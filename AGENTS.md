# Ballon War — Progress Summary

## Goal
Teren procedural neted cu biomi, sistem build/dig, structuri generate pe categorii și luptă funcțională.

## Constraints & Preferences
- Teren neted (interpolare bilineară), 7 biomi, fără găuri la border
- Culori corecte la săpare (bloc expus → culoarea blocului, nu a biomului)
- Sistem structuri: Natural (copaci, pietre), Construcții (case), Inamici (spawnere, baloane)
- Luptă: arbaletă (left click), sabie (Q + left click), mod COMBAT (X)

## Progress
### Done
- Identificat și fixat `SHADING_MODE_SHADED` → `SHADING_MODE_PER_PIXEL` (Godot 4 compat)
- Adăugat `class_name TerenProceduralTerrain` în `teren_proceduaral.gd`
- Rescris `inventar.gd` și `starter_player.gd`: `enum BlockType` local
- Ajustat parametri noise pentru relief variat (5→63 blocuri înălțime)
- Toți 7 biomii apar cu `biome_amplitude=4.0`
- LOD dezactivat (`lod_enabled=false`) — fără găuri T-junction
- `_create_chunk_surface_mesh_extended` cu `extra=1` — border sampling corect
- Precalculare coloane + interpolare bilineară locală — ~13× mai rapid
- `_process_chunk_queue`: `call_deferred` doar când coada nu e goală
- Batch 3 chunk-uri per cadru, randare 7×7 chunk-uri stabil
- **Culori la săpare**: `_surface_color_for_biome` detectează coloane modificate (`height < noise_h`) și returnează `_block_type_color(block_type)` (brown DIRT, gray STONE, etc.)
- **Luminozitate**: `chunk_material.albedo_color = Color(0.5, 0.5, 0.5)` — terenul nu mai e prea luminos
- **Combat hotkey**: KEY_X activează mod COMBAT direct (ca M pentru SAPĂ, Z pentru CONSTRUIRE)
- **System structuri**: `@export` arrays pe 3 categorii cu `_populeaza_structuri_default()` fallback
- **Algorithm structuri**: `genereaza_structuri_specifice_zonei` plasează în fiecare chunk pe bază de biomi (densitate naturală, șansă construcții, nr inamici)
- **Scene create**: Copac.tscn, Piatra.tscn, Casa.tscn, BazaMilitara.tscn

### Known Issues
- Auto-login (CredentialsLoader) schimbă scena la Meniu.tscn — testați cu `mode="custom" scene="res://lume.tscn"`
- InamicBalon creează CollisionShape3D duplicat în `_incarca_vizual_asincron`
- `_limiteaza_pozitie_pe_harta` din InamicBalon caută "TerenProcedural" (nu există) — fail-safe

## Key Decisions
- **KEY_X** pentru mod COMBAT (M=SAVE, Z=CONSTRUIRE, X=LUPTA)
- **Structuri** generate de la `genereaza_structuri_specifice_zonei` apelată în `_genereaza_singur_chunk`
- **Densitate** pe biomi: FOREST=8 naturali, SWAMP=6, HILLS=5, PLAINS=4 etc.
- **Construcții** bazate pe șansă: PLAINS=40%, HILLS=25%, FOREST=15%
- **Inamici**: SWAMP=3, FOREST/HILLS/MOUNTAINS=2, PLAINS/DESERT/SNOW=1

## Relevant Files
- `res://teren_proceduaral.gd`: ~1214 linii — structuri, culori săpare, generare
- `res://starter_player.gd`: 620 linii — KEY_X combat, SAPA/CONSTRUIRE/LUPTA
- `res://Copac.tscn`, `Piatra.tscn`, `Casa.tscn`, `BazaMilitara.tscn` — structuri demo
- `res://InamicBalon.tscn/.gd` — inamic CharacterBody3D, 100HP, `primeste_damage`
- `res://SpawnerInamici.tscn/.gd` — spawner periodic (4-8s)
- `res://SageataProiectil.tscn/.gd` — proiectil Area3D, 25 damage
- `res://lume.tscn` — scenă principală cu Teren + StarterPlayer
- `res://CredentialsLoader.gd` — autoload auto-login
