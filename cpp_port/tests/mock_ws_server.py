#!/usr/bin/env python3
"""Minimal BalloonWar WebSocket server used by tests/net_test.cpp.

Speaks just enough of the protocol to verify the C++ client transport:
auth, room list, room creation and player input echo.
"""

from __future__ import annotations

import asyncio
import json
import sys

import websockets

CLIENTS: dict[int, websockets.WebSocketServerProtocol] = {}
NEXT_ID = 1


async def handler(ws, path=None):
    global NEXT_ID
    player_id = 0
    username = ""
    room_id = ""
    try:
        async for raw in ws:
            try:
                message = json.loads(raw)
            except (json.JSONDecodeError, TypeError):
                continue
            msg_type = message.get("type", "")
            if msg_type == "auth":
                username = str(message.get("username", "probe"))[:50]
                player_id = NEXT_ID
                NEXT_ID += 1
                CLIENTS[player_id] = ws
                await ws.send(
                    json.dumps(
                        {
                            "type": "auth_ok",
                            "player_id": player_id,
                            "username": username,
                            "game_modes": [],
                        }
                    )
                )
            elif msg_type == "list_rooms":
                await ws.send(json.dumps({"type": "room_list", "rooms": []}))
            elif msg_type == "create_room":
                room_id = str(message.get("room_id") or "TEST")
                await ws.send(
                    json.dumps(
                        {
                            "type": "room_created",
                            "room_id": room_id,
                            "players": [{"id": player_id, "name": username}],
                            "settings": {"game_mode": "classic"},
                        }
                    )
                )
            elif msg_type == "player_input":
                await ws.send(
                    json.dumps(
                        {
                            "type": "state_update",
                            "players": [
                                {
                                    "player_id": player_id,
                                    "name": username,
                                    "pos": message.get("pos", [0, 0, 0]),
                                    "rot_x": message.get("rot_x", 0),
                                    "alive": True,
                                }
                            ],
                            "time_remaining": 299,
                        }
                    )
                )
            elif msg_type == "chat":
                await ws.send(
                    json.dumps(
                        {
                            "type": "chat",
                            "name": username,
                            "message": message.get("message", ""),
                        }
                    )
                )
            elif msg_type == "leave_room":
                room_id = ""
                await ws.send(json.dumps({"type": "room_list", "rooms": []}))
    finally:
        CLIENTS.pop(player_id, None)


async def main() -> None:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 9876
    ssl_context = None
    if len(sys.argv) > 3:
        import ssl

        ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ssl_context.load_cert_chain(sys.argv[2], sys.argv[3])
    async with websockets.serve(handler, "127.0.0.1", port,
                                ssl=ssl_context):
        print(f"mock ws server on {port} tls={ssl_context is not None}",
              flush=True)
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
