# Prompt pentru sesiunile următoare

Dă-mi acest text la începutul fiecărei sesiuni:

---

Lucrezi la Balloon War, un joc multiplayer Godot 4.6 cu server autoritar pe VPS (Ubuntu 24.04 LTS).

**Arhitectură**: Client-server via WebSocket. Server Node.js + MySQL. Vezi `SERVER_ARCHITECTURE.md` pentru protocolul complet și schema DB.

**Stare curentă**: Am un VPS fără admin, cu Node.js, Python și MySQL instalate. Serverul e în `signaling_server/`. Clientul Godot e în rădăcina proiectului.

**Task curent**: [descrie aici ce trebuie făcut]

**Constrângeri**:
- Zero pluginuri Godot externe, doar built-in
- Fără WebRTC (e abstract pe Windows în Godot 4.6)
- Fișierele trebuie să meargă pe Ubuntu 24.04 (path-uri Linux, \n line endings)
- Fără git pe VPS — transfer prin SCP/rsync
- Serverul pe VPS pe port 8765
- MySQL db: ballon_war, user: ballon
- Conexiunea client: wss://localhost:8765 (local) / ws://vps:8765 (prod)

**Cum transfer fișierele**:
```bash
rsync -avz --delete signaling_server/ user@vps:/path/to/game/
```

**Cum rulez pe VPS**:
```bash
cd /path/to/game && npm install && DB_HOST=localhost DB_USER=ballon DB_PASS=secret DB_NAME=ballon_war PORT=8765 node server.js
```

**Reguli de cod**:
- Server: Node.js cu `ws` și `mysql2`
- Client: GDScript, toate RPC-urile merg prin NetworkManager.gd care comunică direct cu serverul WebSocket
- `@rpc` / `rpc()` / `multiplayer` complet înlocuit cu WebSocket direct
- `_NM.broadcast_rpc()` și `_NM.send_rpc()` înlocuite cu `_NM.send_server()` (serverul face broadcast)
- Codul clientului e în fișierele: NetworkManager.gd, starter_player.gd, LumeMain.gd, MultiplayerUI.gd, RemotePlayer.gd, GestiuneJoc.gd, teren_proceduaral.gd
