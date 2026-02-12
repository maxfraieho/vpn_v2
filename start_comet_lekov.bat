@echo off
REM ========================================================
REM  Swiss Proxy - Comet Browser (ANTI-LEAK)
REM  Account: lekov00@gmail.com
REM  Port: 9889 (SOCKS5)
REM  IP: Swiss via Tor (changes)
REM ========================================================

set PROXY_IP=100.100.74.9
set PROXY_PORT=9889

REM Set Swiss timezone to prevent timezone leak
set TZ=Europe/Zurich

echo.
echo ========================================================
echo   Comet Browser via Swiss Proxy [PROTECTED]
echo ========================================================
echo.
echo   Account: lekov00@gmail.com
echo   Type:    Tor (Swiss IP, Anonymous)
echo   Proxy:   socks5://%PROXY_IP%:%PROXY_PORT%
echo   IP:      Changes via Tor
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
  --profile-directory="Profile-Lekov"
