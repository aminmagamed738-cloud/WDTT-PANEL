#!/bin/sh
set -e

# WDTT Panel — VK Tunnel Management
# https://github.com/aminmagamed738-cloud/WDTT-PANEL

REPO="aminmagamed738-cloud/WDTT-PANEL"
RELEASE_ZIP="wdtt-panel-release.zip"
INSTALL_DIR="/opt/wdtt-panel"
TMP_DIR="/tmp/wdtt-install-$$"
NODE_MIN=20

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_ok()   { printf "${GREEN}[OK]${NC} %s\n" "$*"; }
log_warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
log_err()  { printf "${RED}[ERR]${NC} %s\n" "$*"; exit 1; }
log_info() { printf "[INFO] %s\n" "$*"; }

echo ""
echo "======================================"
echo "  WDTT Panel - установка"
echo "======================================"
echo ""

# Root check
if [ "$(id -u)" -ne 0 ]; then
  log_err "Запустите от root (su - root)"
fi

# Node.js check
if ! command -v node >/dev/null 2>&1; then
  log_info "Node.js не найден, устанавливаю через NodeSource..."
  curl -fsSL https://deb.nodesource.com/setup_22.x | sh -
  apt-get install -y nodejs
fi

NODE_VER=$(node -e "process.stdout.write(process.versions.node.split('.')[0])")
if [ "$NODE_VER" -lt "$NODE_MIN" ]; then
  log_err "Нужен Node.js >= $NODE_MIN, установлен: $NODE_VER"
fi
log_ok "Node.js v$(node --version)"

# unzip check
if ! command -v unzip >/dev/null 2>&1; then
  log_info "unzip не найден, устанавливаю..."
  apt-get install -y unzip 2>/dev/null || yum install -y unzip 2>/dev/null || true
fi

# Chromium check
CHROMIUM_BIN=""
for bin in chromium chromium-browser google-chrome google-chrome-stable; do
  if command -v "$bin" >/dev/null 2>&1; then
    CHROMIUM_BIN=$(command -v "$bin")
    break
  fi
done

if [ -z "$CHROMIUM_BIN" ]; then
  log_info "Chromium не найден, устанавливаю..."
  apt-get install -y chromium chromium-driver 2>/dev/null \
    || apt-get install -y chromium-browser 2>/dev/null \
    || yum install -y chromium 2>/dev/null \
    || true
  for bin in chromium chromium-browser google-chrome; do
    if command -v "$bin" >/dev/null 2>&1; then
      CHROMIUM_BIN=$(command -v "$bin")
      break
    fi
  done
fi

if [ -n "$CHROMIUM_BIN" ]; then
  log_ok "Chromium: $CHROMIUM_BIN"
else
  log_warn "Chromium не найден. Puppeteer попробует скачать Chromium автоматически."
fi

# Download release ZIP
log_info "Скачиваю последний релиз с GitHub..."
mkdir -p "$TMP_DIR"
DOWNLOAD_URL="https://github.com/${REPO}/releases/latest/download/${RELEASE_ZIP}"
curl -fsSL -o "$TMP_DIR/release.zip" "$DOWNLOAD_URL" \
  || log_err "Не удалось скачать $DOWNLOAD_URL"
log_ok "Скачано"

# Extract
log_info "Распаковываю..."
unzip -q "$TMP_DIR/release.zip" -d "$TMP_DIR/extracted"
log_ok "Распаковано"

# Find the wdtt-panel folder inside extracted
PANEL_SRC=""
for d in "$TMP_DIR/extracted/wdtt-panel" "$TMP_DIR/extracted/wdtt-panel-release/wdtt-panel"; do
  if [ -d "$d" ]; then
    PANEL_SRC="$d"
    break
  fi
done
if [ -z "$PANEL_SRC" ]; then
  log_err "Не найдена папка wdtt-panel в архиве"
fi

# Copy files
mkdir -p "$INSTALL_DIR"
cp -r "$PANEL_SRC/"* "$INSTALL_DIR/"
log_ok "Файлы скопированы в $INSTALL_DIR"

# Copy service file
SERVICE_SRC=""
for f in "$TMP_DIR/extracted/wdtt-panel.service" "$TMP_DIR/extracted/wdtt-panel-release/wdtt-panel.service"; do
  if [ -f "$f" ]; then
    SERVICE_SRC="$f"
    break
  fi
done

if [ -z "$SERVICE_SRC" ]; then
  # Create service file inline
  cat > /etc/systemd/system/wdtt-panel.service <<SVCEOF
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
SVCEOF
else
  cp "$SERVICE_SRC" /etc/systemd/system/wdtt-panel.service
  sed -i "s|/opt/wdtt-panel|$INSTALL_DIR|g" /etc/systemd/system/wdtt-panel.service
fi
log_ok "Systemd сервис установлен"

# Generate session secret
SESSION_SECRET=$(openssl rand -hex 32 2>/dev/null || cat /proc/sys/kernel/random/uuid | tr -d '-')

# Create .env
cat > "$INSTALL_DIR/.env" <<EOF
NODE_ENV=production
PORT=8080
FRONTEND_PORT=26208
SESSION_SECRET=${SESSION_SECRET}
CHROMIUM_PATH=${CHROMIUM_BIN}
SOCKS5_PORT=10808
HTTP_PORT=10809
EOF
log_ok "Создан $INSTALL_DIR/.env"

# Cleanup
rm -rf "$TMP_DIR"

# Start service
systemctl daemon-reload
systemctl enable wdtt-panel
systemctl restart wdtt-panel

sleep 2
if systemctl is-active --quiet wdtt-panel; then
  log_ok "Сервис запущен"
else
  log_err "Сервис не запустился. Проверьте: journalctl -u wdtt-panel -n 50"
fi

echo ""
echo "======================================"
echo "  Установка завершена!"
echo "======================================"
echo ""
echo "  API сервер:     http://$(hostname -I 2>/dev/null | awk '{print $1}'):8080"
echo "  SOCKS5 прокси:  127.0.0.1:10808"
echo "  HTTP прокси:    127.0.0.1:10809"
echo ""
echo "  Команды:"
echo "    systemctl status wdtt-panel"
echo "    journalctl -u wdtt-panel -f"
echo "    systemctl restart wdtt-panel"
echo ""
echo "  GitHub: https://github.com/aminmagamed738-cloud/WDTT-PANEL"
echo ""
