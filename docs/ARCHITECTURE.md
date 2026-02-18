# SwissWorkspaceGateway — Architecture Decision Record

## ADR-001: MVP Display and Session Strategy

**Status:** Accepted  
**Date:** 2026-02-18  
**Decision:** PRoot-distro Debian (Approach B)

---

## Context

The SwissWorkspaceGateway must provide web-based remote desktop access to isolated
workspaces running on a Samsung Android tablet via Termux. The host has no Docker,
no systemd, and no root access. Three approaches were evaluated:

| Approach | Method | Verdict |
|----------|--------|---------|
| A: Termux:X11 | Native X server on Android | Best local performance, but complex remote chain (x11vnc capture required), non-FHS paths break standard browsers |
| B: PRoot-distro Debian | User-space syscall translation via ptrace | FHS-compliant, stable apt packages (Chromium, Firefox), clean isolation via separate dirs |
| C: Headless browser | CDP/Puppeteer streaming | No desktop feel, still needs Xvfb/Xvnc underneath |

**Chosen: Approach B** because:
1. FHS compatibility allows `apt install chromium` without path hacking
2. TigerVNC (Xvnc) runs reliably inside proot Debian
3. Multi-workspace isolation is straightforward (separate dirs, displays, ports)
4. websockify + noVNC run on Termux host (no proot overhead for networking)

---

## Component Chain

```
Browser (any device on Tailnet)
  |
  | HTTP WebSocket (port 6080 or 6081)
  |
Tailscale tunnel (encrypted, zero-trust)
  |
  v
Termux Host (Android)
  |
  +-- websockify A (6080 -> 127.0.0.1:5901)
  +-- websockify B (6081 -> 127.0.0.1:5902)
  |
  v
PRoot Debian Guest
  |
  +-- Workspace A: Xvnc :1 (port 5901, localhost)
  |     +-- XFCE4 session
  |     +-- Chromium (--user-data-dir=~/ws_a/profile)
  |
  +-- Workspace B: Xvnc :2 (port 5902, localhost)
        +-- XFCE4 session
        +-- Chromium (--user-data-dir=~/ws_b/profile)
```

### Port Mapping

| Workspace | VNC Display | VNC Port (localhost) | noVNC/websockify Port | Access URL |
|-----------|-------------|----------------------|-----------------------|------------|
| A | :1 | 5901 | 6080 | `http://<TAILSCALE_IP>:6080/vnc.html` |
| B | :2 | 5902 | 6081 | `http://<TAILSCALE_IP>:6081/vnc.html` |

### Binding Rules

- **VNC (Xvnc):** Bound to `127.0.0.1` only. Never exposed to any network interface.
- **websockify:** Bound to `0.0.0.0` so Tailscale interface can reach it. Tailscale ACLs restrict access.
- **noVNC static files:** Served by websockify's built-in web server from cloned noVNC repo.

---

## Multi-Workspace Isolation

Each workspace gets fully separate:

| Resource | Workspace A | Workspace B |
|----------|-------------|-------------|
| Base directory | `~/ws_a/` | `~/ws_b/` |
| Browser profile | `~/ws_a/profile/` | `~/ws_b/profile/` |
| Log directory | `~/ws_a/logs/` | `~/ws_b/logs/` |
| PID directory | `~/ws_a/run/` | `~/ws_b/run/` |
| VNC display | `:1` | `:2` |
| VNC port | 5901 | 5902 |
| noVNC port | 6080 | 6081 |

Isolation is for clean session separation and independent operations. Each workspace
has its own cookies, localStorage, browser history, and running processes.

---

## Android Pitfalls

### 1. Phantom Process Killer (Android 12+)

Android 12+ aggressively kills background processes that exceed 32 child processes.
This directly threatens long-running VNC and websockify sessions.

**Workarounds:**
- Use `termux-wake-lock` before starting services
- Disable phantom process killing via ADB:
  ```bash
  adb shell "settings put global settings_enable_monitor_phantom_procs false"
  adb shell "/system/bin/device_config set_sync_disabled_for_tests persistent"
  adb shell "/system/bin/device_config put activity_manager max_phantom_processes 2147483647"
  ```
- Keep Termux in foreground notification (Termux:Boot or persistent notification)

### 2. Battery Optimization

Android may throttle or kill Termux when the tablet is on battery.

**Workarounds:**
- Disable battery optimization for Termux in Android Settings
- Keep the tablet plugged in during workspace sessions
- Use `termux-wake-lock` to prevent CPU sleep

### 3. termux-wake-lock

Always acquire wake lock before starting workspace services:
```bash
termux-wake-lock
```
Release when done:
```bash
termux-wake-unlock
```

### 4. PRoot Performance

PRoot uses ptrace for syscall translation, which adds overhead. For VNC + browser
workloads this is acceptable. Avoid CPU-intensive tasks (video encoding, compilation)
inside proot sessions.

### 5. Storage

Termux storage is under `/data/data/com.termux/files/home/`. Ensure sufficient free
space (minimum 2GB recommended for Debian + XFCE + Chromium per workspace).

---

## Fallback: Termux:X11 (Not Implemented)

If PRoot performance is insufficient, Termux:X11 can provide native X rendering:
1. Install `termux-x11-nightly` package
2. Run X server: `termux-x11 :0 -xstartup "xfce4-session"`
3. Capture with x11vnc for remote access

This approach was deferred because:
- Requires Termux:X11 Android app installed separately
- Non-FHS paths may break Chromium without TUR packages
- More complex remote access chain (X11 -> x11vnc -> websockify -> noVNC)

---

## Technology Stack

| Component | Technology | Runs On |
|-----------|------------|---------|
| Linux environment | PRoot-distro (Debian) | Termux host |
| VNC server | TigerVNC (Xvnc) | PRoot Debian |
| Desktop environment | XFCE4 | PRoot Debian |
| Browser | Chromium | PRoot Debian |
| WebSocket proxy | websockify (Python) | Termux host |
| Web VNC client | noVNC (static HTML/JS) | Served by websockify |
| Network access | Tailscale | Termux host |
| Process management | Bash scripts + PID files | Termux host |
| Automation | Cloudy CLI | Termux host |
