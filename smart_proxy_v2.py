import json
import asyncio
import aiohttp
from aiohttp import web, ClientSession
import aiohttp_socks
import logging
import socket
from contextlib import closing

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[
        logging.FileHandler('/data/data/com.termux/files/home/vpn_v2/proxy.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

CONFIG_FILE = "/data/data/com.termux/files/home/vpn_v2/config.json"

def load_config():
    with open(CONFIG_FILE, "r") as f:
        return json.load(f)

def check_port_available(port):
    """Check if port is available"""
    with closing(socket.socket(socket.AF_INET, socket.SOCK_STREAM)) as sock:
        try:
            sock.bind(('0.0.0.0', port))
            return True
        except OSError:
            return False

def find_available_port(start_port, max_attempts=100):
    """Find next available port starting from start_port"""
    for i in range(max_attempts):
        port = start_port + i
        if check_port_available(port):
            return port
    raise RuntimeError(f"Could not find available port starting from {start_port}")

class SwissProxy:
    def __init__(self, config):
        self.config = config
        self.account_by_port = {}
        self.runners = []
        
        # Map ports to accounts with port availability check
        for email, acc_config in config["accounts"].items():
            requested_port = acc_config["proxy_port"]
            
            if check_port_available(requested_port):
                port = requested_port
                logger.info(f"Port {requested_port} is available for {email}")
            else:
                port = find_available_port(requested_port + 1)
                logger.warning(f"Port {requested_port} busy, using {port} for {email}")
            
            self.account_by_port[port] = {
                "email": email,
                "original_port": requested_port,
                **acc_config
            }

    async def handle_http_with_routing(self, request, account_config):
        """HTTP proxy with routing through upstream"""
        
        upstream = account_config["upstream"]
        
        # Setup connector based on upstream type
        if upstream["type"] == "tor":
            connector = aiohttp_socks.ProxyConnector.from_url(
                f"socks5://{upstream['socks_host']}:{upstream['socks_port']}"
            )
        else:
            connector = None

        # Handle CONNECT method for HTTPS tunneling
        if request.method == "CONNECT":
            return web.Response(status=501, text="CONNECT method not implemented in this version")

        # Get target URL
        if request.path_qs.startswith("http"):
            full_url = request.path_qs
        else:
            host = request.headers.get("Host", "")
            if not host:
                return web.Response(status=400, text="Missing Host header")
            full_url = f"http://{host}{request.path_qs}"

        # Prepare headers
        headers = {k: v for k, v in request.headers.items() 
                  if k.lower() not in ["proxy-connection", "connection", "upgrade", "host"]}
        headers["Connection"] = "close"

        try:
            timeout = aiohttp.ClientTimeout(total=30)
            async with ClientSession(connector=connector, timeout=timeout) as session:
                method = request.method.lower()
                
                if method in ["get", "head", "options"]:
                    async with getattr(session, method)(full_url, headers=headers) as resp:
                        body = await resp.read()
                elif method in ["post", "put", "delete", "patch"]:
                    data = await request.read()
                    async with getattr(session, method)(full_url, headers=headers, data=data) as resp:
                        body = await resp.read()
                else:
                    return web.Response(status=501, text=f"Method {method} not implemented")

                # Prepare response headers
                response_headers = {k: v for k, v in resp.headers.items() 
                                  if k.lower() not in ["transfer-encoding", "connection"]}

                return web.Response(
                    status=resp.status,
                    headers=response_headers,
                    body=body
                )
                
        except asyncio.TimeoutError:
            logger.error(f"Request timeout: {full_url}")
            return web.Response(status=504, text="Gateway Timeout")
        except Exception as e:
            logger.error(f"Request failed: {e}")
            return web.Response(status=502, text=f"Bad Gateway: {str(e)}")

    async def start_servers(self):
        """Start HTTP proxy servers on multiple ports"""
        
        for port, account in self.account_by_port.items():
            app = web.Application()
            
            # Create handler with closure to capture account config
            async def make_handler(acc):
                async def handler(request):
                    return await self.handle_http_with_routing(request, acc)
                return handler
            
            handler_func = await make_handler(account)
            app.router.add_route("*", "/{path:.*}", handler_func)
            
            runner = web.AppRunner(app)
            await runner.setup()
            self.runners.append(runner)
            
            try:
                site = web.TCPSite(runner, "0.0.0.0", port)
                await site.start()
                
                logger.info(f"✅ HTTP Proxy started for {account['email']}")
                logger.info(f"   Route: {account['upstream']['name']}")
                logger.info(f"   Port: {port} (requested: {account['original_port']})")
                logger.info(f"   URL: http://{self.config.get('tailscale_ip', '127.0.0.1')}:{port}")
                
            except Exception as e:
                logger.error(f"Failed to start proxy on port {port}: {e}")

        logger.info("All proxy servers started successfully")
        
        # Keep running
        try:
            while True:
                await asyncio.sleep(3600)
        except KeyboardInterrupt:
            logger.info("Shutting down proxy servers...")
        finally:
            for runner in self.runners:
                await runner.cleanup()

def main():
    try:
        config = load_config()
        logger.info("Configuration loaded successfully")
        
        proxy = SwissProxy(config)
        asyncio.run(proxy.start_servers())
        
    except FileNotFoundError:
        logger.error(f"Configuration file not found: {CONFIG_FILE}")
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON in config file: {e}")
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        raise

if __name__ == "__main__":
    main()