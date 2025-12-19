#!/bin/bash

#═══════════════════════════════════════════════════════════════════
#  TAILSCALE VPN/PROXY WATCHDOG FOR DEBIAN
#  Моніторинг Termux SOCKS5 Proxy через Tailscale мережу
#═══════════════════════════════════════════════════════════════════

# ============== КОНФІГУРАЦІЯ ==============

PROXY_HOST="100.100.74.9"
PROXY_PORT="9888"
PROXY_TYPE="socks5"
PROXY_URL="socks5://${PROXY_HOST}:${PROXY_PORT}"

WORKER_URL="https://watchdog-notifier.maxfraieho.workers.dev/"
TELEGRAM_TOKEN="8508516661:AAEQBWvlBk3v62nd5ut3ei70TPFJTkV9LMs"
TELEGRAM_CHAT_IDS="6412868393,347567237"

CHECK_TIMEOUT=10
MAX_RETRIES=3
RETRY_DELAY=5
TEST_URL="http://example.com"

BASE_DIR="/opt/watchdog"
LOG_DIR="${BASE_DIR}/logs"
LOG_FILE="${LOG_DIR}/watchdog.log"
STATE_FILE="${LOG_DIR}/watchdog.state"
ERROR_COUNT_FILE="${LOG_DIR}/error_count.txt"
METRICS_FILE="${LOG_DIR}/metrics.json"

mkdir -p "$LOG_DIR"

# ============== ФУНКЦІЇ ==============

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local color=$NC
    
    case $level in
        ERROR)   color=$RED ;;
        WARN)    color=$YELLOW ;;
        INFO)    color=$GREEN ;;
        DEBUG)   color=$BLUE ;;
    esac
    
    echo -e "${color}[$timestamp] [$level]${NC} $message" | tee -a "$LOG_FILE"
}

check_tailscale() {
    log "DEBUG" "Перевірка Tailscale з'єднання..."
    
    if ! tailscale status &>/dev/null; then
        log "ERROR" "Tailscale не запущено або не підключено"
        return 1
    fi
    
    if ! tailscale status | grep -q "$PROXY_HOST"; then
        log "WARN" "Пристрій $PROXY_HOST не знайдено в Tailscale мережі"
        if ! ping -c 1 -W 2 "$PROXY_HOST" &>/dev/null; then
            log "ERROR" "Пристрій $PROXY_HOST недоступний через Tailscale"
            return 1
        fi
    fi
    
    log "DEBUG" "✓ Tailscale з'єднання активне"
    return 0
}

check_socks_proxy() {
    local attempt=$1
    log "DEBUG" "SOCKS5 Proxy перевірка (спроба $attempt)..."
    
    local start_check=$(date +%s.%N)
    local proxy_test=$(curl -s -o /dev/null -w "%{http_code}" \
        --socks5 "${PROXY_HOST}:${PROXY_PORT}" \
        --connect-timeout $CHECK_TIMEOUT \
        --max-time $((CHECK_TIMEOUT + 5)) \
        "$TEST_URL" 2>&1)
    
    local curl_exit=$?
    local end_check=$(date +%s.%N)
    local check_time=$(echo "$end_check - $start_check" | bc)
    
    # Перевірка: curl має успішно завершитись (exit 0) І HTTP код має бути 200-399
    if [ $curl_exit -eq 0 ] && [ "$proxy_test" != "000" ] && [ "$proxy_test" -ge 200 ] 2>/dev/null && [ "$proxy_test" -lt 400 ] 2>/dev/null; then
        log "INFO" "✓ SOCKS5 Proxy функціональний (HTTP $proxy_test, ${check_time}s)"
        return 0
    else
        if [ "$proxy_test" = "000" ]; then
            log "ERROR" "SOCKS5 Proxy не працює (HTTP 000 - немає відповіді від цільового сервера)"
        else
            log "ERROR" "SOCKS5 Proxy не працює (exit: $curl_exit, HTTP: $proxy_test)"
        fi
        return 1
    fi
}

check_proxy() {
    local retry_count=0
    
    if ! check_tailscale; then
        log "ERROR" "Tailscale недоступний, пропускаємо перевірку проксі"
        return 1
    fi
    
    while [ $retry_count -lt $MAX_RETRIES ]; do
        log "INFO" "Перевірка SOCKS5 $PROXY_HOST:$PROXY_PORT (спроба $((retry_count + 1))/$MAX_RETRIES)..."
        
        if check_socks_proxy $((retry_count + 1)); then
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $MAX_RETRIES ]; then
            log "INFO" "Очікування $RETRY_DELAY сек перед наступною спробою..."
            sleep $RETRY_DELAY
        fi
    done
    
    log "ERROR" "✗ SOCKS5 Proxy недоступний після $MAX_RETRIES спроб"
    return 1
}

send_notification() {
    local message="$1"

    log "INFO" "Відправка сповіщення в Telegram..."

    # Використовуємо jq для правильного екранування JSON
    local payload=$(jq -n \
        --arg token "$TELEGRAM_TOKEN" \
        --arg chat_id "$TELEGRAM_CHAT_IDS" \
        --arg message "$message" \
        '{token: $token, chat_id: $chat_id, message: $message}')

    local response=$(curl -s -X POST "$WORKER_URL" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        --max-time 30 2>&1)
    
    if echo "$response" | grep -q '"success":true'; then
        log "INFO" "✓ Сповіщення успішно відправлено"
        return 0
    else
        log "ERROR" "✗ Помилка відправки: $response"
        return 1
    fi
}

get_last_state() {
    [ -f "$STATE_FILE" ] && cat "$STATE_FILE" || echo "unknown"
}

save_state() {
    echo "$1" > "$STATE_FILE"
    echo "$1" > "${STATE_FILE}.timestamp"
    date '+%s' >> "${STATE_FILE}.timestamp"
}

get_error_count() {
    [ -f "$ERROR_COUNT_FILE" ] && cat "$ERROR_COUNT_FILE" || echo "0"
}

increment_error_count() {
    echo $(($(get_error_count) + 1)) > "$ERROR_COUNT_FILE"
}

reset_error_count() {
    echo "0" > "$ERROR_COUNT_FILE"
}

save_metrics() {
    local status=$1
    local response_time=${2:-0}
    local timestamp=$(date '+%s')
    local datetime=$(date '+%Y-%m-%d %H:%M:%S')

    # Використовуємо jq для створення валідного JSON
    local metric=$(jq -n \
        --argjson timestamp "$timestamp" \
        --arg datetime "$datetime" \
        --arg status "$status" \
        --argjson response_time "$response_time" \
        --arg proxy_host "$PROXY_HOST" \
        --argjson proxy_port "$PROXY_PORT" \
        '{timestamp: $timestamp, datetime: $datetime, status: $status, response_time: $response_time, proxy_host: $proxy_host, proxy_port: $proxy_port}')

    if [ -f "$METRICS_FILE" ]; then
        jq ". += [$metric]" "$METRICS_FILE" > "${METRICS_FILE}.tmp" && mv "${METRICS_FILE}.tmp" "$METRICS_FILE"
    else
        echo "[$metric]" > "$METRICS_FILE"
    fi

    if [ -f "$METRICS_FILE" ]; then
        jq '.[-1000:]' "$METRICS_FILE" > "${METRICS_FILE}.tmp" && mv "${METRICS_FILE}.tmp" "$METRICS_FILE"
    fi
}

calculate_uptime() {
    if [ ! -f "$METRICS_FILE" ]; then
        echo "N/A"
        return
    fi
    
    local total=$(jq 'length' "$METRICS_FILE")
    local up=$(jq '[.[] | select(.status == "up")] | length' "$METRICS_FILE")
    
    if [ "$total" -gt 0 ]; then
        echo "scale=2; ($up / $total) * 100" | bc
    else
        echo "N/A"
    fi
}

get_downtime_duration() {
    if [ ! -f "${STATE_FILE}.timestamp" ]; then
        echo "невідомо"
        return
    fi
    
    local down_time=$(tail -n 1 "${STATE_FILE}.timestamp")
    local current_time=$(date '+%s')
    local duration=$((current_time - down_time))
    
    local hours=$((duration / 3600))
    local minutes=$(((duration % 3600) / 60))
    local seconds=$((duration % 60))
    
    if [ $hours -gt 0 ]; then
        echo "${hours}г ${minutes}хв ${seconds}с"
    elif [ $minutes -gt 0 ]; then
        echo "${minutes}хв ${seconds}с"
    else
        echo "${seconds}с"
    fi
}

get_system_info() {
    local hostname=$(hostname)
    local tailscale_ip=$(tailscale ip -4 2>/dev/null | head -n1)
    local uptime=$(uptime -p)

    printf "🖥 Хост: %s\n" "$hostname"
    printf "🌐 Tailscale IP: %s\n" "$tailscale_ip"
    printf "⏱ Uptime: %s" "$uptime"
}

# ============== ГОЛОВНА ЛОГІКА ==============

main() {
    log "INFO" "=========================================="
    log "INFO" "   WATCHDOG START"
    log "INFO" "=========================================="
    log "INFO" "Проксі: socks5://$PROXY_HOST:$PROXY_PORT"
    log "INFO" "Worker: $WORKER_URL"
    log "INFO" "Tailscale: $(tailscale status --json | jq -r '.Self.HostName' 2>/dev/null || echo 'N/A')"
    
    if [[ "$TELEGRAM_TOKEN" == *"ВАШ_ТОКЕН"* ]] || [[ "$WORKER_URL" == *"YOUR_SUBDOMAIN"* ]]; then
        log "ERROR" "❌ Конфігурація не завершена! Заповніть TELEGRAM_TOKEN та WORKER_URL"
        exit 1
    fi
    
    for cmd in curl jq tailscale bc; do
        if ! command -v $cmd &> /dev/null; then
            log "ERROR" "Команда '$cmd' не знайдена. Встановіть: sudo apt install $cmd"
            exit 1
        fi
    done
    
    local start_time=$(date +%s.%N)
    local current_time=$(date '+%Y-%m-%d %H:%M:%S')
    local last_state=$(get_last_state)
    local error_count=$(get_error_count)
    
    if check_proxy; then
        local end_time=$(date +%s.%N)
        local response_time=$(echo "$end_time - $start_time" | bc)
        
        save_metrics "up" "$response_time"
        
        if [ "$last_state" = "down" ]; then
            local downtime=$(get_downtime_duration)
            local uptime=$(calculate_uptime)

            log "INFO" "🟢 ПРОКСІ ВІДНОВЛЕНО!"

            local message=$(printf "✅ *PROXY RECOVERED*\n\n🕐 Час: %s\n🌐 Проксі: socks5://%s:%s\n⏱ Час простою: %s\n📊 Uptime: %s%%\n⚡ Час відповіді: %ss\n📈 Статус: ONLINE\n\n%s" \
                "$current_time" "$PROXY_HOST" "$PROXY_PORT" "$downtime" "$uptime" "$response_time" "$(get_system_info)")

            send_notification "$message"
            reset_error_count
        else
            log "INFO" "✓ Проксі працює нормально (${response_time}s)"
        fi
        
        save_state "up"
        
    else
        increment_error_count
        error_count=$(get_error_count)
        
        save_metrics "down" "0"
        
        if [ "$last_state" != "down" ]; then
            log "ERROR" "🔴 ПРОКСІ ВПАВ!"

            # Отримуємо тільки статус Tailscale пристрою (online/offline)
            local device_online="offline"
            if tailscale status | grep -q "$PROXY_HOST.*active"; then
                device_online="online"
            fi

            local message=$(printf "🚨 *PROXY DOWN DETECTED*\n\n🕐 Час: %s\n🌐 Проксі: socks5://%s:%s\n❌ Причина: Немає відповіді від сервера\n🔄 Спроб підключення: %s\n📡 Tailscale: %s\n📊 Статус: OFFLINE\n\n%s" \
                "$current_time" "$PROXY_HOST" "$PROXY_PORT" "$MAX_RETRIES" "$device_online" "$(get_system_info)")

            send_notification "$message"
            
        else
            log "WARN" "⚠️  Проксі досі недоступний (помилок: $error_count)"
            
            if [ $((error_count % 5)) -eq 0 ]; then
                local downtime=$(get_downtime_duration)

                local message=$(printf "⚠️ *PROXY STILL DOWN*\n\n🕐 Час: %s\n🌐 Проксі: socks5://%s:%s\n📈 Послідовних помилок: %s\n⏱ Загальний час простою: %s\n🔧 Рекомендація: Перевірте Termux та SOCKS5 службу" \
                    "$current_time" "$PROXY_HOST" "$PROXY_PORT" "$error_count" "$downtime")

                send_notification "$message"
            fi
        fi
        
        save_state "down"
    fi
    
    log "INFO" "=========================================="
    log "INFO" "   WATCHDOG END"
    log "INFO" "=========================================="
}

trap 'log "WARN" "Отримано сигнал переривання"; exit 130' INT TERM

main


### ============================================================
### UPDATE MODE — Перезапуск служб після оновлення
### ============================================================

if [ "${IS_UPDATE:-0}" -eq 1 ]; then
    echo ""
    echo -e "${BLUE}▶ Завершення оновлення та запуск служб${NC}"
    sudo systemctl daemon-reload
    sudo systemctl enable watchdog-proxy.timer
    sudo systemctl start watchdog-proxy.timer
    echo -e "${GREEN}✓ Оновлення завершено успішно${NC}"
else
    echo ""
    echo -e "${GREEN}✓ Нова інсталяція завершена${NC}"
    sudo systemctl daemon-reload
    sudo systemctl enable watchdog-proxy.timer
    sudo systemctl start watchdog-proxy.timer
fi


exit 0
