#!/usr/bin/env bash
# WDTT Panel — Быстрый запуск без установки (Linux / macOS)
set -e

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
RESET='\033[0m'

echo ""
echo -e "${CYAN}${BOLD}═══════════════════════════════════════════${RESET}"
echo -e "${CYAN}${BOLD}   WDTT Panel — Запуск                     ${RESET}"
echo -e "${CYAN}${BOLD}═══════════════════════════════════════════${RESET}"
echo ""

# ── Node.js check ───────────────────────────────────────────────────────────────
if ! command -v node &>/dev/null; then
  echo -e "${RED}❌ Node.js не найден.${RESET}"
  echo ""
  echo "Установите Node.js 18+:"
  echo ""
  echo "  Ubuntu / Debian:"
  echo "    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -"
  echo "    sudo apt-get install -y nodejs"
  echo ""
  echo "  CentOS / RHEL / Fedora:"
  echo "    curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -"
  echo "    sudo yum install -y nodejs"
  echo ""
  echo "  Alpine Linux:"
  echo "    sudo apk add nodejs npm"
  echo ""
  echo "  macOS (Homebrew):"
  echo "    brew install node"
  echo ""
  echo "  Или скачайте с: https://nodejs.org/"
  exit 1
fi

NODE_VER=$(node -e "process.stdout.write(process.version.slice(1).split('.')[0])")
if [ "$NODE_VER" -lt 18 ]; then
  echo -e "${RED}❌ Требуется Node.js 18+. Текущая версия: $(node --version)${RESET}"
  echo "Обновите Node.js: https://nodejs.org/"
  exit 1
fi

echo -e "${GREEN}✓ Node.js $(node --version)${RESET}"

# ── Install dependencies ────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/server"

if [ ! -d "node_modules" ]; then
  echo -e "${YELLOW}📦 Установка зависимостей (только первый раз)...${RESET}"
  npm install --loglevel=error
  echo -e "${GREEN}✓ Зависимости установлены${RESET}"
else
  echo -e "${GREEN}✓ Зависимости уже есть${RESET}"
fi

echo ""
echo -e "${YELLOW}🚀 Запуск WDTT Panel...${RESET}"
echo ""

exec node index.js "$@"
