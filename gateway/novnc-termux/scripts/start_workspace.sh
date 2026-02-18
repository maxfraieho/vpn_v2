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

_dump_crash_attribution() {
    local tigervnc_cfg="$1"
    local display="$2"
    local log_dir="$3"
    local xstartup_path="$4"

    log_err "=== CRASH ATTRIBUTION ==="
    log_err "START_BROWSER=$START_BROWSER, BROWSER=$BROWSER"

    log_err "--- xstartup content ($xstartup_path) ---"
    if [ -f "$xstartup_path" ]; then
        cat "$xstartup_path" 2>/dev/null | sed 's/^/  /' || true
    else
        echo "  (file not found)" || true
    fi

    log_err "--- vnc.log (last 80 lines) ---"
    tail -80 "$log_dir/vnc.log" 2>/dev/null | sed 's/^/  /' || true

    log_err "--- Workspace TigerVNC session logs ($tigervnc_cfg) ---"
    shopt -s nullglob
    for f in "$tigervnc_cfg"/*":${display}.log"; do
        [ -f "$f" ] && echo "=== $f ===" && tail -80 "$f" | sed 's/^/  /'
    done
    shopt -u nullglob

    log_err "--- /root TigerVNC logs (HOME leak check) ---"
    proot-distro login "$PROOT_DISTRO" --shared-tmp -- bash -c "
        shopt -s nullglob
        for f in /root/.config/tigervnc/*:${display}.log; do
            [ -f \"\$f\" ] && echo \"=== \$f (HOME leaked to /root!) ===\" && tail -80 \"\$f\"
        done
        shopt -u nullglob
    " 2>/dev/null | sed 's/^/  /' || true

    local dbus_lines
    dbus_lines=$(grep -ciE "dbus|udev|netlink|bus_socket" "$log_dir/vnc.log" 2>/dev/null || true)
    dbus_lines="${dbus_lines:-0}"
    if [ "$dbus_lines" -gt 0 ] 2>/dev/null; then
        log_warn "dbus/udev/netlink errors found ($dbus_lines lines) — these are common in proot and may have caused VNC exit"
    fi
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

    # ─── Prepare xstartup: always overwrite from config template ──
    local ws_tigervnc_cfg="$base_dir/.config/tigervnc"
    local xstartup_dest="$ws_tigervnc_cfg/xstartup"
    local xstartup_template="$GATEWAY_DIR/configs/workspace_${ws_id}/xstartup"
    mkdir -p "$ws_tigervnc_cfg"

    if [ -f "$xstartup_template" ]; then
        cp "$xstartup_template" "$xstartup_dest"
        log_info "xstartup installed from template: $xstartup_template -> $xstartup_dest"
    else
        log_warn "xstartup template not found at $xstartup_template, writing default..."
        cat > "$xstartup_dest" << 'XEOF'
#!/bin/bash
exec >>"$HOME/logs/xstartup.log" 2>&1
set -x

unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

export XDG_RUNTIME_DIR="$HOME/.run"
mkdir -p "$XDG_RUNTIME_DIR"

export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"

openbox &
xterm &

wait
XEOF
    fi
    chmod +x "$xstartup_dest"

    rm -f "$base_dir/xstartup" 2>/dev/null

    local vnc_sec_args=""
    if [ "$VNC_SECURITY" = "None" ] || [ "$VNC_SECURITY" = "none" ]; then
        vnc_sec_args="-SecurityTypes None --I-KNOW-THIS-IS-INSECURE"
        log_warn "VNC security disabled (SecurityTypes None). Rely on Tailscale ACLs."
    else
        vnc_sec_args="-SecurityTypes VncAuth"
        log_info "VNC security: VncAuth (password required)"
    fi

    # ─── Start VNC server inside proot Debian ────────────────────
    if ! check_pid_alive "$vnc_pid_file"; then
        log_info "Starting Xvnc :$display on ${bind_host}:$vnc_port (HOME=$base_dir)..."
        log_info "START_BROWSER=$START_BROWSER, BROWSER=$BROWSER"

        proot-distro login "$PROOT_DISTRO" --shared-tmp -- bash -c "
            export HOME='$base_dir'
            export USER=\"\$(whoami)\"
            export XDG_CONFIG_HOME=\"\$HOME/.config\"
            export XDG_DATA_HOME=\"\$HOME/.local/share\"
            export XDG_CACHE_HOME=\"\$HOME/.cache\"
            export XDG_RUNTIME_DIR=\"\$HOME/.run\"

            TIGERVNC_CFG=\"\$HOME/.config/tigervnc\"

            rm -f /tmp/.X${display}-lock
            rm -f /tmp/.X11-unix/X${display}

            rm -f \"\$TIGERVNC_CFG/\"*\":${display}.pid\" 2>/dev/null
            rm -f \"\$TIGERVNC_CFG/\"*\":${display}.log\" 2>/dev/null

            mkdir -p \"\$TIGERVNC_CFG\" \"\$XDG_RUNTIME_DIR\" \"\$XDG_DATA_HOME\" \"\$XDG_CACHE_HOME\"

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

        if [ "$vnc_up" != true ]; then
            log_err "Failed to start Xvnc :$display (port $vnc_port not responding after 20s)"
            _dump_crash_attribution "$ws_tigervnc_cfg" "$display" "$log_dir" "$xstartup_dest"
            return 1
        fi
        log_ok "Xvnc :$display listening on port $vnc_port"

        sleep 3
        if ! proot-distro login "$PROOT_DISTRO" --shared-tmp -- nc -z 127.0.0.1 "$vnc_port" 2>/dev/null; then
            log_err "Xvnc :$display exited shortly after start (port $vnc_port gone after 3s)"
            _dump_crash_attribution "$ws_tigervnc_cfg" "$display" "$log_dir" "$xstartup_dest"
            return 1
        fi

        local dbus_udev_warns
        dbus_udev_warns=$(grep -ciE "dbus|udev|netlink|bus_socket" "$log_dir/vnc.log" 2>/dev/null || true)
        dbus_udev_warns="${dbus_udev_warns:-0}"
        if [ "$dbus_udev_warns" -gt 0 ] 2>/dev/null; then
            log_warn "dbus/udev/netlink warnings in vnc.log ($dbus_udev_warns lines) — non-fatal in proot"
        fi

        log_ok "Xvnc :$display stable (HOME=$base_dir, port $vnc_port responding after 3s)"
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
