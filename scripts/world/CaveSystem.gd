class_name CaveSystem
extends Node

signal cave_mesh_ready(chunk_key: String)
signal generation_progress(progress: float)

const CHUNK_SIZE: int = 16
const MC_EDGES: Array = [
	0,1, 1,2, 2,3, 3,0,
	4,5, 5,6, 6,7, 7,4,
	0,4, 1,5, 2,6, 3,7
]

static var _shared_mc_table: Array = []
static var _mc_table_loaded: bool = false

var cave_noise_at: FastNoiseLite
var cave_noise_aniso: FastNoiseLite
var cave_noise_warp: FastNoiseLite
var cave_noise_detail: FastNoiseLite
var erosion_wear_map: Dictionary = {}

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var world_seed: int = 0
var chunk_dimensions: int = 16
var max_height_blocks: int = 128
var cave_min_y: int = 8
var cave_max_depth: int = 48
var cave_threshold: float = 0.35
var cave_enabled: bool = true

func _init() -> void:
	rng.randomize()

static func _ensure_mc_table() -> void:
	if _mc_table_loaded:
		return
	var f: FileAccess = FileAccess.open("res://resources/MarchingCubesTable.json", FileAccess.READ)
	if f == null:
		push_error("CaveSystem: Cannot open MarchingCubesTable.json")
		_mc_table_loaded = true
		return
	var json_str: String = f.get_as_text()
	var json: JSON = JSON.new()
	var err: Error = json.parse(json_str)
	if err != OK:
		push_error("CaveSystem: JSON parse error: ", json.get_error_message())
		_mc_table_loaded = true
		return
	var result = json.data
	if typeof(result) != TYPE_ARRAY:
		push_error("CaveSystem: JSON root is not an array")
		_mc_table_loaded = true
		return
	_shared_mc_table = result
	_mc_table_loaded = true

func init_noise(seed_val: int) -> void:
	world_seed = seed_val
	rng.seed = seed_val
	_ensure_mc_table()

	cave_noise_at = FastNoiseLite.new()
	cave_noise_at.noise_type = FastNoiseLite.TYPE_PERLIN
	cave_noise_at.seed = seed_val + 811
	cave_noise_at.frequency = 0.025
	cave_noise_at.fractal_octaves = 4
	cave_noise_at.fractal_gain = 0.5
	cave_noise_at.fractal_lacunarity = 2.0

	cave_noise_aniso = FastNoiseLite.new()
	cave_noise_aniso.noise_type = FastNoiseLite.TYPE_PERLIN
	cave_noise_aniso.seed = seed_val + 911
	cave_noise_aniso.frequency = 0.012
	cave_noise_aniso.fractal_octaves = 3
	cave_noise_aniso.fractal_gain = 0.5
	cave_noise_aniso.fractal_lacunarity = 2.5

	cave_noise_warp = FastNoiseLite.new()
	cave_noise_warp.noise_type = FastNoiseLite.TYPE_PERLIN
	cave_noise_warp.seed = seed_val + 1011
	cave_noise_warp.frequency = 0.008
	cave_noise_warp.fractal_octaves = 2
	cave_noise_warp.fractal_gain = 0.5
	cave_noise_warp.fractal_lacunarity = 3.0

	cave_noise_detail = FastNoiseLite.new()
	cave_noise_detail.noise_type = FastNoiseLite.TYPE_PERLIN
	cave_noise_detail.seed = seed_val + 1111
	cave_noise_detail.frequency = 0.05
	cave_noise_detail.fractal_octaves = 2
	cave_noise_detail.fractal_gain = 0.5
	cave_noise_detail.fractal_lacunarity = 2.0

func tortuous_noise_3d(x: float, y: float, z: float, flow_dir: Vector3 = Vector3.ZERO) -> float:
	var warp_x: float = cave_noise_warp.get_noise_3d(x * 0.5, y * 0.5, z * 0.5) * 8.0
	var warp_y: float = cave_noise_warp.get_noise_3d(x * 0.5 + 37.0, y * 0.5 + 11.0, z * 0.5 + 23.0) * 6.0
	var warp_z: float = cave_noise_warp.get_noise_3d(x * 0.5 + 53.0, y * 0.5 + 7.0, z * 0.5 + 41.0) * 8.0

	var sx: float = x + warp_x
	var sy: float = y + warp_y
	var sz: float = z + warp_z

	var base: float = cave_noise_at.get_noise_3d(sx, sy, sz)

	if flow_dir.length_squared() > 0.001:
		var fd: Vector3 = flow_dir.normalized()
		var aniso_freq: float = 1.0 + absf(fd.x) * 0.6 + absf(fd.y) * 0.3 + absf(fd.z) * 0.6
		var aniso: float = cave_noise_aniso.get_noise_3d(sx * aniso_freq, sy, sz * aniso_freq)
		base = lerp(base, aniso, 0.35)

	var detail: float = cave_noise_detail.get_noise_3d(sx * 1.5, sy * 1.5, sz * 1.5) * 0.2
	return clamp(base + detail, -1.0, 1.0)

func anisotropic_tortuous_value(x: float, y: float, z: float, direction: Vector3 = Vector3.ZERO) -> float:
	var n: float = tortuous_noise_3d(x, y, z, direction)
	var secondary: float = tortuous_noise_3d(x * 1.7 + 5.0, y * 1.7 + 13.0, z * 1.7 + 7.0, direction * 0.5)
	return lerp(n, secondary, 0.25)

func lsystem_generate(seed_val: int, iterations: int, base_pos: Vector3, base_dir: Vector3, max_segments: int = 120) -> Array:
	var rules: Dictionary = {
		"F": "F[+F]F[-F]",
		"X": "F[+X][-X]FX",
		"Y": "F[-Y]F[+Y]"
	}
	var axiom: String = "X"
	var current: String = axiom
	var local_rng := RandomNumberGenerator.new()
	local_rng.seed = seed_val

	for _iter in range(iterations):
		var next: String = ""
		for ch in current:
			if rules.has(ch):
				next += rules[ch]
			else:
				next += ch
		current = next
		if len(current) > 8000:
			break

	var segments: Array = []
	var stack: Array = []
	var pos: Vector3 = base_pos
	var dir: Vector3 = base_dir.normalized()
	var up: Vector3 = Vector3.UP
	var right: Vector3 = dir.cross(up).normalized()
	up = right.cross(dir).normalized()
	var step_size: float = 4.0
	var angle_h: float = deg_to_rad(22.0 + local_rng.randf_range(-5.0, 5.0))
	var angle_v: float = deg_to_rad(18.0 + local_rng.randf_range(-4.0, 4.0))
	var radius: float = 3.5
	var twist: float = 0.0

	for ch in current:
		match ch:
			'F':
				var end: Vector3 = pos + dir * step_size * (0.8 + local_rng.randf() * 0.4)
				var seg_radius: float = radius * (0.85 + local_rng.randf() * 0.3)
				var branch_angle: float = local_rng.randf_range(-12.0, 12.0)
				var branch_up: Vector3 = dir.cross(up).normalized()
				var branch_offset: Vector3 = branch_up * sin(deg_to_rad(branch_angle)) * step_size * 0.3
				var mid: Vector3 = (pos + end) * 0.5 + branch_offset
				segments.append({
					"a": pos, "b": end, "mid": mid,
					"radius": seg_radius,
					"dir": dir,
					"len": pos.distance_to(end)
				})
				if segments.size() >= max_segments:
					return segments
				pos = end
				twist += local_rng.randf_range(-5.0, 5.0)
			'+':
				var rot := Basis(Vector3.UP, deg_to_rad(angle_h + twist))
				dir = rot * dir
				right = dir.cross(up).normalized()
				up = right.cross(dir).normalized()
			'-':
				var rot := Basis(Vector3.UP, deg_to_rad(-angle_h + twist))
				dir = rot * dir
				right = dir.cross(up).normalized()
				up = right.cross(dir).normalized()
			'^':
				var axis: Vector3 = right
				var rot := Basis(axis, deg_to_rad(angle_v))
				dir = rot * dir
				up = rot * up
			'v':
				var axis: Vector3 = right
				var rot := Basis(axis, deg_to_rad(-angle_v))
				dir = rot * dir
				up = rot * up
			'[':
				stack.append({"pos": pos, "dir": dir, "up": up, "right": right, "radius": radius, "twist": twist})
				radius *= 0.65
				step_size *= 0.75
			']':
				if not stack.is_empty():
					var state: Dictionary = stack.pop_back()
					pos = state.pos
					dir = state.dir
					up = state.up
					right = state.right
					radius = state.radius
					twist = state.twist
					step_size = radius * 1.2

	return segments

func lsystem_generate_underground_river(seed_val: int, base_pos: Vector3, flow_dir: Vector3) -> Array:
	var segments: Array = []
	var local_rng := RandomNumberGenerator.new()
	local_rng.seed = seed_val + 5000
	var pos: Vector3 = base_pos
	var dir: Vector3 = flow_dir.normalized()
	var up: Vector3 = Vector3.UP
	var right: Vector3 = dir.cross(up).normalized()
	up = right.cross(dir).normalized()
	var step: float = 4.0
	var num_steps: int = 30 + local_rng.randi() % 20

	for i in range(num_steps):
		var wobble_h: float = sin(i * 0.3) * step * 0.4 + sin(i * 0.7) * step * 0.2
		var wobble_v: float = cos(i * 0.25) * step * 0.15 + sin(i * 0.5) * step * 0.08
		var h_offset: Vector3 = right * wobble_h
		var v_offset: Vector3 = Vector3.UP * wobble_v
		var end: Vector3 = pos + dir * step + h_offset + v_offset
		var r: float = 3.0 + sin(i * 0.2) * 1.0 + local_rng.randf() * 0.5
		segments.append({
			"a": pos, "b": end,
			"mid": (pos + end) * 0.5 + Vector3(wobble_h * 0.5, wobble_v * 0.3, wobble_h * 0.5),
			"radius": r,
			"dir": dir,
			"len": step
		})
		pos = end
		if local_rng.randf() < 0.08:
			var branch_r: float = r * 0.6
			var b_dir: Vector3 = (dir + right * local_rng.randf_range(-1.0, 1.0)).normalized()
			for j in range(8 + local_rng.randi() % 6):
				var b_end: Vector3 = pos + b_dir * step * 0.8
				segments.append({
					"a": pos, "b": b_end,
					"mid": (pos + b_end) * 0.5,
					"radius": branch_r * (1.0 - j * 0.06),
					"dir": b_dir,
					"len": step * 0.8
				})
				pos = b_end
				b_dir = (b_dir + Vector3(local_rng.randf_range(-0.2, 0.2), 0.0, local_rng.randf_range(-0.2, 0.2))).normalized()
		dir = (dir + Vector3(sin(i * 0.1) * 0.05, sin(i * 0.15) * 0.03, cos(i * 0.12) * 0.05)).normalized()
		right = dir.cross(up).normalized()
		up = right.cross(dir).normalized()

	return segments

func sample_cave_sdf(pos: Vector3, segments: Array, base_surface_y: float = -999.0, water_level: float = 66.0) -> float:
	var min_dist: float = 9999.0
	var has_segment: bool = false

	for seg in segments:
		var a: Vector3 = seg.a
		var b: Vector3 = seg.b
		var mid: Vector3 = seg.mid
		var seg_dir: Vector3 = seg.dir
		var radius: float = seg.radius
		var seg_len: float = a.distance_to(b)

		var ab: Vector3 = b - a
		var ap: Vector3 = pos - a
		var t: float = ap.dot(ab) / max(seg_len * seg_len, 0.0001)
		t = clamp(t, 0.0, 1.0)

		var t_smooth: float = t * t * (3.0 - 2.0 * t)
		var curve: Vector3 = mid.lerp((a + b) * 0.5, 1.0 - abs(t - 0.5) * 2.0)
		var on_curve: Vector3 = a.lerp(b, t) + (curve - (a + b) * 0.5) * (1.0 - abs(t - 0.5) * 2.0)

		var closest: Vector3 = a.lerp(b, t)

		var dist_to_path: float = pos.distance_to(closest)
		if dist_to_path > radius + 3.0:
			continue

		var noise_val: float = anisotropic_tortuous_value(pos.x, pos.y, pos.z, seg_dir)
		var radius_mod: float = 1.0 + noise_val * 0.35
		var effective_radius: float = radius * radius_mod

		var dist_adjusted: float = dist_to_path - effective_radius

		var smoothing: float = 0.6
		var junction_blend: float = 1.0
		var noise_perturb: float = anisotropic_tortuous_value(pos.x * 0.5, pos.y * 0.5, pos.z * 0.5, seg_dir) * 0.8
		var final_dist: float = dist_adjusted - noise_perturb * 0.3

		if final_dist < min_dist:
			min_dist = final_dist
			has_segment = true

	if base_surface_y > -500.0:
		var depth: float = base_surface_y - pos.y
		if depth < 3.0:
			var fade: float = clamp(depth / 3.0, 0.0, 1.0)
			var up_dist: float = pos.y - base_surface_y + 1.0
			if up_dist > 0.0:
				up_dist *= 2.0
			min_dist = max(min_dist, up_dist * (1.0 - fade * 0.5))

	if not has_segment:
		return 9999.0

	return min_dist

func carve_chunk_with_lsystem(cx: int, cz: int, height_callback: Callable, block_check_callback: Callable, block_set_callback: Callable, water_level: float) -> Array:
	if not cave_enabled:
		return []
	var key_seed: int = hash(Vector2i(cx, cz)) + world_seed
	var local_rng := RandomNumberGenerator.new()
	local_rng.seed = key_seed

	var min_x: int = cx * chunk_dimensions
	var max_x: int = min_x + chunk_dimensions - 1
	var min_z: int = cz * chunk_dimensions
	var max_z: int = min_z + chunk_dimensions - 1

	var surface_base_y: float = 0.0
	var total_samples: int = 0
	for sx in range(min_x, max_x + 1, 4):
		for sz in range(min_z, max_z + 1, 4):
			surface_base_y += height_callback.call(float(sx), float(sz))
			total_samples += 1
	if total_samples > 0:
		surface_base_y /= float(total_samples)

	var has_caves: bool = false
	var segments: Array = []
	var can_branch: bool = local_rng.randf() < 0.3

	if surface_base_y > 50.0:
		var num_roots: int = 1 if surface_base_y < 65.0 else (2 if can_branch else 1)
		for ri in range(num_roots):
			var sx: float = float(local_rng.randi_range(min_x + 2, max_x - 2))
			var sz: float = float(local_rng.randi_range(min_z + 2, max_z - 2))
			var base_h: float = height_callback.call(sx, sz)
			if base_h < 40.0:
				continue
			var start_y: float = base_h - 4.0 - local_rng.randf() * 6.0
			var start_dir: Vector3 = Vector3(local_rng.randf_range(-0.3, 0.3), -0.6 - local_rng.randf() * 0.3, local_rng.randf_range(-0.3, 0.3)).normalized()
			var start_pos: Vector3 = Vector3(sx, start_y, sz)

			var branch_segments: Array = lsystem_generate(key_seed + ri * 100, 2 + local_rng.randi() % 2, start_pos, start_dir)
			var river_segments: Array = []
			if local_rng.randf() < 0.15:
				var river_dir: Vector3 = Vector3(local_rng.randf_range(-0.5, 0.5), -0.1, local_rng.randf_range(-0.5, 0.5)).normalized()
				var river_start: Vector3 = start_pos + Vector3(local_rng.randf_range(-5.0, 5.0), -3.0, local_rng.randf_range(-5.0, 5.0))
				river_segments = lsystem_generate_underground_river(key_seed + ri * 100 + 37, river_start, river_dir)

			for seg in branch_segments:
				segments.append(seg)
			for seg in river_segments:
				segments.append(seg)

	if segments.is_empty():
		return []

	if segments.size() > 80:
		segments.resize(80)

	var carved_blocks: Array = []
	var carved_check: Dictionary = {}
	var min_sdf: Vector3 = Vector3(min_x, cave_min_y, min_z)
	var max_sdf: Vector3 = Vector3(max_x, max_height_blocks - 1, max_z)

	var col_count: int = (max_x - min_x + 1) * (max_z - min_z + 1)
	var col_idx: int = 0
	for wx in range(min_x, max_x + 1):
		for wz in range(min_z, max_z + 1):
			col_idx += 1
			if col_idx % 8 == 0:
				generation_progress.emit(float(col_idx) / float(max(col_count, 1)))
			var surface_y: float = height_callback.call(float(wx), float(wz))
			if surface_y < 30.0:
				continue
			var start_y: int = min(int(surface_y) - 2, max_height_blocks - 1)
			var end_y: int = max(cave_min_y, start_y - cave_max_depth)
			for wy in range(start_y, end_y, -1):
				var pos: Vector3 = Vector3(float(wx) + 0.5, float(wy) + 0.5, float(wz) + 0.5)
				var sdf: float = sample_cave_sdf(pos, segments, surface_y, water_level)
				if sdf < 0.0:
					if block_check_callback.call(wx, wy, wz) != 0:
						block_set_callback.call(wx, wy, wz, 0)
						carved_blocks.append({"x": wx, "y": wy, "z": wz})
						carved_check["%d,%d,%d" % [wx, wy, wz]] = true
						has_caves = true

	# Carve vertical shafts from the surface down to root segment positions
	if has_caves and not segments.is_empty() and surface_base_y > 45.0:
		var num_shafts: int = min(3, segments.size())
		for si in range(num_shafts):
			var seg: Dictionary = segments[si]
			var a: Vector3 = seg.a
			var shaft_x: int = int(round(a.x))
			var shaft_z: int = int(round(a.z))
			# Shaft is 2x2 to be easily findable
			for dx2 in range(-1, 1):
				for dz2 in range(-1, 1):
					var sx2: int = shaft_x + dx2
					var sz2: int = shaft_z + dz2
					if sx2 < min_x or sx2 > max_x or sz2 < min_z or sz2 > max_z:
						continue
					var top_y: int = int(height_callback.call(float(sx2), float(sz2)))
					if top_y < 35.0:
						continue
					var bottom_y: int = int(a.y)
					if bottom_y >= top_y:
						continue
					for wy in range(top_y, bottom_y, -1):
						var skey: String = "%d,%d,%d" % [sx2, wy, sz2]
						if not carved_check.has(skey) and wy >= cave_min_y and wy < max_height_blocks:
							if block_check_callback.call(sx2, wy, sz2) != 0:
								block_set_callback.call(sx2, wy, sz2, 0)
								carved_blocks.append({"x": sx2, "y": wy, "z": sz2})
								carved_check[skey] = true
					# Small chamber at the bottom of the shaft to ensure connection
					var chamber_y: int = bottom_y - 1
					for dxc in range(-1, 2):
						for dzc in range(-1, 2):
							var cxc: int = sx2 + dxc
							var czc: int = sz2 + dzc
							if cxc < min_x or cxc > max_x or czc < min_z or czc > max_z:
								continue
							for dyc in range(-1, 1):
								var cyc: int = chamber_y + dyc
								var ckey: String = "%d,%d,%d" % [cxc, cyc, czc]
								if not carved_check.has(ckey) and cyc >= cave_min_y and cyc < max_height_blocks:
									if block_check_callback.call(cxc, cyc, czc) != 0:
										block_set_callback.call(cxc, cyc, czc, 0)
										carved_blocks.append({"x": cxc, "y": cyc, "z": czc})
										carved_check[ckey] = true

	if not has_caves:
		return []

	var erosion_steps: int = 2
	thermal_erosion_pass(carved_check, cx, cz, block_check_callback, block_set_callback, erosion_steps)
	hydraulic_erosion_pass(carved_check, cx, cz, block_check_callback, block_set_callback, erosion_steps)

	var erosion_expand: int = 1
	sedimentation_pass(carved_check, cx, cz, block_check_callback, block_set_callback, erosion_expand)

	return carved_blocks

func thermal_erosion_pass(carved: Dictionary, cx: int, cz: int, block_check: Callable, block_set: Callable, iterations: int) -> void:
	var min_x: int = cx * chunk_dimensions
	var max_x: int = min_x + chunk_dimensions - 1
	var min_z: int = cz * chunk_dimensions
	var max_z: int = min_z + chunk_dimensions - 1
	var angle_repose: float = 0.7

	for _iter in range(iterations):
		var to_add: Array = []
		var to_remove: Array = []
		for key in carved:
			var parts: PackedStringArray = key.split(",")
			if parts.size() != 3:
				continue
			var px: int = int(parts[0])
			var py: int = int(parts[1])
			var pz: int = int(parts[2])
			if px < min_x or px > max_x or pz < min_z or pz > max_z:
				continue
			var neighbors: Array = [
				[px+1, py, pz], [px-1, py, pz],
				[px, py+1, pz], [px, py-1, pz],
				[px, py, pz+1], [px, py, pz-1]
			]
			var exposed_above: int = 0
			var exposed_below: int = 0
			for n in neighbors:
				var nx: int = n[0]; var ny: int = n[1]; var nz: int = n[2]
				var ncheck: String = "%d,%d,%d" % [nx, ny, nz]
				if carved.has(ncheck):
					if ny > py:
						exposed_above += 1
					elif ny < py:
						exposed_below += 1
			if exposed_above > 0 and exposed_below > 0 and exposed_below > exposed_above:
				var slope: float = float(exposed_below) / max(float(exposed_above + exposed_below), 0.001)
				if slope > angle_repose:
					var carve_neighbors: Array = [
						[px, py-1, pz], [px+1, py-1, pz], [px-1, py-1, pz],
						[px, py-1, pz+1], [px, py-1, pz-1]
					]
					for cn in carve_neighbors:
						var cnx: int = cn[0]; var cny: int = cn[1]; var cnz: int = cn[2]
						var cnkey: String = "%d,%d,%d" % [cnx, cny, cnz]
						if not carved.has(cnkey) and cny >= cave_min_y and cny < max_height_blocks:
							var bt: int = block_check.call(cnx, cny, cnz)
							if bt != 0:
								to_add.append({"x": cnx, "y": cny, "z": cnz, "key": cnkey})
					var drop_above: Array = [[px, py+1, pz], [px+1, py+1, pz], [px-1, py+1, pz]]
					for da in drop_above:
						var dax: int = da[0]; var day: int = da[1]; var daz: int = da[2]
						var dakey: String = "%d,%d,%d" % [dax, day, daz]
						if not carved.has(dakey) and day < max_height_blocks:
							var bt2: int = block_check.call(dax, day, daz)
							if bt2 != 0:
								to_add.append({"x": dax, "y": day, "z": daz, "key": dakey})
		for entry in to_add:
			var key: String = entry.key
			if not carved.has(key):
				block_set.call(entry.x, entry.y, entry.z, 0)
				carved[key] = true

func hydraulic_erosion_pass(carved: Dictionary, cx: int, cz: int, block_check: Callable, block_set: Callable, iterations: int) -> void:
	var min_x: int = cx * chunk_dimensions
	var max_x: int = min_x + chunk_dimensions - 1
	var min_z: int = cz * chunk_dimensions
	var max_z: int = min_z + chunk_dimensions - 1

	for _iter in range(iterations):
		var flow_map: Dictionary = {}
		for key in carved:
			var parts: PackedStringArray = key.split(",")
			if parts.size() != 3:
				continue
			var px: int = int(parts[0])
			var py: int = int(parts[1])
			var pz: int = int(parts[2])
			if px < min_x or px > max_x or pz < min_z or pz > max_z:
				continue
			var lowest: int = py
			var low_dir: Vector3i = Vector3i(0, -1, 0)
			var dirs: Array = [
				[0, -1, 0], [1, -1, 0], [-1, -1, 0],
				[0, -1, 1], [0, -1, -1]
			]
			for d in dirs:
				var nx: int = px + d[0]; var ny: int = py + d[1]; var nz: int = pz + d[2]
				var nkey: String = "%d,%d,%d" % [nx, ny, nz]
				if carved.has(nkey) and ny < lowest:
					lowest = ny
					low_dir = Vector3i(d[0], d[1], d[2])
			var flow_key: String = "%d,%d,%d" % [px + low_dir.x, py + low_dir.y, pz + low_dir.z]
			if not flow_map.has(flow_key):
				flow_map[flow_key] = 0
			flow_map[flow_key] += 1

		var to_add: Array = []
		for fkey in flow_map:
			if flow_map[fkey] >= 3:
				var parts: PackedStringArray = fkey.split(",")
				if parts.size() == 3:
					var fx: int = int(parts[0]); var fy: int = int(parts[1]); var fz: int = int(parts[2])
					if fy >= cave_min_y and fy < max_height_blocks:
						if not carved.has(fkey):
							var bt: int = block_check.call(fx, fy, fz)
							if bt != 0:
								to_add.append({"x": fx, "y": fy, "z": fz, "key": fkey})
		for entry in to_add:
			var key: String = entry.key
			if not carved.has(key):
				block_set.call(entry.x, entry.y, entry.z, 0)
				carved[key] = true

		var undercut: Array = []
		for key in carved:
			var parts: PackedStringArray = key.split(",")
			if parts.size() != 3:
				continue
			var px: int = int(parts[0]); var py: int = int(parts[1]); var pz: int = int(parts[2])
			if px < min_x or px > max_x or pz < min_z or pz > max_z:
				continue
			var above_key: String = "%d,%d,%d" % [px, py+1, pz]
			if carved.has(above_key):
				continue
			var left_key: String = "%d,%d,%d" % [px-1, py, pz]
			var right_key: String = "%d,%d,%d" % [px+1, py, pz]
			var front_key: String = "%d,%d,%d" % [px, py, pz+1]
			var back_key: String = "%d,%d,%d" % [px, py, pz-1]
			var lateral_count: int = (1 if carved.has(left_key) else 0) + (1 if carved.has(right_key) else 0) + (1 if carved.has(front_key) else 0) + (1 if carved.has(back_key) else 0)
			if lateral_count >= 2:
				var bt: int = block_check.call(px, py-1, pz)
				if bt != 0:
					var below_key: String = "%d,%d,%d" % [px, py-1, pz]
					if not carved.has(below_key) and py-1 >= cave_min_y:
						undercut.append({"x": px, "y": py-1, "z": pz, "key": below_key})
		for entry in undercut:
			var key: String = entry.key
			if not carved.has(key):
				block_set.call(entry.x, entry.y, entry.z, 0)
				carved[key] = true

func sedimentation_pass(carved: Dictionary, cx: int, cz: int, block_check: Callable, block_set: Callable, iterations: int) -> void:
	var min_x: int = cx * chunk_dimensions
	var max_x: int = min_x + chunk_dimensions - 1
	var min_z: int = cz * chunk_dimensions
	var max_z: int = min_z + chunk_dimensions - 1

	for _iter in range(iterations):
		var floor_candidates: Dictionary = {}
		for key in carved:
			var parts: PackedStringArray = key.split(",")
			if parts.size() != 3:
				continue
			var px: int = int(parts[0]); var py: int = int(parts[1]); var pz: int = int(parts[2])
			if px < min_x or px > max_x or pz < min_z or pz > max_z:
				continue
			var below_key: String = "%d,%d,%d" % [px, py-1, pz]
			if not carved.has(below_key):
				var col_key: String = "%d,%d" % [px, pz]
				if not floor_candidates.has(col_key) or py < floor_candidates[col_key]:
					floor_candidates[col_key] = py

		var neighbors: Array = [[0,0], [1,0], [-1,0], [0,1], [0,-1], [1,1], [-1,-1], [1,-1], [-1,1]]
		for col_key in floor_candidates:
			var parts2: PackedStringArray = col_key.split(",")
			if parts2.size() != 2:
				continue
			var cx2: int = int(parts2[0]); var cz2: int = int(parts2[1])
			var heights: Array = []
			for n in neighbors:
				var nx2: int = cx2 + n[0]; var nz2: int = cz2 + n[1]
				var ncol_key: String = "%d,%d" % [nx2, nz2]
				if floor_candidates.has(ncol_key):
					heights.append(floor_candidates[ncol_key])
			if heights.is_empty():
				continue
			heights.sort()
			var median: int = heights[heights.size() / 2]
			var current_floor: int = floor_candidates[col_key]
			if abs(current_floor - median) <= 1:
				continue
			if median > current_floor:
				for fy in range(current_floor + 1, median):
					var fkey: String = "%d,%d,%d" % [cx2, fy, cz2]
					if not carved.has(fkey) and fy >= cave_min_y and fy < max_height_blocks:
						block_set.call(cx2, fy, cz2, 0)
						carved[fkey] = true
			var fill_neighbors: Array = [[-1, 0], [1, 0], [0, -1], [0, 1]]
			for fn in fill_neighbors:
				var fnx: int = cx2 + fn[0]; var fnz: int = cz2 + fn[1]
				var fncol: String = "%d,%d" % [fnx, fnz]
				if floor_candidates.has(fncol) and abs(floor_candidates[fncol] - current_floor) <= 2:
					var start_fill: int = min(current_floor, floor_candidates[fncol])
					var end_fill: int = max(current_floor, floor_candidates[fncol])
					for fy2 in range(start_fill, end_fill):
						var ffkey: String = "%d,%d,%d" % [fnx, fy2, fnz]
						if not carved.has(ffkey) and fy2 >= cave_min_y and fy2 < max_height_blocks:
							block_set.call(fnx, fy2, fnz, 0)
							carved[ffkey] = true

static func extract_cave_mesh_data_static(carved: Dictionary, min_bound: Vector3i, max_bound: Vector3i) -> Dictionary:
	_ensure_mc_table()
	var verts_by_edge: Dictionary = {}
	var faces: Array = []
	var edge_keys: Dictionary = {}

	for x in range(min_bound.x, max_bound.x + 1):
		for y in range(min_bound.y, max_bound.y + 1):
			for z in range(min_bound.z, max_bound.z + 1):
				var corners: Array = []
				for ci in 8:
					var cx2: int = x + (ci & 1)
					var cy: int = y + ((ci >> 1) & 1)
					var cz2: int = z + ((ci >> 2) & 1)
					var ckey: String = "%d,%d,%d" % [cx2, cy, cz2]
					corners.append(1.0 if carved.has(ckey) else -1.0)

				var cube_code: int = 0
				for ci in 8:
					if corners[ci] > 0.0:
						cube_code |= (1 << ci)

				if cube_code == 0 or cube_code == 255:
					continue

				for ei in 12:
					var v0: int = MC_EDGES[ei * 2]
					var v1: int = MC_EDGES[ei * 2 + 1]
					var val0: float = corners[v0]
					var val1: float = corners[v1]

					if (val0 > 0.0) == (val1 > 0.0):
						continue

					var t_val: float = -val0 / max(val1 - val0, 0.0001)
					t_val = clamp(t_val, 0.05, 0.95)

					var eoffsets: Array = [
						Vector3(0,0,0), Vector3(1,0,0), Vector3(1,0,0), Vector3(0,0,0),
						Vector3(0,1,0), Vector3(1,1,0), Vector3(1,1,0), Vector3(0,1,0),
						Vector3(0,0,0), Vector3(1,0,0), Vector3(1,0,1), Vector3(0,0,1),
					]
					var eof2: Array = [
						Vector3(1,0,0), Vector3(0,0,1), Vector3(1,0,1), Vector3(0,0,1),
						Vector3(1,1,0), Vector3(0,1,1), Vector3(1,1,1), Vector3(0,1,1),
						Vector3(0,1,0), Vector3(1,1,0), Vector3(1,1,1), Vector3(0,1,1),
					]

					var ep0: Vector3 = Vector3(x, y, z) + eoffsets[ei] * 0.5
					var ep1: Vector3 = Vector3(x, y, z) + eof2[ei] * 0.5
					var vert_pos: Vector3 = ep0.lerp(ep1, t_val)

					var edge_key: String = "%d_%d" % [x + y * 256 + z * 65536, ei]
					if not verts_by_edge.has(edge_key):
						verts_by_edge[edge_key] = vert_pos
						edge_keys[edge_key] = verts_by_edge.size() - 1

				var tri_edge_indices: Array = _shared_mc_table[cube_code]
				for ti in range(0, tri_edge_indices.size(), 3):
					if ti + 2 >= tri_edge_indices.size():
						break
					var i0: int = tri_edge_indices[ti]
					var i1: int = tri_edge_indices[ti + 1]
					var i2: int = tri_edge_indices[ti + 2]
					var edge_key0: String = "%d_%d" % [x + y * 256 + z * 65536, i0]
					var edge_key1: String = "%d_%d" % [x + y * 256 + z * 65536, i1]
					var edge_key2: String = "%d_%d" % [x + y * 256 + z * 65536, i2]
					if edge_keys.has(edge_key0) and edge_keys.has(edge_key1) and edge_keys.has(edge_key2):
						faces.append(Vector3i(edge_keys[edge_key0], edge_keys[edge_key1], edge_keys[edge_key2]))

	var all_verts: Array = verts_by_edge.values()
	var vpos := PackedVector3Array()
	vpos.resize(all_verts.size())
	for i in all_verts.size():
		vpos[i] = all_verts[i] as Vector3

	return {"vertices": vpos, "faces": faces}

static func build_cave_mesh_from_data(data: Dictionary) -> ArrayMesh:
	var vpos: PackedVector3Array = data.vertices
	var faces: Array = data.faces
	if faces.is_empty() or vpos.size() < 3:
		return ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in faces:
		st.add_vertex(vpos[f.x])
		st.add_vertex(vpos[f.y])
		st.add_vertex(vpos[f.z])
	st.generate_normals()
	return st.commit()

func extract_smooth_cave_mesh(carved: Dictionary, min_bound: Vector3i, max_bound: Vector3i) -> ArrayMesh:
	var data: Dictionary = extract_cave_mesh_data_static(carved, min_bound, max_bound)
	return build_cave_mesh_from_data(data)


# ===================================================================
# Static thread-safe cave carving (no callbacks, no RenderingServer)
# ===================================================================

static func _create_thread_cave_noise(seed_val: int) -> Dictionary:
	var at := FastNoiseLite.new()
	at.noise_type = FastNoiseLite.TYPE_PERLIN
	at.seed = seed_val + 811
	at.frequency = 0.025
	at.fractal_octaves = 4
	at.fractal_gain = 0.5
	at.fractal_lacunarity = 2.0

	var aniso := FastNoiseLite.new()
	aniso.noise_type = FastNoiseLite.TYPE_PERLIN
	aniso.seed = seed_val + 911
	aniso.frequency = 0.012
	aniso.fractal_octaves = 3
	aniso.fractal_gain = 0.5
	aniso.fractal_lacunarity = 2.5

	var warp := FastNoiseLite.new()
	warp.noise_type = FastNoiseLite.TYPE_PERLIN
	warp.seed = seed_val + 1011
	warp.frequency = 0.008
	warp.fractal_octaves = 2
	warp.fractal_gain = 0.5
	warp.fractal_lacunarity = 3.0

	var detail := FastNoiseLite.new()
	detail.noise_type = FastNoiseLite.TYPE_PERLIN
	detail.seed = seed_val + 1111
	detail.frequency = 0.05
	detail.fractal_octaves = 2
	detail.fractal_gain = 0.5
	detail.fractal_lacunarity = 2.0

	return {"at": at, "aniso": aniso, "warp": warp, "detail": detail}


static func _thread_tortuous_noise_3d(x: float, y: float, z: float, flow_dir: Vector3, nd: Dictionary) -> float:
	var warp_n: FastNoiseLite = nd.warp
	var at_n: FastNoiseLite = nd.at
	var aniso_n: FastNoiseLite = nd.aniso
	var detail_n: FastNoiseLite = nd.detail

	var warp_x: float = warp_n.get_noise_3d(x * 0.5, y * 0.5, z * 0.5) * 8.0
	var warp_y: float = warp_n.get_noise_3d(x * 0.5 + 37.0, y * 0.5 + 11.0, z * 0.5 + 23.0) * 6.0
	var warp_z: float = warp_n.get_noise_3d(x * 0.5 + 53.0, y * 0.5 + 7.0, z * 0.5 + 41.0) * 8.0

	var sx: float = x + warp_x
	var sy: float = y + warp_y
	var sz: float = z + warp_z

	var base: float = at_n.get_noise_3d(sx, sy, sz)

	if flow_dir.length_squared() > 0.001:
		var fd: Vector3 = flow_dir.normalized()
		var aniso_freq: float = 1.0 + absf(fd.x) * 0.6 + absf(fd.y) * 0.3 + absf(fd.z) * 0.6
		var aniso: float = aniso_n.get_noise_3d(sx * aniso_freq, sy, sz * aniso_freq)
		base = lerp(base, aniso, 0.35)

	var detail: float = detail_n.get_noise_3d(sx * 1.5, sy * 1.5, sz * 1.5) * 0.2
	return clamp(base + detail, -1.0, 1.0)


static func _thread_aniso_val(x: float, y: float, z: float, dir: Vector3, nd: Dictionary) -> float:
	var n: float = _thread_tortuous_noise_3d(x, y, z, dir, nd)
	var sec: float = _thread_tortuous_noise_3d(x * 1.7 + 5.0, y * 1.7 + 13.0, z * 1.7 + 7.0, dir * 0.5, nd)
	return lerp(n, sec, 0.25)


static func _thread_sample_cave_sdf(pos: Vector3, segments: Array, nd: Dictionary, base_surface_y: float, water_level: float) -> float:
	var min_dist: float = 9999.0
	var has_segment: bool = false

	for seg in segments:
		var a: Vector3 = seg.a
		var b: Vector3 = seg.b
		var seg_dir: Vector3 = seg.dir
		var radius: float = seg.radius
		var seg_len: float = a.distance_to(b)

		var ab: Vector3 = b - a
		var ap: Vector3 = pos - a
		var t: float = ap.dot(ab) / max(seg_len * seg_len, 0.0001)
		t = clamp(t, 0.0, 1.0)

		var closest: Vector3 = a.lerp(b, t)

		var dist_to_path: float = pos.distance_to(closest)
		if dist_to_path > radius + 3.0:
			continue

		var noise_val: float = _thread_aniso_val(pos.x, pos.y, pos.z, seg_dir, nd)
		var radius_mod: float = 1.0 + noise_val * 0.35
		var effective_radius: float = radius * radius_mod

		var dist_adjusted: float = dist_to_path - effective_radius
		var noise_perturb: float = _thread_aniso_val(pos.x * 0.5, pos.y * 0.5, pos.z * 0.5, seg_dir, nd) * 0.8
		var final_dist: float = dist_adjusted - noise_perturb * 0.3

		if final_dist < min_dist:
			min_dist = final_dist
			has_segment = true

	if base_surface_y > -500.0:
		var depth: float = base_surface_y - pos.y
		if depth < 3.0:
			var fade: float = clamp(depth / 3.0, 0.0, 1.0)
			var up_dist: float = pos.y - base_surface_y + 1.0
			if up_dist > 0.0:
				up_dist *= 2.0
			min_dist = max(min_dist, up_dist * (1.0 - fade * 0.5))

	if not has_segment:
		return 9999.0

	return min_dist


static func compute_carved_blocks_static(params: Dictionary) -> Dictionary:
	var cx: int = params.cx
	var cz: int = params.cz
	var world_seed: int = params.world_seed
	var height_samples: Dictionary = params.height_samples
	var segments: Array = params.segments
	var chunk_dim: int = params.chunk_dimensions
	var max_h: int = params.max_height_blocks
	var cave_min: int = params.cave_min_y
	var cave_depth: int = params.cave_max_depth
	var water: float = params.water_level

	if segments.is_empty():
		return {"blocks": [], "near_surface": []}

	var nd: Dictionary = _create_thread_cave_noise(world_seed)

	var min_x: int = cx * chunk_dim
	var max_x: int = min_x + chunk_dim - 1
	var min_z: int = cz * chunk_dim
	var max_z: int = min_z + chunk_dim - 1

	var carved_blocks: Array = []
	var carved_check: Dictionary = {}
	var near_surface: Array = []

	var has_caves: bool = false

	for wx in range(min_x, max_x + 1):
		for wz in range(min_z, max_z + 1):
			var hk: String = "%d,%d" % [wx, wz]
			if not height_samples.has(hk):
				continue
			var surface_y: float = height_samples[hk]
			if surface_y < 30.0:
				continue
			var start_y: int = min(int(surface_y) - 2, max_h - 1)
			var end_y: int = max(cave_min, start_y - cave_depth)
			for wy in range(start_y, end_y, -1):
				var pos: Vector3 = Vector3(float(wx) + 0.5, float(wy) + 0.5, float(wz) + 0.5)
				var sdf: float = _thread_sample_cave_sdf(pos, segments, nd, surface_y, water)
				if sdf < 0.0:
					carved_blocks.append({"x": wx, "y": wy, "z": wz})
					carved_check["%d,%d,%d" % [wx, wy, wz]] = true
					has_caves = true

			for wy in range(start_y, start_y - 6, -1):
				var ck: String = "%d,%d,%d" % [wx, wy, wz]
				if carved_check.has(ck):
					near_surface.append({"x": wx, "y": wy, "z": wz, "surface_y": surface_y})
					break

	return {"blocks": carved_blocks, "near_surface": near_surface, "has_caves": has_caves}
