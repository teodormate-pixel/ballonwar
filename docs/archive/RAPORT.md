# Ballon War — Raport Final

## Scop
Teren procedural neted cu 7 biomi, sistem build/dig cu blocuri-scenă, structuri generate, și luptă funcțională.

## Stare Curentă — Toate feature-urile implementate

### Sistem Teren (`teren_proceduaral.gd`)
- Teren neted cu interpolare bilineară, 7 biomi (FOREST, SWAMP, PLAINS, HILLS, MOUNTAINS, DESERT, SNOW)
- Relief variat 5–63 blocuri înălțime, tranziții line între biomi
- LOD dezactivat (fără găuri T-junction)
- Batch generare 3 chunk-uri/cadru, 7×7 chunk-uri vizibile
- Culori corecte la săpare: bloc expus → culoarea materialului (DIRT, STONE etc.)

### Sistem Build/Dig
- **Plasare blocuri** (mod CONSTRUIRE — Z sau right-click): instanțiază `BlockScena.tscn` — cub individual cu coliziune (StaticBody3D + BoxShape3D + BoxMesh). Poziție snap la grid.
- **Săpare** (mod SAPĂ — M sau left-click):
  1. Detectează `BlockScena` (bloc așezat) → îl șterge + returnează în inventar
  2. Detectează structuri în grupa "Digable" (copaci, pietre, case) → le șterge
  3. Dacă nu, sapă terenul natural (sistem vechi)
- **Dig Sphere** (B): mod sferă pentru săpat volum mare

### Sistem Luptă
- **Mod COMBAT** (X): arbaletă (left-click) → proiectil `SageataProiectil.tscn` (25 damage)
- **Sabie** (Q + left-click): damage în rază 3.5 (50 damage)
- Moduri: M = SAPĂ, Z = CONSTRUIRE, X = LUPTA
- Inamici (`InamicBalon`): CharacterBody3D, 100HP
- Spawnere (`SpawnerInamici`): generează baloane la 15–30 secunde, la y+15 deasupra spawnerului

### Inventar HUD (`inventar.gd`)
- Hotbar vizual în partea de jos a ecranului
- 8 sloturi cu cărămidă colorată (placeholder pentru texturi) + număr
- Slot selectat cu bordură albă
- Taste 1–7 pentru selecție
- Mereu vizibil (fără toggle cu E)

### Tool-uri Vizuale
- **Sapă** (mod SAPĂ): mâner maro + cap gri în mâna jucătorului
- **Ciocan** (mod CONSTRUIRE): mâner maro + cap cenușiu
- **Arbaletă/Sabie** (mod COMBAT): vizibile în funcție de arma selectată (Q)
- Se pot înlocui cu modele .glb proprii (`@export model_sapa_viitor`, `model_ciocan_viitor`)

### Structuri Generate
- 3 categorii: Naturale (Copac, Piatra), Construcții (Casa, BazaMilitara), Inamici (SpawnerInamici, InamicBalon)
- Algoritm per biom: densitate variabilă, șansă construcții, număr inamici
- Construcții doar în PLAINS (50%) și HILLS (30%)
- Inamici doar în SWAMP/FOREST/MOUNTAINS
- Toate structurile naturale și construcțiile sunt în grupa "Digable" — se pot sparge cu left-click
- Coliziune (StaticBody3D) adăugată la toate structurile

## Listă Fișiere Noi / Modificate Recent

| Fișier | Rol |
|--------|-----|
| `res://starter_player.gd` | Build cu BlockScena, dig detectează blocuri+structuri, tool-uri vizuale (sapă/ciocan) |
| `res://inventar.gd` | Hotbar vizual jos-ecran cu sloturi colorate + număr |
| `res://BlockScena.gd` | Script pentru bloc individual (StaticBody3D, `block_type`) |
| `res://BlockScena.tscn` | Scenă bloc (BoxMesh 1×1×1 + BoxShape3D + StaticBody3D) |
| `res://SpawnerInamici.gd` | Spawn interval 15–30s, baloane la y+15 |
| `res://teren_proceduaral.gd` | Structuri adăugate în grupa "Digable" la generare |
| `res://lume.tscn` | Interfata Control făcut full-screen |
| `res://Copac.tscn` | Coliziune + grupat Digable |
| `res://Piatra.tscn` | Coliziune + grupat Digable |
| `res://Casa.tscn` | Coliziune + grupat Digable |
| `res://BazaMilitara.tscn` | Coliziune + grupat Digable |
| `res://InamicBalon.tscn/.gd` | Inamic funcțional |
| `res://SageataProiectil.tscn/.gd` | Proiectil 25 damage |

## Următorii Pași Recomandați

1. **Texturi în sloturi inventar** — înlocuiești `ColorRect` colorat cu `icon.texture = load("cale_poza")`
2. **Sunete + particule** — efecte la săpat, construit, tras cu arcul
3. **Health bar / mod icons** — UI mai bogat (viață, icon mod activ)
4. **Sistem crafting** — combină resurse pentru unelte/arme mai bune
5. **Salvare stare lume** — blocurile așezate să persiste între sesiuni
6. **Modele custom** — înlocuiești tool-urile generate cu .glb proprii (`model_sapa_viitor` etc.)

## Comenzi Tastatură

| Tastă | Acțiune |
|-------|---------|
| M | Mod SAPĂ |
| Z | Mod CONSTRUIRE |
| X | Mod COMBAT |
| Q | Schimbă armă (arbaletă ↔ sabie) |
| B | Toggle dig sphere (CUBE ↔ SPHERE) |
| V | Ciclu moduri (SAPĂ → CONSTRUIRE → COMBAT) |
| 1-7 | Selectează bloc în inventar |
| Scroll | Zoom third-person / FOV first-person |
| Right-click | Construiește (în mod CONSTRUIRE) |
| Left-click | Sapă / Atacă (după mod) |
