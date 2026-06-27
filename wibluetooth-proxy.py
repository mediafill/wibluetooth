#!/usr/bin/env python3
"""WiBluetooth HTTP CONNECT -> SOCKS5 bridge.
Listens on HTTP_PORT, forwards CONNECT requests through the SOCKS5 dispatch-proxy.
Auto-reconnects to SOCKS5 on failure. Fixes 'UnsupportedProxyProtocol' for apps
that don't support socks5:// proxies.
"""
import socket, threading, sys, os, signal, time, errno

SOCKS_PORT = int(os.environ.get("SOCKS_PORT", "1080"))
HTTP_PORT  = int(os.environ.get("HTTP_PROXY_PORT", "8888"))
LOG        = "/tmp/wibluetooth-http.log"

def log(msg):
    ts = time.strftime("%H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line, flush=True)
    try:
        with open(LOG, "a") as f:
            f.write(line + "\n")
    except Exception:
        pass

def relay(src, dst, tag=""):
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except (BrokenPipeError, ConnectionResetError, OSError):
        pass
    finally:
        try: src.close()
        except Exception: pass
        try: dst.close()
        except Exception: pass

def socks5_connect(host, port):
    """Try IPv4 then IPv6 for SOCKS5 handshake. Uses remote DNS via SOCKS5."""
    last_err = None
    for socks_host in ["127.0.0.1", "::1"]:
        try:
            s = socket.create_connection((socks_host, SOCKS_PORT), timeout=10)
            s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            s.sendall(b"\x05\x01\x00")
            hello = s.recv(2)
            if len(hello) < 2:
                s.close()
                raise ConnectionRefusedError("SOCKS5 hello truncated")
            # Use DOMAIN address type (0x03) for remote DNS resolution
            host_bytes = host.encode("ascii")
            s.sendall(b"\x05\x01\x00\x03" + bytes([len(host_bytes)]) + host_bytes + port.to_bytes(2, "big"))
            resp = s.recv(10)
            if len(resp) < 2 or resp[1] != 0x00:
                s.close()
                raise ConnectionRefusedError(f"SOCKS5 connect failed: {resp[1] if len(resp)>1 else '?'}")
            return s
        except Exception as e:
            last_err = e
            continue
    raise last_err

def handle(client):
    try:
        client.settimeout(30)
        first_line = b""
        while b"\r\n\r\n" not in first_line:
            try:
                chunk = client.recv(4096)
            except socket.timeout:
                client.close()
                return
            if not chunk:
                client.close()
                return
            first_line += chunk
        client.settimeout(None)

        req_line = first_line.split(b"\r\n")[0].decode("utf-8", errors="replace")
        parts = req_line.split(" ", 2)
        if len(parts) < 3:
            client.sendall(b"HTTP/1.1 400 Bad Request\r\n\r\n")
            client.close()
            return
        method, url, _ = parts

        if method == "CONNECT":
            if ":" not in url:
                client.sendall(b"HTTP/1.1 400 Bad Request\r\n\r\n")
                client.close()
                return
            host, port_str = url.rsplit(":", 1)
            port = int(port_str)
            remote = socks5_connect(host, port)
            client.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
            body_start = first_line.split(b"\r\n\r\n", 1)[1]
            if body_start:
                remote.sendall(body_start)
            t1 = threading.Thread(target=relay, args=(client, remote), daemon=True)
            t2 = threading.Thread(target=relay, args=(remote, client), daemon=True)
            t1.start()
            t2.start()
            t1.join()
            t2.join()
        else:
            client.sendall(b"HTTP/1.1 400 Only CONNECT supported\r\n\r\n")
            client.close()
    except Exception as e:
        log(f"handle error: {e}")
        try:
            client.sendall(b"HTTP/1.1 502 Bad Gateway\r\n\r\n")
        except Exception:
            pass
        try:
            client.close()
        except Exception:
            pass

def main():
    # Truncate old log
    try:
        with open(LOG, "w") as f:
            f.write("")
    except Exception:
        pass

    # Write PID file
    with open("/tmp/wibluetooth-http.pid", "w") as f:
        f.write(str(os.getpid()))

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    except Exception:
        pass
    srv.bind(("127.0.0.1", HTTP_PORT))
    srv.listen(128)
    log(f"HTTP CONNECT proxy started on 127.0.0.1:{HTTP_PORT} -> SOCKS5 :{SOCKS_PORT}")

    def shutdown(sig, frame):
        log("Shutting down HTTP bridge")
        try: srv.close()
        except Exception: pass
        try: os.remove("/tmp/wibluetooth-http.pid")
        except Exception: pass
        sys.exit(0)

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    while True:
        try:
            client, _ = srv.accept()
            client.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            threading.Thread(target=handle, args=(client,), daemon=True).start()
        except OSError as e:
            if e.errno == errno.EBADF:
                break
            log(f"accept error: {e}")
            time.sleep(0.1)
        except Exception as e:
            log(f"accept error: {e}")
            time.sleep(0.1)

if __name__ == "__main__":
    main()
