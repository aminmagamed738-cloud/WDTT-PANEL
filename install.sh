#!/bin/bash
set -e

# WDTT Panel — VK Tunnel Management
# https://github.com/aminmagamed738-cloud/WDTT-PANEL

INSTALL_DIR="/opt/wdtt-panel"
SERVICE_NAME="wdtt-panel"
NODE_MIN=20

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_err()  { echo -e "${RED}[ERR]${NC} $*"; exit 1; }
log_info() { echo -e "[INFO] $*"; }

echo ""
echo "======================================"
echo "  WDTT Panel — установка"
echo "======================================"
echo ""

# Root check
if [ "$EUID" -ne 0 ]; then
  log_err "Запустите от root: bash install.sh"
fi

# Node.js check
if ! command -v node &>/dev/null; then
  log_info "Node.js не найден, устанавливаю через NodeSource..."
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
fi

NODE_VER=$(node -e "process.stdout.write(process.versions.node.split('.')[0])")
if [ "$NODE_VER" -lt "$NODE_MIN" ]; then
  log_err "Нужен Node.js >= $NODE_MIN, установлен: $NODE_VER"
fi
log_ok "Node.js v$(node --version)"

# Chromium check
CHROMIUM_BIN=""
for bin in chromium chromium-browser google-chrome google-chrome-stable; do
  if command -v $bin &>/dev/null; then
    CHROMIUM_BIN=$(command -v $bin)
    break
  fi
done

if [ -z "$CHROMIUM_BIN" ]; then
  log_info "Chromium не найден, устанавливаю..."
  if command -v apt-get &>/dev/null; then
    apt-get install -y chromium chromium-driver 2>/dev/null || apt-get install -y chromium-browser 2>/dev/null || true
  elif command -v yum &>/dev/null; then
    yum install -y chromium 2>/dev/null || true
  fi
  for bin in chromium chromium-browser google-chrome; do
    if command -v $bin &>/dev/null; then
      CHROMIUM_BIN=$(command -v $bin)
      break
    fi
  done
fi

if [ -n "$CHROMIUM_BIN" ]; then
  log_ok "Chromium: $CHROMIUM_BIN"
else
  log_warn "Chromium не найден. Puppeteer попробует скачать Chromium автоматически."
fi

# Create install directory
mkdir -p "$INSTALL_DIR"

# Copy files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log_info "Копирую файлы в $INSTALL_DIR ..."
cp -r "$SCRIPT_DIR/wdtt-panel/"* "$INSTALL_DIR/"
log_ok "Файлы скопированы"

# Generate session secret if not set
SESSION_SECRET=${SESSION_SECRET:-$(openssl rand -hex 32)}

# Create env file
cat > "$INSTALL_DIR/.env" <<EOF
NODE_ENV=production
PORT=8080
FRONTEND_PORT=26208
SESSION_SECRET=$SESSION_SECRET
CHROMIUM_PATH=${CHROMIUM_BIN:-}
SOCKS5_PORT=10808
HTTP_PORT=10809
EOF
log_ok "Создан $INSTALL_DIR/.env"

# Install systemd service
cp "$SCRIPT_DIR/wdtt-panel.service" /etc/systemd/system/
sed -i "s|/opt/wdtt-panel|$INSTALL_DIR|g" /etc/systemd/system/wdtt-panel.service

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
echo -e "${GREEN}  Установка завершена!${NC}"
echo "======================================"
echo ""
echo "  API сервер:     http://$(hostname -I | awk '{print $1}'):8080"
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
