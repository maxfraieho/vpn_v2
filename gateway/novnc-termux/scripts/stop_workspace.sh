#!/data/data/com.termux/files/usr/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib_config.sh"

usage() {
    echo "Usage: $0 <workspace_id|all>"
    echo ""
    echo "  workspace_id:  a, b, or all"
    echo ""
    echo "Examples:"
    echo "  $0 a       # Stop workspace A only"
    echo "  $0 b       # Stop workspace B only"
    echo "  $0 all     # Stop all workspaces"
    exit 1
}

stop_single_workspace() {
    local ws_id="$1"
    local config
    config=$(get_ws_config "$ws_id")
    if [ -z "$config" ]; then
        log_err "Unknown workspace: $ws_id"
        return 1
    fi

    local display vnc_port novnc_port geometry depth base_dir bind_host
    read -r display vnc_port novnc_port geometry depth base_dir bind_host <<< "$config"

    local pid_dir="$base_dir/run"
    local vnc_pid_file="$pid_dir/vnc.pid"
    local ws_pid_file="$pid_dir/websockify.pid"

    echo ""
    log_info "Stopping Workspace ${ws_id^^}..."

    kill_by_pid_file "$ws_pid_file" "websockify (port $novnc_port)"

    local orphan_ws
    orphan_ws=$(pgrep -f "websockify.*${novnc_port}" 2>/dev/null | head -1)
    if [ -n "$orphan_ws" ]; then
        kill "$orphan_ws" 2>/dev/null || true
        log_info "Cleaned up orphan websockify process"
    fi

    log_info "Killing Xvnc :$display..."
    proot-distro login "$PROOT_DISTRO" --shared-tmp -- bash -c "
        vncserver -kill :$display 2>/dev/null || true
    " 2>/dev/null || true

    kill_by_pid_file "$vnc_pid_file" "Xvnc :$display"

    local orphan_vnc
    orphan_vnc=$(pgrep -f "Xvnc.*:${display}" 2>/dev/null | head -1)
    if [ -n "$orphan_vnc" ]; then
        kill "$orphan_vnc" 2>/dev/null || true
        log_info "Cleaned up orphan Xvnc process"
    fi

    rm -f "/tmp/.X${display}-lock" 2>/dev/null
    rm -f "/tmp/.X11-unix/X${display}" 2>/dev/null

    log_ok "Workspace ${ws_id^^} stopped"
}

# ─── Main ────────────────────────────────────────────────────────

if [ $# -lt 1 ]; then
    usage
fi

TARGET="$1"

echo -e "${BLUE}=======================================${NC}"
echo -e "${BLUE} SwissWorkspaceGateway — Stop${NC}"
echo -e "${BLUE}=======================================${NC}"

case "$TARGET" in
    all)
        while IFS= read -r ws_id; do
            stop_single_workspace "$ws_id"
        done < <(get_all_ws_ids)
        ;;
    *)
        stop_single_workspace "$TARGET"
        ;;
esac

echo ""
log_ok "Stop complete"
