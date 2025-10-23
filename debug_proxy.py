import json
import asyncio
import aiohttp
from aiohttp import web, ClientSession
import aiohttp_socks
import logging
import socket
from contextlib import closing
import ssl

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

    async def handle_connect(self, request, account_config):
        """Handle HTTPS CONNECT method"""
        try:
            # Debug: log the full request info to understand the issue
            logger.info(f"CONNECT request received: path_qs={request.path_qs}, method={request.method}")
            logger.info(f"Headers: {dict(request.headers)}")
            logger.info(f"Match info: {request.match_info}")
            
            # For CONNECT requests in aiohttp, the target (host:port) should be in the path_qs
            # e.g. "CONNECT httpbin.org:443 HTTP/1.1" -> request.path_qs = "httpbin.org:443"
            target = request.path_qs
            
            # If path_qs doesn't contain the target, try to extract from the Host header
            if not target:
                host_header = request.headers.get('Host', '')
                logger.info(f"No path_qs, trying Host header: {host_header}")
                if host_header:
                    target = host_header
                else:
                    return web.Response(status=400, text="Bad Request: No target specified")
            
            if ':' not in target:
                return web.Response(status=400, text="Bad Request: Port not specified")
            
            # Extract host and port from the CONNECT request target
            host, port = target.split(':', 1)  # Split only on first colon to handle IPv6 if needed
            port = int(port)
            
            logger.info(f"Connecting to {host}:{port} for upstream {account_config['upstream']['type']}")
            
            # Create connector based on account config
            upstream = account_config["upstream"]
            if upstream["type"] == "tor":
                # For Tor, we create a direct connection to the target through Tor SOCKS proxy
                try:
                    reader, writer = await asyncio.open_connection(
                        upstream['socks_host'], 
                        upstream['socks_port']
                    )
                except Exception as e:
                    logger.error(f"Failed to connect to Tor SOCKS proxy: {e}")
                    return web.Response(status=502, text=f"Failed to connect to Tor: {str(e)}")
                
                # Send SOCKS5 protocol request to establish tunnel to target
                # SOCKS5 version identifier
                writer.write(bytearray([0x05, 0x01, 0x00]))  # Version 5, 1 auth method, no auth
                await writer.drain()
                
                # Read authentication response from SOCKS proxy
                auth_response = await reader.read(2)
                if len(auth_response) < 2 or auth_response[0] != 0x05:  # SOCKS5 version
                    logger.error(f"SOCKS authentication failed: {auth_response}")
                    writer.close()
                    await writer.wait_closed()
                    return web.Response(status=502, text="SOCKS authentication failed")
                
                # Send CONNECT request to target host
                addr_type = 0x03  # Domain name
                host_bytes = host.encode('ascii')
                request_data = bytearray([0x05, 0x01, 0x00, addr_type])  # CONNECT request
                request_data.append(len(host_bytes))
                request_data.extend(host_bytes)
                request_data.extend(port.to_bytes(2, 'big'))
                
                writer.write(request_data)
                await writer.drain()
                
                # Read response from SOCKS proxy
                connect_response = await reader.read(10)  # SOCKS5 connection response
                if len(connect_response) < 2 or connect_response[0] != 0x05 or connect_response[1] != 0x00:  # Version, success
                    logger.error(f"SOCKS connection failed: response was {connect_response}")
                    writer.close()
                    await writer.wait_closed()
                    return web.Response(status=502, text=f"SOCKS connection failed: {connect_response[1] if len(connect_response) > 1 else 'unknown'}")
                
                # Send success response to client
                response = (
                    b"HTTP/1.1 200 Connection Established\r\n"
                    b"Proxy-agent: SwissProxy/2.0\r\n"
                    b"\r\n"
                )
                request.transport.write(response)
                
                # Bridge connections with proper error handling
                async def forward_client_to_server(client_reader, server_writer, description="client->server"):
                    try:
                        while True:
                            data = await client_reader.read(4096)
                            if not data:
                                break
                            server_writer.write(data)
                            await server_writer.drain()
                    except Exception as e:
                        logger.debug(f"Forward {description} ended: {e}")
                    finally:
                        try:
                            server_writer.close()
                            await server_writer.wait_closed()
                        except:
                            pass
                
                async def forward_server_to_client(server_reader, client_transport, description="server->client"):
                    try:
                        while True:
                            data = await server_reader.read(4096)
                            if not data:
                                break
                            client_transport.write(data)
                            await client_transport.drain()
                    except Exception as e:
                        logger.debug(f"Forward {description} ended: {e}")
                    finally:
                        try:
                            if not client_transport.is_closing():
                                client_transport.close()
                        except:
                            pass
                
                # Forward data in both directions
                try:
                    await asyncio.gather(
                        forward_client_to_server(request.content, writer, "client->tor"),
                        forward_server_to_client(reader, request.transport, "tor->client")
                    )
                except Exception as e:
                    logger.error(f"Connection forwarding failed: {e}")
                
                return request  # Return the request to indicate we've handled it
            else:
                # For direct connections, create a direct socket connection
                try:
                    reader, writer = await asyncio.open_connection(host, port)
                    logger.info(f"Successfully connected to {host}:{port}")
                except Exception as e:
                    logger.error(f"Failed to connect to target {host}:{port} - {e}")
                    return web.Response(status=502, text=f"Failed to connect to target: {str(e)}")
                
                # Send success response to client
                response = (
                    b"HTTP/1.1 200 Connection Established\r\n"
                    b"Proxy-agent: SwissProxy/2.0\r\n"
                    b"\r\n"
                )
                request.transport.write(response)
                
                # Bridge connections with proper error handling
                async def forward_client_to_server(client_reader, server_writer, description="client->server"):
                    try:
                        while True:
                            data = await client_reader.read(4096)
                            if not data:
                                break
                            server_writer.write(data)
                            await server_writer.drain()
                    except Exception as e:
                        logger.debug(f"Forward {description} ended: {e}")
                    finally:
                        try:
                            server_writer.close()
                            await server_writer.wait_closed()
                        except:
                            pass
                
                async def forward_server_to_client(server_reader, client_transport, description="server->client"):
                    try:
                        while True:
                            data = await server_reader.read(4096)
                            if not data:
                                break
                            client_transport.write(data)
                            await client_transport.drain()
                    except Exception as e:
                        logger.debug(f"Forward {description} ended: {e}")
                    finally:
                        try:
                            if not client_transport.is_closing():
                                client_transport.close()
                        except:
                            pass
                
                # Forward data in both directions
                try:
                    await asyncio.gather(
                        forward_client_to_server(request.content, writer, "client->target"),
                        forward_server_to_client(reader, request.transport, "target->client")
                    )
                except Exception as e:
                    logger.error(f"Connection forwarding failed: {e}")
                
                return request  # Return the request to indicate we've handled it

        except ValueError as e:
            logger.error(f"Value conversion error in CONNECT: {e}")
            return web.Response(status=400, text=f"Bad Request: {str(e)}")
        except Exception as e:
            logger.error(f"CONNECT failed: {e}")
            return web.Response(status=502, text=f"Bad Gateway: {str(e)}")

    async def handle_http_with_routing(self, request, account_config):
        """HTTP proxy with routing through upstream"""
        
        logger.info(f"HTTP request received: {request.method} {request.path_qs}")
        
        # Handle CONNECT method for HTTPS tunneling
        if request.method == "CONNECT":
            return await self.handle_connect(request, account_config)
        
        upstream = account_config["upstream"]
        
        # Setup connector based on upstream type
        if upstream["type"] == "tor":
            connector = aiohttp_socks.ProxyConnector.from_url(
                f"socks5://{upstream['socks_host']}:{upstream['socks_port']}"
            )
        else:
            connector = None

        # Get target URL for regular HTTP requests
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
            
            # Use ssl context for HTTPS requests
            ssl_context = None
            if full_url.startswith('https'):
                ssl_context = ssl.create_default_context()
            
            async with ClientSession(connector=connector, timeout=timeout) as session:
                method = request.method.lower()
                
                if method in ["get", "head", "options"]:
                    if full_url.startswith('https'):
                        async with getattr(session, method)(full_url, headers=headers, ssl=ssl_context) as resp:
                            body = await resp.read()
                    else:
                        async with getattr(session, method)(full_url, headers=headers) as resp:
                            body = await resp.read()
                elif method in ["post", "put", "delete", "patch"]:
                    data = await request.read()
                    if full_url.startswith('https'):
                        async with getattr(session, method)(full_url, headers=headers, data=data, ssl=ssl_context) as resp:
                            body = await resp.read()
                    else:
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
        """Start HTTP/HTTPS proxy servers on multiple ports"""
        
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
                
                logger.info(f"✅ HTTP/HTTPS Proxy started for {account['email']}")
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