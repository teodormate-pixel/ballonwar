# Project Structure

## Runtime
- `lume.tscn` is the main gameplay scene.
- `LumeMain.gd` now owns the world loading overlay and terrain progress signals.
- `teren_proceduaral.gd` handles terrain, water, caves, and chunk streaming.
- `starter_player.gd` handles movement, combat, and terrain interaction.

## Model Assets
- `models/arrow/arrow.glb`
- `models/spawner/Meshy_AI_a_ballon_spawner_mine_0526161540_texture.glb`
- `models/balloon/Meshy_AI_a_simple_balloon_0526165110_texture.glb`

## Texture Assets
- `models/textures/spawner/`
- `models/textures/balloon/`
- `models/textures/arrow/` reserved for future arrow textures

## Future Structure Assets
- `structures/` is reserved for future scene-based structures and prefabs.

## Loading Flow
- The terrain node emits `generation_progress` while chunks are being built.
- The root scene listens to that signal and hides the loading bar once `terrain_ready` fires.
- Smart cave entrances are exposed through `deschide_intrare_pestera()`.
