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
    echo "  $0 a       # Start workspace A only"
    echo "  $0 b       # Start workspace B only"
    echo "  $0 all     # Start all workspaces"
    exit 1
}

start_single_workspace() {
    local ws_id="$1"
    local config
    config=$(get_ws_config "$ws_id")
    if [ -z "$config" ]; then
        log_err "Unknown workspace: $ws_id"
        return 1
    fi

    local display vnc_port novnc_port geometry depth base_dir bind_host
    read -r display vnc_port novnc_port geometry depth base_dir bind_host <<< "$config"

    local log_dir="$base_dir/logs"
    local pid_dir="$base_dir/run"
    local xstartup="$base_dir/xstartup"
    local vnc_pid_file="$pid_dir/vnc.pid"
    local ws_pid_file="$pid_dir/websockify.pid"

    echo ""
    log_info "Starting Workspace ${ws_id^^} (display :$display, VNC $vnc_port, noVNC $novnc_port)"

    mkdir -p "$base_dir/profile" "$log_dir" "$pid_dir"

    if check_pid_alive "$vnc_pid_file"; then
        local existing_pid
        existing_pid=$(cat "$vnc_pid_file")
        log_warn "VNC for workspace $ws_id already running (PID $existing_pid). Skipping VNC start."
        if check_pid_alive "$ws_pid_file"; then
            return 0
        fi
        log_warn "websockify not running, restarting..."
    fi

    # ─── Prepare xstartup inside workspace base_dir ───────────────
    local ws_tigervnc_cfg="$base_dir/.config/tigervnc"
    mkdir -p "$ws_tigervnc_cfg"

    if [ ! -f "$xstartup" ]; then
        log_warn "xstartup not found at $xstartup, creating default..."
        cat > "$xstartup" << 'XEOF'
#!/bin/bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

export XDG_RUNTIME_DIR="${HOME}/.run"
mkdir -p "$XDG_RUNTIME_DIR"

openbox &
xterm &

wait
XEOF
    fi
    chmod +x "$xstartup"

    cp "$xstartup" "$ws_tigervnc_cfg/xstartup"
    chmod +x "$ws_tigervnc_cfg/xstartup"
    log_info "xstartup installed at $ws_tigervnc_cfg/xstartup"

    local vnc_sec_args=""
    if [ "$VNC_SECURITY" = "None" ] || [ "$VNC_SECURITY" = "none" ]; then
        vnc_sec_args="-SecurityTypes None --I-KNOW-THIS-IS-INSECURE"
        log_warn "VNC security disabled (SecurityTypes None). Rely on Tailscale ACLs."
    else
        vnc_sec_args="-SecurityTypes VncAuth"
        log_info "VNC security: VncAuth (password required)"
    fi

    local start_browser="${START_BROWSER:-0}"

    # ─── Start VNC server inside proot Debian ────────────────────
    if ! check_pid_alive "$vnc_pid_file"; then
        log_info "Starting Xvnc :$display on ${bind_host}:$vnc_port (HOME=$base_dir)..."

        proot-distro login "$PROOT_DISTRO" --shared-tmp -- bash -c "
            # Force HOME to workspace base_dir for full isolation
            export HOME='$base_dir'
            export USER=\"\$(whoami)\"
            export XDG_CONFIG_HOME=\"\$HOME/.config\"
            export XDG_DATA_HOME=\"\$HOME/.local/share\"
            export XDG_CACHE_HOME=\"\$HOME/.cache\"
            export XDG_RUNTIME_DIR=\"\$HOME/.run\"
            export START_BROWSER='$start_browser'

            TIGERVNC_CFG=\"\$HOME/.config/tigervnc\"

            # Preflight: clean stale X locks/sockets for this display
            rm -f /tmp/.X${display}-lock
            rm -f /tmp/.X11-unix/X${display}

            # Clean stale TigerVNC pid/log for this display
            rm -f \"\$TIGERVNC_CFG/\"*\":${display}.pid\" 2>/dev/null
            rm -f \"\$TIGERVNC_CFG/\"*\":${display}.log\" 2>/dev/null

            # Ensure dirs exist
            mkdir -p \"\$TIGERVNC_CFG\" \"\$XDG_RUNTIME_DIR\" \"\$XDG_DATA_HOME\" \"\$XDG_CACHE_HOME\"

            # Migrate legacy passwd from /root if needed
            if [ ! -f \"\$TIGERVNC_CFG/passwd\" ]; then
                if [ -f /root/.config/tigervnc/passwd ]; then
                    cp /root/.config/tigervnc/passwd \"\$TIGERVNC_CFG/passwd\"
                    chmod 600 \"\$TIGERVNC_CFG/passwd\"
                elif [ -f /root/.vnc/passwd ]; then
                    cp /root/.vnc/passwd \"\$TIGERVNC_CFG/passwd\"
                    chmod 600 \"\$TIGERVNC_CFG/passwd\"
                fi
            fi

            vncserver -kill :$display 2>/dev/null || true
            sleep 1

            vncserver :$display \
                -localhost yes \
                -geometry $geometry \
                -depth $depth \
                $vnc_sec_args \
                -passwd \"\$TIGERVNC_CFG/passwd\" \
                -xstartup \"\$TIGERVNC_CFG/xstartup\" \
                > '$log_dir/vnc.log' 2>&1
        " &

        local retries=0
        local vnc_up=false
        while [ $retries -lt 20 ]; do
            sleep 1
            retries=$((retries + 1))
            if proot-distro login "$PROOT_DISTRO" --shared-tmp -- nc -z 127.0.0.1 "$vnc_port" 2>/dev/null; then
                vnc_up=true
                break
            fi
        done

        if [ "$vnc_up" = true ]; then
            log_ok "Xvnc :$display listening on port $vnc_port"
        else
            log_err "Failed to start Xvnc :$display (port $vnc_port not responding after 20s)"
            log_err "--- vnc.log (last 50 lines) ---"
            tail -50 "$log_dir/vnc.log" 2>/dev/null | sed 's/^/  /' || true
            log_err "--- Workspace TigerVNC logs ($ws_tigervnc_cfg) ---"
            for f in "$ws_tigervnc_cfg"/*":${display}.log"; do
                [ -f "$f" ] && echo "=== $f ===" && tail -200 "$f" | sed 's/^/  /'
            done 2>/dev/null || true
            log_err "--- /root TigerVNC logs (HOME leak check) ---"
            proot-distro login "$PROOT_DISTRO" --shared-tmp -- bash -c "
                for f in /root/.config/tigervnc/*:${display}.log; do
                    [ -f \"\$f\" ] && echo '=== \$f (HOME leaked to /root!) ===' && tail -200 \"\$f\"
                done
            " 2>/dev/null | sed 's/^/  /' || true
            return 1
        fi

        sleep 2
        if ! proot-distro login "$PROOT_DISTRO" --shared-tmp -- nc -z 127.0.0.1 "$vnc_port" 2>/dev/null; then
            log_err "Xvnc :$display exited shortly after start (port $vnc_port gone)"
            log_err "--- vnc.log (last 50 lines) ---"
            tail -50 "$log_dir/vnc.log" 2>/dev/null | sed 's/^/  /' || true
            log_err "--- Workspace TigerVNC logs ($ws_tigervnc_cfg) ---"
            for f in "$ws_tigervnc_cfg"/*":${display}.log"; do
                [ -f "$f" ] && echo "=== $f ===" && tail -200 "$f" | sed 's/^/  /'
            done 2>/dev/null || true
            log_err "--- /root TigerVNC logs (HOME leak check) ---"
            proot-distro login "$PROOT_DISTRO" --shared-tmp -- bash -c "
                for f in /root/.config/tigervnc/*:${display}.log; do
                    [ -f \"\$f\" ] && echo '=== \$f (HOME leaked to /root!) ===' && tail -200 \"\$f\"
                done
            " 2>/dev/null | sed 's/^/  /' || true
            return 1
        fi
        log_ok "Xvnc :$display stable (HOME=$base_dir, port $vnc_port responding after 2s)"
    fi

    # ─── Start websockify via proot Debian ──────────────────────────
    log_info "Starting websockify ${WEBSOCKIFY_BIND}:$novnc_port -> ${bind_host}:$vnc_port (via Debian)..."
    log_info "noVNC web dir: $NOVNC_DIR"

    if ! run_in_debian test -f "$NOVNC_DIR/vnc.html" 2>/dev/null; then
        log_err "noVNC web dir not accessible inside Debian at $NOVNC_DIR"
        log_err "Resolved NOVNC_DIR=$NOVNC_DIR (from GATEWAY_DIR=$GATEWAY_DIR)"
        log_err "Directory listing:"
        run_in_debian ls -la "$NOVNC_DIR" 2>&1 | sed 's/^/  /' || true
        log_err "Ensure noVNC is cloned and path is under \$HOME. Re-run install_termux.sh."
        return 1
    fi

    local old_ws_pid
    old_ws_pid=$(pgrep -f "websockify.*${novnc_port}" 2>/dev/null | head -1)
    if [ -n "$old_ws_pid" ]; then
        kill "$old_ws_pid" 2>/dev/null || true
        sleep 1
    fi

    nohup proot-distro login "$PROOT_DISTRO" --shared-tmp -- \
        websockify \
        --web="$NOVNC_DIR" \
        ${WEBSOCKIFY_BIND}:${novnc_port} \
        ${bind_host}:${vnc_port} \
        > "$log_dir/websockify.log" 2>&1 &
    local ws_new_pid=$!
    echo "$ws_new_pid" > "$ws_pid_file"

    sleep 3
    if kill -0 "$ws_new_pid" 2>/dev/null; then
        log_ok "websockify started (PID $ws_new_pid, via Debian)"
    else
        log_err "websockify failed to start. Check $log_dir/websockify.log"
        return 1
    fi

    log_ok "Workspace ${ws_id^^} ready: http://<TAILSCALE_IP>:${novnc_port}/vnc.html"
}

# ─── Main ────────────────────────────────────────────────────────

if [ $# -lt 1 ]; then
    usage
fi

TARGET="$1"

echo -e "${BLUE}=======================================${NC}"
echo -e "${BLUE} SwissWorkspaceGateway — Start${NC}"
echo -e "${BLUE}=======================================${NC}"

if [ "$WEBSOCKIFY_BIND" = "__UNSET__" ]; then
    log_err "Cannot determine websockify bind address."
    log_err "Tailscale IP not detected and WEBSOCKIFY_BIND not set in .env."
    log_err "Fix: set WEBSOCKIFY_BIND in gateway/novnc-termux/.env"
    log_err "  e.g. WEBSOCKIFY_BIND=100.100.74.9  (Tailscale IP, recommended)"
    log_err "  or   WEBSOCKIFY_BIND=0.0.0.0       (all interfaces, less secure)"
    exit 1
fi

if command -v termux-wake-lock &>/dev/null; then
    termux-wake-lock 2>/dev/null || true
    log_info "Wake lock acquired"
fi

case "$TARGET" in
    all)
        while IFS= read -r ws_id; do
            start_single_workspace "$ws_id"
        done < <(get_all_ws_ids)
        ;;
    *)
        start_single_workspace "$TARGET"
        ;;
esac

echo ""
echo -e "${GREEN}=======================================${NC}"
echo -e "${GREEN} Startup complete${NC}"
echo -e "${GREEN}=======================================${NC}"
echo ""
echo "Check status: bash $SCRIPT_DIR/healthcheck.sh all"
