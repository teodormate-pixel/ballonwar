#!/usr/bin/env python3
"""Throughput benchmark for a BalloonWar server.

  python3 tests/bench_server.py [port] [clients] [messages]

Measures:
  - pipelined ping/pong round-trips (frame + JSON parse + send path)
  - state_update broadcast rate with N players in a running match
"""

from __future__ import annotations

import asyncio
import json
import sys
import time

import websockets


class Bench:
    def __init__(self, port: int, user: str):
        self.port = port
        self.user = user
        self.ws = None
        self.inbox: list[dict] = []
        self.task = None

    async def connect(self) -> None:
        self.ws = await websockets.connect(f"ws://127.0.0.1:{self.port}")
        self.task = asyncio.create_task(self._reader())

    async def _reader(self) -> None:
        try:
            async for raw in self.ws:
                self.inbox.append(json.loads(raw))
        except Exception:
            pass

    async def send(self, **payload) -> None:
        await self.ws.send(json.dumps(payload))

    async def auth(self) -> None:
        await self.send(type="auth", username=self.user, password="bench")
        await self.wait("auth_ok")

    async def wait(self, msg_type: str, timeout: float = 5.0) -> dict:
        loop = asyncio.get_event_loop()
        deadline = loop.time() + timeout
        while loop.time() < deadline:
            for i, message in enumerate(self.inbox):
                if message.get("type") == msg_type:
                    return self.inbox.pop(i)
            await asyncio.sleep(0.005)
        raise TimeoutError(msg_type)

    async def close(self) -> None:
        if self.task:
            self.task.cancel()
        if self.ws:
            await self.ws.close()


async def bench_ping(port: int, clients: int, messages: int) -> float:
    benches = []
    for i in range(clients):
        b = Bench(port, f"bench_ping_{port}_{i}")
        await b.connect()
        await b.auth()
        benches.append(b)
    for b in benches:
        b.inbox.clear()

    start = time.perf_counter()
    for b in benches:
        for _ in range(messages):
            await b.ws.send(json.dumps({"type": "ping"}))
    received = 0
    while received < clients * messages:
        received = sum(1 for b in benches for m in b.inbox if m.get("type") == "pong")
        await asyncio.sleep(0.005)
    elapsed = time.perf_counter() - start
    for b in benches:
        await b.close()
    return clients * messages / elapsed


async def bench_state(port: int, players: int, seconds: float) -> float:
    benches = []
    host = Bench(port, f"bench_host_{port}")
    await host.connect()
    await host.auth()
    await host.send(type="create_room", name="bench", settings={"game_mode": "sandbox"})
    room = (await host.wait("room_created"))["room_id"]
    benches.append(host)
    for i in range(players - 1):
        b = Bench(port, f"bench_p{i}_{port}")
        await b.connect()
        await b.auth()
        await b.send(type="join_room", room_id=room, password="")
        await b.wait("joined")
        benches.append(b)
    await host.send(type="start_game")
    await host.wait("game_started", timeout=8.0)
    for b in benches:
        b.inbox.clear()

    start = time.perf_counter()
    sent = 0
    while time.perf_counter() - start < seconds:
        for b in benches:
            await b.send(type="player_input", pos=[0.0, 50.0, 0.0], rot_x=0.0)
            sent += 1
        await asyncio.sleep(0.01)
    updates = sum(1 for b in benches for m in b.inbox
                  if m.get("type") == "state_update")
    elapsed = time.perf_counter() - start
    for b in benches:
        await b.close()
    return updates / elapsed


async def main() -> int:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 9890
    clients = int(sys.argv[2]) if len(sys.argv) > 2 else 20
    messages = int(sys.argv[3]) if len(sys.argv) > 3 else 300

    ping = await bench_ping(port, clients, messages)
    state = await bench_state(port, min(8, clients), 2.0)
    print(f"ping/pong   : {ping:9.0f} msg/s ({clients} clients x {messages})")
    print(f"state_update: {state:9.0f} msg/s broadcast (8 players)")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
