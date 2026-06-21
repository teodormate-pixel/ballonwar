# Balloon War — VPS Server Architecture

## Stack
- **Server**: Node.js + WebSocket (`ws`) pe Ubuntu Server 24.04 LTS
- **Database**: MySQL (deja instalat pe VPS)
- **Client**: Godot 4.6 (built-in WebSocket, fără pluginuri)
- **Deploy**: SCP/rsync local → VPS, fără git pe VPS

## Server Files (`signaling_server/`)
```
signaling_server/
├── package.json
├── server.js          ← Main entry: WebSocket + routing
├── db.js              ← MySQL pool + queries
├── rooms.js           ← Room lifecycle (create/join/configure/start)
├── game.js            ← Game loop (20Hz), state management, validation
├── characters.js      ← Character definitions, abilities, stats
└── config.js          ← Environment config + defaults
```

## Database (MySQL) — Schema

```sql
CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP NULL
);

CREATE TABLE characters (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    model_path VARCHAR(255) NOT NULL,        -- res:// path in Godot
    abilities JSON,                           -- [{name, desc, cooldown, effect}]
    base_speed FLOAT DEFAULT 10.0,
    base_health INT DEFAULT 100,
    thumbnail VARCHAR(255) DEFAULT ''
);

CREATE TABLE player_characters (
    user_id INT NOT NULL,
    character_id INT NOT NULL,
    unlocked BOOLEAN DEFAULT TRUE,
    PRIMARY KEY (user_id, character_id),
    FOREIGN KEY (user_id) REFERENCES users(id),
    FOREIGN KEY (character_id) REFERENCES characters(id)
);

CREATE TABLE rooms (
    id VARCHAR(6) PRIMARY KEY,               -- Room code (ex: "IL5N")
    name VARCHAR(50) NOT NULL,
    host_id INT NOT NULL,
    password VARCHAR(50) DEFAULT NULL,
    settings JSON NOT NULL,                   -- {seed, max_players, terrain_type, ...}
    status ENUM('lobby','playing','ended') DEFAULT 'lobby',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (host_id) REFERENCES users(id)
);

CREATE TABLE game_stats (
    id INT AUTO_INCREMENT PRIMARY KEY,
    room_id VARCHAR(6) NOT NULL,
    player_id INT NOT NULL,
    character_id INT DEFAULT NULL,
    kills INT DEFAULT 0,
    deaths INT DEFAULT 0,
    score INT DEFAULT 0,
    duration INT DEFAULT 0,                  -- seconds
    FOREIGN KEY (room_id) REFERENCES rooms(id),
    FOREIGN KEY (player_id) REFERENCES users(id)
);

CREATE TABLE terrain_modifications (
    id INT AUTO_INCREMENT PRIMARY KEY,
    room_id VARCHAR(6) NOT NULL,
    pos_x INT NOT NULL,
    pos_y INT NOT NULL,
    pos_z INT NOT NULL,
    block_type INT NOT NULL,                 -- 0=air(dug), 1=dirt, 2=stone, etc.
    action_type ENUM('dig','place') NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_room (room_id)
);
```

## Protocol — Client ↔ Server

### Flow
```
[Client]                    [Server]
   |                            |
   |--- auth ------------------>|  {username, password}
   |<-- auth_ok / auth_error ---|
   |                            |
   |--- create_room ----------->|  {name, password?, settings{seed?, max_players, ...}}
   |<-- room_created -----------|  {room_id, player_id, settings}
   |                            |
   |  — sau —                   |
   |                            |
   |--- join_room ------------->|  {room_id, password?}
   |<-- joined -----------------|  {room_id, player_id, players[], settings, seed}
   |                            |
   |--- player_ready ---------->|  {character_id}
   |<-- player_ready -----------|  {player_id, character_id} (broadcast)
   |                            |
   |  [Host apasă Start]        |
   |--- start_game ------------>|
   |<-- game_starting ----------|  {countdown: 5}
   |<-- game_started -----------|  {seed, terrain_mods[]}
   |                            |
   |  [Game loop 20Hz]          |
   |--- player_input ---------->|  {seq, keys{forward,back,left,right,jump},
   |                            |     rot_x, rot_y, actions{fire, interact, weapon}}
   |<-- state_update -----------|  {tick, players[{id,pos,rot,hp,weapon,alive,char_id}]}
   |                            |
   |  [La modificare teren]     |
   |--- terrain_modify -------->|  {pos:[x,y,z], type:"dig"/"place", block_type?}
   |<-- terrain_change ---------|  {player_id, pos, type, block_type} (broadcast)
   |                            |
   |--- chat ------------------>|  {message}
   |<-- chat -------------------|  {player_id, message} (broadcast)
   |                            |
   |<-- player_joined ----------|  {player_id, name} (broadcast)
   |<-- player_left ------------|  {player_id} (broadcast)
   |<-- game_over --------------|  {winner_id, stats[]}
```

### Room Settings (JSON trimis la `create_room`)
```json
{
    "seed": 12345,
    "max_players": 8,
    "terrain_type": "default",
    "game_mode": "free_for_all",
    "time_limit": 600,
    "kill_limit": 20,
    "allow_chat": true
}
```

## Character System

Characters definiți în `characters.js`, lista trimisă la login:

```json
{
    "id": 1,
    "name": "Bombadier",
    "model": "res://characters/bombadier/bombadier.tscn",
    "thumbnail": "res://characters/bombadier/thumb.png",
    "base_speed": 10.0,
    "base_health": 100,
    "abilities": [
        {"name": "Triple Shot", "desc": "Trage 3 gloanțe odată", "cooldown": 5},
        {"name": "Shield", "desc": "Scut temporar 3s", "cooldown": 10}
    ]
}
```

## Key Design Decisions

1. **Client face mișcarea, serverul validează** — serverul NU simulează fizică Godot. Clientul trimite poziția rezultată (ca acum), serverul verifică: viteză plauzibilă, distanță rezonabilă de ultima poziție. Dacă depășește limitele, respinge mișcarea.

2. **Teren generat procedural din seed** — Serverul stochează DOAR modificările (`terrain_modifications`). Terenul inițial se generează pe fiecare client din seed.

3. **State update la 20Hz** — Ca acum, dar prin server în loc de relay

4. **MySQL pentru persistență** — utilizatori, statistici, istoric camere

5. **Configurare prin environment variables** — `DB_HOST`, `DB_USER`, `DB_PASS`, `DB_NAME`, `PORT`

## File Transfer to VPS (fără git)

Opțiuni:
```bash
# 1. SCP (dacă ai SSH)
scp -r signaling_server/* user@vps:/path/to/game/

# 2. rsync (mai rapid, doar fișiere modificate)
rsync -avz --delete signaling_server/ user@vps:/path/to/game/

# 3. ZIP + wget pe VPS
zip -r server.zip signaling_server/
# Upload server.zip la un URL accesibil, apoi pe VPS:
# wget https://.../server.zip && unzip server.zip && cd server && npm install

# 4. SFTP (FileZilla, WinSCP) → drag & drop folderul
```

## Running on VPS

```bash
cd /path/to/game
npm install
export DB_HOST=localhost DB_USER=ballon DB_PASS=secret DB_NAME=ballon_war PORT=8765
node server.js
```

Pentru producție: instalează `pm2` (npm global fără admin: `npm install pm2`) sau rulează ca systemd service.
