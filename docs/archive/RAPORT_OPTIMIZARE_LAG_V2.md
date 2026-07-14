# Raport Optimizare Lag V2 — Bugfixuri prompt_lag_chunks_v3

## Bug-uri Rezolvate

### BUG 1: Thread ignoră overrides (coloana de teren nu detectează blocuri săpate)
- **Cauză**: `_generate_chunk_worker()` nu primea `chunk_overrides` → calcula înălțimea coloanei ca și cum nimic nu fusese modificat → după rebuild, blocul săpat reapărea.
- **Fix**: Pasat `gen_data["overrides"] = overrides.duplicate()` în `_process_chunk_queue()` (linia 996). Adăugat `_thread_adjust_height()` care, când override-ul la suprafață e AIR, scade coloana cu 1. Adăugat `overrides` + `cx` + `cz` la `_thread_surface_color()` pentru override-aware vertex color.

### BUG 2+3: Blocuri modificate neselectabile (lipsă grup "Digable")
- **Cauză**: `_add_visible_block()` crea StaticBody3D dar nu îl adăuga în grupul `"Digable"` → raycast-ul player-ului nu le detecta → nu puteau fi săpate.
- **Fix**: Adăugat `body.add_to_group("Digable")` în `_add_visible_block()` (linia 1561).

### BUG 4: Apa invizibilă
- **Cauză**: Water mesh-ul aveac `render_priority` implicit (0) și, din cauza ordinii de randare, nu se vedea deasupra terenului.
- **Fix**: Adăugat `water.render_priority = 1` în `_build_water_surface()`.

### BUG 5: Sincronizare prea lentă (sync blochează main thread)
- **Cauză**: `_sync_generation_results()` făcea totul pe main thread: mesh setup, coliziune, apă, peșteri, structuri, blocuri modificate. Pentru chunk-uri mari (LOD 0), putea depăși 8ms.
- **Fix parțial (V2a)**: Mutat `mesh.create_trimesh_shape()` în worker thread → collision_shape pre-built. Adăugat `_sync_budget_ms = 4` (time budget) în sync loop.
- **Fix complet (V2b)**: Deferat post-sync (apă, peșteri, structuri, blocuri modificate) într-o coadă separată `_pending_post_sync`. Procesat în `_process_pending_post_sync()` cu același time budget de 4ms. Mesh + coliziune + MultiMesh rămân inline (sunt rapide).

### BUG 6: Dead code `_genereaza_singur_chunk`
- **Șters**: întreaga funcție `_genereaza_singur_chunk()` (~30 de linii). Nu mai era apelată de nicăieri după trecerea la WorkerThreadPool.

## Modificări Adiționale
- Fixat type error: `var collision_shape: TriangleMesh = ...` → `var collision_shape = ...` (ConcavePolygonShape3D, nu TriangleMesh — Godot 4.7).
- `processed_in_frame += 1` adăugat în sync loop (lipsa contorului făcea ca time budget-ul să nu se aplice corect).
- `_pending_post_sync` gărzit cu `is_instance_valid(root)` pentru cazul când un chunk e regenerat înainte ca post-sync-ul vechi să fie procesat.

## Reducere Lag Estimată (Delta față de V1)

| Operație | V1 | V2 | Factor |
|---|---|---|---|
| Sync 1 chunk (mesh + coliziune + apă + peșteri + structuri) | ~8-12ms pe main thread | ~2ms mesh+collision + ~4ms post-sync (deferat) | **2-3x** main thread eliberat |
| Rebuild după săpare (surface) | ~25ms thread + ~10ms sync | ~25ms thread + ~2ms sync + ~4ms post-sync | **1.5x** |
| Override ignorat la rebuild | Bloc reapărea la rebuild | Bloc rămâne săpat | **BUGFIX** |
| Bloc săpat neselectabil | Player nu putea săpa din nou | Poate săpa imediat | **BUGFIX** |
| Apă invizibilă | Apa nu se vedea | Apă vizibilă corect | **BUGFIX** |
| Generare inițială (49 chunk-uri) | ~800ms generare + ~500ms sync | ~800ms generare + ~200ms sync + ~200ms post-sync (interleaved) | **~1.5x** (sync mai distribuit) |

## Problemă Rămasă
1. **HeightMapShape3D neimplementat** — coliziunea folosește încă `create_trimesh_shape()`. HeightMapShape3D ar fi de 5-10x mai ieftin.
2. **Mesh patch direct** — la săpare pe suprafață, se face rebuild async. Patch direct pe array-urile ArrayMesh ar elimina rebuild-ul.
3. **Structuri sincrone** — `genereaza_structuri_specifice_zonei()` e încă în post-sync pe main thread. Ar putea fi mutată în thread cu un sistem de "structure tasks".
4. **Cave wall mesh** — la fel, generat pe main thread în post-sync.
