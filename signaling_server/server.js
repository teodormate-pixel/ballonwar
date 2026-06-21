const WebSocket = require('ws');
const bcrypt = require('bcryptjs');
const config = require('./config');
const db = require('./db');
const charactersLib = require('./characters');
const roomsLib = require('./rooms');
const gameLib = require('./game');

const clients = new Map();

function send(ws, data) {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(data));
  }
}

function broadcastToRoom(room, data, excludeWs = null) {
  const str = JSON.stringify(data);
  const sent = new Set();
  for (const [ws] of room.players) {
    if (ws !== excludeWs && ws.readyState === WebSocket.OPEN) {
      ws.send(str);
      sent.add(ws);
    }
  }
  if (!sent.has(room.hostWs) && room.hostWs !== excludeWs && room.hostWs.readyState === WebSocket.OPEN) {
    room.hostWs.send(str);
  }
}

function getPlayerData(ws) {
  return clients.get(ws) || null;
}

async function handleMessage(ws, raw) {
  let msg;
  try {
    msg = JSON.parse(raw);
  } catch {
    return;
  }

  if (msg.type === 'ping') {
    send(ws, { type: 'pong' });
    return;
  }

  const client = getPlayerData(ws);

  if (msg.type === 'auth') {
    return handleAuth(ws, msg);
  }

  if (msg.type === 'register_user') {
    return handleRegisterUser(ws, msg);
  }

  if (!client) {
    send(ws, { type: 'error', message: 'Not authenticated' });
    return;
  }

  switch (msg.type) {
    case 'create_room':
      return handleCreateRoom(ws, client, msg);
    case 'join_room':
      return handleJoinRoom(ws, client, msg);
    case 'leave_room':
      return handleLeaveRoom(ws, client);
    case 'list_rooms':
      return handleListRooms(ws);
    case 'player_ready':
      return handlePlayerReady(ws, client, msg);
    case 'start_game':
      return handleStartGame(ws, client);
    case 'player_input':
      return handlePlayerInput(ws, client, msg);
    case 'terrain_modify':
      return handleTerrainModify(ws, client, msg);
    case 'chat':
      return handleChat(ws, client, msg);
    case 'save_data':
      return handleSaveData(ws, client, msg);
    case 'load_data':
      return handleLoadData(ws, client);
    case 'delete_account':
      return handleDeleteAccount(ws, client);
    default:
      send(ws, { type: 'error', message: `Unknown message type: ${msg.type}` });
  }
}

async function handleAuth(ws, msg) {
  const { username, password } = msg;
  if (!username || !password) {
    send(ws, { type: 'auth_error', message: 'Username and password required' });
    return;
  }

  try {
    let user = await db.findUserByUsername(username);

    if (user) {
      const match = await bcrypt.compare(password, user.password_hash);
      if (!match) {
        send(ws, { type: 'auth_error', message: 'Wrong password' });
        return;
      }
      await db.updateLastLogin(user.id);
    } else {
      const hash = await bcrypt.hash(password, config.bcryptRounds);
      const newId = await db.createUser(username, hash);
      user = { id: newId, username };
    }

    clients.set(ws, { playerId: user.id, username, roomId: null });
    send(ws, {
      type: 'auth_ok',
      player_id: user.id,
      username: user.username,
      game_modes: config.gameModes,
    });
    console.log(`Auth OK: ${user.username} (id=${user.id})`);
  } catch (err) {
    console.error('Auth error:', err);
    send(ws, { type: 'auth_error', message: 'Server error' });
  }
}

async function handleCreateRoom(ws, client, msg) {
  const existing = roomsLib.findRoomByWs(ws);
  if (existing) {
    send(ws, { type: 'error', message: 'Already in a room' });
    return;
  }

  const room = roomsLib.createRoom(
    ws, client.playerId, client.username,
    msg.name, msg.password, msg.settings, msg.seed
  );
  client.roomId = room.id;

  roomsLib.addPlayerToRoom(room, ws, client.playerId, client.username);
  const hostPlayer = room.players.get(ws);
  hostPlayer.characterId = 1;

  try { await db.saveRoom(room); } catch (err) { console.error('DB saveRoom error:', err.message); }

  send(ws, {
    type: 'room_created',
    room_id: room.id,
    player_id: client.playerId,
    settings: room.settings,
    players: [
      { id: client.playerId, name: client.username, characterId: 1 },
    ],
  });
}

async function handleJoinRoom(ws, client, msg) {
  const existing = roomsLib.findRoomByWs(ws);
  if (existing) {
    send(ws, { type: 'error', message: 'Already in a room' });
    return;
  }

  const room = roomsLib.getRoom(msg.room_id);
  if (!room) {
    send(ws, { type: 'error', message: 'Room not found' });
    return;
  }
  if (room.status !== 'lobby') {
    send(ws, { type: 'error', message: 'Game already started' });
    return;
  }
  if (room.password && msg.password !== room.password) {
    send(ws, { type: 'error', message: 'Wrong password' });
    return;
  }
  if (room.players.size >= room.settings.max_players) {
    send(ws, { type: 'error', message: 'Room is full' });
    return;
  }

  client.roomId = room.id;
  roomsLib.addPlayerToRoom(room, ws, client.playerId, client.username);
  const newPlayer = room.players.get(ws);

  const playersList = [{ id: client.playerId, name: client.username, characterId: null }];
  for (const [pws, p] of room.players) {
    if (pws !== ws) {
      playersList.push({ id: p.id, name: p.name, characterId: p.characterId });
    }
  }

  send(ws, {
    type: 'joined',
    room_id: room.id,
    player_id: client.playerId,
    players: playersList,
    settings: room.settings,
    seed: room.seed,
  });

  broadcastToRoom(room, {
    type: 'player_joined',
    player_id: client.playerId,
    name: client.username,
  }, ws);

  console.log(`${client.username} joined room ${room.id}`);
}

async function handleLeaveRoom(ws, client) {
  const room = roomsLib.findRoomByWs(ws);
  if (!room) return;

  client.roomId = null;

  if (ws === room.hostWs) {
    broadcastToRoom(room, { type: 'room_closed', message: 'Host left' });
    await db.closeRoom(room.id);
    roomsLib.deleteRoom(room.id);
    console.log(`Room ${room.id} closed (host left)`);
    return;
  }

  const player = roomsLib.removePlayerFromRoom(room, ws);
  if (player) {
    broadcastToRoom(room, { type: 'player_left', player_id: player.id });
    console.log(`${player.name} left room ${room.id}`);

    if (room.players.size === 0) {
      await db.closeRoom(room.id);
      roomsLib.deleteRoom(room.id);
      console.log(`Room ${room.id} empty -> deleted`);
    }
  }
}

function handleListRooms(ws) {
  send(ws, { type: 'room_list', rooms: roomsLib.getRoomList() });
}

function handlePlayerReady(ws, client, msg) {
  const room = roomsLib.findRoomByWs(ws);
  if (!room) {
    send(ws, { type: 'error', message: 'Not in a room' });
    return;
  }

  const charId = msg.character_id || 1;
  const character = charactersLib.getCharacterById(charId);
  if (!character) {
    send(ws, { type: 'error', message: 'Invalid character' });
    return;
  }

  const player = room.players.get(ws);
  if (player) {
    player.characterId = charId;
    player.ready = true;
    player.hp = character.base_health;
  }

  broadcastToRoom(room, {
    type: 'player_ready',
    player_id: client.playerId,
    character_id: charId,
    name: client.username,
  });
}

function handleStartGame(ws, client) {
  const room = roomsLib.findRoomByWs(ws);
  if (!room) {
    send(ws, { type: 'error', message: 'Not in a room' });
    return;
  }
  if (ws !== room.hostWs) {
    send(ws, { type: 'error', message: 'Only host can start' });
    return;
  }
  if (room.players.size < 1) {
    send(ws, { type: 'error', message: 'Need at least 1 other player' });
    return;
  }

  let spawnIndex = 0;
  for (const [pws, player] of room.players) {
    const angle = (spawnIndex / room.players.size) * Math.PI * 2;
    player.x = Math.cos(angle) * 10;
    player.z = Math.sin(angle) * 10;
    player.y = 50;
    player._velY = 0;
    player._onGround = false;
    if (!player.characterId) player.characterId = 1;
    spawnIndex++;
  }

  broadcastToRoom(room, {
    type: 'game_starting',
    countdown: 3,
  });

  setTimeout(() => {
    room.status = 'playing';
    broadcastToRoom(room, {
      type: 'game_started',
      seed: room.seed,
      terrain_modifications: room.terrainModifications,
    });
    console.log(`Game started in room ${room.id}`);
  }, 3000);
}

function handlePlayerInput(ws, client, msg) {
  const room = roomsLib.findRoomByWs(ws);
  if (!room || room.status !== 'playing') return;

  const player = room.players.get(ws);
  if (!player || !player.alive) return;

  player._pendingInput = {
    keys: msg.keys || {},
    rot_x: msg.rot_x,
    actions: msg.actions || {},
  };

  const pos = msg.pos;
  if (Array.isArray(pos) && pos.length === 3) {
    const dx = pos[0] - player.x;
    const dz = pos[2] - player.z;
    const dy = pos[1] - player.y;
    const dist = Math.sqrt(dx * dx + dz * dz);
    const MAX_MOVE = 2.0;
    if (dist <= MAX_MOVE) {
      player.x = pos[0];
      player.y = pos[1];
      player.z = pos[2];
    } else {
      const ratio = MAX_MOVE / dist;
      player.x += dx * ratio;
      player.z += dz * ratio;
      player.y += dy * ratio;
    }
  }

  if (msg.actions?.weapon !== undefined) {
    player.weapon = msg.actions.weapon;
  }

  if (msg.rot_x !== undefined) player.rot = msg.rot_x;
}

async function handleTerrainModify(ws, client, msg) {
  const room = roomsLib.findRoomByWs(ws);
  if (!room || room.status !== 'playing') return;

  const pos = msg.pos;
  if (!Array.isArray(pos) || pos.length !== 3) return;

  const blockType = msg.block_type || 0;
  const actionType = msg.action_type || 'dig';

  room.terrainModifications.push({ pos, blockType, actionType });

  try {
    await db.saveTerrainModification(room.id, pos, blockType, actionType);
  } catch (err) {
    console.error('DB terrain save error:', err);
  }

  broadcastToRoom(room, {
    type: 'terrain_change',
    player_id: client.playerId,
    pos,
    block_type: blockType,
    action_type: actionType,
  });
}

function handleChat(ws, client, msg) {
  const room = roomsLib.findRoomByWs(ws);
  if (!room) return;
  if (!room.settings.allow_chat) return;

  broadcastToRoom(room, {
    type: 'chat',
    player_id: client.playerId,
    name: client.username,
    message: msg.message,
  });
}

async function handleRegisterUser(ws, msg) {
  const { username, password } = msg;
  if (!username || !password) {
    send(ws, { type: 'register_result', success: false, message: 'Username and password required' });
    return;
  }
  try {
    const existing = await db.findUserByUsername(username);
    if (existing) {
      send(ws, { type: 'register_result', success: false, message: 'Username already exists' });
      return;
    }
    const hash = await bcrypt.hash(password, config.bcryptRounds);
    await db.createUser(username, hash);
    send(ws, { type: 'register_result', success: true, message: 'Account created' });
  } catch (err) {
    console.error('Register error:', err);
    send(ws, { type: 'register_result', success: false, message: 'Server error' });
  }
}

async function handleSaveData(ws, client, msg) {
  const data = msg.data || {};
  try {
    await db.savePlayerData(client.playerId, data);
    send(ws, { type: 'save_data_result', success: true });
  } catch (err) {
    console.error('Save data error:', err);
    send(ws, { type: 'save_data_result', success: false, message: 'Server error' });
  }
}

async function handleLoadData(ws, client) {
  try {
    const data = await db.loadPlayerData(client.playerId);
    send(ws, { type: 'load_data_result', success: true, data: data || {} });
  } catch (err) {
    console.error('Load data error:', err);
    send(ws, { type: 'load_data_result', success: false, message: 'Server error' });
  }
}

async function handleDeleteAccount(ws, client) {
  try {
    await db.deleteUser(client.playerId);
    const room = roomsLib.findRoomByWs(ws);
    if (room) handleLeaveRoom(ws, client);
    clients.delete(ws);
    ws.close();
    console.log(`Account deleted: ${client.username} (id=${client.playerId})`);
  } catch (err) {
    console.error('Delete account error:', err);
    send(ws, { type: 'delete_account_result', success: false, message: 'Server error' });
  }
}

function handleDisconnect(ws) {
  const client = clients.get(ws);
  if (client) {
    handleLeaveRoom(ws, client);
    clients.delete(ws);
    console.log(`Client ${client.username || '?'} disconnected`);
  }
}

async function main() {
  try {
    await db.initSchema();
    console.log('Database connected and schema ready');
  } catch (err) {
    console.error('Database init failed:', err.message);
    console.log('Starting without database (in-memory only)');
  }

  const server = new WebSocket.Server({ port: config.port });
  console.log(`Balloon War server on port ${config.port}`);

  server.on('connection', (ws) => {
    ws.on('message', (raw) => handleMessage(ws, raw));
    ws.on('close', () => handleDisconnect(ws));
    ws.on('error', () => handleDisconnect(ws));
  });

  gameLib.startGameLoop(server);
}

main();
