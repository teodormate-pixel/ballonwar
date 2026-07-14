"""
Simple comm client for agent 'vei' with file logging.
Connects to the comm server, sends a hello, prints received messages, ACKs instruction payloads,
and appends all important events to tools\vei.log.
Usage: python tools\agent_vei.py [host] [port]
"""
import sys
import socket
import json
import time
import os
import datetime

HOST = '127.0.0.1'
PORT = 8765
AGENT_NAME = 'vei'

# Log file path: tools/vei.log (next to this script)
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
LOG_PATH = os.path.join(SCRIPT_DIR, 'vei.log')


def log_line(line: str):
    ts = datetime.datetime.now().astimezone().isoformat()
    try:
        with open(LOG_PATH, 'a', encoding='utf-8') as f:
            f.write(f"{ts} {line}\n")
    except Exception:
        # Best-effort logging; don't crash on logging failures
        pass


if len(sys.argv) >= 2:
    HOST = sys.argv[1]
if len(sys.argv) >= 3:
    try:
        PORT = int(sys.argv[2])
    except Exception:
        pass


def send(sock, obj):
    try:
        text = json.dumps(obj, ensure_ascii=False)
        sock.sendall((text + '\n').encode('utf-8'))
        print("[SEND]", text)
        log_line(f"SEND {text}")
    except Exception as e:
        print(f"[!] Send error: {e}")
        log_line(f"SEND_ERROR {e}")


s = None
try:
    print(f"Connecting to {HOST}:{PORT} as {AGENT_NAME}...")
    log_line(f"START Connecting to {HOST}:{PORT} as {AGENT_NAME}")
    s = socket.create_connection((HOST, PORT))
    # Send hello
    send(s, {'type': 'hello', 'agent': AGENT_NAME})
    print("Connected. Waiting for messages from peers (deepsek)...")
    log_line("Connected")

    buffer = b''
    while True:
        chunk = s.recv(4096)
        if not chunk:
            print("[!] Server closed connection")
            log_line("SERVER_CLOSED")
            break
        buffer += chunk
        while b'\n' in buffer:
            line, buffer = buffer.split(b'\n', 1)
            if not line.strip():
                continue
            try:
                text = line.decode('utf-8')
            except Exception:
                print("[!] Received non-UTF8 line, ignoring")
                log_line("RECV_NON_UTF8")
                continue
            try:
                obj = json.loads(text)
            except Exception:
                print(f"[RAW] {text}")
                log_line(f"RECV_RAW {text}")
                continue
            pretty = json.dumps(obj, ensure_ascii=False)
            print("[RECV]", pretty)
            log_line(f"RECV {pretty}")

            # If server-wrapped message with payload, check for instructions
            payload = obj.get('payload') if isinstance(obj, dict) else None
            if isinstance(payload, dict):
                # Simple rule: if payload has 'type' == 'instruction' or 'cmd', ACK it
                if payload.get('type') in ('instruction', 'cmd') or payload.get('to') in (AGENT_NAME, 'all'):
                    print(f"[INSTR] Received instruction: {json.dumps(payload, ensure_ascii=False)}")
                    log_line(f"INSTR {json.dumps(payload, ensure_ascii=False)}")
                    ack = {'type': 'ack', 'agent': AGENT_NAME, 'ack_for': payload}
                    send(s, ack)

except ConnectionRefusedError:
    msg = f"[!] Could not connect to {HOST}:{PORT} - is the server running?"
    print(msg)
    log_line(f"ERROR {msg}")
except KeyboardInterrupt:
    print('\nInterrupted by user')
    log_line('INTERRUPT')
except Exception as e:
    print(f"[!] Error: {e}")
    log_line(f"ERROR {e}")
finally:
    try:
        if s:
            s.close()
    except Exception:
        pass
    print("Client exiting")
    log_line("EXIT")
