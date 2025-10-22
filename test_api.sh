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