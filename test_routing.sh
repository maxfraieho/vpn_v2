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

