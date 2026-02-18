#!/data/data/com.termux/files/usr/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib_config.sh"

usage() {
    echo "Usage: $0 <workspace_id> [firefox|chromium] [url]"
    echo ""
    echo "  workspace_id:  a or b"
    echo "  browser:       firefox (default) or chromium"
    echo "  url:           starting URL (default: ${START_URL:-about:blank})"
    echo ""
    echo "Examples:"
    echo "  $0 a                          # Firefox in workspace A"
    echo "  $0 b chromium https://example.com"
    echo ""
    echo "This launches a browser inside a running VNC workspace."
    echo "The workspace must already be started via start_workspace.sh."
    exit 1
}

if [ $# -lt 1 ]; then
    usage
fi

WS_ID="$1"
BROWSER_CHOICE="${2:-${BROWSER:-firefox}}"
URL="${3:-${START_URL:-about:blank}}"

config=$(get_ws_config "$WS_ID")
if [ -z "$config" ]; then
    log_err "Unknown workspace: $WS_ID"
    exit 1
fi

read -r display vnc_port novnc_port geometry depth base_dir bind_host <<< "$config"

if ! proot-distro login "$PROOT_DISTRO" --shared-tmp -- bash -c "export HOME='$base_dir'; nc -z 127.0.0.1 $vnc_port" 2>/dev/null; then
    log_err "VNC for workspace $WS_ID is not running (port $vnc_port). Start it first:"
    log_err "  bash $SCRIPT_DIR/start_workspace.sh $WS_ID"
    exit 1
fi

log_info "Launching $BROWSER_CHOICE in Workspace ${WS_ID^^} (display :$display, HOME=$base_dir)"

case "$BROWSER_CHOICE" in
    firefox)
        proot-distro login "$PROOT_DISTRO" --shared-tmp -- bash -c "
            export HOME='$base_dir'
            export DISPLAY=':$display'
            export XDG_CONFIG_HOME=\"\$HOME/.config\"
            export XDG_DATA_HOME=\"\$HOME/.local/share\"
            export XDG_CACHE_HOME=\"\$HOME/.cache\"
            export XDG_RUNTIME_DIR=\"\$HOME/.run\"
            mkdir -p \"\$XDG_RUNTIME_DIR\"

            if ! command -v firefox &>/dev/null && ! command -v firefox-esr &>/dev/null; then
                echo '[ERR] Firefox not installed. Install with: apt install -y firefox-esr'
                exit 1
            fi

            FIREFOX_BIN=\"\$(command -v firefox-esr 2>/dev/null || command -v firefox 2>/dev/null)\"
            mkdir -p \"\$HOME/profile/firefox\"

            nohup \"\$FIREFOX_BIN\" \
                --profile \"\$HOME/profile/firefox\" \
                --no-remote \
                '$URL' \
                > '$base_dir/logs/browser.log' 2>&1 &
            echo \"Firefox launched (PID \$!)\"
        "
        ;;
    chromium)
        log_warn "Chromium in proot may trigger dbus/udev/netlink errors. Firefox is recommended."
        proot-distro login "$PROOT_DISTRO" --shared-tmp -- bash -c "
            export HOME='$base_dir'
            export DISPLAY=':$display'
            export XDG_CONFIG_HOME=\"\$HOME/.config\"
            export XDG_DATA_HOME=\"\$HOME/.local/share\"
            export XDG_CACHE_HOME=\"\$HOME/.cache\"
            export XDG_RUNTIME_DIR=\"\$HOME/.run\"
            mkdir -p \"\$XDG_RUNTIME_DIR\"

            if ! command -v chromium &>/dev/null; then
                echo '[ERR] Chromium not installed. Install with: apt install -y chromium'
                exit 1
            fi

            mkdir -p \"\$HOME/profile/chromium\"

            nohup chromium \
                --no-sandbox \
                --disable-dev-shm-usage \
                --disable-gpu \
                --disable-features=UseOzonePlatform \
                --user-data-dir=\"\$HOME/profile/chromium\" \
                --no-first-run \
                --disable-features=TranslateUI \
                '$URL' \
                > '$base_dir/logs/browser.log' 2>&1 &
            echo \"Chromium launched (PID \$!) — may show dbus/udev warnings (non-fatal)\"
        "
        ;;
    *)
        log_err "Unknown browser: $BROWSER_CHOICE (use 'firefox' or 'chromium')"
        exit 1
        ;;
esac

log_ok "Browser launched in Workspace ${WS_ID^^}. Check $base_dir/logs/browser.log for output."
