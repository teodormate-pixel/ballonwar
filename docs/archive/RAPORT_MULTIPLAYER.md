# Raport Multiplayer — Ballon War

**Status:** Doar LAN testat. Public netestat.
**Config:** `config.cfg` (gitignored) pentru chei Supabase.

---

## Arhitectură

Peer-to-peer cu `ENetMultiplayerPeer`. Host = peer 1, joacă direct (nu server dedicat).
`MultiplayerSpawner` în `lume.tscn` e șters (`queue_free`) în single player; în multiplayer e inactiv (fără `spawnable_scenes`).

---

## Ce funcționează

### Handshake
- Host creează server → client se conectează → schimb de parolă → `_parola_acceptata` trimite `world_seed`
- Clientul primește seed-ul înainte de a încărca scena → teren identic

### Seed sync
- `WorldConfig.world_seed` trimis de host în `_parola_acceptata` (NetworkManager.gd:139)
- Clientul îl aplică pe `_WC.world_seed` înainte de `change_scene`

### Spawn RemotePlayer
- **RPC handler** (`starter_player.gd:779`): la primul sync de la un peer, creează RemotePlayer dacă nu există
- **LumeMain.gd**: `peer_connected` + `peer_disconnected` + `call_deferred` + timer 0.5s fallback
- **`_remove_player`**: cleanup la disconnect

### Sync poziție
- `@rpc("any_peer", "unreliable")` la 0.05s (20/s)
- RemotePlayer face `global_position = target_pos` (snap, fără lerp)
- `_first_sync` → snap la prima poziție primită
- `process_mode = PROCESS_MODE_ALWAYS` pe StarterPlayer (merge și în fundal)

### RemotePlayer vizual
- Corp capsulă colorat (culoare din HSV, bazat pe peer ID)
- 4 arme: arbaletă, sabie, sapă, ciocan
- Label3D cu numele jucătorului
- `inventar` propriu
- `add_to_group("Jucator")`

### Cleanup
- `peer_disconnected` + `_NM.player_left` → `_remove_player` → `queue_free`
- `server_disconnected` → `cleanup()` + meniu

### Securitate IP
- La selectarea unui server din listă (LAN sau public), IP-ul e salvat intern (`_selected_ip`), nu mai apare în UI
- `SUPABASE_URL` și `SUPABASE_KEY` nu mai sunt hardcodate — se încarcă din `config.cfg` (gitignorat)
- `config.cfg.example` are valori placeholder

### InamicBalon
- `jucator_tinta` tip `Node3D` (nu `CharacterBody3D`) — acceptă și StarterPlayer și RemotePlayer
- `is_instance_valid()` checks înainte de utilizare

### cerere_sapare (dig)
- Pe host: sună direct `teren_procedural.cerere_sapare(...)` — nu mai face `rpc_id(1, ...)` pe sine

### Spectate
- La moarte: buton Spectate + Leave
- TAB ciclare între jucătorii din grupul "Jucator"
- Freecam când nu sunt alți jucători

### Single player
- `_NM.peer == null` → `spawner.queue_free()` → fără cod multiplayer

---

## Probleme cunoscute

### 1. CRITICAL — Sync nu funcționează pe client
- Host trimite RPC `_sincronizeaza_pozitie` la 0.05s
- Clientul primește RPC-ul (RemotePlayer e creat), dar poziția nu se actualizează
- RemotePlayer rămâne în poziția inițială, nu urmărește host-ul
- Cauză probabilă: `get_tree().current_scene` returnează null în context RPC, sau RPC-urile nu ajung efectiv
- **Nu s-a rezolvat** — necesită depanare cu print-uri (`SYNC_RECV`)

### 2. Doar LAN testat
- Public nu s-a testat — config Supabase necesită `config.cfg` cu cheia

---

## Fișiere relevante multiplayer

| Fișier | Rol |
|--------|------|
| `res://NetworkManager.gd` | Server/client, parolă, lobby, seed sync, LAN discovery, Supabase |
| `res://MultiplayerUI.gd` | UI host/join, listă servere (IP ascuns) |
| `res://LumeMain.gd` | Spawn/despawn RemotePlayer, cleanup |
| `res://GestiuneJoc.gd` | Rutare poziție către RemotePlayer, cleanup |
| `res://starter_player.gd` | RPC sync sender + receiver (auto-create RemotePlayer) |
| `res://RemotePlayer.gd` | Corp capsulă + arme + nume + snap poziție |
| `res://WorldConfig.gd` | Config lume (seed, parametri teren) — autoload |
| `res://lume.tscn` | MultiplayerSpawner, Players, StarterPlayer |
| `res://config.cfg.example` | Template config — copiază în `config.cfg` și adaugă cheia |
| `res://InamicBalon.gd` | Inamic, țintă Node3D |

---

## Următorii pași

1. **Depanare sync** — adaugă `print("SYNC_RECV")` în `_sincronizeaza_pozitie` și verifică Output
2. **Sync dig/build** — broadcast modificări bloc de la host la clienți
3. **Sync inamici** — poziție, HP, damage
4. **Chat** — simplu RPC text
5. **Ready check / Lobby** — înainte de start
6. **Test public** — port forwarding sau server dedicat
