#!/bin/sh
set -e

REPO="aminmagamed738-cloud/WDTT-PANEL"
BRANCH="main"
INSTALL_DIR="/opt/wdtt-panel"
TMP_DIR="/tmp/wdtt-$$"
NODE_MIN=20

echo ""
echo "======================================"
echo "  WDTT Panel - установка"
echo "======================================"
echo ""

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

# Chromium
CHROMIUM_BIN=""
for bin in chromium chromium-browser google-chrome google-chrome-stable; do
  if command -v "$bin" >/dev/null 2>&1; then
    CHROMIUM_BIN=$(command -v "$bin"); break
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

mkdir -p "$TMP_DIR"
PANEL_SRC=""

# --- Mode A: run from extracted folder (sh install.sh) ---
SCRIPT_DIR=""
if [ -n "$0" ] && [ "$0" != "sh" ] && [ "$0" != "/bin/sh" ] && [ "$0" != "bash" ] && [ "$0" != "-" ]; then
  SCRIPT_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || true
fi

if [ -n "$SCRIPT_DIR" ] && [ -d "$SCRIPT_DIR/wdtt-panel" ]; then
  echo "[INFO] Использую локальные файлы..."
  PANEL_SRC="$SCRIPT_DIR/wdtt-panel"

# --- Mode B: piped via curl — download repo tarball from GitHub ---
else
  echo "[INFO] Скачиваю файлы с GitHub..."
  TARBALL_URL="https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz"
  curl -fsSL -o "$TMP_DIR/repo.tar.gz" "$TARBALL_URL" \
    || { echo "[ERR] Не удалось скачать $TARBALL_URL"; exit 1; }
  echo "[OK] Скачано"
  tar -xzf "$TMP_DIR/repo.tar.gz" -C "$TMP_DIR"
  # GitHub names the folder: REPONAME-BRANCH
  REPO_NAME=$(echo "$REPO" | cut -d'/' -f2)
  EXTRACTED="$TMP_DIR/${REPO_NAME}-${BRANCH}"
  if [ -d "$EXTRACTED/wdtt-panel" ]; then
    PANEL_SRC="$EXTRACTED/wdtt-panel"
    SERVICE_SRC="$EXTRACTED/wdtt-panel.service"
  else
    echo "[ERR] Папка wdtt-panel не найдена в архиве репо"
    exit 1
  fi
fi

# Copy panel files
mkdir -p "$INSTALL_DIR"
cp -r "$PANEL_SRC/." "$INSTALL_DIR/"
echo "[OK] Файлы скопированы в $INSTALL_DIR"

# Systemd service
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

rm -rf "$TMP_DIR"

systemctl daemon-reload
systemctl enable wdtt-panel
systemctl restart wdtt-panel

sleep 2
if systemctl is-active --quiet wdtt-panel; then
  echo "[OK] Сервис запущен"
else
  echo "[ERR] Сервис не запустился"
  journalctl -u wdtt-panel -n 30 --no-pager
  exit 1
fi

echo ""
echo "======================================"
echo "  Установка завершена!"
echo "======================================"
IP=$(hostname -I 2>/dev/null | awk '{print $1}')
echo ""
echo "  Панель:         http://${IP}:8080"
echo "  SOCKS5 прокси:  127.0.0.1:10808"
echo "  HTTP прокси:    127.0.0.1:10809"
echo ""
echo "  Логи:    journalctl -u wdtt-panel -f"
echo "  Стоп:    systemctl stop wdtt-panel"
echo "  Рестарт: systemctl restart wdtt-panel"
echo ""
