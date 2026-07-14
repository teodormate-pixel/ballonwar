extends VoxelGeneratorScript

enum MatType { AIR = 0, GRASS = 1, DIRT = 2, STONE = 3, SAND = 4, SNOW = 5, GRAVEL = 6, CLAY = 7 }

@export var world_seed: int = 0
@export var water_level: float = 10.0

@export var plains_hmin: float = -5.0; @export var plains_hmax: float = 12.0
@export var desert_hmin: float = -8.0; @export var desert_hmax: float = 8.0
@export var forest_hmin: float = 0.0;   @export var forest_hmax: float = 18.0
@export var swamp_hmin: float = -10.0;  @export var swamp_hmax: float = 5.0
@export var hills_hmin: float = 8.0;    @export var hills_hmax: float = 22.0
@export var snow_hmin: float = 15.0;    @export var snow_hmax: float = 25.0

@export var terrain_freq: float = 0.005
@export var biome_freq: float = 0.0012
@export var river_freq: float = 0.012
@export var ocean_thresh: float = -0.65
@export var river_thresh: float = 0.46

@export var ridge_strength: float = 0.6
@export var ridge_freq:     float = 0.022

@export var cave_enabled: bool = true
@export var cave_freq: float = 0.025
@export var cave_thresh: float = 0.06
@export var cave_min_depth: float = 6.0


func _get_used_channels_mask() -> int:
	return VoxelBuffer.CHANNEL_SDF_BIT | VoxelBuffer.CHANNEL_TYPE_BIT


func _generate_block(out_buffer: VoxelBuffer, origin: Vector3i, _lod: int) -> void:
	var sz: Vector3i = out_buffer.get_size()
	var ns_h: FastNoiseLite = _noise(world_seed + 1,  terrain_freq, 6)
	var ns_b: FastNoiseLite = _noise(world_seed + 3,  biome_freq,   3)
	var ns_r: FastNoiseLite = _noise(world_seed + 5,  river_freq,   2)
	var ns_c: FastNoiseLite = _noise(world_seed + 7,  cave_freq,    3)
	var ns_d: FastNoiseLite = _dtl(world_seed + 9,   0.035,         3)
	var ns_w: FastNoiseLite = _wrp(world_seed + 11,  0.006,         2)
	var ns_g: FastNoiseLite = _rdg(world_seed + 13,  ridge_freq,    5)

	for oz in range(sz.z):
		var wz: int = origin.z + oz
		for ox in range(sz.x):
			var wx: int = origin.x + ox
			var wxf: float = float(wx); var wzf: float = float(wz)

			var biome_raw: float = ns_b.get_noise_2d(wxf, wzf)
			var is_ocean: bool = biome_raw < ocean_thresh
			var h_min: float; var h_max: float; var curve: float; var surf_mat: int

			if is_ocean:
				h_min = water_level - 12.0; h_max = water_level - 3.0
				curve = 0.9; surf_mat = MatType.SAND
			else:
				var h_mins: Array[float] = [plains_hmin, desert_hmin, forest_hmin, swamp_hmin, hills_hmin, snow_hmin]
				var h_maxs: Array[float] = [plains_hmax, desert_hmax, forest_hmax, swamp_hmax, hills_hmax, snow_hmax]
				var curves: Array[float] = [0.95, 0.92, 0.95, 0.90, 1.05, 1.05]
				var mats:   Array[int]   = [MatType.GRASS, MatType.SAND, MatType.GRASS, MatType.CLAY, MatType.STONE, MatType.SNOW]
				h_min    = _ble(biome_raw, h_mins,  ocean_thresh)
				h_max    = _ble(biome_raw, h_maxs, ocean_thresh)
				curve    = _ble(biome_raw, curves, ocean_thresh)
				surf_mat = mats[_bix(biome_raw, ocean_thresh)]

			var warp_x: float = ns_w.get_noise_2d(wxf, wzf) * 14.0
			var warp_z: float = ns_w.get_noise_2d(wxf + 37.0, wzf - 23.0) * 14.0

			var base_n: float = ns_h.get_noise_2d((wxf + warp_x), (wzf + warp_z))
			var norm:   float = clampf(base_n * 0.5 + 0.5, 0.0, 1.0)
			norm = pow(norm, curve)

			var alt_frac:   float = clampf((h_max - 10.0) / 55.0, 0.0, 1.0)
			var ridge_raw:  float = ns_g.get_noise_2d((wxf + warp_x) * 1.3, (wzf + warp_z) * 1.3)
			var ridge:      float = pow(absf(ridge_raw), 2.3) * ridge_strength * alt_frac

			var detail: float = ns_d.get_noise_2d(wxf * 0.035, wzf * 0.035) * 0.05
			norm = clampf(norm + ridge + detail + (ridge * 0.15) * alt_frac, 0.0, 1.0)

			var surface_y: float = lerpf(h_min, h_max, norm)

			var is_river: bool = false
			if not is_ocean:
				var rv: float = ns_r.get_noise_2d(wxf * 0.35, wzf * 0.35)
				if absf(rv) > river_thresh:
					is_river = true
					surface_y = minf(surface_y, water_level - (absf(rv) - river_thresh) * 15.0)

			var slope_steep: bool = false
			if not is_ocean:
				var neigh_r: float = _surf(ns_h, ns_b, ns_w, ns_d, ns_g, ocean_thresh, float(wx + 2), wzf)
				var neigh_f: float = _surf(ns_h, ns_b, ns_w, ns_d, ns_g, ocean_thresh, wxf, float(wz + 2))
				if absf(surface_y - neigh_r) > 4.0 or absf(surface_y - neigh_f) > 4.0:
					slope_steep = true

			var col_has_cave: bool = false
			if cave_enabled and not is_ocean:
				var d: int = int(cave_min_depth)
				while d < 90:
					if absf(ns_c.get_noise_3d(wxf, surface_y - float(d), wzf)) < cave_thresh:
						col_has_cave = true; break
					d += 8

			for oy in range(sz.y):
				var wy: int = origin.y + oy; var wyf: float = float(wy)
				var sdf: float = surface_y - wyf
				if wyf < -75.0:
					sdf = 999.0
				var in_cave: bool = false
				if sdf > 0.0 and wyf >= -75.0 and col_has_cave:
					var depth: float = surface_y - wyf
					if depth > cave_min_depth:
						if absf(ns_c.get_noise_3d(wxf, wyf * 0.5, wzf)) < cave_thresh:
							sdf = -10.0; in_cave = true
				if wyf < water_level and surface_y < water_level and not is_river and not in_cave:
					sdf = maxf(sdf, water_level - wyf)

				var mat: int = MatType.AIR
				if sdf > 0.0:
					var depth: float = surface_y - wyf
					if in_cave: mat = MatType.STONE
					elif slope_steep and depth < 8.0: mat = MatType.STONE
					elif depth <= 2.0: mat = MatType.SAND if is_ocean else surf_mat
					elif depth <= 6.0: mat = MatType.DIRT
					elif depth <= 10.0: mat = MatType.GRAVEL
					else: mat = MatType.STONE

				out_buffer.set_voxel_f(sdf, ox, oy, oz, VoxelBuffer.CHANNEL_SDF)
				out_buffer.set_voxel(mat, ox, oy, oz, VoxelBuffer.CHANNEL_TYPE)


func _surf(ns_h: FastNoiseLite, ns_b: FastNoiseLite, ns_w: FastNoiseLite, ns_d: FastNoiseLite, ns_g: FastNoiseLite, oth: float, wxf: float, wzf: float) -> float:
	var biome_raw: float = ns_b.get_noise_2d(wxf, wzf)
	if biome_raw < oth:
		var bn: float = ns_h.get_noise_2d(wxf, wzf)
		return lerpf(water_level - 12.0, water_level - 3.0, pow(clampf(bn * 0.5 + 0.5, 0.0, 1.0), 0.9))

	var h_mins: Array[float] = [plains_hmin, desert_hmin, forest_hmin, swamp_hmin, hills_hmin, snow_hmin]
	var h_maxs: Array[float] = [plains_hmax, desert_hmax, forest_hmax, swamp_hmax, hills_hmax, snow_hmax]
	var curves: Array[float] = [0.95, 0.92, 0.95, 0.90, 1.05, 1.05]

	var h_min: float = _ble(biome_raw, h_mins,  oth)
	var h_max: float = _ble(biome_raw, h_maxs, oth)
	var curve: float = _ble(biome_raw, curves, oth)

	var warp_x: float = ns_w.get_noise_2d(wxf, wzf) * 14.0
	var warp_z: float = ns_w.get_noise_2d(wxf + 37.0, wzf - 23.0) * 14.0

	var bn:   float = ns_h.get_noise_2d((wxf + warp_x), (wzf + warp_z))
	var norm: float = clampf(bn * 0.5 + 0.5, 0.0, 1.0)
	norm = pow(norm, curve)

	var alt_frac:  float = clampf((h_max - 10.0) / 55.0, 0.0, 1.0)
	var ridge_raw: float = ns_g.get_noise_2d((wxf + warp_x) * 1.3, (wzf + warp_z) * 1.3)
	var ridge:     float = pow(absf(ridge_raw), 2.3) * ridge_strength * alt_frac

	var detail: float = ns_d.get_noise_2d(wxf * 0.035, wzf * 0.035) * 0.05
	norm = clampf(norm + ridge + detail + (ridge * 0.15) * alt_frac, 0.0, 1.0)

	return lerpf(h_min, h_max, norm)


func _bix(raw: float, oth: float) -> int:
	var t: float = clampf((raw - oth) / (1.0 - oth), 0.0, 1.0)
	if t <= 0.18: return 0
	elif t <= 0.36: return 1
	elif t <= 0.54: return 2
	elif t <= 0.72: return 3
	elif t <= 0.90: return 4
	return 5


func _ble(raw: float, v: Array, oth: float) -> float:
	var t: float = clampf((raw - oth) / (1.0 - oth), 0.0, 1.0)
	var n: int = v.size()
	if n < 2: return v[0] if n > 0 else 0.0
	var seg: float = 1.0 / float(n - 1)
	var idx: int = clampi(int(t / seg), 0, n - 2)
	var lt: float = clampf((t - float(idx) * seg) / seg, 0.0, 1.0)
	return lerpf(v[idx], v[idx + 1], lt)


func _noise(s: int, freq: float, oct: int) -> FastNoiseLite:
	var n: FastNoiseLite = FastNoiseLite.new()
	n.seed = s; n.frequency = freq
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.fractal_octaves = clampi(oct, 1, 6)
	n.fractal_gain = 0.5; n.fractal_lacunarity = 2.0
	return n


func _dtl(s: int, freq: float, oct: int) -> FastNoiseLite:
	var n: FastNoiseLite = FastNoiseLite.new()
	n.seed = s; n.frequency = freq
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.fractal_octaves = clampi(oct, 1, 4)
	n.fractal_gain = 0.5; n.fractal_lacunarity = 2.0
	return n


func _wrp(s: int, freq: float, oct: int) -> FastNoiseLite:
	var n: FastNoiseLite = FastNoiseLite.new()
	n.seed = s; n.frequency = freq
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_octaves = clampi(oct, 1, 3)
	n.fractal_gain = 0.5; n.fractal_lacunarity = 2.0
	return n


func _rdg(s: int, freq: float, oct: int) -> FastNoiseLite:
	var n: FastNoiseLite = FastNoiseLite.new()
	n.seed = s; n.frequency = freq
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.fractal_octaves = clampi(oct, 1, 6)
	n.fractal_gain = 0.5; n.fractal_lacunarity = 2.0
	return n


func get_surface_height_at(wx: float, wz: float) -> float:
	var ns_h: FastNoiseLite = _noise(world_seed + 1,  terrain_freq, 6)
	var ns_b: FastNoiseLite = _noise(world_seed + 3,  biome_freq,   3)
	var ns_w: FastNoiseLite = _wrp(world_seed + 11,  0.006,         2)
	var ns_d: FastNoiseLite = _dtl(world_seed + 9,   0.035,         3)
	var ns_g: FastNoiseLite = _rdg(world_seed + 13,  ridge_freq,    5)

	var biome_raw: float = ns_b.get_noise_2d(float(wx), float(wz))
	if biome_raw < ocean_thresh:
		return water_level - 10.0

	var h_mins: Array[float] = [plains_hmin, desert_hmin, forest_hmin, swamp_hmin, hills_hmin, snow_hmin]
	var h_maxs: Array[float] = [plains_hmax, desert_hmax, forest_hmax, swamp_hmax, hills_hmax, snow_hmax]
	var curves: Array[float] = [0.95, 0.92, 0.95, 0.90, 1.05, 1.05]

	var h_min: float = _ble(biome_raw, h_mins,  ocean_thresh)
	var h_max: float = _ble(biome_raw, h_maxs, ocean_thresh)
	var curve: float = _ble(biome_raw, curves, ocean_thresh)

	var warp_x: float = ns_w.get_noise_2d(float(wx), float(wz)) * 14.0
	var warp_z: float = ns_w.get_noise_2d(float(wx) + 37.0, float(wz) - 23.0) * 14.0

	var bn:   float = ns_h.get_noise_2d((float(wx) + warp_x), (float(wz) + warp_z))
	var norm: float = clampf(bn * 0.5 + 0.5, 0.0, 1.0)
	norm = pow(norm, curve)

	var alt_frac:   float = clampf((h_max - 10.0) / 55.0, 0.0, 1.0)
	var ridge_raw:  float = ns_g.get_noise_2d((float(wx) + warp_x) * 1.3, (float(wz) + warp_z) * 1.3)
	var ridge:      float = pow(absf(ridge_raw), 2.3) * ridge_strength * alt_frac

	var detail: float = ns_d.get_noise_2d(float(wx) * 0.035, float(wz) * 0.035) * 0.05
	norm = clampf(norm + ridge + detail + (ridge * 0.15) * alt_frac, 0.0, 1.0)

	return lerpf(h_min, h_max, norm)
