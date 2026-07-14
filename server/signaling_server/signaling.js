const WebSocket = require("ws");
const PORT = process.env.PORT || 8765;

const server = new WebSocket.Server({ port: PORT });
console.log("Signaling server on port", PORT);

// room_id -> { host: ws, clients: [{ws, peer_id}], name, created, has_password }
const rooms = {};

function genId() {
  return Math.random().toString(36).substring(2, 6).toUpperCase();
}

server.on("connection", (ws) => {
  ws.on("message", (raw) => {
    let msg;
    try { msg = JSON.parse(raw); } catch { return; }

    // Keepalive
    if (msg.type === "ping") {
      ws.send(JSON.stringify({ type: "pong" }));
      return;
    }

    switch (msg.type) {
      case "create_room": {
        let room_id;
        do { room_id = genId(); } while (rooms[room_id]);
        rooms[room_id] = {
          host: ws,
          clients: [],
          created: Date.now(),
          name: msg.name || "Unnamed",
          password: msg.password || null,
          has_password: !!msg.password
        };
        ws.room_id = room_id;
        ws.is_host = true;
        ws.peer_id = 1;
        ws.send(JSON.stringify({ type: "room_created", room_id, peer_id: 1 }));
        console.log("Room", room_id, "created:", rooms[room_id].name, "(peer 1)", rooms[room_id].has_password ? "(password)" : "(no password)");
        break;
      }

      case "join_room": {
        const room = rooms[msg.room_id];
        if (!room) {
          ws.send(JSON.stringify({ type: "error", message: "Room not found" }));
          return;
        }
        if (room.password && msg.password !== room.password) {
          ws.send(JSON.stringify({ type: "error", message: "Wrong password" }));
          return;
        }
        const pid = room.clients.length + 2; // host=1, clients start at 2
        ws.room_id = msg.room_id;
        ws.is_host = false;
        ws.peer_id = pid;
        room.clients.push({ ws, peer_id: pid });

        ws.send(JSON.stringify({ type: "joined", peer_id: pid }));
        room.host.send(JSON.stringify({ type: "peer_joined", peer_id: pid }));
        // Tell client about host
        ws.send(JSON.stringify({ type: "peer_connected", peer_id: 1 }));
        // Tell host about client
        room.host.send(JSON.stringify({ type: "peer_connected", peer_id: pid }));
        // Send world seed to late-joining client
        if (room.world_seed) {
          ws.send(JSON.stringify({ type: "world_seed", seed: room.world_seed }));
        }
        console.log("Peer", pid, "joined room", msg.room_id);
        break;
      }

      // Forward data to a specific peer in the room
      case "send_to_peer": {
        const room = rooms[msg.room_id];
        if (!room) return;
        const target = msg.peer_id;
        const payload = msg.payload;
        payload._from = ws.peer_id;
        payload.type = "rpc_result";
        const data = JSON.stringify(payload);
        if (target === 1) {
          if (room.host.readyState === WebSocket.OPEN) room.host.send(data);
        } else {
          for (const c of room.clients) {
            if (c.peer_id === target && c.ws.readyState === WebSocket.OPEN) {
              c.ws.send(data);
              break;
            }
          }
        }
        break;
      }

      // Broadcast data to all OTHER peers in the room (exclude sender)
      case "broadcast_to_room": {
        const room = rooms[msg.room_id];
        if (!room) {
          console.log("broadcast_to_room: room NOT FOUND for", msg.room_id);
          return;
        }
        const payload = msg.payload;
        payload._from = ws.peer_id;
        payload.type = "rpc_result";
        const data = JSON.stringify(payload);
        let sent = 0;
        // Send to host (if not sender)
        if (ws !== room.host) {
          if (room.host.readyState === WebSocket.OPEN) {
            room.host.send(data);
            sent++;
          } else {
            console.log("broadcast_to_room: host ws not OPEN, state=", room.host.readyState);
          }
        }
        // Send to all clients (except sender)
        for (const c of room.clients) {
          if (c.ws !== ws) {
            if (c.ws.readyState === WebSocket.OPEN) {
              c.ws.send(data);
              sent++;
            } else {
              console.log("broadcast_to_room: client ws not OPEN, pid=", c.peer_id, "state=", c.ws.readyState);
            }
          }
        }
        console.log("broadcast_to_room: sent", sent, "peers (from", ws.peer_id, ")");
        break;
      }

      case "list_rooms": {
        const list = Object.entries(rooms).map(([id, room]) => ({
          room_id: id,
          name: room.name,
          has_password: room.has_password,
          player_count: 1 + room.clients.filter(c => c.ws.readyState === WebSocket.OPEN).length,
          max_players: 8
        }));
        ws.send(JSON.stringify({ type: "room_list", rooms: list }));
        break;
      }

      case "world_seed_update": {
        const room = rooms[msg.room_id];
        if (room) {
          room.world_seed = msg.seed;
          const data = JSON.stringify({ type: "world_seed", seed: msg.seed });
          for (const c of room.clients) {
            if (c.ws.readyState === WebSocket.OPEN) c.ws.send(data);
          }
        }
        break;
      }
    }
  });

  ws.on("close", () => {
    const room_id = ws.room_id;
    if (!room_id) return;
    const room = rooms[room_id];
    if (!room) return;

    if (ws.is_host) {
      // Host left -> notify clients and close room
      for (const c of room.clients) {
        if (c.ws.readyState === WebSocket.OPEN) {
          c.ws.send(JSON.stringify({ type: "room_closed" }));
        }
      }
      delete rooms[room_id];
      console.log("Room", room_id, "closed (host left)");
    } else {
      // Client left
      const idx = room.clients.findIndex(c => c.ws === ws);
      if (idx >= 0) {
        const pid = room.clients[idx].peer_id;
        room.clients.splice(idx, 1);
        if (room.host.readyState === WebSocket.OPEN) {
          room.host.send(JSON.stringify({ type: "peer_disconnected", peer_id: pid }));
        }
      }
      if (room.clients.length === 0) {
        delete rooms[room_id];
        console.log("Room", room_id, "empty -> deleted");
      }
    }
  });
});

// Cleanup stale rooms every 5 min
setInterval(() => {
  const now = Date.now();
  for (const [id, room] of Object.entries(rooms)) {
    if (now - room.created > 30 * 60 * 1000 && room.clients.length === 0) {
      delete rooms[id];
      console.log("Room", id, "expired");
    }
  }
}, 300000);
