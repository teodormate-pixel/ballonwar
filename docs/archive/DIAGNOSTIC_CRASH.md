# Diagnostic Crash — Teren Procedural

## Cauza Principală
Jocul NU crapă constant — pornește și rulează atât scena principală (`fundal_i_meniu_principal`) cât și `lume.tscn`. Simptomele de freeze/crash descrise (10-30 sec încărcare, blocare) apar intermitent și sunt cauzate de suprasolicitarea main thread-ului în primele secunde ale generării terenului.

## Factorii Identificați

### 1. Prea multe thread-uri simultane (MAX_THREADS = 4 → 2)
- La pornire, `_begin_initial_generation()` lansa până la 4 workeri pe `WorkerThreadPool`.
- 4 thread-uri generând noise fractal + mesh ArrayMesh simultan încărcau CPU la 100% în primele cadre.
- **Fix**: `MAX_THREADS` redus de la 4 la 2 (linia 105).

### 2. `_process_chunk_queue()` apelat direct din `_begin_initial_generation`
- `_begin_initial_generation` era `call_deferred`, dar în interiorul ei apela `_process_chunk_queue()` DIRECT (linia 178).
- Asta însemna că în primul frame după `_ready()`, se executa sincron sync + lansare workeri fără a lăsa restul scenei să se inițializeze.
- **Fix**: Acum e `call_deferred("_process_chunk_queue")` — lasă frame-ul să se termine înainte să înceapă generarea.

### 3. Sync procesa prea multe chunk-uri per frame
- `_sync_generation_results()` nu avea limită — procesa toate rezultatele disponible odată, blocând main thread-ul.
- Chunk-urile includeau operații grele: `create_trimesh_shape()` (mutat pe thread în V2a), `add_child` pentru mesh+collision+multimesh+apă+structuri+peșteri.
- **Fix V2a**: `create_trimesh_shape()` mutat în worker thread.
- **Fix V2b**: Post-sync (apă, peșteri, structuri, overrides) deferat în `_pending_post_sync`.
- **Fix V2c**: Adăugat `MAX_SYNC_PER_FRAME = 2` — maxim 2 chunk-uri procesate per apel `_sync_generation_results()`.
- **Fix V2c**: Adăugat `MAX_POST_SYNC_PER_FRAME = 2` — idem pentru `_process_pending_post_sync()`.

### 4. Post-sync abandonat la final
- `_process_chunk_queue()` verifica `generation_tasks.is_empty()` pentru a decide dacă să se recheme — dar ignora `_pending_post_sync`.
- Dacă toate thread-urile terminau și sync-ul procesa tot, dar post-sync rămânea în urmă, `call_deferred` nu mai era apelat → post-sync abandonat.
- **Fix**: Acum verifică și `_pending_post_sync.is_empty()` la linia 1033.

### 5. `_genereaza_singur_chunk()` (dead code)
- Funcția veche care genera un chunk pe main thread (100ms+ blocare). Fusese deja înlocuită cu systemul pe thread-uri, dar codul mort rămăsese.
- **Fix (V2)**: Șters `_genereaza_singur_chunk()` — nu mai e apelată de nicăieri.

## Modificări (fișier:linie)
| Modificare | Fișier:Linie | Detalii |
|---|---|---|
| MAX_THREADS 4→2 | `teren_proceduaral.gd:105` | Reducere concurență inițială |
| MAX_SYNC_PER_FRAME=2 | `teren_proceduaral.gd:900` | Hard cap sync per frame |
| MAX_POST_SYNC_PER_FRAME=2 | `teren_proceduaral.gd:964` | Hard cap post-sync per frame |
| `_process_chunk_queue` via call_deferred | `teren_proceduaral.gd:178` | Nu mai blochează frame-ul inițial |
| Defer logic include `_pending_post_sync` | `teren_proceduaral.gd:1033-1034` | Previne abandonarea post-sync-ului |
| `_pending_post_sync` system | `teren_proceduaral.gd:79,939,959-983` | Apă/structuri/peșteri procesate asincron |
| Collision shape în worker thread | `teren_proceduaral.gd:798` | `create_trimesh_shape()` pe thread |
| Overrides pasate în worker | `teren_proceduaral.gd:727,766-769,814-835,994-996` | Thread știe de blocurile modificate |
| Grup "Digable" | `teren_proceduaral.gd:1561` | Blocuri modificabile selectabile |
| `render_priority=1` apă | `_build_water_surface()` | Apă vizibilă |
| `_genereaza_singur_chunk` șters | — | Dead code eliminat |

## Verificare Finală
- `project_run mode="main"` → meniul principal se încarcă instant (< 2s)
- `project_run mode="custom" scene="lume.tscn"` → terenul se generează în fundal, jocul rămâne responsive
- 0 erori noi de compilare (doar erori stale din sesiunile anterioare)
