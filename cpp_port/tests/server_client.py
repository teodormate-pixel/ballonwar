#!/usr/bin/env python3
"""Protocol test for the C++ BalloonWar server (tests/server_client.py).

Walks a full session: auth (auto-register), room list, create/join,
ready/start, 20 Hz state updates with anti-cheat position clamping,
terrain modifications, chat, player data and account deletion.

Usage: python3 tests/server_client.py [port]   (default 9879)
"""

from __future__ import annotations

import asyncio
import json
import os
import sys

import websockets

CHECKS = 0
FAILURES = 0


def check(name: str, condition: bool) -> None:
    global CHECKS, FAILURES
    CHECKS += 1
    if not condition:
        FAILURES += 1
        print(f"FAIL  {name}")


class Client:
    def __init__(self, port: int, tls: bool = False):
        self.port = port
        self.tls = tls
        self.ws = None
        self.inbox: list[dict] = []

    async def connect(self) -> None:
        if self.tls:
            import ssl

            context = ssl._create_unverified_context()
            self.ws = await websockets.connect(
                f"wss://127.0.0.1:{self.port}", ssl=context)
        else:
            self.ws = await websockets.connect(f"ws://127.0.0.1:{self.port}")
        asyncio.create_task(self._reader())

    async def _reader(self) -> None:
        try:
            async for raw in self.ws:
                try:
                    self.inbox.append(json.loads(raw))
                except (json.JSONDecodeError, TypeError):
                    pass
        except Exception:
            pass

    async def send(self, **payload) -> None:
        await self.ws.send(json.dumps(payload))

    async def wait_for(self, msg_type: str, timeout: float = 6.0) -> dict:
        loop = asyncio.get_event_loop()
        deadline = loop.time() + timeout
        while loop.time() < deadline:
            for i, message in enumerate(self.inbox):
                if message.get("type") == msg_type:
                    return self.inbox.pop(i)
            await asyncio.sleep(0.02)
        raise TimeoutError(f"no {msg_type} (inbox={[m.get('type') for m in self.inbox]})")

    async def drain(self, seconds: float = 0.2) -> None:
        await asyncio.sleep(seconds)
        self.inbox.clear()

    async def close(self) -> None:
        if self.ws:
            await self.ws.close()


async def main() -> int:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 9879
    tls = len(sys.argv) > 2 and sys.argv[2] == "tls"
    # unique accounts so the test can run against a persistent users file
    suffix = f"{port}_{os.getpid()}"
    user_host = f"cpp_tester_{suffix}"
    user_guest = f"cpp_guest_{suffix}"
    host = Client(port, tls)
    guest = Client(port, tls)
    await host.connect()
    await guest.connect()

    # --- auth (auto-register on first login) ---
    await host.send(type="ping")
    check("pong", (await host.wait_for("pong")).get("type") == "pong")

    await host.send(type="auth", username=user_host, password="hunter2")
    auth = await host.wait_for("auth_ok")
    check("auth_ok id", isinstance(auth.get("player_id"), int) and auth["player_id"] > 0)
    check("auth_ok modes", len(auth.get("game_modes", [])) >= 3)

    await guest.send(type="auth", username=user_guest, password="guestpw")
    gauth = await guest.wait_for("auth_ok")
    check("guest auth", gauth.get("username") == user_guest)

    # wrong password on an existing account
    bad = Client(port, tls)
    await bad.connect()
    await bad.send(type="auth", username=user_host, password="wrong")
    check("wrong password", (await bad.wait_for("auth_error")).get("type") == "auth_error")
    await bad.close()

    # --- rooms ---
    await host.send(type="list_rooms")
    check("room_list", isinstance((await host.wait_for("room_list")).get("rooms"), list))

    await host.send(type="create_room", name="Test Room", password="",
                    settings={"game_mode": "classic", "time_limit": 5}, seed=4242)
    created = await host.wait_for("room_created")
    room_id = created.get("room_id", "")
    check("room_created", len(room_id) == 4)
    check("host in room", created["players"][0]["id"] == auth["player_id"])

    await guest.send(type="join_room", room_id=room_id, password="")
    joined = await guest.wait_for("joined")
    check("joined room", joined.get("room_id") == room_id)
    check("seed passed", joined.get("seed") == 4242)
    check("player_joined",
          (await host.wait_for("player_joined")).get("name") == user_guest)

    await host.send(type="player_ready", character_id=3)
    ready = await guest.wait_for("player_ready")
    check("player_ready char", ready.get("character_id") == 3)
    await guest.send(type="player_ready", character_id=2)
    await host.wait_for("player_ready")

    # --- game start (3 s countdown) ---
    await guest.send(type="start_game")
    check("guest cannot start", (await guest.wait_for("error")).get("type") == "error")
    await host.send(type="start_game")
    check("countdown", (await host.wait_for("game_starting")).get("countdown") == 3)
    started = await host.wait_for("game_started", timeout=6.0)
    check("game_started seed", started.get("seed") == 4242)
    check("game_started mode", started.get("game_mode") == "classic")
    check("ends_at", started.get("ends_at", 0) > 0)

    # --- state updates + position clamping (max 2 m per input) ---
    await host.drain()
    base = await host.wait_for("state_update")
    before = next(p for p in base["players"] if p["id"] == auth["player_id"])
    await host.send(type="player_input", pos=[100.0, 60.0, 100.0], rot_x=1.0,
                    actions={"weapon": 1}, score=10, kills=2, hp=90.0, alive=True)
    update = await host.wait_for("state_update")
    me = next(p for p in update["players"] if p["id"] == auth["player_id"])
    moved = ((me["pos"][0] - before["pos"][0]) ** 2 +
             (me["pos"][2] - before["pos"][2]) ** 2) ** 0.5
    check("position clamped", abs(moved - 2.0) < 0.05)
    check("weapon synced", me["weapon"] == 1)
    check("score synced", me["score"] == 10)
    check("hp synced", abs(me["hp"] - 90.0) < 0.01)

    # falling below the world respawns at y=150 (same column, no clamp)
    await host.send(type="player_input",
                    pos=[me["pos"][0], -500.0, me["pos"][2]], rot_x=0.0)
    update = await host.wait_for("state_update")
    me = next(p for p in update["players"] if p["id"] == auth["player_id"])
    check("respawn y", me["pos"][1] > 100.0)

    # --- terrain + chat ---
    await host.send(type="terrain_modify", pos=[1, 2, 3], block_type=4,
                    action_type="dig")
    change = await guest.wait_for("terrain_change")
    check("terrain broadcast", change.get("pos") == [1, 2, 3])

    await guest.send(type="chat", message="salut de la guest")
    chat = await host.wait_for("chat")
    check("chat relay", chat.get("message") == "salut de la guest")

    # --- player data ---
    await host.send(type="save_data", data={"inventory": [1, 2, 3], "hp": 77})
    check("save_data", (await host.wait_for("save_data_result")).get("success") is True)
    await host.send(type="load_data")
    loaded = await host.wait_for("load_data_result")
    check("load_data", loaded.get("data", {}).get("hp") == 77)

    # --- leave / room closed / player_left ---
    await host.send(type="leave_room")
    check("room_closed", (await guest.wait_for("room_closed")).get("type") == "room_closed")

    await host.send(type="create_room", name="Second", password="",
                    settings={"game_mode": "sandbox"}, seed=7)
    room2 = (await host.wait_for("room_created"))["room_id"]
    await guest.send(type="join_room", room_id=room2, password="")
    await guest.wait_for("joined")
    await host.wait_for("player_joined")
    await guest.send(type="leave_room")
    check("player_left",
          (await host.wait_for("player_left")).get("player_id") == gauth["player_id"])
    await guest.send(type="join_room", room_id=room2, password="")
    await guest.wait_for("joined")
    await host.wait_for("player_joined")
    await host.send(type="leave_room")
    check("room_closed again",
          (await guest.wait_for("room_closed")).get("type") == "room_closed")

    # --- delete account (connection is closed by the server) ---
    await guest.send(type="delete_account")
    try:
        await asyncio.wait_for(guest.ws.wait_closed(), timeout=3.0)
        check("delete closes socket", True)
    except asyncio.TimeoutError:
        check("delete closes socket", False)

    # deleted account can be re-created with the same name
    again = Client(port, tls)
    await again.connect()
    await again.send(type="auth", username=user_guest, password="newpw")
    check("account recreated", (await again.wait_for("auth_ok")).get("type") == "auth_ok")
    await again.close()

    await host.close()
    print(f"{CHECKS} checks, {FAILURES} failures")
    print("SERVER OK" if FAILURES == 0 else "SERVER FAIL")
    return 0 if FAILURES == 0 else 1


if __name__ == "__main__":
    try:
        sys.exit(asyncio.run(main()))
    except TimeoutError as exc:
        print(f"FAIL  timeout: {exc}")
        print("SERVER FAIL")
        sys.exit(1)
