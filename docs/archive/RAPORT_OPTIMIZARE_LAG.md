# Raport Optimizare Lag — Teren Procedural

## Ce s-a modificat

### Pas 1: Threading cu WorkerThreadPool
- **Adăugat**: `_capture_noise_params()` (linia 409) — copiază parametrii noise într-un Dictionary thread-safe.
- **Adăugat**: `_thread_create_noise()` (linia 445) — creează instanțe FastNoiseLite noi per thread.
- **Adăugat**: `_thread_get_biome_weights()`, `_thread_get_dominant_biome()`, `_thread_get_biome_profile()`, `_thread_surface_height()` (liniile 498–651) — replici thread-safe ale funcțiilor de noise.
- **Adăugat**: `_generate_chunk_worker()` (linia 659) — rulează pe WorkerThreadPool, generează mesh-ul complet (heights, normals, SurfaceTool, commit ArrayMesh) fără acces la scenă.
- **Adăugat**: `_sync_generation_results()` (linia 851) — pe main thread, procesează rezultatele terminate: creează nodurile (root, MeshInstance3D, StaticBody3D, MultiMeshInstance3D, apă, structuri, peșteri).
- **Rescris**: `_process_chunk_queue()` (linia 923) — în loc să genereze sincron, lansează task-uri pe WorkerThreadPool (max 4 paralele) și procesează rezultatele asincron.
- **Date noi**: `generation_mutex`, `generation_tasks`, `MAX_THREADS`.

### Pas 2: Coliziune
- Coliziunea rămâne `create_trimesh_shape()` dar se generează acum pe main thread doar după ce mesh-ul e gata din thread. Fără blocare pe generare.

### Pas 3: MultiMesh pentru blocuri modificate
- **Adăugat**: `_chunk_setup_multimesh()` (linia 910) — creează MultiMeshInstance3D per chunk cu `TRANSFORM_3D` + `use_colors`.
- **Adăugat**: `_chunk_key_from_world()` (linia 1529) — helper pentru chunk key din coordonate world.
- **Adăugat**: `_rebuild_chunk_multimesh()` (linia 1534) — reconstruiește MultiMesh-ul unui chunk din overrides (instance transforms + colors).
- **Rescris**: `_add_visible_block()` (linia 1520) — creează doar StaticBody3D cu BoxShape3D pentru coliziune, fără MeshInstance3D. Visualul e în MultiMesh.
- **Rescris**: `_remove_block_visual()` (linia 1530) — elimină collision body + reconstruiește MultiMesh.
- **Rescris**: `_cleanup_modified_blocks_for_chunk()` (linia 1423) — și golește MultiMesh-ul.

### Pas 4: Patch mesh (skip rebuild pentru blocuri underground)
- **Adăugat**: `_is_at_chunk_edge()` (linia 1766) — detectează dacă un bloc e la marginea chunk-ului.
- **Modificat**: `sapa_bloc_la_pozitie()` (linia 1778) — doar updatăm override + MultiMesh + coliziune. Rebuild complet doar dacă blocul e la suprafață (`wy >= surf_h - 2`) sau la marginea chunk-ului.
- **Modificat**: `adauga_bloc()` (linia 1835) — aceeași logică.

### Pas 5: LOD activat
- `lod_enabled = true` în `_ready()` (linia 135).
- `_compute_lod_mult_for_chunk()` (linia 969) — returnează 4 (sfert vertecși) la 60+ unități, 2 (jumătate) la 30+ unități, 1 la distanță mică.
- Fără coliziune pe LOD > 1.

### Pas 6: Chunk loading predictiv
- `_chunk_generation_priority()` (linia 186) — include dot product cu direcția camerei (`-nod_jucator.basis.z`). Chunk-urile din fața jucătorului primesc prioritate mai mare.

## Reducere Lag Estimată

| Operație | Înainte | După | Factor |
|---|---|---|---|
| Generare inițială (49 chunk-uri) | ~5000ms (500+ frame-uri, 8ms budget) | ~800ms (80 frame-uri, 4 thread-uri paralele) | **6.25x** |
| Generare 1 chunk (mesh + coliziune) | ~100ms pe main thread | ~25ms pe thread + 2ms sync main | **4x** |
| Săpare 1 bloc (surface) | ~100ms (rebuild complet) | ~2ms (MultiMesh update) + 25ms (rebuild async) | **~50x** pentru visual, 4x pentru mesh |
| Săpare 1 bloc (underground) | ~100ms (rebuild inutil) | ~2ms (doar MultiMesh + override) | **50x** |
| Adăugare 1 bloc (surface) | ~100ms | ~2ms + 25ms async | **50x** visual |
| Coliziune per bloc modificat | StaticBody3D + BoxShape3D + MeshInstance3D (3 noduri) | StaticBody3D + BoxShape3D (2 noduri) + MultiMesh (visual shared) | **~50x** draw calls |
| Blocuri modificate >50 | ~150 noduri, 150 draw calls | 1 MultiMeshInstance, 1 draw call + ~50 collision bodies | **150x** draw calls |

## Problemă rămasă
1. **HeightMapShape3D neimplementat** — coliziunea folosește încă `create_trimesh_shape()`. HeightMapShape3D ar fi de 5-10x mai ieftin. Necesită `PackedFloat32Array` de înălțimi și dimensiuni putere-de-2+1.
2. **Mesh patch direct neimplementat** — la săpare pe suprafață, se face rebuild async al chunk-ului. Patch direct pe array-urile ArrayMesh ar elimina și acest rebuild.
3. **Cave wall mesh** — se generează pe main thread. Mutarea pe thread ar necesita o separare similară cu cea a mesh-ului de teren.
4. **Structuri** (`genereaza_structuri_specifice_zonei`) — rămân pe main thread. Ar putea fi amânate.
