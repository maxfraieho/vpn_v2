# SwissWorkspaceGateway — Security Guidelines

## Access Model

### Recommended: Tailscale-Only Access

All workspace access should go through Tailscale (zero-trust mesh VPN):

- VNC ports (5901, 5902) are bound to `127.0.0.1` and never exposed externally
- websockify/noVNC ports (6080, 6081) are bound to `0.0.0.0` but only reachable via Tailscale network interface
- No ports are forwarded to the public internet
- Tailscale ACLs should restrict which devices can reach the tablet

### Network Architecture

```
Internet (blocked)
  X
  |  (no port forwarding)
  |
Android Tablet
  |
  +-- VNC :1 on 127.0.0.1:5901 (localhost only)
  +-- VNC :2 on 127.0.0.1:5902 (localhost only)
  +-- websockify on 0.0.0.0:6080 (reachable via Tailscale)
  +-- websockify on 0.0.0.0:6081 (reachable via Tailscale)
  |
  +-- Tailscale interface (100.x.x.x)
        |
        v
      Tailnet (encrypted, authenticated)
        |
        v
      Your devices (laptop, phone, etc.)
```

---

## Threat Model

| Threat | Mitigation |
|--------|------------|
| Unauthorized VNC access | VNC bound to localhost; websockify only reachable via Tailscale |
| VNC password brute force | VNC password set per workspace; Tailscale limits who can connect |
| Session hijacking | Each workspace has separate session, profile, cookies |
| Credential leakage in git | `.env` files in `.gitignore`; only `.env.example` committed |
| Phantom process kill | `termux-wake-lock` + ADB settings to disable process killer |
| Man-in-the-middle | Tailscale provides end-to-end WireGuard encryption |
| Stale sessions | `stop_workspace.sh` cleans PID files; healthcheck detects dead processes |

---

## Rules

1. **No secrets in git.** Never commit passwords, VNC passwords, or API keys. Use `.env` files (gitignored) or environment variables.

2. **VNC passwords.** VNC uses password authentication by default (`VNC_SECURITY=VncAuth`). Set a password before first start with `proot-distro login debian -- vncpasswd`. The password is stored in `~/.vnc/passwd` (encrypted by vncpasswd). Disabling VNC auth (`VNC_SECURITY=None`) is strongly discouraged and should only be done if Tailscale ACLs are fully locked down.

3. **Tailscale ACLs.** Configure your tailnet to restrict access:
   - Only allow specific devices/users to reach the tablet's IP
   - Block all incoming connections from outside the tailnet

4. **Log monitoring.** Regularly check workspace logs for unusual activity:
   ```bash
   tail -50 ~/ws_a/logs/vnc.log
   tail -50 ~/ws_b/logs/vnc.log
   ```

5. **Updates.** Keep Termux packages and Debian guest packages updated:
   ```bash
   pkg update && pkg upgrade
   proot-distro login debian -- apt update && apt upgrade -y
   ```

---

## Optional Hardening (Phase 2)

- **HTTPS wrapper:** Node.js reverse proxy with TLS + HTTP basic auth in front of websockify
- **IP allowlist:** iptables rules or websockify `--auth-plugin` to restrict source IPs
- **2FA:** Tailscale SSO with MFA enabled on the identity provider
- **Session timeout:** Auto-kill idle VNC sessions after configurable period
- **Rate limiting:** Limit connection attempts to websockify ports
- **Audit logging:** Log all connection events with timestamps and source IPs

---

## File Permissions

Ensure scripts are not world-readable if they contain sensitive paths:
```bash
chmod 700 gateway/novnc-termux/scripts/*.sh
chmod 600 gateway/novnc-termux/.env
```

VNC password files are already restricted by TigerVNC:
```bash
ls -la ~/.vnc/passwd
# -rw------- 1 user user 8 ... passwd
```
