# Balloon War — Agent Instructions

## Stack
- **Godot 4.7** — main gameplay scene `lume.tscn`; entry scene `fundal_i_meniu_principal.tscn`
- **Server**: Node.js (`ws` + `mysql2` + `bcryptjs`) in `signaling_server/` — deployed to VPS `host1.subscriberspal.com:8765`
- **DB**: MySQL `teodor_ballon_war` user `teodor_ballon`
- **Physics**: Jolt Physics (`project.godot: physics/3d/physics_engine`)

## Server Deploy (no git on VPS, no admin)
```bash
# transfer
rsync -avz --delete signaling_server/ user@vps:~/playground/Balloon-WAR/
# run
cd ~/playground/Balloon-WAR && npm install && node server.js
```
Server on port 8765, configured via env vars: `DB_HOST`, `DB_USER`, `DB_PASS`, `DB_NAME`, `PORT`.

## Networking
Client-server via raw WebSocket (`WebSocketPeer`), NOT Godot RPC. All networking through `NetworkManager.gd` autoload — signals for inbound, method calls for outbound. Server URL: `ws://62.171.162.154:8765`. Auth on connect; player input sent at 20Hz via `send_input()`.

Key signals on NetworkManager: `auth_ok`, `room_created`, `joined`, `game_started`, `state_update`, `terrain_change`, `chat`.

LAN discovery on UDP port 8913.

## Autoloads
`NetworkManager`, `GestiuneJoc`, `WorldConfig`, `CharacterData`, `MusicManager`, `GlobalSettings`, `DevConsole`, `_mcp_game_helper`.

## Active Terrain
`voxel_world_generator.gd` (extends `VoxelLodTerrain`) with inner `SDFTerrainGenerator` class — current active generator. Player spawns via `_try_spawn_above_terrain()` + `register_frozen_player()`.

Multiple legacy generators exist (`voxel_geometry_generator.gd`, `CostumVoxelGenerator.gd`, `SmoothTerrainGenerator.gd`, `WorldTerrainGenerator.gd`) — do not edit them unless explicitly asked.

## Player / Controls (`starter_player.gd`)
- **Dig mode**: KEY M (mod: `SAPA`), **Build mode**: KEY Z (mod: `CONSTRUIESTE`), **Combat**: KEY X
- **Dig shape**: toggle Cube/Sphere with KEY B
- **Weapon**: toggle crossbow/sword KEY Q
- **Camera**: C (first/third), F (freecam), Shift (shoulder lock), scrollwheel zoom
- **Inventory**: KEY I (toggle), keys 1-7 hotbar
- **Structure build**: KEY V cycles modes, T cycles blueprints
- **Block types**: `AIR=0, GRASS=1, DIRT=2, STONE=3, COAL=4, IRON=5, COPPER=6, GOLD=7, DIAMOND=8, WOOD=9, LEAF=10`
- Block materials are **unshaded colors** (`StandardMaterial3D.SHADING_MODE_UNSHADED`)

## Key Conventions
- Zero external Godot plugins (only built-in addons: `godot_ai`, `dev-console`, `flowkit`)
- No WebRTC
- Line endings: Linux (`\n`)
- Windows export target (x86_64, D3D12, S3TC/BPTC)
