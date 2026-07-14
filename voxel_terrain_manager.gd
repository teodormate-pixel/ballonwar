extends Node3D

signal terrain_ready
signal chunk_loaded(chunk_x: int, chunk_z: int)

const CHUNK_SIZE: int = 16
const CELL_SIZE: float = 2.0
const CHUNK_WORLD: float = CHUNK_SIZE * CELL_SIZE
const VIEW_RADIUS: int = 5
const UNLOAD_RADIUS: int = 9
const BEDROCK_Y: float = -75.0
const WATER_Y: float = -15.0
const CAVE_THRESH: float = 0.12
const CAVE_MIN_DEPTH: float = 6.0

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

@export_group("Plains (Câmpii)")
@export var plains_albedo: Texture2D = null
@export var plains_normal: Texture2D = null
@export var plains_roughness: Texture2D = null

@export_group("Ocean / River (Râuri)")
@export var ocean_albedo: Texture2D = null
@export var ocean_normal: Texture2D = null

@export_group("Desert (Deșert)")
@export var desert_albedo: Texture2D = null
@export var desert_normal: Texture2D = null
@export var desert_roughness: Texture2D = null

@export_group("Snow Peaks (Vârfuri)")
@export var peaks_albedo: Texture2D = null
@export var peaks_normal: Texture2D = null

@export_group("Cave / Stone (Peșteri)")
@export var cave_albedo: Texture2D = null
@export var cave_normal: Texture2D = null
@export var cave_roughness: Texture2D = null

var _NM: Node
var _WC: Node
var _player_ref: Node3D = null
var _chunks: Dictionary = {}
var _pending_results: Array = []
var _gen_mutex: Mutex = Mutex.new()
var _gen_queue: Array = []
var _queue_timer: float = 0.0
var _ready_emitted: bool = false
var _spawn_ready: bool = false
var _frozen_players: Array = []
var _unfreeze_timer: float = 0.0
var last_dug_world_pos: Vector3 = Vector3.ZERO
var _biome_mats: Array[StandardMaterial3D] = []
var _cached_surface_noise: FastNoiseLite = null
var _cached_biome_noise: FastNoiseLite = null
var _cached_warp_noise: FastNoiseLite = null
var _cached_river_noise: FastNoiseLite = null


func _ready() -> void:
	_NM = get_node_or_null("/root/NetworkManager")
	_WC = get_node_or_null("/root/WorldConfig")
	if world_seed == 0:
		world_seed = randi()
	if _WC and _WC.get("world_seed") and _WC.world_seed != 0:
		world_seed = _WC.world_seed
	if _WC and _WC.get("terrain_frequency"):
		terrain_frequency = _WC.terrain_frequency
	_build_biome_materials()
	_init_cached_noise()
	call_deferred("_find_player")
	call_deferred("_emit_ready")


func _init_cached_noise() -> void:
	_cached_surface_noise = FastNoiseLite.new()
	_cached_surface_noise.seed = world_seed + 1
	_cached_surface_noise.frequency = terrain_frequency
	_cached_surface_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_cached_surface_noise.fractal_octaves = 6
	_cached_surface_noise.fractal_gain = 0.5
	_cached_surface_noise.fractal_lacunarity = 2.0

	_cached_biome_noise = FastNoiseLite.new()
	_cached_biome_noise.seed = world_seed + 3
	_cached_biome_noise.frequency = 0.0012
	_cached_biome_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_cached_biome_noise.fractal_octaves = 3
	_cached_biome_noise.fractal_gain = 0.5
	_cached_biome_noise.fractal_lacunarity = 2.0

	_cached_warp_noise = FastNoiseLite.new()
	_cached_warp_noise.seed = world_seed + 11
	_cached_warp_noise.frequency = 0.006
	_cached_warp_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_cached_warp_noise.fractal_octaves = 2
	_cached_warp_noise.fractal_gain = 0.5
	_cached_warp_noise.fractal_lacunarity = 2.0

	_cached_river_noise = FastNoiseLite.new()
	_cached_river_noise.seed = world_seed + 5
	_cached_river_noise.frequency = 0.012
	_cached_river_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_cached_river_noise.fractal_octaves = 2
	_cached_river_noise.fractal_gain = 0.5
	_cached_river_noise.fractal_lacunarity = 2.0


func _build_biome_materials() -> void:
	_biome_mats.clear()

	var m_grass: StandardMaterial3D = StandardMaterial3D.new()
	m_grass.albedo_color = Color(0.15, 0.55, 0.12)
	var gt: Texture2D = plains_albedo if plains_albedo != null else _load_tex("res://Poliigon_GrassPatchyGround_4585/2K/Poliigon_GrassPatchyGround_4585_BaseColor.jpg")
	var gn: Texture2D = plains_normal if plains_normal != null else _load_tex("res://Poliigon_GrassPatchyGround_4585/2K/Poliigon_GrassPatchyGround_4585_Normal.png")
	var gr: Texture2D = plains_roughness if plains_roughness != null else _load_tex("res://Poliigon_GrassPatchyGround_4585/2K/Poliigon_GrassPatchyGround_4585_Roughness.jpg")
	if gt != null:
		m_grass.albedo_texture = gt
	if gn != null:
		m_grass.normal_enabled = true
		m_grass.normal_texture = gn
	if gr != null:
		m_grass.roughness_texture = gr
	m_grass.uv1_triplanar = true
	m_grass.uv1_triplanar_sharpness = 6.5
	m_grass.uv1_scale = Vector3(0.02, 0.02, 0.02)
	m_grass.normal_texture_flip_y = true
	_biome_mats.append(m_grass)

	var m_ocean: StandardMaterial3D = StandardMaterial3D.new()
	m_ocean.albedo_color = Color(0.05, 0.15, 0.55)
	m_ocean.metallic = 0.1
	m_ocean.roughness = 0.3
	m_ocean.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	m_ocean.albedo_color.a = 0.85
	if ocean_albedo != null:
		m_ocean.albedo_texture = ocean_albedo
	if ocean_normal != null:
		m_ocean.normal_enabled = true
		m_ocean.normal_texture = ocean_normal
	m_ocean.uv1_triplanar = true
	m_ocean.uv1_triplanar_sharpness = 6.5
	m_ocean.uv1_scale = Vector3(0.02, 0.02, 0.02)
	m_ocean.normal_texture_flip_y = true
	_biome_mats.append(m_ocean)

	var m_sand: StandardMaterial3D = StandardMaterial3D.new()
	m_sand.albedo_color = Color(0.85, 0.75, 0.4)
	var st: Texture2D = desert_albedo if desert_albedo != null else _load_tex("res://GroundSand005/GroundSand005_COL_2K.jpg")
	var sn: Texture2D = desert_normal if desert_normal != null else _load_tex("res://GroundSand005/GroundSand005_NRM_2K.jpg")
	var sr: Texture2D = desert_roughness if desert_roughness != null else _load_tex("res://GroundSand005/GroundSand005_GLOSS_2K.jpg")
	if st != null:
		m_sand.albedo_texture = st
	if sn != null:
		m_sand.normal_enabled = true
		m_sand.normal_texture = sn
	if sr != null:
		m_sand.roughness_texture = sr
	m_sand.uv1_triplanar = true
	m_sand.uv1_triplanar_sharpness = 6.5
	m_sand.uv1_scale = Vector3(0.02, 0.02, 0.02)
	m_sand.normal_texture_flip_y = true
	_biome_mats.append(m_sand)

	var m_snow: StandardMaterial3D = StandardMaterial3D.new()
	m_snow.albedo_color = Color(0.92, 0.92, 0.96)
	var snt: Texture2D = peaks_albedo if peaks_albedo != null else _load_tex("res://Snow004_2K-JPG/Snow004_2K-JPG_Color.jpg")
	var snn: Texture2D = peaks_normal if peaks_normal != null else _load_tex("res://Snow004_2K-JPG/Snow004_2K-JPG_NormalDX.jpg")
	if snt != null:
		m_snow.albedo_texture = snt
	if snn != null:
		m_snow.normal_enabled = true
		m_snow.normal_texture = snn
	m_snow.uv1_triplanar = true
	m_snow.uv1_triplanar_sharpness = 6.5
	m_snow.uv1_scale = Vector3(0.02, 0.02, 0.02)
	m_snow.normal_texture_flip_y = true
	_biome_mats.append(m_snow)

	var m_rock: StandardMaterial3D = StandardMaterial3D.new()
	m_rock.albedo_color = Color(0.35, 0.35, 0.35)
	var rt: Texture2D = cave_albedo if cave_albedo != null else _load_tex("res://rocks_ground_04_2k.blend/textures/rocks_ground_04_diff_2k.jpg")
	var rn: Texture2D = cave_normal if cave_normal != null else _load_tex("res://rocks_ground_04_2k.blend/textures/rocks_ground_04_nor_2k.jpg")
	var rr: Texture2D = cave_roughness if cave_roughness != null else _load_tex("res://rocks_ground_04_2k.blend/textures/rocks_ground_04_rough_2k.jpg")
	if rt != null:
		m_rock.albedo_texture = rt
	if rn != null:
		m_rock.normal_enabled = true
		m_rock.normal_texture = rn
	if rr != null:
		m_rock.roughness_texture = rr
	m_rock.uv1_triplanar = true
	m_rock.uv1_triplanar_sharpness = 6.5
	m_rock.uv1_scale = Vector3(0.02, 0.02, 0.02)
	m_rock.normal_texture_flip_y = true
	_biome_mats.append(m_rock)


func _load_tex(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var ext: String = path.get_extension().to_lower()
	if ext in ["exr", "tiff", "tif"]:
		return null
	return load(path) as Texture2D


func _emit_ready() -> void:
	if _ready_emitted:
		return
	_ready_emitted = true
	terrain_ready.emit()


func _find_player() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var root: Node = tree.root
	if root == null:
		return
	var lume: Node = root.get_node_or_null("Lume")
	if lume == null:
		return
	var starter: Node = lume.get_node_or_null("StarterPlayer")
	if starter != null and starter is CharacterBody3D:
		_player_ref = starter as Node3D
		return
	var players: Node = lume.get_node_or_null("Players")
	if players != null:
		for child: Node in players.get_children():
			if child is CharacterBody3D:
				_player_ref = child as Node3D
				return
	var cam: Camera3D = get_viewport().get_camera_3d()
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
			if not _chunks.has(key) and not _gen_queue.has([kx, kz]):
				_gen_queue.append([kx, kz])
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
				_chunks.erase(key)


func _generate_chunk_async(cx: int, cz: int) -> void:
	var callable: Callable = Callable(self, "_thread_generate").bind(cx, cz, world_seed, terrain_frequency)
	WorkerThreadPool.add_task(callable, true, "chunk_gen")


func _make_noise(seed_val: int, freq: float, octaves: int, ntype: int = FastNoiseLite.TYPE_PERLIN) -> FastNoiseLite:
	var n: FastNoiseLite = FastNoiseLite.new()
	n.seed = seed_val
	n.frequency = freq
	n.noise_type = ntype
	n.fractal_octaves = octaves
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


func _thread_generate(cx: int, cz: int, seed_val: int, freq: float) -> void:
	var ox: float = float(cx) * CHUNK_WORLD
	var oz: float = float(cz) * CHUNK_WORLD
	var nv: int = CHUNK_SIZE + 1

	var hns: FastNoiseLite = _make_noise(seed_val + 1, freq, 6)
	var bns: FastNoiseLite = _make_noise(seed_val + 3, 0.0012, 3)
	var wns: FastNoiseLite = _make_noise(seed_val + 11, 0.006, 2, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	var rns: FastNoiseLite = _make_noise(seed_val + 13, 0.022, 5)
	var dns: FastNoiseLite = _make_noise(seed_val + 9, 0.035, 3)
	var riv: FastNoiseLite = _make_noise(seed_val + 5, 0.012, 2)
	var cns: FastNoiseLite = _make_noise(seed_val + 7, 0.025, 3)
	var ons: FastNoiseLite = _make_noise(seed_val + 17, 0.045, 2)

	var heights: PackedFloat32Array = PackedFloat32Array()
	heights.resize(nv * nv)
	var cave_v: PackedByteArray = PackedByteArray()
	cave_v.resize(nv * nv)
	var biome_v: PackedByteArray = PackedByteArray()
	biome_v.resize(nv * nv)

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

			var sdf_val: float = float(0) - sy
			var has_cave: bool = false
			if sdf_val < 0.0 and sy > WATER_Y + 4.0:
				var cd: int = int(CAVE_MIN_DEPTH)
				while cd < 40:
					var cn: float = cns.get_noise_3d(wxf, sy - float(cd), wzf)
					if cn > -CAVE_THRESH and cn < CAVE_THRESH:
						has_cave = true
						break
					cd += 6
			if has_cave and sy > 3.0:
				var roof: float = sy * 0.35
				if roof < WATER_Y:
					roof = WATER_Y
				heights[vi] = roof
				cave_v[vi] = 1
				bm = BIOME_CAVE
			biome_v[vi] = bm
			vi += 1

	var surf_verts: Array[PackedVector3Array] = []
	var surf_norms: Array[PackedVector3Array] = []
	var surf_uvs: Array[PackedVector2Array] = []
	for b: int in range(BIOME_COUNT):
		surf_verts.append(PackedVector3Array())
		surf_norms.append(PackedVector3Array())
		surf_uvs.append(PackedVector2Array())

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
			var n1: Vector3 = (p10 - p00).cross(p01 - p00).normalized()
			var n2: Vector3 = (p11 - p10).cross(p01 - p10).normalized()
			var b00: int = biome_v[i00]
			var b01: int = biome_v[i01]
			var b10: int = biome_v[i10]
			var b11: int = biome_v[i11]
			var u0: float = float(ix) / float(CHUNK_SIZE)
			var u1: float = float(ix + 1) / float(CHUNK_SIZE)
			var v0: float = float(iz) / float(CHUNK_SIZE)
			var v1: float = float(iz + 1) / float(CHUNK_SIZE)

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

			if cave_v[i00] > 0 or cave_v[i01] > 0 or cave_v[i10] > 0 or cave_v[i11] > 0:
				var mch: float = h00
				if h01 < mch:
					mch = h01
				if h10 < mch:
					mch = h10
				if h11 < mch:
					mch = h11
				var cf: float = mch - 5.0
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

				if cave_v[i00] > 0 and cave_v[i10] > 0:
					_append_wall(cv, cn, cu, cave_sv0, cave_sv1, cv1, cv0, Vector3(0, 0, -1))
				if cave_v[i00] > 0 and cave_v[i01] > 0:
					_append_wall(cv, cn, cu, cave_sv0, cv0, cv3, cave_sv3, Vector3(-1, 0, 0))
				if cave_v[i10] > 0 and cave_v[i11] > 0:
					_append_wall(cv, cn, cu, cave_sv1, cave_sv2, cv2, cv1, Vector3(1, 0, 0))
				if cave_v[i01] > 0 and cave_v[i11] > 0:
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
	})
	_gen_mutex.unlock()


func _append_wall(verts: PackedVector3Array, norms: PackedVector3Array, uvs: PackedVector2Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
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
			continue
		_build_chunk_mesh(res)
		var qidx: int = _gen_queue.find([cx, cz])
		if qidx >= 0:
			_gen_queue.remove_at(qidx)
		chunk_loaded.emit(cx, cz)


func _build_chunk_mesh(data: Dictionary) -> void:
	var cx: int = data["cx"]
	var cz: int = data["cz"]
	var all_verts: Array = data["verts"]
	var all_norms: Array = data["norms"]
	var all_uvs: Array = data["uvs"]

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
		if surf_idx < _biome_mats.size():
			mesh.surface_set_material(surf_idx, _biome_mats[b])
		has_any = true

	if not has_any:
		return
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Chunk_" + str(cx) + "_" + str(cz)
	mi.mesh = mesh
	add_child(mi)
	mi.create_trimesh_collision()
	_chunks[str(cx) + "," + str(cz)] = {"node": mi, "cx": cx, "cz": cz}


func get_surface_height_at(wx: float, wz: float) -> float:
	if _cached_surface_noise == null or _cached_biome_noise == null or _cached_warp_noise == null:
		_init_cached_noise()
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
	var rns: FastNoiseLite = _make_noise(world_seed + 13, 0.022, 5)
	var rr2: float = rns.get_noise_2d((wx + wx2) * 1.3, (wz + wz2) * 1.3)
	var rv2: float = pow(abs(rr2), 2.3) * 0.6 * af
	var dns: FastNoiseLite = _make_noise(world_seed + 9, 0.035, 3)
	var dt: float = dns.get_noise_2d(wx * 0.035, wz * 0.035) * 0.08
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
		_chunks.erase(str(dcx) + "," + str(dcz))
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
		_chunks.erase(str(bcx) + "," + str(bcz))
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
		var ons: FastNoiseLite = _make_noise(world_seed + 17, 0.045, 2)
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


func _on_terrain_change(_player_id: String, pos: Array, block_type: int, _action_type: String) -> void:
	if pos.size() >= 3:
		var world_pos: Vector3 = Vector3(pos[0], pos[1], pos[2])
		if block_type == 0:
			dig_at(world_pos, Vector3.DOWN)
		else:
			build_at(world_pos, Vector3.DOWN)


func place_structure(_struct_type: String, _world_pos: Vector3) -> bool:
	return true


func get_dominant_biome_at(wx: float, wz: float) -> int:
	if _cached_biome_noise == null:
		_init_cached_noise()
	var br: float = _cached_biome_noise.get_noise_2d(wx, wz)
	return _biome_index(br)
