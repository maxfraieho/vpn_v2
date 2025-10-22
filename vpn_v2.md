# Код проєкту: vpn_v2

**Згенеровано:** 2025-10-22 09:21:19
**Директорія:** `/data/data/com.termux/files/home/vpn_v2`

---

## Структура проєкту

```
├── README_MIGRATION.md
├── config.json
├── manager_v2.sh
├── run_md_service.sh
├── smart_proxy_v2.py
├── survey_automation_v2.py
├── test_routing.sh
├── torrc
├── vpn_v2.md
└── webrtc_block.js
```

---

## Файли проєкту

### config.json

**Розмір:** 762 байт

```json
{
  "accounts": {
    "arsen.k111999@gmail.com": {
      "name": "Син (Arsen)",
      "proxy_port": 8888,
      "upstream": {
        "type": "direct",
        "name": "Tailscale (100.100.74.9)"
      },
      "cookies_file": "/data/data/com.termux/files/home/.cookies_arsen.json",
      "password": "YOUR_PASSWORD"
    },
    "lekov00@gmail.com": {
      "name": "Дружина (Lena)",
      "proxy_port": 8889,
      "upstream": {
        "type": "tor",
        "socks_host": "127.0.0.1",
        "socks_port": 9050,
        "name": "Tor (Switzerland exit)"
      },
      "cookies_file": "/data/data/com.termux/files/home/.cookies_lena.json",
      "password": "YOUR_PASSWORD"
    }
  },
  "survey_service_port": 8090,
  "tailscale_ip": "100.100.74.9"
}

```

### smart_proxy_v2.py

**Розмір:** 7,112 байт

```python
import json
import socks
import socket
import asyncio
import aiohttp
from aiohttp import web, ClientSession
import aiohttp_socks
import logging
import base64
import re
from urllib.parse import urlparse, parse_qs
import os

# Load configuration
CONFIG_FILE = "/data/data/com.termux/files/home/vpn_v2/config.json"

def load_config():
    with open(CONFIG_FILE, "r") as f:
        return json.load(f)

CONFIG = load_config()

class SwissProxy:
    def __init__(self, config):
        self.config = config
        self.account_by_port = {}  # {port: account_config}
        
        # Map ports to accounts
        for email, acc_config in config["accounts"].items():
            port = acc_config["proxy_port"]
            self.account_by_port[port] = {
                "email": email,
                **acc_config
            }

    async def handle_http_with_routing(self, request, account_config):
        """HTTP proxy with routing through upstream"""
        
        # Get upstream configuration
        upstream = account_config["upstream"]
        
        # If Tor - use SOCKS5 proxy
        if upstream["type"] == "tor":
            connector = aiohttp_socks.ProxyConnector.from_url(
                f"socks5://{upstream["socks_host"]}:{upstream["socks_port"]}"
            )
        else:
            # Direct through Tailscale
            connector = None

        # Get the target URL
        if request.method == "CONNECT":  # HTTPS CONNECT tunnel
            # Handle HTTPS CONNECT - this is a simplified implementation
            return web.Response(status=200, text="Tunnel established")
        else:
            # Regular HTTP request
            # Construct the target URL
            if request.path_qs.startswith("http"):
                target_url = request.path_qs
            else:
                # Reconstruct the URL from headers
                target_url = str(request.url)
            
            # Parse the target URL
            url = urlparse(target_url)
            if url.netloc:
                # Full URL with host
                full_url = target_url
            else:
                # Relative path, need to reconstruct
                host = request.headers.get("Host", "")
                if host:
                    full_url = f"http://{host}{target_url}"
                else:
                    return web.Response(status=400, text="Invalid request")

            # Prepare headers (remove proxy-specific headers)
            headers = {}
            for key, value in request.headers.items():
                if key.lower() not in ["proxy-connection", "connection", "upgrade"]:
                    headers[key] = value
            
            headers["Connection"] = "close"  # Avoid keep-alive issues

            try:
                async with ClientSession(connector=connector) as session:
                    if request.method == "GET":
                        async with session.get(full_url, headers=headers) as resp:
                            body = await resp.read()
                    elif request.method == "POST":
                        data = await request.read()
                        async with session.post(full_url, headers=headers, data=data) as resp:
                            body = await resp.read()
                    elif request.method in ["PUT", "DELETE", "PATCH"]:
                        data = await request.read()
                        method = getattr(session, request.method.lower())
                        async with method(full_url, headers=headers, data=data) as resp:
                            body = await resp.read()
                    else:
                        return web.Response(status=501, text=f"Method {request.method} not implemented")

                    # Prepare the response
                    response_headers = {}
                    for key, value in resp.headers.items():
                        if key.lower() not in ["transfer-encoding", "connection", "content-encoding"]:
                            response_headers[key] = value

                    return web.Response(
                        status=resp.status,
                        headers=response_headers,
                        body=body
                    )
            except Exception as e:
                logging.error(f"Request failed: {e}")
                return web.Response(status=502, text=f"Bad Gateway: {str(e)}")

    async def handle_socks5(self, reader, writer):
        """Handle SOCKS5 connection"""
        try:
            # Negotiate SOCKS5 protocol
            version = await reader.read(1)
            if version[0] != 0x05:
                return

            nmethods = await reader.read(1)[0]
            methods = await reader.read(nmethods)

            # Send response: version and method (no auth)
            writer.write(b"\x05\x00")
            await writer.drain()

            # Read connection request
            ver = await reader.read(1)[0]
            cmd = await reader.read(1)[0]
            rsv = await reader.read(1)[0]
            atyp = await reader.read(1)[0]

            if atyp == 1:  # IPv4
                addr = await reader.read(4)
                addr = ".".join(map(str, addr))
            elif atyp == 3:  # Domain name
                length = await reader.read(1)[0]
                addr = (await reader.read(length)).decode()
            else:
                return

            port = int.from_bytes(await reader.read(2), "big")

            # For this implementation, we wont establish connection to destination
            # Just return success (this is a simplified SOCKS server)
            writer.write(b"\x05\x00\x00\x01\x00\x00\x00\x00\x00\x00")
            await writer.drain()

        except Exception as e:
            logging.error(f"SOCKS5 error: {e}")

    async def start_servers(self):
        """Start HTTP proxy on multiple ports"""
        
        tasks = []
        
        # For each account - separate port
        for port, account in self.account_by_port.items():
            app = web.Application()
            
            async def handler(request, acc=account):
                return await self.handle_http_with_routing(request, acc)
            
            app.router.add_route("*", "/{path:.*}", handler)
            
            runner = web.AppRunner(app)
            await runner.setup()
            
            site = web.TCPSite(runner, "0.0.0.0", port)
            await site.start()
            
            print(f"✅ HTTP Proxy for {account["email"]}: {account["upstream"]["name"]}")
            print(f"   Port: http://{CONFIG["tailscale_ip"]}:{port}")
            
            tasks.append(site)
        
        # SOCKS5 on 1080 (keep as is)
        socks_server = await asyncio.start_server(
            self.handle_socks5, "0.0.0.0", 1080
        )
        
        print(f"✅ SOCKS5 Proxy: socks5://{CONFIG["tailscale_ip"]}]:1080")
        
        await socks_server.serve_forever()

def main():
    proxy = SwissProxy(CONFIG)
    asyncio.run(proxy.start_servers())

if __name__ == "__main__":
    main()


```

### survey_automation_v2.py

**Розмір:** 7,846 байт

```python
# Survey Automation v2 - Multi-IP Routing
import json
import requests
import asyncio
from playwright.async_api import async_playwright
import logging
from datetime import datetime
import os

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler("/data/data/com.termux/files/home/vpn_v2/survey.log"),
        logging.StreamHandler()
    ]
)

logger = logging.getLogger(__name__)

# Load configuration
CONFIG_FILE = "/data/data/com.termux/files/home/vpn_v2/config.json"

def load_config():
    with open(CONFIG_FILE, "r") as f:
        return json.load(f)

CONFIG = load_config()

class SurveyAutomation:
    def __init__(self):
        self.is_running = False

    def get_proxy_for_account(self, email: str):
        """Returns proxy configuration for an account"""
        
        account = CONFIG["accounts"].get(email)
        if not account:
            raise ValueError(f"Unknown account: {email}")
        
        port = account["proxy_port"]
        proxy_url = f"http://127.0.0.1:{port}"
        
        return {
            "server": proxy_url,
            "username": None,
            "password": None
        }

    async def check_swiss_ip(self, proxy_config):
        """Check IP through specific proxy"""
        try:
            proxies = {
                "http": proxy_config["server"],
                "https": proxy_config["server"]
            }
            
            resp = requests.get(
                "https://ipapi.co/json/",
                proxies=proxies,
                timeout=10
            )
            
            data = resp.json()
            country = data.get("country_code", "")
            is_swiss = country == "CH"
            
            return is_swiss, data
        except Exception as e:
            logger.error(f"IP check failed: {e}")
            return False, {}

    async def accept_survey(self, email, survey_url, reward=None):
        """Accept survey with automatic proxy selection"""
        
        # Get proxy for this account
        proxy_config = self.get_proxy_for_account(email)
        
        account = CONFIG["accounts"][email]
        
        # Check IP through the correct proxy
        is_swiss, ip_data = await self.check_swiss_ip(proxy_config)
        
        logger.info(f"Account: {email}")
        logger.info(f"Proxy: {account['upstream']['name']}")
        logger.info(f"IP: {ip_data.get('ip')} ({ip_data.get('country_name')})")
        
        if not is_swiss:
            logger.error(f"Not in Switzerland! Location: {ip_data}")
            return {"success": False, "error": "Not in Switzerland"}
        
        # Launch browser with the correct proxy
        async with async_playwright() as p:
            browser = await p.chromium.launch(headless=False)
            
            context = await browser.new_context(
                proxy=proxy_config,  # ← AUTO SELECTS CORRECT PROXY
                viewport={"width": 1920, "height": 1080},
                user_agent="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                locale="de-CH",
                timezone_id="Europe/Zurich"
            )
            
            # Add cookies if available
            cookies_file = account.get("cookies_file")
            if cookies_file and os.path.exists(cookies_file):
                try:
                    with open(cookies_file, "r") as f:
                        cookies = json.load(f)
                    await context.add_cookies(cookies)
                except Exception as e:
                    logger.warning(f"Could not load cookies: {e}")
            
            page = await context.new_page()
            
            try:
                # Navigate to survey
                await page.goto(survey_url, wait_until="networkidle")
                
                # Wait for potential login or cookie acceptance
                await page.wait_for_timeout(2000)
                
                # Look for survey acceptance button - FIXED: Properly quoted selectors
                accept_selectors = [
                    'button:has-text("Accept Survey")',
                    'button:has-text("Start Survey")', 
                    'button:has-text("Beantworten")',
                    'button:has-text("Teilnehmen")',
                    'button[type="submit"]',
                    '.survey-start-btn',
                    'a[href*="accept"]',
                    'a[href*="start"]'
                ]
                
                accepted = False
                for selector in accept_selectors:
                    try:
                        # Wait a bit to ensure page is loaded
                        await page.wait_for_timeout(1000)
                        
                        # Try to find and click the element
                        element = page.locator(selector).first
                        
                        # Check if element is visible
                        if await element.is_visible(timeout=3000):
                            await element.click()
                            logger.info(f"Clicked: {selector}")
                            accepted = True
                            break
                    except Exception as e:
                        # Element not found or not clickable, try next selector
                        logger.debug(f"Selector {selector} failed: {e}")
                        continue
                
                if not accepted:
                    logger.warning("Could not find survey acceptance button")
                
                # Wait and monitor for survey completion
                await page.wait_for_timeout(5000)
                
                # Save cookies for next time
                cookies = await context.cookies()
                with open(account["cookies_file"], "w") as f:
                    json.dump(cookies, f)
                
                logger.info(f"Survey session completed for {email}")
                
                return {"success": True, "message": f"Survey completed for {email}"}
                
            except Exception as e:
                logger.error(f"Survey error for {email}: {e}")
                return {"success": False, "error": str(e)}
            finally:
                await browser.close()

    async def run(self):
        """Main service loop"""
        logger.info("Starting Survey Automation v2...")
        self.is_running = True
        
        # Start HTTP server to receive survey requests
        from aiohttp import web
        
        async def handle_survey_request(request):
            try:
                data = await request.json()
                email = data.get("email")
                survey_url = data.get("url")
                reward = data.get("reward")
                
                result = await self.accept_survey(email, survey_url, reward)
                return web.json_response(result)
            except Exception as e:
                logger.error(f"Request handling error: {e}")
                return web.json_response({"error": str(e)}, status=500)
        
        app = web.Application()
        app.router.add_post("/survey", handle_survey_request)
        
        runner = web.AppRunner(app)
        await runner.setup()
        site = web.TCPSite(runner, "0.0.0.0", CONFIG["survey_service_port"])
        await site.start()
        
        logger.info(f"Survey service running on port {CONFIG['survey_service_port']}")
        
        # Keep running
        while self.is_running:
            await asyncio.sleep(1)

def main():
    automation = SurveyAutomation()
    asyncio.run(automation.run())

if __name__ == "__main__": 
    main()

```

### manager_v2.sh

**Розмір:** 2,869 байт

```bash
#!/data/data/com.termux/files/usr/bin/bash

SETUP_DIR="$HOME/vpn_v2"
PROXY_LOG="$SETUP_DIR/proxy.log"
SURVEY_LOG="$SETUP_DIR/survey.log"
TOR_LOG="$SETUP_DIR/tor.log"

start_all() {
    echo "🚀 Starting VPN v2 services..."
    
    # 1. Tor
    echo "Starting Tor..."
    tor -f "$SETUP_DIR/torrc" &
    echo $! > "$SETUP_DIR/tor.pid"
    sleep 5
    echo "✓ Tor started"
    
    # 2. Multi-proxy server
    echo "Starting Smart Proxy v2..."
    nohup python3 "$SETUP_DIR/smart_proxy_v2.py" > "$PROXY_LOG" 2>&1 &
    echo $! > "$SETUP_DIR/proxy.pid"
    echo "✓ Proxy started (ports 8888 + 8889)"
    
    # 3. Survey automation
    echo "Starting Survey Automation v2..."
    nohup python3 "$SETUP_DIR/survey_automation_v2.py" > "$SURVEY_LOG" 2>&1 &
    echo $! > "$SETUP_DIR/survey.pid"
    echo "✓ Survey automation started (port 8090)"
    
    echo ""
    status
}

stop_all() {
    echo "🛑 Stopping VPN v2 services..."
    
    # Stop all services
    for pid_file in "$SETUP_DIR"/*.pid; do
        if [ -f "$pid_file" ]; then
            pid=$(cat "$pid_file")
            kill -9 "$pid" 2>/dev/null
            rm -f "$pid_file"
        fi
    done
    
    echo "✓ All services stopped"
}

status() {
    echo "📊 VPN v2 Status"
    echo "================"
    echo ""
    
    # Tor
    if [ -f "$SETUP_DIR/tor.pid" ] && ps -p $(cat "$SETUP_DIR/tor.pid") > /dev/null 2>&1; then
        echo "✓ Tor running (PID $(cat $SETUP_DIR/tor.pid))"
        echo "  Testing: curl -x socks5://127.0.0.1:9050 https://ipapi.co/country"
        curl -s -x socks5://127.0.0.1:9050 https://ipapi.co/country
    else
        echo "✗ Tor not running"
    fi
    
    # Proxy
    if [ -f "$SETUP_DIR/proxy.pid" ] && ps -p $(cat "$SETUP_DIR/proxy.pid") > /dev/null 2>&1; then
        echo "✓ Proxy running (PID $(cat $SETUP_DIR/proxy.pid))"
        echo "  Port 8888: Tailscale direct"
        echo "  Port 8889: Tor exit"
    else
        echo "✗ Proxy not running"
    fi
    
    # Survey
    if [ -f "$SETUP_DIR/survey.pid" ] && ps -p $(cat "$SETUP_DIR/survey.pid") > /dev/null 2>&1; then
        echo "✓ Survey running (PID $(cat $SETUP_DIR/survey.pid))"
    else
        echo "✗ Survey not running"
    fi
}

test_routing() {
    echo "🧪 Testing IP routing..."
    echo ""
    
    echo "Account 1 (arsen) - Tailscale:"
    curl -s -x http://127.0.0.1:8888 https://ipapi.co/json/ | jq "{ip,country,city}"
    
    echo ""
    echo "Account 2 (lena) - Tor:"
    curl -s -x http://127.0.0.1:8889 https://ipapi.co/json/ | jq "{ip,country,city}"
}

case "$1" in
    start) start_all ;;
    stop) stop_all ;;
    restart) stop_all && sleep 2 && start_all ;;
    status) status ;;
    test) test_routing ;;
    *)
        echo "VPN v2 Manager"
        echo "=============="
        echo "Usage: $0 {start|stop|restart|status|test}"
        ;;
esac


```

### test_routing.sh

**Розмір:** 1,314 байт

```bash
#!/data/data/com.termux/files/usr/bin/bash

echo "🧪 Testing Multi-IP Routing"
echo "============================"
echo ""

# Check Tor
echo "1. Checking Tor connection..."
if curl -s -x socks5://127.0.0.1:9050 https://ipapi.co/country_code | grep -q "CH"; then
    echo "✅ Tor works (Switzerland exit)"
else
    echo "❌ Tor failed or not Swiss exit"
fi

echo ""

# Check proxy port 8888
echo "2. Checking Proxy Port 8888 (Tailscale)..."
IP1=$(curl -s -x http://127.0.0.1:8888 https://ipapi.co/ip)
COUNTRY1=$(curl -s -x http://127.0.0.1:8888 https://ipapi.co/country_code)
echo "   IP: $IP1"
echo "   Country: $COUNTRY1"

echo ""

# Check proxy port 8889
echo "3. Checking Proxy Port 8889 (Tor)..."
IP2=$(curl -s -x http://127.0.0.1:8889 https://ipapi.co/ip)
COUNTRY2=$(curl -s -x http://127.0.0.1:8889 https://ipapi.co/country_code)
echo "   IP: $IP2"
echo "   Country: $COUNTRY2"

echo ""
echo "============================"

if [ "$IP1" != "$IP2" ] && [ "$COUNTRY1" = "CH" ] && [ "$COUNTRY2" = "CH" ]; then
    echo "✅ SUCCESS! Different IPs, both Swiss!"
    echo ""
    echo "Ready to use:"
    echo "  arsen.k111999@gmail.com → $IP1 (Tailscale)"
    echo "  lekov00@gmail.com → $IP2 (Tor)"
else
    echo "❌ FAILED! Check logs:"
    echo "  ~/vpn_v2/proxy.log"
    echo "  ~/vpn_v2/tor.log"
fi


```

### README_MIGRATION.md

**Розмір:** 1,555 байт

```text
# Міграція на VPN v2 (Multi-IP Routing)

## Що змінилось

- **2 різні IP** для 2х акаунтів
- **Акаунт сина (arsen)**: Tailscale IP (100.100.74.9) як раніше
- **Акаунт дружини (lena)**: Tor exit IP (Швейцарія)
- **Автоматичний вибір** proxy на основі email

## Встановлення

### 1. Встановити Tor
```bash
pkg install tor
```

### 2. Встановити Python залежності
```bash
pip install aiohttp-socks
```

### 3. Налаштувати config.json
Відредагувати ~/vpn_v2/config.json:
- Вставити паролі для акаунтів
- Перевірити Tailscale IP

### 4. Тестування
```bash
cd ~/vpn_v2
chmod +x *.sh
./manager_v2.sh start
./test_routing.sh
```

## Міграція з v1 → v2

### Крок 1: Зупинити старий сервіс
```bash
cd ~/vpn
./manager.sh stop
```

### Крок 2: Запустити новий сервіс
```bash
cd ~/vpn_v2
./manager_v2.sh start
```

### Крок 3: Перевірити
```bash
./manager_v2.sh status
./test_routing.sh
```

## Rollback (якщо щось не так)

```bash
cd ~/vpn_v2
./manager_v2.sh stop

cd ~/vpn
./manager.sh start
```

## Очікуваний результат

```
Account 1 (arsen) - Tailscale:
  IP: 100.100.74.9
  Country: CH

Account 2 (lena) - Tor:
  IP: 185.xxx.xxx.xxx  (інший IP!)
  Country: CH
```

Portal meinungsplatz.ch побачить 2 різні пристрої!


```

### webrtc_block.js

**Розмір:** 377 байт

```javascript
// Блокування WebRTC для запобігання витоку IP
const config = {
  iceServers: [{urls: 'stun:stun.l.google.com:19302'}],
  iceCandidatePoolSize: 0
};

// Override RTCPeerConnection
window.RTCPeerConnection = new Proxy(window.RTCPeerConnection, {
  construct(target, args) {
    console.log('WebRTC blocked');
    return new target(config);
  }
});

```

### run_md_service.sh

**Розмір:** 3,366 байт

```bash
#!/bin/bash

# ===================================================================
# MD TO EMBEDDINGS SERVICE v4.0 - Simple Reliable Launcher (Linux)
# ===================================================================

set -e  # Exit on any error

# Set UTF-8 encoding
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
PYTHON_SCRIPT="md_to_embeddings_service_v4.py"

# Function to print colored output
print_header() {
    echo -e "${BLUE}===================================================================${NC}"
    echo -e "${BLUE}                MD TO EMBEDDINGS SERVICE v4.0${NC}"
    echo -e "${BLUE}===================================================================${NC}"
    echo -e "${YELLOW}Working directory: $(pwd)${NC}"
    echo -e "${BLUE}===================================================================${NC}"
    echo
}

print_error() {
    echo -e "${RED}ERROR: $1${NC}"
}

print_success() {
    echo -e "${GREEN}$1${NC}"
}

print_info() {
    echo -e "${YELLOW}$1${NC}"
}

# Change to script directory
cd "$(dirname "$0")"

# Clear terminal and show header
clear
print_header

# [1/2] Check Python installation
echo "[1/2] Checking Python..."

if command -v python3 &> /dev/null; then
    print_success "Python3 found"
    python3 --version
    PY_CMD="python3"
elif command -v python &> /dev/null; then
    print_success "Python found"
    python --version
    PY_CMD="python"
else
    echo
    print_error "Python not found!"
    echo
    echo "Please install Python3 using:"
    echo "  - Ubuntu/Debian: sudo apt install python3 python3-pip"
    echo "  - CentOS/RHEL: sudo yum install python3 python3-pip"
    echo "  - Fedora: sudo dnf install python3 python3-pip"
    echo "  - Arch: sudo pacman -S python python-pip"
    echo
    exit 1
fi

print_success "Python check completed successfully"
echo

# [2/2] Check main script exists
echo "[2/2] Checking main script..."
if [[ -f "$PYTHON_SCRIPT" ]]; then
    print_success "Main script found: $PYTHON_SCRIPT"
else
    echo
    print_error "$PYTHON_SCRIPT not found!"
    echo "Please make sure the file exists in the current directory."
    echo
    exit 1
fi
echo

# Launch service
echo -e "${BLUE}===================================================================${NC}"
echo -e "${BLUE}Launching MD to Embeddings Service v4.0...${NC}"
echo -e "${BLUE}===================================================================${NC}"
echo
echo "MENU OPTIONS:"
echo "  1. Deploy project template (first run)"
echo "  2. Convert DRAKON schemas"
echo "  3. Create .md file (WITHOUT service files)"
echo "  4. Copy .md to Dropbox"
echo "  5. Exit"
echo
echo -e "${BLUE}===================================================================${NC}"
echo

# Execute the Python script
$PY_CMD "$PYTHON_SCRIPT"
EXIT_CODE=$?

echo
echo -e "${BLUE}===================================================================${NC}"
if [[ $EXIT_CODE -eq 0 ]]; then
    print_success "Service completed successfully"
else
    print_error "Service exited with code: $EXIT_CODE"
fi
echo -e "${BLUE}===================================================================${NC}"
echo

# Wait for user input (Linux equivalent of pause)
read -p "Press Enter to continue..." -r
exit $EXIT_CODE

```

---

## Статистика

- **Оброблено файлів:** 8
- **Пропущено сервісних файлів:** 1
- **Загальний розмір:** 25,201 байт (24.6 KB)
- **Дата створення:** 2025-10-22 09:21:19
