# VPN v2 + SwissWorkspaceGateway

## Overview
Swiss proxy system with HTTP/HTTPS proxy, SOCKS5 proxy, Tor routing, and remote desktop gateway (noVNC). Runs on Android (Termux), accessed from Windows via Tailscale VPN.

## Project Architecture

### Proxy Stack (existing)
- `manager_v2.sh` — Service manager (start/stop/restart/status/test)
- `swiss_proxy_stream.py` — HTTP/HTTPS proxy (ports 8888-8890)
- `swiss_socks5_proxy.py` — SOCKS5 proxy (ports 9888-9890)
- `config.json` — Account & routing configuration
- `torrc` — Tor config (Swiss exit nodes)

### Gateway Module (new — SwissWorkspaceGateway)
Remote desktop access via noVNC over Tailscale:
- `gateway/novnc-termux/` — Main gateway module
  - `scripts/` — install, start, stop, healthcheck bash scripts
  - `configs/` — per-workspace xstartup files
  - `workspaces.json` — workspace port/path config
  - `vendor/noVNC/` — cloned noVNC web client (not in git)
- `gateway/automation/cloudy/` — Cloudy task definitions
- `docs/ARCHITECTURE.md` — ADR and component chain
- `docs/SECURITY.md` — Threat model and hardening

### Port Map
| Service | Port | Binding |
|---------|------|---------|
| VNC Workspace A | 5901 | 127.0.0.1 |
| VNC Workspace B | 5902 | 127.0.0.1 |
| noVNC Workspace A | 6080 | 0.0.0.0 (Tailscale) |
| noVNC Workspace B | 6081 | 0.0.0.0 (Tailscale) |

## Recent Changes
- 2026-02-18: Implemented full SwissWorkspaceGateway module (Tasks 1-6)
  - Architecture docs, config, Termux scripts, xstartup, Cloudy automation, README runbook

## User Preferences
- Follows manager_v2.sh patterns for PID/log management
- No Docker/systemd (Termux on Android)
- Multi-workspace is session isolation only
- Tailscale-only access model
