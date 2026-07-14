extends Node3D

signal terrain_ready
signal generation_progress(progress: float, loaded_chunks: int, total_chunks: int, phase: String)
signal chunk_loaded(chunk_x: int, chunk_z: int)

const CHUNK_SIZE: int = 16
const CELL_SIZE: float = 2.0
const CHUNK_WORLD: float = CHUNK_SIZE * CELL_SIZE
const VIEW_RADIUS: int = 5
const UNLOAD_RADIUS: int = 9
const BEDROCK_Y: float = -75.0
const WATER_Y: float = 15.0
const CAVE_MIN_DEPTH: float = 6.0
const MAX_CONCURRENT_GEN: int = 4

const BIOME_COUNT: int = 5
const BIOME_PLAINS: int = 0
const BIOME_OCEAN: int = 1
const BIOME_DESERT: int = 2
const BIOME_PEAKS: int = 3
const BIOME_CAVE: int = 4

const BLOCK_AIR: int = 0
const BLOCK_GRASS: int = 1
const BLOCK_DIRT: int = 2
const BLOCK_STONE: int = 3
const BLOCK_IRON: int = 4
const BLOCK_GOLD: int = 5
const BLOCK_DIAMOND: int = 6
const BLOCK_COAL: int = 7
const BLOCK_COPPER: int = 8
const BLOCK_WOOD: int = 9
const BLOCK_LEAF: int = 10

@export var world_seed: int = 0
@export var interact_distance: float = 12.0
@export var terrain_frequency: float = 0.002
@export var terrain_material: StandardMaterial3D = null

@export_group("Plains")
@export var plains_albedo: Texture2D = null
@export var plains_normal: Texture2D = null
@export var plains_roughness: Texture2D = null

@export_group("Ocean / River")
@export var ocean_albedo: Texture2D = null
@export var ocean_normal: Texture2D = null

@export_group("Desert")
@export var desert_albedo: Texture2D = null
@export var desert_normal: Texture2D = null
@export var desert_roughness: Texture2D = null

@export_group("Snow Peaks")
@export var peaks_albedo: Texture2D = null
@export var peaks_normal: Texture2D = null

@export_group("Caves")
@export var cave_enabled: bool = true

@export_group("Cave / Stone")
@export var cave_albedo: Texture2D = null
@export var cave_normal: Texture2D = null
@export var cave_roughness: Texture2D = null

var _NM: Node
var _WC: Node
var _player_ref: Node3D = null
var _chunks: Dictionary = {}
var _pending_results: Array = []
var _gen_mutex: Mutex = Mutex.new()
var _gen_queue: Dictionary = {}
var _active_gen_count: int = 0
var _queue_timer: float = 0.0
var _ready_emitted: bool = false
var _spawn_ready: bool = false
var _frozen_players: Array = []
var _unfreeze_timer: float = 0.0
var last_dug_world_pos: Vector3 = Vector3.ZERO
var _block_mats: Array[StandardMaterial3D] = []
var _biome_to_block: Array[int] = []
var _biome_ocean_mat: StandardMaterial3D = null
var _biome_desert_mat: StandardMaterial3D = null
var _biome_peaks_mat: StandardMaterial3D = null
var _water_mat: Material = null
var _terrain_ready_emitted: bool = false
var _generation_order_counter: int = 0
var _total_chunks_generated: int = 0
var _total_chunks_target: int = 0

var _cached_surface_noise: FastNoiseLite
var _cached_biome_noise: FastNoiseLite
var _cached_warp_noise: FastNoiseLite
var _cached_river_noise: FastNoiseLite
var _cached_ore_noise: FastNoiseLite
var _cached_detail_noise: FastNoiseLite
var _cached_ridge_noise: FastNoiseLite
var _cached_micro_noise: FastNoiseLite
var _cached_cave_worm: FastNoiseLite
var _cached_cave_cavern: FastNoiseLite
var _cached_cave_pit: FastNoiseLite
var _cached_cave_surface: FastNoiseLite
var _cached_ocean_mask: FastNoiseLite


func _ready() -> void:
	_NM = get_node_or_null("/root/NetworkManager")
	_WC = get_node_or_null("/root/WorldConfig")
	if world_seed == 0:
		world_seed = randi()
	if _WC and _WC.get("world_seed") and _WC.world_seed != 0:
		world_seed = _WC.world_seed
	if _WC and _WC.get("terrain_frequency"):
		terrain_frequency = _WC.terrain_frequency
	_init_all_noise()
	_build_biome_materials()
	call_deferred("_find_player")
	call_deferred("_emit_ready")
	if _NM and _NM.get("room_id") != "":
		_NM.terrain_change.connect(_on_terrain_change)


func _init_all_noise() -> void:
	_cached_surface_noise = _mk(world_seed + 1, terrain_frequency, 6)
	_cached_biome_noise = _mk(world_seed + 3, 0.0012, 3)
	_cached_warp_noise = _mk_ws(world_seed + 11, 0.006, 2)
	_cached_river_noise = _mk(world_seed + 5, 0.012, 2)
	_cached_ore_noise = _mk(world_seed + 17, 0.045, 2)
	_cached_detail_noise = _mk(world_seed + 9, 0.035, 3)
	_cached_ridge_noise = _mk(world_seed + 13, 0.022, 5)
	_cached_micro_noise = _mk(world_seed + 19, 0.08, 2)
	_cached_cave_worm = _mk(world_seed + 7, 0.025, 3)
	_cached_cave_cavern = _mk(world_seed + 23, 0.012, 2)
	_cached_cave_pit = _mk(world_seed + 29, 0.015, 2)
	_cached_cave_surface = _mk(world_seed + 31, 0.035, 3)
	_cached_ocean_mask = _mk(world_seed + 37, 0.001, 2)


func _mk(seed_val: int, freq: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_val
	n.frequency = freq
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.fractal_octaves = clampi(octaves, 1, 6)
	n.fractal_gain = 0.5
	n.fractal_lacunarity = 2.0
	return n


func _mk_ws(seed_val: int, freq: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_val
	n.frequency = freq
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_octaves = clampi(octaves, 1, 3)
	n.fractal_gain = 0.5
	n.fractal_lacunarity = 2.0
	return n


func _biome_index(br: float) -> int:
	var t: float = (br + 0.65) / 1.65
	if t <= 0.22:
		return BIOME_PLAINS
	if t <= 0.44:
		return BIOME_OCEAN
	if t <= 0.66:
		return BIOME_DESERT
	if t <= 0.84:
		return BIOME_PEAKS
	return BIOME_CAVE


func _dominant_biome(b00: int, b01: int, b10: int, b11: int) -> int:
	if b00 == b01 and b00 == b10 and b00 == b11:
		return b00
	var counts: Array[int] = [0, 0, 0, 0, 0]
	counts[b00] += 1
	counts[b01] += 1
	counts[b10] += 1
	counts[b11] += 1
	var best: int = 0
	var best_c: int = 0
	for i: int in range(BIOME_COUNT):
		if counts[i] > best_c:
			best_c = counts[i]
			best = i
	return best


func _make_pbr(base_color: Color, albedo_exp: Texture2D, normal_exp: Texture2D, rough_exp: Texture2D,
		albedo_fallback: String, normal_fallback: String, rough_fallback: String,
		disp_fallback: String = "") -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = base_color
	_try_apply_pbr(mat, albedo_exp, normal_exp, rough_exp, albedo_fallback, normal_fallback, rough_fallback)
	if not disp_fallback.is_empty():
		var dt: Texture2D = _load_tex(disp_fallback)
		if dt != null:
			mat.heightmap_enabled = true
			mat.heightmap_texture = dt
			mat.heightmap_deep_parallax = true
			mat.heightmap_min_layers = 8
			mat.heightmap_max_layers = 16
	return mat


func _build_biome_materials() -> void:
	_block_mats.clear()
	_block_mats.resize(BLOCK_LEAF + 1)
	_biome_to_block.resize(BIOME_COUNT)

	_block_mats[BLOCK_GRASS] = _make_pbr(Color(0.15, 0.55, 0.12),
		plains_albedo, plains_normal, plains_roughness,
		"res://Poliigon_GrassPatchyGround_4585/2K/Poliigon_GrassPatchyGround_4585_BaseColor.jpg",
		"res://Poliigon_GrassPatchyGround_4585/2K/Poliigon_GrassPatchyGround_4585_Normal.png",
		"res://Poliigon_GrassPatchyGround_4585/2K/Poliigon_GrassPatchyGround_4585_Roughness.jpg",
		"res://Poliigon_GrassPatchyGround_4585/2K/Poliigon_GrassPatchyGround_4585_Displacement.png")

	_block_mats[BLOCK_DIRT] = _make_pbr(Color(0.45, 0.30, 0.15),
		null, null, null,
		"res://GroundSand005/GroundSand005_COL_2K.jpg",
		"res://GroundSand005/GroundSand005_NRM_2K.jpg",
		"res://GroundSand005/GroundSand005_GLOSS_2K.jpg",
		"res://GroundSand005/GroundSand005_DISP_2K.jpg")

	_block_mats[BLOCK_STONE] = _make_pbr(Color(0.45, 0.42, 0.40),
		cave_albedo, cave_normal, cave_roughness,
		"res://rocks_ground_04_2k.blend/textures/rocks_ground_04_diff_2k.jpg",
		"res://rocks_ground_04_2k.blend/textures/rocks_ground_04_nor_gl_2k.exr",
		"res://rocks_ground_04_2k.blend/textures/rocks_ground_04_rough_2k.jpg",
		"res://rocks_ground_04_2k.blend/textures/rocks_ground_04_disp_2k.png")

	_block_mats[BLOCK_COAL] = _make_pbr(Color(0.15, 0.15, 0.15),
		null, null, null, "", "", "")
	_block_mats[BLOCK_COAL].roughness = 0.95

	_block_mats[BLOCK_IRON] = _make_pbr(Color(0.55, 0.45, 0.35),
		null, null, null, "", "", "")
	_block_mats[BLOCK_IRON].metallic = 0.3

	_block_mats[BLOCK_COPPER] = _make_pbr(Color(0.72, 0.45, 0.20),
		null, null, null, "", "", "")
	_block_mats[BLOCK_COPPER].metallic = 0.4

	_block_mats[BLOCK_GOLD] = _make_pbr(Color(0.85, 0.65, 0.12),
		null, null, null, "", "", "")
	_block_mats[BLOCK_GOLD].metallic = 0.7
	_block_mats[BLOCK_GOLD].roughness = 0.25

	_block_mats[BLOCK_DIAMOND] = _make_pbr(Color(0.20, 0.80, 0.75),
		null, null, null, "", "", "")
	_block_mats[BLOCK_DIAMOND].metallic = 0.5
	_block_mats[BLOCK_DIAMOND].roughness = 0.1

	_block_mats[BLOCK_WOOD] = _make_pbr(Color(0.35, 0.22, 0.10),
		null, null, null, "", "", "")

	_block_mats[BLOCK_LEAF] = _make_pbr(Color(0.10, 0.45, 0.08),
		null, null, null, "", "", "")
	_block_mats[BLOCK_LEAF].transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	_block_mats[BLOCK_LEAF].albedo_color.a = 0.9

	var m_snow := _make_pbr(Color(0.92, 0.92, 0.96),
		peaks_albedo, peaks_normal, null,
		"res://Snow004_2K-JPG/Snow004_2K-JPG_Color.jpg",
		"res://Snow004_2K-JPG/Snow004_2K-JPG_NormalDX.jpg",
		"res://Snow004_2K-JPG/Snow004_2K-JPG_Roughness.jpg",
		"res://Snow004_2K-JPG/Snow004_2K-JPG_Displacement.jpg")

	var m_ocean := StandardMaterial3D.new()
	if ResourceLoader.exists("res://water.tres"):
		var loaded: StandardMaterial3D = load("res://water.tres") as StandardMaterial3D
		if loaded != null:
			m_ocean = loaded.duplicate()
	m_ocean.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	m_ocean.albedo_color.a = 0.85

	var m_sand := _make_pbr(Color(0.85, 0.75, 0.40),
		desert_albedo, desert_normal, desert_roughness,
		"res://GroundSand005/GroundSand005_COL_2K.jpg",
		"res://GroundSand005/GroundSand005_NRM_2K.jpg",
		"res://GroundSand005/GroundSand005_GLOSS_2K.jpg",
		"res://GroundSand005/GroundSand005_DISP_2K.jpg")

	_biome_to_block[BIOME_PLAINS] = BLOCK_GRASS
	_biome_to_block[BIOME_OCEAN] = -1
	_biome_to_block[BIOME_DESERT] = -2
	_biome_to_block[BIOME_PEAKS] = -3
	_biome_to_block[BIOME_CAVE] = BLOCK_STONE

	_biome_ocean_mat = m_ocean
	_biome_desert_mat = m_sand
	_biome_peaks_mat = m_snow

	_water_mat = load("res://water.tres") if ResourceLoader.exists("res://water.tres") else null


func _try_apply_pbr(mat: StandardMaterial3D, albedo_exp: Texture2D, normal_exp: Texture2D, rough_exp: Texture2D,
		albedo_fallback: String, normal_fallback: String, rough_fallback: String) -> void:
	if albedo_exp != null:
		mat.albedo_texture = albedo_exp
	elif not albedo_fallback.is_empty():
		var t := _load_tex(albedo_fallback)
		if t != null:
			mat.albedo_texture = t
	if normal_exp != null:
		mat.normal_enabled = true
		mat.normal_texture = normal_exp
	elif not normal_fallback.is_empty():
		var t := _load_tex(normal_fallback)
		if t != null:
			mat.normal_enabled = true
			mat.normal_texture = t
	if rough_exp != null:
		mat.roughness_texture = rough_exp
	elif not rough_fallback.is_empty():
		var t := _load_tex(rough_fallback)
		if t != null:
			mat.roughness_texture = t


func _load_tex(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var ext: String = path.get_extension().to_lower()
	if ext in ["exr", "tiff", "tif"]:
		var img: Image = Image.new()
		var err: Error = img.load(path)
		if err != OK:
			return null
		return ImageTexture.create_from_image(img)
	return load(path) as Texture2D


func _emit_ready() -> void:
	if _ready_emitted:
		return
	_ready_emitted = true
	terrain_ready.emit()


func _find_player() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var root := tree.root
	if root == null:
		return
	var lume := root.get_node_or_null("Lume")
	if lume == null:
		return
	var starter := lume.get_node_or_null("StarterPlayer")
	if starter != null and starter is CharacterBody3D:
		_player_ref = starter as Node3D
		return
	var players := lume.get_node_or_null("Players")
	if players != null:
		for child: Node in players.get_children():
			if child is CharacterBody3D:
				_player_ref = child as Node3D
				return
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		_player_ref = cam


func _process(delta: float) -> void:
	_process_pending_results()
	if _player_ref == null:
		_find_player()
		return
	_queue_timer += delta
	if _queue_timer < 0.15:
		return
	_queue_timer = 0.0
	var ppos: Vector3 = _player_ref.global_position
	var cx: int = int(floor(ppos.x / CHUNK_WORLD))
	var cz: int = int(floor(ppos.z / CHUNK_WORLD))
	_update_chunks(cx, cz)
	_tick_frozen(delta)


func _update_chunks(center_x: int, center_z: int) -> void:
	var to_keep: Dictionary = {}
	for dx: int in range(-VIEW_RADIUS, VIEW_RADIUS + 1):
		for dz: int in range(-VIEW_RADIUS, VIEW_RADIUS + 1):
			var kx: int = center_x + dx
			var kz: int = center_z + dz
			var key: String = str(kx) + "," + str(kz)
			to_keep[key] = true
			if not _chunks.has(key) and not _gen_queue.has(key):
				if _active_gen_count >= MAX_CONCURRENT_GEN:
					_gen_queue[key] = true
					continue
				_gen_queue[key] = true
				_generate_chunk_async(kx, kz)
	for key: String in _chunks.keys():
		if not to_keep.has(key):
			var parts: PackedStringArray = key.split(",")
			var kx: int = int(parts[0])
			var kz: int = int(parts[1])
			var cdx: int = kx - center_x
			var cdz: int = kz - center_z
			if abs(cdx) > UNLOAD_RADIUS or abs(cdz) > UNLOAD_RADIUS:
				var entry: Dictionary = _chunks[key]
				if entry.has("node") and is_instance_valid(entry["node"]):
					entry["node"].queue_free()
				if entry.has("water_node") and is_instance_valid(entry["water_node"]):
					entry["water_node"].queue_free()
				_chunks.erase(key)


func _generate_chunk_async(cx: int, cz: int) -> void:
	_active_gen_count += 1
	var callable := Callable(self, "_thread_generate").bind(cx, cz, world_seed, terrain_frequency)
	WorkerThreadPool.add_task(callable, true, "chunk_gen")


func _thread_generate(cx: int, cz: int, _seed_val: int, _freq: float) -> void:
	var ox: float = float(cx) * CHUNK_WORLD
	var oz: float = float(cz) * CHUNK_WORLD
	var nv: int = CHUNK_SIZE + 1

	var hns := _cached_surface_noise
	var bns := _cached_biome_noise
	var wns := _cached_warp_noise
	var rns := _cached_ridge_noise
	var dns := _cached_detail_noise
	var riv := _cached_river_noise
	var cns_worm := _cached_cave_worm
	var cns_cavern := _cached_cave_cavern
	var cns_pit := _cached_cave_pit
	var oms := _cached_ocean_mask

	var heights: PackedFloat32Array = PackedFloat32Array()
	heights.resize(nv * nv)
	var cave_floor: PackedFloat32Array = PackedFloat32Array()
	cave_floor.resize(nv * nv)
	var biome_v: PackedByteArray = PackedByteArray()
	biome_v.resize(nv * nv)
	var has_cave: PackedByteArray = PackedByteArray()
	has_cave.resize(nv * nv)

	var vi: int = 0
	for ix: int in range(nv):
		var wxf: float = ox + float(ix) * CELL_SIZE
		for iz: int in range(nv):
			var wzf: float = oz + float(iz) * CELL_SIZE
			var br: float = bns.get_noise_2d(wxf, wzf)
			var is_ocean: bool = br < -0.65
			var hm: float = -5.0
			var hx: float = 12.0
			var cu: float = 0.95
			var bm: int = BIOME_PLAINS
			if is_ocean:
				hm = WATER_Y - 8.0
				hx = WATER_Y + 2.0
				cu = 0.9
				bm = BIOME_OCEAN
			else:
				var bi: int = _biome_index(br)
				var hm_a: Array[float] = [-5.0, -8.0, 0.0, -10.0, 8.0]
				var hx_a: Array[float] = [12.0, 8.0, 18.0, 5.0, 28.0]
				var cu_a: Array[float] = [0.95, 0.92, 0.95, 0.90, 1.05]
				hm = hm_a[bi]
				hx = hx_a[bi]
				cu = cu_a[bi]
				bm = bi
			var wx2: float = wns.get_noise_2d(wxf, wzf) * 12.0
			var wz2: float = wns.get_noise_2d(wxf + 37.0, wzf - 23.0) * 12.0
			var bn: float = hns.get_noise_2d(wxf + wx2, wzf + wz2)
			var nm: float = bn * 0.5 + 0.5
			if nm < 0.0:
				nm = 0.0
			nm = pow(nm, cu)
			var af: float = (hx - 8.0) / 30.0
			var rr2: float = rns.get_noise_2d((wxf + wx2) * 1.3, (wzf + wz2) * 1.3)
			var rv2: float = pow(abs(rr2), 2.3) * 0.6 * af
			var dt: float = dns.get_noise_2d(wxf * 0.035, wzf * 0.035) * 0.08
			nm = nm + rv2 + dt + rv2 * 0.15 * af
			var sy: float = hm + (hx - hm) * nm
			if not is_ocean:
				var rv3: float = riv.get_noise_2d(wxf * 0.35, wzf * 0.35)
				if abs(rv3) > 0.46:
					sy = WATER_Y - (abs(rv3) - 0.46) * 15.0
					bm = BIOME_OCEAN
			if sy < BEDROCK_Y + 2.0:
				sy = BEDROCK_Y + 2.0
			if bm != BIOME_OCEAN and hx >= 24.0 and sy > 20.0:
				bm = BIOME_PEAKS
			heights[vi] = sy
			biome_v[vi] = bm

			var cave_detected: bool = false
			var cf_y: float = sy
			if cave_enabled and sy > WATER_Y + 4.0 and bm != BIOME_OCEAN:
				var cd: int = int(CAVE_MIN_DEPTH)
				while cd < 50:
					var wn: float = cns_worm.get_noise_3d(wxf, sy - float(cd), wzf)
					var cn: float = cns_cavern.get_noise_3d(wxf * 0.5, (sy - float(cd)) * 0.5, wzf * 0.5)
					var pn: float = cns_pit.get_noise_2d(wxf * 0.5, wzf * 0.5)
					if abs(wn) < 0.08 or abs(cn) > 0.55 or (abs(pn) > 0.7 and cd < 30):
						cave_detected = true
						cf_y = sy - float(cd) + 2.0
						if cf_y < BEDROCK_Y + 5.0:
							cf_y = BEDROCK_Y + 5.0
						break
					cd += 8
			if cave_detected and sy > 3.0:
				var roof: float = cf_y
				if roof < WATER_Y:
					roof = WATER_Y
				heights[vi] = roof
				cave_floor[vi] = cf_y
				has_cave[vi] = 1
				bm = BIOME_CAVE
			biome_v[vi] = bm
			vi += 1

	# Compute smooth normals from height differences
	var smooth_norms: PackedVector3Array = PackedVector3Array()
	smooth_norms.resize(nv * nv)
	for ix2: int in range(nv):
		for iz2: int in range(nv):
			var h_l: float = heights[max(ix2 - 1, 0) * nv + iz2]
			var h_r: float = heights[min(ix2 + 1, nv - 1) * nv + iz2]
			var h_d: float = heights[ix2 * nv + max(iz2 - 1, 0)]
			var h_u: float = heights[ix2 * nv + min(iz2 + 1, nv - 1)]
			smooth_norms[ix2 * nv + iz2] = Vector3(
				h_l - h_r,
				2.0 * CELL_SIZE,
				h_d - h_u
			).normalized()

	var surf_verts: Array[PackedVector3Array] = []
	var surf_norms: Array[PackedVector3Array] = []
	var surf_uvs: Array[PackedVector2Array] = []
	for b: int in range(BIOME_COUNT):
		surf_verts.append(PackedVector3Array())
		surf_norms.append(PackedVector3Array())
		surf_uvs.append(PackedVector2Array())

	var has_ocean: bool = false

	for ix: int in range(CHUNK_SIZE):
		var x0: float = ox + float(ix) * CELL_SIZE
		var x1: float = ox + float(ix + 1) * CELL_SIZE
		for iz: int in range(CHUNK_SIZE):
			var z0: float = oz + float(iz) * CELL_SIZE
			var z1: float = oz + float(iz + 1) * CELL_SIZE
			var i00: int = ix * nv + iz
			var i01: int = ix * nv + iz + 1
			var i10: int = (ix + 1) * nv + iz
			var i11: int = (ix + 1) * nv + iz + 1
			var h00: float = heights[i00]
			var h01: float = heights[i01]
			var h10: float = heights[i10]
			var h11: float = heights[i11]
			var p00: Vector3 = Vector3(x0, h00, z0)
			var p10: Vector3 = Vector3(x1, h10, z0)
			var p01: Vector3 = Vector3(x0, h01, z1)
			var p11: Vector3 = Vector3(x1, h11, z1)

			var n00: Vector3 = smooth_norms[i00]
			var n10: Vector3 = smooth_norms[i10]
			var n01: Vector3 = smooth_norms[i01]
			var n11: Vector3 = smooth_norms[i11]
			var n1: Vector3 = (n00 + n10 + n01).normalized()
			var n2: Vector3 = (n10 + n11 + n01).normalized()

			var b00: int = biome_v[i00]
			var b01: int = biome_v[i01]
			var b10: int = biome_v[i10]
			var b11: int = biome_v[i11]
			var u0: float = x0 * 0.02
			var u1: float = x1 * 0.02
			var v0: float = z0 * 0.02
			var v1: float = z1 * 0.02

			var sb1: int = _dominant_biome(b00, b01, b10, b11)
			var sv1: PackedVector3Array = surf_verts[sb1]
			var sn1: PackedVector3Array = surf_norms[sb1]
			var su1: PackedVector2Array = surf_uvs[sb1]
			sv1.append(p00); sv1.append(p10); sv1.append(p01)
			sn1.append(n1); sn1.append(n1); sn1.append(n1)
			su1.append(Vector2(u0, v0)); su1.append(Vector2(u1, v0)); su1.append(Vector2(u0, v1))
			var sb2: int = _dominant_biome(b10, b11, b01, b11)
			var sv2: PackedVector3Array = surf_verts[sb2]
			var sn2: PackedVector3Array = surf_norms[sb2]
			var su2: PackedVector2Array = surf_uvs[sb2]
			sv2.append(p10); sv2.append(p11); sv2.append(p01)
			sn2.append(n2); sn2.append(n2); sn2.append(n2)
			su2.append(Vector2(u1, v0)); su2.append(Vector2(u1, v1)); su2.append(Vector2(u0, v1))
			surf_verts[sb1] = sv1
			surf_norms[sb1] = sn1
			surf_uvs[sb1] = su1
			surf_verts[sb2] = sv2
			surf_norms[sb2] = sn2
			surf_uvs[sb2] = su2

			if sb1 == BIOME_OCEAN or sb2 == BIOME_OCEAN:
				has_ocean = true

			if has_cave[i00] > 0 or has_cave[i01] > 0 or has_cave[i10] > 0 or has_cave[i11] > 0:
				var mch: float = h00
				if h01 < mch:
					mch = h01
				if h10 < mch:
					mch = h10
				if h11 < mch:
					mch = h11
				var cf: float = cave_floor[i00]
				if cave_floor[i01] < cf:
					cf = cave_floor[i01]
				if cave_floor[i10] < cf:
					cf = cave_floor[i10]
				if cave_floor[i11] < cf:
					cf = cave_floor[i11]
				if cf < BEDROCK_Y + 3.0:
					cf = BEDROCK_Y + 3.0
				var cv: PackedVector3Array = surf_verts[BIOME_CAVE]
				var cn: PackedVector3Array = surf_norms[BIOME_CAVE]
				var cu: PackedVector2Array = surf_uvs[BIOME_CAVE]

				var cv0: Vector3 = Vector3(x0, cf, z0)
				var cv1: Vector3 = Vector3(x1, cf, z0)
				var cv2: Vector3 = Vector3(x1, cf, z1)
				var cv3: Vector3 = Vector3(x0, cf, z1)
				var cave_sv0: Vector3 = Vector3(x0, h00, z0)
				var cave_sv1: Vector3 = Vector3(x1, h10, z0)
				var cave_sv2: Vector3 = Vector3(x1, h11, z1)
				var cave_sv3: Vector3 = Vector3(x0, h01, z1)

				cv.append(cv0); cv.append(cv1); cv.append(cv2)
				cv.append(cv0); cv.append(cv2); cv.append(cv3)
				for _k: int in range(6):
					cn.append(Vector3.UP)
					cu.append(Vector2.ZERO)

				cv.append(cave_sv0); cv.append(cave_sv2); cv.append(cave_sv3)
				cv.append(cave_sv0); cv.append(cave_sv1); cv.append(cave_sv2)
				for _k2: int in range(6):
					cn.append(Vector3.DOWN)
					cu.append(Vector2.ZERO)

				if has_cave[i00] > 0 and has_cave[i10] > 0:
					_append_wall(cv, cn, cu, cave_sv0, cave_sv1, cv1, cv0, Vector3(0, 0, -1))
				if has_cave[i00] > 0 and has_cave[i01] > 0:
					_append_wall(cv, cn, cu, cave_sv0, cv0, cv3, cave_sv3, Vector3(-1, 0, 0))
				if has_cave[i10] > 0 and has_cave[i11] > 0:
					_append_wall(cv, cn, cu, cave_sv1, cave_sv2, cv2, cv1, Vector3(1, 0, 0))
				if has_cave[i01] > 0 and has_cave[i11] > 0:
					_append_wall(cv, cn, cu, cave_sv3, cv3, cv2, cave_sv2, Vector3(0, 0, 1))

				surf_verts[BIOME_CAVE] = cv
				surf_norms[BIOME_CAVE] = cn
				surf_uvs[BIOME_CAVE] = cu

	_gen_mutex.lock()
	_pending_results.append({
		"cx": cx,
		"cz": cz,
		"verts": surf_verts,
		"norms": surf_norms,
		"uvs": surf_uvs,
		"has_ocean": has_ocean,
	})
	_gen_mutex.unlock()


func _append_wall(verts: PackedVector3Array, norms: PackedVector3Array, uvs: PackedVector2Array,
		a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	verts.append(a); verts.append(b); verts.append(c)
	verts.append(a); verts.append(c); verts.append(d)
	for _k: int in range(6):
		norms.append(normal)
		uvs.append(Vector2.ZERO)


func _process_pending_results() -> void:
	if _pending_results.is_empty():
		return
	_gen_mutex.lock()
	var batch: Array = _pending_results.duplicate()
	_pending_results.clear()
	_gen_mutex.unlock()
	for res: Dictionary in batch:
		var cx: int = res["cx"]
		var cz: int = res["cz"]
		var key: String = str(cx) + "," + str(cz)
		if _chunks.has(key):
			_active_gen_count = max(_active_gen_count - 1, 0)
			continue
		_build_chunk_mesh(res)
		_gen_queue.erase(key)
		_active_gen_count = max(_active_gen_count - 1, 0)
		_total_chunks_generated += 1
		chunk_loaded.emit(cx, cz)
		_flush_gen_queue()
		if not _terrain_ready_emitted:
			var progress: float = 0.0
			if _total_chunks_target > 0:
				progress = clamp(float(_total_chunks_generated) / float(_total_chunks_target), 0.0, 1.0)
			generation_progress.emit(progress, _total_chunks_generated, _total_chunks_target, "Generating terrain...")
			if _total_chunks_generated >= _total_chunks_target and not _terrain_ready_emitted:
				_terrain_ready_emitted = true
				_spawn_ready = true
				generation_progress.emit(1.0, _total_chunks_generated, _total_chunks_target, "World ready")
				terrain_ready.emit()


func _flush_gen_queue() -> void:
	while _active_gen_count < MAX_CONCURRENT_GEN and not _gen_queue.is_empty():
		var next_key: String = _gen_queue.keys()[0]
		_gen_queue.erase(next_key)
		var parts: PackedStringArray = next_key.split(",")
		var nx: int = int(parts[0])
		var nz: int = int(parts[1])
		if not _chunks.has(next_key):
			_generate_chunk_async(nx, nz)


func _build_chunk_mesh(data: Dictionary) -> void:
	var cx: int = data["cx"]
	var cz: int = data["cz"]
	var all_verts: Array = data["verts"]
	var all_norms: Array = data["norms"]
	var all_uvs: Array = data["uvs"]
	var has_ocean: bool = data.get("has_ocean", false)

	var mesh: ArrayMesh = ArrayMesh.new()
	var has_any: bool = false

	for b: int in range(BIOME_COUNT):
		var bv: PackedVector3Array = all_verts[b]
		if bv.size() < 3:
			continue
		var bn: PackedVector3Array = all_norms[b]
		var bu: PackedVector2Array = all_uvs[b]
		var idx: PackedInt32Array = PackedInt32Array()
		var vc: int = bv.size()
		idx.resize(vc)
		for j: int in range(0, vc, 3):
			idx[j] = j
			idx[j + 1] = j + 1
			idx[j + 2] = j + 2
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = bv
		arrays[Mesh.ARRAY_NORMAL] = bn
		arrays[Mesh.ARRAY_TEX_UV] = bu
		arrays[Mesh.ARRAY_INDEX] = idx
		var surf_idx: int = mesh.get_surface_count()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mat: StandardMaterial3D = null
		if b < _biome_to_block.size():
			var bt: int = _biome_to_block[b]
			if bt >= 0 and bt < _block_mats.size():
				mat = _block_mats[bt]
			elif bt == -1:
				mat = _biome_ocean_mat
			elif bt == -2:
				mat = _biome_desert_mat
			elif bt == -3:
				mat = _biome_peaks_mat
		if mat != null:
			mesh.surface_set_material(surf_idx, mat)
		has_any = true

	if not has_any:
		return
	var mi := MeshInstance3D.new()
	mi.name = "Chunk_" + str(cx) + "_" + str(cz)
	mi.mesh = mesh
	add_child(mi)

	var water_node: MeshInstance3D = null
	if has_ocean:
		water_node = _build_water_mesh(cx, cz)
		if water_node != null:
			add_child(water_node)

	_chunks[str(cx) + "," + str(cz)] = {"node": mi, "cx": cx, "cz": cz, "water_node": water_node}


func _build_water_mesh(cx: int, cz: int) -> MeshInstance3D:
	var ox: float = float(cx) * CHUNK_WORLD
	var oz: float = float(cz) * CHUNK_WORLD
	var mesh: ArrayMesh = ArrayMesh.new()
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()

	var step: float = CHUNK_WORLD / 4.0
	var vi: int = 0
	for ix: int in range(5):
		var wx: float = ox + float(ix) * step
		for iz: int in range(5):
			var wz: float = oz + float(iz) * step
			verts.append(Vector3(wx, WATER_Y, wz))
			normals.append(Vector3.UP)
			uvs.append(Vector2(wx * 0.01, wz * 0.01))
	for ix: int in range(4):
		for iz: int in range(4):
			var i: int = ix * 5 + iz
			indices.append(i)
			indices.append(i + 5)
			indices.append(i + 1)
			indices.append(i + 1)
			indices.append(i + 5)
			indices.append(i + 6)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if _water_mat != null:
		var wmat: StandardMaterial3D = _water_mat.duplicate() if _water_mat is StandardMaterial3D else _water_mat
		mesh.surface_set_material(0, wmat)

	var mi := MeshInstance3D.new()
	mi.name = "Water_" + str(cx) + "_" + str(cz)
	mi.mesh = mesh
	return mi


func get_surface_height_at(wx: float, wz: float) -> float:
	if _cached_biome_noise == null:
		_init_all_noise()
	if _cached_biome_noise == null:
		return 0.0
	var br: float = _cached_biome_noise.get_noise_2d(wx, wz)
	var is_ocean: bool = br < -0.65
	var hm: float = -5.0
	var hx: float = 12.0
	var cu: float = 0.95
	if is_ocean:
		hm = WATER_Y - 8.0
		hx = WATER_Y + 2.0
		cu = 0.9
	else:
		var bi: int = _biome_index(br)
		var hm_a: Array[float] = [-5.0, -8.0, 0.0, -10.0, 8.0]
		var hx_a: Array[float] = [12.0, 8.0, 18.0, 5.0, 28.0]
		var cu_a: Array[float] = [0.95, 0.92, 0.95, 0.90, 1.05]
		hm = hm_a[bi]
		hx = hx_a[bi]
		cu = cu_a[bi]
	var wx2: float = _cached_warp_noise.get_noise_2d(wx, wz) * 12.0
	var wz2: float = _cached_warp_noise.get_noise_2d(wx + 37.0, wz - 23.0) * 12.0
	var bn: float = _cached_surface_noise.get_noise_2d(wx + wx2, wz + wz2)
	var nm: float = bn * 0.5 + 0.5
	if nm < 0.0:
		nm = 0.0
	nm = pow(nm, cu)
	var af: float = (hx - 8.0) / 30.0
	var rr2: float = _cached_ridge_noise.get_noise_2d((wx + wx2) * 1.3, (wz + wz2) * 1.3)
	var rv2: float = pow(abs(rr2), 2.3) * 0.6 * af
	var dt: float = _cached_detail_noise.get_noise_2d(wx * 0.035, wz * 0.035) * 0.08
	nm = nm + rv2 + dt + rv2 * 0.15 * af
	var sy: float = hm + (hx - hm) * nm
	if not is_ocean:
		var rv3: float = _cached_river_noise.get_noise_2d(wx * 0.35, wz * 0.35)
		if abs(rv3) > 0.46:
			sy = WATER_Y - (abs(rv3) - 0.46) * 15.0
	if sy < BEDROCK_Y + 2.0:
		sy = BEDROCK_Y + 2.0
	return sy


func register_frozen_player(player: Node3D) -> void:
	if not player in _frozen_players:
		_frozen_players.append(player)
		if player is CharacterBody3D:
			player.velocity = Vector3.ZERO


func unregister_frozen_player(player: Node3D) -> void:
	_frozen_players.erase(player)


func is_spawn_ready() -> bool:
	return _spawn_ready


func _tick_frozen(delta: float) -> void:
	if _frozen_players.is_empty():
		return
	_unfreeze_timer += delta
	if _unfreeze_timer > 3.0:
		for player: Variant in _frozen_players.duplicate():
			if is_instance_valid(player):
				var p: Node3D = player as Node3D
				var sy: float = get_surface_height_at(p.global_position.x, p.global_position.z)
				p.global_position.y = sy + 25.0
				p.velocity = Vector3.ZERO
			_frozen_players.erase(player)
		_spawn_ready = true
		_unfreeze_timer = 0.0


func sapa_bloc(start: Vector3, direction: Vector3) -> int:
	return 3 if dig_at(start, direction) else 0


func sapa_sfera(start: Vector3, direction: Vector3) -> Array:
	return [1, 3] if dig_at(start, direction, 4.5) else []


func construieste_sfera(start: Vector3, direction: Vector3) -> int:
	return 1 if build_at(start, direction) else 0


func dig_at(origin: Vector3, direction: Vector3, _radius: float = 2.5) -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + direction * interact_distance)
	query.collision_mask = 1
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return false
	var hit_pos: Vector3 = hit.position
	if hit_pos.y <= BEDROCK_Y:
		return false
	var hit_node: Node = hit.collider
	if hit_node is MeshInstance3D and hit_node.get_parent() == self:
		var node_name: String = hit_node.name
		if not node_name.begins_with("Chunk_"):
			return false
		var parts: PackedStringArray = node_name.trim_prefix("Chunk_").split("_")
		if parts.size() < 2:
			return false
		var dcx: int = int(parts[0])
		var dcz: int = int(parts[1])
		hit_node.queue_free()
		var key: String = str(dcx) + "," + str(dcz)
		if _chunks.has(key) and _chunks[key].has("water_node"):
			var wn: Node = _chunks[key]["water_node"]
			if is_instance_valid(wn):
				wn.queue_free()
		_chunks.erase(key)
		_generate_chunk_async(dcx, dcz)
		last_dug_world_pos = hit_pos
		if _NM and _NM.has_method("send_terrain_modify"):
			_NM.send_terrain_modify([hit_pos.x, hit_pos.y, hit_pos.z], "dig", 0)
		return true
	return false


func build_at(origin: Vector3, direction: Vector3, _radius: float = 2.0) -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + direction * interact_distance)
	query.collision_mask = 1
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return false
	var hit_pos: Vector3 = hit.position + hit.normal * 1.0
	if hit_pos.y <= BEDROCK_Y:
		return false
	var hit_node: Node = hit.collider
	if hit_node is MeshInstance3D and hit_node.get_parent() == self:
		var node_name: String = hit_node.name
		if not node_name.begins_with("Chunk_"):
			return false
		var parts: PackedStringArray = node_name.trim_prefix("Chunk_").split("_")
		if parts.size() < 2:
			return false
		var bcx: int = int(parts[0])
		var bcz: int = int(parts[1])
		hit_node.queue_free()
		var key: String = str(bcx) + "," + str(bcz)
		if _chunks.has(key) and _chunks[key].has("water_node"):
			var wn: Node = _chunks[key]["water_node"]
			if is_instance_valid(wn):
				wn.queue_free()
		_chunks.erase(key)
		_generate_chunk_async(bcx, bcz)
		last_dug_world_pos = hit_pos
		return true
	return false


func modify_smooth_terrain(world_pos: Vector3, radius: float, mode: String, material_idx: int = 0) -> bool:
	if mode == "dig":
		return dig_at(world_pos, Vector3.DOWN)
	return build_at(world_pos, Vector3.DOWN)


func ray_pick_block(start: Vector3, direction: Vector3) -> Variant:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(start, start + direction * interact_distance)
	query.collision_mask = 1
	return space.intersect_ray(query)


func get_block_type_at(wx: int, wy: int, wz: int) -> int:
	var sy: float = get_surface_height_at(float(wx), float(wz))
	var sdf_val: float = float(wy) - sy
	if sdf_val > -2.0:
		return BLOCK_GRASS
	elif sdf_val > -8.0:
		return BLOCK_DIRT
	else:
		var ons: FastNoiseLite = _cached_ore_noise
		var ore_n: float = ons.get_noise_3d(float(wx) * 0.5, float(wy), float(wz) * 0.5)
		if ore_n > 0.7 and sdf_val < -20.0:
			return BLOCK_DIAMOND
		elif ore_n > 0.55 and sdf_val < -15.0:
			return BLOCK_GOLD
		elif ore_n > 0.4 and sdf_val < -10.0:
			return BLOCK_IRON
		elif ore_n > 0.3 and sdf_val < -6.0:
			return BLOCK_COAL
		return BLOCK_STONE


func _on_terrain_change(_player_id, pos: Array, block_type: int, _action_type: String) -> void:
	if pos.size() >= 3:
		var world_pos: Vector3 = Vector3(pos[0], pos[1], pos[2])
		if block_type == 0:
			dig_at(world_pos, Vector3.DOWN)
		else:
			build_at(world_pos, Vector3.DOWN)


func place_structure(_struct_type: String, _world_pos: Vector3) -> bool:
	return true


func marcheaza_bloc_sters(_poz: Vector3) -> void:
	pass


func get_dominant_biome_at(wx: float, wz: float) -> int:
	var br: float = _cached_biome_noise.get_noise_2d(wx, wz)
	return _biome_index(br)


func get_biome_name_at(wx: float, wz: float) -> String:
	var biome: int = get_dominant_biome_at(wx, wz)
	match biome:
		BIOME_PLAINS: return "Plains"
		BIOME_OCEAN: return "Ocean"
		BIOME_DESERT: return "Desert"
		BIOME_PEAKS: return "Peaks"
		BIOME_CAVE: return "Cave"
	return "Unknown"
