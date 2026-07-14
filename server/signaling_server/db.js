const mysql = require('mysql2/promise');
const config = require('./config');

let pool = null;
let isAvailable = false;

// In-memory fallback stores
const memUsers = [];
let memUserIdCounter = 1;

async function getPool() {
  if (!pool && isAvailable) {
    pool = mysql.createPool({
      host: config.db.host,
      user: config.db.user,
      password: config.db.password,
      database: config.db.database,
      waitForConnections: true,
      connectionLimit: 10,
    });
  }
  return pool;
}

async function initSchema() {
  try {
    const testPool = mysql.createPool({
      host: config.db.host,
      user: config.db.user,
      password: config.db.password,
      database: config.db.database,
      waitForConnections: true,
      connectionLimit: 2,
    });
    await testPool.execute('SELECT 1');
    pool = testPool;
    isAvailable = true;

    await pool.execute(`
      CREATE TABLE IF NOT EXISTS users (
        id INT AUTO_INCREMENT PRIMARY KEY,
        username VARCHAR(50) UNIQUE NOT NULL,
        password_hash VARCHAR(255) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        last_login TIMESTAMP NULL
      )
    `);
    await pool.execute(`
      CREATE TABLE IF NOT EXISTS characters (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(50) NOT NULL,
        model_path VARCHAR(255) NOT NULL,
        abilities JSON NOT NULL,
        base_speed FLOAT DEFAULT 10.0,
        base_health INT DEFAULT 100,
        thumbnail VARCHAR(255) DEFAULT ''
      )
    `);
    await pool.execute(`
      CREATE TABLE IF NOT EXISTS player_characters (
        user_id INT NOT NULL,
        character_id INT NOT NULL,
        unlocked BOOLEAN DEFAULT TRUE,
        PRIMARY KEY (user_id, character_id),
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
        FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE
      )
    `);
    await pool.execute(`
      CREATE TABLE IF NOT EXISTS rooms (
        id VARCHAR(6) PRIMARY KEY,
        name VARCHAR(50) NOT NULL,
        host_id INT NOT NULL,
        password VARCHAR(50) DEFAULT NULL,
        settings JSON NOT NULL,
        status ENUM('lobby','playing','ended') DEFAULT 'lobby',
        seed BIGINT DEFAULT 0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (host_id) REFERENCES users(id) ON DELETE CASCADE
      )
    `);
    await pool.execute(`
      CREATE TABLE IF NOT EXISTS game_stats (
        id INT AUTO_INCREMENT PRIMARY KEY,
        room_id VARCHAR(6) NOT NULL,
        player_id INT NOT NULL,
        character_id INT DEFAULT NULL,
        kills INT DEFAULT 0,
        deaths INT DEFAULT 0,
        score INT DEFAULT 0,
        duration INT DEFAULT 0,
        FOREIGN KEY (room_id) REFERENCES rooms(id) ON DELETE CASCADE,
        FOREIGN KEY (player_id) REFERENCES users(id) ON DELETE CASCADE
      )
    `);
    await pool.execute(`
      CREATE TABLE IF NOT EXISTS terrain_modifications (
        id INT AUTO_INCREMENT PRIMARY KEY,
        room_id VARCHAR(6) NOT NULL,
        pos_x INT NOT NULL,
        pos_y INT NOT NULL,
        pos_z INT NOT NULL,
        block_type INT NOT NULL,
        action_type ENUM('dig','place') NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_room (room_id),
        FOREIGN KEY (room_id) REFERENCES rooms(id) ON DELETE CASCADE
      )
    `);
    await addPlayerDataColumn();
    try { await pool.execute('ALTER TABLE rooms MODIFY COLUMN seed BIGINT DEFAULT 0'); } catch (e) {}
    console.log('Schema initialized');
  } catch (err) {
    console.log('Database unavailable, using in-memory storage');
    isAvailable = false;
    pool = null;
  }
}

async function findUserByUsername(username) {
  if (isAvailable && pool) {
    const [rows] = await pool.execute('SELECT * FROM users WHERE username = ?', [username]);
    return rows[0] || null;
  }
  return memUsers.find((u) => u.username === username) || null;
}

async function createUser(username, passwordHash) {
  if (isAvailable && pool) {
    const [result] = await pool.execute(
      'INSERT INTO users (username, password_hash) VALUES (?, ?)',
      [username, passwordHash]
    );
    return result.insertId;
  }
  const id = memUserIdCounter++;
  memUsers.push({ id, username, password_hash: passwordHash });
  return id;
}

async function addPlayerDataColumn() {
  if (isAvailable && pool) {
    try {
      await pool.execute('ALTER TABLE users ADD COLUMN player_data JSON NULL AFTER password_hash');
    } catch (e) {
      // column already exists
    }
  }
}

async function savePlayerData(userId, data) {
  if (isAvailable && pool) {
    await pool.execute('UPDATE users SET player_data = ? WHERE id = ?', [JSON.stringify(data), userId]);
  }
  // in-memory is not supported for player_data
}

async function loadPlayerData(userId) {
  if (isAvailable && pool) {
    const [rows] = await pool.execute('SELECT player_data FROM users WHERE id = ?', [userId]);
    if (rows.length > 0 && rows[0].player_data) {
      const raw = rows[0].player_data;
      if (typeof raw === 'string') {
        try { return JSON.parse(raw); } catch { return {}; }
      }
      return raw;
    }
    return {};
  }
  return {};
}

async function deleteUser(userId) {
  if (isAvailable && pool) {
    await pool.execute('DELETE FROM users WHERE id = ?', [userId]);
  }
}

async function updateLastLogin(userId) {
  if (isAvailable && pool) {
    await pool.execute('UPDATE users SET last_login = NOW() WHERE id = ?', [userId]);
  }
}

async function saveRoom(room) {
  if (isAvailable && pool) {
    await pool.execute(
      `INSERT INTO rooms (id, name, host_id, password, settings, seed)
       VALUES (?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE status = VALUES(status)`,
      [room.id, room.name, room.hostId, room.password || null,
       JSON.stringify(room.settings), room.seed || 0]
    );
  }
}

async function closeRoom(roomId) {
  if (isAvailable && pool) {
    await pool.execute('DELETE FROM rooms WHERE id = ?', [roomId]);
  }
}

async function saveTerrainModification(roomId, pos, blockType, actionType) {
  if (isAvailable && pool) {
    await pool.execute(
      'INSERT INTO terrain_modifications (room_id, pos_x, pos_y, pos_z, block_type, action_type) VALUES (?, ?, ?, ?, ?, ?)',
      [roomId, pos[0], pos[1], pos[2], blockType, actionType]
    );
  }
}

async function getTerrainModifications(roomId) {
  if (isAvailable && pool) {
    const [rows] = await pool.execute(
      'SELECT pos_x, pos_y, pos_z, block_type, action_type FROM terrain_modifications WHERE room_id = ?',
      [roomId]
    );
    return rows;
  }
  return [];
}

module.exports = {
  initSchema,
  findUserByUsername,
  createUser,
  updateLastLogin,
  savePlayerData,
  loadPlayerData,
  deleteUser,
  saveRoom,
  closeRoom,
  saveTerrainModification,
  getTerrainModifications,
};
