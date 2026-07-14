# Diagnostic Fix V3 — Bugfixuri prompt_fix_crash_37.txt

## Modificări

### Bug 1: `_pending_post_sync.has(key)` nu funcționează → duplicate + crash
- **Cauză**: `Array.has()` pe un array de dictionary-uri verifică dacă string-ul `key` E UN ELEMENT — un string nu e niciodată un dictionary, deci `has` întoarce mereu false. Același chunk era adăugat de 2-3 ori → a doua oară `root` era freed → crash.
- **Fix**: Adăugat `_pending_post_sync_keys: Dictionary = {}` ca tracker. Înlocuit `_pending_post_sync.has(key)` cu `_pending_post_sync_keys.has(key)`. Adăugat `_pending_post_sync_keys.erase(key)` după `pop_front()`.
- **Fișier**: `teren_proceduaral.gd:80-81, 941-944, 975`

### Bug 2: `generation_completed_chunks` incrementat de două ori
- **Cauză**: Se incrementa la LANSAREA workerului (în `_process_chunk_queue`) și iar la FINALIZAREA post-sync-ului. Progresul sărea aiurea și ajungea la 100% când doar jumate din chunk-uri erau gata.
- **Fix**: Șters incrementul din `_process_chunk_queue` (liniile 1029-1031). Păstrat doar cel din `_process_pending_post_sync` — progresul real e când chunk-ul e complet (mesh + apă + structuri + peșteri).

### Bug 3: `water.render_priority = 1` pe MeshInstance3D
- **Status**: Deja rezolvat în sesiunile anterioare. Linia nu există în codul curent — `_build_water_surface()` (linia 2093) nu mai are `render_priority`. Apa e vizibilă corect prin `material_water` și ordinea de randare.
- **Notă**: Dacă se dorește render priority pe apă, trebuie setat pe material: `material_water.render_priority = 1` în `_init_materials()`.

### Bug 4: `_thread_adjust_height` poate returna valori sub WATER_LEVEL
- **Cauză**: Dacă toate blocurile de la suprafață până la `surface_min_height` sunt AIR (săpate), funcția returna `surface_min_height` — care poate fi sub nivelul apei.
- **Fix**: Adăugat `max(float(params.surface_min_height), float(params.WATER_LEVEL) - 2.0)` ca limită inferioară.
- **Fișier**: `teren_proceduaral.gd:673`

### Bug 5: Coliziune generată pe thread poate fi null
- **Status**: Deja rezolvat — `collision_shape` e întotdeauna în `result_data` (linia 807), chiar dacă e `null`. La sync, `if collision_shape != null:` (linia 930) gestionează corect cazul nul.

## Verificare
- `project_run mode="custom" scene="lume.tscn"` → jocul pornește instant
- 0 erori noi de compilare
- 0 erori de runtime în editor logs
- Jocul rămâne live > 30 sec fără freeze/crash
