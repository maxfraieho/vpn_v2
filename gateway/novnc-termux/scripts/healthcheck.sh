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

hc_ok()   { echo -e "  ${GREEN}[ OK ]${NC} $1"; }
hc_fail() { echo -e "  ${RED}[FAIL]${NC} $1"; OVERALL_STATUS=1; }
hc_warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; }
hc_cfg()  { echo -e "  ${BLUE}[CFG ]${NC} $1"; }

check_single_workspace() {
    local ws_id="$1"
    local config
    config=$(get_ws_config "$ws_id")
    if [ -z "$config" ]; then
        hc_fail "Unknown workspace: $ws_id"
        return
    fi

    local display vnc_port novnc_port geometry depth base_dir bind_host
    read -r display vnc_port novnc_port geometry depth base_dir bind_host <<< "$config"

    local pid_dir="$base_dir/run"
    local ws_pid_file="$pid_dir/websockify.pid"
    local log_dir="$base_dir/logs"

    echo ""
    echo -e "${BLUE}--- Workspace ${ws_id^^} (display :$display) ---${NC}"

    # ─── VNC check: Debian-side nc with correct HOME ─────────────
    local vnc_up=false
    if proot-distro login "$PROOT_DISTRO" --shared-tmp -- bash -c "
        export HOME='$base_dir'
        nc -z 127.0.0.1 $vnc_port
    " 2>/dev/null; then
        vnc_up=true
        hc_ok "Xvnc :$display: port $vnc_port listening (Debian-side, HOME=$base_dir)"
    else
        local deb_ps
        deb_ps=$(proot-distro login "$PROOT_DISTRO" --shared-tmp -- bash -c \
            "ps -ef 2>/dev/null | grep -E 'Xtigervnc.*:${display}|Xvnc.*:${display}' | grep -v grep" 2>/dev/null || true)
        if [ -n "$deb_ps" ]; then
            vnc_up=true
            hc_ok "Xvnc :$display: process found inside Debian (port not yet responding)"
        else
            hc_fail "Xvnc :$display: not running (no port, no process inside Debian)"
        fi
    fi

    # ─── websockify process check ────────────────────────────────
    if check_pid_alive "$ws_pid_file"; then
        local ws_pid
        ws_pid=$(cat "$ws_pid_file")
        hc_ok "websockify: running (PID $ws_pid)"
    else
        local ws_pid
        ws_pid=$(pgrep -f "websockify.*${novnc_port}" 2>/dev/null | head -1 || true)
        if [ -n "$ws_pid" ]; then
            hc_ok "websockify: running (PID $ws_pid, no pidfile)"
        else
            hc_fail "websockify: not running"
        fi
    fi

    # ─── noVNC port check (Debian-side nc) ────────────────────────
    local novnc_check_host="${WEBSOCKIFY_BIND:-127.0.0.1}"
    if [ "$novnc_check_host" = "__UNSET__" ] || [ "$novnc_check_host" = "0.0.0.0" ]; then
        novnc_check_host="127.0.0.1"
    fi
    if proot-distro login "$PROOT_DISTRO" --shared-tmp -- nc -z "$novnc_check_host" "$novnc_port" 2>/dev/null; then
        hc_ok "noVNC port: port $novnc_port listening"
    else
        hc_fail "noVNC port: port $novnc_port not listening"
    fi

    # ─── noVNC HTTP check (via Debian curl/wget) ─────────────────
    local http_url="http://${novnc_check_host}:${novnc_port}/vnc.html"
    local http_code
    http_code=$(proot-distro login "$PROOT_DISTRO" --shared-tmp -- bash -c "
        if command -v curl &>/dev/null; then
            curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 '$http_url' 2>/dev/null
        elif command -v wget &>/dev/null; then
            wget -q --spider -S '$http_url' 2>&1 | grep 'HTTP/' | tail -1 | awk '{print \$2}'
        else
            echo 'nocurl'
        fi
    " 2>/dev/null || echo "error")
    if [ "$http_code" = "200" ] || [ "$http_code" = "302" ]; then
        hc_ok "noVNC HTTP: HTTP $http_code on port $novnc_port"
    elif [ "$http_code" = "nocurl" ]; then
        hc_warn "noVNC HTTP: curl/wget not available inside Debian (skipped)"
    else
        hc_fail "noVNC HTTP: expected 200, got ${http_code:-timeout} on port $novnc_port"
    fi

    # ─── Log location check: per-workspace vs /root leak ─────────
    local ws_tigervnc_cfg="$base_dir/.config/tigervnc"
    local ws_log_found=false
    shopt -s nullglob
    for f in "$ws_tigervnc_cfg"/*":${display}.log"; do
        if [ -f "$f" ]; then
            ws_log_found=true
            hc_ok "TigerVNC log: $f (per-workspace, correct)"
            break
        fi
    done
    shopt -u nullglob
    if [ "$ws_log_found" = false ]; then
        local root_log_found=false
        root_log_found=$(proot-distro login "$PROOT_DISTRO" --shared-tmp -- bash -c "
            for f in /root/.config/tigervnc/*:${display}.log; do
                [ -f \"\$f\" ] && echo 'yes' && break
            done
        " 2>/dev/null || true)
        if [ "$root_log_found" = "yes" ]; then
            hc_fail "TigerVNC log: HOME leaked to /root! Logs in /root/.config/tigervnc/ instead of $ws_tigervnc_cfg/"
            proot-distro login "$PROOT_DISTRO" --shared-tmp -- bash -c "
                ls -la /root/.config/tigervnc/*:${display}.log 2>/dev/null
            " 2>/dev/null | sed 's/^/         /' || true
        else
            hc_warn "TigerVNC log: not found in $ws_tigervnc_cfg/ or /root/ for display :$display"
        fi
    fi

    # ─── Log warnings (non-fatal) ────────────────────────────────
    if [ -f "$log_dir/vnc.log" ]; then
        local vnc_errors
        vnc_errors=$(grep -iE "fatal|failed to start|password.*not found" "$log_dir/vnc.log" 2>/dev/null | tail -3 || true)
        if [ -n "$vnc_errors" ]; then
            hc_warn "Recent VNC log errors:"
            echo "$vnc_errors" | sed 's/^/         /'
        fi
    fi
    shopt -s nullglob
    for f in "$ws_tigervnc_cfg"/*":${display}.log"; do
        if [ -f "$f" ]; then
            local session_errors
            session_errors=$(grep -iE "fatal|error|failed|abort" "$f" 2>/dev/null | tail -5 || true)
            if [ -n "$session_errors" ]; then
                hc_warn "TigerVNC session log errors ($f):"
                echo "$session_errors" | sed 's/^/         /'
            fi
        fi
    done
    shopt -u nullglob
    if [ -f "$log_dir/websockify.log" ]; then
        local ws_errors
        ws_errors=$(grep -iE "error|fatal|failed" "$log_dir/websockify.log" 2>/dev/null | tail -3 || true)
        if [ -n "$ws_errors" ]; then
            hc_warn "Recent websockify log errors:"
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
        hc_ok "Tailscale: connected ($local_ip)"
    else
        hc_warn "Tailscale: not connected"
    fi
else
    if [ "${WEBSOCKIFY_BIND:-__UNSET__}" != "__UNSET__" ]; then
        hc_cfg "Tailscale CLI: not installed (WEBSOCKIFY_BIND=$WEBSOCKIFY_BIND from .env)"
    else
        hc_warn "Tailscale: not installed and WEBSOCKIFY_BIND not set"
    fi
fi

if command -v termux-wake-lock &>/dev/null; then
    hc_ok "termux-wake-lock: available"
else
    hc_warn "termux-wake-lock: not available (processes may be killed)"
fi

hc_cfg "VNC security: ${VNC_SECURITY:-VncAuth}"
hc_cfg "websockify bind: ${WEBSOCKIFY_BIND:-__UNSET__}"
hc_cfg "START_BROWSER: ${START_BROWSER:-0}"
hc_cfg "BROWSER: ${BROWSER:-firefox}"
hc_cfg "Config: $CONFIG_FILE"

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
