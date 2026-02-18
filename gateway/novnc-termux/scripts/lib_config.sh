#!/data/data/com.termux/files/usr/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATEWAY_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$GATEWAY_DIR/workspaces.json"
ENV_FILE="$GATEWAY_DIR/.env"

if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

PROOT_DISTRO="${PROOT_DISTRO:-debian}"
NOVNC_DIR="${NOVNC_DIR:-$GATEWAY_DIR/vendor/noVNC}"
WEBSOCKIFY_BIND="${WEBSOCKIFY_BIND:-0.0.0.0}"
VNC_SECURITY="${VNC_SECURITY:-VncAuth}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err()  { echo -e "${RED}[ERR]${NC} $1"; }

_read_json_field() {
    local ws_id="$1"
    local field="$2"
    if command -v python3 &>/dev/null; then
        python3 -c "
import json, os, sys
with open('$CONFIG_FILE') as f:
    cfg = json.load(f)
for ws in cfg['workspaces']:
    if ws['id'] == '$ws_id':
        val = str(ws.get('$field', ''))
        print(val.replace('\$HOME', os.environ.get('HOME', '')))
        sys.exit(0)
sys.exit(1)
" 2>/dev/null
    else
        return 1
    fi
}

get_ws_config() {
    local ws_id="$1"

    if [ -f "$CONFIG_FILE" ] && command -v python3 &>/dev/null; then
        local display vnc_port novnc_port geometry depth base_dir bind_host
        display=$(_read_json_field "$ws_id" "display")
        vnc_port=$(_read_json_field "$ws_id" "vnc_port")
        novnc_port=$(_read_json_field "$ws_id" "novnc_port")
        geometry=$(_read_json_field "$ws_id" "geometry")
        depth=$(_read_json_field "$ws_id" "depth")
        base_dir=$(_read_json_field "$ws_id" "base_dir")
        bind_host=$(_read_json_field "$ws_id" "bind_host")

        if [ -n "$display" ] && [ -n "$vnc_port" ]; then
            echo "$display $vnc_port $novnc_port ${geometry:-1280x720} ${depth:-24} ${base_dir:-$HOME/ws_$ws_id} ${bind_host:-127.0.0.1}"
            return 0
        fi
    fi

    case "$ws_id" in
        a) echo "1 5901 6080 1280x720 24 $HOME/ws_a 127.0.0.1" ;;
        b) echo "2 5902 6081 1280x720 24 $HOME/ws_b 127.0.0.1" ;;
        *) echo ""; return 1 ;;
    esac
}

get_all_ws_ids() {
    if [ -f "$CONFIG_FILE" ] && command -v python3 &>/dev/null; then
        python3 -c "
import json
with open('$CONFIG_FILE') as f:
    cfg = json.load(f)
for ws in cfg['workspaces']:
    if ws.get('enabled', True):
        print(ws['id'])
" 2>/dev/null
        return
    fi
    echo "a"
    echo "b"
}

check_pid_alive() {
    local pid_file="$1"
    if [ -f "$pid_file" ]; then
        local pid
        pid=$(cat "$pid_file" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
        rm -f "$pid_file"
    fi
    return 1
}

kill_by_pid_file() {
    local pid_file="$1"
    local name="$2"

    if [ ! -f "$pid_file" ]; then
        return 0
    fi

    local pid
    pid=$(cat "$pid_file" 2>/dev/null)
    if [ -z "$pid" ]; then
        rm -f "$pid_file"
        return 0
    fi

    if kill -0 "$pid" 2>/dev/null; then
        log_info "Stopping $name (PID $pid)..."
        kill -15 "$pid" 2>/dev/null
        sleep 2
        if kill -0 "$pid" 2>/dev/null; then
            log_warn "Force killing $name (PID $pid)..."
            kill -9 "$pid" 2>/dev/null
            sleep 1
        fi
    fi

    rm -f "$pid_file"
    log_ok "$name stopped"
}
