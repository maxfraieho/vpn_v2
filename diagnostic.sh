#!/bin/bash
# Діагностика системи VPN v2

echo "🔍 Діагностика системи VPN v2"
echo "============================="

# Перевірка Tor
echo "1. Перевірка Tor сервісу..."
if netstat -tuln 2>/dev/null | grep -q ":9050 "; then
    echo "   ✅ Tor працює на порті 9050"
else
    echo "   ❌ Tor НЕ працює на порті 9050"
fi

# Перевірка портів проксі
echo "2. Перевірка портів проксі..."
if netstat -tuln 2>/dev/null | grep -q ":8888 "; then
    echo "   ❌ Порт 8888 вже використовується"
else
    echo "   ✅ Порт 8888 вільний"
fi

if netstat -tuln 2>/dev/null | grep -q ":8889 "; then
    echo "   ❌ Порт 8889 вже використовується"
else
    echo "   ✅ Порт 8889 вільний"
fi

# Перевірка процесів
echo "3. Перевірка процесів..."
if pgrep -f "tor" > /dev/null; then
    echo "   ✅ Процес Tor запущений"
else
    echo "   ❌ Процес Tor НЕ запущений"
fi

if pgrep -f "smart_proxy_v2" > /dev/null; then
    echo "   ✅ Процес Smart Proxy запущений"
else
    echo "   ❌ Процес Smart Proxy НЕ запущений"
fi

if pgrep -f "survey_automation_v2" > /dev/null; then
    echo "   ✅ Процес Survey Automation запущений"
else
    echo "   ❌ Процес Survey Automation НЕ запущений"
fi

# Перевірка Tailscale IP
echo "4. Перевірка Tailscale IP..."
if curl -s --socks5-hostname 100.100.74.9:9050 https://ipapi.co/json/ 2>/dev/null | grep -q "CH"; then
    echo "   ✅ Tailscale IP 100.100.74.9:9050 працює (Швейцарія)"
else
    echo "   ❌ Tailscale IP 100.100.74.9:9050 НЕ працює"
fi

# Перевірка модулів Python
echo "5. Перевірка необхідних модулів Python..."
if python3 -c "import aiohttp" 2>/dev/null; then
    echo "   ✅ aiohttp встановлено"
else
    echo "   ❌ aiohttp НЕ встановлено"
fi

if python3 -c "import aiohttp_socks" 2>/dev/null; then
    echo "   ✅ aiohttp_socks встановлено"
else
    echo "   ❌ aiohttp_socks НЕ встановлено"
fi

if python3 -c "import playwright" 2>/dev/null; then
    echo "   ✅ playwright встановлено"
else
    echo "   ❌ playwright НЕ встановлено (впливає на Survey Automation)"
fi

# Перевірка файлів конфігурації
echo "6. Перевірка файлів конфігурації..."
if [ -f "config.json" ]; then
    echo "   ✅ config.json існує"
    echo "   Деталі конфігурації:"
    python3 -c "import json; c=json.load(open('config.json')); print(f'  - Кількість облікових записів: {len(c[\"accounts\"])}'); [print(f'  - {email}: порт {acc[\"proxy_port\"]}') for email, acc in c['accounts'].items()]"
else
    echo "   ❌ config.json НЕ існує"
fi

if [ -f "torrc" ]; then
    echo "   ✅ torrc існує"
else
    echo "   ❌ torrc НЕ існує"
fi

echo ""
echo "💡 Рекомендації:"
echo "   - Якщо є проблеми з проксі, перевірте занятість портів 8888/8889"
echo "   - Якщо Survey Automation не працює, спробуйте встановити playwright або знайти альтернативу"
echo "   - Для перевірки Tor проксі: curl --socks5-hostname 100.100.74.9:9050 https://ipapi.co/json/"
echo ""