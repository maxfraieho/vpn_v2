@echo off
set PROXY_IP=100.100.74.9
set SOCKS5_PORT=9888

REM 🇨🇭 Launch Chrome via Swiss Direct Connection (Ukrainian IP)
REM Account: arsen.k111999@gmail.com
echo Starting Chrome via Swiss Direct Proxy (Port %SOCKS5_PORT%)...
echo This will show Ukrainian IP address
echo.

"C:\Program Files\Google\Chrome\Application\chrome.exe" ^
  --proxy-server="socks5://%PROXY_IP%:%SOCKS5_PORT%" ^
  --user-data-dir="%TEMP%\chrome-swiss-direct" ^
  --no-first-run ^
  --profile-directory="Default"
