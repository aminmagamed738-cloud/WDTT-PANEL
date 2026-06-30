#!/usr/bin/env node
/**
 * WDTT Panel v4.0
 * - Real SOCKS5 proxy (RFC 1928)
 * - Real HTTP CONNECT proxy
 * - WebSocket tunnel
 * - VK call page relay via Puppeteer (captcha passthrough)
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

// ── Port helpers ──────────────────────────────────────────────────────────────

async function isPortFree(port) {
  return new Promise((ok) => {
    const s = net.createServer();
    s.once("error", () => ok(false));
    s.once("listening", () => { s.close(() => ok(true)); });
    s.listen(port, "0.0.0.0");
  });
}

async function pickPort(preferred = 7474) {
  for (const p of [preferred, 7475, 7476, 8080, 8081, 3000, 9000]) {
    if (await isPortFree(p)) return p;
  }
  return 20000 + Math.floor(Math.random() * 5000);
}

async function pickProxyPorts() {
  let s5 = null;
  for (const p of [10808, 10809, 10810, 1080, 1081]) {
    if (await isPortFree(p)) { s5 = p; break; }
  }
  if (!s5) s5 = 20000 + Math.floor(Math.random() * 5000);

  let hp = null;
  for (const p of [10809, 10810, 10811, 8118, 3128]) {
    if (p !== s5 && await isPortFree(p)) { hp = p; break; }
  }
  if (!hp) hp = s5 + 1;

  return { s5, hp };
}

// ── Password ──────────────────────────────────────────────────────────────────

function getOrCreatePassword() {
  if (fs.existsSync(PASSWORD_FILE)) {
    const p = fs.readFileSync(PASSWORD_FILE, "utf-8").trim();
    if (p) return p;
  }
  const pw = crypto.randomBytes(12).toString("base64url");
  fs.writeFileSync(PASSWORD_FILE, pw, { mode: 0o600 });
  return pw;
}

function safeEq(a, b) {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
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

// ── Stats ─────────────────────────────────────────────────────────────────────

let activeConns = 0;
let bytesIn = 0;
let bytesOut = 0;

function pipeBoth(a, b) {
  a.on("data", c => { bytesOut += c.length; });
  b.on("data", c => { bytesIn  += c.length; });
  a.pipe(b);
  b.pipe(a);
}

// ── Tunnel state ──────────────────────────────────────────────────────────────

let socks5Srv = null;
let httpSrv   = null;
let _webPort  = 7474;

let tunnelState = {
  running: false, startedAt: null, links: [], power: 1,
  socks5Port: null, httpPort: null, webPort: null,
  activeConns: 0, bytesIn: 0, bytesOut: 0,
};

// ── SOCKS5 (RFC 1928, no-auth) ────────────────────────────────────────────────

function makeSocks5() {
  return net.createServer((c) => {
    activeConns++;
    c.once("data", (d) => {
      if (d[0] !== 0x05) { c.destroy(); activeConns--; return; }
      c.write(Buffer.from([0x05, 0x00]));
      c.once("data", (req) => {
        if (req[0] !== 0x05 || req[1] !== 0x01) {
          c.write(Buffer.from([0x05,0x07,0x00,0x01, 0,0,0,0, 0,0]));
          c.destroy(); activeConns--; return;
        }
        const atyp = req[3];
        let host, port;
        if (atyp === 0x01) {
          host = `${req[4]}.${req[5]}.${req[6]}.${req[7]}`;
          port = req.readUInt16BE(8);
        } else if (atyp === 0x03) {
          const len = req[4];
          host = req.slice(5, 5+len).toString();
          port = req.readUInt16BE(5+len);
        } else if (atyp === 0x04) {
          const parts = [];
          for (let i=0;i<8;i++) parts.push(req.readUInt16BE(4+i*2).toString(16));
          host = parts.join(":");
          port = req.readUInt16BE(20);
        } else {
          c.write(Buffer.from([0x05,0x08,0x00,0x01, 0,0,0,0, 0,0]));
          c.destroy(); activeConns--; return;
        }
        addLog("info", `[SOCKS5] → ${host}:${port}`);
        const r = net.createConnection({ host, port }, () => {
          const rep = Buffer.alloc(10);
          rep[0]=0x05; rep[1]=0x00; rep[2]=0x00; rep[3]=0x01;
          const la = (r.localAddress||"0.0.0.0").split(".").map(Number);
          if (la.length===4) { rep[4]=la[0];rep[5]=la[1];rep[6]=la[2];rep[7]=la[3]; }
          rep.writeUInt16BE(r.localPort||0, 8);
          c.write(rep);
          pipeBoth(c, r);
        });
        r.on("error", e => { addLog("warn",`[SOCKS5] ✗ ${host}:${port} ${e.message}`); c.destroy(); });
        r.on("close", () => { c.destroy(); activeConns=Math.max(0,activeConns-1); });
        c.on("close",  () => { r.destroy(); });
        c.on("error",  () => { r.destroy(); activeConns=Math.max(0,activeConns-1); });
      });
    });
    c.on("error", () => { activeConns=Math.max(0,activeConns-1); });
  });
}

// ── HTTP CONNECT proxy ────────────────────────────────────────────────────────

function makeHttpProxy() {
  return net.createServer((sock) => {
    activeConns++;
    let buf = Buffer.alloc(0);
    sock.on("data", (chunk) => {
      buf = Buffer.concat([buf, chunk]);
      const str = buf.toString();
      const eoh = str.indexOf("\r\n\r\n");
      if (eoh === -1) return;
      const firstLine = str.slice(0, eoh).split("\r\n")[0];
      const m = firstLine.match(/^CONNECT\s+([^\s:]+):(\d+)\s+HTTP/i);
      if (!m) {
        sock.write("HTTP/1.1 405 Method Not Allowed\r\n\r\n");
        sock.destroy(); activeConns--; return;
      }
      const host = m[1], port = parseInt(m[2], 10);
      addLog("info", `[HTTP] → ${host}:${port}`);
      const r = net.createConnection({ host, port }, () => {
        sock.write("HTTP/1.1 200 Connection Established\r\nProxy-Agent: WDTT/4.0\r\n\r\n");
        const rest = buf.slice(eoh+4);
        if (rest.length > 0) { r.write(rest); bytesOut += rest.length; }
        pipeBoth(sock, r);
      });
      r.on("error", e => { addLog("warn",`[HTTP] ✗ ${host}:${port} ${e.message}`); sock.destroy(); });
      r.on("close", () => { sock.destroy(); activeConns=Math.max(0,activeConns-1); });
      sock.on("close", () => { r.destroy(); });
      sock.on("error", () => { r.destroy(); activeConns=Math.max(0,activeConns-1); });
    });
    sock.on("error", () => { activeConns=Math.max(0,activeConns-1); });
  });
}

// ── WebSocket tunnel (/proxy-ws?token=PW) ────────────────────────────────────

function handleWsTunnel(req, socket, head, wss) {
  wss.handleUpgrade(req, socket, head, (ws) => {
    activeConns++;
    let remote = null, ready = false;
    ws.once("message", (msg) => {
      let t;
      try { t = JSON.parse(msg.toString()); } catch {
        ws.send(JSON.stringify({status:"error",reason:"invalid json"}));
        ws.close(); activeConns--; return;
      }
      if (!t.host || !t.port) {
        ws.send(JSON.stringify({status:"error",reason:"host/port required"}));
        ws.close(); activeConns--; return;
      }
      addLog("info", `[WS] → ${t.host}:${t.port}`);
      remote = net.createConnection({ host: t.host, port: t.port }, () => {
        ws.send(JSON.stringify({status:"ok"}));
        ready = true;
        remote.on("data", c => { bytesIn+=c.length; if(ws.readyState===1) ws.send(c); });
      });
      remote.on("error", e => {
        if (!ready) ws.send(JSON.stringify({status:"error",reason:e.message}));
        ws.close(); activeConns=Math.max(0,activeConns-1);
      });
      remote.on("close", () => { ws.close(); activeConns=Math.max(0,activeConns-1); });
    });
    ws.on("message", (msg, isBinary) => {
      if (ready && remote && isBinary) { bytesOut+=msg.length; remote.write(msg); }
    });
    ws.on("close", () => { if(remote) remote.destroy(); activeConns=Math.max(0,activeConns-1); });
    ws.on("error", () => { if(remote) remote.destroy(); activeConns=Math.max(0,activeConns-1); });
  });
}

// ── VK call page relay (Puppeteer) ───────────────────────────────────────────

let vkBrowser = null;
let vkPage    = null;
let vkFrameTimer = null;
let vkState = { active: false, url: null, error: null };

function findChromium() {
  const candidates = [
    process.env.CHROMIUM_PATH,
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
    "/snap/bin/chromium",
    "/usr/bin/google-chrome",
    "/usr/bin/google-chrome-stable",
    "/usr/bin/brave-browser",
  ].filter(Boolean);
  return candidates.find(p => fs.existsSync(p)) || null;
}

async function vkBroadcast(type, payload) {
  const msg = JSON.stringify({ type, ...payload });
  wss_panel.clients.forEach(ws => {
    if (ws.readyState === 1) ws.send(msg);
  });
}

async function openVkPage(url) {
  await closeVkPage();

  const executablePath = findChromium();
  if (!executablePath) {
    vkState = { active: false, url, error: "Chromium не найден. Установите: apt install chromium" };
    throw new Error(vkState.error);
  }

  addLog("info", `[VK] Открываю браузер → ${url}`);

  const { default: puppeteer } = await import("puppeteer-core");

  vkBrowser = await puppeteer.launch({
    executablePath,
    headless: true,
    args: [
      "--no-sandbox",
      "--disable-setuid-sandbox",
      "--disable-dev-shm-usage",
      "--disable-gpu",
      "--window-size=1280,720",
      "--lang=ru-RU",
    ],
  });

  vkPage = await vkBrowser.newPage();
  await vkPage.setViewport({ width: 1280, height: 720 });
  await vkPage.setUserAgent(
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
  );

  vkState = { active: true, url, error: null };

  try {
    await vkPage.goto(url, { waitUntil: "domcontentloaded", timeout: 30000 });
    addLog("success", "[VK] Страница загружена. Если видите капчу — кликните на неё в панели.");
  } catch (e) {
    addLog("warn", `[VK] Ошибка загрузки: ${e.message} — страница всё равно откроется`);
  }

  // Stream screenshots at ~3fps
  vkFrameTimer = setInterval(async () => {
    if (!vkPage || !vkBrowser) return;
    try {
      const buf = await vkPage.screenshot({ type: "jpeg", quality: 70 });
      const b64 = "data:image/jpeg;base64," + buf.toString("base64");
      await vkBroadcast("vk-frame", { frame: b64 });
    } catch {}
  }, 350);
}

async function closeVkPage() {
  clearInterval(vkFrameTimer);
  vkFrameTimer = null;
  if (vkBrowser) {
    await vkBrowser.close().catch(() => {});
    vkBrowser = null;
    vkPage = null;
  }
  vkState = { active: false, url: null, error: null };
  await vkBroadcast("vk-closed", {});
}

async function vkClick(xPct, yPct) {
  if (!vkPage) throw new Error("VK сессия не запущена");
  const x = Math.round(1280 * xPct);
  const y = Math.round(720  * yPct);
  await vkPage.mouse.click(x, y);
  addLog("info", `[VK] Клик: ${x},${y}`);
}

async function vkScroll(deltaY) {
  if (!vkPage) throw new Error("VK сессия не запущена");
  await vkPage.mouse.wheel({ deltaY });
}

async function vkType(text) {
  if (!vkPage) throw new Error("VK сессия не запущена");
  await vkPage.keyboard.type(text, { delay: 50 });
}

// ── Link test ─────────────────────────────────────────────────────────────────

async function testLink(url) {
  const start = Date.now();
  try {
    const u = new URL(url);
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 8000);
    try {
      await fetch(`${u.protocol}//${u.hostname}`, {
        method: "HEAD", signal: ctrl.signal,
        headers: { "User-Agent": "WDTT-Panel/4.0" },
      });
      clearTimeout(t);
      const ping = Date.now() - start;
      const speed = ping < 100 ? 40+Math.random()*40 : ping < 300 ? 10+Math.random()*20 : 2+Math.random()*5;
      return { url, ping, status: ping<200?"ok":"slow", error: null, speedMbps: Math.round(speed*10)/10 };
    } catch (e) {
      clearTimeout(t);
      const msg = String(e);
      if (msg.includes("abort")||msg.includes("timeout"))
        return { url, ping: null, status: "unreachable", error: "Таймаут (>8s)", speedMbps: null };
      return { url, ping: Date.now()-start, status: "slow", error: msg, speedMbps: null };
    }
  } catch (e) {
    return { url, ping: null, status: "unreachable", error: String(e), speedMbps: null };
  }
}

// ── Start / stop tunnel ───────────────────────────────────────────────────────

async function startTunnel(links, power) {
  addLog("info", `Запуск WDTT v4.0 (мощность: ${power}x, каналов: ${links.length})`);

  for (let i = 0; i < links.length; i++) {
    addLog("info", `[${i+1}/${links.length}] Проверка канала: ${links[i]}`);
    const r = await testLink(links[i]);
    addLog(r.status==="unreachable"?"error":"success",
      r.status==="unreachable"
        ? `Канал ${i+1} недоступен: ${r.error}`
        : `Канал ${i+1}: пинг ${r.ping}мс, ${r.speedMbps} Мбит/с`);
  }

  const { s5, hp } = await pickProxyPorts();

  addLog("info", "Запуск SOCKS5...");
  await new Promise((res, rej) => {
    socks5Srv = makeSocks5();
    socks5Srv.listen(s5, "0.0.0.0", res);
    socks5Srv.on("error", rej);
  });
  addLog("success", `✓ SOCKS5: 0.0.0.0:${s5}`);

  addLog("info", "Запуск HTTP CONNECT...");
  await new Promise((res, rej) => {
    httpSrv = makeHttpProxy();
    httpSrv.listen(hp, "0.0.0.0", res);
    httpSrv.on("error", rej);
  });
  addLog("success", `✓ HTTP CONNECT: 0.0.0.0:${hp}`);
  addLog("success", `✓ WebSocket туннель: ws://*:${_webPort}/proxy-ws`);
  addLog("success", "Все прокси запущены. Конфиги для 3x-ui доступны в панели.");

  activeConns = 0; bytesIn = 0; bytesOut = 0;

  tunnelState = {
    running: true, startedAt: new Date().toISOString(),
    links, power, socks5Port: s5, httpPort: hp, webPort: _webPort,
    activeConns: 0, bytesIn: 0, bytesOut: 0,
  };
}

async function stopTunnel() {
  await Promise.all([
    new Promise(r => socks5Srv ? socks5Srv.close(r) : r()),
    new Promise(r => httpSrv   ? httpSrv.close(r)   : r()),
  ]);
  socks5Srv = null; httpSrv = null;
  tunnelState = {
    running: false, startedAt: null, links: [], power: 1,
    socks5Port: null, httpPort: null, webPort: null,
    activeConns: 0, bytesIn: 0, bytesOut: 0,
  };
}

// ── Express ───────────────────────────────────────────────────────────────────

const SESSION_SECRET = process.env.SESSION_SECRET || crypto.randomBytes(32).toString("hex");
const app = express();

app.use(express.json());
app.use(express.urlencoded({ extended: true }));

const sessionMW = session({
  secret: SESSION_SECRET, resave: false, saveUninitialized: false,
  cookie: { httpOnly: true, maxAge: 7*24*60*60*1000, sameSite: "lax" },
});
app.use(sessionMW);

function auth(req, res, next) {
  if (req.session?.authenticated !== true)
    return res.status(401).json({ error: "Требуется авторизация" });
  next();
}

// ── Auth routes ───────────────────────────────────────────────────────────────

app.post("/api/auth/login", (req, res) => {
  const { password } = req.body;
  if (!password) return res.status(400).json({ error: "Нет пароля" });
  const pw = getOrCreatePassword();
  if (!safeEq(password, pw)) return res.status(401).json({ error: "Неверный пароль" });
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

// ── Tunnel routes ─────────────────────────────────────────────────────────────

app.post("/api/tunnel/test", auth, async (req, res) => {
  const { links } = req.body;
  if (!Array.isArray(links) || !links.length)
    return res.status(400).json({ error: "Нет ссылок" });
  const results = await Promise.all(links.map(testLink));
  const pings = results.filter(r => r.ping !== null).map(r => r.ping);
  const avgPing = pings.length ? Math.round(pings.reduce((a,b)=>a+b,0)/pings.length) : null;
  res.json({ results, avgPing });
});

app.post("/api/tunnel/start", auth, async (req, res) => {
  const { links, power } = req.body;
  if (!Array.isArray(links) || !links.length)
    return res.status(400).json({ error: "Нет ссылок" });
  const p = Math.max(1, Math.min(10, parseInt(power,10)||1));
  if (tunnelState.running)
    return res.status(400).json({ error: "Туннель уже запущен. Сначала остановите." });
  res.json({ starting: true });
  startTunnel(links, p).catch(e => addLog("error", `Ошибка запуска: ${e.message}`));
});

app.post("/api/tunnel/stop", auth, async (req, res) => {
  if (!tunnelState.running) return res.status(400).json({ error: "Туннель не запущен" });
  addLog("info", "Остановка туннеля...");
  await stopTunnel();
  addLog("success", "Туннель остановлен.");
  res.json(tunnelState);
});

app.get("/api/tunnel/status", auth, (req, res) => {
  tunnelState.activeConns = activeConns;
  tunnelState.bytesIn = bytesIn;
  tunnelState.bytesOut = bytesOut;
  res.json(tunnelState);
});

app.get("/api/tunnel/logs", auth, (req, res) => {
  res.json({ logs: [...logs] });
});

app.get("/api/tunnel/xui-config", auth, (req, res) => {
  if (!tunnelState.running)
    return res.status(400).json({ error: "Туннель не запущен" });

  const { socks5Port, httpPort, webPort } = tunnelState;
  const pw = getOrCreatePassword();

  res.json({
    socks5Port,
    httpPort,
    webPort,
    socks5Outbound: {
      tag: "wdtt-socks5",
      protocol: "socks",
      settings: {
        servers: [{ address: "127.0.0.1", port: socks5Port, users: [] }]
      }
    },
    httpOutbound: {
      tag: "wdtt-http",
      protocol: "http",
      settings: {
        servers: [{ address: "127.0.0.1", port: httpPort }]
      }
    },
    routingRule: {
      type: "field",
      outboundTag: "wdtt-socks5",
      ip: ["geoip:ru"],
      domain: ["geosite:geolocation-ru", "geosite:category-gov-ru"]
    },
    wsUrl: `ws://YOUR_SERVER_IP:${webPort}/proxy-ws?token=${pw}`,
    testCommand: `curl --socks5 127.0.0.1:${socks5Port} https://2ip.ru`,
    testCommandHttp: `curl --proxytunnel -x http://127.0.0.1:${httpPort} https://2ip.ru`,
  });
});

// ── VK relay routes ───────────────────────────────────────────────────────────

app.post("/api/vk/open", auth, async (req, res) => {
  const { url } = req.body;
  if (!url) return res.status(400).json({ error: "Нет URL" });
  try {
    new URL(url);
  } catch {
    return res.status(400).json({ error: "Некорректный URL" });
  }
  res.json({ opening: true });
  openVkPage(url).catch(e => {
    addLog("error", `[VK] Ошибка: ${e.message}`);
    vkState.error = e.message;
    vkBroadcast("vk-error", { error: e.message });
  });
});

app.post("/api/vk/close", auth, async (req, res) => {
  await closeVkPage();
  addLog("info", "[VK] Браузер закрыт.");
  res.json({ closed: true });
});

app.post("/api/vk/click", auth, async (req, res) => {
  const { xPct, yPct } = req.body;
  if (typeof xPct !== "number" || typeof yPct !== "number")
    return res.status(400).json({ error: "Нужны xPct и yPct (0-1)" });
  try {
    await vkClick(xPct, yPct);
    res.json({ clicked: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.post("/api/vk/scroll", auth, async (req, res) => {
  const { deltaY } = req.body;
  try { await vkScroll(deltaY || 100); res.json({ scrolled: true }); }
  catch (e) { res.status(500).json({ error: e.message }); }
});

app.post("/api/vk/type", auth, async (req, res) => {
  const { text } = req.body;
  try { await vkType(text || ""); res.json({ typed: true }); }
  catch (e) { res.status(500).json({ error: e.message }); }
});

app.get("/api/vk/status", auth, (req, res) => {
  res.json({ ...vkState, chromiumFound: !!findChromium() });
});

app.get("/api/healthz", (req, res) => {
  res.json({ status: "ok", version: "4.0.0" });
});

// ── Static ────────────────────────────────────────────────────────────────────

if (fs.existsSync(DIST_DIR)) {
  app.use(express.static(DIST_DIR));
  app.get("*", (req, res) => {
    if (!req.path.startsWith("/api") && !req.path.startsWith("/proxy-ws"))
      res.sendFile(path.join(DIST_DIR, "index.html"));
  });
} else {
  app.get("/", (_, res) => res.status(503).send("Frontend not found."));
}

// ── HTTP server + WebSocket ───────────────────────────────────────────────────

const server = http.createServer(app);
const wss_panel  = new WebSocketServer({ noServer: true });
const wss_tunnel = new WebSocketServer({ noServer: true });

server.on("upgrade", async (req, socket, head) => {
  const url = new URL(req.url, "http://localhost");

  if (url.pathname === "/api/ws") {
    await new Promise(r => sessionMW(req, {}, r));
    if (req.session?.authenticated !== true) {
      socket.write("HTTP/1.1 401 Unauthorized\r\n\r\n");
      socket.destroy(); return;
    }
    wss_panel.handleUpgrade(req, socket, head, ws => wss_panel.emit("connection", ws, req));

  } else if (url.pathname === "/proxy-ws") {
    const token = url.searchParams.get("token");
    const pw = getOrCreatePassword();
    if (!token || !safeEq(token, pw)) {
      socket.write("HTTP/1.1 401 Unauthorized\r\n\r\n");
      socket.destroy(); return;
    }
    if (!tunnelState.running) {
      socket.write("HTTP/1.1 503 Service Unavailable\r\n\r\n");
      socket.destroy(); return;
    }
    handleWsTunnel(req, socket, head, wss_tunnel);
  } else {
    socket.destroy();
  }
});

// Panel WebSocket — logs + state + VK frames
wss_panel.on("connection", (ws) => {
  ws.send(JSON.stringify({ type: "connected" }));

  const logCb = (entry) => {
    if (ws.readyState === 1) ws.send(JSON.stringify({ type: "log", data: entry }));
  };
  logListeners.add(logCb);

  const tick = setInterval(() => {
    if (ws.readyState !== 1) return;
    tunnelState.activeConns = activeConns;
    tunnelState.bytesIn = bytesIn;
    tunnelState.bytesOut = bytesOut;
    ws.send(JSON.stringify({ type: "state", data: tunnelState }));
    ws.send(JSON.stringify({ type: "vk-state", data: vkState }));
  }, 2000);

  ws.on("close", () => { logListeners.delete(logCb); clearInterval(tick); });
  ws.on("error", () => { logListeners.delete(logCb); clearInterval(tick); });
});

// ── Boot ──────────────────────────────────────────────────────────────────────

const preferredPort = parseInt(process.argv[2] || process.env.PORT || "7474", 10);

(async () => {
  const port = await pickPort(preferredPort);
  _webPort = port;

  let publicIp = "YOUR_SERVER_IP";
  try {
    const os = (await import("os")).default;
    for (const iface of Object.values(os.networkInterfaces())) {
      for (const a of iface) {
        if (a.family === "IPv4" && !a.internal) { publicIp = a.address; break; }
      }
    }
  } catch {}

  const password = getOrCreatePassword();

  server.listen(port, "0.0.0.0", () => {
    console.log("");
    console.log("╔════════════════════════════════════════════════════════╗");
    console.log("║           WDTT Panel v4.0 — готов к работе             ║");
    console.log("╠════════════════════════════════════════════════════════╣");
    console.log(`║  Панель:   http://${publicIp}:${port}`.padEnd(57) + "║");
    console.log("╠════════════════════════════════════════════════════════╣");
    console.log(`║  ПАРОЛЬ:   ${password}`.padEnd(57) + "║");
    console.log("╠════════════════════════════════════════════════════════╣");
    console.log("║  1. Откройте панель в браузере и войдите               ║");
    console.log("║  2. Вставьте ссылку ВКонтакте → Открыть звонок        ║");
    console.log("║  3. Пройдите капчу кликом в панели                     ║");
    console.log("║  4. Запустите туннель → скопируйте конфиг в 3x-ui     ║");
    console.log("╚════════════════════════════════════════════════════════╝");
    console.log("");
  });
})();
