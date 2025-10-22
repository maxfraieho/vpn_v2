#!/data/data/com.termux/files/usr/bin/bash

# Quick Fix Script for VPN v2
# Automatically fixes common issues

set -e

SETUP_DIR="$HOME/vpn_v2"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}VPN v2 Quick Fix${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

# Step 1: Stop all services
echo -e "${YELLOW}[1/5] Stopping all services...${NC}"
pkill -f "smart_proxy" 2>/dev/null || true
pkill -f "survey_automation" 2>/dev/null || true
pkill -f "tor -f" 2>/dev/null || true
sleep 2
echo -e "${GREEN}✓${NC} Services stopped"
echo ""

# Step 2: Clean up
echo -e "${YELLOW}[2/5] Cleaning up...${NC}"
rm -f "$SETUP_DIR"/*.pid
echo -e "${GREEN}✓${NC} PID files cleaned"
echo ""

# Step 3: Check dependencies
echo -e "${YELLOW}[3/5] Checking dependencies...${NC}"

missing=()

if ! python3 -c "import aiohttp" 2>/dev/null; then
    missing+=("aiohttp")
fi

if ! python3 -c "import aiohttp_socks" 2>/dev/null; then
    missing+=("aiohttp-socks")
fi

if ! python3 -c "import requests" 2>/dev/null; then
    missing+=("requests")
fi

if ! python3 -c "import bs4" 2>/dev/null; then
    missing+=("beautifulsoup4")
fi

if [ ${#missing[@]} -gt 0 ]; then
    echo -e "${YELLOW}Installing missing packages: ${missing[*]}${NC}"
    pip install "${missing[@]}"
    echo -e "${GREEN}✓${NC} Dependencies installed"
else
    echo -e "${GREEN}✓${NC} All dependencies present"
fi
echo ""

# Step 4: Check for fixed scripts
echo -e "${YELLOW}[4/5] Checking for fixed scripts...${NC}"

if [ ! -f "$SETUP_DIR/smart_proxy_v2_fixed.py" ]; then
    echo -e "${RED}✗${NC} smart_proxy_v2_fixed.py not found"
    echo "   Please create this file from the Claude artifacts"
    MISSING_FIXED=1
else
    echo -e "${GREEN}✓${NC} smart_proxy_v2_fixed.py found"
fi

if [ ! -f "$SETUP_DIR/survey_automation_v2_fixed.py" ]; then
    echo -e "${RED}✗${NC} survey_automation_v2_fixed.py not found"
    echo "   Please create this file from the Claude artifacts"
    MISSING_FIXED=1
else
    echo -e "${GREEN}✓${NC} survey_automation_v2_fixed.py found"
fi

if [ ! -f "$SETUP_DIR/manager_v2_fixed.sh" ]; then
    echo -e "${RED}✗${NC} manager_v2_fixed.sh not found"
    echo "   Please create this file from the Claude artifacts"
    MISSING_FIXED=1
else
    echo -e "${GREEN}✓${NC} manager_v2_fixed.sh found"
    chmod +x "$SETUP_DIR/manager_v2_fixed.sh"
fi

if [ ! -f "$SETUP_DIR/diagnostic.sh" ]; then
    echo -e "${YELLOW}○${NC} diagnostic.sh not found (optional)"
else
    echo -e "${GREEN}✓${NC} diagnostic.sh found"
    chmod +x "$SETUP_DIR/diagnostic.sh"
fi

echo ""

# Step 5: Start services
if [ -z "$MISSING_FIXED" ]; then
    echo -e "${YELLOW}[5/5] Starting services...${NC}"
    
    cd "$SETUP_DIR"
    
    if [ -f "manager_v2_fixed.sh" ]; then
        ./manager_v2_fixed.sh start
    else
        echo -e "${RED}Cannot start - missing manager script${NC}"
        exit 1
    fi
    
    echo ""
    echo -e "${BLUE}================================${NC}"
    echo -e "${GREEN}Quick fix completed!${NC}"
    echo -e "${BLUE}================================${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Check status: cd ~/vpn_v2 && ./manager_v2_fixed.sh status"
    echo "2. Test routing: ./manager_v2_fixed.sh test"
    echo "3. View logs: ./manager_v2_fixed.sh logs proxy"
else
    echo ""
    echo -e "${YELLOW}[5/5] Skipping service start - fixed scripts missing${NC}"
    echo ""
    echo -e "${BLUE}================================${NC}"
    echo -e "${YELLOW}Action required!${NC}"
    echo -e "${BLUE}================================${NC}"
    echo ""
    echo "Please create the following files from Claude artifacts:"
    echo "1. smart_proxy_v2_fixed.py"
    echo "2. survey_automation_v2_fixed.py"
    echo "3. manager_v2_fixed.sh"
    echo "4. diagnostic.sh (optional)"
    echo ""
    echo "Then run this script again: ./quick_fix.sh"
fi