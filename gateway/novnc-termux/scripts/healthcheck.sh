#!/data/data/com.termux/files/usr/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib_config.sh"

OVERALL_STATUS=0

usage() {
    echo "Usage: $0 [workspace_id|all]"
    echo ""
    echo "  workspace_id:  a, b, or all (default: all)"
    exit 1
}

check_process_by_pid() {
    local pid_file="$1"
    local name="$2"

    if [ ! -f "$pid_file" ]; then
        echo -e "  ${RED}[FAIL]${NC} $name: no PID file"
        OVERALL_STATUS=1
        return 1
    fi

    local pid
    pid=$(cat "$pid_file" 2>/dev/null)

    if [ -z "$pid" ]; then
        echo -e "  ${RED}[FAIL]${NC} $name: empty PID file"
        OVERALL_STATUS=1
        return 1
    fi

    if kill -0 "$pid" 2>/dev/null; then
        echo -e "  ${GREEN}[ OK ]${NC} $name: running (PID $pid)"
        return 0
    else
        echo -e "  ${RED}[FAIL]${NC} $name: not running (stale PID $pid)"
        OVERALL_STATUS=1
        return 1
    fi
}

check_process_by_pattern() {
    local pattern="$1"
    local name="$2"

    local pid
    pid=$(pgrep -f "$pattern" 2>/dev/null | head -1)

    if [ -n "$pid" ]; then
        echo -e "  ${GREEN}[ OK ]${NC} $name: running (PID $pid)"
        return 0
    else
        echo -e "  ${RED}[FAIL]${NC} $name: not running"
        OVERALL_STATUS=1
        return 1
    fi
}

check_port() {
    local port="$1"
    local name="$2"

    if ss -tln 2>/dev/null | grep -q ":${port} " || \
       netstat -tln 2>/dev/null | grep -q ":${port} "; then
        echo -e "  ${GREEN}[ OK ]${NC} $name: port $port listening"
        return 0
    else
        echo -e "  ${RED}[FAIL]${NC} $name: port $port not listening"
        OVERALL_STATUS=1
        return 1
    fi
}

check_novnc_http() {
    local port="$1"
    local name="$2"

    if command -v curl &>/dev/null; then
        if curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${port}/vnc.html" 2>/dev/null | grep -q "200"; then
            echo -e "  ${GREEN}[ OK ]${NC} $name: HTTP 200 on port $port"
            return 0
        else
            echo -e "  ${YELLOW}[WARN]${NC} $name: HTTP check failed on port $port (port may still be ok)"
            return 0
        fi
    fi
    return 0
}

check_single_workspace() {
    local ws_id="$1"
    local config
    config=$(get_ws_config "$ws_id")
    if [ -z "$config" ]; then
        echo -e "${RED}[ERR] Unknown workspace: $ws_id${NC}"
        OVERALL_STATUS=1
        return 1
    fi

    local display vnc_port novnc_port geometry depth base_dir bind_host
    read -r display vnc_port novnc_port geometry depth base_dir bind_host <<< "$config"

    local pid_dir="$base_dir/run"
    local vnc_pid_file="$pid_dir/vnc.pid"
    local ws_pid_file="$pid_dir/websockify.pid"

    echo ""
    echo -e "${BLUE}--- Workspace ${ws_id^^} (display :$display) ---${NC}"

    if ! check_process_by_pid "$vnc_pid_file" "Xvnc :$display"; then
        check_process_by_pattern "Xvnc.*:${display}" "Xvnc :$display (by pattern)"
    fi

    check_port "$vnc_port" "VNC port"

    if ! check_process_by_pid "$ws_pid_file" "websockify"; then
        check_process_by_pattern "websockify.*${novnc_port}" "websockify (by pattern)"
    fi

    check_port "$novnc_port" "noVNC port"
    check_novnc_http "$novnc_port" "noVNC HTTP"

    local log_dir="$base_dir/logs"
    if [ -f "$log_dir/vnc.log" ]; then
        local vnc_errors
        vnc_errors=$(grep -i "error\|fatal\|failed" "$log_dir/vnc.log" 2>/dev/null | tail -3)
        if [ -n "$vnc_errors" ]; then
            echo -e "  ${YELLOW}[WARN]${NC} Recent VNC log errors:"
            echo "$vnc_errors" | sed 's/^/         /'
        fi
    fi
    if [ -f "$log_dir/websockify.log" ]; then
        local ws_errors
        ws_errors=$(grep -i "error\|fatal\|failed" "$log_dir/websockify.log" 2>/dev/null | tail -3)
        if [ -n "$ws_errors" ]; then
            echo -e "  ${YELLOW}[WARN]${NC} Recent websockify log errors:"
            echo "$ws_errors" | sed 's/^/         /'
        fi
    fi
}

# ─── Main ────────────────────────────────────────────────────────

TARGET="${1:-all}"

echo -e "${BLUE}=======================================${NC}"
echo -e "${BLUE} SwissWorkspaceGateway — Healthcheck${NC}"
echo -e "${BLUE}=======================================${NC}"

echo ""
echo -e "${BLUE}--- Infrastructure ---${NC}"
if command -v tailscale &>/dev/null; then
    if tailscale status &>/dev/null 2>&1; then
        local_ip=$(tailscale ip -4 2>/dev/null || echo "unknown")
        echo -e "  ${GREEN}[ OK ]${NC} Tailscale: connected ($local_ip)"
    else
        echo -e "  ${YELLOW}[WARN]${NC} Tailscale: not connected"
    fi
else
    echo -e "  ${YELLOW}[WARN]${NC} Tailscale: not installed"
fi

if command -v termux-wake-lock &>/dev/null; then
    echo -e "  ${GREEN}[ OK ]${NC} termux-wake-lock: available"
else
    echo -e "  ${YELLOW}[WARN]${NC} termux-wake-lock: not available (processes may be killed)"
fi

echo -e "  ${BLUE}[CFG ]${NC} VNC security: $VNC_SECURITY"
echo -e "  ${BLUE}[CFG ]${NC} websockify bind: $WEBSOCKIFY_BIND"
echo -e "  ${BLUE}[CFG ]${NC} Config: $CONFIG_FILE"

case "$TARGET" in
    all)
        while IFS= read -r ws_id; do
            check_single_workspace "$ws_id"
        done < <(get_all_ws_ids)
        ;;
    *)
        check_single_workspace "$TARGET"
        ;;
esac

echo ""
echo -e "${BLUE}=======================================${NC}"
if [ $OVERALL_STATUS -eq 0 ]; then
    echo -e "${GREEN} All checks passed${NC}"
else
    echo -e "${RED} Some checks failed (exit code $OVERALL_STATUS)${NC}"
fi
echo -e "${BLUE}=======================================${NC}"

exit $OVERALL_STATUS
