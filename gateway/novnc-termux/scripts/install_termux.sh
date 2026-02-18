#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GATEWAY_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VENDOR_DIR="$GATEWAY_DIR/vendor"
NOVNC_DIR="$VENDOR_DIR/noVNC"
PROOT_DISTRO="${PROOT_DISTRO:-debian}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err()  { echo -e "${RED}[ERR]${NC} $1"; }

echo -e "${BLUE}=======================================${NC}"
echo -e "${BLUE} SwissWorkspaceGateway — Installer${NC}"
echo -e "${BLUE}=======================================${NC}"
echo ""

# ─── Step 1: Termux host packages ───────────────────────────────
log_info "Step 1/5: Installing Termux host packages..."

pkg update -y 2>/dev/null || true
pkg upgrade -y 2>/dev/null || true

TERMUX_PKGS=(proot-distro python git)

for p in "${TERMUX_PKGS[@]}"; do
    if dpkg -s "$p" &>/dev/null; then
        log_ok "$p already installed"
    else
        log_info "Installing $p..."
        pkg install -y "$p"
        log_ok "$p installed"
    fi
done

# ─── Step 2: (reserved — websockify installed in Debian guest below) ─
log_info "Step 2/5: websockify will be installed inside Debian guest (step 4)..."

# ─── Step 3: PRoot Debian distro ────────────────────────────────
log_info "Step 3/5: Setting up PRoot distro ($PROOT_DISTRO)..."

if proot-distro login "$PROOT_DISTRO" -- true >/dev/null 2>&1; then
    log_ok "$PROOT_DISTRO already installed — skipping install"
else
    log_info "Installing $PROOT_DISTRO via proot-distro..."
    if proot-distro install "$PROOT_DISTRO"; then
        log_ok "$PROOT_DISTRO installed"
    else
        log_err "Failed to install $PROOT_DISTRO"
        exit 1
    fi
fi

# ─── Step 4: Debian guest packages ──────────────────────────────
log_info "Step 4/5: Installing packages inside Debian guest..."

DEBIAN_PKGS="xfce4 xfce4-terminal chromium tigervnc-standalone-server dbus-x11 procps websockify python3-websockify netcat-openbsd"

proot-distro login "$PROOT_DISTRO" -- bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y --no-install-recommends $DEBIAN_PKGS
    echo 'Guest packages installed.'
"
log_ok "Debian guest packages installed (including websockify)"

# ─── Step 5: Clone noVNC ────────────────────────────────────────
log_info "Step 5/5: Setting up noVNC web client..."

mkdir -p "$VENDOR_DIR"

if [ -d "$NOVNC_DIR" ] && [ -f "$NOVNC_DIR/vnc.html" ]; then
    log_ok "noVNC already cloned at $NOVNC_DIR"
else
    if [ -d "$NOVNC_DIR" ]; then
        rm -rf "$NOVNC_DIR"
    fi
    log_info "Cloning noVNC..."
    git clone --depth 1 https://github.com/novnc/noVNC.git "$NOVNC_DIR"
    log_ok "noVNC cloned to $NOVNC_DIR"
fi

# ─── Step 6: Create workspace directories ───────────────────────
log_info "Creating workspace directories..."

for ws in a b; do
    WS_DIR="$HOME/ws_${ws}"
    mkdir -p "$WS_DIR/profile" "$WS_DIR/logs" "$WS_DIR/run"
    log_ok "Workspace $ws dirs: $WS_DIR/{profile,logs,run}"
done

# ─── Step 7: Copy xstartup configs ──────────────────────────────
log_info "Installing xstartup configs..."

CONFIGS_DIR="$GATEWAY_DIR/configs"
for ws in a b; do
    SRC="$CONFIGS_DIR/workspace_${ws}/xstartup"
    if [ -f "$SRC" ]; then
        cp "$SRC" "$HOME/ws_${ws}/xstartup"
        chmod +x "$HOME/ws_${ws}/xstartup"
        log_ok "xstartup for workspace $ws installed"
    else
        log_warn "xstartup for workspace $ws not found at $SRC"
    fi
done

# ─── Done ────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}=======================================${NC}"
echo -e "${GREEN} Installation complete!${NC}"
echo -e "${GREEN}=======================================${NC}"
echo ""
echo "Next steps:"
echo "  1. Set VNC password:  mkdir -p ~/.config/tigervnc && proot-distro login debian -- vncpasswd ~/.config/tigervnc/passwd"
echo "  2. Start workspaces:  bash $SCRIPT_DIR/start_workspace.sh all"
echo "  3. Run healthcheck:   bash $SCRIPT_DIR/healthcheck.sh all"
echo ""
echo "Access via Tailscale:"
echo "  Workspace A: http://<TAILSCALE_IP>:6080/vnc.html"
echo "  Workspace B: http://<TAILSCALE_IP>:6081/vnc.html"
