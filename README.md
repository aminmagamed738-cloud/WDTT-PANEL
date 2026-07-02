# WDTT Panel — VK Tunnel Management

Веб-панель управления VPN-туннелем через инфраструктуру звонков ВКонтакте.

## Что делает

- Подключается к VK звонку через headless Chromium
- Создаёт SOCKS5 (порт 10808) и HTTP CONNECT (порт 10809) прокси на VPS
- Туннелирует трафик через TURN-серверы VK звонков
- Генерирует готовый конфиг для 3x-ui / xray
- Стриминг логов в реальном времени
- Авто-капча (WBV) + ручной режим

## Требования

- Ubuntu 20.04+ / Debian 11+, root
- Node.js 20+ (установится автоматически)
- Chromium (установится автоматически)
- Порты: 8080, 10808, 10809

## Установка

```sh
curl -fsSL https://raw.githubusercontent.com/aminmagamed738-cloud/WDTT-PANEL/main/install.sh | sh
```

Или вручную из клона:

```sh
git clone https://github.com/aminmagamed738-cloud/WDTT-PANEL.git
cd WDTT-PANEL
sh install.sh
```

## Управление

```sh
systemctl status wdtt-panel
systemctl restart wdtt-panel
systemctl stop wdtt-panel
journalctl -u wdtt-panel -f
```

## Настройка `/opt/wdtt-panel/.env`

```env
NODE_ENV=production
PORT=8080
SESSION_SECRET=<автогенерируется>
CHROMIUM_PATH=/usr/bin/chromium
SOCKS5_PORT=10808
HTTP_PORT=10809
```

После изменения:

```sh
systemctl restart wdtt-panel
```

## Порты

| Назначение    | Порт  |
|---------------|-------|
| API / панель  | 8080  |
| SOCKS5 прокси | 10808 |
| HTTP прокси   | 10809 |

## Использование с 3x-ui / xray

В панели вкладка "Конфиг" — скопировать outbound JSON в xray config.

## Капча

- **Авто (WBV)** — кнопка "АВТО КАПЧА", панель кликает сама
- **Ручной** — кликнуть по скриншоту браузера

## Полное удаление

```sh
systemctl stop wdtt-panel
systemctl disable wdtt-panel
rm -f /etc/systemd/system/wdtt-panel.service
systemctl daemon-reload
rm -rf /opt/wdtt-panel
echo "WDTT Panel удалён"
```

## Лицензия

MIT
