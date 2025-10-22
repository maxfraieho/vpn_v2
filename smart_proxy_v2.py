import json
import socks
import socket
import asyncio
import aiohttp
from aiohttp import web, ClientSession
import aiohttp_socks
import logging
import base64
import re
from urllib.parse import urlparse, parse_qs
import os

# Load configuration
CONFIG_FILE = "/data/data/com.termux/files/home/vpn_v2/config.json"

def load_config():
    with open(CONFIG_FILE, "r") as f:
        return json.load(f)

CONFIG = load_config()

class SwissProxy:
    def __init__(self, config):
        self.config = config
        self.account_by_port = {}  # {port: account_config}
        
        # Map ports to accounts
        for email, acc_config in config["accounts"].items():
            port = acc_config["proxy_port"]
            self.account_by_port[port] = {
                "email": email,
                **acc_config
            }

    async def handle_http_with_routing(self, request, account_config):
        """HTTP proxy with routing through upstream"""
        
        # Get upstream configuration
        upstream = account_config["upstream"]
        
        # If Tor - use SOCKS5 proxy
        if upstream["type"] == "tor":
            connector = aiohttp_socks.ProxyConnector.from_url(
                f"socks5://{upstream["socks_host"]}:{upstream["socks_port"]}"
            )
        else:
            # Direct through Tailscale
            connector = None

        # Get the target URL
        if request.method == "CONNECT":  # HTTPS CONNECT tunnel
            # Handle HTTPS CONNECT - this is a simplified implementation
            return web.Response(status=200, text="Tunnel established")
        else:
            # Regular HTTP request
            # Construct the target URL
            if request.path_qs.startswith("http"):
                target_url = request.path_qs
            else:
                # Reconstruct the URL from headers
                target_url = str(request.url)
            
            # Parse the target URL
            url = urlparse(target_url)
            if url.netloc:
                # Full URL with host
                full_url = target_url
            else:
                # Relative path, need to reconstruct
                host = request.headers.get("Host", "")
                if host:
                    full_url = f"http://{host}{target_url}"
                else:
                    return web.Response(status=400, text="Invalid request")

            # Prepare headers (remove proxy-specific headers)
            headers = {}
            for key, value in request.headers.items():
                if key.lower() not in ["proxy-connection", "connection", "upgrade"]:
                    headers[key] = value
            
            headers["Connection"] = "close"  # Avoid keep-alive issues

            try:
                async with ClientSession(connector=connector) as session:
                    if request.method == "GET":
                        async with session.get(full_url, headers=headers) as resp:
                            body = await resp.read()
                    elif request.method == "POST":
                        data = await request.read()
                        async with session.post(full_url, headers=headers, data=data) as resp:
                            body = await resp.read()
                    elif request.method in ["PUT", "DELETE", "PATCH"]:
                        data = await request.read()
                        method = getattr(session, request.method.lower())
                        async with method(full_url, headers=headers, data=data) as resp:
                            body = await resp.read()
                    else:
                        return web.Response(status=501, text=f"Method {request.method} not implemented")

                    # Prepare the response
                    response_headers = {}
                    for key, value in resp.headers.items():
                        if key.lower() not in ["transfer-encoding", "connection", "content-encoding"]:
                            response_headers[key] = value

                    return web.Response(
                        status=resp.status,
                        headers=response_headers,
                        body=body
                    )
            except Exception as e:
                logging.error(f"Request failed: {e}")
                return web.Response(status=502, text=f"Bad Gateway: {str(e)}")

    async def handle_socks5(self, reader, writer):
        """Handle SOCKS5 connection"""
        try:
            # Negotiate SOCKS5 protocol
            version = await reader.read(1)
            if version[0] != 0x05:
                return

            nmethods = await reader.read(1)[0]
            methods = await reader.read(nmethods)

            # Send response: version and method (no auth)
            writer.write(b"\x05\x00")
            await writer.drain()

            # Read connection request
            ver = await reader.read(1)[0]
            cmd = await reader.read(1)[0]
            rsv = await reader.read(1)[0]
            atyp = await reader.read(1)[0]

            if atyp == 1:  # IPv4
                addr = await reader.read(4)
                addr = ".".join(map(str, addr))
            elif atyp == 3:  # Domain name
                length = await reader.read(1)[0]
                addr = (await reader.read(length)).decode()
            else:
                return

            port = int.from_bytes(await reader.read(2), "big")

            # For this implementation, we wont establish connection to destination
            # Just return success (this is a simplified SOCKS server)
            writer.write(b"\x05\x00\x00\x01\x00\x00\x00\x00\x00\x00")
            await writer.drain()

        except Exception as e:
            logging.error(f"SOCKS5 error: {e}")

    async def start_servers(self):
        """Start HTTP proxy on multiple ports"""
        
        tasks = []
        
        # For each account - separate port
        for port, account in self.account_by_port.items():
            app = web.Application()
            
            async def handler(request, acc=account):
                return await self.handle_http_with_routing(request, acc)
            
            app.router.add_route("*", "/{path:.*}", handler)
            
            runner = web.AppRunner(app)
            await runner.setup()
            
            site = web.TCPSite(runner, "0.0.0.0", port)
            await site.start()
            
            print(f"✅ HTTP Proxy for {account["email"]}: {account["upstream"]["name"]}")
            print(f"   Port: http://{CONFIG["tailscale_ip"]}:{port}")
            
            tasks.append(site)
        
        # SOCKS5 on 1080 (keep as is)
        socks_server = await asyncio.start_server(
            self.handle_socks5, "0.0.0.0", 1080
        )
        
        print(f"✅ SOCKS5 Proxy: socks5://{CONFIG["tailscale_ip"]}]:1080")
        
        await socks_server.serve_forever()

def main():
    proxy = SwissProxy(CONFIG)
    asyncio.run(proxy.start_servers())

if __name__ == "__main__":
    main()

