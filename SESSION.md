# BalloonWar Python Port - stare finala desktop (31 august 2026)

> Aceasta sectiune inlocuieste planurile "Fazele viitoare" din istoricul de
> mai jos. Sectiunile vechi raman numai ca jurnal tehnic al portarii.

## Stare

Portul runtime-ului desktop activ este COMPLET in Python 3.15:

- teren procedural realistic, eroziune, LOD/streaming, apa, texturi si pesteri;
- fizica jucatorului, first/third/free camera, dig/build si inventar cu 10 sloturi;
- combat complet (baloane, sageti, arme, damage, scor, moarte/respawn si audio);
- structuri deterministe, crafting, salvare locala/online si autosave;
- HUD, meniu principal/pauza, Creator, selectie personaj si Game Over;
- editor de structuri cu grid, nume, save/load JSON, undo/redo si blueprint-uri;
- login, cont nou, logout/stergere cont, lobby, ready/start, chat si sincronizare
  multiplayer (pozitii, stare remote si modificari de teren).

Nu se porteaza separat scripturile Godot din `scripts/legacy/` si scenele de
test: nu fac parte din runtime-ul activ. Serverul Node ramane serviciul
multiplayer separat, iar clientul jocului este Python. Faza mobile ramane
EXCLUSA pana la o cerere explicita a utilizatorului.

## Ultima runda - completare, buguri si optimizari

### Functionalitate terminata

1. Salvare versionata v3, atomica, cu world config, inventar, player, override-uri,
   blocuri, chunk-uri de structuri si profilul personajului.
2. Crafting tranzactional si resurse JSON incluse in pachet.
3. Audio rezilient cu muzica, pop, tragere si impact.
4. Meniu complet: play/load/save, Creator, personaje, setari, cont si multiplayer.
5. Editorul de structuri si biblioteca de blueprint-uri compatibile cu JSON-ul
   original `StructureData.gd`.
6. Client WebSocket in thread separat, reautentificare, camere/lobby, ready,
   save/load online, chat, stergere cont si cleanup complet.
7. Remote players cu interpolare, modele de personaje/unelte si nameplate-uri.
8. Entry point `balloonwar`, README, package-data pentru shader-e, retete si
   blueprint-urile implicite.

### Buguri reparate in audit

1. **Cache de teren contaminat intre lumi**: cache-ul global era indexat numai
   cu `(x,z)`; doua seed-uri/configuratii in acelasi proces refoloseau terenul
   primei lumi. Cheia include acum seed-ul si toti parametrii relevanti.
2. **Creator fara efect real**: frecventa, detail, warp, curve, ridge,
   biome frequency si limitele min/max sunt conectate la generatorul realistic.
   Valorile default pastreaza aspectul existent.
3. **Limite Creator diferite scalar/mesh**: clamp-ul dupa eroziune se aplica
   identic in coliziuni, interogari vectorizate si mesh-ul chunk-ului.
4. **`cave_enabled` ignorat**: optiunea opreste acum scalarul, generatorul
   vectorizat si mesh-ul pesterii; acesta foloseste suprafata erodata corecta.
5. **Salvari corupte puteau opri jocul**: toate numerele, coordonatele,
   cantitatile, tipurile de bloc si listele au validare, clamp si limite.
6. **Mesaje server invalide puteau opri jocul**: protocolul defensiv filtreaza
   ID-uri/liste/pozitii/tipuri, prinde erorile WebSocket si reseteaza starea la
   disconnect. Retry-ul de parola functioneaza pe conexiunea existenta.
7. **Stare de text ramasa activa in meniu**: orice comanda non-field inchide
   campul activ, deci tastele nu mai ajung accidental in input-ul anterior.
8. **Lifecycle smoke test incomplet**: testul vizual inchide acum reteaua,
   resursele GPU si GLFW inclusiv pe ramura de eroare.

### Optimizari

1. Coada de streaming foloseste `collections.deque.popleft()` O(1), nu
   `list.pop(0)` O(n), si nu mai adauga rebuild-uri LOD duplicate.
2. Coloanele lipsa din cache sunt deduplicate inainte de noise/eroziune.
3. Rendererul de blocuri pastreaza referinta registrului, nu o copie completa,
   si construieste VBO numai pentru raza streamata (18 chunk-uri).
4. Resursele GPU ale chunk-urilor, pesterilor, jucatorilor remote, UI-ului,
   audio si conexiunii sunt eliberate explicit la restart/exit.

## Verificare finala

```text
pytest tests -q       -> 144 passed, 3 skipped in 68.60s
ruff check src tests  -> All checks passed
compileall src tests  -> OK
python -m balloonwar.main --help -> OK
```

Cele 3 skip-uri sunt guard-uri dependente de seed pentru chunk-uri fara apa,
nu teste esuate.

Smoke OpenGL in `xvfb`:

- seed 1337, 30 cadre: 132 chunk-uri, screenshot 1280x720;
- seed 2026, 20 cadre: 83 chunk-uri, screenshot 1280x720;
- cadrele au mii de culori distincte si doar 0.001% pixeli aproape negri
  (nu sunt blank, rasturnate sau acoperite de un buffer necuratat).

## Rulare

```bash
cd /home/teodor/Desktop/BalloonWar/python_port
source /mnt/spatiu/balloonwar_venv/bin/activate
python -m balloonwar.main
```

Optiuni validate: `--seed`, `--load`, `--mode creator`,
`--mode structure_editor`, `--no-audio`.

- `BALLOONWAR_ASSET_ROOT`: directorul `python_port` cand jocul este lansat
  din afara checkout-ului.
- `BALLOONWAR_SERVER_URL`: endpoint WebSocket alternativ; foloseste
  `wss://` cand serverul suporta TLS.

## Limitari cunoscute, neblocante

1. Endpoint-ul serverului existent este implicit `ws://` (fara TLS);
   clientul suporta `wss://`, dar serverul trebuie configurat pentru TLS.
2. Asset-urile runtime au aproximativ 596 MB si raman externe wheel-ului;
   codul, shader-ele si JSON-urile sunt package-data.
3. Registrul persistent al structurilor/blocurilor creste cu explorarea unei
   lumi infinite. Randarea este acum limitata spatial, dar fisierul de salvare
   poate creste in sesiuni de explorare foarte lungi.
4. Serverul instalat nu trimite inca modul uneltei remote in toate mesajele;
   clientul foloseste combat ca fallback si este compatibil cu campul nou.

---

# BalloonWar Python Port - Rezumat Sesiune (29 august 2026)

## Ce s-a facut in aceasta sesiune (29 aug 2026) — FAZA 7+8+9 + reparatii utilizator (runda 7: far terrain SCOS)

### REPARATII din raportul utilizatorului (runda 7: "aceias problema, refa codul care mergea")

1. **FAR TERRAIN-ul a fost SCOS definitiv** — a cauzat 2 runde de bug-uri
   vizuale ("totul arata ca far"): desenat DUPA chunk-uri, suprafata lui
   (inaltimi de BAZA, cu pana la 0.6 m mai sus decat cele erodate) castiga
   depth test-ul si acoperea 65% din ecran. Desenat INAINTE, tot nu mergea
   (test definitiv: 65% pixeli diferiti fata de randarea fara el - testele
   anterioare "2.7%" erau eronate). Fix real nu a functionat -> SCOS.
   Jocul a revenit la starea vizuala care mergea (runde 3-4).
2. **Raza de randare 16 -> 18 (288 m)**: orizontul de pe varfuri mai aproape
   (cer sub orizont: ~20% -> 10.4% la 288 m) fara cost mare (122 FPS steady
   cu 1369 chunk-uri; "24 FPS" la raza 20 era masurat in timpul streaming-ului
   dupa mutarea camerei - real e 122 FPS).

**107 teste pass + 3 skip, ruff curat. Far terrain scos, raza 288 m, 122 FPS.**

### REPARATII din raportul utilizatorului (runda 6: "aceias problema + totul arata ca far, jos pare o groapa")

1. **"TOTUL ARATA CA FAR TERRAIN"** — far terrain-ul (mesh-ul indepartat de
   64 m) ACOPERA chunk-urile apropiate: 67% din pixeli erau suprascrisi!
   Cauza: suprafata far terrain-ului e la inaltimile de BAZA, iar chunk-urile
   la cele ERODATE (cu pana la 0.6 m mai jos) -> far terrain-ul, desenat
   DUPA chunk-uri, avea adancime mai mica si castiga depth test-ul.
   Fix: far terrain-ul se deseneaza INAINTEA chunk-urilor (ele il acopera
   oricum; in afara lor el acopera pana la orizont). Rezultat: doar 2.7% din
   pixeli difera fata de randarea fara far terrain (exact zonele de peste
   256 m). "Groapa" din screenshot era de fapt oceanul din far terrain.
2. **Orizontul de pe varfuri**: acoperirea cerului sub orizont a coborat de
   la y=584 la y=292 pe coloana x=1000 (far terrain pana la ~4 km); restul
   de "cer" sub orizont = cerul legitim deasupra liniei orizontului.
3. Screenshot-ul utilizatorului (20:54) era din build-ul v5: jucator MORT
   (HP 0, "AI MURIT") - titlul ferestrei confirma versiunea. "Obiectele
   suspendate"/"groapa" erau efectele vizuale ale far terrain-ului peste
   chunk-uri.

**107 teste pass + 3 skip, ruff curat. Far terrain fara suprascrierea
chunk-urilor (2.7% pixeli), orizont pana la 4 km, 137 FPS steady.**

### REPARATII din raportul utilizatorului (runda 5: "la deal, teren transparent")

1. **"LA DEAL, TEREN TRANSPARENT"** — de pe varfurile muntilor se vedea cerul
   prin muntii indepartati: raza de randare (256 m) e mica fata de orizontul
   peste uscat (km). Masurat: 24-49% cer sub orizont de pe un varf la 121 m.
   Fix: **`render/far_terrain.py` (NOU)** — un heightfield grosier (celule
   64 m, 129x129 coloane) care acopera de la ~256 m pana la far plane (4 km)
   si urmareste camera (snap 64 m, refacut doar la miscare):
   - inaltimile = ACEEASI functie ca terenul apropiat (columns + eroziune)
   - culori per-varf = sloturi de textura (biome + ocean + piatra/zapada pe
     altitudine) - deci muntii indepartati au culorile corecte
   - **shader DEDICAT** (far_terrain.glsl, culoare plata fara textura):
     sampling-ul texturii la UV-uri de km distanta iesea NEGRU (mipmap)
   - polygon offset POZITIV (+2) -> chunk-urile apropiate castiga la
     suprapunere (fara z-fighting)
   - Rezultat: cer sub orizont de pe varf 49% -> ~19% (restul = orizontul
     real + banda de ~1 grade deasupra marginii terenului la 4 km);
     136 FPS steady (la 32 m/celula era 31 FPS - prea mult).
2. **BUILD-VERIFICARE**: titlul ferestrei are acum "BalloonWar v5" - daca
   utilizatorul vede altceva, ruleaza un proces/build vechi.

**107 teste pass + 3 skip, ruff curat. Teren pana la orizont (4 km) de pe
munti, 136 FPS.**

### REPARATII din raportul utilizatorului (runda 4: "e terenul transparent si vad caveurile de sub mine")

1. **CAUZA GASITA: streaming-ul initial dureaza 4-5 s** — raza 16 = 1089
   chunk-uri la buget 12 ms/frame. La pornire jucatorul vedea cer/apa in loc
   de teren (inclusiv SUB el — "vad caveurile de sub mine"), iar lumea se
   umplea incet. Verificat pe 60 de pozitii + toate unghiurile: DUPA umplere
   NU exista gauri (0.00/40 coloane, inclusiv la miscare cu swap atomic).
   Fix:
   - **Buget ADAPTIV**: cand coada e lunga (>200 chunk-uri) generam cu
     40 ms/frame in loc de 12 — umplerea initiala scade de la 4-5s la ~1.5-2s.
   - **`_pregen_around_player`**: 3x3 chunk-uri in jurul jucatorului se
     genereaza SINCRON la start — pamantul de sub picioare exista din frame-ul
     1 (dupa init: 9 chunk-uri; frame 0: 31; frame 120: 955).
   - Verificat: frame 1 privind in jos = 94% teren solid (inainte ~0%).
2. Verificat si exclus: fustele LOD (fara pereti inchisi vizibili), litoralul
   (fara apa pe uscat), orizontul (apa pana la linia cerului), formula de
   alpha a apei (originalul e chiar MAI transparent: 0.75 vs 0.82 — asa trebuie).

**107 teste pass + 3 skip, ruff curat. Teren solid din frame-ul 1, lume plina
in ~2s, 0 gauri la miscare.**

### REPARATII din raportul utilizatorului (runda 3: apa care "urmareste" jucatorul)

1. **APA "MA URMARESTE"** — undele din vertex shader-ul apei aveau frecvente
   0.05/0.04/0.03 rad/m (lungimi de unda 125-200 m) pe o grila de ~128 m/celula
   -> ALIASING: varfurile esantionau unda la limita Nyquist si suprafata parea
   sa "curga" cu camera (la miscare, grila se deplasa peste unda si tot tiparul
   mare se muta cu jucatorul). Fix: unde LENTE in vertex shader
   (0.012/0.010/0.008 -> 500-800 m, valuri subtiri) + detaliul fin ramane in
   fragment (per-pixel, world-fixed). + polygon offset NEGATIV (-1, -1) la apa
   (z-fighting la linia apei cu terenul, ca in SESSION nota din Faza 5).
2. **SPAWN PE INSULITA** — cautarea de uscat lua PRIMA celula de uscat din
   scan (ex: (-68, 92) cu DOAR 11% uscat in raza 32 m) -> jucatorul era mereu
   inconjurat de apa. Fix: cauta celula cu CEL MAI MULT uscat in raza 48 m
   (grila 25x25) - seed 1337 acum spawn la (36, 78.7, 52), 625/625 uscat.
3. **BALOANE NEGRE** — `balloon.glsl` a primit uniforma `u_color` (pentru
   sageata) dar BalloonRenderer nu o seta -> default moderngl (0,0,0) ->
   `albedo * 0 = negru`. Fix: `u_color = (1,1,1)` in BalloonRenderer.
   Balonul e acum rosu (textura reala), 0 pixeli negri.
4. Verificari vizuale: litoral fara apa pe uscat, inelul LOD fara pereti
   inchisi (fuste invizibile), orizontul peste ocean complet (apa pana la
   linia cerului, fara banda de cer intre ele).

**107 teste pass + 3 skip, ruff curat.**

### REPARATII din raportul utilizatorului (runda 2)

1. **TERENUL TOT TRANSPARENT "in principal"** — cauza reala: ORIONTUL. La
   96-160 m terenul se termina si se vedea cerul prin ocean/munti. Fix COMPLET:
   - `FAR_PLANE` 500 -> 4000 m + **plan GLOBAL de apa** (`build_water_plane` +
     water.glsl cu `u_center`/`u_extent`): apa urmareste camera, ajunge la
     orizont (patch-urile per chunk scoase din renderer - lasau cer vizibil
     prin ocean peste 160 m). Banda de cer de pe dealuri: 21° -> ~0.9°.
   - **LOD real cu FUSTE anti-crapaturi**: chunk_mesh adauga perimetru care
     coboara sub suprafata (y=-4) la LOD>1 - acopera T-junctions-urile dintre
     chunk-urile de LOD diferit. `_lod_for` dupa distanta: <5 chunk-uri LOD1,
     <9 LOD2, altfel LOD4. `RENDER_RADIUS = 16` (256 m), UNLOAD 18.
   - **Swap ATOMIC la regenerarea LOD**: mesh-ul nou se construieste INAINTE
     sa se distruga cel vechi (fara gauri temporare la miscare - masurat:
     0.00% gauri in miscare, inainte erau chunk-uri disparute ~1s).
   - Rezultat: 1089 chunk-uri, LOD {1:81, 2:208, 4:800}, 146 FPS steady,
     0.00% cer sub orizont de pe munte la 150 m inaltime.
2. **SAGETILE LIPSEAU** — aveau acelasi bug de flip Z (vertecsi Godot fara
   flip -> z_cam pozitiv -> taiate de clip). Fix + **modelul REAL arrow.glb**:
   `render/arrow_renderer.py` (NOU) - 2 primitive (tija alba "bulder_wood" +
   varf rosu "arew_tip" baseColorFactor), orientate pe directia de zbor cu
   `u_model = FlipZ * T * R(axa->directie) * R_model * S` (axa modelului se
   aliniaza cu directia sagetii). `enemy_renderer.py` sters (cutiile vechi).
3. **`render/gltf.py` extins**: suport pentru MULTIPLE primitive per mesh +
   `baseColorFactor` per material (sageata nu are texturi, doar culori).
4. **`balloon.glsl`**: uniforma `u_color` (tenta pentru modelele fara albedo).

**107 teste pass + 3 skip, ruff curat. Teren fara gauri pana la 256 m +
orizont complet pe apa, 146 FPS, sagetile si armele vizibile.**

### REPARATII raportate de utilizator (runda 1)

1. **TEREN TRANSPARENT (se vedea cerul prin munti)** — cauza: raza de randare
   de 96 m (6 chunk-uri); de pe dealuri orizontul era DINCOTRO de terenul randat
   si se vedea cerul prin "gauri". Fix: `RENDER_RADIUS = 10` (160 m) +
   `UNLOAD_RADIUS = 12`. ATENTIE: UNLOAD_RADIUS trebuie sa fie MAI MARE decat
   RENDER_RADIUS, altfel chunk-urile de la raza 9-10 se distrug si se
   regenereaza la fiecare rebuild de coada (masurat: 2173 generate pentru 441
   unice - bucla infinita). Rezultat: 0.00% gauri sub orizont (era 9.2%).
2. **DEPTH BUFFER NU ERA CURATAT NICIODATA** — `ctx.clear()` fara `depth=1.0`
   lasa adancimea din frame-urile vechi: obiectele apropiate (arma, baloanele,
   structuri) puteau pica pe depth test gresit si "disparea". Fix:
   `ctx.clear(r, g, b, a, depth=1.0)` in main.py + render_test.
3. **BALONUL - MODELUL GLB REAL** — `render/gltf.py` (NOU): loader minimal
   glTF 2.0 (.glb): mesh unic (POSITION/NORMAL/TEXCOORD_0 + indices),
   transformul nodului, texturile embedded (image/jpeg -> PIL). `ballon.glb`:
   85835 varfuri, 152k triunghiuri, albedo 2048x2048 (downscalat la 512).
   `render/balloon_renderer.py` (NOU): VBO/VAO partajat + draw call per inamic
   cu u_model (scala + flip Z + translatie) si u_flash (hit flash, gd:146-148);
   culling pe distanta (70 m - modelul e dens). Inlocuieste sfera UV.
   Masurat: 145 FPS cu 8 baloane glb vizibile.
4. **ARMA LIPSEA** — `render/weapon_renderer.py` (NOU): port
   `_genereaza_arme_automate_cod` (gd:216-290): ARBALETA cutie (0.15,0.15,0.8)
   maro la (0.3,-0.3,0.6), SABIE (0.06,0.8,0.06) gri rot -20, SAPA si CIOCAN
   (mana + cap). Vizibile doar in first person, dupa modul (gd:941-947).
5. **BUG CRITIC: flip-ul Z lipsa la vertecsi noi** — weapon_renderer scria
   vertecsii in coordonate GODOT dar view-ul asteapta OPENGL (z flippat):
   arma ajungea IN SPATELE camerei (z_cam pozitiv -> clipped de w<0) si nu se
   vedea deloc; balonul avea aceeasi problema in u_model (translatia z trebuie
   flippata: m[2,2]=-scale, m[2,3]=-pos.z). Fix in ambele + test de regresie
   (`test_weapon_vertices_in_front_of_camera`). Bonus: `up = cross(fwd, right)`
   (cross invers punea arma deasupra ochiului).

**106 teste pass + 3 skip, ruff curat. 145 FPS cu baloane glb, teren fara
gauri pana la 160 m.**

### FAZA 8: UI — COMPLETA (health bar, hotbar, crosshair, damage overlay, text)

- `render/text_renderer.py` (NOU) — atlas de glife ASCII 32-126 dintr-un TTF
  (freetype-py, Roboto-Bold.ttf din assets), glife ALBE (culoarea din shader),
  pitfall: buffer-ul freetype poate fi list si pitch-ul > latime (padding).
- `render/shaders/ui.glsl` + `render/ui.py` (NOU) — overlay 2D ortografic
  (pixeli, y in JOS ca Godot), doua loturi pe frame (recturi cu textura alba
  1x1 + text cu atlasul), VBO dinamic. Port Interfata din lume.tscn:
  - HealthBarBg (20,50,300x28) + HealthBarFill 296*pct (verde >60%, galben
    >30%, rosu) + "X / 100 HP" centrat (gd:857-870)
  - DamageOverlay rosu full-screen, alpha 0.3 la damage, fade -2*delta/s
    (gd:728-729, 1007-1008) - setat in run() cand HP scade
  - Crosshair cruce centrata (lume.tscn:51-66)
  - Hotbar 7 sloturi 50x54 jos centrat: mini-cub cu culoarea blocului +
    contur, contur alb pe slotul selectat, contorul de resurse
  - label_debug verde (20, 20): "HP | SCOR | ARMA | DIG | MOD | APA"
    (gd:_actualizeaza_text_debug, fara emoji-uri)
  - AI MURIT + timer respawn centrat (Game Over simplu)
- BUG-uri gasite pe parcurs: `ctx.depth_test`/`is_enabled` NU exista in
  moderngl (state-tracking manual); matricea UI trebuia TRANSPUSA la uniforma
  (SESSION.md nota 1 - fara .T nimic nu se pozitiona corect); al doilea draw
  (text) trebuia cu `first=len(rects)`; `p.VIATA_MAXIMA` era constanta de
  modul (AttributeError latent in titlul ferestrei dupa 1s de joc!).
- Screenshot-urile erau rasturnate pe verticala (framebuffer GL bottom-up vs
  PIL top-down) -> FLIP_TOP_BOTTOM in render_test.

**102 teste pass + 3 skip, ruff curat. Jocul ~50 FPS cu HUD-ul activ.**

### FAZA 7: STRUCTURI — COMPLETA (copaci, pietre, case)

- `world/structures.py` (NOU) — port `genereaza_structuri_specifice_zonei`
  (gd:2418-2496): copaci (trunchi 3-5 + coroana 5 frunze, gd:266-276), pietre
  (1-2 blocuri, gd:278-283), case (podea 3x3 + pereti 2 inaltimi WOOD +
  acoperis STONE, gd:2402-2417). Determinist per chunk: RNG propriu cu
  seed = (cx*73856093 ^ cz*19349663) + world_seed (hash Godot instabil).
  Numere pe biome (gd:2470-2496): FOREST 4, SWAMP 3, HILLS 2, PLAINS 2,
  MOUNTAINS/DESERT/SNOW 1, OCEAN/RIVER 0; case PLAINS 50% / HILLS 30%.
  NIMIC in apa (h <= WATER_LEVEL + 0.5, gd:2433/2443).
- Blocurile structurilor intra in `placed_blocks` al jucatorului: se randeaza
  (block_renderer), sunt SOLIDE (coliziuni) si se pot SAPA (scos permanent +
  resursa in inventar = blocuri_structuri_sterse gd:245-247, doar ca nu ne
  trebuie registru separat: nu regeneram structurile).
- Streaming in `main.py:_update_structures` (buget 6 chunk-uri/frame, urmareste
  chunk-urile din renderer, nu genereaza blocuri la distanta <= 2 de jucator).
  render_test le include si el (screenshot cu copaci).

### BUG-URI de fizica reparate (necesare pentru structuri solide)

1. **Jucatorul CADEA prin blocurile plasate** — verificarea verticala din
   `Player.update` nu tinea cont de blocurile plasate (body_top lipsea).
   Fix: `terrain_height(x, z, body_top, feet)` — aterizezi pe un bloc doar
   daca varful lui e la cel mult STEP_HEIGHT deasupra picioarelor (by+1 <=
   feet + 0.5). Fara `feet`, stand langa un perete de 1 bloc erai ridicat
   automat pe el (incalca testul de perete existent).
2. **Fizica O(n) pe placed_blocks** — `terrain_height` iterau TOATE blocurile
   la fiecare frame (cu structurile: mii). Fix: `_block_cols` = index pe
   coloane {(bx, bz): [by sortate]} + `bisect_right`; rebuilt la mutatii
   (`_rebuild_block_index` in try_dig/try_build, `add_structure_blocks`).
   Masurat: 0.06 ms/frame cu 2502 blocuri structuri.
3. **block_renderer: varfuri cub VECTORIZATE** — `_cube_vertices_np` (36
   offset-uri template, identic cu `_cube_vertices` — verificat 1:1 in test).
   5000 blocuri: 12.5 ms/rebuild (in loc de sute de ms in Python pur).

**96 teste pass + 3 skip, ruff curat. Jocul 62+ FPS cu 1023 blocuri structuri
randate. 2502 blocuri in zona de randare: fizica 0.06 ms/frame.**

### Reparatii combat/randare (inainte de Faza 7)

1. **BUG: sagetile nu se eliberau la moartea inamicului** (`entities/projectile.py`):
   `Sageata.update` nu apela niciodata `inregistreaza_sageata` (gd:35-41), deci
   `sageti_incordate` ramanea gol in joc real (feature-ul functiona doar in testele
   care o adaugau manual). Fix: la impact cu inamicul -> `enemy.sageti_incordate.append(self)`
   + `hit_enemy`; sageata infipta URMARESTE inamicul care zboara (ca reparent din
   original); `elibereaza` scoate sageata din lista inamicului. Teste noi:
   `test_arrow_registers_with_enemy_on_hit`, `test_stuck_arrow_follows_enemy`,
   `test_arrow_killing_enemy_gets_released`.
2. **BUG: reconstruire chunk-uri gresita dupa dig** (`main.py:_try_do_dig`): se facea
   un AL DOILEA raycast dupa dig ca sa gaseasca pozitia — putea lovi alta celula si
   reconstruia chunk-urile gresite (crapaturi). Fix: `try_dig` intoarce pozitia SAPATA
   (wx, wy, wz) sau None; main.py reconstruieste 3x3 in jurul pozitiei reale.
   Test nou: `test_dig_returns_dug_position`.
3. **BUG: displacement pe slotul texturii** (`render/shaders/terrain.glsl`): comentariul
   zicea "strat FIX 0" dar codul samplea `block_idx` -> trepte vizibile la granitele
   materialelor pe pante (fix-ul documentat in sesiunea trecuta nu era aplicat).
   Fix: `texture(u_terrain_height, vec3(uv, 0.0))`.
4. **BUG: RuntimeWarnings de overflow** (`core/noise.py`): overflow-ul int32 din hash
   (wrap identic cu C++) afisa `RuntimeWarning: overflow encountered in scalar multiply/add`
   la fiecare apel scalar de noise. Fix: `np.errstate(over="ignore")` in `_hash2d`,
   `_hash3d`, `_single_perlin_2d/3d` (valorile NU se schimba - crossval 452 valori intact).
5. **Diferente fata de original (starter_player.gd) corectate** (`main.py`):
   - M = SAPA + sapa imediat (gd:315-318), Z = CONSTRUIESTE + construieste imediat (gd:320-323)
   - click stanga in modul BUILD construieste (gd:361-364)
   - rotita comuta automat camera: third person la zoom minim -> first person (gd:441-446);
     first person la FOV maxim -> third person (gd:449-456)
   - inamicii urmaresc CAMERA reala in freecam (gd:96-98 `_camera_ref`): `EnemyManager.update`
     accepta `tinta_pos` optional, main.py trimite `camera.pos` in freecam.

**85 teste pass + 3 skip, ruff curat. Jocul ruleaza 60+ FPS, simulare combat 5 seed-uri fara erori.**

---

# BalloonWar Python Port — Rezumat Sesiune (21 august 2026)

Rezumat complet al sesiunii de portare a jocului Godot 4.7 BalloonWar in Python 3.15
(numpy + moderngl + glfw). Foloseste acest fisier ca sa reiei rapid lucrul.

---

## Stare generala: FAZELE 1-6 COMPLETE (jocul se joaca in Python)

| Faza | Continut | Stare |
|---|---|---|
| 1 | Skeleton + venv + fereastra de test | COMPLETA |
| 2 | Noise FastNoiseLite 1:1 + loop/events/config | COMPLETA (452 valori cross-validate cu C++) |
| 3 | Teren procedural | COMPLETA - REINLOCUIT cu algoritmul realistic (vezi mai jos) |
| 4 | Randare 3D (mesh heightfield numpy, apa, shader triplanar, LOD) | COMPLETA (60 FPS) |
| 5 | Jucatorul (fizica, dig/build vizual, inventar, camere) | COMPLETA - miscare FIXATA + third person vizibil |
| 5.5 | Teren realistic (algoridmDereferinta.py) + eroziune vectorizata + 4 texturi | COMPLETA (fara gauri intre chunk-uri) |
| 6 | COMBAT (baloane inamice + balista + sabie + viata/scor + spawnere) | COMPLETA |

**81 teste pass + 3 skip, ruff clean.**

---

## Faza 6 - COMBAT (ce s-a adaugat)

- `entities/enemy.py` — InamicBalon (port InamicBalon.gd): AI-ul urmareste
  OCHIUL CAMEREI (nu corpul!), distanta > 3.0 zboara (fara gravitatie),
  <= 3.0 ataca cu 10 damage la 1.2s; tipuri normal/rapid/mare (3.2/5.5/2.0,
  100/60/200 HP, 10/15/30 puncte); DROP_TABLE (piatra/carbune/fier/aur);
  hit flash 0.15s; sagetile incordate se elibereaza la moarte (viteza 15).
- `entities/projectile.py` — Sageata (port SageataProiectil.gd): viteza 30,
  damage 25, viata 5s (15s infipta), se infige in teren sau in inamic.
- `entities/enemy_manager.py` — spawnere pe biome per chunk (SWAMP 3,
  FOREST 2, MOUNTAINS 2 - gd:2489-2496), DETERMINISTE per chunk (seed
  propriu, hash Godot e instabil); primul balon dupa 5s, apoi 15-30s;
  balonul apare la +15 deasupra; cap 50 de inamici (deviatie - lume infinita).
- `entities/player.py` — VIATA_MAXIMA 100, primeste_damage cu invincibilitate
  0.5s, WORLD_BOTTOM damage 50 (gd:836-839, INAINTE de coliziune), scor +
  baloane_sparte, arma ARBALETA/SABIE, respawn (automat 2s sau R, 3s invinc.).
- `render/enemy_renderer.py` — baloane = sfere UV (raza 0.95), culori per tip
  (rosu/portocaliu/mov), hit flash spre alb; sagetile = cutii alungite.
- `main.py` — X=combat, Q=arma, click stanga=atac; HUD in titlul ferestrei
  (HP | SCOR | ARMA | inamici); combat merge si in freecam.
- Control: X = combat, Q = balista/sabie, R = respawn (sau automat dupa 2s).


## Ce s-a facut in aceasta sesiune (21 aug 2026)

1. **FIX miscare jucator** (`entities/player.py:_rotate_yaw`): W mergea in
   MIRRORUL directiei camerei (W te ducea inapoi la yaw=0). Formula noua
   mapeaza W -> forward() (sin yaw, 0, cos yaw) si D -> right() (cos, 0, -sin).
   Inotul cu pitch: `velocity[1] += direction[1] * VITEZA_INOT` (privesti sus,
   W inoata sus). `ray_from_camera` foloseste pozitia camerei in third person.
2. **Third person vizibil** (`render/player_renderer.py` NOU): corp capsaula
   (7 cuburi, albastru), randat doar in third person, rotit cu yaw. Camera
   din third person NU mai intra in teren (clamp pe `terrain_height` in main.py).
3. **TEREN REALISTIC NOU** (referinta `algoridmDereferinta.py`, Blender):
   - `world/terrain_noise.py`: canale noi - warp (FBM 3 oct), continent (FBM 5),
     landmask (FBM 3, frecventa medie ~200 blocuri - amesteca uscat/ocean in
     ORICE zona, indiferent de seed), mountain_range (FBM 4), mountain/ridge
     (1 octav, ridged manual cu weight-feedback din referinta!), hill (FBM 4),
     detail (FBM 4), micro (FBM 3). WORLD_SCALE_DIVISOR = 4 (feature-uri la
     scara de joc). S-au pastrat biome + ore.
   - `world/terrain.py`: formula din referinta (domain warp -> continente ->
     lanturi muntoase -> ridged -> dealuri -> detaliu/micro), amplitudinile
     calibrate pe domeniul 0..127 blocuri (apa la 66). Inaltimi tipice 60-100,
     varfuri pana la 127, ocean ~15-60% (per seed).
   - `world/erosion.py` (NOU): anti-spike + thermal + hydraulic aproximativ,
     VECTORIZATE (np.roll), < 1 ms/chunk (referinta: minute!). Compuse ca
     DELTA independente de baza (nu in lant) -> suport EXACT EROSION_RADIUS.
   - **FARA GAURI INTRE CHUNK-URI**: inaltimea = functie PURA de (x, z) int +
     cache global de coloane de baza; eroziunea = filtru cu suport limitat pe
     grila padded (pad = EROSION_RADIUS + 1). Muchiile chunk-urilor sunt
     IDENTICE (teste dedicate, dif < 1e-4).
   - LOD ramane DEZACTIVAT; CHUNK_DIMENSIONS = 16 FIX (fara T-junctions).
4. **TEXTURI**: strat 4 de zapada (Snow004) in TextureArray; sloturi per-vertex
   alpha*4 (0=iarba, 1=nisip, 2=piatra, 3=zapada); zapada la altitudini >= 100,
   piatra >= 85, nisip pe plaje/fund de ocean.
5. **Spawn** in `main.py`: cautare VECTORIZATA (eroded_heights_vec pe grila
   pas 4, raza 100) - instant si gaseste uscat pe orice seed.

### Performanta
- Chunk rece ~8.7 ms, cald ~4.4 ms (buget streaming 8 ms/frame).
- 60 FPS la 1280x720 (render_test).
- Eroziunea: ~1 ms per chunk (vs 45000 de picaturi in Python, minute).


## Mediu

- Python: `/usr/local/bin/python3.15` (3.15.0rc1)
- venv: `/mnt/spatiu/balloonwar_venv` — activare: `source /mnt/spatiu/balloonwar_venv/bin/activate`
- VSCode interpreter: `/mnt/spatiu/balloonwar_venv/bin/python`
- Backup original: `/mnt/spatiu/BalloonWar_backup_2026-08-19.7z` (SHA256 4dfe246eb6c645bd5edba574dca7b9fab8f5baf0da3a0d908e86dee200ee432b)
- Radacina proiect: `/home/teodor/Desktop/BalloonWar` (assets/textures folosite direct de la original)
- Texturile reale sunt in `python_port/assets/textures/` (iarba, nisip, piatra, zapada Snow004, apa)


## Cum se joaca

```bash
cd /home/teodor/Desktop/BalloonWar/python_port
source /mnt/spatiu/balloonwar_venv/bin/activate
python -m balloonwar.main        # sau cu seed: python -m balloonwar.main
```

- WASD miscare (dupa camera), SPACE saritura / inot sus, SHIFT inot jos
- Click stanga = dig, click dreapta = build (blocul selectat)
- Tastele 1-7 = slot inventar (GRASS/DIRT/STONE/COAL/IRON/COPPER/GOLD)
- M = dig, Z = build, X = combat (fara arme inca), V = ciclu, B = dig cub/sfera
- C = first/third person (corpul jucatorului vizibil in third), F = freecam,
  scroll = zoom FOV / distanta camera, ESC = meniu/exit
- Dupa dig mesh-ul se reconstruieste (3x3 chunk-uri); blocurile plasate = cuburi colorate

## Teste si lint

```bash
cd python_port
source /mnt/spatiu/balloonwar_venv/bin/activate
python -m pytest tests/ -q          # 59 passed, 3 skipped
ruff check src/ tests/               # curat
```

Screenshot: `python -m balloonwar.tools.render_test --seed 1337 --frames 60 --out /tmp/x.png`
Harta teren: `python -m balloonwar.tools.render_terrain_map --seed 1337 --size 512`

---

## Structura portului (python_port/src/balloonwar/)

- `core/noise.py` — FastNoiseLite 1:1 (Perlin+FBM+Ridged vectorizat; int32 overflow wrap; FastFloor)
- `core/config.py` — WorldConfig (parametri identici WorldConfig.gd)
- `core/loop.py`, `core/events.py` — loop 60Hz + EventBus (nefolosite inca in main)
- `world/terrain_noise.py` — canalele NOI ale algoritmului realistic (warp, continent, landmask, mountain_range, mountain/ridge 1-oct, hill, detail, micro) + biome + ore
- `world/erosion.py` — eroziune vectorizata (anti-spike + thermal + hydraulic aprox.), compusa ca DELTA independente de baza, suport EROSION_RADIUS=4, < 1 ms/chunk
- `world/terrain.py` — algoritmul realistic (domain warp + continente + ridged + dealuri + detaliu), inaltimi 4..127 (apa 66), cache-ul global `_col_cache` (baza) + `_eroded_cache` (final) aici, `thread_surface_height` = baza + eroziune, `surface_height_from_noise*` = ACEEASI suprafata (unificat)
- `world/chunk_mesh.py` — mesh heightfield numpy; grila de coloane cu pad (extra + EROSION_RADIUS) + `erode()` pe grila → muchii identice intre chunk-uri; culori alpha = slot/4 (0=iarba 1=nisip 2=piatra 3=zapada); LOD suportat dar DEZACTIVAT
- `world/water.py` — patratul de apa (4x4 celule, WATER_LEVEL+0.08, uv=poz*0.08)
- `entities/player.py` — fizica (gravitatie 9.8, saritura 5.5, viteza 7, inot 5, capsula 0.9), coliziune heightfield + cuburi exacte, raycast combinat, dig/build, moduri camera; `_rotate_yaw` aliniat cu `forward()` (W = unde priveste camera)
- `entities/inventory.py` — inventar (BLOCK_ORDER identic, 64/64/32 initial, slot 1-7)
- `render/camera.py` — FPS (yaw/pitch), coordonate GODOT + flip Z in view matrix
- `render/chunk_renderer.py` — streaming radial, buget generare 8ms/frame, request_rebuild
- `render/block_renderer.py` — cuburi BlockScena colorate (VBO dinamic)
- `render/player_renderer.py` — corpul jucatorului (capsula 7 cuburi) in third person
- `render/textures.py` — TextureArray 4 straturi (iarba/nisip/piatra/zapada) 256x256 din assets
- `render/shaders/terrain.glsl`, `water.glsl`, `block.glsl` — porturi din resources/*.gdshader; separatorul sectiunilor: `// ===== FRAGMENT =====`
- `main.py` — jocul (fereastra 1280x720, FOV 75, soare + cer, spawn vectorizat)

---

## Detalii tehnice CRITICE (nu uita!)

1. **Matrice transpusa la uniforme**: numpy e row-major, GLSL mat4 e column-major.
   SE SCRIE `p["u_proj"].write(proj.T.tobytes())` — fara `.T` nu se deseneaza nimic.
2. **LOD DEZACTIVAT** (render/chunk_renderer.py `_lod_for` returneaza 1) SI
   **CHUNK_DIMENSIONS = 16 FIX**: singura combinatie fara crapaturi. Muchiile
   chunk-urilor sunt identice pentru ca inaltimea e o functie PURA de (x, z)
   int (cache global de coloane) si eroziunea e un filtru cu suport limitat.
3. **EROZIUNEA = DELTA independente de baza** (world/erosion.py `erode`):
   `final = baza + delta_spike + delta_thermal + delta_hydro`, fiecare pas
   calculat din baza (NU in lant!). In lant, coruptia de la muchii se aduna
   (raza totala = suma razelor) → crapaturi intre chunk-uri. Cu deltele,
   suportul e EXACT EROSION_RADIUS (4) → pad-ul grilei = EROSION_RADIUS + 1
   e suficient. Nu schimba ordinea/structura fara sa recalculezi pad-ul!
4. **Cache-ul coloanelor e in world/terrain.py** (`_col_cache` baza +
   `_eroded_cache` final), NU in chunk_mesh. `clear_column_cache()` sterge
   ambele. `Terrain.columns(wx, wz)` populeaza cache-ul de baza; mesh-ul
   aplica `erode()` pe grila, scalarul `thread_surface_height` pe crop 9x9
   (rezultate IDENTICE — testat 1:1).
5. **WATER_LEVEL**: terenul foloseste 66 (constanta reala). Originalul in starter_player.gd
   are 10 (bug) — inotul era imposibil; noi folosim 66 (diferenta documentata).
6. **`None != 0` e True in Python**: in _adjusted_column (player.py) verificarea corecta
   e `ov is not None and ov == 0` — altfel TOATE coloanele erau coborate cu floor(h).
7. **Shaders**: variabilele nefolosite sunt optimizate de compilator → KeyError la
   `vertex_array` (ex: in_normal nefolosit). Foloseste fiecare attribute/uniform SAU scoate-l.
8. **Fragment shader-ul are nevoie de propriile `in`-uri si `#version 330 core`**
   (in _load_shader_program din main.py se prepenir + `#version` la fragment).
9. **Originalul NU inmulteste COLOR.rgb in albedo** (doar COLOR.a → slot textura).
   Noi facem la fel — tint-urile RGB sunt ignorate la randare (identitate vizuala).
10. **Sloturi textura**: alpha = slot/4 (0=iarba, 1=nisip, 2=piatra, 3=zapada);
    shader-ul face `round(in_color.a * 4.0)`. Zapada la altitudini >= 100,
    piatra >= 85 (in chunk_mesh, dupa culorile de biome).
11. **Mouse**: yaw += dx (dreapta = dreapta; originalul avea semnul invers).
    Pitch: -= dy (mouse sus = privire sus; GLFW dy negativ la sus).
12. **Miscare jucator**: `_rotate_yaw` trebuie sa produca `forward()`
    (sin yaw, 0, cos yaw) pentru W — NU mirror-ul lui (bug vechi: W te ducea
    inapoi). Inotul cu pitch: velocity[1] ia direction[1].
13. **Fog ELIMINAT** la cererea utilizatorului (inainte: u_fog_density 0.00006).
14. **Spawn**: cautare VECTORIZATA in main.py (eroded_heights_vec, grila pas 4,
    raza 100) — nu folosi thread_surface_height scalar in bucle (lent).

## Bugs rezolvati in sesiune

- Miscarea jucatorului nu urma camera (mirror Z in _rotate_yaw) → fixat
- Third person nu avea corp vizibil + camera intra in teren → player_renderer + clamp
- Inotul nu tinea cont de pitch (privesti sus, inoti in jos) → direction[1] in viteza
- Eroziunea in lant producea crapaturi la muchii (raza acumulata) → delta-compunere
- Oceanul pe uscat: centrul biome OCEAN era selectat pe pamant → exclus pe uscat
- thread_base_block_type_vec folosea inaltimea de BAZA (nu erodata) → mismatch scalar
- Spawn lent (bucle scalare) + posibil peste apa pe seed-uri oceanice → vectorizat
- Determinism pe seed: continentul singur dadea 100% ocean/100% uscat → landmask
- Crash la start in thread_biome_color (MOUNTAINS): `m[snow]` indexa array-ul
  complet cu un mask pe SUBSETUL m -> IndexError boolean (289 vs 25) → fix cu
  `subset = flatnonzero(m)` + test de regresie (test_mountains_biome_color_*)
- Gauri in CUBURILE plasate: fiecare fata avea doar 4 varfuri randate ca
  TRIANGLES (8 triunghiuri din 12) -> cuburi goale. Fix: 6 varfuri/fata
  (2 tris), ordinea (p0,p2,p1,p0,p3,p2) + flip Z = CCW in OpenGL.
  Acelasi bug in player_renderer (corpul din third person). Test: 36 varfuri,
  triunghiuri nedegenerate, normalele spre exterior.
- Crapaturi la BORDURILE chunk-urilor dupa DIG: clamp-ul de muchii (gd:951-962)
  folosea doar vecinul din interiorul chunk-ului (stanga cu coloana 15, dreapta
  cu 17 -> inaltimi diferite pe x=16, crack ~0.44 blocuri). Fix: clamp cu
  AMBII vecini (exista in grila padded) -> identic in chunk-urile vecine.
  Test: dig pe muchie/colt + build, crack = 0 pe 4 directii si seed-uri.
- Crapaturi vizuale ramase (raport utilizator, "inainte si dupa dig"):
  - Z-FIGHTING: fundul cuburilor plasate e coplanar cu terenul (si apa cu
    terenul la linia apei) -> flicker/crapaturi. Fix: glPolygonOffset
    (cuburi + corp jucator: +1/+1; apa: -1/-1) in render/block_renderer.py,
    player_renderer.py, chunk_renderer.py.
  - TREPTE la granitele materialelor: displacement-ul din vertex shader
    samplea textura height la slotul materialului (iarba/piatra/zapada) ->
    trepte de pana la 0.08 blocuri vizibile pe pante. Fix: displacement pe
    strat FIX 0 (terrain.glsl).
- DIG NEATOMIC: chunk-ul distrus de request_rebuild nu se randeaza pana
  nu e regenarat (coada 8ms/frame) -> gaura temporara + muchii necoincidente
  cateva cadre. Fix: `ChunkRenderer.flush_queue(rebuilds)` reface cele 9
  chunk-uri (3x3) in acelasi frame (54 ms per click).
- TERENUL NU APAREA LA START (raport utilizator: "~1s pana se randeaza",
  "meshes create onli when dig", "pamantul transparent"): coada de streaming
  se scotea cu `pop()` (din COADA) desi era construita radial aproape->departe
  -> se generau mai intai chunk-urile cele mai DEPARTATE si terenul din jurul
  jucatorului aparea abia dupa ~1s (sau niciodata pana nu se dadea dig ->
  flush_queue). Fix: `pop(0)` (din FATA) - terenul e vizibil din frame-ul 1.
- EROZIUNEA invizibila: parametri prea slabi -> thermal/hydro intarite
  (threshold 0.5/0.3, strength 0.25/0.20). ATENTIE: pasul hydro citeste h la
  distanta 2 (deposit-ul foloseste carve-urile vecinilor) -> raza reala =
  iteratii x 2 = 6 -> EROSION_RADIUS = 6 (era 4, producea dif 0.0009 intre
  scalar si vec si crapaturi subtile la muchii). Pad-ul grilei = 7 (32x32).

---

## Fazele viitoare (detaliat)

### Faza 6: Combat — COMPLETA (vezi sectiunea de mai sus)
- Ramas de facut (UI/audio, Faza 8): health bar vizual, DamageOverlay, sunete
  (pop, rele.wav, arrowhit.wav - miniaudio e instalat), Game Over panel.

### Faza 7: Structuri (copaci, pietre, case, spawner baloane) — COMPLETA
Vezi sectiunea "FAZA 7: STRUCTURI" de mai sus (world/structures.py + streaming
in main.py + blocuri solide/sapabile in placed_blocks).

### Faza 8: UI (health bar, hotbar, crosshair) — COMPLETA
Vezi sectiunea "FAZA 8: UI" de mai sus (render/ui.py + text_renderer.py).
- Ramas: sunete (pop, rele.wav, arrowhit.wav - miniaudio e instalat),
  meniurile (Faza 11) si Game Over panel complet.
-Reconstruiet meniurile din codul original si systemul login,play etc
### Faza 9: Pesteri
Sursa: `scripts/world/CaveSystem.gd` (750+ linii) + gd:1360-1400.
- DEZACTIVATE in original (`cave_enabled = false`, gd:153) — portul le poate
  activa separat; logica: worm/cavern/pit noise + MarchingCubes (resurse/MarchingCubesTable.json)
  + mesh smooth din date (gd:731-745). Blocul din pesteri: `_get_block_type_at` special.
- Randare: mesh separat (cave_material gd:407-422, rocks texture, CULL_DISABLED).
-Sursa a mers prost nu ne vom loa dupa ia vom face prorprul algoridm
### Faza 10: Networking (multiplayer)
Sursa: `scripts/network/*.gd`, `scripts/legacy/teren_proceduaral.gd` (gd:124-125 sync).
- Server Node.js existent (dir `server/` — de verificat); `websockets 17.0.1` instalat.
- Sync: pozitie/camera la 0.05s (gd:733-749), modificari teren
  (`_NM.send_terrain_modify` gd:586), room_id, RemotePlayer (scenes/entities/RemotePlayer.tscn).
- Serializare: JSON cu pozitii + override-uri; seed-ul lumii din sala (WorldConfig).

### Faza 11: Meniu + login + selectie personaj
Sursa: `scenes/menu/*.tscn` (fundal_i_meniu_principal, Meniu, CharacterSelectMenu,
PlayOptions) + `scripts/ui/*.gd` (CharacterData, CharacterSelect, ChatUI).
- Flow original: login → Meniu → sala/multiplayer → lume (cu seed).
- In port: meniu text/overlay GLFW inainte de lume; selectia de seed din meniu
  trebuie sa fie gata inainte de Terrain (acum seed hardcodat 1337 in main.py).

### Faza 12: Mobile (Kivy)
- Amânat prin design: randarea e separata de logica (render/ vs world/+entities/).
- Kivy + py3.15 pe Android — de validat; alternative: BeeWare/Chaquopy.
- Physics/termen: identice, doar renderer-ul se schimba.
_NU facem pan nuu spun
### Open questions / decizii viitoare
- `hash()` Godot (structuri) — inlocuitor deterministic propriu.
- Sunet: miniaudio 1.71 instalat (assets audio exista) — faza UI sau combat.
- Salvare/incarcare joc (get_save_data gd:873) — JSON local.

## Referinte originale (Godot)

- `python_port/algoridmDereferinta.py` (1807 linii) — ALGORITMUL REALISTIC de
  teren (domain warp, ridged, eroziune hidraulica cu picaturi) — baza pentru
  noul world/terrain.py + world/erosion.py (erodat optimizat vectorizat)
- `scripts/legacy/teren_proceduaral.gd` (2951 linii) — terenul original Godot
  (INLOCUIT in port de algoritmul realistic; pastrat ca referinta)
- `scripts/player/starter_player.gd` (1265 linii) — jucatorul
- `scripts/inventory/inventar.gd` — inventarul
- `scripts/world/voxel_world_generator.gd` — generator NOU (doar scene de test, NU folosit)
- `/tmp/opencode/godot-4.7-stable/thirdparty/misc/FastNoiseLite.h` — algoritmul real
- `/tmp/opencode/noise_ref` + `tests/noise_ref_output.txt` — referinta C++ (452 valori)
