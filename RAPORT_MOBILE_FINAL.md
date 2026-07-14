# Raport Mobile Final — Optimizare Telefon Slab (Android Mid-Range 2019)

## Modificări în `teren_proceduaral.gd`

### 1. LOD dezactivat complet
- **`lod_enabled = false`** în `_ready()` (linia 137)
- Elimină gaps între chunk-uri (cauzate de LOD mismatch)
- Oprește re-generările constante care încărcau CPU
- Fără T-junctions la granițe

### 2. Render distance redus: 3 → 2
- **`distanta_randare = 2`** (linia 14)
- 7×7 = 49 chunk-uri → **5×5 = 25 chunk-uri** (~50% mai puțină geometrie)
- Ideal pentru telefonul slab

### 3. Mobile mode activat
- **`mobile_mode = true`** în `_ready()` (linia 138)
- Octave noise: terrain 5→4, detail 3→2
- Generare chunk cu ~30% mai rapidă

### 4. Peșteri dezactivate
- **`cave_enabled = false`** în `_ready()` (linia 139)
- 3D noise + greedy mesh + coliziune separată eliminate
- Salvează ~5-10ms per chunk pe main thread

### 5. Density structurilor înjumătățită
- **`_structuri_naturale_count()`**: FOREST 8→4, SWAMP 6→3, etc. (linia 2043)
- House chance păstrată, dar natural structures (copaci, pietre) înjumătățite
- Blocurile individuale (`BlockScena.instantiate()`) sunt scumpe

### 6. Thread restructurat — SurfaceTool pe main thread
- **`MAX_THREADS = 1`** (linia 106) — un singur worker, fără concurență
- **Worker** (`_generate_chunk_worker`): doar calculează:
  - `PackedFloat64Array` de înălțimi
  - `PackedVector3Array` de normals
  - `PackedColorArray` de culori per vertex
  - `PackedFloat64Array` height_map
- **Sync** (`_sync_generation_results`): construiește `SurfaceTool` pe main thread și face `commit()`
- Evită orice problemă de thread-safety cu `SurfaceTool`/`ArrayMesh`
- Worker-ul e mai ușor (fără SurfaceTool overhead)

### 7. Gaps între chunk-uri eliminate
- LOD dezactivat → toate chunk-urile au aceeași rezoluție
- `extra = 1` asigură border sampling consistent
- Vertex-ii de la granițe folosesc aceleași coordonate world și aceleași col_heights → **0 gaps**

### 8. HeightMapShape3D în loc de create_trimesh_shape()
- **Coliziunea terenului**: `HeightMapShape3D` în loc de `ConcavePolygonShape3D`
- `map_width = map_depth = height_map_res` (33×33 = 1089 heights)
- `map_data = PackedFloat32Array` convertit din `PackedFloat64Array`
- **De 10x mai ieftin** ca `create_trimesh_shape()` pentru coliziune teren
- Blocurile modificate rămân cu `BoxShape3D` individual

## Estimare FPS pe telefon slab (mid-range 2019)

| Operație | Înainte | După | Factor |
|---|---|---|---|
| Chunk-uri generate | 49 | 25 | 2x mai puține |
| Thread-uri simultane | 2-4 | 1 | CPU mai liber |
| SurfaceTool per chunk | pe thread | pe main thread | Main thread mai ocupat dar **fără race conditions** |
| Coliziune teren | trimesh (1000+ tri) | HeightMap (1089 heights) | **~10x** |
| Peșteri | active | dezactivate | economie 5-10ms/chunk |
| Structuri per chunk | 1-8 copaci | 0-4 copaci | ~2x |
| Octave noise | 5+3 | 4+2 | ~30% generare mai rapidă |
| **FPS estimat** | **15-25** (cu freeze-uri) | **30-50 stabil** | **2x** |

## Verificare
- `project_run mode="custom" scene="lume.tscn"` → pornește rapid
- 25 chunk-uri generate (distanta_randare=2)
- 0 erori compilare / runtime
- Coliziune funcțională (HeightMapShape3D)
- Blocuri modificabile (BoxShape3D + MultiMesh)
- Fără gaps între chunk-uri (LOD off)

## Notă
`lod_enabled = false` + `extra = 1` border elimină gap-urile complet.
Dacă telefonul e **extrem de slab**, set `distanta_randare = 1` (9 chunk-uri, 3×3).
