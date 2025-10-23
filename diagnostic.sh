#!/data/data/com.termux/files/usr/bin/bash

# VPN v2 Diagnostic Script

SETUP_DIR="$HOME/vpn_v2"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}VPN v2 Diagnostic Tool${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

check_files() {
    echo -e "${YELLOW}[1/6] Checking required files...${NC}"
    
    local files=(
        "config.json"
        "smart_proxy_v2.py"
        "survey_automation_v2.py"
        "manager_v2.sh"
        "torrc"
    )
    
    local missing=0
    for file in "${files[@]}"; do
        if [ -f "$SETUP_DIR/$file" ]; then
            echo -e "  ${GREEN}✓${NC} $file"
        else
            echo -e "  ${RED}✗${NC} $file (missing)"
            missing=$((missing + 1))
        fi
    done
    
    if [ $missing -eq 0 ]; then
        echo -e "${GREEN}All required files present${NC}"
    else
        echo -e "${RED}Missing $missing files${NC}"
    fi
    echo ""
}

check_dependencies() {
    echo -e "${YELLOW}[2/6] Checking dependencies...${NC}"
    
    # Check Python
    if command -v python3 &> /dev/null; then
        local py_version=$(python3 --version)
        echo -e "  ${GREEN}✓${NC} Python3: $py_version"
    else
        echo -e "  ${RED}✗${NC} Python3 not found"
    fi
    
    # Check Tor
    if command -v tor &> /dev/null; then
        local tor_version=$(tor --version | head -n 1)
        echo -e "  ${GREEN}✓${NC} Tor: $tor_version"
    else
        echo -e "  ${RED}✗${NC} Tor not installed"
    fi
    
    # Check Python packages
    echo ""
    echo "  Python packages:"
    for pkg in aiohttp aiohttp-socks requests beautifulsoup4; do
        if python3 -c "import ${pkg//-/_}" 2>/dev/null; then
            echo -e "    ${GREEN}✓${NC} $pkg"
        else
            echo -e "    ${RED}✗${NC} $pkg (missing)"
        fi
    done
    echo ""
}

check_ports() {
    echo -e "${YELLOW}[3/6] Checking ports...${NC}"
    
    local ports=(9050 8888 8889 8090)
    
    for port in "${ports[@]}"; do
        # Try different methods to check if port is listening
        if command -v ss &> /dev/null && ss -tuln 2>/dev/null | grep -q ":$port "; then
            # Port is listening according to ss
            echo -e "  ${GREEN}✓${NC} Port $port: listening"
        elif netstat -tuln 2>/dev/null | grep -q ":$port "; then
            # Port is listening according to netstat
            echo -e "  ${GREEN}✓${NC} Port $port: listening"
        elif lsof -i :$port 2>/dev/null | grep -q LISTEN; then
            # Port is listening according to lsof
            echo -e "  ${GREEN}✓${NC} Port $port: listening"
        else
            # Since we can't reliably check port status on Termux, 
            # let's test connectivity to the port instead
            if timeout 5 curl -s http://localhost:$port 2>/dev/null | grep -q "Proxy" || \
               timeout 5 curl -s http://127.0.0.1:$port 2>/dev/null | grep -q "Proxy"; then
                echo -e "  ${GREEN}✓${NC} Port $port: reachable"
            else
                # Check if process is running that should listen on this port
                local process_check=""
                case $port in
                    9050)
                        process_check="tor"
                        ;;
                    8888|8889)
                        process_check="smart_proxy"
                        ;;
                    8090)
                        process_check="survey"
                        ;;
                esac
                
                if [ ! -z "$process_check" ] && pgrep -f "$process_check" > /dev/null; then
                    echo -e "  ${GREEN}✓${NC} Port $port: process running (connectivity test inconclusive)"
                else
                    echo -e "  ${YELLOW}○${NC} Port $port: unavailable"
                fi
            fi
        fi
    done
    echo ""
}

check_processes() {
    echo -e "${YELLOW}[4/6] Checking processes...${NC}"
    
    # Check Tor - try PID file first, then fall back to process search
    local tor_running=false
    if [ -f "$SETUP_DIR/tor.pid" ]; then
        local tor_pid=$(cat "$SETUP_DIR/tor.pid" 2>/dev/null)
        if [ ! -z "$tor_pid" ] && ps -p "$tor_pid" > /dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} Tor running (PID $tor_pid)"
            tor_running=true
        else
            # PID file exists but process not running, try to find Tor process anyway
            local tor_pids=$(pgrep -f "tor -f" 2>/dev/null)
            if [ ! -z "$tor_pids" ]; then
                echo -e "  ${GREEN}✓${NC} Tor running (PID $tor_pids) [PID file may be stale]"
                tor_running=true
            else
                echo -e "  ${RED}✗${NC} Tor not running"
            fi
        fi
    else
        # No PID file, search for processes
        local tor_pids=$(pgrep -f "tor -f" 2>/dev/null)
        if [ ! -z "$tor_pids" ]; then
            echo -e "  ${GREEN}✓${NC} Tor running (PID $tor_pids)"
            tor_running=true
        else
            echo -e "  ${RED}✗${NC} Tor not running"
        fi
    fi
    
    # Check Proxy
    if pgrep -f "smart_proxy" > /dev/null; then
        local proxy_pid=$(pgrep -f "smart_proxy")
        echo -e "  ${GREEN}✓${NC} Smart Proxy running (PID $proxy_pid)"
    else
        echo -e "  ${RED}✗${NC} Smart Proxy not running"
    fi
    
    # Check Survey
    if pgrep -f "survey_automation" > /dev/null; then
        local survey_pid=$(pgrep -f "survey_automation")
        echo -e "  ${GREEN}✓${NC} Survey Automation running (PID $survey_pid)"
    else
        echo -e "  ${RED}✗${NC} Survey Automation not running"
    fi
    echo ""
}

check_connectivity() {
    echo -e "${YELLOW}[5/6] Checking connectivity...${NC}"
    
    # Check internet
    if ping -c 1 8.8.8.8 &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} Internet connection: OK"
    else
        echo -e "  ${RED}✗${NC} No internet connection"
    fi
    
    # Check Tor
    if timeout 15 sh -c 'curl -s --socks5 127.0.0.1:9050 --connect-timeout 10 https://check.torproject.org/ | grep -q "Congratulations"' 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Tor connection: OK"
        local tor_ip=$(timeout 10 curl -s --socks5 127.0.0.1:9050 https://ipapi.co/ip 2>/dev/null)
        local tor_country=$(timeout 10 curl -s --socks5 127.0.0.1:9050 https://ipapi.co/country_code 2>/dev/null)
        if [ ! -z "$tor_ip" ] && [ ! -z "$tor_country" ]; then
            echo -e "      IP: $tor_ip ($tor_country)"
        fi
    else
        echo -e "  ${RED}✗${NC} Tor connection failed"
    fi
    
    # Check Tailscale
    if command -v tailscale &> /dev/null; then
        if tailscale status &> /dev/null; then
            echo -e "  ${GREEN}✓${NC} Tailscale: connected"
        else
            echo -e "  ${YELLOW}○${NC} Tailscale: not connected"
        fi
    else
        echo -e "  ${YELLOW}○${NC} Tailscale: not installed"
    fi
    echo ""
}

check_logs() {
    echo -e "${YELLOW}[6/6] Checking logs for errors...${NC}"
    
    # Check proxy log
    if [ -f "$SETUP_DIR/proxy.log" ]; then
        local proxy_errors=$(grep -i "error" "$SETUP_DIR/proxy.log" | tail -n 3)
        if [ ! -z "$proxy_errors" ]; then
            echo -e "  ${RED}!${NC} Recent proxy errors:"
            echo "$proxy_errors" | sed 's/^/      /'
        else
            echo -e "  ${GREEN}✓${NC} Proxy log: no recent errors"
        fi
    fi
    
    # Check survey log
    if [ -f "$SETUP_DIR/survey.log" ]; then
        local survey_errors=$(grep -i "error" "$SETUP_DIR/survey.log" | tail -n 3)
        if [ ! -z "$survey_errors" ]; then
            echo -e "  ${RED}!${NC} Recent survey errors:"
            echo "$survey_errors" | sed 's/^/      /'
        else
            echo -e "  ${GREEN}✓${NC} Survey log: no recent errors"
        fi
    fi
    
    # Check tor log
    if [ -f "$SETUP_DIR/tor.log" ]; then
        local tor_errors=$(grep -i "error\|warn" "$SETUP_DIR/tor.log" | tail -n 3)
        if [ ! -z "$tor_errors" ]; then
            echo -e "  ${YELLOW}!${NC} Recent Tor warnings:"
            echo "$tor_errors" | sed 's/^/      /'
        else
            echo -e "  ${GREEN}✓${NC} Tor log: no recent errors"
        fi
    fi
    echo ""
}

recommendations() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}Recommendations${NC}"
    echo -e "${BLUE}================================${NC}"
    echo ""
    
    # Check if services are running
    local tor_running=$(pgrep -f "tor -f" 2>/dev/null)
    if [ -z "$tor_running" ]; then
        echo -e "${YELLOW}•${NC} Tor is not running. Start with: ./manager_v2.sh start"
    fi
    
    if ! pgrep -f "smart_proxy" > /dev/null; then
        echo -e "${YELLOW}•${NC} Smart Proxy is not running. Check proxy.log for errors"
    fi
    
    # Check for missing dependencies
    if ! python3 -c "import aiohttp_socks" 2>/dev/null; then
        echo -e "${YELLOW}•${NC} Install missing dependency: pip install aiohttp-socks"
    fi
    
    if ! python3 -c "import bs4" 2>/dev/null; then
        echo -e "${YELLOW}•${NC} Install missing dependency: pip install beautifulsoup4"
    fi
    
    # Additional recommendation for Termux users
    echo -e "${YELLOW}•${NC} On Termux/Android systems, network diagnostics may show false negatives due to limited command support."
    echo -e "${YELLOW}•${NC} If services appear offline but are working externally (as tested with curl), the system is functioning correctly."
    echo ""
}

# Main execution
case "$1" in
    files)
        check_files
        ;;
    deps)
        check_dependencies
        ;;
    ports)
        check_ports
        ;;
    procs)
        check_processes
        ;;
    conn)
        check_connectivity
        ;;
    logs)
        check_logs
        ;;
    all|"")
        check_files
        check_dependencies
        check_ports
        check_processes
        check_connectivity
        check_logs
        recommendations
        ;;
    *)
        echo "Usage: $0 {files|deps|ports|procs|conn|logs|all}"
        echo ""
        echo "Options:"
        echo "  files  - Check required files"
        echo "  deps   - Check dependencies"
        echo "  ports  - Check port status"
        echo "  procs  - Check running processes"
        echo "  conn   - Check connectivity"
        echo "  logs   - Check logs for errors"
        echo "  all    - Run all checks (default)"
        ;;
esac