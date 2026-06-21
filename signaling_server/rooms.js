const uuid = require('./uuid');
const config = require('./config');

const rooms = new Map();

function createRoomId() {
  let id;
  do {
    id = uuid.generate(config.roomCodeLength);
  } while (rooms.has(id));
  return id;
}

function createRoom(ws, hostId, hostName, name, password, settings, seed) {
  const id = createRoomId();
  const validModes = config.gameModes.map(m => m.id);
  const gameMode = validModes.includes(settings?.game_mode) ? settings.game_mode : 'free_for_all';
  const room = {
    id,
    name: name || `${hostName}'s Game`,
    hostWs: ws,
    hostId,
    password: password || null,
    settings: {
      seed: seed || Math.floor(Math.random() * 2147483647),
      max_players: settings?.max_players || config.maxPlayersPerRoom,
      terrain_type: settings?.terrain_type || 'default',
      game_mode: gameMode,
      time_limit: settings?.time_limit || 600,
      kill_limit: settings?.kill_limit || 20,
      allow_chat: settings?.allow_chat !== false,
    },
    seed: seed || Math.floor(Math.random() * 2147483647),
    status: 'lobby',
    players: new Map(),
    terrainModifications: [],
    created: Date.now(),
  };
  rooms.set(id, room);
  console.log(`Room ${id} created by ${hostName}`);
  return room;
}

function addPlayerToRoom(room, ws, playerId, playerName) {
  room.players.set(ws, {
    id: playerId,
    name: playerName,
    x: 0, y: 50, z: 0,
    rot: 0,
    hp: 100,
    weapon: 0,
    alive: true,
    characterId: null,
    ready: false,
    _pendingInput: null,
    kills: 0,
    deaths: 0,
    score: 0,
  });
}

function removePlayerFromRoom(room, ws) {
  const player = room.players.get(ws);
  if (!player) return null;
  room.players.delete(ws);
  return player;
}

function getRoom(id) {
  return rooms.get(id) || null;
}

function deleteRoom(id) {
  rooms.delete(id);
}

function getRoomList() {
  const list = [];
  for (const [id, room] of rooms) {
    if (room.status === 'lobby') {
      const gm = config.gameModes.find(m => m.id === room.settings.game_mode);
      list.push({
        room_id: id,
        name: room.name,
        player_count: room.players.size,
        max_players: room.settings.max_players,
        has_password: !!room.password,
        terrain_type: room.settings.terrain_type,
        game_mode: room.settings.game_mode,
        game_mode_name: gm ? gm.name : room.settings.game_mode,
      });
    }
  }
  return list;
}

function findRoomByWs(ws) {
  for (const room of rooms.values()) {
    if (room.hostWs === ws || room.players.has(ws)) return room;
  }
  return null;
}

module.exports = {
  createRoom,
  addPlayerToRoom,
  removePlayerFromRoom,
  getRoom,
  deleteRoom,
  getRoomList,
  findRoomByWs,
  rooms,
};
