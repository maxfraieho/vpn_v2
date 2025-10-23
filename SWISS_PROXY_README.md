# Swiss Proxy System - Інструкція користування

## Огляд системи

Система надає доступ до швейцарського інтернету з України через три акаунти з різними IP адресами.

### Доступні акаунти:

1. **arsen.k111999@gmail.com** - Прямий доступ (Український IP)
   - HTTP Proxy: `http://100.100.74.9:8888`
   - SOCKS5 Proxy: `socks5://100.100.74.9:9888`
   - IP: `46.253.188.140`

2. **lekov00@gmail.com** - Через Tor (Швейцарський IP)
   - HTTP Proxy: `http://100.100.74.9:8889`
   - SOCKS5 Proxy: `socks5://100.100.74.9:9890`
   - IP: `185.195.71.244` (змінюється через Tor)

3. **tukroschu@gmail.com** - Через Tor (Швейцарський IP)
   - HTTP Proxy: `http://100.100.74.9:8890`
   - SOCKS5 Proxy: `socks5://100.100.74.9:9891`
   - IP: `185.195.71.244` (змінюється через Tor)

## Запуск серверів (Termux на Android)

### 1. Запуск HTTP/HTTPS проксі:
```bash
cd /data/data/com.termux/files/home/vpn_v2
python3 swiss_proxy_stream.py
```

Або у фоні:
```bash
nohup python3 swiss_proxy_stream.py > /dev/null 2>&1 &
```

### 2. Запуск SOCKS5 проксі:
```bash
cd /data/data/com.termux/files/home/vpn_v2
python3 swiss_socks5_proxy.py
```

Або у фоні:
```bash
nohup python3 swiss_socks5_proxy.py > /dev/null 2>&1 &
```

### 3. Перевірка статусу:
```bash
# Перевірити чи працюють сервери
ps aux | grep -E "(swiss_proxy|socks5)" | grep -v grep

# Перевірити логи
tail -f proxy.log       # HTTP/HTTPS логи
tail -f socks5_proxy.log  # SOCKS5 логи
```

### 4. Зупинка серверів:
```bash
pkill -f swiss_proxy_stream.py
pkill -f swiss_socks5_proxy.py
```

## Використання на Windows

### Доступні батники:

#### Для Comet Browser:
1. **`start_comet_swiss_direct.bat`** - arsen.k111999@gmail.com (прямий, український IP)
2. **`start_comet_swiss_tor.bat`** - lekov00@gmail.com (Tor, швейцарський IP)
3. **`start_comet_tukroschu.bat`** - tukroschu@gmail.com (Tor, швейцарський IP)

#### Для Google Chrome:
1. **`start_chrome_swiss_direct.bat`** - arsen.k111999@gmail.com (прямий, український IP)
2. **`start_chrome_swiss_tor.bat`** - lekov00@gmail.com (Tor, швейцарський IP)
3. **`start_chrome_tukroschu.bat`** - tukroschu@gmail.com (Tor, швейцарський IP)

### Варіант 3: Ручна конфігурація Chrome/Edge

#### Для прямого доступу (порт 9888):
```
chrome.exe --proxy-server="socks5://100.100.74.9:9888" --user-data-dir="%TEMP%\chrome-swiss-direct"
```

#### Для Tor доступу (порт 9889):
```
chrome.exe --proxy-server="socks5://100.100.74.9:9889" --user-data-dir="%TEMP%\chrome-swiss-tor"
```

## Тестування з командного рядка

### Windows PowerShell/CMD:

#### Тест HTTP проксі:
```cmd
curl -x http://100.100.74.9:8888 https://api.ipify.org
curl -x http://100.100.74.9:8889 https://api.ipify.org
curl -x http://100.100.74.9:8890 https://api.ipify.org
```

#### Тест SOCKS5 проксі:
```cmd
curl --socks5 100.100.74.9:9888 https://api.ipify.org
curl --socks5 100.100.74.9:9890 https://api.ipify.org
curl --socks5 100.100.74.9:9891 https://api.ipify.org
```

### Linux/Mac:

```bash
# HTTP проксі
curl -x http://100.100.74.9:8888 https://api.ipify.org  # arsen (український IP)
curl -x http://100.100.74.9:8889 https://api.ipify.org  # lekov00 (швейцарський IP)
curl -x http://100.100.74.9:8890 https://api.ipify.org  # tukroschu (швейцарський IP)

# SOCKS5 проксі
curl --socks5 100.100.74.9:9888 https://api.ipify.org   # arsen (український IP)
curl --socks5 100.100.74.9:9890 https://api.ipify.org   # lekov00 (швейцарський IP)
curl --socks5 100.100.74.9:9891 https://api.ipify.org   # tukroschu (швейцарський IP)
```

## Архітектура системи

```
┌─────────────────────────────────────────────────────┐
│            Android Termux Server                     │
│  ┌────────────────────┐  ┌────────────────────┐    │
│  │   HTTP/HTTPS       │  │   SOCKS5           │    │
│  │   Port 8888/8889   │  │   Port 9888/9889   │    │
│  └────────┬───────────┘  └────────┬───────────┘    │
│           │                        │                 │
│           └────────┬───────────────┘                 │
│                    │                                 │
│         ┌──────────▼──────────┐                     │
│         │  Router/Dispatcher  │                     │
│         └──────────┬──────────┘                     │
│                    │                                 │
│         ┏━━━━━━━━━━┻━━━━━━━━━━┓                    │
│         ┃                      ┃                    │
│    ┌────▼─────┐          ┌────▼─────┐              │
│    │  Direct  │          │   Tor    │              │
│    │ (8888/   │          │  (8889/  │              │
│    │  9888)   │          │   9889)  │              │
│    └────┬─────┘          └────┬─────┘              │
│         │                      │                    │
└─────────┼──────────────────────┼────────────────────┘
          │                      │
          │                      │
     ┌────▼────┐            ┌───▼────┐
     │Ukrainian│            │ Swiss  │
     │   IP    │            │   IP   │
     │46.253...│            │81.17...│
     └─────────┘            └────────┘
```

## Виправлені проблеми

### Помилка 56 (SSL wrong version number)
**Причина:** HTTP заголовки CONNECT запиту не читалися повністю, залишалися в буфері і передавалися на цільовий сервер як частина SSL handshake.

**Рішення:** Додано читання всіх HTTP заголовків до порожнього рядка перед встановленням тунелю (`swiss_proxy_stream.py:86-95`).

### Дублювання портів
**Причина:** При пошуку вільних портів не відстежувалися вже виділені порти, через що обидва акаунти отримували один порт.

**Рішення:** Додано `self.used_ports` для відстеження виділених портів (`swiss_proxy_stream.py:46, 64`).

## Логи та діагностика

### Файли логів:
- `/data/data/com.termux/files/home/vpn_v2/proxy.log` - HTTP/HTTPS проксі
- `/data/data/com.termux/files/home/vpn_v2/socks5_proxy.log` - SOCKS5 проксі

### Перегляд логів в реальному часі:
```bash
tail -f proxy.log
tail -f socks5_proxy.log
```

### Перевірка портів:
```bash
netstat -tlnp | grep -E '(8888|8889|9888|9889)'
```

## Налаштування

Конфігурація зберігається в `config.json`:

```json
{
  "accounts": {
    "arsen.k111999@gmail.com": {
      "email": "arsen.k111999@gmail.com",
      "proxy_port": 8888,
      "upstream": {
        "type": "direct",
        "name": "Tailscale Direct"
      }
    },
    "lekov00@gmail.com": {
      "email": "lekov00@gmail.com",
      "proxy_port": 8889,
      "upstream": {
        "type": "tor",
        "socks_host": "127.0.0.1",
        "socks_port": 9050,
        "name": "Direct Tor Connection"
      }
    },
    "tukroschu@gmail.com": {
      "email": "tukroschu@gmail.com",
      "proxy_port": 8890,
      "upstream": {
        "type": "tor",
        "socks_host": "127.0.0.1",
        "socks_port": 9050,
        "name": "Direct Tor Connection"
      }
    }
  },
  "tailscale_ip": "100.100.74.9"
}
```

## Підтримка

Якщо виникли проблеми:

1. Перевірте чи працюють сервери: `ps aux | grep swiss`
2. Перевірте логи: `tail -50 proxy.log` та `tail -50 socks5_proxy.log`
3. Перевірте Tor (для порту 8889/9889): `systemctl status tor` або `ps aux | grep tor`
4. Перевірте з'єднання: `curl --socks5 127.0.0.1:9888 https://api.ipify.org`

## Автозапуск

Для автозапуску при завантаженні системи, додайте до `~/.bashrc`:

```bash
# Автозапуск Swiss Proxy
cd /data/data/com.termux/files/home/vpn_v2
nohup python3 swiss_proxy_stream.py > /dev/null 2>&1 &
nohup python3 swiss_socks5_proxy.py > /dev/null 2>&1 &
```
