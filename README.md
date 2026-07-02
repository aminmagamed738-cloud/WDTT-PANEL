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
- Открытые порты: 8080 (API), 10808 (SOCKS5), 10809 (HTTP)

## Установка одной командой

```sh
curl -fsSL https://raw.githubusercontent.com/aminmagamed738-cloud/WDTT-PANEL/main/install.sh | sh
```

## Управление сервисом

```sh
systemctl status wdtt-panel
journalctl -u wdtt-panel -f
systemctl restart wdtt-panel
systemctl stop wdtt-panel
```

## Настройка

После установки: `/opt/wdtt-panel/.env`

```env
NODE_ENV=production
PORT=8080
SESSION_SECRET=<автогенерируется>
CHROMIUM_PATH=/usr/bin/chromium
SOCKS5_PORT=10808
HTTP_PORT=10809
```

После изменения `.env`: `systemctl restart wdtt-panel`

## Порты

| Назначение     | Порт  |
|----------------|-------|
| API сервер     | 8080  |
| SOCKS5 прокси  | 10808 |
| HTTP CONNECT   | 10809 |

## Использование с 3x-ui / xray

В панели во вкладке "Конфиг" — скопировать готовый outbound JSON и добавить в xray config.

## Капча

- **Авто режим (WBV)** — нажать "АВТО КАПЧА", панель попробует кликнуть сама
- **Ручной режим** — кликнуть по скриншоту браузера в нужном месте

## Сборка из исходников

```sh
git clone https://github.com/aminmagamed738-cloud/WDTT-PANEL.git
cd WDTT-PANEL
npm install -g pnpm
pnpm install
pnpm --filter @workspace/api-server run dev
pnpm --filter @workspace/vk-tunnel-panel run dev
```

## Лицензия

MIT
