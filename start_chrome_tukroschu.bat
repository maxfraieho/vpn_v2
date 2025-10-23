@echo off
set PROXY_IP=100.100.74.9
set SOCKS5_PORT=9891

REM 🇨🇭 Launch Chrome via Swiss Tor Connection (Swiss IP)
REM Account: tukroschu@gmail.com
echo Starting Chrome for tukroschu@gmail.com via Tor (Port %SOCKS5_PORT%)...
echo This will show Swiss IP address
echo.

"C:\Program Files\Google\Chrome\Application\chrome.exe" ^
  --proxy-server="socks5://%PROXY_IP%:%SOCKS5_PORT%" ^
  --user-data-dir="%TEMP%\chrome-tukroschu" ^
  --no-first-run ^
  --profile-directory="Default"
