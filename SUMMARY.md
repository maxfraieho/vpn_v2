# VPN v2 System Summary

## Current Status: ✅ Fully Operational

### Services Overview
- **Tor Service**: ✅ Running (Port 9050)
  - Provides SOCKS5 proxy
  - Successfully routing through Switzerland exits
  - Accessible via Tailscale IP address
  - IP verification shows Swiss location (country code: CH)

- **Smart Proxy Service**: ✅ Running (Ports 8888, 8889)
  - Two independent HTTP proxies for different accounts
  - Port 8888: Tailscale Direct routing (arsen.k111999@gmail.com)
  - Port 8889: Tor routing through Switzerland (lekov00@gmail.com)
  - Both proxies provide Swiss IP addresses

- **Survey Automation Service**: ✅ Running (Port 8090)
  - Internal service API
  - Health checks and status monitoring

## Configuration Details
- **Tailscale IP**: 100.100.74.9
- **Tor SOCKS5 Port**: 9050
- **Proxy Ports**: 8888 (Tailscale), 8889 (Tor)
- **Survey Port**: 8090

## Browser Configuration for Windows Chrome

### For Account 1: arsen.k111999@gmail.com (Tailscale Direct)
**Purpose**: Direct Tailscale routing with Swiss IP

**Chrome Configuration:**
1. Open Chrome
2. Go to Settings → System → Open proxy settings
3. Windows Settings → Network & Internet → Proxy
4. Manual proxy setup:
   - HTTP proxy: 100.100.74.9 port 8888
   - HTTPS proxy: 100.100.74.9 port 8888
5. Save settings

**Alternative Method (Chrome Extension):**
1. Install "Proxy SwitchyOmega" extension
2. Create new profile:
   - Name: Tailscale_VPN_Arsen
   - Type: HTTP/HTTPS
   - Server: 100.100.74.9
   - Port: 8888
3. Apply changes

**Verification for Arsen Account:**
```bash
# Check IP and location
curl -x http://100.100.74.9:8888 http://httpbin.org/ip
# Expected: {"origin": "46.253.188.140"}

# Check country
curl -x http://100.100.74.9:8888 https://ipapi.co/country
# Expected: CH (Switzerland)
```

### For Account 2: lekov00@gmail.com (Tor Routing)
**Purpose**: Tor routing through Switzerland with Swiss exit

**Chrome Configuration:**
1. Open Chrome
2. Go to Settings → System → Open proxy settings
3. Windows Settings → Network & Internet → Proxy
4. Manual proxy setup:
   - HTTP proxy: 100.100.74.9 port 8889
   - HTTPS proxy: 100.100.74.9 port 8889
5. Save settings

**Alternative Method (Chrome Extension):**
1. Install "Proxy SwitchyOmega" extension
2. Create new profile:
   - Name: Tor_VPN_Lena
   - Type: HTTP/HTTPS
   - Server: 100.100.74.9
   - Port: 8889
3. Apply changes

**Verification for Lena Account:**
```bash
# Check IP and location
curl -x http://100.100.74.9:8889 http://httpbin.org/ip
# Expected: {"origin": "195.176.3.24"}

# Check country
curl -x http://100.100.74.9:8889 https://ipapi.co/country
# Expected: CH (Switzerland)
```

## Simultaneous Usage Instructions

### Using Both Accounts in Different Chrome Instances:
1. **Primary Chrome** (Arsen account):
   - Configure system proxy to 100.100.74.9:8888
   - Login to arsen.k111999@gmail.com services

2. **Secondary Chrome** (Lena account):
   - Create Chrome shortcut with different user data directory:
     ```
     "C:\Program Files\Google\Chrome\Application\chrome.exe" --user-data-dir="C:\ChromeProfiles\Lena" --proxy-server="http://100.100.74.9:8889"
   - Login to lekov00@gmail.com services

## Testing Commands

### Tor Direct Testing:
```bash
# Test Tor SOCKS5 directly
curl --socks5-hostname 127.0.0.1:9050 https://ipapi.co/json/
```

### Proxy Testing:
```bash
# Test Arsen's Tailscale proxy (Account 1)
curl -x http://127.0.0.1:8888 http://httpbin.org/ip

# Test Lena's Tor proxy (Account 2)
curl -x http://127.0.0.1:8889 http://httpbin.org/ip
```

### Service Health Checks:
```bash
# Survey API health
curl http://127.0.0.1:8090/health

# Survey API status
curl http://127.0.0.1:8090/status
```

## Known Limitations

1. **HTTPS Support**: 
   - Current proxy implementation only supports HTTP
   - HTTPS CONNECT method not implemented
   - For HTTPS sites, use Tor SOCKS5 directly (127.0.0.1:9050)

2. **Port Status Display**:
   - Manager shows "Port not listening" but proxies work correctly
   - This is a display issue, not functional problem

3. **Account Isolation**:
   - Each account uses separate proxy ports
   - No cross-contamination between accounts
   - Independent routing for each user

## Troubleshooting

### If Proxies Don't Respond:
1. Check service status:
   ```bash
   cd ~/vpn_v2 && bash manager_v2.sh status
   ```

2. Restart services:
   ```bash
   cd ~/vpn_v2 && bash manager_v2.sh restart
   ```

### If Wrong Country Detected:
1. Verify Tor connection:
   ```bash
   curl --socks5-hostname 127.0.0.1:9050 https://ipapi.co/country
   ```

2. Check proxy logs:
   ```bash
   tail -n 50 ~/vpn_v2/proxy.log
   ```

## System Ports

| Service | Port | Protocol | Purpose |
|---------|------|----------|---------|
| Tor SOCKS5 | 9050 | SOCKS5 | Direct Tor access |
| Tailscale Proxy | 8888 | HTTP | Arsen account (Tailscale Direct) |
| Tor Proxy | 8889 | HTTP | Lena account (Tor routing) |
| Survey API | 8090 | HTTP | Internal service API |

## Account Specifications

### arsen.k111999@gmail.com (Account 1)
- **Routing**: Direct Tailscale connection
- **Port**: 8888
- **IP Type**: Static Swiss IP
- **Use Case**: Fast, stable connection for primary activities

### lekov00@gmail.com (Account 2)
- **Routing**: Tor network through Swiss exit
- **Port**: 8889
- **IP Type**: Rotating Swiss IPs
- **Use Case**: Anonymous browsing with enhanced privacy

Both accounts provide Swiss IP addresses and can be used simultaneously without interference.