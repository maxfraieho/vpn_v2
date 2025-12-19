#!/bin/bash

#═══════════════════════════════════════════════════════════════════
#  WATCHDOG INSTALLER (Optimized)
#  Автоматична установка Watchdog для моніторингу SOCKS5 проксі
#═══════════════════════════════════════════════════════════════════

set -e

# Кольори
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Константи
INSTALL_DIR="/opt/watchdog"
CURRENT_USER=$(whoami)

echo -e "${CYAN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════╗
║                                                       ║
║   TAILSCALE SOCKS5 WATCHDOG - INSTALLER              ║
║   Моніторинг Termux SOCKS5 через Tailscale           ║
║                                                       ║
╚═══════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Перевірка root
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}❌ Не запускайте цей скрипт від root!${NC}"
    echo -e "Використовуйте: ${YELLOW}./install.sh${NC}"
    exit 1
fi
### ============================================================
### UPDATE MODE — Виявлення попередньої інсталяції
### ============================================================

IS_UPDATE=0
TIMER_FILE="/etc/systemd/system/watchdog-proxy.timer"
SERVICE_FILE="/etc/systemd/system/watchdog-proxy.service"

if [ -f "$INSTALL_DIR/watchdog.sh" ]; then
    echo ""
    echo -e "${YELLOW}Попередня інсталяція Watchdog знайдена.${NC}"
    read -p "Оновити її (зберігаючи конфігурацію)? (y/n): " upd

    if [[ "$upd" =~ ^[Yy]$ ]]; then
        IS_UPDATE=1
        echo -e "${CYAN}Режим: ОНОВЛЕННЯ${NC}"

        echo -e "${BLUE}▶ Зупинка служб...${NC}"
        sudo systemctl stop watchdog-proxy.timer 2>/dev/null || true
        sudo systemctl stop watchdog-proxy.service 2>/dev/null || true
        sudo systemctl disable watchdog-proxy.timer 2>/dev/null || true
        sudo systemctl disable watchdog-proxy.service 2>/dev/null || true
        echo -e "${GREEN}✓ Служби зупинено${NC}"
    else
        echo -e "${CYAN}Режим: чиста інсталяція${NC}"
    fi
else
    echo -e "${GREEN}Попередню інсталяцію не знайдено.${NC}"
fi



# Функція для виводу кроків
step() {
    echo ""
    echo -e "${BLUE}▶ $1${NC}"
    echo "─────────────────────────────────────────"
}

# Функція для введення
prompt() {
    local prompt_text="$1"
    local var_name="$2"
    local default_value="$3"
    
    if [ -n "$default_value" ]; then
        read -p "$(echo -e ${CYAN}$prompt_text ${MAGENTA}[$default_value]${CYAN}: ${NC})" input
        eval "$var_name=\"${input:-$default_value}\""
    else
        read -p "$(echo -e ${CYAN}$prompt_text: ${NC})" input
        while [ -z "$input" ]; do
            echo -e "${RED}Це поле обов'язкове!${NC}"
            read -p "$(echo -e ${CYAN}$prompt_text: ${NC})" input
        done
        eval "$var_name=\"$input\""
    fi
}

# ============== КРОК 1: Перевірка залежностей ==============
step "Перевірка залежностей"

missing_packages=()

# Перевірка пакетів
for package in curl jq bc systemd; do
    if ! command -v $package &> /dev/null; then
        missing_packages+=($package)
        echo -e "${RED}✗${NC} $package не встановлено"
    else
        echo -e "${GREEN}✓${NC} $package"
    fi
done

# Перевірка Tailscale окремо
if ! command -v tailscale &> /dev/null; then
    echo -e "${RED}✗${NC} tailscale не встановлено"
    missing_packages+=("tailscale")
else
    echo -e "${GREEN}✓${NC} tailscale"
fi

if [ ${#missing_packages[@]} -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}⚠️  Відсутні пакети: ${missing_packages[*]}${NC}"
    echo ""
    read -p "Встановити відсутні пакети? (y/n): " install_deps
    
    if [[ "$install_deps" == "y" || "$install_deps" == "Y" ]]; then
        echo "Оновлення списку пакетів..."
        sudo apt update
        
        # Встановлення базових пакетів
        base_packages=(curl jq bc)
        to_install=()
        
        for pkg in "${base_packages[@]}"; do
            if [[ " ${missing_packages[@]} " =~ " ${pkg} " ]]; then
                to_install+=($pkg)
            fi
        done
        
        if [ ${#to_install[@]} -gt 0 ]; then
            echo "Встановлення: ${to_install[*]}"
            sudo apt install -y "${to_install[@]}"
        fi
        
        # Tailscale окремо
        if [[ " ${missing_packages[@]} " =~ " tailscale " ]]; then
            echo ""
            echo "Встановлення Tailscale..."
            curl -fsSL https://tailscale.com/install.sh | sh
            echo ""
            echo -e "${YELLOW}⚠️  Підключіть Tailscale:${NC}"
            echo "    sudo tailscale up"
            echo ""
            read -p "Натисніть Enter після підключення Tailscale..."
        fi
        
        echo -e "${GREEN}✓ Пакети встановлено${NC}"
    else
        echo -e "${RED}❌ Встановлення скасовано${NC}"
        exit 1
    fi
fi

# Перевірка Tailscale з'єднання
echo ""
if ! tailscale status &>/dev/null; then
    echo -e "${RED}❌ Tailscale не запущено або не підключено${NC}"
    echo ""
    echo "Підключіть Tailscale:"
    echo "  sudo tailscale up"
    echo ""
    read -p "Продовжити після підключення? (y/n): " continue_install
    if [[ "$continue_install" != "y" && "$continue_install" != "Y" ]]; then
        exit 1
    fi
    
    # Повторна перевірка
    if ! tailscale status &>/dev/null; then
        echo -e "${RED}❌ Tailscale все ще не підключено${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✓ Tailscale підключено${NC}"

# Показати Tailscale пристрої
echo ""
echo -e "${CYAN}Пристрої в Tailscale мережі:${NC}"
tailscale status | grep -v "^#" | head -n 10

# ============== КРОК 2: Збір конфігурації ==============
step "Налаштування конфігурації"

echo "Введіть параметри для Watchdog:"
echo ""

# Tailscale IP Termux
prompt "Tailscale IP адреса Termux (SOCKS5 сервер)" PROXY_HOST "100.100.74.9"

# Перевірка доступності
echo -e "${YELLOW}Перевірка доступності $PROXY_HOST...${NC}"
if ping -c 2 -W 3 "$PROXY_HOST" &>/dev/null; then
    echo -e "${GREEN}✓ Пристрій доступний в мережі${NC}"
else
    echo -e "${YELLOW}⚠️  Пристрій не відповідає на ping (може бути норма)${NC}"
fi

# Порт SOCKS5
echo ""
prompt "Порт SOCKS5 проксі" PROXY_PORT "9888"

# Тест SOCKS5
echo -e "${YELLOW}Тестування SOCKS5 ${PROXY_HOST}:${PROXY_PORT}...${NC}"
if curl -s --socks5 "${PROXY_HOST}:${PROXY_PORT}" --connect-timeout 5 --max-time 10 http://example.com &>/dev/null; then
    echo -e "${GREEN}✓ SOCKS5 проксі працює!${NC}"
else
    echo -e "${YELLOW}⚠️  Не вдалося підключитись до SOCKS5 (перевірте пізніше)${NC}"
fi

# Cloudflare Worker URL
echo ""
echo -e "${CYAN}Cloudflare Worker:${NC}"
echo "Якщо ще не створили Worker:"
echo "1. Зайдіть на https://dash.cloudflare.com"
echo "2. Workers & Pages → Create Worker"
echo "3. Скопіюйте код з артефакту 'cloudflare-worker'"
echo "4. Deploy і скопіюйте URL"
echo ""
prompt "URL Cloudflare Worker" WORKER_URL ""

while [[ ! "$WORKER_URL" =~ ^https:// ]]; do
    echo -e "${RED}URL має починатися з https://${NC}"
    prompt "URL Cloudflare Worker" WORKER_URL ""
done

# Тест Worker
echo -e "${YELLOW}Тестування Worker...${NC}"
worker_test=$(curl -s -X POST "$WORKER_URL" \
    -H "Content-Type: application/json" \
    -d '{"token":"test","chat_id":"test","message":"test"}' 2>&1)

if echo "$worker_test" | grep -q "Missing required fields\|Unauthorized"; then
    echo -e "${GREEN}✓ Worker доступний${NC}"
else
    echo -e "${YELLOW}⚠️  Worker може бути недоступний: $worker_test${NC}"
fi

# Telegram токен
echo ""
echo -e "${CYAN}Telegram Bot:${NC}"
echo "Якщо ще не створили бота:"
echo "1. Знайдіть @BotFather в Telegram"
echo "2. Відправте /newbot"
echo "3. Скопіюйте токен"
echo ""
prompt "Telegram Bot Token" TELEGRAM_TOKEN ""

# Простая валідація токена
if [[ ! "$TELEGRAM_TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
    echo -e "${YELLOW}⚠️  Токен має незвичний формат (але продовжимо)${NC}"
fi

# Telegram Chat ID
echo ""
echo "Для отримання Chat ID:"
echo "1. Надішліть повідомлення @userinfobot"
echo "2. Або відправте /start вашому боту і виконайте:"
echo "   curl 'https://api.telegram.org/bot${TELEGRAM_TOKEN}/getUpdates'"
echo ""
prompt "Telegram Chat ID" TELEGRAM_CHAT_ID ""

# Тест Telegram
echo -e "${YELLOW}Тестування Telegram...${NC}"
test_message="🧪 Тестове повідомлення від Watchdog Installer"
telegram_test=$(curl -s -X POST "$WORKER_URL" \
    -H "Content-Type: application/json" \
    -d "{\"token\":\"$TELEGRAM_TOKEN\",\"chat_id\":\"$TELEGRAM_CHAT_ID\",\"message\":\"$test_message\"}" 2>&1)

if echo "$telegram_test" | grep -q '"success":true'; then
    echo -e "${GREEN}✓ Тестове повідомлення відправлено в Telegram!${NC}"
else
    echo -e "${YELLOW}⚠️  Помилка відправки: $telegram_test${NC}"
    echo -e "${YELLOW}Перевірте Token та Chat ID${NC}"
    read -p "Продовжити встановлення? (y/n): " continue_anyway
    if [[ "$continue_anyway" != "y" && "$continue_anyway" != "Y" ]]; then
        exit 1
    fi
fi

# Інтервал перевірки
echo ""
prompt "Інтервал перевірки (хвилини)" CHECK_INTERVAL "20"

# ============== КРОК 3: Створення структури ==============
step "Створення структури директорій"

sudo mkdir -p "$INSTALL_DIR/logs"
sudo chown -R "$CURRENT_USER:$CURRENT_USER" "$INSTALL_DIR"

echo -e "${GREEN}✓${NC} $INSTALL_DIR"
echo -e "${GREEN}✓${NC} $INSTALL_DIR/logs"

# ============== КРОК 4: Створення watchdog.sh ==============
step "Створення головного скрипта"

cat > "$INSTALL_DIR/watchdog.sh" << 'WATCHDOG_SCRIPT'
#!/bin/bash

#═══════════════════════════════════════════════════════════════════
#  TAILSCALE VPN/PROXY WATCHDOG FOR DEBIAN
#  Моніторинг Termux SOCKS5 Proxy через Tailscale мережу
#═══════════════════════════════════════════════════════════════════

# ============== КОНФІГУРАЦІЯ ==============

PROXY_HOST="__PROXY_HOST__"
PROXY_PORT="__PROXY_PORT__"
PROXY_TYPE="socks5"
PROXY_URL="socks5://${PROXY_HOST}:${PROXY_PORT}"

WORKER_URL="__WORKER_URL__"
TELEGRAM_TOKEN="__TELEGRAM_TOKEN__"
TELEGRAM_CHAT_ID="__TELEGRAM_CHAT_ID__"

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
    
    if [ $curl_exit -eq 0 ]; then
        log "INFO" "✓ SOCKS5 Proxy функціональний (HTTP $proxy_test, ${check_time}s)"
        return 0
    else
        log "ERROR" "SOCKS5 Proxy не працює (exit: $curl_exit)"
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
    
    message=$(echo "$message" | sed 's/"/\\"/g')
    
    local payload=$(cat <<EOF
{
  "token": "$TELEGRAM_TOKEN",
  "chat_id": "$TELEGRAM_CHAT_ID",
  "message": "$message"
}
EOF
)
    
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
    local response_time=$2
    local timestamp=$(date '+%s')
    
    local metric=$(cat <<EOF
{
  "timestamp": $timestamp,
  "datetime": "$(date '+%Y-%m-%d %H:%M:%S')",
  "status": "$status",
  "response_time": $response_time,
  "proxy_host": "$PROXY_HOST",
  "proxy_port": $PROXY_PORT
}
EOF
)
    
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
    
    echo "🖥 Хост: \`$hostname\`"
    echo "🌐 Tailscale IP: \`$tailscale_ip\`"
    echo "⏱ Uptime: $uptime"
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
            
            local message="✅ *PROXY RECOVERED*\n\n"
            message+="🕐 Час: \`$current_time\`\n"
            message+="🌐 Проксі: \`socks5://$PROXY_HOST:$PROXY_PORT\`\n"
            message+="⏱ Час простою: $downtime\n"
            message+="📊 Uptime: ${uptime}%\n"
            message+="⚡ Час відповіді: ${response_time}s\n"
            message+="📈 Статус: ONLINE\n\n"
            message+="$(get_system_info)"
            
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
            
            local tailscale_status=$(tailscale status | grep "$PROXY_HOST" || echo "Пристрій не в мережі")
            
            local message="🚨 *PROXY DOWN DETECTED*\n\n"
            message+="🕐 Час: \`$current_time\`\n"
            message+="🌐 Проксі: \`socks5://$PROXY_HOST:$PROXY_PORT\`\n"
            message+="❌ Причина: Немає відповіді від сервера\n"
            message+="🔄 Спроб підключення: $MAX_RETRIES\n"
            message+="📡 Tailscale: \`$tailscale_status\`\n"
            message+="📊 Статус: OFFLINE\n\n"
            message+="$(get_system_info)"
            
            send_notification "$message"
            
        else
            log "WARN" "⚠️  Проксі досі недоступний (помилок: $error_count)"
            
            if [ $((error_count % 5)) -eq 0 ]; then
                local downtime=$(get_downtime_duration)
                
                local message="⚠️ *PROXY STILL DOWN*\n\n"
                message+="🕐 Час: \`$current_time\`\n"
                message+="🌐 Проксі: \`socks5://$PROXY_HOST:$PROXY_PORT\`\n"
                message+="📈 Послідовних помилок: $error_count\n"
                message+="⏱ Загальний час простою: $downtime\n"
                message+="🔧 Рекомендація: Перевірте Termux та SOCKS5 службу"
                
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

if [ $IS_UPDATE -eq 1 ]; then
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
WATCHDOG_SCRIPT

# Заміна плейсхолдерів
sed -i "s|__PROXY_HOST__|$PROXY_HOST|g" "$INSTALL_DIR/watchdog.sh"
sed -i "s|__PROXY_PORT__|$PROXY_PORT|g" "$INSTALL_DIR/watchdog.sh"
sed -i "s|__WORKER_URL__|$WORKER_URL|g" "$INSTALL_DIR/watchdog.sh"
sed -i "s|__TELEGRAM_TOKEN__|$TELEGRAM_TOKEN|g" "$INSTALL_DIR/watchdog.sh"
sed -i "s|__TELEGRAM_CHAT_ID__|$TELEGRAM_CHAT_ID|g" "$INSTALL_DIR/watchdog.sh"

chmod +x "$INSTALL_DIR/watchdog.sh"

echo -e "${GREEN}✓${NC} $INSTALL_DIR/watchdog.sh"

# ============== КРОК 5: Створення systemd сервісів ==============
step "Налаштування systemd"

sudo tee /etc/systemd/system/watchdog-proxy.service > /dev/null << EOF
[Unit]
Description=Tailscale SOCKS5 Proxy Watchdog
After=network.target tailscaled.service
Wants=tailscaled.service

[Service]
Type=oneshot
User=$CURRENT_USER
Group=$CURRENT_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/watchdog.sh
StandardOutput=append:$INSTALL_DIR/logs/systemd.log
StandardError=append:$INSTALL_DIR/logs/systemd-error.log
MemoryLimit=256M
CPUQuota=50%
TimeoutStartSec=60
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF

echo -e "${GREEN}✓${NC} /etc/systemd/system/watchdog-proxy.service"

sudo tee /etc/systemd/system/watchdog-proxy.timer > /dev/null << EOF
[Unit]
Description=Tailscale SOCKS5 Proxy Watchdog Timer
Requires=watchdog-proxy.service

[Timer]
OnBootSec=2min
OnUnitActiveSec=${CHECK_INTERVAL}min
AccuracySec=1min
Persistent=true

[Install]
WantedBy=timers.target
EOF

echo -e "${GREEN}✓${NC} /etc/systemd/system/watchdog-proxy.timer"

sudo systemctl daemon-reload

echo -e "${GREEN}✓${NC} Systemd перезавантажено"

# ============== КРОК 6: Створення dashboard ==============
step "Створення dashboard (опціонально)"

cat > "$INSTALL_DIR/dashboard.sh" << 'DASHBOARD_SCRIPT'
#!/bin/bash

METRICS_FILE="/opt/watchdog/logs/metrics.json"
LOG_FILE="/opt/watchdog/logs/watchdog.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

clear
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}     TAILSCALE SOCKS5 WATCHDOG DASHBOARD${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo ""

if [ ! -f "$METRICS_FILE" ]; then
    echo -e "${RED}❌ Метрики ще не зібрані. Запустіть watchdog спочатку.${NC}"
    exit 1