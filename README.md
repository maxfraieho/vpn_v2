# VPN v2 - Swiss Proxy System

Proxy system that routes traffic through Swiss IP addresses for accessing Swiss survey platforms. Runs on Android (Termux), accessed from Windows via Tailscale VPN.

## Quick Start

### Termux (Android server)

```bash
cd ~/vpn_v2
./manager_v2.sh start    # Start Tor + HTTP proxy + SOCKS5 proxy
./manager_v2.sh status   # Check status
./manager_v2.sh test     # Test IP routing
```

### Windows (client)

Double-click the appropriate .bat file to launch Comet Browser with Swiss proxy:

- `start_comet_arsen.bat` — Swiss IP via Tailscale (port 9888)
- `start_comet_lekov.bat` — Swiss IP via Tor (port 9889)
- `start_comet_tukroschu.bat` — Swiss IP via Tor (port 9890)

## Components

| File | Purpose |
|------|---------|
| `swiss_proxy_stream.py` | HTTP/HTTPS proxy (ports 8888-8890) |
| `swiss_socks5_proxy.py` | SOCKS5 proxy (ports 9888-9890) |
| `manager_v2.sh` | Service manager (start/stop/restart/status/test) |
| `config.json` | Account & routing configuration |
| `torrc` | Tor config (Swiss exit nodes) |
| `start_comet_*.bat` | Windows browser launchers with anti-leak protection |

## Documentation

- **[SWISS_PROXY_README.md](SWISS_PROXY_README.md)** — Full deployment & usage guide
- **[TERMUX_README.md](TERMUX_README.md)** — Termux-specific notes

## Gateway — Remote Desktop Workspaces

Web-based remote desktop access to isolated browser workspaces via noVNC over Tailscale.

| Workspace | noVNC URL |
|-----------|-----------|
| A | `http://<TAILSCALE_IP>:6080/vnc.html` |
| B | `http://<TAILSCALE_IP>:6081/vnc.html` |

- **[Gateway README](gateway/novnc-termux/README.md)** — Quick start & runbook
- **[Architecture](docs/ARCHITECTURE.md)** — ADR, component chain, port mapping
- **[Security](docs/SECURITY.md)** — Threat model, Tailscale-only access

## Anti-leak Protection

Swiss .bat files include flags to prevent geolocation detection:
- DNS resolution through proxy (no DNS leak)
- WebRTC disabled (no IP leak)
- Swiss German language (`de-CH`)
- Swiss timezone (`Europe/Zurich`)
