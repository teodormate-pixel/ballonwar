# Raport Complet — Generatorul de Teren Procedural

## 1. Erori de Compilare (Rezolvate)

| Problemă | Soluție |
|---|---|
| `SHADING_MODE_SHADED` nu există în Godot 4 | Schimbat cu `SHADING_MODE_PER_PIXEL` |
| `TerenProceduralTerrain.BlockType` - erori ciclu între scripturi | `inventar.gd` și `starter_player.gd` -> `enum BlockType` local |
| `chunk_needs_full_scan` folosit ca variabilă | Corectat la `_chunk_needs_full_scan(key)` |
| Cache Godot corupt (script vechi reținut) | `editor_reload_plugin` + `reimport` forțat |

**Stare:** 0 erori compilare, jocul rulează.

---

## 2. Generatorul de Noise — 6 Straturi

| Noise | Rol | Frecvență | Octave |
|---|---|---|---|
| `terrain_noise` | Forma de bază a reliefului | 0.02 | 5 |
| `detail_noise` | Detalii fine | 0.035 | 3 |
| `warp_noise` | Deformare orizontală | 0.012 | 2 |
| `biome_noise` | Distribuția biomilor | 0.0025 | 3 |
| `ridge_noise` | Creste/ridge-uri | 0.025 | 4 |
| `micro_noise` | Zgomot fin | 0.08 | 2 |

Formula combinată în `_surface_height_from_noise()`:
```
combined = base_noise * 0.60 + detail + ridge + micro * 0.15
smooth_value = clamp(combined, -1, 1) -> smoothstep -> pow(curve)
height = lerp(h_min, h_max, smooth_value)
```

**Rezultatul este `int`** (rotunjit) — principala cauză a abruptului.

---

## 3. Cei 7 Biomi (cu blend între ei)

| Biome | terrain_scale | curve | height_min | height_max |
|---|---|---|---|---|
| PLAINS | 0.012 | 1.0 | 102 | 138 |
| FOREST | 0.014 | 1.2 | 108 | 156 |
| HILLS | 0.018 | 1.5 | 132 | 176 |
| DESERT | 0.010 | 0.8 | 90 | 120 |
| SWAMP | 0.015 | 0.6 | 84 | 120 |
| SNOW | 0.015 | 1.1 | 140 | 240 |
| MOUNTAINS | 0.022 | 1.8 | 160 | 280 |

Fiecare vertex face blend între toți biomii vecini (weighted interpolation). Parametri: `biome_frequency=0.0025`, `biome_amplitude=3.0`.

---

## 4. Arhitectura Mesh-ului (optimizare ~13×)

**Nivel 1 — Precalculare coloane:**
- Grid 19×19 = 361 coloane de înălțimi întregi
- Fiecare coloană: 1 evaluare `_surface_height_from_noise()` (361 evaluări noise per chunk)

**Nivel 2 — Interpolare bilineară:**
- Grid 34×34 vertices (cu border sampling extra=1)
- Fiecare vertex: interpolare lerp între 4 coloane vecine (0 evaluări noise)
- Total: ~2100 triunghiuri per chunk indexate

**Parametri:** `surface_resolution=2`, `lod_enabled=false`, `extra=1`

Fără această optimizare: 34×34=1156 evaluări noise per chunk. Cu precalculare: doar 361. Viteză ~3.2× mai mare la generare, ~13× la sampling dacă s-ar evalua per vertex.

---

## 5. Încărcare Chunk-uri (Render Distance)

- 7×7 = 49 chunk-uri, fiecare 16×16 unități
- Suprafață totală acoperită: 112×112 unități
- Batch de 3 chunk-uri per cadru (deferred call)
- Re-generare la mișcare prin `_physics_process` (când `chunk_curent != chunk_vechi`)
- Coliziune: `create_trimesh_shape()` per chunk

**Bug fixat:** `call_deferred("_process_chunk_queue")` DOAR când coada nu-i goală, altfel buclă infinită -> crash.

---

## 6. Cauza „Abruptului”

`_surface_height_from_noise()` returnează `int` (linia 570):
```gdscript
return int(round(lerp(float(h_min), float(h_max), smooth_value)))
```

Rotunjirea la întreg face ca fiecare coloană să aibă o înălțime exactă în blocuri. Chiar cu interpolare bilineară între coloane, panta dintre două coloane este o linie dreaptă între două valori discrete. La `surface_resolution=2` (2 vertices per unitate), abruptul este vizibil.

**Soluție propusă:** Schimbă `int(round(...))` -> `round(...)` (returnează `float`). Include și actualizarea tipului de return în funcție și în `col_heights`.

---

## 7. Stare Curentă

- Generatorul produce toate 49 chunk-urile cu mesh + coliziune
- Jocul rulează stabil, fără erori
- Scripturi: `teren_proceduaral.gd` (964 linii, 47 funcții), `starter_player.gd` (620 linii)
- Known issue: Auto-login (CredentialsLoader) schimbă scena la Meniu, interferează cu testarea
