# Schimbări de la ultimul commit (586eef6)

## 1. Inventar Minecraft-style (`inventar.gd`)
- Ecran full inventory overlay (tasta **I**)
- Dark overlay + panel centrat cu armură (4 sloturi decorative), HP bar, rețete crafting, grid 5 coloane, hotbar
- **Crafting**: rețete cu buton direct "Craft"
- ESC/I închide
- Mouse-ul devine vizibil când inventarul e deschis

## 2. Săgeata se înfige + ricosează (`SageataProiectil.gd`)
- La impact: `reparent()` pe corpul lovit, dezactivează fizica, rămâne 15s
- Sunet impact: `addons/crazygames/arrowhit.wav`
- La spargerea balonului: săgețile reparentate înapoi în lume cu viteză

## 3. Balon (`InamicBalon.gd`)
- Urmărește săgețile înfipte (`inregistreaza_sageata`)
- La moarte: eliberează săgețile + sunet `balloon-pop.wav` + puncte

## 4. Sunete (`starter_player.gd`)
- Tragere arbaletă: `addons/crazygames/rele.wav`
- Săpat/Construit: `res://addons/ziva_agent/audio/knock.wav`
- Helper `_reda_sunet()` — AudioStreamPlayer3D temporar

## 5. Muzică fundal (`MusicManager.gd` — autoload)
- Redă `WhatsApp Audio.mp3` la intrarea în joc, volum -12dB
- Se oprește la părăsirea scenei (`_leave_game()`)

## 6. CharacterData + CharacterSelect
- **CharacterData.gd** (autoload) — 4 personaje
- **CharacterSelect.gd** — bară 60px jos, 4 carduri Button
- **MultiplayerUI** — CharacterSelect + server list, start button fix

## 7. NetworkManager.gd
- `auth_ok` signal redus la 3 parametri
- Fix: double-auth bug
- Fix: `_auth_sent` reset
- Fix: `seed`/`name` shadow warnings
- URL: `62.171.162.154:8765`

## 8. Server VPS
- `auth_ok` fără `characters[]`
- `getAllCharacters()` eliminat
- Deployat + repornit

## 9. Fișiere noi
- `CharacterData.gd`
- `CharacterSelect.gd`
- `MusicManager.gd`
- `CHANGES.md`
