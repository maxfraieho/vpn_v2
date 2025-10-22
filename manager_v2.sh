#!/data/data/com.termux/files/usr/bin/bash

SETUP_DIR="$HOME/vpn_v2"
PROXY_LOG="$SETUP_DIR/proxy.log"
SURVEY_LOG="$SETUP_DIR/survey.log"
TOR_LOG="$SETUP_DIR/tor.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_process() {
    local pid_file="$1"
    local name="$2"
    
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if ps -p "$pid" > /dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} $name running (PID $pid)"
            return 0
        else
            echo -e "${RED}✗${NC} $name not running (stale PID file)"
            rm -f "$pid_file"
            return 1
        fi
    else
        echo -e "${RED}✗${NC} $name not running"
        return 1
    fi
}

kill_process() {
    local pid_file="$1"
    local name="$2"
    
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if ps -p "$pid" > /dev/null 2>&1; then
            echo "Stopping $name (PID $pid)..."
            kill -15 "$pid" 2>/dev/null
            sleep 2
            
            # Force kill if still running
            if ps -p "$pid" > /dev/null 2>&1; then
                echo "Force stopping $name..."
                kill -9 "$pid" 2>/dev/null
                sleep 1
            fi
        fi
        rm -f "$pid_file"
    fi
}

cleanup_old_processes() {
    echo "Cleaning up old processes..."
    
    # Kill any old instances
    pkill -f "smart_proxy_v2" 2>/dev/null
    pkill -f "survey_automation_v2" 2>/dev/null
    
    # Clean stale PID files
    for pid_file in "$SETUP_DIR"/*.pid; do
        if [ -f "$pid_file" ]; then
            local pid=$(cat "$pid_file" 2>/dev/null)
            if ! ps -p "$pid" > /dev/null 2>&1; then
                rm -f "$pid_file"
            fi
        fi
    done
    
    sleep 1
}

start_all() {
    echo "🚀 Starting VPN v2 services..."
    echo ""
    
    # Cleanup first
    cleanup_old_processes
    
    # 1. Start Tor
    echo "Starting Tor..."
    if [ ! -f "$SETUP_DIR/torrc" ]; then
        echo -e "${RED}Error: torrc file not found${NC}"
        return 1
    fi
    
    tor -f "$SETUP_DIR/torrc" > "$TOR_LOG" 2>&1 &
    local tor_pid=$!
    echo $tor_pid > "$SETUP_DIR/tor.pid"
    
    # Wait for Tor to be ready
    echo "Waiting for Tor to initialize..."
    for i in {1..30}; do
        if curl -s --socks5 127.0.0.1:9050 https://check.torproject.org/ | grep -q "Congratulations"; then
            echo -e "${GREEN}✓${NC} Tor started successfully"
            break
        fi
        sleep 1
    done
    
    # 2. Start Multi-proxy server
    echo ""
    echo "Starting Smart Proxy v2..."
    
    # Use fixed version if exists, otherwise use original
    if [ -f "$SETUP_DIR/smart_proxy_v2_fixed.py" ]; then
        proxy_script="smart_proxy_v2_fixed.py"
    else
        proxy_script="smart_proxy_v2.py"
    fi
    
    nohup python3 "$SETUP_DIR/$proxy_script" > "$PROXY_LOG" 2>&1 &
    local proxy_pid=$!
    echo $proxy_pid > "$SETUP_DIR/proxy.pid"
    
    # Wait for proxy to start
    sleep 3
    if ps -p "$proxy_pid" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Proxy started (PID $proxy_pid)"
    else
        echo -e "${RED}✗${NC} Proxy failed to start. Check $PROXY_LOG"
    fi
    
    # 3. Start Survey automation
    echo ""
    echo "Starting Survey Automation v2..."
    
    # Use fixed version if exists
    if [ -f "$SETUP_DIR/survey_automation_v2_fixed.py" ]; then
        survey_script="survey_automation_v2_fixed.py"
    else
        survey_script="survey_automation_v2.py"
    fi
    
    nohup python3 "$SETUP_DIR/$survey_script" > "$SURVEY_LOG" 2>&1 &
    local survey_pid=$!
    echo $survey_pid > "$SETUP_DIR/survey.pid"
    
    # Wait for survey service to start
    sleep 3
    if ps -p "$survey_pid" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Survey automation started (PID $survey_pid)"
    else
        echo -e "${YELLOW}⚠${NC} Survey automation may have issues. Check $SURVEY_LOG"
    fi
    
    echo ""
    echo "================================"
    status
}

stop_all() {
    echo "🛑 Stopping VPN v2 services..."
    echo ""
    
    kill_process "$SETUP_DIR/survey.pid" "Survey automation"
    kill_process "$SETUP_DIR/proxy.pid" "Smart proxy"
    kill_process "$SETUP_DIR/tor.pid" "Tor"
    
    # Final cleanup
    cleanup_old_processes
    
    echo ""
    echo -e "${GREEN}✓${NC} All services stopped"
}

status() {
    echo "📊 VPN v2 Status"
    echo "================"
    echo ""
    
    # Tor
    check_process "$SETUP_DIR/tor.pid" "Tor"
    if [ $? -eq 0 ]; then
        echo "   Testing connection..."
        local country=$(curl -s --socks5 127.0.0.1:9050 https://ipapi.co/country_code)
        if [ ! -z "$country" ]; then
            echo -e "   Country: ${GREEN}$country${NC}"
        fi
    fi
    
    echo ""
    
    # Proxy
    check_process "$SETUP_DIR/proxy.pid" "Smart Proxy"
    if [ $? -eq 0 ]; then
        echo "   Checking ports..."
        for port in 8888 8889; do
            if netstat -tuln 2>/dev/null | grep -q ":$port "; then
                echo -e "   Port $port: ${GREEN}listening${NC}"
            else
                echo -e "   Port $port: ${YELLOW}not listening${NC}"
            fi
        done
    fi
    
    echo ""
    
    # Survey
    check_process "$SETUP_DIR/survey.pid" "Survey Automation"
    if [ $? -eq 0 ]; then
        local port=$(grep -o '"survey_service_port": [0-9]*' "$SETUP_DIR/config.json" | grep -o '[0-9]*')
        if [ ! -z "$port" ]; then
            if netstat -tuln 2>/dev/null | grep -q ":$port "; then
                echo -e "   Port $port: ${GREEN}listening${NC}"
            fi
        fi
    fi
    
    echo ""
}

test_routing() {
    echo "🧪 Testing IP routing..."
    echo ""
    
    echo "Checking Tor connection:"
    curl -s --socks5 127.0.0.1:9050 https://ipapi.co/json/ | python3 -m json.tool | grep -E '"ip"|"country"|"city"'
    
    echo ""
    echo "Testing proxy ports:"
    
    for port in 8888 8889; do
        echo ""
        echo "Port $port:"
        if curl -s -x http://127.0.0.1:$port https://ipapi.co/json/ --connect-timeout 5 | python3 -m json.tool | grep -E '"ip"|"country"' 2>/dev/null; then
            echo -e "${GREEN}✓${NC} Working"
        else
            echo -e "${YELLOW}⚠${NC} Not responding"
        fi
    done
}

logs() {
    local service="$1"
    
    case "$service" in
        tor)
            echo "=== Tor Log (last 50 lines) ==="
            tail -n 50 "$TOR_LOG"
            ;;
        proxy)
            echo "=== Proxy Log (last 50 lines) ==="
            tail -n 50 "$PROXY_LOG"
            ;;
        survey)
            echo "=== Survey Log (last 50 lines) ==="
            tail -n 50 "$SURVEY_LOG"
            ;;
        *)
            echo "Usage: $0 logs {tor|proxy|survey}"
            ;;
    esac
}

case "$1" in
    start)
        start_all
        ;;
    stop)
        stop_all
        ;;
    restart)
        stop_all
        sleep 2
        start_all
        ;;
    status)
        status
        ;;
    test)
        test_routing
        ;;
    logs)
        logs "$2"
        ;;
    clean)
        cleanup_old_processes
        echo "Cleanup complete"
        ;;
    *)
        echo "VPN v2 Manager"
        echo "=============="
        echo "Usage: $0 {start|stop|restart|status|test|logs|clean}"
        echo ""
        echo "Commands:"
        echo "  start   - Start all services"
        echo "  stop    - Stop all services"
        echo "  restart - Restart all services"
        echo "  status  - Show status of services"
        echo "  test    - Test IP routing"
        echo "  logs    - View logs (tor|proxy|survey)"
        echo "  clean   - Clean up old processes"
        ;;
esac