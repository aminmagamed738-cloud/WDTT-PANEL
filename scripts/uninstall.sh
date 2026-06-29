#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║         WDTT Panel — Полное удаление с VPS                     ║
# ╚══════════════════════════════════════════════════════════════════╝
set -euo pipefail

SERVICE_NAME="wdtt-panel"
INSTALL_DIR="/opt/wdtt-panel"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

echo ""
echo -e "${RED}${BOLD}╔═══════════════════════════════════════════════════╗${RESET}"
echo -e "${RED}${BOLD}║         WDTT Panel — Удаление панели              ║${RESET}"
echo -e "${RED}${BOLD}╚═══════════════════════════════════════════════════╝${RESET}"
echo ""

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}✗ Запустите от root (на VPS вы уже root)${RESET}"
  exit 1
fi

echo -e "${YELLOW}Это удалит WDTT Panel, сервис и все файлы из $INSTALL_DIR${RESET}"
echo ""
read -r -p "Продолжить? (y/N): " CONFIRM
case "$CONFIRM" in
  [yY][eE][sS]|[yY]) echo "" ;;
  *) echo "Отменено."; exit 0 ;;
esac

# ── Stop and remove systemd service ────────────────────────────────────────────
if command -v systemctl &>/dev/null; then
  echo -e "${CYAN}▸ Останавливаем сервис...${RESET}"
  systemctl stop "$SERVICE_NAME" 2>/dev/null && echo -e "${GREEN}  ✓ Сервис остановлен${RESET}" || echo -e "${YELLOW}  ⚠ Сервис не был запущен${RESET}"
  systemctl disable "$SERVICE_NAME" 2>/dev/null && echo -e "${GREEN}  ✓ Автозапуск отключён${RESET}" || true

  if [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    systemctl daemon-reload
    echo -e "${GREEN}  ✓ Файл сервиса удалён${RESET}"
  fi
fi

# ── Remove OpenRC service (Alpine) ──────────────────────────────────────────────
if command -v rc-service &>/dev/null && [ -f "/etc/init.d/${SERVICE_NAME}" ]; then
  echo -e "${CYAN}▸ Удаляем OpenRC сервис...${RESET}"
  rc-service "$SERVICE_NAME" stop 2>/dev/null || true
  rc-update del "$SERVICE_NAME" default 2>/dev/null || true
  rm -f "/etc/init.d/${SERVICE_NAME}"
  echo -e "${GREEN}  ✓ OpenRC сервис удалён${RESET}"
fi

# ── Remove installed files ──────────────────────────────────────────────────────
if [ -d "$INSTALL_DIR" ]; then
  echo -e "${CYAN}▸ Удаляем файлы панели...${RESET}"
  rm -rf "$INSTALL_DIR"
  echo -e "${GREEN}  ✓ Папка $INSTALL_DIR удалена${RESET}"
else
  echo -e "${YELLOW}  ⚠ Папка $INSTALL_DIR не найдена (уже удалена?)${RESET}"
fi

# ── Close firewall port (optional) ─────────────────────────────────────────────
echo -e "${CYAN}▸ Закрытие портов в файрволе...${RESET}"
for PORT in 7474 7475 7476 8080 8081; do
  command -v ufw &>/dev/null && ufw delete allow "$PORT/tcp" >/dev/null 2>&1 || true
  command -v firewall-cmd &>/dev/null && firewall-cmd --permanent --remove-port="$PORT/tcp" >/dev/null 2>&1 || true
done
command -v firewall-cmd &>/dev/null && firewall-cmd --reload >/dev/null 2>&1 || true
echo -e "${GREEN}  ✓ Порты закрыты${RESET}"

echo ""
echo -e "${GREEN}${BOLD}╔═══════════════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}${BOLD}║       ✓ WDTT Panel полностью удалена!             ║${RESET}"
echo -e "${GREEN}${BOLD}╚═══════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  Node.js ${YELLOW}НЕ удалён${RESET} (может использоваться другими приложениями)"
echo -e "  Для удаления Node.js: apt remove nodejs  или  dnf remove nodejs"
echo ""
