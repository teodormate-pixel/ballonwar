"""
Send a single MCP-style command to the comm server.
Usage: python tools\send_mcp_command.py [host] [port]
Defaults: 127.0.0.1 8765
"""
import sys, socket, json
HOST='127.0.0.1'
PORT=8765
if len(sys.argv)>=2: HOST=sys.argv[1]
if len(sys.argv)>=3:
    try:
        PORT=int(sys.argv[2])
    except:
        pass

msg = {
    "type": "mcp_command",
    "command": "generate_chunk_and_screenshot",
    "to": "godot_mcp",
    "params": {
        "cx": 0,
        "cz": 0,
        "screenshot_path": "tools/vei_screenshots/test_chunk.png",
        "export_build": True,
        "export_path": "builds/ballonwar_test_build.exe"
    }
}

s = None
try:
    s = socket.create_connection((HOST, PORT), timeout=5)
    s.sendall((json.dumps(msg, ensure_ascii=False) + '\n').encode('utf-8'))
    print('Sent command:', json.dumps(msg, ensure_ascii=False))
except Exception as e:
    print('Error sending command:', e)
finally:
    try:
        if s: s.close()
    except:
        pass
