@echo off
REM ========================================================
REM  Swiss Proxy - Comet Browser (ANTI-LEAK)
REM  Account: arsen.k111999@gmail.com
REM  Port: 9888 (SOCKS5)
REM  IP: Swiss via Tailscale Direct (Bluewin)
REM ========================================================

set PROXY_IP=100.100.74.9
set PROXY_PORT=9888

REM Set Swiss timezone to prevent timezone leak
set TZ=Europe/Zurich

echo.
echo ========================================================
echo   Comet Browser via Swiss Proxy [PROTECTED]
echo ========================================================
echo.
echo   Account: arsen.k111999@gmail.com
echo   Type:    Tailscale Direct (Swiss IP)
echo   Proxy:   socks5://%PROXY_IP%:%PROXY_PORT%
echo   IP:      Swiss Bluewin
echo   Lang:    de-CH (Swiss German)
echo   TZ:      Europe/Zurich
echo   WebRTC:  DISABLED (no IP leak)
echo   DNS:     Through proxy (no DNS leak)
echo.
echo ========================================================
echo.

"C:\Users\vokov\AppData\Local\Perplexity\Comet\Application\comet.exe" ^
  --proxy-server="socks5://%PROXY_IP%:%PROXY_PORT%" ^
  --webrtc-ip-handling-policy=disable_non_proxied_udp ^
  --enforce-webrtc-ip-permission-check ^
  --disable-features=WebRtcHideLocalIpsWithMdns ^
  --lang=de-CH ^
  --user-data-dir="%LOCALAPPDATA%\Perplexity\Comet\User Data" ^
  --profile-directory="Profile-Arsen"
