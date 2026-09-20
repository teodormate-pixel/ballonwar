# BalloonWar - port C++ (OpenGL / GLFW + server C++)

Portul C++ al jocului BalloonWar. Terenul si apa sunt implementarile C++
din proiectul **23 august 1944** (`terrain.cpp`, `water.cpp`, `world.cpp`),
peste care este construit gameplay-ul BalloonWar: blocuri si inventar,
baloane AI, sageti, crafting, salvare, meniuri, Creator, editor de
structuri, multiplayer WebSocket si HUD. Serverul de multiplayer are un
port C++ propriu (`wsserver.cpp` + `gameserver.cpp`), compatibil cu
protocolul serverului Node.

## Build

```bash
cd cpp_port
make -j4          # produce ./balloonwar (client) si ./balloonwar-server
make server       # doar serverul
make run          # ruleaza clientul cu LD_LIBRARY_PATH pentru GLFW/GLEW
../run_server.sh  # ruleaza serverul (il construieste daca lipseste)
```

Pentru **macOS si Windows** (si pachete de release) exista build CMake
cross-platform: vezi [RELEASE.md](RELEASE.md) (dependinte, CPack,
workflow GitHub Actions cu artefacte pentru Linux/macOS/Windows).

Dependinte: g++ (C++17), OpenGL, X11, OpenSSL, libcrypt (bcrypt). GLFW,
GLEW, glm, nlohmann/json si stb_image sunt incluse in `third_party/`
(copiate din 23-augus-1944).

## Rulare

```bash
./run_cpp.sh                  # din radacina proiectului
# sau
cd cpp_port && make run
```

Optiuni prin variabile de mediu:

- `BALLOONWAR_ASSET_ROOT` - directorul cu `assets/` si `models/`
  (implicit: cauta in sus din directorul curent).
- `BALLOONWAR_SERVER_URL` - endpoint multiplayer (implicit
  `ws://62.171.162.154:8765`). Sunt suportate atat `ws://` cat si `wss://`
  (TLS); certificatele sunt verificate, iar `BW_TLS_INSECURE=1` permite
  certificate self-signed (folosit de teste).
- `BW_FAST=1` - mod rapid (fara MSAA, fereastra 640x360, mai putine
  pagini de teren) pentru testare.
- `BW_NO_AUDIO=1` - dezactiveaza sunetul (mpv/paplay).

Debug animatie personaj (folosite pentru capturi/teste):

- `BW_ORBIT_DEG=<grade>` + `BW_CAM_DIST=<m>` - camera third-person orbiteaza
  in jurul personajului (inspectie din orice unghi).
- `BW_ANIM_DEBUG=1` - log cu starea masinii de stari (ground/air/swim/dead,
  blends, crouch, viteza).
- `BW_ANIM_STATE=air|swim|dead` - forteaza starea; `BW_ANIM_SPEED=0..1.6`,
  `BW_ANIM_VY=<m/s>`, `BW_ANIM_AIM=1`, `BW_ANIM_SWORD=1`,
  `BW_ANIM_ATTACK=0..1` + `BW_ANIM_KIND=0|1`, `BW_ANIM_HIT=0..1` -
  forteaza pozitiile de saritura/cadere/inot/tintire/atac/flinch.
- `BW_ANIM_PHASE=<rad>` / `BW_ANIM_FORCE=1` - congeleaza/forteaza ciclul
  de mers baked.
- `BW_AUTO_MOVE=<secunde>` - mers automat inainte cu sarituri periodice.
- `BW_TREES=<densitate>` - densitatea copacilor (0 = fara copaci).

## Controale

- `WASD` miscare, `Space` saritura / inot sus, `Shift` inot jos
- mouse: privire; click stanga: actiunea modului; click dreapta: construieste
- `M`, `Z`, `X`: dig, build, combat; `V`: ciclu mod; `B`: cub/sfera
- `Q`: arbaleta/sabie; `1-9`, `0`: slot inventar
- `C`: first/third person; `F`: freecam
- `I`: crafting; `T`: chat (multiplayer); `Esc`: meniu; `F5`: salvare
- `P`: alege blueprint-ul; in modul build, click dreapta il plaseaza in lume
- editor: click stanga pune, click dreapta sterge, scroll alege nivelul,
  WASD zbor, `1-0` tipul de bloc

## Moduri

- `Classic` - 5 minute, castiga cine sparge cele mai multe baloane
- `Balloon vs Player` - survival fara limita de timp
- `Sandbox` - blocuri nelimitate, fara inamici
- `Creator` - parametri de teren (seed, frecventa, warp, curba, ridge,
  densitate copaci, relief munti 1.0-20.0; implicit 3.0 = munti naturali,
  1.0 = forma de referinta)
- `Editor structuri` - grila, undo/redo, salvare/incarcare blueprint JSON

## Teren si apa

- `terrain.cpp` - pipeline-ul de referinta: domain warp, continente,
  munti domo, eroziune hidraulica cu 45 000 de picaturi, anti-spike,
  netezire termica si amplificarea RELIEF x100. Seed-ul si parametrii
  Creator sunt runtime (`terrain::SEED`, `TERRAIN_SCALE`, ...).
- `world.cpp` - suprafata infinita: harta erodata centrala + noise
  continuu, pagini de 128 m mestecate pe CPU, sapare pe coloane.
- `water.cpp` - simulare shallow-water pe aceeasi grila de 2 m: ploaie,
  rauri, lacuri, evaporare, pagini 64x64.

Amplitudinea muntilor este controlata de `terrain::RELIEF_SCALE`
(implicit 3.0). Proiectul de referinta folosea 100 (munti de kilometri);
portul BalloonWar ii aduce la un nivel natural, reglabil din Creator.

## Verificare

```bash
make test        # verificari fara OpenGL (teren, blocuri, combat, save, rig)
make test_net    # client WebSocket (ws:// si wss://) contra unui server mock
make test_server # serverul C++: clientul C++ real + clientul de protocol,
                 # pe ws:// si wss:// (31 verificari de protocol)
make bench       # benchmark ping/pong al serverului C++
make test_san    # testele sub AddressSanitizer + UndefinedBehaviorSanitizer
```

## Server de joc C++ (balloonwar-server)

Port C++ al `server/signaling_server/server.js` (`src/wsserver.cpp` +
`src/gameserver.cpp` + `src/server_main.cpp`). Acelasi protocol JSON, deci
clientii C++/Python functioneaza neschimbati.

```bash
../run_server.sh              # sau: cd cpp_port && make server && ./balloonwar-server
BALLOONWAR_SERVER_URL=ws://127.0.0.1:8765 ./balloonwar   # clientul catre serverul C++
```

- `wsserver.cpp` - WebSocket RFC 6455 scris de la zero: handshake HTTP,
  frames mascate/unmaskate, fragmentare, ping/pong/close, `poll()` cu o
  singura bucla; TLS (`wss://`) cu OpenSSL cand `TLS_CERT`/`TLS_KEY` sunt
  setate; conexiunile inchise in callback-uri sunt eliberate la finalul
  iteratiei (fara use-after-free).
- `gameserver.cpp` - auth/register cu bcrypt (`crypt_r`, hash-uri `$2b$`
  compatibile bcryptjs), camere (create/join/leave/list/ready/start),
  game loop 20 Hz cu `state_update`, anti-cheat de pozitie (max 2 m per
  input), `terrain_modify`, chat, `save_data`/`load_data`,
  `delete_account`, expirare camere.
- conturile si `player_data` se pastreaza in `BW_USERS_FILE` (implicit
  `~/.local/share/balloonwar/server_users.json`, scriere atomica); fara
  headere MySQL pe sistem, tabelele de camere/teren ramin in memorie
  (Node facea la fel cand baza de date lipsea).
- variabile: `PORT`, `BIND`, `TLS_CERT`, `TLS_KEY`, `BW_TICK_RATE`,
  `BW_BCRYPT_ROUNDS`, `BW_MAX_PLAYERS`, `BW_USERS_FILE`.

Benchmark ping/pong cu clientul C++ (`make bench`): ~34 000 msg/s fata de
~26 000 msg/s la serverul Node pe aceeasi masina (20 clienti x 2000
mesaje), adica ~+33% throughput.

## Debugging

- `BW_DEBUG=1` porneste cu overlay-ul de debug (F3 il comuta in joc):
  FPS/frame time, pozitia si camera, pagini de teren, apa, baloane,
  blocuri, stare retea, calea log-ului.
- Log persistent in `~/.local/share/balloonwar/balloonwar.log`
  (schimbabil cu `BW_LOG=/cale/log.txt`); fiecare linie are ora si nivel.
- Handler de crash: SIGSEGV/SIGABRT/SIGFPE/SIGILL/SIGBUS scriu un
  backtrace in log si pe stderr.
- `BW_GL_CHECK=1` verifica erorile OpenGL dupa fiecare cadru.
- `BW_DEBUG_ARROW=1` spawn-eaza 3 sageti fixe (inainte/up/lateral) in fata
  jucatorului, pentru verificarea orientarii mesh-ului; orientarea este
  calculata de `bw::arrowModelMatrix()` (varful mesh-ului e pe -X si este
  rotit pe direcția de zbor) si testata in `make test`.
- `make debug` construieste `balloonwar_debug` cu ASan+UBSan; rularea
  lui prinde buffer overflow, use-after-free si comportament nedefinit.
- Build-ul normal include `-g`, deci backtrace-urile au simboluri.

## Animatie scheletica (rig)

Loader-ul GLB citeste skin-ul glTF (`JOINTS_0` / `WEIGHTS_0`,
`skins` + `inverseBindMatrices`) si ierarhia completa de noduri. Personajul
din `models/characters/baiaat.glb` are 29 de oase si clipurile baked
`Idle` / `Walk` / `Run`, peste care `anim.cpp` aplica un strat procedural:

- `anim::Rig` - maparea oaselor dupa numele din Blender metarig
  (`thigh.L/R`, `shin.L/R`, `foot.L/R`, `heel.02.L/R`, `toe.L/R`,
  `upper_arm.L/R`, `forearm.L/R`, `hand.L/R`, `shoulder.L/R`,
  `spine`..`spine.006`, `breast.L/R`, `pelvis.L/R`);
- `anim::Driver` - masina de stari (`GROUND` / `AIR` / `SWIM` / `DEAD`) cu
  blend-uri netezite, aplicata per personaj (jucator + jucatori remote);
- layere in spatiul modelului (rotatii in jurul articulatiei, `pointBone`
  pentru directia unui os): saritura (tuck), cadere, aterizare cu crouch
  amortizat, inot prone (brasare crawl + flutter kick), tintire arbaleta,
  atac sabie (windup/strike/recover), flinch la damage, prabusire la moarte,
  lean in acceleratie/viraje, privirea urmareste pitch-ul camerei si
  respiratie/balans in idle;
- clipurile baked merg in reluare lenta in aer/apa si ingheata la moarte,
  ca layerele procedurale sa preia controlul;
- daca GLB-ul nu are clipuri, `Driver` sintetizeaza un ciclu de mers
  procedural (`proceduralBase`);
- orientarea modelului (fata -X in exportul Blender) si scale-ul/asezarea
  la sol sunt calculate de `anim::characterMatrix()` din bounds-ul mesh-ului
  skinned, nu din bbox-ul nodului;
- viteza ciclului urmareste viteza reala de deplasare (mai putin alunecarea
  labelor).

## Texturare procedurala (`bake.cpp`)

Personajul (`baiaat.glb`) si sageata (`arrow.glb`) nu au materiale in GLB
(mesh alb); `bake.cpp` le genereaza o textura de albedo la incarcare,
determinist, fara fisiere externe (deci re-exportul din Blender functioneaza
in continuare):

- UV-urile modelelor (unwarp automat) au insule suprapuse masiv (~9% din
  atlas); `bake::repackSceneUVs()` le reimpacheteaza inainte de upload-ul
  VBO-urilor, ca mesh-ul randat si textura sa foloseasca aceeasi mapare;
- insulele care amesteca regiuni de oase (ex. doua triunghiuri de calcai
  lipite de insula fetei) sunt separate inainte de packing, altfel culoarea
  unui membru se imprastia pe fata;
- fiecare texel primeste culoarea din pozitia 3D + normala + osul dominant:
  gluga/jacheta albastra, pantaloni gri, bocanci si manusi maro, fata bej cu
  ochi (masca elipsoidala pe partea frontala a capului) si un rim inchis
  in jurul fetei; peste culoare se adauga un grain subtil si un gradient
  vertical (luminarea o face shader-ul jocului);
- spatiul liber este umplut BFS cu culoarea celei mai apropiate insule,
  ca mipmap-urile sa nu amestece insulele cu negru (altfel personajul se
  innegreste la distanta);
- `BW_NO_BAKE=1` dezactiveaza repacking-ul si texturarea (model alb);
  `BW_DUMP_TEX=1` scrie atlasul in `/tmp/balloonwar_char_tex.ppm`;
- daca GLB-ul are deja textura (material + imagine, ca `baiaat.glb` dupa
  pictare in Blender), baker-ul este ocolit complet: se folosesc UV-urile
  si textura din fisier, fara repacking;
- UV-urile glTF adreseaza randurile imaginii in ordinea stocata (v=0 sus);
  loader-ul de scene nu mai intoarce V-ul (bug vechi care oglindea pe
  vertical orice textura reala — la ballon/spawner nu se observa, la
  personajul pictat aparea ca un mozaic). `UV_FLIP=1` ramane pentru
  asset-uri neconforme.

## PBR pe teren (`terraintex.cpp`)

Terenul foloseste texturi PBR reale din proiect, cate un strat pentru
fiecare material: nisip, iarba, pamant, stanca, stanca deschisa si zapada.

- `terraintex::generate()` incarca seturile din `assets/textures/`:
  `GroundSand005` (nisip, rough din GLOSS), `Poliigon_GrassPatchyGround_4585`
  (iarba), `GroundDirtWeedsPatchy004` (pamant), `rocks_ground_04_2k`
  (stanca + stanca deschisa) si `Snow004_2K-JPG` (zapada); fisierele 2K
  sunt reduse cu box-filter la 256 px (sau cat e `BW_TERRAIN_TEX_SIZE`);
- se folosesc **toate hartile** disponibile: albedo, normal, roughness
  (sau GLOSS inversat), AO (impachetat in alpha-ul normal map-ului),
  metallic, reflectance si displacement (height); cele fara fisier primesc
  valori neutre;
- in shader: AO scaladeaza ambientul si o parte din difuz, metallic +
  reflectance intra in F0 (metallic workflow), iar height da un parallax
  subtil (offset in UV dupa directia de vedere) peste cele doua proiectii;
- rezultatul e cache-uit in `~/.cache/balloonwar/terrain.bin` (cheia
  include dimensiunile fisierelor sursa), deci prima rulare dureaza ~1 s
  mai mult, urmatoarele sunt instant; `BW_TERRAIN_CACHE=<cale>` schimba
  cache-ul;
- poti pune texturi proprii in `assets/textures/terrain/<nume>_albedo.png`,
  `_normal.png`, `_rough.png`; ele au prioritate fata de seturile de mai sus;
- daca un set lipseste, materialul respectiv cade pe generarea procedurala
  (albedo RGB + roughness in alpha, normal map tangent, tileable);
- in shader, materialele sunt alese dupa aceleasi praguri de altitudine si
  panta ca inainte, apoi texturile sunt esantionate in doua proiectii
  (de sus pe teren plat, lateral pe pereti) ca sa nu se intinda pe pante;
- iluminarea este Cook-Torrance GGX (dielectric, F0 = 0.04) cu soare
  directional + ambient hemisferic; zapada iese usor lucioasa (roughness
  ~0.3), stanca mata (~0.6-0.8);
- `BW_TERRAIN_TEX=0` revine la paleta plata veche, `BW_TERRAIN_TEX_SIZE`
  schimba rezolutia, `BW_CAM_ELEV=<grade>` ridica camera de debug
  (impreuna cu `BW_ORBIT_DEG`) ca sa inspectezi terenul de sus.

## Limitari cunoscute

- Audio-ul foloseste `mpv`/`paplay` ca subprocese (silentios daca lipsesc);
  copiii sunt legati de parinte cu `PR_SET_PDEATHSIG`, iar SIGINT/SIGTERM/
  SIGHUP opresc muzica si salveaza inainte de iesire, deci nu raman
  procese `mpv` orfane.
- Apa este randata procedural (fara texturi PBR).
- Personajul skinned are ~145k vertecsi per mesh; in third person costul
  de randare creste (se poate folosi `BW_FAST=1` pentru teste).
- Textura personajului/sagetii este procedurala (paleta pe regiuni), nu
  pictata manual; pentru arta finala se poate pune o textura in GLB, caz
  in care baker-ul este ocolit automat (geom.texImage >= 0).
