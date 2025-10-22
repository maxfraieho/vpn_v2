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

