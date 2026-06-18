#!/usr/bin/env python3
"""Master server for Balloon War - public room listing via HTTP."""
import json
import time
import uuid
from http.server import HTTPServer, BaseHTTPRequestHandler

SERVERS = {}
TIMEOUT_SEC = 70  # servers must ping every 30s, cleanup at 70

class Handler(BaseHTTPRequestHandler):
    def do_OPTIONS(self):
        self._cors()
        self.send_response(204)
        self.end_headers()

    def do_GET(self):
        self._cors()
        if self.path == "/list":
            now = time.time()
            active = [s for s in SERVERS.values()
                      if now - s["last_seen"] < TIMEOUT_SEC]
            self._json({"servers": active})
        else:
            self._json({"error": "not_found"}, 404)

    def do_POST(self):
        self._cors()
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length) if length else b"{}"
        try:
            data = json.loads(body)
        except json.JSONDecodeError:
            return self._json({"error": "bad_json"}, 400)

        if self.path == "/register":
            sid = data.get("id") or str(uuid.uuid4())[:8]
            SERVERS[sid] = {
                "id": sid,
                "name": data.get("name", "Unnamed"),
                "ip": data.get("ip", "?"),
                "port": data.get("port", 8912),
                "players": data.get("players", 0),
                "max_players": data.get("max_players", 8),
                "has_password": data.get("has_password", False),
                "version": data.get("version", "1.0"),
                "last_seen": time.time(),
                "created": time.time(),
            }
            self._json({"ok": True, "id": sid})

        elif self.path == "/ping":
            sid = data.get("id")
            if sid and sid in SERVERS:
                SERVERS[sid]["last_seen"] = time.time()
                SERVERS[sid]["players"] = data.get("players", SERVERS[sid]["players"])
                self._json({"ok": True})
            else:
                self._json({"error": "unknown_id"}, 404)

        elif self.path == "/unregister":
            sid = data.get("id")
            if sid and sid in SERVERS:
                del SERVERS[sid]
            self._json({"ok": True})

        else:
            self._json({"error": "not_found"}, 404)

    def _json(self, obj, code=200):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(json.dumps(obj, indent=2).encode())

    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def log_message(self, fmt, *args):
        pass  # quieter logs

if __name__ == "__main__":
    import sys
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    server = HTTPServer(("0.0.0.0", port), Handler)
    print(f"[Master Server] Listening on 0.0.0.0:{port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down.")
        server.server_close()
