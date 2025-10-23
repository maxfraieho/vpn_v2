@echo off
set PROXY_IP=100.100.74.9
set SOCKS5_PORT=9891

REM 🇨🇭 Launch Comet Browser via Swiss Tor Connection (Swiss IP)
REM Account: tukroschu@gmail.com
echo Starting Comet for tukroschu@gmail.com via Tor (Port %SOCKS5_PORT%)...
echo This will show Swiss IP address
echo.

"C:\Users\tukro\AppData\Local\Perplexity\Comet\Application\comet.exe" ^
  --proxy-server="socks5://%PROXY_IP%:%SOCKS5_PORT%" ^
  --user-data-dir="%TEMP%\comet-tukroschu" ^
  --no-first-run ^
  --profile-directory="Default"
