class_name BiomeVoxelGenerator
extends VoxelGeneratorScript

const BODY_DEPTH: float = 1.0

@export var world_seed: int = 0
@export var water_level: float = -15.0
@export var terrain_frequency: float = 0.018

@export var plains_height_min:   float = 25.0
@export var plains_height_max:   float = 45.0
@export var desert_height_min:   float = 22.0
@export var desert_height_max:   float = 38.0
@export var forest_height_min:   float = 30.0
@export var forest_height_max:   float = 55.0
@export var swamp_height_min:    float = 20.0
@export var swamp_height_max:    float = 32.0
@export var snow_height_min:     float = 55.0
@export var snow_height_max:     float = 80.0
@export var mountain_height_min: float = 70.0
@export var mountain_height_max: float = 115.0

@export var cave_enabled: bool        = true
@export var cave_worm_freq: float     = 0.025
@export var cave_worm_threshold: float = 0.04
@export var cave_cavern_freq: float   = 0.010
@export var cave_cavern_thresh: float = 0.05
@export var cave_min_depth: float     = 12.0

@export var biome_blend_freq: float    = 0.0025
@export var biome_blend_octaves: int   = 3

func _get_used_channels_mask() -> int:
	return VoxelBuffer.CHANNEL_SDF_BIT

func _generate_block(out_buffer: VoxelBuffer, origin: Vector3i, _lod: int) -> void:
	var sz: Vector3i = out_buffer.get_size()
	var ns_base   := _make_noise(world_seed + 1,  terrain_frequency, 5)
	var ns_biome  := _make_noise(world_seed + 3,  biome_blend_freq,  biome_blend_octaves)
	var ns_worm   := _make_noise(world_seed + 13, cave_worm_freq,    3)
	var ns_cavern := _make_noise(world_seed + 17, cave_cavern_freq,  2)
	for oz in range(sz.z):
		var wz: int = origin.z + oz
		for ox in range(sz.x):
			var wx: int = origin.x + ox
			var wxf: float = float(wx)
			var wzf: float = float(wz)
			var biome_raw: float = ns_biome.get_noise_2d(wxf, wzf)
			var h_min: float = _lerp_param(biome_raw, plains_height_min, desert_height_min, forest_height_min, swamp_height_min, snow_height_min, mountain_height_min)
			var h_max: float = _lerp_param(biome_raw, plains_height_max, desert_height_max, forest_height_max, swamp_height_max, snow_height_max, mountain_height_max)
			var curve: float  = _lerp_curve(biome_raw)
			var base_n: float = ns_base.get_noise_2d(wxf, wzf)
			var norm: float = clampf(base_n * 0.5 + 0.5, 0.0, 1.0)
			norm = pow(norm, curve)
			var surface_y: float = lerpf(h_min, h_max, norm)
			var col_has_cave: bool = false
			if cave_enabled:
				var d: int = int(cave_min_depth)
				while d < 90:
					if _cave_test(wxf, surface_y - float(d), wzf, ns_worm, ns_cavern):
						col_has_cave = true
						break
					d += 8
			for oy in range(sz.y):
				var wy: int = origin.y + oy
				var wyf: float = float(wy)
				var sdf: float = (surface_y - wyf) * BODY_DEPTH
				if sdf > 0.0 and col_has_cave:
					var depth: float = surface_y - wyf
					if depth > cave_min_depth and _cave_test(wxf, wyf, wzf, ns_worm, ns_cavern):
						sdf = -10.0
				out_buffer.set_voxel_f(sdf, ox, oy, oz, VoxelBuffer.CHANNEL_SDF)

func _lerp_param(raw: float, p0: float, p1: float, p2: float, p3: float, p4: float, p5: float) -> float:
	var t: float = clampf(raw, -1.0, 1.0)
	if t <= -0.60:   return _smix(p0, p1, (t + 0.60) / 0.45)
	elif t <= -0.15: return _smix(p1, p2, (t + 0.15) / 0.45)
	elif t <= 0.15:  return _smix(p2, p3, (t + 0.15) / 0.30)
	elif t <= 0.50:  return _smix(p3, p4, (t - 0.15) / 0.35)
	elif t <= 0.85:  return _smix(p4, p5, (t - 0.50) / 0.35)
	else:            return _smix(p5, p5, 0.0)

func _lerp_curve(raw: float) -> float:
	var c: Array[float] = [0.55, 0.50, 0.60, 0.45, 0.65, 0.78]
	var t: float = clampf(raw, -1.0, 1.0)
	if t <= -0.60:   return _smix(c[0], c[1], (t + 0.60) / 0.45)
	elif t <= -0.15: return _smix(c[1], c[2], (t + 0.15) / 0.45)
	elif t <= 0.15:  return _smix(c[2], c[3], (t + 0.15) / 0.30)
	elif t <= 0.50:  return _smix(c[3], c[4], (t - 0.15) / 0.35)
	elif t <= 0.85:  return _smix(c[4], c[5], (t - 0.50) / 0.35)
	return c[5]

func _smix(a: float, b: float, t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return a + (b - a) * (t * t * (3.0 - 2.0 * t))

func _cave_test(wxf: float, wyf: float, wzf: float, ns_worm: FastNoiseLite, ns_cavern: FastNoiseLite) -> bool:
	if absf(ns_worm.get_noise_3d(wxf, wyf * 0.5, wzf)) < cave_worm_threshold:
		return true
	if absf(ns_cavern.get_noise_3d(wxf * 0.3, wyf * 0.3, wzf * 0.3)) < cave_cavern_thresh:
		return true
	return false

func _make_noise(s: int, freq: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = s
	n.frequency = freq
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.fractal_octaves = clampi(octaves, 1, 6)
	n.fractal_gain = 0.5
	n.fractal_lacunarity = 2.0
	return n

static func clampi(v: int, lo: int, hi: int) -> int:
	return v if v >= lo else lo

func get_surface_height_at(wx: float, wz: float) -> float:
	var ns_base  := _make_noise(world_seed + 1, terrain_frequency, 5)
	var ns_biome := _make_noise(world_seed + 3, biome_blend_freq, biome_blend_octaves)
	var wxf: float = float(wx)
	var wzf: float = float(wz)
	var biome_raw: float = ns_biome.get_noise_2d(wxf, wzf)
	var h_min: float = _lerp_param(biome_raw, plains_height_min, desert_height_min, forest_height_min, swamp_height_min, snow_height_min, mountain_height_min)
	var h_max: float = _lerp_param(biome_raw, plains_height_max, desert_height_max, forest_height_max, swamp_height_max, snow_height_max, mountain_height_max)
	var curve: float  = _lerp_curve(biome_raw)
	var base_n: float = ns_base.get_noise_2d(wxf, wzf)
	var norm: float = clampf(base_n * 0.5 + 0.5, 0.0, 1.0)
	return lerpf(h_min, h_max, pow(norm, curve))
