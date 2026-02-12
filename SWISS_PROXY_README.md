# Swiss Proxy System - Deployment & Usage Guide

## Overview

The system provides access to the Swiss internet from Ukraine through three accounts with different IP addresses. It runs on Android (Termux) and is accessed from Windows via Tailscale VPN.

### Accounts & Ports

| Account | HTTP Port | SOCKS5 Port | Route | IP |
|---------|-----------|-------------|-------|-----|
| arsen.k111999@gmail.com | 8888 | 9888 | Tailscale Direct | Swiss (Bluewin, Renens) |
| lekov00@gmail.com | 8889 | 9889 | Tor | Swiss (changes, Tor exit) |
| tukroschu@gmail.com | 8890 | 9890 | Tor | Swiss (changes, Tor exit) |

Tailscale IP of the server: `100.100.74.9`

---

## Architecture

```
Windows (Comet Browser)
  |
  | SOCKS5 via Tailscale VPN (100.100.74.9)
  |
Android Termux Server
  |
  +-- swiss_proxy_stream.py  (HTTP/HTTPS proxy: 8888, 8889, 8890)
  +-- swiss_socks5_proxy.py  (SOCKS5 proxy: 9888, 9889, 9890)
  |
  +-- Port 8888/9888 (arsen)  --> Direct (Tailscale exit = Swiss Bluewin)
  +-- Port 8889/9889 (lekov)  --> Tor SOCKS5 (127.0.0.1:9050) --> Swiss exit node
  +-- Port 8890/9890 (tukro)  --> Tor SOCKS5 (127.0.0.1:9050) --> Swiss exit node
```

Tor is configured with `ExitNodes {ch}` and `StrictNodes 1` to guarantee Swiss exit nodes.

---

## Deployment on Termux (Android)

### Prerequisites

```bash
pkg install tor python
pip install aiohttp aiohttp-socks requests beautifulsoup4
```

### Files required

| File | Purpose |
|------|---------|
| `config.json` | Account & upstream configuration |
| `torrc` | Tor config (Swiss exit nodes) |
| `swiss_proxy_stream.py` | HTTP/HTTPS proxy server |
| `swiss_socks5_proxy.py` | SOCKS5 proxy server |
| `manager_v2.sh` | Service manager (start/stop/status/test) |

### Start all services

```bash
cd ~/vpn_v2
./manager_v2.sh start
```

This starts:
1. Tor (with Swiss exit nodes)
2. HTTP/HTTPS proxy (ports 8888, 8889, 8890)
3. SOCKS5 proxy (ports 9888, 9889, 9890)

### Check status

```bash
./manager_v2.sh status
```

### Stop all services

```bash
./manager_v2.sh stop
```

### Restart

```bash
./manager_v2.sh restart
```

### Test IP routing

```bash
./manager_v2.sh test
```

---

## Windows Setup (Comet Browser)

### Available .bat launchers

| File | Account | Type |
|------|---------|------|
| `start_comet_arsen.bat` | arsen.k111999@gmail.com | Swiss (Tailscale Direct) |
| `start_comet_lekov.bat` | lekov00@gmail.com | Swiss (Tor, anonymous) |
| `start_comet_tukroschu.bat` | tukroschu@gmail.com | Swiss (Tor, anonymous) |
| `start_comet_arsen_UA.bat` | arsen.k111999@gmail.com | Ukrainian IP variant |
| `start_comet_lekov_UA.bat` | lekov00@gmail.com | Tor variant (no anti-leak) |
| `start_comet_tukroschu_UA.bat` | tukroschu@gmail.com | Tor variant (no anti-leak) |

### Anti-leak protection (Swiss .bat files)

The Swiss .bat files include protection against geolocation detection:

```batch
--host-resolver-rules="MAP * ~NOTFOUND , EXCLUDE 127.0.0.1"
--force-webrtc-ip-handling-policy=disable_non_proxied_udp
--lang=de-CH
set TZ=Europe/Zurich
```

| Protection | Flag | What it prevents |
|------------|------|-----------------|
| DNS leak | `--host-resolver-rules` | DNS queries going to real ISP |
| WebRTC leak | `--force-webrtc-ip-handling-policy` | Real IP exposed via WebRTC |
| Language leak | `--lang=de-CH` | Non-Swiss browser language |
| Timezone leak | `set TZ=Europe/Zurich` | Non-Swiss timezone in JS |

### Usage

1. Ensure services are running on Android: `./manager_v2.sh status`
2. Ensure Tailscale is connected on both devices
3. Double-click the desired .bat file on Windows

---

## Testing

### From Termux (use `--socks5-hostname` to avoid DNS leak)

```bash
# Test SOCKS5 ports (DNS resolved through proxy)
curl -s --socks5-hostname 127.0.0.1:9888 https://ipapi.co/json/  # arsen
curl -s --socks5-hostname 127.0.0.1:9889 https://ipapi.co/json/  # lekov
curl -s --socks5-hostname 127.0.0.1:9890 https://ipapi.co/json/  # tukroschu

# Test HTTP proxy ports
curl -s -x http://127.0.0.1:8888 https://ipapi.co/json/  # arsen
curl -s -x http://127.0.0.1:8889 https://ipapi.co/json/  # lekov
curl -s -x http://127.0.0.1:8890 https://ipapi.co/json/  # tukroschu

# Test Tor directly
curl -s --socks5-hostname 127.0.0.1:9050 https://ipapi.co/json/
```

### From Windows PowerShell

```powershell
curl.exe --socks5-hostname 100.100.74.9:9888 https://ipapi.co/json/
curl.exe --socks5-hostname 100.100.74.9:9889 https://ipapi.co/json/
curl.exe --socks5-hostname 100.100.74.9:9890 https://ipapi.co/json/
```

**Important:** Always use `--socks5-hostname` (not `--socks5`) to prevent DNS leaks. The `-hostname` variant sends the domain name to the proxy for resolution instead of resolving it locally.

---

## Configuration

### config.json

```json
{
  "accounts": {
    "arsen.k111999@gmail.com": {
      "email": "arsen.k111999@gmail.com",
      "proxy_port": 8888,
      "upstream": {
        "type": "direct",
        "name": "Tailscale Direct"
      }
    },
    "lekov00@gmail.com": {
      "email": "lekov00@gmail.com",
      "proxy_port": 8889,
      "upstream": {
        "type": "tor",
        "socks_host": "127.0.0.1",
        "socks_port": 9050,
        "name": "Direct Tor Connection"
      }
    },
    "tukroschu@gmail.com": {
      "email": "tukroschu@gmail.com",
      "proxy_port": 8890,
      "upstream": {
        "type": "tor",
        "socks_host": "127.0.0.1",
        "socks_port": 9050,
        "name": "Direct Tor Connection"
      }
    }
  },
  "tailscale_ip": "100.100.74.9"
}
```

SOCKS5 ports are computed automatically: HTTP port + 1000 (8888 -> 9888, 8889 -> 9889, 8890 -> 9890).

### torrc

```
SOCKSPort 127.0.0.1:9050
ExitNodes {ch}
StrictNodes 1
Log notice file /data/data/com.termux/files/home/vpn_v2/tor.log
DataDirectory /data/data/com.termux/files/home/vpn_v2/tor_data
```

---

## Autostart on Android Boot

### Option 1: Termux:Boot

1. Install Termux:Boot from [F-Droid](https://f-droid.org/packages/com.termux.boot/)
2. Create boot script:

```bash
mkdir -p ~/.termux/boot
cat > ~/.termux/boot/start-proxy.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
sleep 10
cd ~/vpn_v2
./manager_v2.sh start > ~/vpn_v2/autostart.log 2>&1
EOF
chmod +x ~/.termux/boot/start-proxy.sh
```

3. Launch Termux:Boot once to register

### Option 2: Manual start

```bash
cd ~/vpn_v2
./manager_v2.sh start
```

---

## Logs & Diagnostics

| Log file | Content |
|----------|---------|
| `proxy.log` | HTTP/HTTPS proxy (swiss_proxy_stream.py) |
| `socks5_proxy.log` | SOCKS5 proxy (swiss_socks5_proxy.py) |
| `socks5_proxy.log.startup` | SOCKS5 latest startup log |
| `tor.log` | Tor daemon |
| `autostart.log` | Boot autostart log |

```bash
# View logs
./manager_v2.sh logs proxy
./manager_v2.sh logs tor
```

---

## Troubleshooting

### SOCKS5 Tor ports not working (9889/9890)

**Symptom:** `curl --socks5-hostname 127.0.0.1:9889` fails or times out.

**Check:**
1. Is Tor running? `pgrep -f "tor -f"`
2. Is Tor working? `curl -s --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip`
3. Check SOCKS5 log: `tail -20 socks5_proxy.log.startup`
4. Restart: `./manager_v2.sh restart`

### Swiss sites detect non-Swiss location

**Possible causes:**
1. **DNS leak** — browser resolves DNS locally. Fix: use `--host-resolver-rules` flag (already in Swiss .bat files)
2. **WebRTC leak** — browser exposes real IP. Fix: use `--force-webrtc-ip-handling-policy` flag (already in Swiss .bat files)
3. **Timezone mismatch** — JS `Intl.DateTimeFormat().resolvedOptions().timeZone` returns non-Swiss. Fix: `set TZ=Europe/Zurich` (already in Swiss .bat files)
4. **Language mismatch** — `navigator.language` returns non-Swiss. Fix: `--lang=de-CH` (already in Swiss .bat files)
5. **Browser not launched via .bat** — manual browser launch won't have protection flags

**Verify:** Open `https://browserleaks.com/ip` and `https://browserleaks.com/webrtc` in the proxied browser.

### "No connection" from Windows

1. Check proxy status: `./manager_v2.sh status`
2. Check Tailscale: `tailscale status` on both devices
3. Ping Android from Windows: `ping 100.100.74.9`
4. Restart: `./manager_v2.sh restart`

### Ports changed after restart

Run `./manager_v2.sh status` to see current ports and update .bat files if needed.

---

## Known Fixed Issues

### IPv6 forwarding to Tor (Feb 2025)
SOCKS5 proxy was sending IPv6 addresses to Tor as domain name type (0x03), causing Tor to reject the connection. Fixed to properly forward IPv4/IPv6/domain types.

### SSL wrong version number (Oct 2025)
HTTP headers from CONNECT request were not fully consumed, leaking into the TLS handshake. Fixed by reading all headers before establishing the tunnel.

### Port duplication (Oct 2025)
Multiple accounts could receive the same port. Fixed with `used_ports` tracking.
