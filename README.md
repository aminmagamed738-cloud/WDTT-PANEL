# WDTT Panel

**VPN-туннель через звонки ВКонтакте** — веб-панель управления для VPS.

WDTT (White-list Double Tunnel Technology) использует инфраструктуру VK-звонков как транспортный слой. Серверы VK находятся в белых списках российских ISP — трафик проходит даже при жёстких блокировках. Интегрируется с 3x-ui / VLESS.

---

## Установка на VPS (Linux) — одна команда

> Работает на **Ubuntu, Debian, CentOS, RHEL, Fedora, Rocky, AlmaLinux, Alpine, Arch** и других дистрибутивах.  
> Запускать от root (на VPS вы уже root).

```bash
curl -fsSL https://raw.githubusercontent.com/aminmagamed738-cloud/WDTT-PANEL/main/scripts/quick-install.sh | bash
```

Скрипт автоматически:
- Определит вашу операционную систему
- Установит Node.js 20, если его нет (или обновит старую версию)
- Скачает последнюю версию панели с GitHub
- Установит зависимости
- Создаст systemd сервис с **автозапуском после перезагрузки**
- Откроет нужный порт в файрволе (ufw / firewalld / iptables)
- Покажет ссылку и пароль

После установки откройте в браузере адрес, который покажет скрипт.

---

## Обновление

```bash
curl -fsSL https://raw.githubusercontent.com/aminmagamed738-cloud/WDTT-PANEL/main/scripts/quick-install.sh | bash
```

> Скрипт сохраняет ваш пароль при обновлении.

---

## Удаление (полное)

```bash
curl -fsSL https://raw.githubusercontent.com/aminmagamed738-cloud/WDTT-PANEL/main/scripts/uninstall.sh | bash
```

Или вручную (от root):

```bash
# Остановить и отключить сервис
systemctl stop wdtt-panel
systemctl disable wdtt-panel

# Удалить файл сервиса
rm -f /etc/systemd/system/wdtt-panel.service
systemctl daemon-reload

# Удалить файлы панели
rm -rf /opt/wdtt-panel

# Закрыть порт в файрволе (если нужно)
ufw delete allow 7474/tcp                                                      # для ufw
firewall-cmd --permanent --remove-port=7474/tcp && firewall-cmd --reload       # для firewalld
```

---

## Установка вручную из репозитория

```bash
git clone https://github.com/aminmagamed738-cloud/WDTT-PANEL.git
cd WDTT-PANEL
bash scripts/install.sh
```

---

## Запуск без установки (для теста)

### Linux / macOS
```bash
git clone https://github.com/aminmagamed738-cloud/WDTT-PANEL.git
cd WDTT-PANEL
bash start.sh
```

### Windows
```bat
git clone https://github.com/aminmagamed738-cloud/WDTT-PANEL.git
cd WDTT-PANEL
start.bat
```

### Вручную
```bash
cd server
npm install
node index.js
# Указать свой порт:
node index.js 8080
```

---

## Как пользоваться

1. Запустите панель — в консоли появится **ссылка** и **пароль**
2. Откройте ссылку в браузере
3. Введите пароль и войдите
4. Вставьте **ссылки на звонки ВКонтакте** (одну или несколько)
5. Нажмите **«Тестировать каналы»** — панель проверит пинг и скорость
6. Выберите **мощность** (1–10 потоков)
7. Нажмите **«Запустить туннель»** — смотрите логи в реальном времени
8. После запуска скопируйте конфигурацию для **3x-ui**

---

## Интеграция с 3x-ui (VLESS + маршрутизация)

После запуска туннеля в панели появится раздел **«Интеграция с 3x-ui»** с готовыми блоками JSON.

1. Откройте 3x-ui → Настройки → Xray конфигурация
2. В `"outbounds"` добавьте блок SOCKS5 (из панели)
3. В `"routing" → "rules"` добавьте правило (из панели)
4. Сохраните, перезапустите Xray

Российский трафик пойдёт через VK-туннель, остальной — напрямую.

---

## Управление сервисом (после установки на VPS)

```bash
# Статус
systemctl status wdtt-panel

# Логи в реальном времени
journalctl -u wdtt-panel -f

# Рестарт
systemctl restart wdtt-panel

# Остановить
systemctl stop wdtt-panel

# Запустить снова
systemctl start wdtt-panel

# Обновить с GitHub
cd /opt/wdtt-panel && git pull && systemctl restart wdtt-panel
```

---

## Смена порта

```bash
# Через переменную окружения
PORT=8080 node server/index.js

# Или аргументом
node server/index.js 8080
```

Чтобы изменить порт у systemd-сервиса — отредактируйте `/etc/systemd/system/wdtt-panel.service`, замените порт в строке `ExecStart`, затем:

```bash
systemctl daemon-reload
systemctl restart wdtt-panel
```

Панель автоматически переключится на другой свободный порт, если выбранный занят.

---

## Пароль

Пароль хранится в файле `server/.wdtt-password` (генерируется автоматически при первом запуске).

```bash
# Посмотреть пароль
cat /opt/wdtt-panel/server/.wdtt-password

# Сбросить пароль (будет сгенерирован новый при рестарте)
rm /opt/wdtt-panel/server/.wdtt-password
systemctl restart wdtt-panel
journalctl -u wdtt-panel -n 10
```

---

## Требования

| Компонент | Минимум |
|-----------|---------|
| Node.js   | 18+     |
| RAM       | 256 МБ  |
| Место     | 50 МБ   |
| ОС        | Linux (systemd / OpenRC) |
| Порт      | 7474 (или любой свободный) |

Node.js устанавливается **автоматически** скриптом установки.

---

## Структура проекта

```
WDTT-PANEL/
├── server/
│   ├── index.js          # Express + WebSocket сервер
│   ├── package.json
│   └── public/
│       └── index.html    # Фронтенд (без сборки)
├── scripts/
│   ├── install.sh        # Установка из локальной папки
│   ├── quick-install.sh  # Установка с GitHub (одна команда)
│   └── uninstall.sh      # Полное удаление
├── start.sh              # Быстрый запуск Linux/macOS
├── start.bat             # Быстрый запуск Windows
└── README.md
```

---

## Поддерживаемые ОС

| ОС | Версии |
|----|--------|
| Ubuntu | 20.04, 22.04, 24.04 |
| Debian | 10, 11, 12, 13 |
| CentOS | 7, 8, 9 (Stream) |
| Rocky Linux | 8, 9 |
| AlmaLinux | 8, 9 |
| Fedora | 38, 39, 40, 41 |
| RHEL | 8, 9 |
| Alpine Linux | 3.16+ |
| Arch Linux | актуальный |
| openSUSE | Leap, Tumbleweed |
| Raspberry Pi OS | Bullseye, Bookworm |
