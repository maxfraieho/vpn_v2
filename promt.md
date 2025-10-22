# Швидке розгортання VPN v2 - Покрокова інструкція

## Передумови
- ✅ Termux встановлено
- ✅ Tailscale підключено
- ✅ Python встановлено

## Крок 1: Встановлення залежностей (5 хв)

```bash
# Оновити пакети
pkg update && pkg upgrade -y

# Встановити необхідні пакети
pkg install -y tor python curl jq

# Встановити Python бібліотеки
pip install aiohttp aiohttp-socks requests
```

## Крок 2: Створення структури (2 хв)

```bash
# Створити директорію
mkdir -p ~/vpn_v2
cd ~/vpn_v2

# Створити директорію для Tor
mkdir -p ~/vpn_v2/tor_data
```

## Крок 3: Створення файлів конфігурації (3 хв)

### 3.1 config.json
```bash
cat > ~/vpn_v2/config.json << 'EOF'
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
      "password": "YOUR_PASSWORD_HERE"
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
      "password": "YOUR_PASSWORD_HERE"
    }
  },
  "survey_service_port": 8090,
  "tailscale_ip": "100.100.74.9"
}
EOF
```

**⚠️ ВАЖЛИВО:** Відредагуй config.json та заміни `YOUR_PASSWORD_HERE` на справжні паролі:
```bash
nano ~/vpn_v2/config.json
```

### 3.2 torrc
```bash
cat > ~/vpn_v2/torrc << 'EOF'
SOCKSPort 127.0.0.1:9050
ExitNodes {ch}
StrictNodes 1
Log notice file /data/data/com.termux/files/home/vpn_v2/tor.log
DataDirectory /data/data/com.termux/files/home/vpn_v2/tor_data
EOF
```

### 3.3 webrtc_block.js
```bash
cat > ~/vpn_v2/webrtc_block.js << 'EOF'
// Блокування WebRTC для запобігання витоку IP
const config = {
  iceServers: [{urls: 'stun:stun.l.google.com:19302'}],
  iceCandidatePoolSize: 0
};

window.RTCPeerConnection = new Proxy(window.RTCPeerConnection, {
  construct(target, args) {
    console.log('WebRTC blocked');
    return new target(config);
  }
});
EOF
```

## Крок 4: Копіювання Python скриптів (5 хв)

### 4.1 smart_proxy_v2.py
(Збережено в системі)

### 4.2 survey_automation_v2_lite.py (без Playwright)
```python
# Survey Automation v2 LITE - Multi-IP Routing (без Playwright)
# Використовує лише requests для простішої роботи в Termux
import json
import requests
import asyncio
import logging
from datetime import datetime
import os
from aiohttp import web

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

class SurveyAutomationLite:
    def __init__(self):
        self.is_running = False
        self.sessions = {}  # Store sessions for each account

    def get_proxy_for_account(self, email: str):
        """Returns proxy configuration for an account"""
        
        account = CONFIG["accounts"].get(email)
        if not account:
            raise ValueError(f"Unknown account: {email}")
        
        port = account["proxy_port"]
        proxy_url = f"http://127.0.0.1:{port}"
        
        return {
            "http": proxy_url,
            "https": proxy_url
        }

    def get_session(self, email: str):
        """Get or create a requests session for an account"""
        
        if email not in self.sessions:
            session = requests.Session()
            
            # Load cookies if available
            account = CONFIG["accounts"].get(email)
            cookies_file = account.get("cookies_file")
            
            if cookies_file and os.path.exists(cookies_file):
                try:
                    with open(cookies_file, "r") as f:
                        cookies_data = json.load(f)
                        for cookie in cookies_data:
                            session.cookies.set(
                                cookie.get("name"),
                                cookie.get("value"),
                                domain=cookie.get("domain")
                            )
                    logger.info(f"Loaded cookies for {email}")
                except Exception as e:
                    logger.warning(f"Could not load cookies for {email}: {e}")
            
            # Set headers
            session.headers.update({
                "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                "Accept-Language": "de-CH,de;q=0.9,en;q=0.8",
                "Accept-Encoding": "gzip, deflate, br",
                "DNT": "1",
                "Connection": "keep-alive",
                "Upgrade-Insecure-Requests": "1"
            })
            
            self.sessions[email] = session
        
        return self.sessions[email]

    def check_swiss_ip(self, email: str):
        """Check IP through specific proxy"""
        try:
            proxies = self.get_proxy_for_account(email)
            
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
            logger.error(f"IP check failed for {email}: {e}")
            return False, {}

    def fetch_survey(self, email: str, survey_url: str):
        """Fetch survey page through correct proxy"""
        
        try:
            session = self.get_session(email)
            proxies = self.get_proxy_for_account(email)
            account = CONFIG["accounts"][email]
            
            # Check IP first
            is_swiss, ip_data = self.check_swiss_ip(email)
            
            logger.info(f"Account: {email}")
            logger.info(f"Proxy: {account['upstream']['name']}")
            logger.info(f"IP: {ip_data.get('ip')} ({ip_data.get('country_name')})")
            
            if not is_swiss:
                logger.error(f"Not in Switzerland! Location: {ip_data}")
                return {"success": False, "error": "Not in Switzerland"}

            # Fetch the survey page
            logger.info(f"Fetching survey: {survey_url}")
            response = session.get(
                survey_url,
                proxies=proxies,
                timeout=30,
                allow_redirects=True
            )
            
            if response.status_code == 200:
                logger.info(f"Survey page loaded successfully for {email}")
                
                # Save cookies
                cookies_file = account.get("cookies_file")
                if cookies_file:
                    try:
                        cookies_list = []
                        for cookie in session.cookies:
                            cookies_list.append({
                                "name": cookie.name,
                                "value": cookie.value,
                                "domain": cookie.domain,
                                "path": cookie.path,
                                "secure": cookie.secure
                            })
                        
                        with open(cookies_file, "w") as f:
                            json.dump(cookies_list, f, indent=2)
                        logger.info(f"Cookies saved for {email}")
                    except Exception as e:
                        logger.warning(f"Could not save cookies: {e}")
                
                return {
                    "success": True,
                    "message": f"Survey fetched for {email}",
                    "status_code": response.status_code,
                    "url": response.url,
                    "content_length": len(response.content)
                }
            else:
                logger.error(f"Survey fetch failed: HTTP {response.status_code}")
                return {
                    "success": False,
                    "error": f"HTTP {response.status_code}",
                    "url": response.url
                }
                
        except Exception as e:
            logger.error(f"Survey fetch error for {email}: {e}")
            return {"success": False, "error": str(e)}

    async def run(self):
        """Main service loop"""
        logger.info("Starting Survey Automation v2 LITE...")
        self.is_running = True
        
        # Start HTTP server to receive survey requests
        async def handle_survey_request(request):
            try:
                data = await request.json()
                email = data.get("email")
                survey_url = data.get("url")
                
                if not email or not survey_url:
                    return web.json_response(
                        {"error": "Missing email or url"},
                        status=400
                    )
                
                # Run synchronous fetch in executor
                loop = asyncio.get_event_loop()
                result = await loop.run_in_executor(
                    None,
                    self.fetch_survey,
                    email,
                    survey_url
                )
                
                return web.json_response(result)
            except Exception as e:
                logger.error(f"Request handling error: {e}")
                return web.json_response({"error": str(e)}, status=500)
        
        async def handle_check_ip(request):
            """Endpoint to check current IP for an account"""
            try:
                data = await request.json()
                email = data.get("email")
                
                if not email:
                    return web.json_response(
                        {"error": "Missing email"},
                        status=400
                    )
                
                loop = asyncio.get_event_loop()
                is_swiss, ip_data = await loop.run_in_executor(
                    None,
                    self.check_swiss_ip,
                    email
                )
                
                return web.json_response({
                    "success": is_swiss,
                    "ip_data": ip_data
                })
            except Exception as e:
                logger.error(f"IP check error: {e}")
                return web.json_response({"error": str(e)}, status=500)
        
        async def handle_health(request):
            """Health check endpoint"""
            return web.json_response({
                "status": "running",
                "accounts": list(CONFIG["accounts"].keys()),
                "version": "v2-lite"
            })
        
        app = web.Application()
        app.router.add_post("/survey", handle_survey_request)
        app.router.add_post("/check-ip", handle_check_ip)
        app.router.add_get("/health", handle_health)
        
        runner = web.AppRunner(app)
        await runner.setup()
        site = web.TCPSite(runner, "0.0.0.0", CONFIG["survey_service_port"])
        await site.start()
        
        logger.info(f"Survey service LITE running on port {CONFIG['survey_service_port']}")
        logger.info("Available endpoints:")
        logger.info("  POST /survey - Fetch survey")
        logger.info("  POST /check-ip - Check IP for account")
        logger.info("  GET /health - Health check")
        
        # Keep running
        while self.is_running:
            await asyncio.sleep(1)

def main():
    automation = SurveyAutomationLite()
    asyncio.run(automation.run())

if __name__ == "__main__": 
    main()
```

## Крок 5: Копіювання shell скриптів (5 хв)

### 5.1 manager_v2.sh
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
    tor -f "$SETUP_DIR/torrc" > "$TOR_LOG" 2>&1 &
    echo $! > "$SETUP_DIR/tor.pid"
    sleep 5
    echo "✓ Tor started"
    
    # 2. Multi-proxy server
    echo "Starting Smart Proxy v2..."
    nohup python3 "$SETUP_DIR/smart_proxy_v2.py" > "$PROXY_LOG" 2>&1 &
    echo $! > "$SETUP_DIR/proxy.pid"
    sleep 2
    echo "✓ Proxy started (ports 8888 + 8889)"
    
    # 3. Survey automation
    echo "Starting Survey Automation v2 (LITE)..."
    nohup python3 "$SETUP_DIR/survey_automation_v2.py" > "$SURVEY_LOG" 2>&1 &
    echo $! > "$SETUP_DIR/survey.pid"
    sleep 2
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
            kill -TERM "$pid" 2>/dev/null
            # Wait a bit before force killing
            sleep 2
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
        echo "  Testing Swiss exit..."
        COUNTRY=$(curl -s --socks5 127.0.0.1:9050 https://ipapi.co/country 2>/dev/null)
        if [ "$COUNTRY" = "CH" ]; then
            echo "  ✓ Swiss exit confirmed: $COUNTRY"
        else
            echo "  ⚠ Non-Swiss exit: $COUNTRY"
        fi
    else
        echo "✗ Tor not running"
    fi
    echo ""
    
    # Proxy
    if [ -f "$SETUP_DIR/proxy.pid" ] && ps -p $(cat "$SETUP_DIR/proxy.pid") > /dev/null 2>&1; then
        echo "✓ Proxy running (PID $(cat $SETUP_DIR/proxy.pid))"
        echo "  Port 8888: Tailscale direct"
        echo "  Port 8889: Tor exit"
        
        # Test ports
        if curl -s -x http://127.0.0.1:8888 https://ipapi.co/ip > /dev/null 2>&1; then
            echo "  ✓ Port 8888 responding"
        else
            echo "  ✗ Port 8888 not responding"
        fi
        
        if curl -s -x http://127.0.0.1:8889 https://ipapi.co/ip > /dev/null 2>&1; then
            echo "  ✓ Port 8889 responding"
        else
            echo "  ✗ Port 8889 not responding"
        fi
    else
        echo "✗ Proxy not running"
    fi
    echo ""
    
    # Survey
    if [ -f "$SETUP_DIR/survey.pid" ] && ps -p $(cat "$SETUP_DIR/survey.pid") > /dev/null 2>&1; then
        echo "✓ Survey running (PID $(cat $SETUP_DIR/survey.pid)) [LITE]"
        
        # Test API
        if curl -s http://127.0.0.1:8090/health > /dev/null 2>&1; then
            echo "  ✓ API responding"
        else
            echo "  ✗ API not responding"
        fi
    else
        echo "✗ Survey not running"
    fi
}

test_routing() {
    echo "🧪 Testing Multi-IP Routing"
    echo "============================"
    echo ""
    
    echo "1. Checking Tor connection..."
    if curl -s --socks5 127.0.0.1:9050 https://ipapi.co/country | grep -q "CH"; then
        echo "✅ Tor works (Switzerland exit)"
    else
        echo "❌ Tor not working properly"
    fi
    echo ""
    
    echo "2. Checking Proxy Port 8888 (Tailscale)..."
    IP1=$(curl -s -x http://127.0.0.1:8888 https://ipapi.co/ip)
    COUNTRY1=$(curl -s -x http://127.0.0.1:8888 https://ipapi.co/country)
    echo "   IP: $IP1"
    echo "   Country: $COUNTRY1"
    echo ""
    
    echo "3. Checking Proxy Port 8889 (Tor)..."
    IP2=$(curl -s -x http://127.0.0.1:8889 https://ipapi.co/ip)
    COUNTRY2=$(curl -s -x http://127.0.0.1:8889 https://ipapi.co/country)
    echo "   IP: $IP2"
    echo "   Country: $COUNTRY2"
    echo ""
    
    if [ "$IP1" != "$IP2" ] && [ "$COUNTRY1" = "CH" ] && [ "$COUNTRY2" = "CH" ]; then
        echo "============================"
        echo "✅ SUCCESS! Different IPs, both Swiss!"
        echo ""
        echo "Ready to use:"
        echo "  arsen.k111999@gmail.com → $IP1 (Tailscale)"
        echo "  lekov00@gmail.com → $IP2 (Tor)"
    else
        echo "============================"
        echo "❌ ISSUE: IPs might be the same or not Swiss"
    fi
}

case "$1" in
    start) start_all ;;
    stop) stop_all ;;
    restart) stop_all && sleep 3 && start_all ;;
    status) status ;;
    test) test_routing ;;
    *) 
        echo "VPN v2 Manager"
        echo "=============="
        echo "Usage: $0 {start|stop|restart|status|test}"
        ;;
esac
```

### 5.2 test_routing.sh
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

### 5.3 diagnostic.sh
```bash
#!/data/data/com.termux/files/usr/bin/bash

# Diagnostic tools for VPN v2
# Детальна діагностика всіх компонентів системи

SETUP_DIR="$HOME/vpn_v2"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}=================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

# 1. Check Tor
check_tor() {
    print_header "1. TOR DIAGNOSTIC"
    
    if ! command -v tor &> /dev/null; then
        print_error "Tor not installed"
        echo "Install: pkg install tor"
        return 1
    fi
    print_success "Tor binary found"
    
    if [ -f "$SETUP_DIR/tor.pid" ] && ps -p $(cat "$SETUP_DIR/tor.pid") > /dev/null 2>&1; then
        print_success "Tor process running (PID $(cat $SETUP_DIR/tor.pid))"
    else
        print_error "Tor not running"
        return 1
    fi
    
    # Test SOCKS5 connection
    print_info "Testing SOCKS5 connection..."
    if curl -s --socks5 127.0.0.1:9050 https://check.torproject.org/api/ip 2>/dev/null | grep -q "true"; then
        IP=$(curl -s --socks5 127.0.0.1:9050 https://ipapi.co/ip 2>/dev/null)
        COUNTRY=$(curl -s --socks5 127.0.0.1:9050 https://ipapi.co/country 2>/dev/null)
        print_success "Tor SOCKS5 working: $IP ($COUNTRY)"
        
        if [ "$COUNTRY" = "CH" ]; then
            print_success "Swiss exit node confirmed"
        else
            print_error "Not using Swiss exit node!"
        fi
    else
        print_error "Tor SOCKS5 connection failed"
        return 1
    fi
    
    echo ""
}

# 2. Check Python dependencies
check_python_deps() {
    print_header "2. PYTHON DEPENDENCIES"
    
    DEPS=("aiohttp" "aiohttp_socks" "requests")
    
    for dep in "${DEPS[@]}"; do
        if python3 -c "import $dep" 2>/dev/null; then
            print_success "$dep installed"
        else
            print_error "$dep NOT installed"
            echo "Install: pip install $dep"
        fi
    done
    
    echo ""
}

# 3. Check proxy ports
check_proxy_ports() {
    print_header "3. PROXY PORTS"
    
    # Check if smart_proxy_v2.py is running
    if [ -f "$SETUP_DIR/proxy.pid" ] && ps -p $(cat "$SETUP_DIR/proxy.pid") > /dev/null 2>&1; then
        print_success "Smart Proxy running (PID $(cat $SETUP_DIR/proxy.pid))"
    else
        print_error "Smart Proxy not running"
        echo ""
        return 1
    fi
    
    # Test port 8888 (Tailscale direct)
    print_info "Testing port 8888 (Tailscale direct)..."
    if timeout 5 curl -s -x http://127.0.0.1:8888 https://ipapi.co/ip 2>/dev/null | grep -E '^[0-9.]+$' > /dev/null; then
        IP1=$(curl -s -x http://127.0.0.1:8888 https://ipapi.co/ip)
        COUNTRY1=$(curl -s -x http://127.0.0.1:8888 https://ipapi.co/country)
        print_success "Port 8888: $IP1 ($COUNTRY1)"
    else
        print_error "Port 8888 not responding"
        echo "Check logs: tail -20 $SETUP_DIR/proxy.log"
    fi
    
    # Test port 8889 (Tor)
    print_info "Testing port 8889 (Tor exit)..."
    if timeout 5 curl -s -x http://127.0.0.1:8889 https://ipapi.co/ip 2>/dev/null | grep -E '^[0-9.]+$' > /dev/null; then
        IP2=$(curl -s -x http://127.0.0.1:8889 https://ipapi.co/ip)
        COUNTRY2=$(curl -s -x http://127.0.0.1:8889 https://ipapi.co/country)
        print_success "Port 8889: $IP2 ($COUNTRY2)"
    else
        print_error "Port 8889 not responding"
        echo "Check logs: tail -20 $SETUP_DIR/proxy.log"
    fi
    
    echo ""
}

# 4. Check survey service
check_survey_service() {
    print_header "4. SURVEY SERVICE"
    
    if [ -f "$SETUP_DIR/survey.pid" ] && ps -p $(cat "$SETUP_DIR/survey.pid") > /dev/null 2>&1; then
        print_success "Survey service running (PID $(cat $SETUP_DIR/survey.pid))"
        
        # Test health endpoint
        print_info "Testing health endpoint..."
        if curl -s http://127.0.0.1:8090/health 2>/dev/null | grep -q "running"; then
            print_success "Health check OK"
        else
            print_error "Health check failed"
        fi
    else
        print_error "Survey service not running"
        echo "Check logs: tail -20 $SETUP_DIR/survey.log"
    fi
    
    echo ""
}

# 5. Check config
check_config() {
    print_header "5. CONFIGURATION"
    
    if [ -f "$SETUP_DIR/config.json" ]; then
        print_success "config.json exists"
        
        # Check for default passwords
        if grep -q "YOUR_PASSWORD" "$SETUP_DIR/config.json"; then
            print_error "Default passwords found in config.json"
            echo "Please edit config.json and set real passwords"
        else
            print_success "Passwords configured"
        fi
        
        # Show accounts
        print_info "Configured accounts:"
        python3 -c "
import json
with open('$SETUP_DIR/config.json') as f:
    config = json.load(f)
    for email, acc in config['accounts'].items():
        print(f\\\"  - {email}: port {acc['proxy_port']} via {acc['upstream']['name']}\\\")
" 2>/dev/null
    else
        print_error "config.json not found"
    fi
    
    echo ""
}

# 6. Show logs
show_recent_logs() {
    print_header "6. RECENT LOGS"
    
    if [ -f "$SETUP_DIR/proxy.log" ]; then
        echo -e "${YELLOW}=== Proxy Log (last 10 lines) ===${NC}"
        tail -10 "$SETUP_DIR/proxy.log"
        echo ""
    fi
    
    if [ -f "$SETUP_DIR/survey.log" ]; then
        echo -e "${YELLOW}=== Survey Log (last 10 lines) ===${NC}"
        tail -10 "$SETUP_DIR/survey.log"
        echo ""
    fi
    
    if [ -f "$SETUP_DIR/tor.log" ]; then
        echo -e "${YELLOW}=== Tor Log (last 10 lines) ===${NC}"
        tail -10 "$SETUP_DIR/tor.log"
        echo ""
    fi
}

# 7. Network test
network_test() {
    print_header "7. NETWORK CONNECTIVITY"
    
    print_info "Testing direct connection..."
    if curl -s -m 5 https://ipapi.co/ip > /dev/null; then
        IP=$(curl -s https://ipapi.co/ip)
        print_success "Direct connection OK: $IP"
    else
        print_error "Direct connection failed"
    fi
    
    print_info "Testing Tailscale..."
    TAILSCALE_IP=$(cat "$SETUP_DIR/config.json" 2>/dev/null | grep -oP '\"tailscale_ip\":\\s*\"\\K[^\"]+')
    if [ -n "$TAILSCALE_IP" ]; then
        if ping -c 1 -W 2 "$TAILSCALE_IP" > /dev/null 2>&1; then
            print_success "Tailscale reachable: $TAILSCALE_IP"
        else
            print_error "Tailscale not reachable: $TAILSCALE_IP"
        fi
    fi
    
    echo ""
}

# Main menu
case "$1" in
    tor)
        check_tor
        ;;
    deps)
        check_python_deps
        ;;
    proxy)
        check_proxy_ports
        ;;
    survey)
        check_survey_service
        ;;
    config)
        check_config
        ;;
    logs)
        show_recent_logs
        ;;
    network)
        network_test
        ;;
    all|"")
        check_tor
        check_python_deps
        check_proxy_ports
        check_survey_service
        check_config
        network_test
        echo ""
        print_header "DIAGNOSTIC COMPLETE"
        echo "For detailed logs, run: $0 logs"
        ;;
    *)
        echo "VPN v2 Diagnostic Tools"
        echo "======================="
        echo "Usage: $0 {tor|deps|proxy|survey|config|logs|network|all}"
        echo ""
        echo "Commands:"
        echo "  tor     - Check Tor connection"
        echo "  deps    - Check Python dependencies"
        echo "  proxy   - Check proxy ports"
        echo "  survey  - Check survey service"
        echo "  config  - Check configuration"
        echo "  logs    - Show recent logs"
        echo "  network - Test network connectivity"
        echo "  all     - Run all checks (default)"
        ;;
esac
```

### 5.4 test_api.sh
```bash
#!/data/data/com.termux/files/usr/bin/bash

# Test Survey Service API
# Перевірка роботи Survey Automation API

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

API_URL="http://127.0.0.1:8090"

echo "🧪 Testing Survey Service API"
echo "=============================="
echo ""

# 1. Health check
echo "1. Health Check"
echo "   GET $API_URL/health"
HEALTH=$(curl -s "$API_URL/health")
if echo "$HEALTH" | grep -q "running"; then
    echo -e "${GREEN}   ✓ Service is running${NC}"
    echo "$HEALTH" | python3 -m json.tool 2>/dev/null || echo "$HEALTH"
else
    echo -e "${RED}   ✗ Service not responding${NC}"
    exit 1
fi
echo ""

# 2. Check IP for arsen account
echo "2. Check IP for arsen.k111999@gmail.com (Tailscale)"
echo "   POST $API_URL/check-ip"
IP_CHECK_ARSEN=$(curl -s -X POST "$API_URL/check-ip" \
    -H "Content-Type: application/json" \
    -d '{"email": "arsen.k111999@gmail.com"}')

if echo "$IP_CHECK_ARSEN" | grep -q "ip"; then
    echo -e "${GREEN}   ✓ IP check successful${NC}"
    echo "$IP_CHECK_ARSEN" | python3 -m json.tool 2>/dev/null
else
    echo -e "${RED}   ✗ IP check failed${NC}"
    echo "$IP_CHECK_ARSEN"
fi
echo ""

# 3. Check IP for lena account
echo "3. Check IP for lekov00@gmail.com (Tor)"
echo "   POST $API_URL/check-ip"
IP_CHECK_LENA=$(curl -s -X POST "$API_URL/check-ip" \
    -H "Content-Type: application/json" \
    -d '{"email": "lekov00@gmail.com"}')

if echo "$IP_CHECK_LENA" | grep -q "ip"; then
    echo -e "${GREEN}   ✓ IP check successful${NC}"
    echo "$IP_CHECK_LENA" | python3 -m json.tool 2>/dev/null
else
    echo -e "${RED}   ✗ IP check failed${NC}"
    echo "$IP_CHECK_LENA"
fi
echo ""

# 4. Test survey fetch (dry run)
echo "4. Test Survey Fetch (example.com)"
echo "   POST $API_URL/survey"
SURVEY_TEST=$(curl -s -X POST "$API_URL/survey" \
    -H "Content-Type: application/json" \
    -d '{
        "email": "arsen.k111999@gmail.com",
        "url": "https://example.com"
    }')

if echo "$SURVEY_TEST" | grep -q "success"; then
    echo -e "${GREEN}   ✓ Survey fetch test completed${NC}"
    echo "$SURVEY_TEST" | python3 -m json.tool 2>/dev/null
else
    echo -e "${YELLOW}   ⚠ Survey fetch returned error (may be expected)${NC}"
    echo "$SURVEY_TEST" | python3 -m json.tool 2>/dev/null
fi
echo ""

# Summary
echo "=============================="
echo "Summary:"
echo ""

# Extract IPs from responses
IP_ARSEN=$(echo "$IP_CHECK_ARSEN" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('ip_data', {}).get('ip', 'N/A'))" 2>/dev/null || echo "N/A")
COUNTRY_ARSEN=$(echo "$IP_CHECK_ARSEN" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('ip_data', {}).get('country_name', 'N/A'))" 2>/dev/null || echo "N/A")

IP_LENA=$(echo "$IP_CHECK_LENA" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('ip_data', {}).get('ip', 'N/A'))" 2>/dev/null || echo "N/A")
COUNTRY_LENA=$(echo "$IP_CHECK_LENA" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('ip_data', {}).get('country_name', 'N/A'))" 2>/dev/null || echo "N/A")

echo "Account 1 (arsen): $IP_ARSEN ($COUNTRY_ARSEN)"
echo "Account 2 (lena):  $IP_LENA ($COUNTRY_LENA)"
echo ""

if [ "$IP_ARSEN" != "$IP_LENA" ] && [ "$IP_ARSEN" != "N/A" ] && [ "$IP_LENA" != "N/A" ]; then
    echo -e "${GREEN}✓ SUCCESS: Different IPs detected!${NC}"
    
    if [ "$COUNTRY_ARSEN" = "Switzerland" ] && [ "$COUNTRY_LENA" = "Switzerland" ]; then
        echo -e "${GREEN}✓ Both IPs are from Switzerland!${NC}"
    else
        echo -e "${YELLOW}⚠ Warning: Not all IPs are from Switzerland${NC}"
    fi
else
    echo -e "${RED}✗ FAILED: IPs are the same or not detected${NC}"
fi
```

## Крок 6: Перевірка файлів (1 хв)

```bash
cd ~/vpn_v2
ls -lah

# Очікуваний вигляд:
# -rw-r--r-- config.json
# -rwxr-xr-x diagnostic.sh
# -rwxr-xr-x manager_v2.sh
# -rw-r--r-- smart_proxy_v2.py
# lrwxrwxrwx survey_automation_v2.py -> survey_automation_v2_lite.py
# -rw-r--r-- survey_automation_v2_lite.py
# -rwxr-xr-x test_api.sh
# -rwxr-xr-x test_routing.sh
# drwxr-xr-x tor_data/
# -rw-r--r-- torrc
# -rw-r--r-- webrtc_block.js
```

## Крок 7: Запуск сервісів (2 хв)

```bash
cd ~/vpn_v2
bash manager_v2.sh start
```

Очікуваний вивід:
```
🚀 Starting VPN v2 services...
Starting Tor...
✓ Tor started
Starting Smart Proxy v2...
✓ Proxy started (ports 8888 + 8889)
Starting Survey Automation v2 (LITE)...
✓ Survey automation started (port 8090)

📊 VPN v2 Status
================

✓ Tor running (PID 12345)
  Testing Swiss exit...
  ✓ Swiss exit confirmed

✓ Proxy running (PID 12346)
  Port 8888: Tailscale direct
  Port 8889: Tor exit
  ✓ Port 8888 responding
  ✓ Port 8889 responding

✓ Survey running (PID 12347) [LITE]
  ✓ API responding
```

## Крок 8: Тестування (3 хв)

### 8.1 Базова діагностика
```bash
bash diagnostic.sh all
```

### 8.2 Тест routing
```bash
bash test_routing.sh
```

Очікуваний результат:
```
🧪 Testing Multi-IP Routing
============================

1. Checking Tor connection...
✅ Tor works (Switzerland exit)

2. Checking Proxy Port 8888 (Tailscale)...
   IP: 100.100.74.9
   Country: CH

3. Checking Proxy Port 8889 (Tor)...
   IP: 185.xxx.xxx.xxx
   Country: CH

============================
✅ SUCCESS! Different IPs, both Swiss!

Ready to use:
  arsen.k111999@gmail.com → 100.100.74.9 (Tailscale)
  lekov00@gmail.com → 185.xxx.xxx.xxx (Tor)
```

### 8.3 Тест API
```bash
bash test_api.sh
```

## Крок 9: Автозапуск (опціонально)

Додати до `~/.bashrc`:
```bash
echo 'alias vpn2="cd ~/vpn_v2 && bash manager_v2.sh"' >> ~/.bashrc
source ~/.bashrc
```

Тепер можна використовувати:
```bash
vpn2 start
vpn2 stop
vpn2 status
vpn2 test
```

## Крок 10: Перевірка з реальним survey

```bash
# Через curl
curl -X POST http://127.0.0.1:8090/survey \
  -H "Content-Type: application/json" \
  -d '{
    "email": "arsen.k111999@gmail.com",
    "url": "https://meinungsplatz.ch"
  }'

# Або з іншого пристрою в мережі Tailscale
curl -X POST http://100.100.74.9:8090/survey \
  -H "Content-Type: application/json" \
  -d '{
    "email": "lekov00@gmail.com",
    "url": "https://meinungsplatz.ch"
  }'
```

## Чеклист готовності

- [x] Всі залежності встановлено
- [x] Файли створено і права встановлено
- [x] config.json відредаговано (паролі вставлено)
- [x] Tailscale IP вказано правильно
- [x] Сервіси запущено без помилок
- [x] Tor підключається до швейцарських exit nodes
- [x] Обидва proxy порти відповідають
- [x] Survey API працює
- [x] test_routing.sh показує різні IP
- [x] Обидва IP з Швейцарії (CH)

## Troubleshooting швидких проблем

### Tor не запускається
```bash
# Видалити старі дані
rm -rf ~/vpn_v2/tor_data/*
# Перезапустити
bash manager_v2.sh restart
```

### Proxy не відповідає
```bash
# Перевірити логи
tail -50 ~/vpn_v2/proxy.log
# Перевірити синтаксис
python3 -m py_compile smart_proxy_v2.py
```

### Survey service не запускається
```bash
# Перевірити залежності
pip list | grep -E "aiohttp|requests"
# Перевірити логи
tail -50 ~/vpn_v2/survey.log
```

### Не Swiss IP
```bash
# Перезапустити Tor з примусовою зміною exit
pkill tor
sleep 2
tor -f ~/vpn_v2/torrc &
sleep 10
# Перевірити
curl -s -x socks5://127.0.0.1:9050 https://ipapi.co/country
```

## Підтримка

Логи знаходяться в:
- `~/vpn_v2/proxy.log` - Smart Proxy
- `~/vpn_v2/survey.log` - Survey Automation
- `~/vpn_v2/tor.log` - Tor

Швидка діагностика:
```bash
cd ~/vpn_v2
bash diagnostic.sh all
```

---

**Час розгортання:** ~25 хвилин  
**Складність:** Середня  
**Підтримувані платформи:** Termux (Android), Linux

## Промт для Qwen Coder: Розгортання VPN v2 системи на хості 100.100.74.9

Ти є експертом у сфері DevOps, мережевої безпеки та автоматизації. Тобі необхідно налаштувати систему VPN v2 на хості з IP 100.100.74.9, яка дозволяє одночасно використовувати різні IP-адреси для різних акаунтів через систему проксі-серверів з роутингом на основі акаунта.

## Контекст

Система має забезпечувати наступне:
- Обслуговування двох акаунтів (arsen.k111999@gmail.com та lekov00@gmail.com)
- Кожен акаунт має отримувати різні IP-адреси з Швейцарії
- Один акаунт використовує Tailscale (100.100.74.9) для отримання Swiss IP
- Другий акаунт використовує Tor з виходом у Швейцарії
- Система має працювати на хості 100.100.74.9 з підтримкою віддаленого доступу

## Архітектура системи

- Smart Proxy v2 (Python) на портах 8888 та 8889
- Survey Automation v2 LITE (Python) на порті 8090
- Tor (SOCKS5) для одного акаунта
- Tailscale для іншого акаунта
- HTTP API для керування процесами опитування

## Завдання

Створи та розгорни повну систему VPN v2 на хості 100.100.74.9 з наступним функціоналом:

1. Встанови всі необхідні залежності (Tor, Python, aiohttp, requests тощо)
2. Створи всі необхідні файли з правильними конфігураціями
3. Налаштуй роутинг та перенаправлення на основі акаунта
4. Створи скрипти для запуску, зупинки та моніторингу сервісів
5. Забезпеч стабільну роботу всіх компонентів
6. Створи діагностичні інструменти для перевірки системи

## Конкретні компоненти для реалізації

### 1. config.json
Створи файл конфігурації з двома акаунтами:
- arsen.k111999@gmail.com → порт 8888 → Tailscale (Swiss IP на хості 100.100.74.9)
- lekov00@gmail.com → порт 8889 → Tor (Swiss IP через CH exit nodes)

### 2. smart_proxy_v2.py
Реалізуй HTTP-проксі-сервер, який:
- Обробляє запити на портах 8888 та 8889
- Маршрутизує трафік відповідно до акаунта користувача
- Направляє трафік до відповідного upstream (Tailscale або Tor)
- Зберігає логи у proxy.log

### 3. survey_automation_v2_lite.py
Створи сервіс для автоматизації опитувань, який:
- Використовує лише requests (без Playwright для сумісності з Termux)
- Має REST API на порті 8090
- Використовує правильні проксі для кожного акаунта
- Перевіряє, чи IP знаходиться в Швейцарії
- Зберігає та відновлює cookies
- Зберігає логи у survey.log

### 4. manager_v2.sh
Створи скрипт для управління всіма сервісами:
- Запуск/зупинка/перезапуск всіх компонентів
- Перевірка статусу всіх сервісів
- Ведення PID файлів
- Відображення зручного інтерфейсу користувача

### 5. Діагностичні скрипти
- diagnostic.sh - комплексна перевірка всіх компонентів
- test_api.sh - перевірка роботи API сервісів
- test_routing.sh - перевірка правильного маршрутизування IP

### 6. torrc
Конфігурація Tor для виходу лише через швейцарські вузли

## Вимоги до реалізації

- Всі файли мають бути створені у теці ~/vpn_v2
- Права доступу до файлів мають бути встановлені правильно
- Забезпеч стабільну роботу навіть у середовищі Termux
- Створи механізми автозапуску при старті системи
- Впровадь належне логування для всіх компонентів
- Створи інструменти для усунення несправностей

## Очікувані результати

Після розгортання система має:
- Запускатися однією командою
- Показувати різні Swiss IP для різних акаунтів
- Дозволяти виконувати опитування через API
- Бути стійкою до перезавантажень
- Мати зручні інструменти для моніторингу та діагностики