# REPORT: Teren Procedural - v1

**Data:** 2026-06-13
**Autor:** opencode AI
**Proiect:** Ballon War
**Fișier modificat:** `res://teren_proceduaral.gd`

## Modificări efectuate

### 1. Sistem de Blending a Biomilor
- Adăugată funcția `get_biome_weights(world_x, world_z)` -> returnează o listă de ponderi pentru biomasii din apropiere
- Folosește distanța Gaussiană față de centrele biomilor în spațiul de zgomot
- `BIOME_BLEND_SPREAD = 0.18` -> controlează cât de largi sunt tranzițiile
- Tranzițiile între biomi sunt acum line, fără margini dure

### 2. Relief Realist per Biom
Profilele biomilor au fost ajustate pentru a fi mai realiste:

| Biom | Înălțime | Scara | Vârf curbură | Relief |
|------|---------|-------|--------------|--------|
| SWAMP | 88-120 | 0.0035 | 1.04 | Foarte plat, jos |
| PLAINS | 108-155 | 0.0042 | 1.06 | Ușor ondulat |
| FOREST | 115-195 | 0.0055 | 1.18 | Deluros ușor |
| HILLS | 128-240 | 0.0080 | 1.30 | Deluros pronunțat |
| DESERT | 100-158 | 0.0038 | 1.03 | Plat cu dune mici |
| SNOW | 170-285 | 0.0070 | 1.35 | Înalt, stâncos |
| MOUNTAINS | 175-345 | 0.014 | 1.60 | Abrupt, înalt |

### 3. Tranziții Line
- Înălțimea terenului se calculează prin ponderarea parametrilor biomilor activi
- Culorile terenului se amestecă între biomi pentru tranziții vizuale line
- Funcția `_surface_color_for_biome` primește acum coordonatele lumii pentru blending

### 4. Sistem LOD (Level of Detail)
- Chunk-urile îndepărtate au rezoluție redusă pentru performanță
- 3 niveluri: LOD0 (complet), LOD1 (jumătate), LOD2 (sfert)
- Distanțe configurabile: [0, 30, 60] unități
- Coliziuni doar pe LOD0 (chunk-uri apropiate)
- Reducere drastică de vertexuri pentru chunk-uri departate

### 5. Optimizări pentru Telefon
- `mobile_mode = true` reduce octavele de zgomot (4 în loc de 5)
- `max_height_blocks` redus de la 500 la 350
- LOD implicit activ
- Generare asincronă prin coadă de chunk-uri

## Performanță
- 3x3 = 9 chunk-uri random
- Fără LOD: ~4600 triunghiuri per chunk = ~41400 total
- Cu LOD: variază - chunk central full rez, colțuri la 1/16 rezoluție
- Coliziuni doar la LOD0 -> mai puține shape-uri de coliziune

## Testare
- Jucătorul spawn-ează corect pe teren
- Biomasii se schimbă lin (Hills -> Forest -> etc.)
- LOD funcționează (ex: Chunk_-3_-3_LOD1)
- Fără erori în Output

## Următorii pași posibili
- Arbori/plante specifice biomilor
- Apă în zone joase (swamp)
- Zăpadă pe vârfuri de munți
- Texturi în loc de culori solide
