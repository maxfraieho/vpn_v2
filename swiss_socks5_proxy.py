import json
import asyncio
import logging
import socket
import struct
from contextlib import closing

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[
        logging.FileHandler('/data/data/com.termux/files/home/vpn_v2/socks5_proxy.log'),
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

class SwissSOCKS5Proxy:
    def __init__(self, config):
        self.config = config
        self.account_by_port = {}
        self.used_ports = set()

        # Map ports to accounts with port availability check
        # SOCKS5 ports will be HTTP port + 1000 by default
        for email, acc_config in config["accounts"].items():
            # SOCKS5 port = HTTP port + 1000 (e.g., 8888 -> 9888)
            requested_port = acc_config["proxy_port"] + 1000

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
                "http_port": acc_config["proxy_port"],
                **acc_config
            }

    def create_client_handler(self, port, account_config):
        """Create a SOCKS5 client handler with account config bound to it"""
        async def handle_client(reader, writer):
            """Handle a SOCKS5 client connection"""
            try:
                # SOCKS5 greeting
                # Client sends: [VER, NMETHODS, METHODS]
                greeting = await reader.read(2)
                if len(greeting) < 2:
                    return

                version, nmethods = greeting[0], greeting[1]
                if version != 0x05:  # SOCKS version 5
                    logger.error(f"[Port {port}] Unsupported SOCKS version: {version}")
                    return

                # Read authentication methods
                methods = await reader.read(nmethods)

                # We support no authentication (0x00)
                if 0x00 not in methods:
                    # No acceptable methods
                    writer.write(bytes([0x05, 0xFF]))
                    await writer.drain()
                    return

                # Send method selection: [VER, METHOD]
                writer.write(bytes([0x05, 0x00]))  # No authentication required
                await writer.drain()

                # SOCKS5 request
                # Client sends: [VER, CMD, RSV, ATYP, DST.ADDR, DST.PORT]
                request_header = await reader.read(4)
                if len(request_header) < 4:
                    return

                version, cmd, rsv, atyp = request_header

                if version != 0x05:
                    logger.error(f"[Port {port}] Invalid SOCKS version in request: {version}")
                    return

                # Parse destination address based on address type
                if atyp == 0x01:  # IPv4
                    addr_bytes = await reader.read(4)
                    dst_addr = socket.inet_ntop(socket.AF_INET, addr_bytes)
                elif atyp == 0x03:  # Domain name
                    addr_len_bytes = await reader.read(1)
                    addr_len = addr_len_bytes[0]
                    addr_bytes = await reader.read(addr_len)
                    dst_addr = addr_bytes.decode('ascii')
                elif atyp == 0x04:  # IPv6
                    addr_bytes = await reader.read(16)
                    dst_addr = socket.inet_ntop(socket.AF_INET6, addr_bytes)
                else:
                    logger.error(f"[Port {port}] Unsupported address type: {atyp}")
                    # Send error response
                    writer.write(bytes([0x05, 0x08, 0x00, 0x01]) + bytes(6))
                    await writer.drain()
                    return

                # Read destination port
                port_bytes = await reader.read(2)
                dst_port = struct.unpack('!H', port_bytes)[0]

                logger.info(f"[Port {port}] SOCKS5 {cmd} request to {dst_addr}:{dst_port} via {account_config['upstream']['name']}")

                # We only support CONNECT command (0x01)
                if cmd == 0x01:  # CONNECT
                    await self.handle_connect(reader, writer, dst_addr, dst_port, account_config, port)
                else:
                    logger.error(f"[Port {port}] Unsupported command: {cmd}")
                    # Send command not supported error
                    writer.write(bytes([0x05, 0x07, 0x00, 0x01]) + bytes(6))
                    await writer.drain()

            except Exception as e:
                logger.error(f"[Port {port}] Error handling client: {e}", exc_info=True)
            finally:
                try:
                    writer.close()
                    await writer.wait_closed()
                except:
                    pass

        return handle_client

    async def handle_connect(self, client_reader, client_writer, dst_addr, dst_port, account_config, listen_port):
        """Handle SOCKS5 CONNECT command"""
        try:
            upstream = account_config["upstream"]

            if upstream["type"] == "tor":
                # Connect through Tor SOCKS proxy
                try:
                    target_reader, target_writer = await asyncio.open_connection(
                        upstream['socks_host'],
                        upstream['socks_port']
                    )
                except Exception as e:
                    logger.error(f"[Port {listen_port}] Failed to connect to Tor: {e}")
                    # Send connection refused error
                    client_writer.write(bytes([0x05, 0x05, 0x00, 0x01]) + bytes(6))
                    await client_writer.drain()
                    return

                # Send SOCKS5 handshake to Tor
                target_writer.write(bytes([0x05, 0x01, 0x00]))  # Version 5, 1 auth method, no auth
                await target_writer.drain()

                # Read authentication response
                auth_response = await target_reader.read(2)
                if len(auth_response) < 2 or auth_response[0] != 0x05:
                    logger.error(f"[Port {listen_port}] Tor SOCKS authentication failed")
                    client_writer.write(bytes([0x05, 0x05, 0x00, 0x01]) + bytes(6))
                    await client_writer.drain()
                    target_writer.close()
                    await target_writer.wait_closed()
                    return

                # Send CONNECT request to Tor
                request_data = bytearray([0x05, 0x01, 0x00, 0x03])  # CONNECT, domain name
                host_bytes = dst_addr.encode('ascii')
                request_data.append(len(host_bytes))
                request_data.extend(host_bytes)
                request_data.extend(struct.pack('!H', dst_port))

                target_writer.write(request_data)
                await target_writer.drain()

                # Read connection response from Tor
                connect_response = await target_reader.read(10)
                if len(connect_response) < 2 or connect_response[0] != 0x05 or connect_response[1] != 0x00:
                    logger.error(f"[Port {listen_port}] Tor SOCKS connection failed")
                    client_writer.write(bytes([0x05, 0x05, 0x00, 0x01]) + bytes(6))
                    await client_writer.drain()
                    target_writer.close()
                    await target_writer.wait_closed()
                    return

                logger.info(f"[Port {listen_port}] Connected to {dst_addr}:{dst_port} via Tor")

            else:
                # Direct connection
                try:
                    target_reader, target_writer = await asyncio.open_connection(dst_addr, dst_port)
                    logger.info(f"[Port {listen_port}] Connected to {dst_addr}:{dst_port} directly")
                except Exception as e:
                    logger.error(f"[Port {listen_port}] Failed to connect to {dst_addr}:{dst_port}: {e}")
                    # Send connection refused error
                    client_writer.write(bytes([0x05, 0x05, 0x00, 0x01]) + bytes(6))
                    await client_writer.drain()
                    return

            # Send success response to client
            # [VER, REP, RSV, ATYP, BND.ADDR, BND.PORT]
            response = bytes([0x05, 0x00, 0x00, 0x01])  # Success
            response += bytes([0, 0, 0, 0])  # Bind address 0.0.0.0
            response += bytes([0, 0])  # Bind port 0
            client_writer.write(response)
            await client_writer.drain()

            # Now relay data between client and target
            await self.relay_data(client_reader, client_writer, target_reader, target_writer, listen_port)

        except Exception as e:
            logger.error(f"[Port {listen_port}] Error in CONNECT: {e}", exc_info=True)

    async def relay_data(self, client_reader, client_writer, target_reader, target_writer, port):
        """Relay data between client and target"""
        try:
            async def forward_client_to_target():
                try:
                    while True:
                        data = await client_reader.read(8192)
                        if not data:
                            break
                        target_writer.write(data)
                        await target_writer.drain()
                except Exception as e:
                    logger.debug(f"[Port {port}] Client->Target relay ended: {e}")
                finally:
                    try:
                        target_writer.close()
                        await target_writer.wait_closed()
                    except:
                        pass

            async def forward_target_to_client():
                try:
                    while True:
                        data = await target_reader.read(8192)
                        if not data:
                            break
                        client_writer.write(data)
                        await client_writer.drain()
                except Exception as e:
                    logger.debug(f"[Port {port}] Target->Client relay ended: {e}")
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
            logger.error(f"[Port {port}] Relay error: {e}")

    async def start_server(self, port, account):
        """Start a single SOCKS5 proxy server for a specific account"""
        handler = self.create_client_handler(port, account)
        server = await asyncio.start_server(
            handler,
            '0.0.0.0',
            port
        )

        logger.info(f"✅ SOCKS5 Proxy started for {account['email']}")
        logger.info(f"   Route: {account['upstream']['name']}")
        logger.info(f"   Port: {port} (HTTP port: {account['http_port']})")
        logger.info(f"   URL: socks5://0.0.0.0:{port}")

        async with server:
            await server.serve_forever()

    async def start_servers(self):
        """Start SOCKS5 proxy servers on multiple ports"""
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

        proxy = SwissSOCKS5Proxy(config)
        asyncio.run(proxy.start_servers())

    except FileNotFoundError:
        logger.error(f"Configuration file not found: {CONFIG_FILE}")
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON in config file: {e}")
    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)
        raise

if __name__ == "__main__":
    main()
