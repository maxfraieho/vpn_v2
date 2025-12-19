# 🔍 Tailscale Proxy Watchdog

Система моніторингу VPN/Proxy сервісу, що працює на Termux через Tailscale мережу.

## 📋 Зміст

- [Архітектура](#архітектура)
- [Встановлення](#встановлення)
- [Налаштування](#налаштування)
- [Використання](#використання)
- [Troubleshooting](#troubleshooting)

---

## 🏗️ Архітектура

```
┌──────────────┐         ┌──────────────┐
│ Debian x86   │ ◄─────► │   Termux     │
│  Watchdog    │ Monitor │ VPN/Proxy    │
│  Server      │         │ 100.100.74.9 │
└──────────────┘         └──────────────┘
       │
       │ HTTP Check via Tailscale
       ▼
┌──────────────┐
│  Cloudflare  │────────▶ Telegram Bot
│   Worker     │  Notify
└──────────────┘
```

**Компоненти:**
- **Debian Server**: Запускає Watchdog скрипт кожні 20 хвилин
- **Termux Device**: VPN/Proxy сервіс в Tailscale мережі
- **Cloudflare Worker**: Проксі для Telegram сповіщень
- **Telegram Bot**: Отримання alerts

---

## 🚀 Встановлення

### Крок 1: Підготовка системи

```bash
# Оновлення Debian
sudo apt update && sudo apt upgrade -y

# Встановлення залежностей
sudo apt install -y curl jq bc git

# Встановлення Tailscale (якщо не встановлено)
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

### Крок 2: Перевірка Tailscale

```bash
# Перевірка статусу
tailscale status

# Перевірка доступності Termux пристрою
ping -c 3 100.100.74.9

# Перевірка порту проксі
curl -v http://100.100.74.9:8888
```

### Крок 3: Створення Telegram бота

1. Відкрийте [@BotFather](https://t.me/BotFather) в Telegram
2. Надішліть `/newbot`
3. Вкажіть ім'я та username бота
4. Збережіть токен (формат: `1234567890:ABC...`)

Отримання Chat ID:
```bash
# Спосіб 1: Через бота
# Надішліть повідомлення @userinfobot

# Спосіб 2: Через API
curl "https://api.telegram.org/bot<TOKEN>/getUpdates"
```

### Крок 4: Cloudflare Worker

1. Зайдіть на https://dash.cloudflare.com
2. Workers & Pages → Create Application → Create Worker
3. Скопіюйте код з артефакту `cloudflare-worker`
4. Deploy
5. Збережіть URL Worker

### Крок 5: Встановлення Watchdog

```bash
# Створення структури
sudo mkdir -p /opt/watchdog/logs
sudo chown -R $USER:$USER /opt/watchdog

# Завантаження скриптів
cd /opt/watchdog

# Скопіюйте watchdog.sh з артефакту
nano watchdog.sh
# Вставте код, заповніть конфігурацію

# Зробіть виконуваним
chmod +x watchdog.sh
```

---

## ⚙️ Налаштування

### Редагування конфігурації

```bash
nano /opt/watchdog/watchdog.sh
```

**Обов'язкові параметри:**

```bash
PROXY_HOST="100.100.74.9"          # IP Termux в Tailscale
PROXY_PORT="8888"                  # Порт проксі
PROXY_TYPE="http"                  # http/socks5/socks4
WORKER_URL="https://..."           # URL Cloudflare Worker
TELEGRAM_TOKEN="..."               # Токен бота
TELEGRAM_CHAT_ID="..."             # Chat ID
```

### Налаштування типу проксі

**HTTP Proxy (Tinyproxy, Privoxy):**
```bash
PROXY_PORT="8888"
PROXY_TYPE="http"
```

**SOCKS5 Proxy:**
```bash
PROXY_PORT="1080"
PROXY_TYPE="socks5"
```

**Squid Proxy:**
```bash
PROXY_PORT="3128"
PROXY_TYPE="http"
```

### Systemd сервіси

```bash
# Створення service
sudo nano /etc/systemd/system/watchdog-proxy.service
# Вставте код з артефакту systemd-service
# Замініть YOUR_USERNAME на ваш username

# Створення timer
sudo nano /etc/systemd/system/watchdog-proxy.timer
# Вставте код з артефакту systemd-timer

# Активація
sudo systemctl daemon-reload
sudo systemctl enable watchdog-proxy.timer
sudo systemctl start watchdog-proxy.timer
```

---

## 📊 Використання

### Базові команди

```bash
# Перевірка статусу
sudo systemctl status watchdog-proxy.timer

# Перегляд логів (реальний час)
tail -f /opt/watchdog/logs/watchdog.log

# Ручний запуск перевірки
sudo systemctl start watchdog-proxy.service

# Перезапуск служби
sudo systemctl restart watchdog-proxy.timer

# Зупинка служби
sudo systemctl stop watchdog-proxy.timer
```

### Dashboard

```bash
# Створення dashboard скрипта
nano /opt/watchdog/dashboard.sh
# Вставте код з артефакту dashboard-script

chmod +x /opt/watchdog/dashboard.sh

# Запуск dashboard
/opt/watchdog/dashboard.sh
```

### Перегляд метрик

```bash
# JSON метрики
cat /opt/watchdog/logs/metrics.json | jq .

# Останні 10 подій
cat /opt/watchdog/logs/metrics.json | jq '.[-10:]'

# Розрахунок uptime
cat /opt/watchdog/logs/metrics.json | jq '
  [.[] | select(.status == "up")] | length as $up |
  length as $total |
  ($up / $total * 100)
'
```

### Ротація логів

```bash
# Створення скрипта ротації
nano /opt/watchdog/rotate_logs.sh
# Вставте код з артефакту log-rotation-script

chmod +x /opt/watchdog/rotate_logs.sh

# Додавання в crontab (щодня о 3:00)
crontab -e
# Додайте:
0 3 * * * /opt/watchdog/rotate_logs.sh
```

---

## 🔧 Troubleshooting

### Проблема: Не приходять сповіщення

**Діагностика:**
```bash
# 1. Перевірка токена
curl "https://api.telegram.org/bot<TOKEN>/getMe"

# 2. Тест Worker
curl -X POST https://your-worker.workers.dev \
  -H "Content-Type: application/json" \
  -d '{
    "token": "TEST",
    "chat_id": "TEST",
    "message": "Test"
  }'

# 3. Перевірка логів
tail -f /opt/watchdog/logs/watchdog.log | grep "Telegram"
```

### Проблема: Проксі завжди "недоступний"

**Перевірка:**
```bash
# 1. Перевірка Tailscale
tailscale status | grep 100.100.74.9

# 2. Перевірка порту
nc -zv 100.100.74.9 8888

# 3. Тест через curl
curl -v http://100.100.74.9:8888

# 4. Для SOCKS5
curl --socks5 100.100.74.9:1080 http://example.com
```

**Рішення:**
- Перевірте, чи працює проксі на Termux
- Переконайтеся, що правильний порт
- Перевірте firewall на Termux
- Переконайтеся, що Tailscale активний

### Проблема: Timer не запускається

**Діагностика:**
```bash
# Статус timer
sudo systemctl status watchdog-proxy.timer

# Список всіх timers
sudo systemctl list-timers --all

# Логи systemd
journalctl -u watchdog-proxy.timer -f
journalctl -u watchdog-proxy.service -f

# Перевірка синтаксису
sudo systemd-analyze verify watchdog-proxy.service
sudo systemd-analyze verify watchdog-proxy.timer
```

**Рішення:**
```bash
# Перезавантаження
sudo systemctl daemon-reload
sudo systemctl restart watchdog-proxy.timer

# Повне очищення та рестарт
sudo systemctl stop watchdog-proxy.timer
sudo systemctl disable watchdog-proxy.timer
sudo systemctl daemon-reload
sudo systemctl enable watchdog-proxy.timer
sudo systemctl start watchdog-proxy.timer
```

### Проблема: Високе використання ресурсів

**Оптимізація:**

1. Збільште інтервал перевірки:
```bash
sudo nano /etc/systemd/system/watchdog-proxy.timer
# Змініть OnUnitActiveSec=20min на 30min або більше
```

2. Обмежте ресурси:
```bash
sudo nano /etc/systemd/system/watchdog-proxy.service
# Додайте:
MemoryLimit=128M
CPUQuota=30%
```

3. Обмежте логування:
```bash
# У watchdog.sh закоментуйте рядки з DEBUG
sed -i 's/log "DEBUG"/# log "DEBUG"/' /opt/watchdog/watchdog.sh
```

---

## 📱 Формат сповіщень

### При збої:
```
🚨 PROXY WATCHDOG ALERT

🚨 *PROXY DOWN DETECTED*

🕐 Час: `2025-12-13 14:35:22`
🌐 Проксі: `http://100.100.74.9:8888`
❌ Причина: Немає відповіді від сервера
🔄 Спроб підключення: 3
📡 Tailscale: `Пристрій не в мережі`
📊 Статус: OFFLINE
```

### При відновленні:
```
🚨 PROXY WATCHDOG ALERT

✅ *PROXY RECOVERED*

🕐 Час: `2025-12-13 14:42:10`
🌐 Проксі: `http://100.100.74.9:8888`
⏱ Час простою: 6хв 48с
📊 Uptime: 98.50%
⚡ Час відповіді: 0.123s
📈 Статус: ONLINE
```

---

## 🔐 Безпека

### Захист токенів

**Метод 1: Environment файл**
```bash
# Створення .env
nano /opt/watchdog/.env
# Вставте конфігурацію

# Обмеження прав
chmod 600 /opt/watchdog/.env

# У watchdog.sh додайте:
source /opt/watchdog/.env
```

**Метод 2: Systemd Environment**
```bash
sudo nano /etc/systemd/system/watchdog-proxy.service

# Додайте в секцію [Service]:
Environment="TELEGRAM_TOKEN=your_token"
Environment="TELEGRAM_CHAT_ID=your_chat_id"
```

### Обмеження доступу

```bash
# Права на директорію
sudo chown -R $USER:$USER /opt/watchdog
chmod 750 /opt/watchdog
chmod 640 /opt/watchdog/.env

# Права на скрипти
chmod 750 /opt/watchdog/*.sh
```

---

## 📈 Моніторинг та метрики

### Статистика uptime

```bash
# Uptime за весь час
cat /opt/watchdog/logs/metrics.json | jq '
  [.[] | select(.status == "up")] | length as $up |
  length as $total |
  "\($up)/\($total) = \(($up/$total*100*100|round)/100)%"
'

# Uptime за останні 24 години
time_24h=$(date -d '24 hours ago' +%s)
cat /opt/watchdog/logs/metrics.json | jq --arg time "$time_24h" '
  [.[] | select(.timestamp > ($time|tonumber))] |
  [.[] | select(.status == "up")] | length as $up |
  length as $total |
  "\($up)/\($total) = \(($up/$total*100*100|round)/100)%"
'
```

### Середній час відповіді

```bash
cat /opt/watchdog/logs/metrics.json | jq '
  [.[] | select(.status == "up") | .response_time | tonumber] |
  (add / length * 1000 | round) / 1000
'
```

### Експорт метрик

```bash
# CSV формат
cat /opt/watchdog/logs/metrics.json | jq -r '
  ["timestamp","datetime","status","response_time"],
  (.[] | [.timestamp, .datetime, .status, .response_time]) |
  @csv
' > metrics.csv
```

---

## 🔄 Оновлення

```bash
# Зупинка служби
sudo systemctl stop watchdog-proxy.timer

# Backup поточної конфігурації
cp /opt/watchdog/watchdog.sh /opt/watchdog/watchdog.sh.backup

# Оновлення скрипта
nano /opt/watchdog/watchdog.sh
# Вставте новий код

# Перезапуск
sudo systemctl daemon-reload
sudo systemctl start watchdog-proxy.timer
```

---

## 📞 Підтримка

**Логи для діагностики:**
```bash
# Системні логи
journalctl -u watchdog-proxy.service -n 100

# Watchdog логи
tail -n 100 /opt/watchdog/logs/watchdog.log

# Метрики
cat /opt/watchdog/logs/metrics.json | jq '.[-10:]'
```

**Корисні посилання:**
- [Tailscale Docs](https://tailscale.com/kb/)
- [Telegram Bot API](https://core.telegram.org/bots/api)
- [Cloudflare Workers](https://developers.cloudflare.com/workers/)

---

## 📄 Ліцензія

MIT License - використовуйте вільно для особистих та комерційних проектів.

---

**Версія:** 1.0.0  
**Остання оновлення:** 2025-12-13