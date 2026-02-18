# SwissWorkspaceGateway — noVNC Remote Desktop (Termux)

Web-based remote desktop access to isolated browser workspaces running on a Swiss Android tablet via Termux. Uses PRoot-distro Debian + TigerVNC + websockify + noVNC, accessed over Tailscale VPN.

**No Docker. No systemd. No root required.**

---

## Quick Start (15 commands)

### 1. Clone and install

```bash
# On the Swiss tablet, in Termux:
cd ~
git clone https://github.com/maxfraieho/vpn_v2.git
cd vpn_v2/gateway/novnc-termux

# Configure environment
cp .env.example .env
# Edit .env: set WEBSOCKIFY_BIND to your Tailscale IP (e.g. 100.100.74.9)

# Run the installer (idempotent — safe to re-run)
bash scripts/install_termux.sh
```

### 2. Set VNC password (required — default is VncAuth)

```bash
proot-distro login debian -- vncpasswd
# Enter and confirm a password
```

> VNC uses password authentication by default (`VNC_SECURITY=VncAuth`).
> To disable password auth (not recommended), set `VNC_SECURITY=None` in `.env`.

### 3. Start workspaces

```bash
# Start both workspaces
bash scripts/start_workspace.sh all

# Or start individually
bash scripts/start_workspace.sh a
bash scripts/start_workspace.sh b
```

### 4. Verify

```bash
bash scripts/healthcheck.sh all
```

Expected output:
```
=======================================
 SwissWorkspaceGateway — Healthcheck
=======================================

--- Infrastructure ---
  [ OK ] Tailscale: connected (100.x.x.x)
  [ OK ] termux-wake-lock: available

--- Workspace A (display :1) ---
  [ OK ] Xvnc :1: running (PID 12345)
  [ OK ] VNC port: port 5901 listening
  [ OK ] websockify: running (PID 12346)
  [ OK ] noVNC port: port 6080 listening
  [ OK ] noVNC HTTP: HTTP 200 on port 6080

--- Workspace B (display :2) ---
  [ OK ] Xvnc :2: running (PID 12347)
  [ OK ] VNC port: port 5902 listening
  [ OK ] websockify: running (PID 12348)
  [ OK ] noVNC port: port 6081 listening
  [ OK ] noVNC HTTP: HTTP 200 on port 6081

=======================================
 All checks passed
=======================================
```

### 5. Access via browser (over Tailscale)

Find your tablet's Tailscale IP:
```bash
tailscale ip -4
# Example: 100.100.74.9
```

Open in any browser on your tailnet:

| Workspace | URL |
|-----------|-----|
| A | `http://100.100.74.9:6080/vnc.html` |
| B | `http://100.100.74.9:6081/vnc.html` |

### 6. Stop workspaces

```bash
bash scripts/stop_workspace.sh all
```

---

## Port Mapping

| Workspace | VNC Display | VNC Port (localhost) | noVNC Port (Tailscale) | Browser Profile |
|-----------|-------------|----------------------|------------------------|-----------------|
| A | :1 | 5901 | 6080 | `~/ws_a/profile/chromium` |
| B | :2 | 5902 | 6081 | `~/ws_b/profile/chromium` |

---

## File Structure

```
gateway/novnc-termux/
├── configs/
│   ├── workspace_a/xstartup    # XFCE4 + Chromium for workspace A
│   └── workspace_b/xstartup    # XFCE4 + Chromium for workspace B
├── scripts/
│   ├── install_termux.sh       # One-time setup (idempotent)
│   ├── start_workspace.sh      # Start VNC + websockify (via Debian)
│   ├── stop_workspace.sh       # Graceful shutdown
│   ├── healthcheck.sh          # Process + port verification
│   └── smoke_test.sh           # Automated smoke test (exit 0 = pass)
├── vendor/
│   └── noVNC/                  # Cloned by installer
├── workspaces.json             # Workspace configuration
├── .env.example                # Environment template
└── README.md                   # This file

gateway/automation/cloudy/
├── deploy_task.yaml            # Install + start + verify
├── restart_task.yaml           # Stop + start + verify
└── health_task.yaml            # Healthcheck with auto-restart
```

---

## Cloudy Automation

```bash
# Full deploy (install + start + verify)
cloudy run gateway/automation/cloudy/deploy_task.yaml

# Restart all workspaces
cloudy run gateway/automation/cloudy/restart_task.yaml

# Health check (auto-restarts on failure)
cloudy run gateway/automation/cloudy/health_task.yaml
```

---

## Troubleshooting

### Phantom Process Killer (Android 12+)

Android aggressively kills background processes. Fix via ADB from a computer:

```bash
adb shell "settings put global settings_enable_monitor_phantom_procs false"
adb shell "/system/bin/device_config set_sync_disabled_for_tests persistent"
adb shell "/system/bin/device_config put activity_manager max_phantom_processes 2147483647"
```

Always run `termux-wake-lock` before starting workspaces.

### Wake Lock

```bash
# Before starting workspaces:
termux-wake-lock

# To release when done:
termux-wake-unlock
```

### Battery Optimization

Disable battery optimization for Termux in Android Settings:
Settings > Apps > Termux > Battery > Unrestricted

### websockify

websockify is installed inside Debian (via `apt install websockify`) and runs via `proot-distro login debian -- websockify ...`. It is **not** installed on the Termux host (pip install fails due to numpy build issues on Android).

To check if websockify is working inside Debian:
```bash
proot-distro login debian -- websockify --help
# or
proot-distro login debian -- python3 -m websockify --help
```

Note: `websockify --version` may not exist on some Debian builds. Use `--help` instead.

### Chromium Sandbox

Chromium inside proot requires `--no-sandbox` (already set in xstartup configs). This is safe because:
- proot is already a sandboxed environment
- Network access is restricted to Tailscale

### D-Bus Errors

If you see D-Bus warnings in VNC logs, they're usually harmless. The xstartup configs use `dbus-launch` to handle this.

### Screen Resolution

Edit `workspaces.json` and change the `geometry` field, then restart:
```bash
bash scripts/stop_workspace.sh all
bash scripts/start_workspace.sh all
```

### websockify not found

If websockify fails to start, verify it's installed inside Debian:
```bash
proot-distro login debian -- which websockify
# Should output: /usr/bin/websockify
```

If missing, re-run the installer:
```bash
bash scripts/install_termux.sh
```

### Logs

```bash
# VNC logs
tail -50 ~/ws_a/logs/vnc.log
tail -50 ~/ws_b/logs/vnc.log

# websockify logs
tail -50 ~/ws_a/logs/websockify.log
tail -50 ~/ws_b/logs/websockify.log
```

### Clean Restart

```bash
bash scripts/stop_workspace.sh all
rm -f ~/ws_a/run/*.pid ~/ws_b/run/*.pid
rm -f /tmp/.X1-lock /tmp/.X2-lock
rm -f /tmp/.X11-unix/X1 /tmp/.X11-unix/X2
bash scripts/start_workspace.sh all
```

---

## Architecture

See [docs/ARCHITECTURE.md](../../docs/ARCHITECTURE.md) for full architecture decision record.

## Security

See [docs/SECURITY.md](../../docs/SECURITY.md) for threat model and hardening recommendations.
