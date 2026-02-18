# SwissWorkspaceGateway — Test Runbook

Target: Swiss Android tablet (Samsung) running Termux  
Tailscale IP: `100.100.74.9`

---

## Prerequisites

Before testing, ensure:
- Termux is installed and updated on the tablet
- Tailscale is installed and connected on the tablet
- Tailscale is installed and connected on your testing device (laptop/desktop)
- Battery optimization is disabled for Termux
- Phantom Process Killer is disabled (see ARCHITECTURE.md)

---

## Step 1 — Verify Tailscale connectivity

**On the tablet (Termux):**

```bash
tailscale status
```

Expected output:
```
100.100.74.9    swiss-tablet        user@example.com  linux   -
100.x.x.x      your-laptop         user@example.com  windows -
```

```bash
tailscale ip -4
```

Expected output:
```
100.100.74.9
```

**From your laptop:**

```bash
ping 100.100.74.9
```

Expected output:
```
PING 100.100.74.9: 64 bytes from 100.100.74.9: icmp_seq=1 ttl=64 time=X ms
```

---

## Step 2 — Install (first time, or after updates)

**On the tablet (Termux):**

```bash
termux-wake-lock
cd ~/vpn_v2/gateway/novnc-termux
bash scripts/install_termux.sh
```

Expected output (abbreviated):
```
=======================================
 SwissWorkspaceGateway — Installer
=======================================

[INFO] Step 1/5: Installing Termux host packages...
[OK] proot-distro already installed
[OK] python already installed
[OK] git already installed
[INFO] Step 2/5: websockify will be installed inside Debian guest (step 4)...
[INFO] Step 3/5: Setting up PRoot distro (debian)...
[OK] debian already installed
[INFO] Step 4/5: Installing packages inside Debian guest...
[OK] Debian guest packages installed (including websockify)
[INFO] Step 5/5: Setting up noVNC web client...
[OK] noVNC already cloned at /data/.../vendor/noVNC
[INFO] Creating workspace directories...
[OK] Workspace a dirs: .../ws_a/{profile,logs,run}
[OK] Workspace b dirs: .../ws_b/{profile,logs,run}
[INFO] Installing xstartup configs...
[OK] xstartup for workspace a installed
[OK] xstartup for workspace b installed

=======================================
 Installation complete!
=======================================
```

---

## Step 3 — Set VNC password (first time only)

```bash
proot-distro login debian -- vncpasswd
```

Expected output:
```
Password:
Verify:
Would you like to enter a view-only password (y/n)? n
```

---

## Step 4 — Configure environment

```bash
cd ~/vpn_v2/gateway/novnc-termux
cp .env.example .env
```

Edit `.env`:
```bash
# Set your Tailscale IP (find with: tailscale ip -4)
# If Tailscale is running, WEBSOCKIFY_BIND auto-detects. Otherwise set it:
WEBSOCKIFY_BIND=100.100.74.9
VNC_SECURITY=VncAuth
```

Verify `VNC_SECURITY=VncAuth` (default, requires password).

---

## Step 5 — Start workspaces

```bash
bash scripts/start_workspace.sh all
```

Expected output:
```
=======================================
 SwissWorkspaceGateway — Start
=======================================

[INFO] Wake lock acquired

[INFO] Starting Workspace A (display :1, VNC 5901, noVNC 6080)
[INFO] VNC security: VncAuth (password required)
[INFO] Starting Xvnc :1 on 127.0.0.1:5901...
[OK] Xvnc :1 started (PID 12345)
[INFO] Starting websockify 100.100.74.9:6080 -> 127.0.0.1:5901 (via Debian)...
[OK] websockify started (PID 12346, via Debian)
[OK] Workspace A ready: http://100.100.74.9:6080/vnc.html

[INFO] Starting Workspace B (display :2, VNC 5902, noVNC 6081)
[INFO] VNC security: VncAuth (password required)
[INFO] Starting Xvnc :2 on 127.0.0.1:5902...
[OK] Xvnc :2 started (PID 12347)
[INFO] Starting websockify 100.100.74.9:6081 -> 127.0.0.1:5902 (via Debian)...
[OK] websockify started (PID 12348, via Debian)
[OK] Workspace B ready: http://100.100.74.9:6081/vnc.html

=======================================
 Startup complete
=======================================
```

---

## Step 6 — Verify ports and bindings

**On the tablet (Termux):**

```bash
ss -ltnp | grep -E '5901|5902|6080|6081'
```

Expected output:
```
LISTEN  0  5       127.0.0.1:5901   0.0.0.0:*   users:(("Xvnc",pid=12345,...))
LISTEN  0  5       127.0.0.1:5902   0.0.0.0:*   users:(("Xvnc",pid=12347,...))
LISTEN  0  5   100.100.74.9:6080   0.0.0.0:*   users:(("python3",pid=12346,...))
LISTEN  0  5   100.100.74.9:6081   0.0.0.0:*   users:(("python3",pid=12348,...))
```

**Critical checks:**
- VNC ports (5901, 5902) MUST show `127.0.0.1` — never `0.0.0.0` or `*`
- websockify ports (6080, 6081) should show `100.100.74.9` (Tailscale IP) or `0.0.0.0`
- websockify ports must NOT show `127.0.0.1` (otherwise they'd be inaccessible remotely)

---

## Step 7 — Verify noVNC HTTP (on tablet)

```bash
curl -I http://127.0.0.1:6080/vnc.html
```

Expected output:
```
HTTP/1.1 200 OK
Content-Type: text/html
...
```

```bash
curl -I http://127.0.0.1:6081/vnc.html
```

Expected output:
```
HTTP/1.1 200 OK
...
```

Note: If websockify is bound to Tailscale IP, use `curl -I http://100.100.74.9:6080/vnc.html` instead.

---

## Step 8 — Verify noVNC HTTP (from another tailnet device)

**From your laptop (connected to same tailnet):**

```bash
curl -I http://100.100.74.9:6080/vnc.html
```

Expected output:
```
HTTP/1.1 200 OK
Content-Type: text/html
...
```

```bash
curl -I http://100.100.74.9:6081/vnc.html
```

Expected output:
```
HTTP/1.1 200 OK
...
```

---

## Step 9 — Open workspaces in browser

Open these URLs in a browser on any tailnet-connected device:

| Workspace | URL |
|-----------|-----|
| A | http://100.100.74.9:6080/vnc.html |
| B | http://100.100.74.9:6081/vnc.html |

You should see:
1. noVNC connection screen
2. Enter VNC password when prompted
3. XFCE4 desktop with Chromium browser

---

## Step 10 — Verify session isolation

**In Workspace A (via noVNC):**

1. Open Chromium (should already be running)
2. Navigate to `https://httpbin.org/cookies/set/workspace/A`
3. Then navigate to `https://httpbin.org/cookies`
4. Verify output shows: `{"cookies": {"workspace": "A"}}`

**In Workspace B (via noVNC):**

1. Open Chromium (should already be running)
2. Navigate to `https://httpbin.org/cookies/set/workspace/B`
3. Then navigate to `https://httpbin.org/cookies`
4. Verify output shows: `{"cookies": {"workspace": "B"}}`

**Isolation check:**
- Go back to Workspace A Chromium and navigate to `https://httpbin.org/cookies`
- It must still show `{"cookies": {"workspace": "A"}}` — NOT "B"
- This confirms separate `--user-data-dir` isolation is working

---

## Step 11 — Run healthcheck

```bash
bash scripts/healthcheck.sh all
```

Expected output:
```
=======================================
 SwissWorkspaceGateway — Healthcheck
=======================================

--- Infrastructure ---
  [ OK ] Tailscale: connected (100.100.74.9)
  [ OK ] termux-wake-lock: available
  [CFG ] VNC security: VncAuth
  [CFG ] websockify bind: 100.100.74.9
  [CFG ] Config: .../workspaces.json

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

---

## Step 12 — Run smoke test

```bash
bash scripts/smoke_test.sh
```

Expected output:
```
=======================================
 SwissWorkspaceGateway — Smoke Test
=======================================

[INFO] Running healthcheck...
[OK] Healthcheck passed

[INFO] Verifying VNC localhost binding...
[OK] VNC :5901 bound to localhost only
[OK] VNC :5902 bound to localhost only

[INFO] Verifying noVNC HTTP endpoints...
[OK] noVNC port 6080: HTTP 200
[OK] noVNC port 6081: HTTP 200

[INFO] Verifying VNC NOT exposed on 0.0.0.0...
[OK] VNC :5901 not exposed on 0.0.0.0
[OK] VNC :5902 not exposed on 0.0.0.0

=======================================
 All smoke tests passed
=======================================
```

---

## Step 13 — Stop workspaces

```bash
bash scripts/stop_workspace.sh all
```

Expected output:
```
=======================================
 SwissWorkspaceGateway — Stop
=======================================

[INFO] Stopping Workspace A...
[INFO] Stopping websockify (port 6080) (PID 12346)...
[OK] websockify (port 6080) stopped
[INFO] Killing Xvnc :1...
[OK] Xvnc :1 stopped
[OK] Workspace A stopped

[INFO] Stopping Workspace B...
[INFO] Stopping websockify (port 6081) (PID 12348)...
[OK] websockify (port 6081) stopped
[INFO] Killing Xvnc :2...
[OK] Xvnc :2 stopped
[OK] Workspace B stopped

[OK] Stop complete
```

---

## Troubleshooting

### VNC fails to start

```bash
cat ~/ws_a/logs/vnc.log
```

Common issues:
- `Address already in use` → Run `stop_workspace.sh all` first, then clean: `rm -f /tmp/.X1-lock /tmp/.X2-lock`
- `Password file not found` → Run `proot-distro login debian -- vncpasswd`

### websockify fails to start

```bash
cat ~/ws_a/logs/websockify.log
```

Common issues:
- `Address already in use` → Kill orphan: `pkill -f 'websockify.*6080'`
- `websockify: command not found` → Re-run `bash scripts/install_termux.sh` (installs websockify inside Debian)
- `noVNC directory not found` → Re-run `install_termux.sh`

Verify websockify is available inside Debian:
```bash
proot-distro login debian -- websockify --help
# or
proot-distro login debian -- python3 -m websockify --help
```

Note: `websockify --version` may not exist on some Debian builds. Use `--help` instead.

**Important:** websockify is NOT installed on the Termux host (pip install fails due to numpy build issues on Android). It runs inside proot Debian via `proot-distro login debian -- websockify ...`.

### Processes killed by Android

```bash
dmesg | grep -i kill
```

Fix:
```bash
termux-wake-lock
adb shell "settings put global settings_enable_monitor_phantom_procs false"
```

### Cannot access from laptop

1. Verify Tailscale is connected on both devices: `tailscale status`
2. Verify firewall isn't blocking: `tailscale ping 100.100.74.9`
3. Verify websockify is bound correctly: `ss -ltnp | grep 6080`

---

## Done When

All of these are true:
1. `tailscale status` shows the tablet connected as `100.100.74.9`
2. `bash scripts/healthcheck.sh all` exits 0 with all `[ OK ]`
3. `bash scripts/smoke_test.sh` exits 0 with all checks passed
4. `ss -ltnp` shows VNC on `127.0.0.1` only, websockify on Tailscale IP
5. `http://100.100.74.9:6080/vnc.html` opens noVNC in browser from laptop
6. `http://100.100.74.9:6081/vnc.html` opens noVNC in browser from laptop
7. Cookies set in Workspace A do NOT appear in Workspace B (isolation verified)
