# Termux/Android Specific Instructions

## Diagnostics

Due to limitations in Termux environment, some diagnostic tools may not work properly:

1. `netstat` may not support all protocols
2. Port checking may show false negatives
3. Process detection works but may not show all details

### Recommended way to check if services are working

Instead of relying on the diagnostic script's port checking, test connectivity externally:

```bash
# Test port 8888 (Direct connection)
curl -x http://localhost:8888 http://httpbin.org/ip

# Test port 8889 (Tor connection)
curl -x http://localhost:8889 http://httpbin.org/ip
```

If these commands return IP addresses, the services are working correctly.

## Common Issues

### 1. "Port not listening" in diagnostics
This is often a false negative on Termux. As long as external tests work, the service is running.

### 2. Missing dependencies
Install required Python packages:
```bash
pip install aiohttp aiohttp-socks requests beautifulsoup4
```

### 3. Tor connection issues
If Tor isn't working:
1. Check that Tor is running: `pgrep -f "tor -f"`
2. Verify torrc configuration: `cat ~/vpn_v2/torrc`
3. Check Tor logs: `tail -n 20 ~/vpn_v2/tor.log`

## Service Management

Start services:
```bash
cd ~/vpn_v2
./manager_v2.sh start
```

Stop services:
```bash
cd ~/vpn_v2
./manager_v2.sh stop
```

Check status:
```bash
cd ~/vpn_v2
./manager_v2.sh status
```

Note: The status command may show false negatives for port listening status on Termux.