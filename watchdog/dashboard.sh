#!/bin/bash

#═══════════════════════════════════════════════════════════════════
#  WATCHDOG DASHBOARD
#  Перегляд статистики та метрик моніторингу
#═══════════════════════════════════════════════════════════════════

METRICS_FILE="/opt/watchdog/logs/metrics.json"
LOG_FILE="/opt/watchdog/logs/watchdog.log"
STATE_FILE="/opt/watchdog/logs/watchdog.state"

# Кольори
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

clear
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}     TAILSCALE PROXY WATCHDOG DASHBOARD${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo ""

# Перевірка наявності файлів
if [ ! -f "$METRICS_FILE" ]; then
    echo -e "${RED}❌ Метрики ще не зібрані. Запустіть watchdog спочатку.${NC}"
    echo ""
    echo "Для запуску вручну:"
    echo "  sudo systemctl start watchdog-proxy.service"
    echo ""
    echo "Або запустіть скрипт напряму:"
    echo "  /opt/watchdog/watchdog.sh"
    exit 1
fi

# ============== ЗАГАЛЬНА СТАТИСТИКА ==============
echo -e "${MAGENTA}📊 ЗАГАЛЬНА СТАТИСТИКА:${NC}"

total=$(jq 'length' "$METRICS_FILE")
up_count=$(jq '[.[] | select(.status == "up")] | length' "$METRICS_FILE")
down_count=$(jq '[.[] | select(.status == "down")] | length' "$METRICS_FILE")

if [ "$total" -gt 0 ]; then
    uptime=$(echo "scale=2; ($up_count / $total) * 100" | bc)
else
    uptime="0.00"
fi

echo -e "   Всього перевірок: ${BLUE}$total${NC}"
echo -e "   ✅ Успішних: ${GREEN}$up_count${NC}"
echo -e "   ❌ Невдалих: ${RED}$down_count${NC}"

# Кольоровий uptime
if (( $(echo "$uptime >= 99" | bc -l) )); then
    uptime_color=$GREEN
elif (( $(echo "$uptime >= 95" | bc -l) )); then
    uptime_color=$YELLOW
else
    uptime_color=$RED
fi
echo -e "   📈 Uptime: ${uptime_color}${uptime}%${NC}"
echo ""

# ============== ПОТОЧНИЙ СТАТУС ==============
current_status=$(jq -r '.[-1].status' "$METRICS_FILE")
current_time=$(jq -r '.[-1].datetime' "$METRICS_FILE")

echo -e "${MAGENTA}🔍 ПОТОЧНИЙ СТАТУС:${NC}"
if [ "$current_status" = "up" ]; then
    echo -e "   ${GREEN}🟢 ONLINE${NC}"
else
    echo -e "   ${RED}🔴 OFFLINE${NC}"
fi
echo -e "   Остання перевірка: ${CYAN}$current_time${NC}"

# Час з останньої перевірки
if [ -f "$STATE_FILE.timestamp" ]; then
    last_check=$(tail -n 1 "$STATE_FILE.timestamp")
    current_epoch=$(date +%s)
    time_since=$((current_epoch - last_check))
    
    if [ $time_since -lt 60 ]; then
        echo -e "   ⏰ Час з останньої перевірки: ${GREEN}${time_since}с тому${NC}"
    elif [ $time_since -lt 1800 ]; then
        minutes=$((time_since / 60))
        echo -e "   ⏰ Час з останньої перевірки: ${YELLOW}${minutes}хв тому${NC}"
    else
        minutes=$((time_since / 60))
        echo -e "   ⏰ Час з останньої перевірки: ${RED}${minutes}хв тому (можлива проблема!)${NC}"
    fi
fi
echo ""

# ============== СЕРЕДНІЙ ЧАС ВІДПОВІДІ ==============
avg_response=$(jq '[.[] | select(.status == "up") | .response_time | tonumber] | add / length' "$METRICS_FILE" 2>/dev/null)
if [ -n "$avg_response" ] && [ "$avg_response" != "null" ]; then
    # Форматування до 3 знаків після коми
    avg_response=$(printf "%.3f" "$avg_response")
    echo -e "${MAGENTA}⚡ ПРОДУКТИВНІСТЬ:${NC}"
    echo -e "   Середній час відповіді: ${CYAN}${avg_response}s${NC}"
    
    # Мін/Макс час відповіді
    min_response=$(jq '[.[] | select(.status == "up") | .response_time | tonumber] | min' "$METRICS_FILE" 2>/dev/null)
    max_response=$(jq '[.[] | select(.status == "up") | .response_time | tonumber] | max' "$METRICS_FILE" 2>/dev/null)
    
    if [ -n "$min_response" ] && [ "$min_response" != "null" ]; then
        min_response=$(printf "%.3f" "$min_response")
        echo -e "   Мінімальний час: ${GREEN}${min_response}s${NC}"
    fi
    
    if [ -n "$max_response" ] && [ "$max_response" != "null" ]; then
        max_response=$(printf "%.3f" "$max_response")
        echo -e "   Максимальний час: ${YELLOW}${max_response}s${NC}"
    fi
    echo ""
fi

# ============== СТАТИСТИКА ЗА 24 ГОДИНИ ==============
echo -e "${MAGENTA}📅 СТАТИСТИКА ЗА ОСТАННІ 24 ГОДИНИ:${NC}"

# Час 24 години тому
time_24h_ago=$(date -d '24 hours ago' '+%s')

# Підрахунок за 24 години
total_24h=$(jq "[.[] | select(.timestamp > $time_24h_ago)] | length" "$METRICS_FILE")
up_24h=$(jq "[.[] | select(.timestamp > $time_24h_ago and .status == \"up\")] | length" "$METRICS_FILE")
down_24h=$(jq "[.[] | select(.timestamp > $time_24h_ago and .status == \"down\")] | length" "$METRICS_FILE")

if [ "$total_24h" -gt 0 ]; then
    uptime_24h=$(echo "scale=2; ($up_24h / $total_24h) * 100" | bc)
    echo -e "   Перевірок: ${BLUE}$total_24h${NC}"
    echo -e "   Uptime 24h: ${GREEN}${uptime_24h}%${NC}"
else
    echo -e "   ${YELLOW}Недостатньо даних за 24 години${NC}"
fi
echo ""

# ============== ОСТАННІ ПОДІЇ ==============
echo -e "${MAGENTA}📝 ОСТАННІ 10 ПОДІЙ:${NC}"

jq -r '.[-10:] | reverse | .[] | 
    if .status == "up" then
        "\(.datetime) - ✅ UP (\(.response_time)s)"
    else
        "\(.datetime) - ❌ DOWN"
    end' "$METRICS_FILE" | while read -r line; do
    if [[ "$line" == *"✅"* ]]; then
        echo -e "   ${GREEN}$line${NC}"
    else
        echo -e "   ${RED}$line${NC}"
    fi
done

echo ""

# ============== ОСТАННІ ПОМИЛКИ З ЛОГІВ ==============
if [ -f "$LOG_FILE" ]; then
    error_count=$(grep -c "ERROR" "$LOG_FILE" 2>/dev/null || echo "0")
    if [ "$error_count" -gt 0 ]; then
        echo -e "${MAGENTA}⚠️  ОСТАННІ ПОМИЛКИ В ЛОГАХ:${NC}"
        echo -e "${RED}"
        tail -n 100 "$LOG_FILE" | grep "ERROR" | tail -n 5 | sed 's/^/   /'
        echo -e "${NC}"
    fi
fi

# ============== КОМАНДИ ==============
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}📋 КОРИСНІ КОМАНДИ:${NC}"
echo ""
echo -e "  ${CYAN}Перегляд логів (реальний час):${NC}"
echo "    tail -f /opt/watchdog/logs/watchdog.log"
echo ""
echo -e "  ${CYAN}Перегляд метрик (JSON):${NC}"
echo "    cat /opt/watchdog/logs/metrics.json | jq ."
echo ""
echo -e "  ${CYAN}Ручний запуск перевірки:${NC}"
echo "    sudo systemctl start watchdog-proxy.service"
echo ""
echo -e "  ${CYAN}Статус timer:${NC}"
echo "    sudo systemctl status watchdog-proxy.timer"
echo ""
echo -e "  ${CYAN}Перезапуск watchdog:${NC}"
echo "    sudo systemctl restart watchdog-proxy.timer"
echo ""
echo -e "  ${CYAN}Відключення watchdog:${NC}"
echo "    sudo systemctl stop watchdog-proxy.timer"
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo ""