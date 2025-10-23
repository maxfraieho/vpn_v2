import json
import asyncio
import logging
import socket
from contextlib import closing
import re

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
        self.used_ports = set()

        # Map ports to accounts with port availability check
        for email, acc_config in config["accounts"].items():
            requested_port = acc_config["proxy_port"]

            if check_port_available(requested_port) and requested_port not in self.used_ports:
                port = requested_port
                logger.info(f"Port {requested_port} is available for {email}")
            else:
                # Find available port that's not already used
                port = requested_port + 1
                while port in self.used_ports or not check_port_available(port):
                    port += 1
                    if port > requested_port + 100:
                        raise RuntimeError(f"Could not find available port for {email}")
                logger.warning(f"Port {requested_port} busy, using {port} for {email}")

            self.used_ports.add(port)
            self.account_by_port[port] = {
                "email": email,
                "original_port": requested_port,
                **acc_config
            }

    def create_client_handler(self, port, account_config):
        """Create a client handler with account config bound to it"""
        async def handle_client(reader, writer):
            """Handle a client connection"""
            try:
                # Read the first line to determine if it's a CONNECT request
                request_line = await reader.readline()
                request_line = request_line.decode('utf-8').strip()

                if not request_line:
                    return

                logger.info(f"[Port {port}] Received request: {request_line}")

                # Parse the request line to determine method and target
                parts = request_line.split()
                if len(parts) < 3:
                    writer.write(b"HTTP/1.1 400 Bad Request\r\n\r\n")
                    await writer.drain()
                    return

                method = parts[0]
                target = parts[1]

                # Read all HTTP headers until empty line
                # This is CRITICAL for CONNECT requests - we must consume all headers
                # before establishing the tunnel, otherwise they'll be sent to target
                # as part of SSL/TLS handshake and break the connection
                while True:
                    header_line = await reader.readline()
                    if not header_line or header_line == b'\r\n' or header_line == b'\n':
                        break

                if method == "CONNECT":
                    await self.handle_connect(reader, writer, target, account_config)
                else:
                    # Handle regular HTTP requests - for now just send 501
                    writer.write(b"HTTP/1.1 501 Not Implemented\r\n\r\n")
                    await writer.drain()

            except Exception as e:
                logger.error(f"[Port {port}] Error handling client: {e}")
            finally:
                try:
                    writer.close()
                    await writer.wait_closed()
                except:
                    pass

        return handle_client

    async def handle_connect(self, reader, writer, target, account_config):
        """Handle HTTPS CONNECT method"""
        try:
            # target should be in the format host:port
            if ':' not in target:
                writer.write(b"HTTP/1.1 400 Bad Request\r\n\r\n")
                await writer.drain()
                return

            host, port_str = target.rsplit(':', 1)  # rsplit to handle IPv6 if needed
            try:
                port = int(port_str)
            except ValueError:
                writer.write(b"HTTP/1.1 400 Bad Request\r\n\r\n")
                await writer.drain()
                return

            logger.info(f"Connecting to {host}:{port} via {account_config['upstream']['name']}")

            # Create connection to target based on upstream configuration
            upstream = account_config["upstream"]
            if upstream["type"] == "tor":
                # Connect through Tor SOCKS proxy
                try:
                    target_reader, target_writer = await asyncio.open_connection(
                        upstream['socks_host'], 
                        upstream['socks_port']
                    )
                except Exception as e:
                    logger.error(f"Failed to connect to Tor SOCKS proxy: {e}")
                    writer.write(b"HTTP/1.1 502 Bad Gateway\r\n\r\n")
                    await writer.drain()
                    return
                
                # Send SOCKS5 handshake
                target_writer.write(bytearray([0x05, 0x01, 0x00]))  # Version 5, 1 auth method, no auth
                await target_writer.drain()
                
                # Read authentication response
                auth_response = await target_reader.read(2)
                if len(auth_response) < 2 or auth_response[0] != 0x05:
                    logger.error(f"SOCKS authentication failed: {auth_response}")
                    target_writer.close()
                    await target_writer.wait_closed()
                    writer.write(b"HTTP/1.1 502 Bad Gateway\r\n\r\n")
                    await writer.drain()
                    return
                
                # Send CONNECT request to target
                addr_type = 0x03  # Domain name
                host_bytes = host.encode('ascii')
                request_data = bytearray([0x05, 0x01, 0x00, addr_type])
                request_data.append(len(host_bytes))
                request_data.extend(host_bytes)
                request_data.extend(port.to_bytes(2, 'big'))
                
                target_writer.write(request_data)
                await target_writer.drain()
                
                # Read connection response
                connect_response = await target_reader.read(10)
                if len(connect_response) < 2 or connect_response[0] != 0x05 or connect_response[1] != 0x00:
                    logger.error(f"SOCKS connection failed: response was {connect_response}")
                    target_writer.close()
                    await target_writer.wait_closed()
                    writer.write(b"HTTP/1.1 502 Bad Gateway\r\n\r\n")
                    await writer.drain()
                    return
                
                # Connection established, send success to client
                writer.write(b"HTTP/1.1 200 Connection Established\r\nProxy-agent: SwissProxy/2.0\r\n\r\n")
                await writer.drain()
                
            else:
                # Direct connection to target
                try:
                    target_reader, target_writer = await asyncio.open_connection(host, port)
                except Exception as e:
                    logger.error(f"Failed to connect to target {host}:{port} - {e}")
                    writer.write(f"HTTP/1.1 502 Bad Gateway\r\n\r\n".encode())
                    await writer.drain()
                    return
                
                # Connection established, send success to client
                writer.write(b"HTTP/1.1 200 Connection Established\r\nProxy-agent: SwissProxy/2.0\r\n\r\n")
                await writer.drain()
            
            # Now bridge data between client and target
            await self.bridge_connections(reader, writer, target_reader, target_writer)
            
        except Exception as e:
            logger.error(f"Error in CONNECT: {e}")
            try:
                writer.write(b"HTTP/1.1 500 Internal Server Error\r\n\r\n")
                await writer.drain()
            except:
                pass

    async def bridge_connections(self, client_reader, client_writer, target_reader, target_writer):
        """Bridge data between client and target"""
        try:
            # Create two tasks to forward data in both directions
            async def forward_client_to_target():
                try:
                    while True:
                        data = await client_reader.read(4096)
                        if not data:
                            break
                        target_writer.write(data)
                        await target_writer.drain()
                except Exception as e:
                    logger.debug(f"Client to target forward ended: {e}")
                finally:
                    try:
                        target_writer.close()
                        await target_writer.wait_closed()
                    except:
                        pass

            async def forward_target_to_client():
                try:
                    while True:
                        data = await target_reader.read(4096)
                        if not data:
                            break
                        client_writer.write(data)
                        await client_writer.drain()
                except Exception as e:
                    logger.debug(f"Target to client forward ended: {e}")
                finally:
                    try:
                        client_writer.close()
                        await client_writer.wait_closed()
                    except:
                        pass

            # Run both directions concurrently
            await asyncio.gather(
                forward_client_to_target(),
                forward_target_to_client(),
                return_exceptions=True
            )
        except Exception as e:
            logger.error(f"Bridge connection error: {e}")

    async def start_server(self, port, account):
        """Start a single proxy server for a specific account"""
        handler = self.create_client_handler(port, account)
        server = await asyncio.start_server(
            handler,
            '0.0.0.0',
            port
        )

        logger.info(f"✅ HTTP/HTTPS Proxy started for {account['email']}")
        logger.info(f"   Route: {account['upstream']['name']}")
        logger.info(f"   Port: {port} (requested: {account['original_port']})")
        logger.info(f"   URL: http://0.0.0.0:{port}")

        async with server:
            await server.serve_forever()

    async def start_servers(self):
        """Start HTTP/HTTPS proxy servers on multiple ports"""
        tasks = []
        
        for port, account in self.account_by_port.items():
            task = asyncio.create_task(self.start_server(port, account))
            tasks.append(task)
        
        # Wait for all servers to complete (they run indefinitely)
        await asyncio.gather(*tasks, return_exceptions=True)

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