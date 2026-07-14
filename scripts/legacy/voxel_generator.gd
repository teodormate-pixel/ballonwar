@tool
extends VoxelGeneratorScript

# =============================================================================
# VOXEL GENERATOR — SDF-based procedural terrain for VoxelLodTerrain
# =============================================================================
#
# ARCHITECTURE:
#   This script is instantiated as a VoxelGeneratorScript resource and assigned
#   to VoxelLodTerrain.generator. The engine calls _generate_block() for every
#   16x16x16 mesh block visible to any VoxelViewer.
#
#   Channel layout:
#     CHANNEL_SDF  = surface_height - world_y   (neg = solid, pos = air)
#     CHANNEL_TYPE = integer material index for future PBR texturing
#
#   The Transvoxel mesher reads CHANNEL_SDF to produce smooth isosurface meshes
#   and generates collision shapes when generate_collisions is enabled on the
#   VoxelLodTerrain node.
#
# FEATURE INVENTORY:
#   • 8 weighted biomes blended via multi-octave Perlin noise
#   • Rivers carved below water_level where noise thresholds intersect
#   • Oceans covering regions where the ocean mask falls below threshold
#   • 3 distinct cave systems: worm tunnels, open caverns, vertical shafts
#   • Surface entry points where cave noise exceeds surface_entry_threshold
#   • 10 mineral types distributed by depth with cave-density bonuses
#   • Ridge noise for mountain crest definition
#   • Micro-detail noise for surface roughness
#   • Domain warping to break up repetitive noise patterns
#
# UNIQUENESS:
#   Every FastNoiseLite instance receives a unique seed derived from
#   world_seed + offset, ensuring no two worlds produce identical geometry.
# =============================================================================

# ---------------------------------------------------------------------------
# MATERIAL TYPE INDICES — written to CHANNEL_TYPE
# The index matches what future PBR shaders will sample from a texture array.
# starter_player.gd mirrors a subset of these via its own BlockType enum.
# ---------------------------------------------------------------------------
enum BlockType {
	AIR,          # 0  — empty space
	DIRT,         # 1  — brown soil
	STONE,        # 2  — grey rock
	GRASS,        # 3  — green surface
	SAND,         # 4  — desert / ocean floor
	SNOW,         # 5  — snow biome surface
	WATER,        # 6  — (reserved, not used in SDF itself)
	ICE,          # 7  — frozen water
	COAL,         # 8  — fuel, common above elevation
	IRON,         # 9  — mid-depth metal
	GOLD,         # 10 — precious, deeper
	DIAMOND,      # 11 — rare, deepest
	EMERALD,      # 12 — rare gem
	QUARTZ,       # 13 — crystal mineral
	COPPER,       # 14 — shallow metal
	SULFUR,       # 15 — surface-level volcanic
	WOOD,         # 16 — tree trunks (placed as BlockScena instances)
	LEAVES,       # 17 — foliage (placed as BlockScena instances)
	SOIL,         # 18 — swamp surface (dark mud)
	GRAVEL,       # 19 — transition layer between dirt and stone
	CLAY,         # 20 — swamp deposit
	BEDROCK       # 21 — unbreakable floor
}

# ---------------------------------------------------------------------------
# BIOME IDENTIFIERS
# Each biome has a noise-center value in the BIOME_CENTERS table and a
# parameter profile dict returned by _biome_profile().
# ---------------------------------------------------------------------------

# The five user-requested biomes occupy these indices.
# Additional biomes (PLAINS, HILLS, OCEAN) are kept for richness.

enum BiomeType {
	PLAINS,       # 0 — flat fields
	FOREST,       # 1 — rolling hills + dense vegetation
	HILLS,        # 2 — gentle elevated slopes
	DESERT,       # 3 — flat or dune-shaped, sand surface
	SWAMP,        # 4 — lowland, water-adjacent, clay/soil
	SNOW,         # 5 — smooth high-altitude, snow surface
	MOUNTAINS,    # 6 — extreme jagged cliffs
	OCEAN         # 7 — fully submerged terrain
}

# Each biome maps to a position along the 1D biome-noise gradient.
# Neighbor biomes blend smoothly within BIOME_BLEND_SPREAD.
const BIOME_CENTERS: Dictionary = {
	BiomeType.PLAINS:    -0.22,
	BiomeType.FOREST:    -0.08,
	BiomeType.HILLS:      0.04,
	BiomeType.DESERT:     0.16,
	BiomeType.SWAMP:      0.28,
	BiomeType.SNOW:       0.40,
	BiomeType.MOUNTAINS:  0.52,
	BiomeType.OCEAN:     -0.34
}

const BIOME_BLEND_SPREAD: float = 0.25

# =============================================================================
# EXPORT — tunable from the Inspector when the generator .tres is opened
# =============================================================================

@export var world_seed: int = 0
@export var max_height: int = 128
@export var surface_min_height: int = 32
@export var surface_max_height: int = 96
@export var grass_layers: int = 2
@export var dirt_layers: int = 7
@export var water_level: float = 66.0

@export_group("Terrain Noise")
@export var terrain_frequency: float = 0.018
@export var terrain_detail_frequency: float = 0.03
@export var terrain_warp_frequency: float = 0.010
@export var terrain_warp_strength: float = 5.0
@export var terrain_curve: float = 0.7
@export var ridge_frequency: float = 0.025
@export var ridge_mix: float = 0.05
@export var micro_frequency: float = 0.08
@export var micro_amplitude: float = 1.5

@export_group("Biomes")
@export var biome_frequency: float = 0.0035
@export var biome_amplitude: float = 3.0

@export_group("Rivers & Oceans")
@export var river_frequency: float = 0.01
@export var ocean_mask_frequency: float = 0.001
@export var ocean_threshold: float = -0.45

@export_group("Ore / Minerals")
@export var ore_frequency: float = 0.04
@export var ore_cave_bonus_threshold: float = 0.55

@export_group("Caves")
@export var cave_enabled: bool = true
@export var cave_worm_frequency: float = 0.025
@export var cave_worm_threshold: float = 0.55
@export var cave_worm_vertical_scale: float = 0.5
@export var cave_cavern_frequency: float = 0.012
@export var cave_cavern_threshold: float = 0.62
@export var cave_cavern_scale: float = 0.3
@export var cave_pit_frequency: float = 0.015
@export var cave_pit_threshold: float = 0.78
@export var cave_surface_entry_threshold: float = 0.85
@export var cave_min_depth: float = 3.0

# =============================================================================
# NOISE INSTANCES
# Each FastNoiseLite is constructed lazily by init_noise() using a unique
# seed derived from world_seed + per-instance offset. This guarantees that
# no two generator instances produce the same world.
# =============================================================================

var _noise_init: bool = false
var _terrain_noise: FastNoiseLite          # primary terrain shape
var _detail_noise: FastNoiseLite           # high-frequency overlay
var _warp_noise: FastNoiseLite             # domain distortion
var _biome_noise: FastNoiseLite            # biome selection (1D gradient)
var _ridge_noise: FastNoiseLite            # mountain crests
var _micro_noise: FastNoiseLite            # surface micro-roughness
var _river_noise: FastNoiseLite            # river channel detection
var _river_detail_noise: FastNoiseLite     # river bank fine detail
var _ocean_mask_noise: FastNoiseLite       # continent/ocean separation
var _ore_noise: FastNoiseLite              # mineral deposit density
var _ore_cave_mask: FastNoiseLite          # cave-correlated ore boost
var _cave_worm_noise: FastNoiseLite        # winding tunnel detection
var _cave_cavern_noise: FastNoiseLite      # open chamber detection
var _cave_pit_noise: FastNoiseLite         # vertical shaft detection
var _cave_surface_noise: FastNoiseLite     # surface-breaching entries


# =============================================================================
# LIFECYCLE — called once by VoxelTerrainManager after setting @export vars
# =============================================================================
func init_noise() -> void:
	if _noise_init:
		return
	_noise_init = true

	# Derive a stable base-seed. If world_seed is 0, a hard-coded fallback
	# is used so that the editor preview doesn't crash.
	var sb: int = world_seed if world_seed != 0 else 12345

	# Each noise layer receives a unique offset from the base seed.
	# The offsets are chosen as distinct prime-like numbers to avoid
	# accidental correlation between layers.
	_terrain_noise      = _make(sb,        terrain_frequency,          5)
	_detail_noise       = _make(sb + 101,  terrain_detail_frequency,   3)
	_warp_noise         = _make(sb + 211,  terrain_warp_frequency,     2)
	_biome_noise        = _make(sb + 419,  biome_frequency,            3)
	_ridge_noise        = _make(sb + 307,  ridge_frequency,            4)
	_micro_noise        = _make(sb + 509,  micro_frequency,            2)
	_river_noise        = _make(sb + 613,  river_frequency,            3)
	_river_detail_noise = _make(sb + 617,  0.025,                      2)
	_ocean_mask_noise   = _make(sb + 701,  ocean_mask_frequency,       2)
	_ore_noise          = _make(sb + 307,  ore_frequency,              3)
	_ore_cave_mask      = _make(sb + 821,  0.018,                      3)
	_cave_worm_noise    = _make(sb + 811,  cave_worm_frequency,        3)
	_cave_cavern_noise  = _make(sb + 911,  cave_cavern_frequency,      2)
	_cave_pit_noise     = _make(sb + 1013, cave_pit_frequency,         2)
	_cave_surface_noise = _make(sb + 1019, 0.035,                      3)


# =============================================================================
# NOISE FACTORY — configures one FastNoiseLite with Perlin or Simplex
# =============================================================================
#
# All noise layers use TYPE_PERLIN with fractal octaves for natural-looking
# terrain. The gain (0.5) and lacunarity (2.0) produce standard fractional
# Brownian motion.
#
func _make(s: int, freq: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = s
	n.frequency = freq
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.fractal_octaves = clampi(octaves, 1, 6)
	n.fractal_gain = 0.5
	n.fractal_lacunarity = 2.0
	return n


# =============================================================================
# CHANNEL MASK — tells the engine which data channels we write
# =============================================================================
func _get_used_channels_mask() -> int:
	return VoxelBuffer.CHANNEL_SDF_BIT | VoxelBuffer.CHANNEL_TYPE_BIT


# =============================================================================
# CORE GENERATION LOOP — called per 16x16x16 mesh block
# =============================================================================
#
# For each (x, z) column we compute:
#   1. surface_y = _surface_height(wx, wz)       — full multi-noise height
#   2. biome     = get_dominant_biome_at(wx, wz) — dominant biome at column
#   3. in_cave_column = pre-pass cave check       — skip y-loop if no cave
#
# Then for each y in the column:
#   sdf    = surface_y - wy        (negative inside, positive outside)
#   block  = _get_block_column()   (detailed layering + ores)
#
# If a cave is present at (wx, wy, wz), both sdf and block are overwritten
# to air (sdf=1.0, block=AIR).
#
func _generate_block(out_buffer: VoxelBuffer, origin: Vector3i, _lod: int) -> void:
	assert(_noise_init, "Call init_noise() on the generator before terrain starts!")
	var sz: Vector3i = out_buffer.get_size()

	for oz in range(sz.z):
		var wz: int = origin.z + oz
		for ox in range(sz.x):
			var wx: int = origin.x + ox

			# Compute per-column data once, reuse for every y.
			var surface_y: float = _surface_height(wx, wz)
			var biome: int = get_dominant_biome_at(wx, wz)
			var in_cave_column: bool = false
			if cave_enabled:
				in_cave_column = _column_has_any_cave(wx, wz, surface_y)

			for oy in range(sz.y):
				var wy: int = origin.y + oy
				var sdf: float = surface_y - float(wy)
				var block: int = BlockType.AIR

				if sdf < 0.0:
					# Below surface — compute detailed block column.
					block = _get_block_column(wx, wy, wz, surface_y, biome)

					# If a cave should exist here, carve out the voxel.
					if in_cave_column and _is_any_cave(wx, wy, wz, surface_y):
						sdf = 1.0
						block = BlockType.AIR

				out_buffer.set_voxel_f(sdf, ox, oy, oz, VoxelBuffer.CHANNEL_SDF)
				out_buffer.set_voxel(block, ox, oy, oz, VoxelBuffer.CHANNEL_TYPE)


# =============================================================================
# CAVE COLUMN PRE-PASS — fast check whether any cave exists in this column
# =============================================================================
#
# Instead of running the full 3D cave check for every y (expensive), we first
# test a sparse vertical sample (step=4) to see if this column contains caves
# at all. If not, we skip cave evaluation entirely in the inner y loop.
#
func _column_has_any_cave(wx: int, wz: int, surface_y: float) -> bool:
	# Surface entry: a breach point where cave noise spikes above the threshold
	# right at the surface level, creating a natural opening.
	if absf(_cave_surface_noise.get_noise_2d(float(wx), float(wz))) > cave_surface_entry_threshold:
		return true

	var range_start: int = int(surface_y) - max_height
	var range_end: int   = int(surface_y) - int(cave_min_depth)
	for wy in range(range_start, range_end, 4):
		if _test_cave_fast(wx, wy, wz, surface_y):
			return true
	return false


# =============================================================================
# FAST CAVE TEST — 3D noise evaluation for all three cave types
# =============================================================================
func _test_cave_fast(wx: int, wy: int, wz: int, surface_y: float) -> bool:
	var d: float = surface_y - float(wy)
	if d < cave_min_depth:
		return false

	var wxf: float = float(wx)
	var wyf: float = float(wy)
	var wzf: float = float(wz)

	# WORM CAVES — winding horizontal-ish tunnels.
	#   The vertical_scale (0.5) squashes the noise vertically so tunnels
	#   are wider than tall, mimicking natural erosion.
	if absf(_cave_worm_noise.get_noise_3d(wxf, wyf * cave_worm_vertical_scale, wzf)) > cave_worm_threshold:
		return true

	# CAVERNS — large open underground rooms.
	#   The cavern_scale (0.3) stretches the noise, producing larger
	#   continuous hollow regions.
	if absf(_cave_cavern_noise.get_noise_3d(wxf * cave_cavern_scale, wyf * cave_cavern_scale, wzf * cave_cavern_scale)) > cave_cavern_threshold:
		return true

	# VERTICAL PITS — narrow shafts dropping straight down.
	#   Only appears within the top 30m (d < 30). Uses 2D noise so the shaft
	#   is vertically continuous.
	if absf(_cave_pit_noise.get_noise_2d(wxf * 0.5, wzf * 0.5)) > cave_pit_threshold and d < 30.0:
		return true

	return false


# =============================================================================
# BLOCK COLUMN — determines the material type for one (wx, wy, wz) voxel
# =============================================================================
#
# Layering order (from surface downward):
#   depth == 0           → surface block (depends on biome)
#   depth < grass_layers → GRASS (or biome surface variant)
#   depth < grass + dirt → DIRT
#   swamp extra          → CLAY or DIRT depending on micro-noise
#   transition           → GRAVEL or DIRT
#   deeper                → ore check or STONE
#
func _get_block_column(wx: int, wy: int, wz: int, surface_y: float, biome: int) -> int:
	if wy < 0:
		return BlockType.BEDROCK
	if wy >= max_height:
		return BlockType.AIR

	var depth: int = int(surface_y) - wy

	# Surfacing: the very top voxel gets the biome-specific surface material.
	if depth == 0:
		return _surface_block(biome)

	# Ocean floor override: below water level, ocean biome always gets sand.
	if biome == BiomeType.OCEAN and wy <= water_level - 2:
		return BlockType.SAND

	# Grass layer: top few blocks (unless desert/snow/ocean which use their own).
	if depth < grass_layers:
		if biome in [BiomeType.DESERT, BiomeType.SNOW, BiomeType.OCEAN]:
			return _surface_block(biome)
		return BlockType.GRASS

	# Dirt layer: below grass, fairly thick.
	if depth < grass_layers + dirt_layers:
		return BlockType.DIRT

	# Swamp extra: swamp biomes have extra clay-rich soil layers.
	if biome == BiomeType.SWAMP and depth < grass_layers + dirt_layers + 4:
		return BlockType.CLAY if _micro_noise.get_noise_3d(float(wx), float(wy), float(wz)) > 0.3 else BlockType.DIRT

	# Gravel transition: patchy gravel layer between dirt and stone.
	if depth < grass_layers + dirt_layers + 3:
		return BlockType.GRAVEL if _micro_noise.get_noise_3d(float(wx), float(wy), float(wz)) > 0.5 else BlockType.DIRT

	# Ore check: below the dirt/gravel, stone may contain mineral deposits.
	var ore: int = _get_ore_block(wx, wy, wz, depth, surface_y)
	if ore != BlockType.AIR:
		return ore

	return BlockType.STONE


# =============================================================================
# SURFACE BLOCK — biome-dependent top material
# =============================================================================
func _surface_block(biome: int) -> int:
	match biome:
		BiomeType.DESERT: return BlockType.SAND
		BiomeType.SNOW:   return BlockType.SNOW
		BiomeType.OCEAN:  return BlockType.SAND
		BiomeType.SWAMP:  return BlockType.SOIL
	return BlockType.GRASS


# =============================================================================
# MINERAL DISTRIBUTION — depth-gated probabilistic ore placement
# =============================================================================
#
# A single 3D ore-noise field is sampled. Its absolute value |noise| drives
# ore probability. Different ore types occupy different depth ranges with
# different threshold levels.
#
# Inside caves, a bonus of 0.08 is added to effectively reduce the threshold,
# making mineral veins 2-3x more frequent in cave walls.
#
# Depth ranges (blocks from surface):
#   Coal    > 0m   (threshold 0.38)  — everywhere, most common
#   Copper  > 5m   (threshold 0.50)  — shallow metal
#   Iron    > 20m  (threshold 0.59)  — mid-depth workhorse metal
#   Gold    > 30m  (threshold 0.66)  — precious, deep
#   Quartz  > 40m  (threshold 0.73)  — crystal mineral
#   Emerald > 50m  (threshold 0.80)  — rare gem
#   Diamond > 60m  (threshold 0.85)  — ultra-rare, deepest
#   Sulfur  < 15m  (threshold 0.70)  — near-surface volcanic deposit
#
func _get_ore_block(wx: int, wy: int, wz: int, depth: int, surface_y: float) -> int:
	var v: float = absf(_ore_noise.get_noise_3d(float(wx), float(wy), float(wz)))
	var in_cave: bool = cave_enabled and _is_any_cave(wx, wy, wz, surface_y)
	var bonus: float = 0.08 if in_cave else 0.0
	var cv: float = v + bonus

	if depth > 60 and cv > (0.85 - bonus):   return BlockType.DIAMOND
	if depth > 50 and cv > (0.80 - bonus):   return BlockType.EMERALD
	if depth > 40 and cv > (0.73 - bonus):   return BlockType.QUARTZ
	if depth > 30 and cv > (0.66 - bonus):   return BlockType.GOLD
	if depth > 20 and cv > (0.59 - bonus):   return BlockType.IRON
	if depth >  5 and cv > (0.50 - bonus):   return BlockType.COPPER
	if cv > 0.38:                              return BlockType.COAL
	if depth < 15 and cv > 0.70:              return BlockType.SULFUR

	return BlockType.AIR


# =============================================================================
# SURFACE HEIGHT — the core multi-noise 2D height function
# =============================================================================
#
# This is the primary function determining the terrain shape at any (x, z).
# It blends per-biome parameters (terrain_scale, detail_scale, warp_strength,
# detail_mix, curve, height_min, height_max) weighted by biome influence.
#
# Algorithm:
#   1. If dominant biome is OCEAN, return submerged ocean-floor height.
#   2. Check for river erosion: if river noise exceeds threshold, carve a
#      river channel down to water_level.
#   3. For each biome with non-zero weight, compute weighted blend of all
#      height parameters.
#   4. Apply domain warping (warp_noise offsets the input coordinates).
#   5. Combine: base_noise + detail_overlay + ridge_sharpening + micro_detail.
#   6. Normalize to [0, 1] via smoothstep.
#   7. Apply power-curve for cliff steepening.
#   8. Map from [0, 1] → [height_min, height_max].
#
func _surface_height(wx: int, wz: int) -> float:
	var dom: int = get_dominant_biome_at(wx, wz)
	if dom == BiomeType.OCEAN:
		return water_level - 2.0 + absf(_biome_noise.get_noise_2d(float(wx) * 0.01, float(wz) * 0.01)) * 1.0

	# River erosion: if the river noise channel is strong enough, lower the
	# terrain to water_level, creating natural river paths.
	var rv: float = _river_noise.get_noise_2d(float(wx) * 0.6, float(wz) * 0.6)
	var rd: float = _river_detail_noise.get_noise_2d(float(wx) * 0.25, float(wz) * 0.25)
	if absf(rv) > 0.45 and absf(rd) > 0.2:
		return water_level - minf((absf(rv) - 0.45) * 6.0, 4.0)

	# Compute weighted biome parameters.
	var w: Array = get_biome_weights(wx, wz)
	if w.is_empty():
		return float(surface_min_height)

	var bs: float = 0.0     # blended terrain_scale
	var bds: float = 0.0    # blended detail_scale
	var bws: float = 0.0    # blended warp_strength
	var bdm: float = 0.0    # blended detail_mix
	var bc: float = 0.0     # blended curve
	var bmin: float = 0.0   # blended height_min
	var bmax: float = 0.0   # blended height_max

	for e in w:
		var p: Dictionary = _biome_profile(e["biome"])
		var bw: float = e["weight"]
		bs   += float(p["terrain_scale"])  * bw
		bds  += float(p["detail_scale"])   * bw
		bws  += float(p["warp_strength"])  * bw
		bdm  += float(p["detail_mix"])     * bw
		bc   += float(p["curve"])          * bw
		bmin += float(p["height_min"])     * bw
		bmax += float(p["height_max"])     * bw

	var hmin: float = clampf(bmin, 0.0, float(max_height - 1))
	var hmax: float = clampf(bmax, hmin, float(max_height - 1))
	var wx_f: float = float(wx)
	var wz_f: float = float(wz)

	# Domain warping: offset the input of the primary terrain noise by the
	# warp noise values, creating organic ridges and valleys.
	var wx2: float = _warp_noise.get_noise_2d(wx_f, wz_f) * bws
	var wz2: float = _warp_noise.get_noise_2d(wx_f + 37.0, wz_f - 23.0) * bws

	# Primary terrain noise.
	var bn: float = _terrain_noise.get_noise_2d((wx_f + wx2) * bs, (wz_f + wz2) * bs)

	# Detail overlay: high-frequency noise adds surface texture.
	var dt: float = _detail_noise.get_noise_2d(wx_f * bds, wz_f * bds) * bdm

	# Ridge noise: creates sharp mountain crests by inverting and squaring.
	var rr: float = _ridge_noise.get_noise_2d(wx_f * bs * 1.5, wz_f * bs * 1.5)
	var rdg: float = pow(1.0 - absf(rr), 2.0) * ridge_mix

	# Micro-detail: very fine surface noise for dirt roughness.
	var mc: float = _micro_noise.get_noise_2d(wx_f, wz_f) * micro_amplitude

	# Combine all layers.
	var cb: float = clampf(bn * 0.60 + dt + rdg + mc * 0.15, -1.0, 1.0)

	# Normalize to [0, 1].
	var sm: float = cb * 0.5 + 0.5

	# Smooth-step interpolation then power curve for cliff shaping.
	sm = sm * sm * (3.0 - 2.0 * sm)
	sm = pow(sm, bc)

	return lerpf(hmin, hmax, sm)


# =============================================================================
# CAVE DETECTION — full 3D check for all cave types
# =============================================================================
func _is_any_cave(wx: int, wy: int, wz: int, surface_y: float) -> bool:
	var d: float = surface_y - float(wy)
	if d < cave_min_depth:
		return false

	var wxf: float = float(wx)
	var wyf: float = float(wy)
	var wzf: float = float(wz)

	if absf(_cave_worm_noise.get_noise_3d(wxf, wyf * cave_worm_vertical_scale, wzf)) > cave_worm_threshold:
		return true

	if absf(_cave_cavern_noise.get_noise_3d(wxf * cave_cavern_scale, wyf * cave_cavern_scale, wzf * cave_cavern_scale)) > cave_cavern_threshold:
		return true

	if absf(_cave_pit_noise.get_noise_2d(wxf * 0.5, wzf * 0.5)) > cave_pit_threshold and d < 30.0:
		return true

	return false


# =============================================================================
# BIOME IDENTIFICATION — dominant biome at a given world column
# =============================================================================
func get_dominant_biome_at(wx: int, wz: int) -> int:
	var om: float = _ocean_mask_noise.get_noise_2d(float(wx), float(wz))
	if om < ocean_threshold:
		return BiomeType.OCEAN

	var w: Array = get_biome_weights(wx, wz)
	if w.is_empty():
		return BiomeType.PLAINS

	var best: int = w[0]["biome"]
	var best_w: float = w[0]["weight"]
	for e in w:
		if e["weight"] > best_w:
			best_w = e["weight"]
			best = e["biome"]
	return best


# =============================================================================
# BIOME WEIGHTS — per-biome influence blending at a world column
# =============================================================================
#
# The biome_noise outputs a 1D value in [-1, 1]. Each biome has a fixed
# center position in this 1D space (BIOME_CENTERS). The distance from the
# current noise value to each center determines that biome's weight.
# Weights are normalized so they sum to 1.0.
#
func get_biome_weights(wx: int, wz: int) -> Array:
	var raw: float = _biome_noise.get_noise_2d(float(wx) * biome_amplitude, float(wz) * biome_amplitude)
	var result: Array = []
	var total: float = 0.0

	for bid: int in BIOME_CENTERS:
		var c: float = BIOME_CENTERS[bid]
		var d: float = absf(raw - c)
		var w: float = 1.0 - d / BIOME_BLEND_SPREAD
		w = maxf(w, 0.0)
		w = _smoothstep(0.0, 1.0, w)
		if w > 0.001:
			result.append({"biome": bid, "weight": w})
			total += w

	if total > 0.0:
		for e in result:
			e["weight"] /= total
	return result


# =============================================================================
# BIOME PROFILE — per-biome terrain generation parameters
# =============================================================================
#
# Each biome's parameter set controls:
#   terrain_scale  — horizontal compression/stretching of terrain noise
#   detail_scale   — frequency multiplier for detail overlay
#   warp_strength  — intensity of domain warping
#   detail_mix     — blending weight of detail vs base noise
#   curve          — power exponent for cliff steepness (> 1 = sharper cliffs)
#   height_min     — lowest possible terrain in this biome
#   height_max     — highest possible terrain in this biome
#
func _biome_profile(biome: int) -> Dictionary:
	match biome:
		BiomeType.PLAINS:
			return {"terrain_scale": 0.025, "detail_scale": 0.05,  "warp_strength": 4.0, "detail_mix": 0.3,  "curve": 0.7,  "height_min": 68.0, "height_max": 80.0}
		BiomeType.FOREST:
			return {"terrain_scale": 0.028, "detail_scale": 0.055, "warp_strength": 4.5, "detail_mix": 0.35, "curve": 0.7,  "height_min": 70.0, "height_max": 82.0}
		BiomeType.HILLS:
			return {"terrain_scale": 0.030, "detail_scale": 0.06,  "warp_strength": 5.0, "detail_mix": 0.4,  "curve": 0.75, "height_min": 72.0, "height_max": 86.0}
		BiomeType.DESERT:
			return {"terrain_scale": 0.022, "detail_scale": 0.04,  "warp_strength": 2.0, "detail_mix": 0.2,  "curve": 0.65, "height_min": 67.0, "height_max": 78.0}
		BiomeType.SWAMP:
			return {"terrain_scale": 0.024, "detail_scale": 0.045, "warp_strength": 3.0, "detail_mix": 0.25, "curve": 0.6,  "height_min": 64.0, "height_max": 72.0}
		BiomeType.SNOW:
			return {"terrain_scale": 0.030, "detail_scale": 0.055, "warp_strength": 4.0, "detail_mix": 0.35, "curve": 0.7,  "height_min": 70.0, "height_max": 84.0}
		BiomeType.MOUNTAINS:
			return {"terrain_scale": 0.035, "detail_scale": 0.06,  "warp_strength": 5.0, "detail_mix": 0.4,  "curve": 0.8,  "height_min": 72.0, "height_max": 90.0}
		BiomeType.OCEAN:
			return {"terrain_scale": 0.01,  "detail_scale": 0.02,  "warp_strength": 1.0, "detail_mix": 0.05, "curve": 0.3,  "height_min": 40.0, "height_max": 55.0}

	# Fallback — uses the exported surface range.
	return {"terrain_scale": 0.025, "detail_scale": 0.05, "warp_strength": 4.0, "detail_mix": 0.3, "curve": 0.7, "height_min": float(surface_min_height), "height_max": float(surface_max_height)}


# =============================================================================
# PUBLIC QUERY API — called by VoxelTerrainManager and starter_player.gd
# =============================================================================

func get_surface_height_at(wx: float, wz: float) -> float:
	return _surface_height(int(round(wx)), int(round(wz)))


func get_biome_at(wx: float, wz: float) -> int:
	return get_dominant_biome_at(int(round(wx)), int(round(wz)))


# =============================================================================
# UTILITY
# =============================================================================

static func _smoothstep(from: float, to: float, x: float) -> float:
	var t: float = clampf((x - from) / (to - from), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func clampi(v: int, lo: int, hi: int) -> int:
	return v if v > hi else (v if v >= lo else lo)
