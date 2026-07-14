"""
Simple TCP JSON broadcast server for agent-to-agent communication.
Usage (on the machine where the server will run):
    python tools\comm_server.py [host] [port]
Default host: 127.0.0.1
Default port: 8765

Protocol:
- Each message is a single JSON object encoded as UTF-8, terminated by a newline ("\n").
- Clients should send a hello handshake: {"type": "hello", "agent": "name"}
- Server broadcasts all received messages (except raw binary) to all connected clients.
- Server responds to {"type":"ping"} with {"type":"pong"}.

NOTE: This server is intentionally minimal and has no authentication. Do not expose it publicly without adding security.
"""

import socket
import threading
import json
import sys
from typing import List

HOST = '127.0.0.1'
PORT = 8765

clients_lock = threading.Lock()
clients: List[socket.socket] = []


def broadcast(message: str, origin: socket.socket = None):
    """Broadcast a string message (already JSON/text) followed by newline to all clients except origin."""
    with clients_lock:
        for c in list(clients):
            if c is origin:
                continue
            try:
                c.sendall(message.encode('utf-8') + b"\n")
            except Exception:
                try:
                    c.close()
                except Exception:
                    pass
                clients.remove(c)


def handle_client(conn: socket.socket, addr):
    print(f"[+] Connected: {addr}")
    with clients_lock:
        clients.append(conn)
    buffer = b""
    try:
        while True:
            data = conn.recv(4096)
            if not data:
                break
            buffer += data
            while b"\n" in buffer:
                line, buffer = buffer.split(b"\n", 1)
                line = line.strip()
                if not line:
                    continue
                try:
                    text = line.decode('utf-8')
                except UnicodeDecodeError:
                    print(f"[!] Received non-UTF8 from {addr}, ignoring")
                    continue
                try:
                    obj = json.loads(text)
                except json.JSONDecodeError:
                    print(f"[!] Invalid JSON from {addr}: {text}")
                    continue

                # Basic built-in handling
                if isinstance(obj, dict) and obj.get('type') == 'ping':
                    reply = json.dumps({'type': 'pong'})
                    try:
                        conn.sendall(reply.encode('utf-8') + b"\n")
                    except Exception:
                        pass
                    continue

                # Log and broadcast
                print(f"[<] From {addr}: {json.dumps(obj, ensure_ascii=False)}")
                broadcast(json.dumps({'from': f"{addr}", 'payload': obj}), origin=conn)
    except Exception as e:
        print(f"[!] Connection error {addr}: {e}")
    finally:
        print(f"[-] Disconnected: {addr}")
        with clients_lock:
            try:
                clients.remove(conn)
            except ValueError:
                pass
        try:
            conn.close()
        except Exception:
            pass


def run(host=HOST, port=PORT):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((host, port))
    s.listen(16)
    print(f"Comm server listening on {host}:{port}")
    try:
        while True:
            conn, addr = s.accept()
            t = threading.Thread(target=handle_client, args=(conn, addr), daemon=True)
            t.start()
    except KeyboardInterrupt:
        print('\nShutting down server...')
    finally:
        with clients_lock:
            for c in clients:
                try:
                    c.close()
                except Exception:
                    pass
            clients.clear()
        try:
            s.close()
        except Exception:
            pass


if __name__ == '__main__':
    h = HOST
    p = PORT
    if len(sys.argv) >= 2:
        h = sys.argv[1]
    if len(sys.argv) >= 3:
        try:
            p = int(sys.argv[2])
        except Exception:
            pass
    run(h, p)
