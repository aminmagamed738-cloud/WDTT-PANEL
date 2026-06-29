#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║        WDTT Panel — Универсальный установщик для VPS            ║
# ║    Поддержка: Ubuntu, Debian, CentOS, RHEL, Fedora, Rocky,      ║
# ║               AlmaLinux, openSUSE, Alpine, Arch Linux           ║
# ╚══════════════════════════════════════════════════════════════════╝
set -euo pipefail

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

banner() {
  echo ""
  echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════════════════╗${RESET}"
  echo -e "${CYAN}${BOLD}║         WDTT Panel — Установщик v1.0              ║${RESET}"
  echo -e "${CYAN}${BOLD}║   github.com/aminmagamed738-cloud/WDTT-PANEL       ║${RESET}"
  echo -e "${CYAN}${BOLD}╚═══════════════════════════════════════════════════╝${RESET}"
  echo ""
}

step() { echo -e "\n${CYAN}${BOLD}▸ $1${RESET}"; }
ok()   { echo -e "${GREEN}  ✓ $1${RESET}"; }
warn() { echo -e "${YELLOW}  ⚠ $1${RESET}"; }
err()  { echo -e "${RED}  ✗ $1${RESET}"; exit 1; }
info() { echo -e "${DIM}  → $1${RESET}"; }

banner

# ── Root check ──────────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
  err "Запустите скрипт от root: sudo bash install.sh"
fi

# ── Detect OS ───────────────────────────────────────────────────────────────────
step "Определение операционной системы"

OS_TYPE=""
PKG_MANAGER=""

if [ -f /etc/os-release ]; then
  . /etc/os-release
  case "$ID" in
    ubuntu|debian|linuxmint|pop|elementary|kali|parrot|raspbian)
      OS_TYPE="debian"
      PKG_MANAGER="apt"
      ok "Обнаружена: ${PRETTY_NAME:-$ID}"
      ;;
    centos|rhel|rocky|almalinux|ol)
      OS_TYPE="rhel"
      command -v dnf &>/dev/null && PKG_MANAGER="dnf" || PKG_MANAGER="yum"
      ok "Обнаружена: ${PRETTY_NAME:-$ID}"
      ;;
    fedora)
      OS_TYPE="rhel"
      PKG_MANAGER="dnf"
      ok "Обнаружена: ${PRETTY_NAME:-$ID}"
      ;;
    opensuse*|sles)
      OS_TYPE="suse"
      PKG_MANAGER="zypper"
      ok "Обнаружена: ${PRETTY_NAME:-$ID}"
      ;;
    arch|manjaro|endeavouros|garuda)
      OS_TYPE="arch"
      PKG_MANAGER="pacman"
      ok "Обнаружена: ${PRETTY_NAME:-$ID}"
      ;;
    alpine)
      OS_TYPE="alpine"
      PKG_MANAGER="apk"
      ok "Обнаружена: ${PRETTY_NAME:-$ID}"
      ;;
    *)
      warn "ОС '$ID' не в списке, пробуем определить по пакетному менеджеру..."
      if command -v apt-get &>/dev/null; then
        OS_TYPE="debian"; PKG_MANAGER="apt"
      elif command -v dnf &>/dev/null; then
        OS_TYPE="rhel"; PKG_MANAGER="dnf"
      elif command -v yum &>/dev/null; then
        OS_TYPE="rhel"; PKG_MANAGER="yum"
      elif command -v pacman &>/dev/null; then
        OS_TYPE="arch"; PKG_MANAGER="pacman"
      elif command -v apk &>/dev/null; then
        OS_TYPE="alpine"; PKG_MANAGER="apk"
      else
        err "Не удалось определить пакетный менеджер. Установите Node.js 20+ вручную: https://nodejs.org/"
      fi
      ok "Пакетный менеджер: $PKG_MANAGER"
      ;;
  esac
else
  err "Не удалось определить ОС (нет /etc/os-release)"
fi

# ── Helper: install package ─────────────────────────────────────────────────────
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

# ── Install curl if missing ─────────────────────────────────────────────────────
if ! command -v curl &>/dev/null; then
  step "Установка curl"
  pkg_install curl
  ok "curl установлен"
fi

# ── Install git if missing ──────────────────────────────────────────────────────
if ! command -v git &>/dev/null; then
  step "Установка git"
  pkg_install git
  ok "git установлен"
fi

# ── Install Node.js 20 ──────────────────────────────────────────────────────────
step "Проверка Node.js"

NEED_NODE=false
if command -v node &>/dev/null; then
  NODE_VER=$(node -e "process.stdout.write(process.version.slice(1).split('.')[0])" 2>/dev/null || echo "0")
  if [ "$NODE_VER" -ge 18 ] 2>/dev/null; then
    ok "Node.js $(node --version) уже установлен (подходит)"
  else
    warn "Node.js $(node --version) слишком старый (нужен 18+), обновляем..."
    NEED_NODE=true
  fi
else
  info "Node.js не найден, устанавливаем..."
  NEED_NODE=true
fi

if [ "$NEED_NODE" = true ]; then
  case $OS_TYPE in
    debian)
      info "Добавляем NodeSource репозиторий для Debian/Ubuntu..."
      curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
      DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs >/dev/null 2>&1
      ;;
    rhel)
      info "Добавляем NodeSource репозиторий для RHEL/CentOS/Fedora..."
      curl -fsSL https://rpm.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
      $PKG_MANAGER install -y nodejs >/dev/null 2>&1
      ;;
    suse)
      info "Установка Node.js через zypper..."
      zypper addrepo https://rpm.nodesource.com/pub_20.x/nodistro/repo/nodesource-release-nodistro-1.noarch.rpm nodesource >/dev/null 2>&1 || true
      zypper install -y -n nodejs20 >/dev/null 2>&1 || {
        warn "Пробуем через snap..."
        snap install node --classic >/dev/null 2>&1 || err "Установите Node.js 20+ вручную: https://nodejs.org/"
      }
      ;;
    arch)
      info "Установка Node.js через pacman..."
      pacman -Sy --noconfirm nodejs npm >/dev/null 2>&1
      ;;
    alpine)
      info "Установка Node.js через apk..."
      apk add --no-cache nodejs npm >/dev/null 2>&1
      ;;
  esac

  # Verify
  if command -v node &>/dev/null; then
    ok "Node.js $(node --version) установлен"
  else
    err "Не удалось установить Node.js. Установите вручную: https://nodejs.org/"
  fi
fi

# ── Copy/update panel files ─────────────────────────────────────────────────────
step "Установка файлов панели"

# Backup password if exists
PW_BACKUP=""
if [ -f "$INSTALL_DIR/server/.wdtt-password" ]; then
  PW_BACKUP=$(cat "$INSTALL_DIR/server/.wdtt-password")
  info "Сохраняем существующий пароль..."
fi

# Get source directory (script's parent parent)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$(dirname "$SCRIPT_DIR")"

if [ -d "$SRC_DIR/server" ]; then
  rm -rf "$INSTALL_DIR"
  mkdir -p "$INSTALL_DIR"
  cp -r "$SRC_DIR/." "$INSTALL_DIR/"
  ok "Файлы скопированы из локальной папки"
else
  err "Папка server/ не найдена рядом со скриптом. Запустите из корня проекта."
fi

# Restore password
if [ -n "$PW_BACKUP" ]; then
  echo "$PW_BACKUP" > "$INSTALL_DIR/server/.wdtt-password"
  chmod 600 "$INSTALL_DIR/server/.wdtt-password"
  ok "Пароль восстановлен"
fi

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
    PORT=$p
    break
  fi
done

if [ "$PORT" != "$DEFAULT_PORT" ]; then
  warn "Порт $DEFAULT_PORT занят → используем порт $PORT"
else
  ok "Порт $PORT свободен"
fi

# ── Create systemd service ──────────────────────────────────────────────────────
step "Настройка автозапуска (systemd)"

NODE_BIN=$(command -v node)

if command -v systemctl &>/dev/null && systemctl --version &>/dev/null 2>&1; then
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
    ok "Сервис systemd запущен и добавлен в автозапуск"
  else
    warn "Сервис запущен с ошибками. Проверьте: journalctl -u $SERVICE_NAME -n 50"
  fi

# ── Fallback: OpenRC (Alpine) ───────────────────────────────────────────────────
elif command -v rc-service &>/dev/null; then
  cat > /etc/init.d/${SERVICE_NAME} << EOF
#!/sbin/openrc-run
name="${SERVICE_NAME}"
description="WDTT Panel - VPN Tunnel via VK Calls"
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
  ok "Сервис OpenRC запущен (Alpine)"

else
  warn "systemd/openrc не найден. Запустите вручную: node $INSTALL_DIR/server/index.js $PORT"
fi

# ── Firewall ────────────────────────────────────────────────────────────────────
step "Настройка файрвола"

if command -v ufw &>/dev/null; then
  ufw allow "$PORT/tcp" >/dev/null 2>&1 && ok "UFW: порт $PORT открыт"
fi

if command -v firewall-cmd &>/dev/null; then
  firewall-cmd --permanent --add-port="$PORT/tcp" >/dev/null 2>&1
  firewall-cmd --reload >/dev/null 2>&1
  ok "firewalld: порт $PORT открыт"
fi

if command -v iptables &>/dev/null && ! command -v ufw &>/dev/null && ! command -v firewall-cmd &>/dev/null; then
  iptables -I INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null && ok "iptables: порт $PORT открыт"
fi

# ── Get password ────────────────────────────────────────────────────────────────
sleep 2
PW_FILE="$INSTALL_DIR/server/.wdtt-password"
[ -f "$PW_FILE" ] && PW=$(cat "$PW_FILE") || PW="(будет показан после первого запуска)"

# ── Get public IP ───────────────────────────────────────────────────────────────
PUB_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || \
         curl -s --max-time 5 https://ifconfig.me 2>/dev/null || \
         curl -s --max-time 5 https://icanhazip.com 2>/dev/null || \
         echo "ваш-публичный-ip")

# ── Final output ────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}╔═══════════════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}${BOLD}║          ✓ WDTT Panel установлена!                ║${RESET}"
echo -e "${GREEN}${BOLD}╠═══════════════════════════════════════════════════╣${RESET}"
echo -e "${GREEN}${BOLD}║${RESET}  🌐 URL:      ${BOLD}http://${PUB_IP}:${PORT}${RESET}"
echo -e "${GREEN}${BOLD}║${RESET}  🔑 Пароль:   ${BOLD}${PW}${RESET}"
echo -e "${GREEN}${BOLD}╠═══════════════════════════════════════════════════╣${RESET}"
echo -e "${GREEN}${BOLD}║${RESET}  Логи:     journalctl -u ${SERVICE_NAME} -f${RESET}"
echo -e "${GREEN}${BOLD}║${RESET}  Статус:   systemctl status ${SERVICE_NAME}${RESET}"
echo -e "${GREEN}${BOLD}║${RESET}  Стоп:     systemctl stop ${SERVICE_NAME}${RESET}"
echo -e "${GREEN}${BOLD}║${RESET}  Удалить:  bash ${INSTALL_DIR}/scripts/uninstall.sh${RESET}"
echo -e "${GREEN}${BOLD}╚═══════════════════════════════════════════════════╝${RESET}"
echo ""
