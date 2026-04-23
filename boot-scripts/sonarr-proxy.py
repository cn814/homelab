#!/usr/bin/env python3
"""Simple HTTP/HTTPS forward proxy for Sonarr Discord notifications."""
import socket
import threading
import select
import sys

PORT = 3128
BIND = '0.0.0.0'

def relay(src, dst):
    try:
        while True:
            r, _, _ = select.select([src], [], [], 30)
            if not r:
                break
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except Exception:
        pass
    finally:
        for s in (src, dst):
            try:
                s.shutdown(socket.SHUT_RDWR)
            except Exception:
                pass

def handle(conn, addr):
    try:
        data = b''
        while b'\r\n\r\n' not in data:
            chunk = conn.recv(4096)
            if not chunk:
                return
            data += chunk

        lines = data.split(b'\r\n')
        method, path, _ = lines[0].split(b' ', 2)

        if method == b'CONNECT':
            host, port = path.rsplit(b':', 1)
            host = host.decode()
            port = int(port)
            remote = socket.create_connection((host, port), timeout=30)
            conn.sendall(b'HTTP/1.1 200 Connection established\r\n\r\n')
            t = threading.Thread(target=relay, args=(remote, conn), daemon=True)
            t.start()
            relay(conn, remote)
            t.join()
        else:
            # Plain HTTP
            if path.startswith(b'http://'):
                path = path[7:]
                slash = path.find(b'/')
                if slash == -1:
                    host_part = path
                    path = b'/'
                else:
                    host_part = path[:slash]
                    path = path[slash:]
            else:
                host_part = b''
                for line in lines[1:]:
                    if line.lower().startswith(b'host:'):
                        host_part = line[5:].strip()
                        break

            host_part = host_part.decode()
            port = 80
            if ':' in host_part:
                host_part, port = host_part.rsplit(':', 1)
                port = int(port)

            new_req = method + b' ' + path + b' HTTP/1.1\r\n'
            for line in lines[1:]:
                if line.lower().startswith(b'proxy-'):
                    continue
                new_req += line + b'\r\n'

            remote = socket.create_connection((host_part, port), timeout=30)
            remote.sendall(new_req)
            relay(remote, conn)
    except Exception as e:
        pass
    finally:
        try:
            conn.close()
        except Exception:
            pass

def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((BIND, PORT))
    srv.listen(64)
    print(f'Proxy listening on {BIND}:{PORT}', flush=True)
    while True:
        conn, addr = srv.accept()
        threading.Thread(target=handle, args=(conn, addr), daemon=True).start()

if __name__ == '__main__':
    main()
