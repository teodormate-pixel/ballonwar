# Ballon War — Progress Summary

## Goal
Multiplayer functional cu poziție sincronizată (RemotePlayer), dig sincronizat, inamici, teren identic pe host și client.

## Constraints & Preferences
- Zero pluginuri externe, doar Godot 4 built-in.
- Peer-to-peer: host = peer 1, joacă direct.
- RemotePlayer identic vizual cu StarterPlayer (corp capsulă + arme).
- Single player: MultiplayerSpawner șters (`queue_free`).
- Sync poziție via RPC manual (`@rpc("any_peer", "unreliable")`).

## Progress
### Done
- **MultiplayerSpawner** în `lume.tscn` — spawnare manuală, nu auto-spawn.
- **LumeMain.gd** — spawn/despawn RemotePlayer la `peer_connected`/`peer_disconnected`, `call_deferred` + timer 0.5s fallback.
- **GestiuneJoc.gd** — rutare poziție către RemotePlayer.
- **RemotePlayer.gd** — capsulă colorată + 4 arme + Label3D nume + `_first_sync` snap.
- **starter_player.gd** — `rpc("_sincronizeaza_pozitie", ...)` la 0.05s cu `@rpc("any_peer", "unreliable")`. RPC handler creează RemotePlayer la primul sync. `process_mode = PROCESS_MODE_ALWAYS`.
- **Seed sync** — `WorldConfig.world_seed` trimis de host la client în `_parola_acceptata`.
- **InamicBalon** — `jucator_tinta` tip `Node3D` (nu `CharacterBody3D`).
- **cerere_sapare** — pe host sună direct funcția, nu `rpc_id(1, ...)`.
- **Cleanup disconnect** — `_remove_player` conectat la `peer_disconnected` + `player_left`.
- **Securitate** — IP-ul serverelor nu mai apare în UI (salvat intern). Cheile Supabase mutate în `config.cfg` (gitignorat).
- Parametri teren optimizați.

### Known Issues
- **CRITICAL**: Poziția RemotePlayer nu se actualizează pe client — host trimite sync dar clientul nu vede mișcarea. RPC-urile posibil neprimite pe client. Netestat public, doar LAN.
- Auto-login (CredentialsLoader) schimbă scena la Meniu.tscn.

## Key Decisions
- **RemotePlayer creat în RPC handler** (`_sincronizeaza_pozitie`) — nu mai depinde de semnale MultiplayerSpawner.
- **Snap direct** la `target_pos` (fără lerp) pentru precizie maximă.
- **Sync la 0.05s** (20/s) pentru reacție rapidă.
- **Seed trimis în handshake** — client primește `world_seed` înainte de a încărca terenul.
- **Config separat** — `config.cfg` cu chei, ignorat de git.

## Relevant Files
- `res://NetworkManager.gd` — server/client, parolă, lobby, seed sync
- `res://MultiplayerUI.gd` — UI host/join, listă servere (IP ascuns)
- `res://LumeMain.gd` — spawn/despawn RemotePlayer
- `res://GestiuneJoc.gd` — rutare poziție
- `res://starter_player.gd` — sync sender/receiver (RPC)
- `res://RemotePlayer.gd` — capsulă + arme + snap poziție
- `res://lume.tscn` — MultiplayerSpawner, Players, StarterPlayer
- `res://InamicBalon.gd` — țintă Node3D
- `res://config.cfg.example` — template config
- `res://RAPORT_MULTIPLAYER.md` — raport detaliat multiplayer
