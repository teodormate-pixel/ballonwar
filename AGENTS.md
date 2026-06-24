# Balloon War — VPS Architecture

## Stare
Tranziție de la relay WebSocket (HF Spaces) la **server autoritar pe VPS** (Ubuntu 24.04, Node.js + MySQL). Vezi `SERVER_ARCHITECTURE.md` pentru protocolul complet.

## Arhitectură Nouă
- **Server**: Node.js WebSocket (`ws` + `mysql2`) — rulează pe VPS (port 8765)
- **Client**: Godot 4.6 WebSocket direct — trimite input, primește stare autoritară
- **DB**: MySQL — users, characters, rooms, game_stats, terrain_modifications
- **Auth**: Prin MySQL (username + password_hash)
- **Conexiune**: `ws://vps:8765` (WS, nu WSS — pe VPS local)

## Structură Server (pe VPS: `~/playground/Balloon-WAR/`)
- `code/server.js` — main + WebSocket routing
- `code/db.js` — MySQL pool
- `code/rooms.js` — room lifecycle
- `code/game.js` — game loop 20Hz + stat
- `code/characters.js` — definiții personaje
- `code/config.js` — env vars
- `logs/` — server.log

## Stare Curentă
- ✅ **Deploy pe VPS** — serverul rulează pe `host1.subscriberspal.com:8765`
- ✅ **MySQL integrat** — `teodor_ballon_war` DB, user `teodor_ballon`
- Serverul VECHI `signaling.js` (relay) NU se mai folosește
- URL-ul HF Spaces mort
- **`server.js`** funcțional pe port 8765 — auth, camere, game loop 20Hz, terrain broadcast
- **`NetworkManager.gd`** rescris client-server direct — auto-auth pe connect, semnale tipate
- **5 game modes** în `config.js`: free_for_all, team_deathmatch, last_man_standing, capture_the_flag, balloon_hunt
- **Baloon Hunt**: jumate jucători baloane, jumate vânători (doar UI + settings, logica de joc de implementat)
- **Terrain sync** prin server — dig/place trimit `terrain_modify`, serverul broadcast `terrain_change`

## Constrângeri
- Zero pluginuri Godot externe
- Fără WebRTC
- Ubuntu 24.04 LTS (path-uri Linux, \n)
- Fără git pe VPS → `rsync`/`scp`
- MySQL db: `teodor_ballon_war`, user: `teodor_ballon`
- Server fără admin → npm packages locale, pm2 optional

## Memorie Persistentă (opencode-plugin-simple-memory)
- Plugin: `@knikolov/opencode-plugin-simple-memory` (clonat local `~/.opencode-memory-plugin/`)
- Config: `plugin: ["file:///home/teodor/.opencode-memory-plugin/index.ts"]` în `~/.config/opencode/opencode.json`
- Memoriile se salvează în `.opencode/memory/` ca fișiere `.logfmt` per zi
- Tooluri: `memory_remember`, `memory_recall`, `memory_update`, `memory_forget`, `memory_list`, `memory_context`
- Se încarcă automat la pornirea opencode

## Ce urmează
1. ~~Scrie `server.js` (WebSocket + game loop)~~ ✅
2. ~~Scrie `db.js` (MySQL pool + init schema)~~ ✅
3. ~~Scrie `rooms.js` + `game.js` + `characters.js`~~ ✅
4. ~~Rescrie `NetworkManager.gd` (client-server direct)~~ ✅
5. ~~Update `starter_player.gd` (trimite input)~~ ✅
6. ~~Update UI (MultiplayerUI, room settings)~~ ✅
7. ~~Test local (localhost) — auth, rooms, game loop, terrain sync~~ ✅
8. ~~Deploy pe VPS (scp + npm install + node server.js)~~ ✅
9. Implementează logica specifică pentru fiecare game mode (balloon_hunt, etc.)
10. Character select UI + skin-uri

## Fișiere Cheie
- `SERVER_ARCHITECTURE.md` — protocol, schema DB, arhitectură completă
- `PROMPT.md` — prompt de dat AI la începutul sesiunii
- `signaling_server/` — toate fișierele serverului
- `NetworkManager.gd` — client WebSocket (de rescris)
- `starter_player.gd` — trimite input în loc de RPC
- `MultiplayerUI.gd` — room settings + character select
