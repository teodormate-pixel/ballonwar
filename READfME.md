# BalloonWar - port Python

Portul desktop al jocului BalloonWar ruleaza pe Python 3.15, NumPy,
ModernGL si GLFW. Include gameplay-ul, terenul procedural, combatul,
salvarile, crafting-ul, audio, meniurile, Creator, editorul de structuri si
clientul multiplayer WebSocket.

Aplicatia mobila nu face parte din acest port. Serverul multiplayer existent
ramane un serviciu separat; clientul Python este compatibil cu protocolul lui.

## Rulare

```bash
cd /home/teodor/Desktop/BalloonWar/python_port
source /mnt/spatiu/balloonwar_venv/bin/activate
python -m balloonwar.main
```

Alternative:

```bash
python -m balloonwar.main --seed 42
python -m balloonwar.main --load
python -m balloonwar.main --game-mode classic
python -m balloonwar.main --game-mode balloon_vs_player
python -m balloonwar.main --game-mode sandbox
python -m balloonwar.main --mode creator
python -m balloonwar.main --mode structure_editor --no-audio
```

Dupa instalarea editabila, aceleasi optiuni sunt disponibile prin comanda
`balloonwar`. Asset-urile mari raman in checkout; pentru rulare din alt
director seteaza `BALLOONWAR_ASSET_ROOT` la directorul `python_port`.
Endpoint-ul multiplayer poate fi schimbat prin `BALLOONWAR_SERVER_URL`,
inclusiv cu un URL `wss://`.

## Moduri de joc

- `Classic`: meci de 5 minute; castiga jucatorul care strange cel mai mare
  scor spargand baloane.
- `Balloon vs Player`: survival solo sau co-op multiplayer, fara limita de
  timp, impotriva baloanelor AI.
- `Sandbox`: singleplayer sau multiplayer, fara baloane ostile si cu blocuri
  nelimitate pentru construit.

Modul singleplayer se alege din meniul `JOACA`. Pentru multiplayer, gazda il
alege inainte sa creeze sala, iar serverul sincronizeaza timerul si clasamentul.

## Controale

- `WASD`: miscare; `Space`: saritura/inot sus; `Shift`: inot jos
- mouse: privire; click stanga/dreapta: actiunea modului curent
- `M`, `Z`, `X`: dig, build, combat; `V`: ciclu mod
- `Q`: schimba arma; `B`: cub/sfera; `C`: first/third person
- `F`: freecam; `1-9`, `0`: slot inventar; `Esc`: meniu
- `I`: crafting; `T`: chat in multiplayer

Editorul de structuri expune comenzile si in meniul `Esc`; suporta salvare,
incarcare, undo/redo, dimensiunea grilei si blueprint-uri.

## Verificare

```bash
python -m pytest tests -q
python -m ruff check src tests
xvfb-run -a python -m balloonwar.tools.render_test --frames 30
```

Salvarea locala si credentialele sunt in
`~/.local/share/balloonwar/`. Detaliile tehnice si istoricul portarii sunt
in `SESSION.md`.
