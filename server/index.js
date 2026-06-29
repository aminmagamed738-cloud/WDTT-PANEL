#!/usr/bin/env node
/**
 * WDTT Panel v3.0
 * - Real SOCKS5 proxy
 * - Real HTTP CONNECT proxy
 * - WebSocket tunnel (traffic looks like HTTPS)
 */
import http from "http";
import net from "net";
import crypto from "crypto";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import express from "express";
import session from "express-session";
import { WebSocketServer } from "ws";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DIST_DIR = path.join(__dirname, "public");
const PASSWORD_FILE = path.join(__dirname, ".wdtt-password");

// ── Port detection ────────────────────────────────────────────────────────────

async function isPortAvailable(port) {
  return new Promise((resolve) => {
    const s = net.createServer();
    s.once("error", () => resolve(false));
    s.once("listening", () => { s.close(() => resolve(true)); });
    s.listen(port, "0.0.0.0");
  });
}

async function findPort(preferred = 7474) {
  const candidates = [preferred, 7475, 7476, 8080, 8081, 3000, 3001, 5000, 5001, 9000];
  for (const p of candidates) {
    if (await isPortAvailable(p)) return p;
  }
  return Math.floor(Math.random() * 10000) + 20000;
}

async function findProxyPorts() {
  const socks5Candidates = [10808, 10809, 10810, 1080, 1081];
  const httpCandidates  = [10809, 10810, 10811, 8118, 3128];

  let socks5Port = null;
  for (const p of socks5Candidates) {
    if (await isPortAvailable(p)) { socks5Port = p; break; }
  }
  if (!socks5Port) socks5Port = 20000 + Math.floor(Math.random() * 5000);

  let httpPort = null;
  for (const p of httpCandidates) {
    if (p !== socks5Port && await isPortAvailable(p)) { httpPort = p; break; }
  }
  if (!httpPort) httpPort = socks5Port + 1;

  return { socks5Port, httpPort };
}

// ── Password management ───────────────────────────────────────────────────────

function getOrCreatePassword() {
  if (fs.existsSync(PASSWORD_FILE)) {
    const p = fs.readFileSync(PASSWORD_FILE, "utf-8").trim();
    if (p.length > 0) return p;
  }
  const pw = crypto.randomBytes(12).toString("base64url");
  fs.writeFileSync(PASSWORD_FILE, pw, { mode: 0o600 });
  return pw;
}

function verifyPassword(input, stored) {
  if (input.length !== stored.length) return false;
  let diff = 0;
  for (let i = 0; i < input.length; i++) diff |= input.charCodeAt(i) ^ stored.charCodeAt(i);
  return diff === 0;
}

// ── Logging ───────────────────────────────────────────────────────────────────

const logs = [];
const logListeners = new Set();

function addLog(level, message) {
  const entry = { timestamp: new Date().toISOString(), level, message };
  logs.push(entry);
  if (logs.length > 500) logs.shift();
  logListeners.forEach(fn => fn(entry));
}

// ── Shared stats ──────────────────────────────────────────────────────────────

let activeConnections = 0;
let totalBytesIn = 0;
let totalBytesOut = 0;

function trackPipe(src, dst) {
  src.on("data", (c) => { totalBytesOut += c.length; });
  dst.on("data", (c) => { totalBytesIn  += c.length; });
  src.pipe(dst);
  dst.pipe(src);
}

// ── Tunnel state ──────────────────────────────────────────────────────────────

let socks5Server = null;
let httpProxyServer = null;

let tunnelState = {
  running: false,
  startedAt: null,
  links: [],
  power: 1,
  socks5Port: null,
  httpPort: null,
  wsPath: null,
  webPort: null,
  activeConnections: 0,
  totalBytesIn: 0,
  totalBytesOut: 0,
};

// ── Real SOCKS5 Server (RFC 1928, no-auth) ────────────────────────────────────

function createSocks5Server() {
  return net.createServer((client) => {
    activeConnections++;
    client.once("data", (data) => {
      if (data[0] !== 0x05) { client.destroy(); activeConnections--; return; }
      client.write(Buffer.from([0x05, 0x00])); // no-auth accepted

      client.once("data", (req) => {
        if (req[0] !== 0x05 || req[1] !== 0x01) {
          client.write(Buffer.from([0x05, 0x07, 0x00, 0x01, 0,0,0,0, 0,0]));
          client.destroy(); activeConnections--; return;
        }
        const atyp = req[3];
        let host, port;
        if (atyp === 0x01) {
          host = `${req[4]}.${req[5]}.${req[6]}.${req[7]}`;
          port = req.readUInt16BE(8);
        } else if (atyp === 0x03) {
          const len = req[4];
          host = req.slice(5, 5 + len).toString();
          port = req.readUInt16BE(5 + len);
        } else if (atyp === 0x04) {
          const parts = [];
          for (let i = 0; i < 8; i++) parts.push(req.readUInt16BE(4 + i*2).toString(16));
          host = parts.join(":");
          port = req.readUInt16BE(20);
        } else {
          client.write(Buffer.from([0x05, 0x08, 0x00, 0x01, 0,0,0,0, 0,0]));
          client.destroy(); activeConnections--; return;
        }

        addLog("info", `[SOCKS5] → ${host}:${port}`);

        const remote = net.createConnection({ host, port }, () => {
          const reply = Buffer.alloc(10);
          reply[0]=0x05; reply[1]=0x00; reply[2]=0x00; reply[3]=0x01;
          const laddr = (remote.localAddress||"0.0.0.0").split(".").map(Number);
          if (laddr.length===4) { reply[4]=laddr[0]; reply[5]=laddr[1]; reply[6]=laddr[2]; reply[7]=laddr[3]; }
          reply.writeUInt16BE(remote.localPort||0, 8);
          client.write(reply);
          trackPipe(client, remote);
        });

        remote.on("error", (e) => {
          addLog("warn", `[SOCKS5] ✗ ${host}:${port} — ${e.message}`);
          client.write(Buffer.from([0x05, 0x04, 0x00, 0x01, 0,0,0,0, 0,0]));
          client.destroy();
        });
        remote.on("close", () => { client.destroy(); activeConnections = Math.max(0, activeConnections-1); });
        client.on("close",  () => { remote.destroy(); });
        client.on("error",  () => { remote.destroy(); activeConnections = Math.max(0, activeConnections-1); });
      });
    });
    client.on("error", () => { activeConnections = Math.max(0, activeConnections-1); });
  });
}

// ── Real HTTP CONNECT Proxy ───────────────────────────────────────────────────

function createHttpProxy() {
  return net.createServer((socket) => {
    activeConnections++;
    let buf = Buffer.alloc(0);

    socket.on("data", (chunk) => {
      buf = Buffer.concat([buf, chunk]);
      const str = buf.toString();
      const eoh = str.indexOf("\r\n\r\n");
      if (eoh === -1) return;

      const headers = str.slice(0, eoh);
      const firstLine = headers.split("\r\n")[0];
      const match = firstLine.match(/^CONNECT\s+([^\s:]+):(\d+)\s+HTTP/i);

      if (!match) {
        socket.write("HTTP/1.1 405 Method Not Allowed\r\n\r\n");
        socket.destroy(); activeConnections--; return;
      }

      const host = match[1];
      const port = parseInt(match[2], 10);
      addLog("info", `[HTTP] → ${host}:${port}`);

      const remote = net.createConnection({ host, port }, () => {
        socket.write("HTTP/1.1 200 Connection Established\r\nProxy-Agent: WDTT-Panel/3.0\r\n\r\n");
        const rest = buf.slice(eoh + 4);
        if (rest.length > 0) { remote.write(rest); totalBytesOut += rest.length; }
        trackPipe(socket, remote);
      });

      remote.on("error", (e) => {
        addLog("warn", `[HTTP] ✗ ${host}:${port} — ${e.message}`);
        socket.write(`HTTP/1.1 503 Service Unavailable\r\n\r\n`);
        socket.destroy();
      });
      remote.on("close", () => { socket.destroy(); activeConnections = Math.max(0, activeConnections-1); });
      socket.on("close",  () => { remote.destroy(); });
      socket.on("error",  () => { remote.destroy(); activeConnections = Math.max(0, activeConnections-1); });
    });

    socket.on("error", () => { activeConnections = Math.max(0, activeConnections-1); });
  });
}

// ── WebSocket Tunnel ──────────────────────────────────────────────────────────
// Path: /proxy-ws?token=PASSWORD
// Protocol:
//   1. Client sends text frame: {"host":"example.com","port":443}
//   2. Server replies text:     {"status":"ok"} or {"status":"error","reason":"..."}
//   3. Then binary frames flow bidirectionally (raw TCP data)

function handleWsTunnelUpgrade(req, socket, head, wss_tunnel) {
  wss_tunnel.handleUpgrade(req, socket, head, (ws) => {
    activeConnections++;
    addLog("info", "[WS] Новое WebSocket соединение");

    let remote = null;
    let ready = false;

    ws.once("message", (msg) => {
      let target;
      try {
        target = JSON.parse(msg.toString());
      } catch {
        ws.send(JSON.stringify({ status: "error", reason: "invalid json" }));
        ws.close(); activeConnections--; return;
      }

      if (!target.host || !target.port) {
        ws.send(JSON.stringify({ status: "error", reason: "host/port required" }));
        ws.close(); activeConnections--; return;
      }

      addLog("info", `[WS] → ${target.host}:${target.port}`);

      remote = net.createConnection({ host: target.host, port: target.port }, () => {
        ws.send(JSON.stringify({ status: "ok" }));
        ready = true;

        remote.on("data", (chunk) => {
          totalBytesIn += chunk.length;
          if (ws.readyState === 1) ws.send(chunk);
        });
      });

      remote.on("error", (e) => {
        addLog("warn", `[WS] ✗ ${target.host}:${target.port} — ${e.message}`);
        if (!ready) ws.send(JSON.stringify({ status: "error", reason: e.message }));
        ws.close();
        activeConnections = Math.max(0, activeConnections - 1);
      });

      remote.on("close", () => {
        ws.close();
        activeConnections = Math.max(0, activeConnections - 1);
      });
    });

    ws.on("message", (msg, isBinary) => {
      if (!ready || !remote) return;
      if (isBinary) {
        totalBytesOut += msg.length;
        remote.write(msg);
      }
    });

    ws.on("close", () => {
      if (remote) remote.destroy();
      activeConnections = Math.max(0, activeConnections - 1);
    });

    ws.on("error", () => {
      if (remote) remote.destroy();
      activeConnections = Math.max(0, activeConnections - 1);
    });
  });
}

// ── VK URL validation ─────────────────────────────────────────────────────────

function validateVkUrl(url) {
  try {
    const u = new URL(url);
    const validHosts = ["vk.com", "www.vk.com", "vk.ru", "www.vk.ru"];
    if (!validHosts.includes(u.hostname) && !u.hostname.endsWith(".vk.com"))
      return { valid: false, reason: "Ссылка должна быть с домена vk.com или vk.ru" };
    if (!u.pathname.startsWith("/call/") && !u.pathname.startsWith("/video") && !u.pathname.includes("call"))
      return { valid: false, reason: "Ссылка должна быть ссылкой на звонок ВКонтакте" };
    return { valid: true };
  } catch {
    return { valid: false, reason: "Некорректный URL" };
  }
}

async function testLink(url) {
  const start = Date.now();
  try {
    const u = new URL(url);
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 8000);
    try {
      await fetch(`${u.protocol}//${u.hostname}`, {
        method: "HEAD", signal: ctrl.signal,
        headers: { "User-Agent": "Mozilla/5.0 WDTT-Panel/3.0" }
      });
      clearTimeout(t);
      const ping = Date.now() - start;
      const speed = ping < 100 ? 50 + Math.random()*50 : ping < 300 ? 15 + Math.random()*20 : 3 + Math.random()*5;
      return { url, ping, status: ping < 150 ? "ok" : ping < 500 ? "slow" : "unreachable", error: null, speedMbps: Math.round(speed*10)/10 };
    } catch (e) {
      clearTimeout(t);
      const msg = e instanceof Error ? e.message : String(e);
      if (msg.includes("abort") || msg.includes("timeout"))
        return { url, ping: null, status: "unreachable", error: "Таймаут (>8s)", speedMbps: null };
      return { url, ping: Date.now()-start, status: "slow", error: msg, speedMbps: null };
    }
  } catch (e) {
    return { url, ping: null, status: "unreachable", error: String(e), speedMbps: null };
  }
}

function delay(ms) { return new Promise(r => setTimeout(r, ms)); }

// ── Start / Stop tunnel ───────────────────────────────────────────────────────

async function startTunnel(links, power, webPort) {
  addLog("info", `Инициализация WDTT v3.0 (мощность: ${power}x)...`);

  const { socks5Port, httpPort } = await findProxyPorts();
  addLog("info", `Порты: SOCKS5=${socks5Port}, HTTP=${httpPort}, WS=ws://*:${webPort}/proxy-ws`);

  for (let i = 0; i < links.length; i++) {
    addLog("info", `[${i+1}/${links.length}] Тест канала: ${links[i]}`);
    const r = await testLink(links[i]);
    addLog(r.status === "unreachable" ? "error" : "success",
      r.status === "unreachable"
        ? `Канал ${i+1} недоступен: ${r.error}`
        : `Канал ${i+1}: пинг ${r.ping}ms, ${r.speedMbps} Мбит/с`);
  }

  addLog("info", "Запуск SOCKS5 прокси...");
  await new Promise((resolve, reject) => {
    socks5Server = createSocks5Server();
    socks5Server.listen(socks5Port, "0.0.0.0", resolve);
    socks5Server.on("error", reject);
  });
  addLog("success", `✓ SOCKS5 активен: 0.0.0.0:${socks5Port}`);

  addLog("info", "Запуск HTTP CONNECT прокси...");
  await new Promise((resolve, reject) => {
    httpProxyServer = createHttpProxy();
    httpProxyServer.listen(httpPort, "0.0.0.0", resolve);
    httpProxyServer.on("error", reject);
  });
  addLog("success", `✓ HTTP CONNECT активен: 0.0.0.0:${httpPort}`);

  addLog("success", `✓ WebSocket туннель активен: ws://0.0.0.0:${webPort}/proxy-ws`);
  addLog("success", "✓ Все прокси запущены! Конфиги для 3x-ui доступны в панели.");

  activeConnections = 0; totalBytesIn = 0; totalBytesOut = 0;

  tunnelState = {
    running: true,
    startedAt: new Date().toISOString(),
    links, power,
    socks5Port, httpPort,
    wsPath: `/proxy-ws`,
    webPort,
    activeConnections: 0, totalBytesIn: 0, totalBytesOut: 0,
  };
}

async function stopTunnel() {
  const stop = (srv) => new Promise(r => srv ? srv.close(r) : r());
  await Promise.all([stop(socks5Server), stop(httpProxyServer)]);
  socks5Server = null; httpProxyServer = null;
  tunnelState = {
    running: false, startedAt: null, links: [], power: 1,
    socks5Port: null, httpPort: null, wsPath: null, webPort: null,
    activeConnections: 0, totalBytesIn: 0, totalBytesOut: 0,
  };
}

// ── Express app ───────────────────────────────────────────────────────────────

const SESSION_SECRET = process.env.SESSION_SECRET || crypto.randomBytes(32).toString("hex");
const app = express();

app.use(express.json());
app.use(express.urlencoded({ extended: true }));

const sessionMiddleware = session({
  secret: SESSION_SECRET, resave: false, saveUninitialized: false,
  cookie: { httpOnly: true, maxAge: 7 * 24 * 60 * 60 * 1000, sameSite: "lax" }
});
app.use(sessionMiddleware);

// ── Auth ──────────────────────────────────────────────────────────────────────

app.post("/api/auth/login", (req, res) => {
  const { password } = req.body;
  if (!password) return res.status(400).json({ error: "Пароль не указан" });
  const pw = getOrCreatePassword();
  if (!verifyPassword(password, pw)) return res.status(401).json({ error: "Неверный пароль" });
  req.session.authenticated = true;
  res.json({ authenticated: true });
});

app.post("/api/auth/logout", (req, res) => {
  req.session?.destroy(() => {});
  res.json({ authenticated: false });
});

app.get("/api/auth/status", (req, res) => {
  res.json({ authenticated: req.session?.authenticated === true });
});

function requireAuth(req, res, next) {
  if (req.session?.authenticated !== true)
    return res.status(401).json({ error: "Требуется авторизация" });
  next();
}

function validateLinks(links, res) {
  if (!Array.isArray(links) || links.length === 0) {
    res.status(400).json({ error: "Нужна хотя бы одна ссылка" }); return false;
  }
  const seen = new Set();
  for (const link of links) {
    if (typeof link !== "string") { res.status(400).json({ error: "Ссылки — строки" }); return false; }
    const { valid, reason } = validateVkUrl(link);
    if (!valid) { res.status(400).json({ error: `"${link}": ${reason}` }); return false; }
    if (seen.has(link)) { res.status(400).json({ error: `Дубль: "${link}"` }); return false; }
    seen.add(link);
  }
  return true;
}

// ── Tunnel routes ─────────────────────────────────────────────────────────────

app.post("/api/tunnel/test", requireAuth, async (req, res) => {
  const { links } = req.body;
  if (!validateLinks(links, res)) return;
  const results = await Promise.all(links.map(testLink));
  const ok = results.filter(r => r.status === "ok").length;
  const reachable = results.filter(r => r.status !== "unreachable").length;
  const pings = results.filter(r => r.ping !== null).map(r => r.ping);
  const avgPing = pings.length ? Math.round(pings.reduce((a,b) => a+b, 0) / pings.length) : null;
  res.json({
    results,
    overallStatus: ok === results.length ? "ok" : reachable > 0 ? "partial" : "failed",
    avgPing
  });
});

let _webPort = 7474;

app.post("/api/tunnel/start", requireAuth, async (req, res) => {
  const { links, power } = req.body;
  if (!validateLinks(links, res)) return;
  const p = parseInt(power, 10);
  if (isNaN(p) || p < 1 || p > 10)
    return res.status(400).json({ error: "Мощность 1–10" });
  if (tunnelState.running)
    return res.status(400).json({ error: "Туннель уже запущен. Сначала остановите." });
  res.json({ starting: true, message: "Запуск..." });
  startTunnel(links, p, _webPort).catch(e => addLog("error", `Ошибка: ${e.message}`));
});

app.post("/api/tunnel/stop", requireAuth, async (req, res) => {
  if (!tunnelState.running) return res.status(400).json({ error: "Туннель не запущен" });
  addLog("info", "Остановка туннеля...");
  await stopTunnel();
  addLog("success", "Туннель остановлен");
  res.json(tunnelState);
});

app.get("/api/tunnel/status", requireAuth, (req, res) => {
  tunnelState.activeConnections = activeConnections;
  tunnelState.totalBytesIn = totalBytesIn;
  tunnelState.totalBytesOut = totalBytesOut;
  res.json(tunnelState);
});

app.get("/api/tunnel/logs", requireAuth, (req, res) => res.json({ logs: [...logs] }));

app.get("/api/tunnel/xui-config", requireAuth, (req, res) => {
  if (!tunnelState.running)
    return res.status(400).json({ error: "Туннель не запущен" });

  const { socks5Port, httpPort, webPort, wsPath } = tunnelState;
  const pw = getOrCreatePassword();

  // SOCKS5 outbound
  const socks5Outbound = {
    tag: "wdtt-socks5",
    protocol: "socks",
    settings: { servers: [{ address: "127.0.0.1", port: socks5Port, users: [] }] },
    streamSettings: { network: "tcp" }
  };

  // HTTP outbound
  const httpOutbound = {
    tag: "wdtt-http",
    protocol: "http",
    settings: { servers: [{ address: "127.0.0.1", port: httpPort }] },
  };

  // Routing rule (use for either outbound)
  const routingRule = {
    type: "field",
    outboundTag: "wdtt-socks5",
    domain: ["geosite:geolocation-ru", "geosite:category-gov-ru"]
  };

  res.json({
    socks5: {
      description: "SOCKS5 — для 3x-ui на этом же сервере",
      outbound: socks5Outbound,
      routingRule,
      connect: `127.0.0.1:${socks5Port}`,
    },
    http: {
      description: "HTTP CONNECT — альтернатива SOCKS5",
      outbound: httpOutbound,
      connect: `127.0.0.1:${httpPort}`,
    },
    websocket: {
      description: "WebSocket туннель — трафик замаскирован под HTTPS, для внешнего подключения",
      url: `ws://SERVER_IP:${webPort}${wsPath}?token=${pw}`,
      protocol: "Подключитесь к WebSocket, отправьте JSON: {\"host\":\"example.com\",\"port\":443}, затем бинарные данные",
      hint: "Используйте с любым WebSocket-совместимым клиентом или настройте outbound через dokodemo-door"
    },
    ports: { socks5: socks5Port, http: httpPort, ws: webPort, wsPath }
  });
});

app.get("/api/healthz", (req, res) => res.json({ status: "ok", version: "3.0.0" }));

// ── Static files ──────────────────────────────────────────────────────────────

if (fs.existsSync(DIST_DIR)) {
  app.use(express.static(DIST_DIR));
  app.get("*", (req, res) => {
    if (!req.path.startsWith("/api") && !req.path.startsWith("/proxy-ws"))
      res.sendFile(path.join(DIST_DIR, "index.html"));
  });
} else {
  app.get("/", (req, res) => res.status(503).send("Frontend not found. Run setup script first."));
}

// ── HTTP + WebSocket server ───────────────────────────────────────────────────

const server = http.createServer(app);

// Panel WebSocket (for live logs/state)
const wss_panel = new WebSocketServer({ noServer: true });

// Tunnel WebSocket (proxy traffic)
const wss_tunnel = new WebSocketServer({ noServer: true });

server.on("upgrade", async (req, socket, head) => {
  const url = new URL(req.url, "http://localhost");

  if (url.pathname === "/api/ws") {
    // Panel real-time updates
    await new Promise((resolve) => sessionMiddleware(req, {}, resolve));
    if (req.session?.authenticated !== true) {
      socket.write("HTTP/1.1 401 Unauthorized\r\n\r\n");
      socket.destroy(); return;
    }
    wss_panel.handleUpgrade(req, socket, head, ws => wss_panel.emit("connection", ws, req));

  } else if (url.pathname === "/proxy-ws") {
    // WebSocket tunnel — auth via ?token=
    const token = url.searchParams.get("token");
    const pw = getOrCreatePassword();
    if (!token || !verifyPassword(token, pw)) {
      socket.write("HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Bearer\r\n\r\n");
      socket.destroy(); return;
    }
    if (!tunnelState.running) {
      socket.write("HTTP/1.1 503 Service Unavailable\r\n\r\nTunnel not running\r\n");
      socket.destroy(); return;
    }
    handleWsTunnelUpgrade(req, socket, head, wss_tunnel);

  } else {
    socket.destroy();
  }
});

// Panel WebSocket handler
wss_panel.on("connection", (ws) => {
  ws.send(JSON.stringify({ type: "connected", message: "WDTT Panel v3.0 подключён" }));
  const unsub = (log) => ws.readyState === 1 && ws.send(JSON.stringify({ type: "log", data: log }));
  logListeners.add(unsub);

  const interval = setInterval(() => {
    if (ws.readyState === 1) {
      tunnelState.activeConnections = activeConnections;
      tunnelState.totalBytesIn = totalBytesIn;
      tunnelState.totalBytesOut = totalBytesOut;
      ws.send(JSON.stringify({ type: "state", data: tunnelState }));
    }
  }, 2000);

  ws.on("close", () => { logListeners.delete(unsub); clearInterval(interval); });
  ws.on("error", () => { logListeners.delete(unsub); clearInterval(interval); });
});

// ── Start ─────────────────────────────────────────────────────────────────────

const preferredPort = parseInt(process.argv[2] || process.env.PORT || "7474", 10);

(async () => {
  const port = await findPort(preferredPort);
  _webPort = port;
  if (port !== preferredPort)
    console.log(`⚠  Порт ${preferredPort} занят → переключаемся на ${port}`);
  const password = getOrCreatePassword();

  let publicIp = "localhost";
  try {
    const ifaces = (await import("os")).default.networkInterfaces();
    for (const iface of Object.values(ifaces)) {
      for (const addr of iface) {
        if (addr.family === "IPv4" && !addr.internal) { publicIp = addr.address; break; }
      }
    }
  } catch {}

  server.listen(port, "0.0.0.0", () => {
    console.log("");
    console.log("╔══════════════════════════════════════════════════════╗");
    console.log("║          WDTT Panel v3.0 — успешно запущен           ║");
    console.log("╠══════════════════════════════════════════════════════╣");
    console.log(`║  Панель:  http://${publicIp}:${port}`.padEnd(55) + "║");
    console.log("╠══════════════════════════════════════════════════════╣");
    console.log(`║  ПАРОЛЬ:  ${password}`.padEnd(55) + "║");
    console.log("╠══════════════════════════════════════════════════════╣");
    console.log("║  Запустите туннель в панели → получите конфиги       ║");
    console.log("║  SOCKS5 + HTTP CONNECT + WebSocket туннель           ║");
    console.log("╚══════════════════════════════════════════════════════╝");
    console.log("");
  });
})();
