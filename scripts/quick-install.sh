#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║   WDTT Panel — Быстрая установка с GitHub (одна команда)       ║
# ║                                                                  ║
# ║   curl -fsSL https://raw.githubusercontent.com/                 ║
# ║     aminmagamed738-cloud/WDTT-PANEL/main/scripts/               ║
# ║     quick-install.sh | bash                                      ║
# ╚══════════════════════════════════════════════════════════════════╝
set -euo pipefail

GITHUB_USER="aminmagamed738-cloud"
GITHUB_REPO="WDTT-PANEL"
BRANCH="main"
INSTALL_DIR="/opt/wdtt-panel"
SERVICE_NAME="wdtt-panel"
DEFAULT_PORT=7474

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

step() { echo -e "\n${CYAN}${BOLD}▸ $1${RESET}"; }
ok()   { echo -e "${GREEN}  ✓ $1${RESET}"; }
warn() { echo -e "${YELLOW}  ⚠ $1${RESET}"; }
err()  { echo -e "${RED}  ✗ $1${RESET}"; exit 1; }
info() { echo -e "${DIM}  → $1${RESET}"; }

echo ""
echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}${BOLD}║         WDTT Panel — Быстрая установка            ║${RESET}"
echo -e "${CYAN}${BOLD}║   github.com/aminmagamed738-cloud/WDTT-PANEL       ║${RESET}"
echo -e "${CYAN}${BOLD}╚═══════════════════════════════════════════════════╝${RESET}"
echo ""

# ── Root check ──────────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
  err "Запустите от root. На VPS введите: sudo -i  затем повторите команду"
fi

# ── Detect OS ───────────────────────────────────────────────────────────────────
step "Определение операционной системы"

OS_TYPE=""
PKG_MANAGER=""

if [ -f /etc/os-release ]; then
  . /etc/os-release
  case "${ID:-}" in
    ubuntu|debian|linuxmint|pop|elementary|kali|parrot|raspbian)
      OS_TYPE="debian"; PKG_MANAGER="apt"
      ok "Обнаружена: ${PRETTY_NAME:-$ID}"
      ;;
    centos|rhel|rocky|almalinux|ol)
      OS_TYPE="rhel"
      command -v dnf &>/dev/null && PKG_MANAGER="dnf" || PKG_MANAGER="yum"
      ok "Обнаружена: ${PRETTY_NAME:-$ID}"
      ;;
    fedora)
      OS_TYPE="rhel"; PKG_MANAGER="dnf"
      ok "Обнаружена: ${PRETTY_NAME:-$ID}"
      ;;
    opensuse*|sles)
      OS_TYPE="suse"; PKG_MANAGER="zypper"
      ok "Обнаружена: ${PRETTY_NAME:-$ID}"
      ;;
    arch|manjaro|endeavouros|garuda)
      OS_TYPE="arch"; PKG_MANAGER="pacman"
      ok "Обнаружена: ${PRETTY_NAME:-$ID}"
      ;;
    alpine)
      OS_TYPE="alpine"; PKG_MANAGER="apk"
      ok "Обнаружена: ${PRETTY_NAME:-$ID}"
      ;;
    *)
      if command -v apt-get &>/dev/null; then OS_TYPE="debian"; PKG_MANAGER="apt"
      elif command -v dnf &>/dev/null;   then OS_TYPE="rhel";   PKG_MANAGER="dnf"
      elif command -v yum &>/dev/null;   then OS_TYPE="rhel";   PKG_MANAGER="yum"
      elif command -v pacman &>/dev/null; then OS_TYPE="arch";  PKG_MANAGER="pacman"
      elif command -v apk &>/dev/null;   then OS_TYPE="alpine"; PKG_MANAGER="apk"
      else err "Неизвестная ОС. Установите Node.js 20+ вручную: https://nodejs.org/"; fi
      warn "ОС не распознана, используем $PKG_MANAGER"
      ;;
  esac
else
  err "Нет /etc/os-release. Невозможно определить ОС."
fi

# ── Helper: silent install ──────────────────────────────────────────────────────
pkg_install() {
  case $PKG_MANAGER in
    apt)    DEBIAN_FRONTEND=noninteractive apt-get install -y -q "$@" >/dev/null 2>&1 ;;
    dnf)    dnf install -y -q "$@" >/dev/null 2>&1 ;;
    yum)    yum install -y -q "$@" >/dev/null 2>&1 ;;
    zypper) zypper install -y -n "$@" >/dev/null 2>&1 ;;
    pacman) pacman -Sy --noconfirm "$@" >/dev/null 2>&1 ;;
    apk)    apk add --no-cache "$@" >/dev/null 2>&1 ;;
  esac
}

# ── Install prerequisites ───────────────────────────────────────────────────────
step "Проверка зависимостей"

for tool in curl tar; do
  if ! command -v $tool &>/dev/null; then
    info "Устанавливаем $tool..."
    pkg_install $tool
  fi
  ok "$tool"
done

# ── Node.js 20 ──────────────────────────────────────────────────────────────────
step "Проверка Node.js"

NEED_NODE=false
if command -v node &>/dev/null; then
  VER=$(node -e "process.stdout.write(process.version.slice(1).split('.')[0])" 2>/dev/null || echo "0")
  if [ "$VER" -ge 18 ] 2>/dev/null; then
    ok "Node.js $(node --version) — подходит"
  else
    warn "Node.js $(node --version) слишком старый, обновляем..."
    NEED_NODE=true
  fi
else
  info "Node.js не найден, устанавливаем..."
  NEED_NODE=true
fi

if [ "$NEED_NODE" = true ]; then
  case $OS_TYPE in
    debian)
      curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
      DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs >/dev/null 2>&1
      ;;
    rhel)
      curl -fsSL https://rpm.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
      $PKG_MANAGER install -y nodejs >/dev/null 2>&1
      ;;
    suse)
      zypper install -y -n nodejs20 npm20 >/dev/null 2>&1 || {
        curl -fsSL https://rpm.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
        zypper install -y -n nodejs >/dev/null 2>&1
      }
      ;;
    arch)
      pacman -Sy --noconfirm nodejs npm >/dev/null 2>&1
      ;;
    alpine)
      apk add --no-cache nodejs npm >/dev/null 2>&1
      ;;
  esac

  command -v node &>/dev/null || err "Не удалось установить Node.js. Установите вручную: https://nodejs.org/"
  ok "Node.js $(node --version) установлен"
fi

# ── Download from GitHub ────────────────────────────────────────────────────────
step "Загрузка WDTT Panel с GitHub"

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

ARCHIVE_URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}/archive/refs/heads/${BRANCH}.tar.gz"
info "Источник: $ARCHIVE_URL"

if ! curl -fsSL --connect-timeout 15 --max-time 60 "$ARCHIVE_URL" -o "$TMP/panel.tar.gz"; then
  err "Не удалось скачать панель. Проверьте доступ к github.com"
fi

tar -xzf "$TMP/panel.tar.gz" -C "$TMP"
EXTRACTED=$(ls "$TMP" | grep -v "panel.tar.gz" | head -1)

[ -z "$EXTRACTED" ] && err "Архив пустой или повреждён"
ok "Архив распакован: $EXTRACTED"

SRC="$TMP/$EXTRACTED"

# Backup password
PW_BACKUP=""
if [ -f "$INSTALL_DIR/server/.wdtt-password" ]; then
  PW_BACKUP=$(cat "$INSTALL_DIR/server/.wdtt-password")
  info "Сохраняем пароль от предыдущей установки..."
fi

# ── Detect repo structure (flat or nested) ──────────────────────────────────────
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/server/public"
mkdir -p "$INSTALL_DIR/scripts"

if [ -d "$SRC/server" ]; then
  # Правильная структура: server/ папка есть
  cp -r "$SRC/." "$INSTALL_DIR/"
  info "Структура: стандартная (server/ папка)"
else
  # Плоская структура: всё в корне репо
  info "Структура: плоская (файлы в корне)"
  [ -f "$SRC/index.js" ]   && cp "$SRC/index.js"   "$INSTALL_DIR/server/"
  [ -f "$SRC/package.json" ] && cp "$SRC/package.json" "$INSTALL_DIR/server/"
  [ -f "$SRC/package-lock.json" ] && cp "$SRC/package-lock.json" "$INSTALL_DIR/server/"
  # index.html → server/public/
  if [ -f "$SRC/index.html" ]; then
    cp "$SRC/index.html" "$INSTALL_DIR/server/public/"
  fi
  # Скрипты
  for f in quick-install.sh install.sh uninstall.sh; do
    [ -f "$SRC/$f" ] && cp "$SRC/$f" "$INSTALL_DIR/scripts/"
    [ -f "$SRC/scripts/$f" ] && cp "$SRC/scripts/$f" "$INSTALL_DIR/scripts/"
  done
  [ -f "$SRC/start.sh" ]  && cp "$SRC/start.sh"  "$INSTALL_DIR/"
  [ -f "$SRC/start.bat" ] && cp "$SRC/start.bat" "$INSTALL_DIR/"
  [ -f "$SRC/README.md" ] && cp "$SRC/README.md" "$INSTALL_DIR/"
fi

# Restore password
if [ -n "$PW_BACKUP" ]; then
  echo "$PW_BACKUP" > "$INSTALL_DIR/server/.wdtt-password"
  chmod 600 "$INSTALL_DIR/server/.wdtt-password"
  ok "Пароль сохранён"
fi

# Verify key files
[ -f "$INSTALL_DIR/server/index.js" ] || err "index.js не найден после распаковки"
[ -f "$INSTALL_DIR/server/public/index.html" ] || warn "index.html не найден — панель запустится без фронтенда"

ok "Файлы установлены в $INSTALL_DIR"

# ── npm install ─────────────────────────────────────────────────────────────────
step "Установка npm-зависимостей"
cd "$INSTALL_DIR/server"
npm install --loglevel=error --production 2>/dev/null
ok "Зависимости установлены"

# ── Find free port ──────────────────────────────────────────────────────────────
step "Выбор порта"
PORT=$DEFAULT_PORT
for p in 7474 7475 7476 8080 8081 3000 5000 9000; do
  if ! ss -tulpn 2>/dev/null | grep -q ":$p " && \
     ! netstat -tlpn 2>/dev/null | grep -q ":$p "; then
    PORT=$p; break
  fi
done

[ "$PORT" != "$DEFAULT_PORT" ] && warn "Порт $DEFAULT_PORT занят → используем $PORT" || ok "Порт $PORT"

# ── systemd / OpenRC service ────────────────────────────────────────────────────
step "Настройка автозапуска"

NODE_BIN=$(command -v node)

if command -v systemctl &>/dev/null; then
  cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=WDTT Panel - VPN Tunnel via VK Calls
Documentation=https://github.com/aminmagamed738-cloud/WDTT-PANEL
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}/server
ExecStart=${NODE_BIN} ${INSTALL_DIR}/server/index.js ${PORT}
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}
Environment=NODE_ENV=production
Environment=PORT=${PORT}

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME" >/dev/null 2>&1
  systemctl restart "$SERVICE_NAME"
  sleep 2

  if systemctl is-active --quiet "$SERVICE_NAME"; then
    ok "Сервис запущен и добавлен в автозапуск"
  else
    warn "Возможны ошибки: journalctl -u $SERVICE_NAME -n 30"
  fi

elif command -v rc-service &>/dev/null; then
  cat > /etc/init.d/${SERVICE_NAME} << EOF
#!/sbin/openrc-run
name="${SERVICE_NAME}"
description="WDTT Panel"
command="${NODE_BIN}"
command_args="${INSTALL_DIR}/server/index.js ${PORT}"
directory="${INSTALL_DIR}/server"
pidfile="/run/${SERVICE_NAME}.pid"
command_background=yes
depend() { need net; }
EOF
  chmod +x /etc/init.d/${SERVICE_NAME}
  rc-update add "$SERVICE_NAME" default >/dev/null 2>&1
  rc-service "$SERVICE_NAME" start
  ok "Сервис OpenRC запущен"

else
  warn "systemd не найден. Запустите: node $INSTALL_DIR/server/index.js $PORT"
fi

# ── Firewall ────────────────────────────────────────────────────────────────────
step "Открываем порт $PORT в файрволе"

command -v ufw &>/dev/null && \
  ufw allow "$PORT/tcp" >/dev/null 2>&1 && ok "UFW: порт $PORT открыт"

command -v firewall-cmd &>/dev/null && {
  firewall-cmd --permanent --add-port="$PORT/tcp" >/dev/null 2>&1
  firewall-cmd --reload >/dev/null 2>&1
  ok "firewalld: порт $PORT открыт"
}

if ! command -v ufw &>/dev/null && ! command -v firewall-cmd &>/dev/null; then
  iptables -I INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null && ok "iptables: порт $PORT открыт" || true
fi

# ── Final result ────────────────────────────────────────────────────────────────
sleep 2
PW_FILE="$INSTALL_DIR/server/.wdtt-password"
[ -f "$PW_FILE" ] && PW=$(cat "$PW_FILE") || PW="(панель генерирует пароль при первом запуске)"

PUB_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || \
         curl -s --max-time 5 https://ifconfig.me 2>/dev/null || \
         curl -s --max-time 5 https://icanhazip.com 2>/dev/null || \
         echo "ВАШ-IP")

echo ""
echo -e "${GREEN}${BOLD}╔═══════════════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}${BOLD}║          ✓ WDTT Panel установлена!                ║${RESET}"
echo -e "${GREEN}${BOLD}╠═══════════════════════════════════════════════════╣${RESET}"
echo -e "${GREEN}${BOLD}║${RESET}  🌐 Откройте в браузере:${RESET}"
echo -e "${GREEN}${BOLD}║${RESET}     ${BOLD}http://${PUB_IP}:${PORT}${RESET}"
echo -e "${GREEN}${BOLD}║${RESET}  🔑 Пароль:  ${BOLD}${PW}${RESET}"
echo -e "${GREEN}${BOLD}╠═══════════════════════════════════════════════════╣${RESET}"
echo -e "${GREEN}${BOLD}║${RESET}  Логи:     journalctl -u ${SERVICE_NAME} -f${RESET}"
echo -e "${GREEN}${BOLD}║${RESET}  Статус:   systemctl status ${SERVICE_NAME}${RESET}"
echo -e "${GREEN}${BOLD}║${RESET}  Рестарт:  systemctl restart ${SERVICE_NAME}${RESET}"
echo -e "${GREEN}${BOLD}║${RESET}  Удалить:  curl -fsSL https://raw.githubusercontent.com/${RESET}"
echo -e "${GREEN}${BOLD}║${RESET}    ${GITHUB_USER}/${GITHUB_REPO}/main/scripts/uninstall.sh | bash${RESET}"
echo -e "${GREEN}${BOLD}╚═══════════════════════════════════════════════════╝${RESET}"
echo ""
