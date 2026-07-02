# WDTT Panel — VK Tunnel Management

Веб-панель управления VPN-туннелем через инфраструктуру звонков ВКонтакте.

## Что делает

- Подключается к VK звонку через headless Chromium (puppeteer)
- Создаёт SOCKS5 (порт 10808) и HTTP CONNECT (порт 10809) локальные прокси на VPS
- Туннелирует трафик через TURN-серверы VK звонков
- Генерирует готовый конфиг для 3x-ui / xray (SOCKS5 outbound + routing rules)
- Стриминг логов в реальном времени через WebSocket
- Авто-капча (WBV метод) + ручной режим кликов по скриншоту

## Требования

- VPS / сервер с Ubuntu 20.04+ / Debian 11+
- root доступ
- Node.js 20+ (установится автоматически)
- Chromium (установится автоматически)
- Открытые порты: 8080 (API), 26208 (веб, опционально), 10808 (SOCKS5), 10809 (HTTP)

## Установка одной командой

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/wdtt-panel/main/install.sh | sudo bash
```

Или скачать и запустить вручную:

```bash
wget https://github.com/YOUR_USERNAME/wdtt-panel/releases/latest/download/wdtt-panel.zip
unzip wdtt-panel.zip
cd wdtt-panel-release
sudo bash install.sh
```

## Управление сервисом

```bash
# Статус
systemctl status wdtt-panel

# Логи в реальном времени
journalctl -u wdtt-panel -f

# Перезапуск
systemctl restart wdtt-panel

# Остановить
systemctl stop wdtt-panel
```

## Настройка

После установки создаётся файл `/opt/wdtt-panel/.env`:

```env
NODE_ENV=production
PORT=8080
FRONTEND_PORT=26208
SESSION_SECRET=<автогенерируется>
CHROMIUM_PATH=/usr/bin/chromium
SOCKS5_PORT=10808
HTTP_PORT=10809
```

После изменения `.env` — перезапустить: `systemctl restart wdtt-panel`

## Порты

| Назначение     | Порт  |
|----------------|-------|
| API сервер     | 8080  |
| Веб-панель     | 26208 |
| SOCKS5 прокси  | 10808 |
| HTTP CONNECT   | 10809 |

## Использование SOCKS5 с 3x-ui / xray

В панели во вкладке "Конфиг" — скопировать готовый outbound JSON и добавить в xray config.

Пример routing rule для направления трафика через туннель:

```json
{
  "type": "field",
  "outboundTag": "vk-tunnel",
  "domain": ["domain:vk.com", "domain:userapi.com", "domain:vk-cdn.net"]
}
```

## Капча

При первом подключении к VK звонку может появиться капча:

- **Авто режим (WBV)** — нажать "АВТО КАПЧА", панель попробует кликнуть сама
- **Ручной режим** — кликнуть по скриншоту браузера в нужном месте

## Сборка из исходников

```bash
# Клонировать
git clone https://github.com/YOUR_USERNAME/wdtt-panel.git
cd wdtt-panel

# Зависимости
npm install -g pnpm
pnpm install

# Codegen (после изменений OpenAPI)
pnpm --filter @workspace/api-spec run codegen

# Запуск в режиме разработки
pnpm --filter @workspace/api-server run dev   # API на :8080
pnpm --filter @workspace/vk-tunnel-panel run dev  # Панель на :26208

# Сборка
pnpm --filter @workspace/api-server run build
pnpm --filter @workspace/vk-tunnel-panel run build
```

## Лицензия

MIT
