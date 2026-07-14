# BalloonWar — Coliziune Teren: Diagnostic și Fix

## Istoric

### Bug 1: Offset coliziune ~8 blocuri (FIXAT)
**Cauză:** `HeightMapShape3D` în Godot își centrează gridul pe originea CollisionShape3D. Codul din `godot_shape_3d.h:_get_point`:
```cpp
r_point.x = p_x - 0.5 * (width - 1.0);
r_point.z = p_z - 0.5 * (depth - 1.0);
```
Cu `map_width=17, map_depth=17`, gridul acoperă `[-8, 8]` în loc de `[0, 16]` cum se aștepta codul.

**Fix (teren_proceduaral.gd:933):**
```gdscript
# ÎNAINTE (greșit — offset -8 în X și Z):
body.position = Vector3(cx * chunk_dimensions, 0, cz * chunk_dimensions)
# DUPĂ (corect — compensează centrarea HeightMap):
body.position = Vector3(cx * chunk_dimensions + chunk_dimensions * 0.5, 0, cz * chunk_dimensions + chunk_dimensions * 0.5)
```

### Bug 2: Border chunk — blocuri rămase nedugite (FIXAT)
**Cauză:** Când săpai la marginea chunk-ului, doar chunk-ul curent era reconstruit. Chunk-ul adiacent avea încă HeightMap-ul original, creând coliziune invizibilă la border care bloca săpatul.

**Fix (teren_proceduaral.gd:1815, 1876):**
```gdscript
var at_edge: bool = _is_at_chunk_edge(wx, wz)
if wy >= int(surf_h) - 2 or at_edge:
    _request_rebuild_for_world(wx, wz, chunk_dimensions if at_edge else 0)
```
Când e la margine, rebuild-ează și chunk-urile adiacente (`radius_blocks=chunk_dimensions` → `r_chunks=1`).

### Bug 3: WATER_LEVEL diferit între teren și jucător (FIXAT)
**Cauză:** `starter_player.gd` avea `WATER_LEVEL=74.0`, `teren_proceduaral.gd` avea `WATER_LEVEL=66.0`. Apa vizuală era la y=66 dar înotul pornea la y=74 — 8 unități diferență.

**Fix (starter_player.gd:14):**
```gdscript
const WATER_LEVEL: float = 66.0  # era 74.0
```

---

## Verificări Rămase

### 1. Apă la border
Water mesh-ul e creat ca `MeshInstance3D` copil al `root` chunk-ului. Vertexurile sunt în coordonate absolute. La x=16 între chunk (0,0) și (1,0), ambele chunk-uri au apă la aceeași y=66.08. Verifică dacă e vizibilă o linie/gap la border.

### 2. Override dict și border
Când săpăm la `local_x=15` în chunk (0,0) și rebuild-uim chunk-urile adiacente, override-ul din chunk (0,0) nu afectează chunk (1,0). Dar cum `_generate_chunk_worker` pentru chunk (1,0) nu va găsi override-uri proprii, va genera terenul original. HeightMap-ul chunk-ului (1,0) la `local_x=0` (world_x=16) va avea înălțimea originală. Verifică dacă asta creează un "pas" invizibil la x=16.

### 3. Sincronizare multiplayer (separat)
`NetworkManager.gd` trimite `terrain_modify` pentru blocuri săpare/plasate. Clientul care primește apelează `sapa_bloc_la_pozitie` → același flow cu rebuild la margini.

---

## Fișiere Modificate
- `teren_proceduaral.gd` — linia 933 (body.position cu +8 offset), liniile 1815/1876 (rebuild adiacent la margine)
- `starter_player.gd` — linia 14 (WATER_LEVEL 66)
- `prompt_offset_coliziune_mesh.md` — acest fișier
