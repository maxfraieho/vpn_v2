@echo off
set PROXY_IP=100.100.74.9
set SOCKS5_PORT=9888

REM 🇨🇭 Launch Comet Browser via Swiss Direct Connection (Ukrainian IP)
REM Account: arsen.k111999@gmail.com
echo Starting Comet via Swiss Direct Proxy (Port %SOCKS5_PORT%)...
echo This will show Ukrainian IP address
echo.

"C:\Users\tukro\AppData\Local\Perplexity\Comet\Application\comet.exe" ^
  --proxy-server="socks5://%PROXY_IP%:%SOCKS5_PORT%" ^
  --user-data-dir="%TEMP%\comet-swiss-direct" ^
  --no-first-run ^
  --profile-directory="Default"
