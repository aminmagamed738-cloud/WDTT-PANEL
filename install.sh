#!/bin/sh
set -e

REPO="aminmagamed738-cloud/WDTT-PANEL"
INSTALL_DIR="/opt/wdtt-panel"
TMP_DIR="/tmp/wdtt-$$"
NODE_MIN=20

echo ""
echo "======================================"
echo "  WDTT Panel - установка"
echo "======================================"
echo ""

# Root check
if [ "$(id -u)" -ne 0 ]; then
  echo "[ERR] Запустите от root"
  exit 1
fi

# Node.js
if ! command -v node >/dev/null 2>&1; then
  echo "[INFO] Устанавливаю Node.js 22..."
  curl -fsSL https://deb.nodesource.com/setup_22.x | sh -
  apt-get install -y nodejs
fi
NODE_VER=$(node -e "process.stdout.write(process.versions.node.split('.')[0])")
if [ "$NODE_VER" -lt "$NODE_MIN" ]; then
  echo "[ERR] Нужен Node.js >= $NODE_MIN (установлен $NODE_VER)"
  exit 1
fi
echo "[OK] Node.js $(node --version)"

# unzip
if ! command -v unzip >/dev/null 2>&1; then
  echo "[INFO] Устанавливаю unzip..."
  apt-get install -y unzip 2>/dev/null || yum install -y unzip 2>/dev/null || true
fi

# Chromium
CHROMIUM_BIN=""
for bin in chromium chromium-browser google-chrome google-chrome-stable; do
  if command -v "$bin" >/dev/null 2>&1; then
    CHROMIUM_BIN=$(command -v "$bin")
    break
  fi
done
if [ -z "$CHROMIUM_BIN" ]; then
  echo "[INFO] Устанавливаю Chromium..."
  apt-get install -y chromium chromium-driver 2>/dev/null \
    || apt-get install -y chromium-browser 2>/dev/null \
    || yum install -y chromium 2>/dev/null || true
  for bin in chromium chromium-browser google-chrome; do
    if command -v "$bin" >/dev/null 2>&1; then
      CHROMIUM_BIN=$(command -v "$bin"); break
    fi
  done
fi
if [ -n "$CHROMIUM_BIN" ]; then
  echo "[OK] Chromium: $CHROMIUM_BIN"
else
  echo "[WARN] Chromium не найден - puppeteer скачает сам"
fi

# Determine source of panel files
# Mode A: script is next to wdtt-panel/ folder (run from extracted ZIP)
# Mode B: piped via curl — download release ZIP from GitHub

mkdir -p "$TMP_DIR"
PANEL_SRC=""

SCRIPT_DIR=""
if [ -n "$0" ] && [ "$0" != "sh" ] && [ "$0" != "/bin/sh" ] && [ "$0" != "bash" ]; then
  SCRIPT_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || true
fi

if [ -n "$SCRIPT_DIR" ] && [ -d "$SCRIPT_DIR/wdtt-panel" ]; then
  echo "[INFO] Использую локальные файлы из $(dirname "$0")"
  PANEL_SRC="$SCRIPT_DIR/wdtt-panel"
  SERVICE_SRC="$SCRIPT_DIR/wdtt-panel.service"
else
  echo "[INFO] Скачиваю релиз с GitHub..."
  DOWNLOAD_URL="https://github.com/${REPO}/releases/latest/download/wdtt-panel-release.zip"
  if ! curl -fsSL -o "$TMP_DIR/release.zip" "$DOWNLOAD_URL"; then
    echo "[ERR] Не удалось скачать релиз: $DOWNLOAD_URL"
    echo "[ERR] Убедитесь что на GitHub создан Release с файлом wdtt-panel-release.zip"
    exit 1
  fi
  echo "[OK] Скачано"
  unzip -q "$TMP_DIR/release.zip" -d "$TMP_DIR/src"
  # Find wdtt-panel dir in extracted content
  for d in \
    "$TMP_DIR/src/wdtt-panel" \
    "$TMP_DIR/src/wdtt-panel-release/wdtt-panel"; do
    if [ -d "$d" ]; then PANEL_SRC="$d"; break; fi
  done
  for f in \
    "$TMP_DIR/src/wdtt-panel.service" \
    "$TMP_DIR/src/wdtt-panel-release/wdtt-panel.service"; do
    if [ -f "$f" ]; then SERVICE_SRC="$f"; break; fi
  done
  if [ -z "$PANEL_SRC" ]; then
    echo "[ERR] Папка wdtt-panel не найдена в архиве"
    exit 1
  fi
fi

# Copy panel files
mkdir -p "$INSTALL_DIR"
cp -r "$PANEL_SRC/." "$INSTALL_DIR/"
echo "[OK] Файлы скопированы в $INSTALL_DIR"

# Write systemd service
if [ -n "$SERVICE_SRC" ] && [ -f "$SERVICE_SRC" ]; then
  cp "$SERVICE_SRC" /etc/systemd/system/wdtt-panel.service
  sed -i "s|/opt/wdtt-panel|$INSTALL_DIR|g" /etc/systemd/system/wdtt-panel.service
else
  cat > /etc/systemd/system/wdtt-panel.service <<EOF
[Unit]
Description=WDTT Panel - VK Tunnel Management
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
EnvironmentFile=${INSTALL_DIR}/.env
ExecStart=/usr/bin/node --enable-source-maps index.mjs
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=wdtt-panel

[Install]
WantedBy=multi-user.target
EOF
fi
echo "[OK] Systemd сервис установлен"

# .env
SESSION_SECRET=$(openssl rand -hex 32 2>/dev/null || od -vAn -N32 -tx1 /dev/urandom | tr -d ' \n')
cat > "$INSTALL_DIR/.env" <<EOF
NODE_ENV=production
PORT=8080
SESSION_SECRET=${SESSION_SECRET}
CHROMIUM_PATH=${CHROMIUM_BIN}
SOCKS5_PORT=10808
HTTP_PORT=10809
EOF
echo "[OK] Создан $INSTALL_DIR/.env"

# Cleanup
rm -rf "$TMP_DIR"

# Start
systemctl daemon-reload
systemctl enable wdtt-panel
systemctl restart wdtt-panel

sleep 2
if systemctl is-active --quiet wdtt-panel; then
  echo "[OK] Сервис запущен"
else
  echo "[ERR] Сервис не запустился"
  journalctl -u wdtt-panel -n 20 --no-pager
  exit 1
fi

echo ""
echo "======================================"
echo "  Установка завершена!"
echo "======================================"
echo ""
IP=$(hostname -I 2>/dev/null | awk '{print $1}')
echo "  Панель:         http://${IP}:8080"
echo "  SOCKS5 прокси:  127.0.0.1:10808"
echo "  HTTP прокси:    127.0.0.1:10809"
echo ""
echo "  Логи:  journalctl -u wdtt-panel -f"
echo "  Стоп:  systemctl stop wdtt-panel"
echo ""
