# Security Notes (SwissWorkspaceGateway)

- Prefer Tailscale-only access (no public exposure).
- Use strong auth (at minimum Basic Auth behind Tailscale; ideally 2FA at the network level).
- Keep logs of access and service health.
- Avoid storing secrets in git. Use environment variables / Replit Secrets.
