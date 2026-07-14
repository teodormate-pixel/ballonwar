extends VoxelGeneratorScript
# =============================================================================
# VoxelGeometryGenerator — Clean SDF Terrain (Godot 4.7)
# =============================================================================
# Geometry only — no texture loading, no material creation.
# CHANNEL_SDF  (0): linear density sdf = gy - surface_y (continuous, no clamps)
# CHANNEL_TYPE (1): 0=Air 1=Grass 2=Dirt 3=Stone 4=Sand 5=Snow 6=Gravel 7=Clay
# 5 biomes: Plains, Desert, Forest, Swamp, Hills
# 3D fractal caves that breach the surface naturally
# =============================================================================

enum Mat { AIR=0, GRASS=1, DIRT=2, STONE=3, SAND=4, SNOW=5, GRAVEL=6, CLAY=7 }

# ---- Biome height ranges ----------------------------------------------------
@export var plains_hmin: float = -5.0;  @export var plains_hmax: float = 12.0
@export var desert_hmin: float = -8.0;  @export var desert_hmax: float = 8.0
@export var forest_hmin: float = 0.0;   @export var forest_hmax: float = 18.0
@export var swamp_hmin: float = -10.0;  @export var swamp_hmax: float = 5.0
@export var hills_hmin: float = 8.0;    @export var hills_hmax: float = 22.0

# ---- World parameters -------------------------------------------------------
@export var world_seed: int = 0
@export var water_level: float = 10.0
@export var terrain_freq: float = 0.004
@export var biome_freq: float = 0.0012
@export var river_freq: float = 0.012
@export var ocean_thresh: float = -0.65
@export var river_thresh: float = 0.46

# ---- Ridge / detail ---------------------------------------------------------
@export var ridge_strength: float = 0.6
@export var ridge_freq: float = 0.022

# ---- Cave parameters --------------------------------------------------------
@export var cave_enabled: bool = true
@export var cave_freq: float = 0.025
@export var cave_thresh: float = 0.06
@export var cave_min_depth: float = 6.0


func _get_used_channels_mask() -> int:
	return VoxelBuffer.CHANNEL_SDF_BIT | VoxelBuffer.CHANNEL_TYPE_BIT


func _generate_block(out: VoxelBuffer, origin: Vector3i, _lod: int) -> void:
	var size: Vector3i = out.get_size()

	var ns_h: FastNoiseLite = _perlin(world_seed + 1, terrain_freq, 6)
	var ns_b: FastNoiseLite = _perlin(world_seed + 3, biome_freq, 3)
	var ns_r: FastNoiseLite = _perlin(world_seed + 5, river_freq, 2)
	var ns_c: FastNoiseLite = _perlin(world_seed + 7, cave_freq, 3)
	var ns_d: FastNoiseLite = _perlin(world_seed + 9, 0.035, 3)
	var ns_w: FastNoiseLite = _simplex(world_seed + 11, 0.006, 2)
	var ns_g: FastNoiseLite = _perlin(world_seed + 13, ridge_freq, 5)

	for oz: int in range(size.z):
		var wz: int = origin.z + oz
		for ox: int in range(size.x):
			var wx: int = origin.x + ox
			var wxf: float = float(wx)
			var wzf: float = float(wz)

			var biome_raw: float = ns_b.get_noise_2d(wxf, wzf)
			var is_ocean: bool = biome_raw < ocean_thresh
			var h_min: float
			var h_max: float
			var curve: float
			var surface_mat: int

			if is_ocean:
				h_min = water_level - 12.0
				h_max = water_level - 3.0
				curve = 0.9
				surface_mat = Mat.SAND
			else:
				var h_mins: Array[float] = [plains_hmin, desert_hmin, forest_hmin, swamp_hmin, hills_hmin]
				var h_maxs: Array[float] = [plains_hmax, desert_hmax, forest_hmax, swamp_hmax, hills_hmax]
				var curves: Array[float] = [0.95, 0.92, 0.95, 0.90, 1.05]
				var mats:   Array[int]   = [Mat.GRASS, Mat.SAND, Mat.GRASS, Mat.CLAY, Mat.STONE]
				h_min = _blend(biome_raw, h_mins, ocean_thresh)
				h_max = _blend(biome_raw, h_maxs, ocean_thresh)
				curve = _blend(biome_raw, curves, ocean_thresh)
				surface_mat = mats[_biome_idx(biome_raw, ocean_thresh)]

			var warp_x: float = ns_w.get_noise_2d(wxf, wzf) * 12.0
			var warp_z: float = ns_w.get_noise_2d(wxf + 37.0, wzf - 23.0) * 12.0

			var base_n: float = ns_h.get_noise_2d(wxf + warp_x, wzf + warp_z)
			var norm: float = base_n * 0.5 + 0.5
			if norm < 0.0: norm = 0.0
			norm = pow(norm, curve)

			var alt_fraction: float = (h_max - 8.0) / 30.0
			var ridge_raw: float = ns_g.get_noise_2d((wxf + warp_x) * 1.3, (wzf + warp_z) * 1.3)
			var ridge_val: float = pow(absf(ridge_raw), 2.3) * ridge_strength * alt_fraction

			var detail: float = ns_d.get_noise_2d(wxf * 0.035, wzf * 0.035) * 0.08
			norm = norm + ridge_val + detail + ridge_val * 0.15 * alt_fraction

			var surface_y: float = lerpf(h_min, h_max, norm)

			var is_river: bool = false
			if not is_ocean:
				var rv: float = ns_r.get_noise_2d(wxf * 0.35, wzf * 0.35)
				if absf(rv) > river_thresh:
					is_river = true
					surface_y = minf(surface_y, water_level - (absf(rv) - river_thresh) * 15.0)

			var steep_slope: bool = false
			if not is_ocean:
				var neigh_r: float = _surface_sample(ns_h, ns_b, ns_w, ns_d, ns_g, ocean_thresh, float(wx + 2), wzf)
				var neigh_f: float = _surface_sample(ns_h, ns_b, ns_w, ns_d, ns_g, ocean_thresh, wxf, float(wz + 2))
				if absf(surface_y - neigh_r) > 4.0 or absf(surface_y - neigh_f) > 4.0:
					steep_slope = true

			var column_has_cave: bool = false
			if cave_enabled and not is_ocean:
				var d: int = int(cave_min_depth)
				while d < 90:
					if absf(ns_c.get_noise_3d(wxf, surface_y - float(d), wzf)) < cave_thresh:
						column_has_cave = true
						break
					d += 8

			for oy: int in range(size.y):
				var wy: int = origin.y + oy
				var wyf: float = float(wy)
				var sdf: float = surface_y - wyf

				if wyf < -75.0:
					sdf = 999.0

				var in_cave: bool = false
				if sdf > 0.0 and wyf >= -75.0 and column_has_cave:
					var depth: float = surface_y - wyf
					if depth > cave_min_depth:
						if absf(ns_c.get_noise_3d(wxf, wyf * 0.5, wzf)) < cave_thresh:
							sdf = -10.0
							in_cave = true

				if wyf < water_level and surface_y < water_level and not is_river and not in_cave:
					if sdf < water_level - wyf:
						sdf = water_level - wyf

				var mat: int = Mat.AIR
				if sdf > 0.0:
					var depth: float = surface_y - wyf
					if in_cave:
						mat = Mat.STONE
					elif steep_slope and depth < 8.0:
						mat = Mat.STONE
					elif depth <= 2.0:
						mat = Mat.SAND if is_ocean else surface_mat
					elif depth <= 6.0:
						mat = Mat.DIRT
					elif depth <= 10.0:
						mat = Mat.GRAVEL
					else:
						mat = Mat.STONE

				out.set_voxel_f(sdf, ox, oy, oz, VoxelBuffer.CHANNEL_SDF)
				out.set_voxel(mat, ox, oy, oz, VoxelBuffer.CHANNEL_TYPE)


func _surface_sample(ns_h: FastNoiseLite, ns_b: FastNoiseLite, ns_w: FastNoiseLite, ns_d: FastNoiseLite, ns_g: FastNoiseLite, oth: float, wxf: float, wzf: float) -> float:
	var biome_raw: float = ns_b.get_noise_2d(wxf, wzf)
	if biome_raw < oth:
		var bn: float = ns_h.get_noise_2d(wxf, wzf)
		var on: float = bn * 0.5 + 0.5
		if on < 0.0: on = 0.0
		return lerpf(water_level - 12.0, water_level - 3.0, pow(on, 0.9))

	var h_mins: Array[float] = [plains_hmin, desert_hmin, forest_hmin, swamp_hmin, hills_hmin]
	var h_maxs: Array[float] = [plains_hmax, desert_hmax, forest_hmax, swamp_hmax, hills_hmax]
	var curves: Array[float] = [0.95, 0.92, 0.95, 0.90, 1.05]

	var h_min: float = _blend(biome_raw, h_mins, oth)
	var h_max: float = _blend(biome_raw, h_maxs, oth)
	var curve: float = _blend(biome_raw, curves, oth)

	var warp_x: float = ns_w.get_noise_2d(wxf, wzf) * 12.0
	var warp_z: float = ns_w.get_noise_2d(wxf + 37.0, wzf - 23.0) * 12.0

	var bn: float = ns_h.get_noise_2d(wxf + warp_x, wzf + warp_z)
	var norm: float = bn * 0.5 + 0.5
	if norm < 0.0: norm = 0.0
	norm = pow(norm, curve)

	var alt_fraction: float = (h_max - 8.0) / 30.0
	var ridge_raw: float = ns_g.get_noise_2d((wxf + warp_x) * 1.3, (wzf + warp_z) * 1.3)
	var ridge_val: float = pow(absf(ridge_raw), 2.3) * ridge_strength * alt_fraction

	var detail: float = ns_d.get_noise_2d(wxf * 0.035, wzf * 0.035) * 0.08
	norm = norm + ridge_val + detail + ridge_val * 0.15 * alt_fraction

	return lerpf(h_min, h_max, norm)


func _biome_idx(raw: float, oth: float) -> int:
	var t: float = (raw - oth) / (1.0 - oth)
	if t <= 0.22: return 0
	if t <= 0.44: return 1
	if t <= 0.66: return 2
	if t <= 0.84: return 3
	return 4


func _blend(raw: float, values: Array, oth: float) -> float:
	var t: float = (raw - oth) / (1.0 - oth)
	var n: int = values.size()
	if n < 2:
		return values[0] if n > 0 else 0.0
	var seg: float = 1.0 / float(n - 1)
	var idx: int = int(t / seg)
	if idx < 0: idx = 0
	if idx >= n - 1: idx = n - 2
	var local_t: float = (t - float(idx) * seg) / seg
	if local_t < 0.0: local_t = 0.0
	if local_t > 1.0: local_t = 1.0
	return lerpf(values[idx], values[idx + 1], local_t)


func _perlin(seed_val: int, freq: float, octaves: int) -> FastNoiseLite:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = seed_val
	noise.frequency = freq
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.fractal_octaves = clampi(octaves, 1, 6)
	noise.fractal_gain = 0.5
	noise.fractal_lacunarity = 2.0
	return noise


func _simplex(seed_val: int, freq: float, octaves: int) -> FastNoiseLite:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = seed_val
	noise.frequency = freq
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_octaves = clampi(octaves, 1, 3)
	noise.fractal_gain = 0.5
	noise.fractal_lacunarity = 2.0
	return noise


func get_surface_height_at(wx: float, wz: float) -> float:
	var ns_h: FastNoiseLite = _perlin(world_seed + 1, terrain_freq, 6)
	var ns_b: FastNoiseLite = _perlin(world_seed + 3, biome_freq, 3)
	var ns_w: FastNoiseLite = _simplex(world_seed + 11, 0.006, 2)
	var ns_d: FastNoiseLite = _perlin(world_seed + 9, 0.035, 3)
	var ns_g: FastNoiseLite = _perlin(world_seed + 13, ridge_freq, 5)

	var biome_raw: float = ns_b.get_noise_2d(float(wx), float(wz))
	if biome_raw < ocean_thresh:
		return water_level - 8.0

	var h_mins: Array[float] = [plains_hmin, desert_hmin, forest_hmin, swamp_hmin, hills_hmin]
	var h_maxs: Array[float] = [plains_hmax, desert_hmax, forest_hmax, swamp_hmax, hills_hmax]
	var curves: Array[float] = [0.95, 0.92, 0.95, 0.90, 1.05]

	var h_min: float = _blend(biome_raw, h_mins, ocean_thresh)
	var h_max: float = _blend(biome_raw, h_maxs, ocean_thresh)
	var curve: float = _blend(biome_raw, curves, ocean_thresh)

	var warp_x: float = ns_w.get_noise_2d(float(wx), float(wz)) * 12.0
	var warp_z: float = ns_w.get_noise_2d(float(wx) + 37.0, float(wz) - 23.0) * 12.0

	var bn: float = ns_h.get_noise_2d(float(wx) + warp_x, float(wz) + warp_z)
	var norm: float = bn * 0.5 + 0.5
	if norm < 0.0: norm = 0.0
	norm = pow(norm, curve)

	var alt_fraction: float = (h_max - 8.0) / 30.0
	var ridge_raw: float = ns_g.get_noise_2d((float(wx) + warp_x) * 1.3, (float(wz) + warp_z) * 1.3)
	var ridge_val: float = pow(absf(ridge_raw), 2.3) * ridge_strength * alt_fraction

	var detail: float = ns_d.get_noise_2d(float(wx) * 0.035, float(wz) * 0.035) * 0.08
	norm = norm + ridge_val + detail + ridge_val * 0.15 * alt_fraction

	return lerpf(h_min, h_max, norm)
