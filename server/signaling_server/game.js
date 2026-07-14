const config = require('./config');
const roomsLib = require('./rooms');
const db = require('./db');

const MAX_SPEED = 15.0;
const MAX_SPEED_PER_TICK = MAX_SPEED / config.tickRate;
const GRAVITY = -25.0;
const TICK_DT = 1.0 / config.tickRate;

function updatePlayer(player, input) {
  // Client-authoritative position — server no longer simulates movement
  // Rotation from client input
  if (input.rot_x !== undefined) player.rot = input.rot_x;
}

function serializePlayers(room) {
  const list = [];
  for (const [ws, p] of room.players) {
    list.push({
      id: p.id,
      name: p.name,
      pos: [Math.round(p.x * 100) / 100, Math.round(p.y * 100) / 100, Math.round(p.z * 100) / 100],
      rot: p.rot,
      hp: p.hp,
      weapon: p.weapon,
      alive: p.alive,
      characterId: p.characterId,
      kills: p.kills,
      deaths: p.deaths,
    });
  }
  return list;
}

function startGameLoop(server) {
  console.log(`Game loop started at ${config.tickRate}Hz`);

  setInterval(() => {
    for (const room of roomsLib.rooms.values()) {
      if (room.status !== 'playing') continue;

      for (const [ws, player] of room.players) {
        const input = player._pendingInput || { keys: {}, actions: {} };
        player._pendingInput = null;
        updatePlayer(player, input);
      }

      const state = {
        type: 'state_update',
        tick: Date.now(),
        players: serializePlayers(room),
      };
      const data = JSON.stringify(state);

      const sent = new Set();
      for (const [ws] of room.players) {
        if (ws.readyState === 1) { ws.send(data); sent.add(ws); }
      }
      if (!sent.has(room.hostWs) && room.hostWs.readyState === 1) {
        room.hostWs.send(data);
      }
    }
  }, config.tickInterval);

  setInterval(() => {
    const now = Date.now();
    for (const [id, room] of roomsLib.rooms) {
      if (room.status === 'lobby' && now - room.created > 3600000) {
        if (room.players.size === 0) {
          roomsLib.deleteRoom(id);
          console.log(`Room ${id} expired`);
        }
      }
    }
  }, 300000);
}

module.exports = { startGameLoop, serializePlayers };
