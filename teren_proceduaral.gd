class_name TerenProceduralTerrain
extends Node3D
@onready var _NM = get_node("/root/NetworkManager")
@onready var _WC = get_node("/root/WorldConfig")

enum BlockType { AIR, GRASS, DIRT, STONE, COAL, IRON, COPPER, GOLD, DIAMOND, WOOD, LEAF }
enum BiomeType { PLAINS, FOREST, HILLS, DESERT, SWAMP, SNOW, MOUNTAINS }

@export var chunk_dimensions: int = 16
@export var max_height_blocks: int = 128
@export var distanta_randare: int = 2
@export var interact_distance: float = 12.0
@export var ray_step: float = 0.25

@export var surface_min_height: int = 32
@export var surface_max_height: int = 96
@export var grass_layers: int = 2
@export var dirt_layers: int = 7

@export var terrain_frequency: float = 0.018
@export var terrain_detail_frequency: float = 0.03
@export var terrain_warp_frequency: float = 0.010
@export var terrain_warp_strength: float = 5.0
@export var terrain_curve: float = 0.7
@export var surface_resolution: int = 1
@export var biome_frequency: float = 0.006
@export var biome_amplitude: float = 4.0

@export var ore_frequency: float = 0.04
@export var ore_vertical_frequency: float = 0.05

@export var ridge_frequency: float = 0.025
@export var ridge_strength: float = 0.8
@export var ridge_mix: float = 0.05

@export var lod_enabled: bool = false
@export var lod_distances: Array = [0.0, 30.0, 60.0]
@export var lod_resolutions: Array = [1, 2, 4]
@export var mobile_mode: bool = false

@export_group("Structuri")
@export var structuri_naturale: Array[PackedScene] = []
@export var structuri_constructii: Array[PackedScene] = []
@export var structuri_inamici: Array[PackedScene] = []

var world_seed: int = 0

var terrain_noise: FastNoiseLite = FastNoiseLite.new()
var detail_noise: FastNoiseLite = FastNoiseLite.new()
var warp_noise: FastNoiseLite = FastNoiseLite.new()
var biome_noise: FastNoiseLite = FastNoiseLite.new()
var ore_noise: FastNoiseLite = FastNoiseLite.new()
var ridge_noise: FastNoiseLite = FastNoiseLite.new()
var micro_noise: FastNoiseLite = FastNoiseLite.new()

var chunk_jucator_vechi: Vector2i = Vector2i(-999, -999)
var chunk_centrul_activ: Vector2i = Vector2i.ZERO
var nod_jucator: CharacterBody3D = null

var chunk_visuals: Dictionary = {}
var chunk_overrides: Dictionary = {}
var modified_block_visuals: Dictionary = {}
var chunk_generation_queue: Array = []
var chunk_generation_pending: Dictionary = {}
var blocuri_structuri_sterse: Dictionary = {}
var generating_chunk: bool = false
var highlight_block: MeshInstance3D = null

var material_grass: StandardMaterial3D
var material_dirt: StandardMaterial3D
var material_stone: StandardMaterial3D
var material_coal: StandardMaterial3D
var material_iron: StandardMaterial3D
var material_copper: StandardMaterial3D
var material_gold: StandardMaterial3D
var material_diamond: StandardMaterial3D
var chunk_material: StandardMaterial3D
var cube_mesh: BoxMesh = BoxMesh.new()

const BIOME_CENTERS: Dictionary = {
	0: -0.825,
	1: -0.50,
	2: -0.20,
	3: 0.10,
	4: 0.375,
	5: 0.625,
	6: 0.875
}
const BIOME_BLEND_SPREAD: float = 0.25
const BlockScenaScene = preload("res://BlockScena.tscn")

func _ready() -> void:
	_init_materials()
	if _WC.world_seed != 0:
		world_seed = _WC.world_seed
	surface_min_height = _WC.surface_min_height
	surface_max_height = _WC.surface_max_height
	terrain_frequency = _WC.terrain_frequency
	terrain_detail_frequency = _WC.terrain_frequency * 1.5
	terrain_warp_strength = _WC.terrain_warp_strength
	terrain_curve = _WC.terrain_curve
	biome_frequency = _WC.biome_frequency
	ridge_strength = _WC.ridge_strength
	ridge_mix = _WC.ridge_mix
	_init_noise()
	_populeaza_structuri_default()
	cube_mesh.size = Vector3.ONE
	highlight_block = _create_highlight_block()
	cautare_jucator_securizata()
	_actualizeaza_chunk_uri(Vector2i.ZERO)
	_process_chunk_queue()
	if _NM.room_id != "":
		_NM.terrain_change.connect(_on_terrain_change)


func _populeaza_structuri_default() -> void:
	var default_inamici: Array[String] = ["res://InamicBalon.tscn", "res://SpawnerInamici.tscn"]
	if structuri_inamici.is_empty():
		for p in default_inamici:
			if ResourceLoader.exists(p):
				structuri_inamici.append(load(p))


func marcheaza_bloc_sters(poz: Vector3) -> void:
	blocuri_structuri_sterse[str(poz)] = true


func _plaseaza_un_bloc(root: Node3D, x: float, y: float, z: float, block_type: int) -> void:
	var key: String = str(Vector3(x, y, z))
	if key in blocuri_structuri_sterse:
		return
	var block: StaticBody3D = BlockScenaScene.instantiate()
	block.block_type = block_type
	block.position = Vector3(x, y, z)
	block.add_to_group("Digable")
	var mesh_instance: MeshInstance3D = block.get_node("Mesh") as MeshInstance3D
	if mesh_instance:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = _block_type_color(block_type)
		mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		mesh_instance.material_override = mat
	root.add_child(block)


func _genereaza_copac(root: Node3D, wx: float, wz: float, h: float, rng: RandomNumberGenerator) -> void:
	var trunk_h: int = rng.randi_range(3, 5)
	for i in range(trunk_h):
		_plaseaza_un_bloc(root, wx, h + 0.5 + i, wz, BlockType.WOOD)
	var top_y: float = h + 0.5 + trunk_h - 1
	_plaseaza_un_bloc(root, wx, top_y + 1.0, wz, BlockType.LEAF)
	_plaseaza_un_bloc(root, wx + 1.0, top_y, wz, BlockType.LEAF)
	_plaseaza_un_bloc(root, wx - 1.0, top_y, wz, BlockType.LEAF)
	_plaseaza_un_bloc(root, wx, top_y, wz + 1.0, BlockType.LEAF)
	_plaseaza_un_bloc(root, wx, top_y, wz - 1.0, BlockType.LEAF)


func _genereaza_piatra(root: Node3D, wx: float, wz: float, h: float, rng: RandomNumberGenerator) -> void:
	var n: int = rng.randi_range(1, 2)
	for i in range(n):
		var ox: float = float(rng.randi_range(-1, 1)) * 0.5
		var oz: float = float(rng.randi_range(-1, 1)) * 0.5
		_plaseaza_un_bloc(root, wx + ox, h + 0.5, wz + oz, BlockType.STONE)


func _create_highlight_block() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "BlockHighlight"
	var box := BoxMesh.new()
	box.size = Vector3(1.02, 1.02, 1.02)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1, 0.25)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	box.material = mat
	mi.mesh = box
	mi.visible = false
	add_child(mi)
	return mi


func _physics_process(_delta: float) -> void:
	if nod_jucator == null or not nod_jucator.is_inside_tree():
		cautare_jucator_securizata()
		return
	var cx: int = int(floor(nod_jucator.global_position.x / float(chunk_dimensions)))
	var cz: int = int(floor(nod_jucator.global_position.z / float(chunk_dimensions)))
	var chunk_curent: Vector2i = Vector2i(cx, cz)
	chunk_centrul_activ = chunk_curent
	if chunk_curent != chunk_jucator_vechi:
		_actualizeaza_chunk_uri(chunk_curent)
		chunk_jucator_vechi = chunk_curent
	_process_chunk_queue()
	_update_highlight_from_player()


func _update_highlight_from_player() -> void:
	if highlight_block == null:
		return
	if nod_jucator == null or not nod_jucator.has_node("Cap/SpringArm3D/Camera3D"):
		highlight_block.visible = false
		return
	var cam: Camera3D = nod_jucator.get_node("Cap/SpringArm3D/Camera3D") as Camera3D
	if cam == null:
		highlight_block.visible = false
		return
	var start: Vector3 = cam.global_position
	var dir: Vector3 = (-cam.global_transform.basis.z).normalized()
	var hit: Variant = ray_pick_block(start, dir)
	if hit == null or hit is bool:
		highlight_block.visible = false
		return
	var wp: Vector3 = hit["hit"]["world"]
	var wx: int = int(wp.x)
	var wy: int = int(wp.y)
	var wz: int = int(wp.z)
	var block: int = get_block_type_at(wx, wy, wz)
	if block == BlockType.AIR:
		highlight_block.visible = false
		return
	highlight_block.visible = true
	highlight_block.position = Vector3(wx + 0.5, wy + 0.5, wz + 0.5)


func _init_materials() -> void:
	material_grass = _make_material(Color(0.28, 0.70, 0.24))
	material_dirt = _make_material(Color(0.58, 0.40, 0.24))
	material_stone = _make_material(Color(0.52, 0.52, 0.52))
	material_coal = _make_material(Color(0.12, 0.12, 0.12))
	material_iron = _make_material(Color(0.72, 0.72, 0.78))
	material_copper = _make_material(Color(0.78, 0.48, 0.30))
	material_gold = _make_material(Color(0.90, 0.78, 0.18))
	material_diamond = _make_material(Color(0.35, 0.85, 0.95))
	chunk_material = _make_material(Color(0.5, 0.5, 0.5))


func _make_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.roughness = 0.85
	mat.metallic = 0.0
	mat.vertex_color_use_as_albedo = true
	return mat


func _init_noise() -> void:
	if world_seed == 0:
		world_seed = randi()
	terrain_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	terrain_noise.seed = world_seed
	terrain_noise.frequency = terrain_frequency
	terrain_noise.fractal_octaves = 5 if not mobile_mode else 4
	terrain_noise.fractal_gain = 0.5
	terrain_noise.fractal_lacunarity = 2.0
	detail_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	detail_noise.seed = world_seed + 101
	detail_noise.frequency = terrain_detail_frequency
	detail_noise.fractal_octaves = 3 if not mobile_mode else 2
	detail_noise.fractal_gain = 0.5
	detail_noise.fractal_lacunarity = 2.0
	warp_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	warp_noise.seed = world_seed + 211
	warp_noise.frequency = terrain_warp_frequency
	warp_noise.fractal_octaves = 2
	warp_noise.fractal_gain = 0.5
	warp_noise.fractal_lacunarity = 2.0
	biome_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	biome_noise.seed = world_seed + 419
	biome_noise.frequency = biome_frequency
	biome_noise.fractal_octaves = 3
	biome_noise.fractal_gain = 0.5
	biome_noise.fractal_lacunarity = 2.0
	ridge_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	ridge_noise.seed = world_seed + 307
	ridge_noise.frequency = ridge_frequency
	ridge_noise.fractal_octaves = 4
	ridge_noise.fractal_gain = 0.5
	ridge_noise.fractal_lacunarity = 2.0
	micro_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	micro_noise.seed = world_seed + 509
	micro_noise.frequency = 0.08
	micro_noise.fractal_octaves = 2
	micro_noise.fractal_gain = 0.5
	micro_noise.fractal_lacunarity = 2.0
	ore_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	ore_noise.seed = world_seed + 307
	ore_noise.frequency = ore_frequency
	ore_noise.fractal_octaves = 3
	ore_noise.fractal_gain = 0.5
	ore_noise.fractal_lacunarity = 2.0


func cautare_jucator_securizata() -> void:
	var jucatori: Array = get_tree().get_nodes_in_group("Jucator")
	if jucatori.size() > 0:
		nod_jucator = jucatori[0] as CharacterBody3D


func _actualizeaza_chunk_uri(centru_chunk: Vector2i) -> void:
	var chei_necesare: Array = []
	for x_offset in range(-distanta_randare, distanta_randare + 1):
		for z_offset in range(-distanta_randare, distanta_randare + 1):
			var coord: Vector2i = Vector2i(centru_chunk.x + x_offset, centru_chunk.y + z_offset)
			var key: String = _chunk_key(coord.x, coord.y)
			chei_necesare.append(key)
			var needed_lod: int = _compute_lod_for_chunk(coord.x, coord.y)
			if not chunk_visuals.has(key):
				_enqueue_chunk_generation(coord.x, coord.y, key)
			elif lod_enabled:
				var existing: Dictionary = chunk_visuals[key]
				if existing.get("lod", -1) != needed_lod:
					_clear_chunk_visuals(key)
					_enqueue_chunk_generation(coord.x, coord.y, key)
	for existing_key in chunk_visuals.keys():
		if not chei_necesare.has(existing_key):
			_clear_chunk_visuals(existing_key)


func _enqueue_chunk_generation(cx: int, cz: int, key: String) -> void:
	if chunk_generation_pending.has(key):
		return
	var data: Dictionary = {"cx": cx, "cz": cz, "key": key}
	chunk_generation_queue.append(data)
	chunk_generation_pending[key] = data


func _process_chunk_queue() -> void:
	if generating_chunk:
		return
	generating_chunk = true
	var batch: int = 1
	for b in range(batch):
		if chunk_generation_queue.is_empty():
			break
		var data: Dictionary = chunk_generation_queue.pop_front()
		chunk_generation_pending.erase(data["key"])
		if not _is_chunk_within_render_distance(data["cx"], data["cz"]):
			continue
		_genereaza_singur_chunk(data["cx"], data["cz"], data["key"])
	generating_chunk = false
	if not chunk_generation_queue.is_empty():
		call_deferred("_process_chunk_queue")


func _genereaza_singur_chunk(cx: int, cz: int, key: String) -> void:
	_clear_chunk_visuals(key)
	var lod_level: int = 0
	var res_mult: int = 1
	var root := Node3D.new()
	root.name = "Chunk_%s" % key.replace(",", "_")
	add_child(root)
	chunk_visuals[key] = {"root": root, "lod": 0}
	var mesh: ArrayMesh = _create_chunk_surface_mesh_extended(cx, cz, res_mult)
	if mesh == null:
		return
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = mesh
	mesh_inst.material_override = chunk_material
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_inst.name = "Mesh"
	root.add_child(mesh_inst)
	if lod_level == 0:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 1
		var cs := CollisionShape3D.new()
		cs.shape = mesh.create_trimesh_shape()
		body.add_child(cs)
		root.add_child(body)
		chunk_visuals[key]["collision_body"] = body
	chunk_visuals[key]["mesh_instance"] = mesh_inst
	var biome: int = get_dominant_biome_at(cx * chunk_dimensions + int(chunk_dimensions * 0.5), cz * chunk_dimensions + int(chunk_dimensions * 0.5))
	genereaza_structuri_specifice_zonei(root, cx, cz, biome)
	_sync_modified_blocks_from_overrides(key)


func _create_chunk_surface_mesh(cx: int, cz: int, lod_mult: int = 1) -> ArrayMesh:
	var step_count: int = max(1, surface_resolution)
	var lod_step: int = max(1, lod_mult)
	var sample_count: int = int(floor(float(chunk_dimensions * step_count) / float(lod_step)))
	if sample_count < 1:
		sample_count = 1
	var start_x: float = float(cx * chunk_dimensions)
	var start_z: float = float(cz * chunk_dimensions)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var heights: Array = []
	heights.resize(sample_count + 1)
	for x in range(sample_count + 1):
		heights[x] = []
		heights[x].resize(sample_count + 1)
		var wx: float = start_x + float(x * lod_step) / float(step_count)
		for z in range(sample_count + 1):
			var wz: float = start_z + float(z * lod_step) / float(step_count)
			heights[x][z] = get_surface_height_at(wx, wz)
	var normals: Array = []
	normals.resize(sample_count + 1)
	for x in range(sample_count + 1):
		normals[x] = []
		normals[x].resize(sample_count + 1)
		for z in range(sample_count + 1):
			var hL: float = heights[max(0, x - 1)][z]
			var hR: float = heights[min(sample_count, x + 1)][z]
			var hD: float = heights[x][max(0, z - 1)]
			var hU: float = heights[x][min(sample_count, z + 1)]
			var step_world: float = float(lod_step) / float(step_count)
			normals[x][z] = Vector3((hL - hR) / step_world, 2.0, (hD - hU) / step_world).normalized()
	for x in range(sample_count):
		var x0: float = start_x + float(x * lod_step) / float(step_count)
		var x1: float = start_x + float((x + 1) * lod_step) / float(step_count)
		for z in range(sample_count):
			var z0: float = start_z + float(z * lod_step) / float(step_count)
			var z1: float = start_z + float((z + 1) * lod_step) / float(step_count)
			var h00: float = heights[x][z]
			var h10: float = heights[x + 1][z]
			var h01: float = heights[x][z + 1]
			var h11: float = heights[x + 1][z + 1]
			var n00: Vector3 = normals[x][z]
			var n10: Vector3 = normals[x + 1][z]
			var n01: Vector3 = normals[x][z + 1]
			var n11: Vector3 = normals[x + 1][z + 1]
			st.set_normal(n00)
			st.set_color(_surface_color_for_biome(h00, int(x0), int(z0), n00))
			st.add_vertex(Vector3(x0, h00, z0))
			st.set_normal(n10)
			st.set_color(_surface_color_for_biome(h10, int(x1), int(z0), n10))
			st.add_vertex(Vector3(x1, h10, z0))
			st.set_normal(n01)
			st.set_color(_surface_color_for_biome(h01, int(x0), int(z1), n01))
			st.add_vertex(Vector3(x0, h01, z1))
			st.set_normal(n10)
			st.set_color(_surface_color_for_biome(h10, int(x1), int(z0), n10))
			st.add_vertex(Vector3(x1, h10, z0))
			st.set_normal(n11)
			st.set_color(_surface_color_for_biome(h11, int(x1), int(z1), n11))
			st.add_vertex(Vector3(x1, h11, z1))
			st.set_normal(n01)
			st.set_color(_surface_color_for_biome(h01, int(x0), int(z1), n01))
			st.add_vertex(Vector3(x0, h01, z1))
	st.index()
	return st.commit()


func _create_chunk_surface_mesh_extended(cx: int, cz: int, lod_mult: int = 1) -> ArrayMesh:
	var step_count: int = max(1, surface_resolution)
	var lod_step: int = max(1, lod_mult)
	var extra: int = 1
	var sample_count: int = int(floor(float(chunk_dimensions * step_count) / float(lod_step))) + extra * 2
	if sample_count < 1:
		sample_count = 1
	var start_x: float = float(cx * chunk_dimensions) - float(extra * lod_step) / float(step_count)
	var start_z: float = float(cz * chunk_dimensions) - float(extra * lod_step) / float(step_count)
	var col_min_x: int = int(floor(start_x))
	var col_min_z: int = int(floor(start_z))
	var col_max_x: int = int(ceil(start_x + float(sample_count * lod_step) / float(step_count)))
	var col_max_z: int = int(ceil(start_z + float(sample_count * lod_step) / float(step_count)))
	var col_w: int = col_max_x - col_min_x + 2
	var col_h: int = col_max_z - col_min_z + 2
	var col_heights: Array = []
	col_heights.resize(col_w)
	for ci in range(col_w):
		col_heights[ci] = []
		col_heights[ci].resize(col_h)
		for cj in range(col_h):
			col_heights[ci][cj] = _get_effective_height(col_min_x + ci, col_min_z + cj)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var heights: Array = []
	heights.resize(sample_count + 1)
	for x in range(sample_count + 1):
		heights[x] = []
		heights[x].resize(sample_count + 1)
		var wx: float = start_x + float(x * lod_step) / float(step_count)
		for z in range(sample_count + 1):
			var wz: float = start_z + float(z * lod_step) / float(step_count)
			var ix: int = int(floor(wx))
			var iz: int = int(floor(wz))
			var tx: float = wx - float(ix)
			var tz: float = wz - float(iz)
			var cx0: int = ix - col_min_x
			var cz0: int = iz - col_min_z
			var h00: float = col_heights[cx0][cz0]
			var h10: float = col_heights[cx0 + 1][cz0]
			var h01: float = col_heights[cx0][cz0 + 1]
			var h11: float = col_heights[cx0 + 1][cz0 + 1]
			heights[x][z] = lerp(lerp(h00, h10, tx), lerp(h01, h11, tx), tz)
	var normals: Array = []
	normals.resize(sample_count + 1)
	for x in range(sample_count + 1):
		normals[x] = []
		normals[x].resize(sample_count + 1)
		for z in range(sample_count + 1):
			var hL: float = heights[max(0, x - 1)][z]
			var hR: float = heights[min(sample_count, x + 1)][z]
			var hD: float = heights[x][max(0, z - 1)]
			var hU: float = heights[x][min(sample_count, z + 1)]
			var step_world: float = float(lod_step) / float(step_count)
			normals[x][z] = Vector3((hL - hR) / step_world, 2.0, (hD - hU) / step_world).normalized()
	var tri_start: int = extra
	var tri_end: int = sample_count - extra
	for x in range(tri_start, tri_end):
		var x0: float = start_x + float(x * lod_step) / float(step_count)
		var x1: float = start_x + float((x + 1) * lod_step) / float(step_count)
		for z in range(tri_start, tri_end):
			var z0: float = start_z + float(z * lod_step) / float(step_count)
			var z1: float = start_z + float((z + 1) * lod_step) / float(step_count)
			var h00: float = heights[x][z]
			var h10: float = heights[x + 1][z]
			var h01: float = heights[x][z + 1]
			var h11: float = heights[x + 1][z + 1]
			var n00: Vector3 = normals[x][z]
			var n10: Vector3 = normals[x + 1][z]
			var n01: Vector3 = normals[x][z + 1]
			var n11: Vector3 = normals[x + 1][z + 1]
			st.set_normal(n00)
			st.set_color(_surface_color_for_biome(h00, int(x0), int(z0), n00))
			st.add_vertex(Vector3(x0, h00, z0))
			st.set_normal(n10)
			st.set_color(_surface_color_for_biome(h10, int(x1), int(z0), n10))
			st.add_vertex(Vector3(x1, h10, z0))
			st.set_normal(n01)
			st.set_color(_surface_color_for_biome(h01, int(x0), int(z1), n01))
			st.add_vertex(Vector3(x0, h01, z1))
			st.set_normal(n10)
			st.set_color(_surface_color_for_biome(h10, int(x1), int(z0), n10))
			st.add_vertex(Vector3(x1, h10, z0))
			st.set_normal(n11)
			st.set_color(_surface_color_for_biome(h11, int(x1), int(z1), n11))
			st.add_vertex(Vector3(x1, h11, z1))
			st.set_normal(n01)
			st.set_color(_surface_color_for_biome(h01, int(x0), int(z1), n01))
			st.add_vertex(Vector3(x0, h01, z1))
	st.index()
	return st.commit()


func _create_chunk_surface_mesh_smooth(cx: int, cz: int, lod_mult: int = 1) -> ArrayMesh:
	var step_count: int = max(1, surface_resolution * 2)
	var lod_step: int = max(1, lod_mult)
	var extra: int = 1
	var sample_count: int = int(floor(float(chunk_dimensions * step_count) / float(lod_step))) + extra * 2
	if sample_count < 1:
		sample_count = 1
	var start_x: float = float(cx * chunk_dimensions) - float(extra * lod_step) / float(step_count)
	var start_z: float = float(cz * chunk_dimensions) - float(extra * lod_step) / float(step_count)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var heights: Array = []
	heights.resize(sample_count + 1)
	for x in range(sample_count + 1):
		heights[x] = []
		heights[x].resize(sample_count + 1)
		var wx: float = start_x + float(x * lod_step) / float(step_count)
		for z in range(sample_count + 1):
			var wz: float = start_z + float(z * lod_step) / float(step_count)
			heights[x][z] = _sample_surface_height(wx, wz)
	var normals: Array = []
	normals.resize(sample_count + 1)
	for x in range(sample_count + 1):
		normals[x] = []
		normals[x].resize(sample_count + 1)
		for z in range(sample_count + 1):
			var hL: float = heights[max(0, x - 1)][z]
			var hR: float = heights[min(sample_count, x + 1)][z]
			var hD: float = heights[x][max(0, z - 1)]
			var hU: float = heights[x][min(sample_count, z + 1)]
			var step_world: float = float(lod_step) / float(step_count)
			normals[x][z] = Vector3((hL - hR) / step_world, 2.0, (hD - hU) / step_world).normalized()
	var tri_start: int = extra
	var tri_end: int = sample_count - extra
	for x in range(tri_start, tri_end):
		var x0: float = start_x + float(x * lod_step) / float(step_count)
		var x1: float = start_x + float((x + 1) * lod_step) / float(step_count)
		for z in range(tri_start, tri_end):
			var z0: float = start_z + float(z * lod_step) / float(step_count)
			var z1: float = start_z + float((z + 1) * lod_step) / float(step_count)
			var h00: float = heights[x][z]
			var h10: float = heights[x + 1][z]
			var h01: float = heights[x][z + 1]
			var h11: float = heights[x + 1][z + 1]
			var n00: Vector3 = normals[x][z]
			var n10: Vector3 = normals[x + 1][z]
			var n01: Vector3 = normals[x][z + 1]
			var n11: Vector3 = normals[x + 1][z + 1]
			st.set_normal(n00)
			st.set_color(_surface_color_for_biome(h00, int(x0), int(z0), n00))
			st.add_vertex(Vector3(x0, h00, z0))
			st.set_normal(n10)
			st.set_color(_surface_color_for_biome(h10, int(x1), int(z0), n10))
			st.add_vertex(Vector3(x1, h10, z0))
			st.set_normal(n01)
			st.set_color(_surface_color_for_biome(h01, int(x0), int(z1), n01))
			st.add_vertex(Vector3(x0, h01, z1))
			st.set_normal(n10)
			st.set_color(_surface_color_for_biome(h10, int(x1), int(z0), n10))
			st.add_vertex(Vector3(x1, h10, z0))
			st.set_normal(n11)
			st.set_color(_surface_color_for_biome(h11, int(x1), int(z1), n11))
			st.add_vertex(Vector3(x1, h11, z1))
			st.set_normal(n01)
			st.set_color(_surface_color_for_biome(h01, int(x0), int(z1), n01))
			st.add_vertex(Vector3(x0, h01, z1))
	st.index()
	return st.commit()


func _sample_surface_height(wx: float, wz: float) -> float:
	var x0: int = int(floor(wx))
	var z0: int = int(floor(wz))
	var x1: int = x0 + 1
	var z1: int = z0 + 1
	var tx: float = wx - float(x0)
	var tz: float = wz - float(z0)
	var h00: float = get_surface_height_at(float(x0), float(z0))
	var h10: float = get_surface_height_at(float(x1), float(z0))
	var h01: float = get_surface_height_at(float(x0), float(z1))
	var h11: float = get_surface_height_at(float(x1), float(z1))
	return lerp(lerp(h00, h10, tx), lerp(h01, h11, tx), tz)


func _block_type_color(block_type: int) -> Color:
	match block_type:
		BlockType.GRASS: return Color(0.28, 0.70, 0.24)
		BlockType.DIRT: return Color(0.58, 0.40, 0.24)
		BlockType.STONE: return Color(0.52, 0.52, 0.52)
		BlockType.COAL: return Color(0.12, 0.12, 0.12)
		BlockType.IRON: return Color(0.72, 0.72, 0.78)
		BlockType.COPPER: return Color(0.78, 0.48, 0.30)
		BlockType.GOLD: return Color(0.90, 0.78, 0.18)
		BlockType.DIAMOND: return Color(0.35, 0.85, 0.95)
		BlockType.WOOD: return Color(0.50, 0.30, 0.15)
		BlockType.LEAF: return Color(0.15, 0.55, 0.15)
	return Color(0.52, 0.52, 0.52)


func _surface_color_for_biome(height: float, wx: int, wz: int, normal: Vector3) -> Color:
	var noise_h: float = _surface_height_from_noise(wx, wz)
	if height < noise_h:
		var sy: int = int(round(height)) - 1
		if sy >= 0 and sy < max_height_blocks:
			var bt: int = get_block_type_at(wx, sy, wz)
			if bt != BlockType.AIR:
				return _block_type_color(bt)
	var biome: int = get_dominant_biome_at(wx, wz)
	return _surface_color_for_single_biome(height, wx, wz, normal, biome)


func _surface_color_for_single_biome(height: float, _wx: int, _wz: int, _normal: Vector3, biome: int) -> Color:
	if biome == BiomeType.SNOW:
		return Color(0.95, 0.97, 1.0)
	if biome == BiomeType.MOUNTAINS:
		var blend: float = clamp((height - 180.0) / 60.0, 0.0, 1.0)
		return Color(0.45, 0.45, 0.45).lerp(Color(0.7, 0.7, 0.7), blend)
	if biome == BiomeType.DESERT:
		return Color(0.85, 0.74, 0.42)
	if biome == BiomeType.SWAMP:
		return Color(0.35, 0.50, 0.28)
	if biome == BiomeType.FOREST:
		return Color(0.25, 0.55, 0.20)
	if biome == BiomeType.HILLS:
		return Color(0.50, 0.60, 0.25)
	return Color(0.28, 0.70, 0.24)


func _clear_chunk_visuals(key: String) -> void:
	if not chunk_visuals.has(key):
		return
	var data: Dictionary = chunk_visuals[key]
	if data.has("root") and is_instance_valid(data["root"]):
		data["root"].queue_free()
	chunk_visuals.erase(key)
	_cleanup_modified_blocks_for_chunk(key)


func _cleanup_modified_blocks_for_chunk(key: String) -> void:
	var parts: PackedStringArray = key.split(",")
	if parts.size() != 2:
		return
	var cx: int = int(parts[0])
	var cz: int = int(parts[1])
	var min_x: int = cx * chunk_dimensions
	var max_x: int = min_x + chunk_dimensions
	var min_z: int = cz * chunk_dimensions
	var max_z: int = min_z + chunk_dimensions
	var to_remove: Array = []
	for k in modified_block_visuals:
		var kparts: PackedStringArray = k.split(",")
		if kparts.size() == 3:
			var wx: int = int(kparts[0])
			var wz: int = int(kparts[2])
			if wx >= min_x and wx < max_x and wz >= min_z and wz < max_z:
				to_remove.append(k)
	for k in to_remove:
		var body: StaticBody3D = modified_block_visuals[k]
		if is_instance_valid(body):
			body.queue_free()
		modified_block_visuals.erase(k)


func _get_effective_height(wx: int, wz: int) -> float:
	var noise_h: float = _surface_height_from_noise(wx, wz)
	var surface_y: int = int(floor(noise_h))
	if surface_y >= 0 and surface_y < max_height_blocks:
		var top_block: int = get_block_type_at(wx, surface_y, wz)
		if top_block == BlockType.AIR:
			# Surface block dug — find next solid block below and dip the mesh
			for y in range(surface_y - 1, -1, -1):
				if get_block_type_at(wx, y, wz) != BlockType.AIR:
					return float(y)
			return 1.0
	return noise_h


func _sync_modified_blocks_from_overrides(key: String) -> void:
	var parts: PackedStringArray = key.split(",")
	if parts.size() != 2:
		return
	var cx: int = int(parts[0])
	var cz: int = int(parts[1])
	var overrides: Dictionary = _get_override_dict(key, false)
	if overrides.is_empty():
		return
	var min_x: int = cx * chunk_dimensions
	var min_z: int = cz * chunk_dimensions
	for ok in overrides:
		var kparts: PackedStringArray = ok.split(",")
		if kparts.size() == 3:
			var world_x: int = min_x + int(kparts[0])
			var world_y: int = int(kparts[1])
			var world_z: int = min_z + int(kparts[2])
			var block_type: int = int(overrides[ok])
			if block_type != BlockType.AIR:
				_add_visible_block(block_type, world_x, world_y, world_z)
			else:
				_remove_block_visual(world_x, world_y, world_z)


func _chunk_needs_full_scan(_key: String) -> bool:
	return true


func _surface_height_from_noise(world_x: int, world_z: int) -> float:
	var wx: float = float(world_x)
	var wz: float = float(world_z)
	var weights: Array = get_biome_weights(world_x, world_z)
	if weights.is_empty():
		return float(surface_min_height)
	var blended_scale: float = 0.0
	var blended_detail_scale: float = 0.0
	var blended_warp_strength: float = 0.0
	var blended_detail_mix: float = 0.0
	var blended_curve: float = 0.0
	var blended_height_min: float = 0.0
	var blended_height_max: float = 0.0
	for entry in weights:
		var profile: Dictionary = _get_biome_profile(entry["biome"])
		var w: float = entry["weight"]
		blended_scale += float(profile["terrain_scale"]) * w
		blended_detail_scale += float(profile["detail_scale"]) * w
		blended_warp_strength += float(profile["warp_strength"]) * w
		blended_detail_mix += float(profile["detail_mix"]) * w
		blended_curve += float(profile["curve"]) * w
		blended_height_min += float(profile["height_min"]) * w
		blended_height_max += float(profile["height_max"]) * w
	# Keep min/max as floats to allow sub-block heights for smooth rendering
	var h_min: float = clamp(blended_height_min, 0.0, float(max_height_blocks - 1))
	var h_max: float = clamp(blended_height_max, h_min, float(max_height_blocks - 1))
	var warp_x: float = warp_noise.get_noise_2d(wx, wz) * blended_warp_strength
	var warp_z: float = warp_noise.get_noise_2d(wx + 37.0, wz - 23.0) * blended_warp_strength
	var base_noise: float = terrain_noise.get_noise_2d((wx + warp_x) * blended_scale, (wz + warp_z) * blended_scale)
	var detail: float = detail_noise.get_noise_2d(wx * blended_detail_scale, wz * blended_detail_scale) * blended_detail_mix
	var ridge_raw: float = ridge_noise.get_noise_2d(wx * blended_scale * 1.5, wz * blended_scale * 1.5)
	var ridge: float = pow(1.0 - abs(ridge_raw), 2.0) * ridge_mix
	var micro: float = micro_noise.get_noise_2d(wx, wz) * 1.5
	var combined: float = clamp(base_noise * 0.60 + detail + ridge + micro * 0.15, -1.0, 1.0)
	var smooth_value: float = combined * 0.5 + 0.5
	smooth_value = smooth_value * smooth_value * (3.0 - 2.0 * smooth_value)
	smooth_value = pow(smooth_value, blended_curve)
	# Return a float height (no integer rounding) so mesh interpolation is smooth
	return lerp(h_min, h_max, smooth_value)


func _get_surface_normal(wx: float, wz: float) -> Vector3:
	var _h: float = get_surface_height_at(wx, wz)
	var hL: float = get_surface_height_at(wx - 1.0, wz)
	var hR: float = get_surface_height_at(wx + 1.0, wz)
	var hD: float = get_surface_height_at(wx, wz - 1.0)
	var hU: float = get_surface_height_at(wx, wz + 1.0)
	return Vector3(hL - hR, 2.0, hD - hU).normalized()


func _get_base_block_type(world_x: int, world_y: int, world_z: int) -> int:
	if world_y < 0 or world_y >= max_height_blocks:
		return BlockType.AIR
	var surface_y: float = _surface_height_from_noise(world_x, world_z)
	if world_y > surface_y:
		return BlockType.AIR
	var depth: int = int(surface_y) - world_y
	if depth < grass_layers:
		return BlockType.GRASS
	if depth < grass_layers + dirt_layers:
		return BlockType.DIRT
	var ore_value: float = absf(ore_noise.get_noise_3d(
		float(world_x), float(world_y), float(world_z)))
	if ore_value > 0.85:
		return BlockType.DIAMOND
	if ore_value > 0.78:
		return BlockType.GOLD
	if ore_value > 0.68:
		return BlockType.IRON
	if ore_value > 0.57:
		return BlockType.COPPER
	if ore_value > 0.43:
		return BlockType.COAL
	if depth < 10 and surface_y - world_y < 5:
		return BlockType.GRASS
	return BlockType.STONE


func _world_to_grid_info(world_pos: Vector3) -> Variant:
	var gx: int = int(floor(world_pos.x))
	var gy: int = int(floor(world_pos.y))
	var gz: int = int(floor(world_pos.z))
	if gy < 0 or gy >= max_height_blocks:
		return null
	return {"world": Vector3(gx, gy, gz)}


func _get_override_dict(key: String, create: bool = false) -> Dictionary:
	if not chunk_overrides.has(key):
		if create:
			chunk_overrides[key] = {}
		else:
			return {}
	return chunk_overrides[key]


func _override_key(local_x: int, world_y: int, local_z: int) -> String:
	return "%d,%d,%d" % [local_x, world_y, local_z]


func get_block_type_at(world_x: int, world_y: int, world_z: int) -> int:
	if world_y < 0 or world_y >= max_height_blocks:
		return BlockType.AIR
	var chunk_x: int = int(floor(float(world_x) / float(chunk_dimensions)))
	var chunk_z: int = int(floor(float(world_z) / float(chunk_dimensions)))
	var local_x: int = world_x - chunk_x * chunk_dimensions
	var local_z: int = world_z - chunk_z * chunk_dimensions
	var key: String = _chunk_key(chunk_x, chunk_z)
	var overrides: Dictionary = _get_override_dict(key, false)
	if not overrides.is_empty():
		var ok: String = _override_key(local_x, world_y, local_z)
		if overrides.has(ok):
			return int(overrides[ok])
	return _get_base_block_type(world_x, world_y, world_z)


func _is_block_exposed(world_x: int, world_y: int, world_z: int) -> bool:
	if get_block_type_at(world_x, world_y, world_z) == BlockType.AIR:
		return false
	if get_block_type_at(world_x, world_y + 1, world_z) == BlockType.AIR:
		return true
	if get_block_type_at(world_x + 1, world_y, world_z) == BlockType.AIR:
		return true
	if get_block_type_at(world_x - 1, world_y, world_z) == BlockType.AIR:
		return true
	if get_block_type_at(world_x, world_y, world_z + 1) == BlockType.AIR:
		return true
	if get_block_type_at(world_x, world_y, world_z - 1) == BlockType.AIR:
		return true
	return false


func _add_visible_block(block_type: int, world_x: int, world_y: int, world_z: int) -> void:
	var key: String = "%d,%d,%d" % [world_x, world_y, world_z]
	if modified_block_visuals.has(key):
		return
	var body := StaticBody3D.new()
	body.position = Vector3(world_x + 0.5, world_y + 0.5, world_z + 0.5)
	var cs := CollisionShape3D.new()
	cs.shape = BoxShape3D.new()
	body.add_child(cs)
	add_child(body)
	var mi := MeshInstance3D.new()
	mi.mesh = cube_mesh
	mi.material_override = _material_for_block(block_type)
	body.add_child(mi)
	modified_block_visuals[key] = body


func _remove_block_visual(world_x: int, world_y: int, world_z: int) -> void:
	var key: String = "%d,%d,%d" % [world_x, world_y, world_z]
	if not modified_block_visuals.has(key):
		return
	var body: StaticBody3D = modified_block_visuals[key]
	if is_instance_valid(body):
		body.queue_free()
	modified_block_visuals.erase(key)


func _material_for_block(block_type: int) -> StandardMaterial3D:
	match block_type:
		BlockType.GRASS:
			return material_grass
		BlockType.DIRT:
			return material_dirt
		BlockType.STONE:
			return material_stone
		BlockType.COAL:
			return material_coal
		BlockType.IRON:
			return material_iron
		BlockType.COPPER:
			return material_copper
		BlockType.GOLD:
			return material_gold
		BlockType.DIAMOND:
			return material_diamond
	return material_stone


func _chunk_key(cx: int, cz: int) -> String:
	return "%d,%d" % [cx, cz]


func _compute_lod_for_chunk(cx: int, cz: int) -> int:
	if not lod_enabled or nod_jucator == null:
		return 0
	var dx: float = float(cx * chunk_dimensions) + float(chunk_dimensions) / 2.0 - nod_jucator.global_position.x
	var dz: float = float(cz * chunk_dimensions) + float(chunk_dimensions) / 2.0 - nod_jucator.global_position.z
	var dist: float = sqrt(dx * dx + dz * dz)
	for i in range(lod_distances.size() - 1, -1, -1):
		if dist >= lod_distances[i]:
			return lod_resolutions[i] if i < lod_resolutions.size() else 1
	return 0


func _is_chunk_within_render_distance(cx: int, cz: int) -> bool:
	if nod_jucator == null or not nod_jucator.is_inside_tree():
		return true
	var p = nod_jucator.global_position
	var dx: float = absf(float(cx * chunk_dimensions) + float(chunk_dimensions) / 2.0 - p.x)
	var dz: float = absf(float(cz * chunk_dimensions) + float(chunk_dimensions) / 2.0 - p.z)
	return dx <= distanta_randare * chunk_dimensions and dz <= distanta_randare * chunk_dimensions


func _request_rebuild_for_world(world_x: int, world_z: int, radius_blocks: int) -> void:
	var chunk_x: int = int(floor(float(world_x) / float(chunk_dimensions)))
	var chunk_z: int = int(floor(float(world_z) / float(chunk_dimensions)))
	var r_chunks: int = ceil(float(radius_blocks) / float(chunk_dimensions))
	var keys_to_rebuild: Array = []
	for dx in range(-r_chunks, r_chunks + 1):
		for dz in range(-r_chunks, r_chunks + 1):
			keys_to_rebuild.append(_chunk_key(chunk_x + dx, chunk_z + dz))
	for key in keys_to_rebuild:
		var parts: PackedStringArray = key.split(",")
		if parts.size() == 2:
			var cx: int = int(parts[0])
			var cz: int = int(parts[1])
			var data: Dictionary = _get_override_dict(key, false)
			if not data.is_empty() or _chunk_needs_full_scan(key):
				_enqueue_chunk_generation(cx, cz, key)


func _set_override_for_world(world_x: int, world_y: int, world_z: int, block_type: int) -> void:
	if world_y < 0 or world_y >= max_height_blocks:
		return
	var chunk_x: int = int(floor(float(world_x) / float(chunk_dimensions)))
	var chunk_z: int = int(floor(float(world_z) / float(chunk_dimensions)))
	var local_x: int = world_x - chunk_x * chunk_dimensions
	var local_z: int = world_z - chunk_z * chunk_dimensions
	var key: String = _chunk_key(chunk_x, chunk_z)
	var overrides: Dictionary = _get_override_dict(key, true)
	var ok: String = _override_key(local_x, world_y, local_z)
	overrides[ok] = block_type


func _highest_solid_y_at_column(world_x: int, world_z: int) -> int:
	var approx_surface: float = _surface_height_from_noise(world_x, world_z)
	var approx_int: int = int(round(approx_surface))
	var start_y: int = clamp(approx_int + 12, 0, max_height_blocks - 1)
	var lower_bound: int = clamp(approx_int - 64, 0, max_height_blocks - 1)
	for y in range(start_y, lower_bound - 1, -1):
		if get_block_type_at(world_x, y, world_z) != BlockType.AIR:
			return y
	for y in range(lower_bound - 1, -1, -1):
		if get_block_type_at(world_x, y, world_z) != BlockType.AIR:
			return y
	return -1


func get_surface_height_at(wx: float, wz: float) -> float:
	var ix: int = int(floor(wx))
	var iz: int = int(floor(wz))
	var top_y: int = _highest_solid_y_at_column(ix, iz)
	if top_y < 0:
		return 0.0
	return float(top_y + 1)


func ray_pick_block(start: Vector3, direction: Vector3, max_distance: float = 0.0) -> Variant:
	if direction == Vector3.ZERO:
		return null
	var dir: Vector3 = direction.normalized()
	var travel_distance: float = 0.0
	var max_dist: float = max_distance if max_distance > 0.0 else interact_distance
	while travel_distance <= max_dist:
		var current_pos: Vector3 = start + dir * travel_distance
		var info = _world_to_grid_info(current_pos)
		if info != null:
			var block_type: int = get_block_type_at(int(info["world"].x), int(info["world"].y), int(info["world"].z))
			if block_type != BlockType.AIR:
				var placement_dist: float = max(travel_distance - ray_step, 0.0)
				var placement_pos: Vector3 = start + dir * placement_dist
				var placement_info = _world_to_grid_info(placement_pos)
				return {
					"hit": info,
					"placement": placement_info
				}
		travel_distance += ray_step
	return null


func sapa_bloc(start: Vector3, direction: Vector3) -> int:
	if direction == Vector3.ZERO:
		return BlockType.AIR
	var hit: Variant = ray_pick_block(start, direction)
	if hit == null or hit is bool:
		return BlockType.AIR
	var world_pos: Vector3 = hit["hit"]["world"]
	return sapa_bloc_la_pozitie(world_pos)

func sapa_bloc_la_pozitie(world_pos: Vector3) -> int:
	var wx: int = int(world_pos.x)
	var wy: int = int(world_pos.y)
	var wz: int = int(world_pos.z)
	var block: int = get_block_type_at(wx, wy, wz)
	if block == BlockType.AIR:
		return BlockType.AIR
	_set_override_for_world(wx, wy, wz, BlockType.AIR)
	_remove_block_visual(wx, wy, wz)
	_request_rebuild_for_world(wx, wz, 0)
	return block


func sapa_sfera(start: Vector3, direction: Vector3, raza_sfera: float = 3.0) -> Array:
	if direction == Vector3.ZERO:
		return []
	var hit: Variant = ray_pick_block(start, direction)
	if hit == null or hit is bool:
		return []
	var world_pos: Vector3 = hit["hit"]["world"]
	var center_x: int = int(world_pos.x)
	var center_y: int = int(world_pos.y)
	var center_z: int = int(world_pos.z)
	var radius_i: int = int(ceil(raza_sfera))
	var removed: Array = []
	var affected: Dictionary = {}
	for dx in range(-radius_i, radius_i + 1):
		for dy in range(-radius_i, radius_i + 1):
			for dz in range(-radius_i, radius_i + 1):
				var dist_sq: float = float(dx * dx + dy * dy + dz * dz)
				if dist_sq <= raza_sfera * raza_sfera:
					var wx: int = center_x + dx
					var wy: int = center_y + dy
					var wz: int = center_z + dz
					if wy >= 0 and wy < max_height_blocks:
						var block: int = get_block_type_at(wx, wy, wz)
						if block != BlockType.AIR:
							_set_override_for_world(wx, wy, wz, BlockType.AIR)
							_remove_block_visual(wx, wy, wz)
							removed.append(block)
							var ck: String = _chunk_key(int(floor(float(wx) / float(chunk_dimensions))), int(floor(float(wz) / float(chunk_dimensions))))
							affected[ck] = true
	if not removed.is_empty():
		for ck in affected:
			var parts: PackedStringArray = ck.split(",")
			if parts.size() == 2:
				_enqueue_chunk_generation(int(parts[0]), int(parts[1]), ck)
	return removed


func adauga_bloc(start: Vector3, direction: Vector3, block_type: int) -> bool:
	if direction == Vector3.ZERO:
		return false
	var hit: Variant = ray_pick_block(start, direction)
	if hit == null or hit is bool:
		return false
	if hit["placement"] == null:
		return false
	var world_pos: Vector3 = hit["placement"]["world"]
	var wx: int = int(world_pos.x)
	var wy: int = int(world_pos.y)
	var wz: int = int(world_pos.z)
	var existing: int = get_block_type_at(wx, wy, wz)
	if existing != BlockType.AIR:
		return false
	_set_override_for_world(wx, wy, wz, block_type)
	_add_visible_block(block_type, wx, wy, wz)
	_request_rebuild_for_world(wx, wz, 0)
	return true


func _collect_rebuild_keys_for_world(world_x: int, world_z: int, radius_chunks: int) -> Array:
	var chunk_x: int = int(floor(float(world_x) / float(chunk_dimensions)))
	var chunk_z: int = int(floor(float(world_z) / float(chunk_dimensions)))
	var keys: Array = []
	for dx in range(-radius_chunks, radius_chunks + 1):
		for dz in range(-radius_chunks, radius_chunks + 1):
			keys.append(_chunk_key(chunk_x + dx, chunk_z + dz))
	return keys


func _material_name_for_block(_block_type: int) -> String:
	return "stone"


func get_biome_at(world_x: int, world_z: int) -> int:
	var raw: float = biome_noise.get_noise_2d(float(world_x) * biome_amplitude, float(world_z) * biome_amplitude)
	var best_biome: int = BiomeType.PLAINS
	var best_dist: float = 999.0
	for biome_id: int in BIOME_CENTERS:
		var center: float = BIOME_CENTERS[biome_id]
		var dist: float = abs(raw - center)
		if dist < best_dist:
			best_dist = dist
			best_biome = biome_id
	if best_dist > BIOME_BLEND_SPREAD:
		return BiomeType.PLAINS
	return best_biome


func get_biome_weights(world_x: int, world_z: int) -> Array:
	var raw: float = biome_noise.get_noise_2d(float(world_x) * biome_amplitude, float(world_z) * biome_amplitude)
	var result: Array = []
	var total_weight: float = 0.0
	for biome_id: int in BIOME_CENTERS:
		var center: float = BIOME_CENTERS[biome_id]
		var dist: float = abs(raw - center)
		var weight: float = 1.0 - dist / BIOME_BLEND_SPREAD
		weight = max(weight, 0.0)
		weight = smoothstep(0.0, 1.0, weight)
		if weight > 0.001:
			result.append({"biome": biome_id, "weight": weight})
			total_weight += weight
	if total_weight > 0.0:
		for entry in result:
			entry["weight"] /= total_weight
	return result


func get_dominant_biome_at(world_x: int, world_z: int) -> int:
	var weights: Array = get_biome_weights(world_x, world_z)
	if weights.is_empty():
		return BiomeType.PLAINS
	var best: int = weights[0]["biome"]
	var best_w: float = weights[0]["weight"]
	for entry in weights:
		if entry["weight"] > best_w:
			best_w = entry["weight"]
			best = entry["biome"]
	return best


func get_biome_name_at(world_x: int, world_z: int) -> String:
	var biome: int = get_dominant_biome_at(world_x, world_z)
	match biome:
		BiomeType.PLAINS:
			return "Plains"
		BiomeType.FOREST:
			return "Forest"
		BiomeType.HILLS:
			return "Hills"
		BiomeType.DESERT:
			return "Desert"
		BiomeType.SWAMP:
			return "Swamp"
		BiomeType.SNOW:
			return "Snow"
		BiomeType.MOUNTAINS:
			return "Mountains"
	return "Unknown"



func _get_biome_profile(biome: int) -> Dictionary:
	var h_min: float = float(surface_min_height)
	var h_max: float = float(surface_max_height)
	match biome:
		BiomeType.PLAINS:
			return {"terrain_scale": 0.025, "detail_scale": 0.05, "warp_strength": 4.0, "detail_mix": 0.3, "curve": 0.7, "height_min": 115.0, "height_max": 130.0}
		BiomeType.FOREST:
			return {"terrain_scale": 0.028, "detail_scale": 0.055, "warp_strength": 4.5, "detail_mix": 0.35, "curve": 0.7, "height_min": 116.0, "height_max": 133.0}
		BiomeType.HILLS:
			return {"terrain_scale": 0.030, "detail_scale": 0.06, "warp_strength": 5.0, "detail_mix": 0.4, "curve": 0.75, "height_min": 118.0, "height_max": 138.0}
		BiomeType.DESERT:
			return {"terrain_scale": 0.022, "detail_scale": 0.04, "warp_strength": 2.0, "detail_mix": 0.2, "curve": 0.65, "height_min": 114.0, "height_max": 128.0}
		BiomeType.SWAMP:
			return {"terrain_scale": 0.024, "detail_scale": 0.045, "warp_strength": 3.0, "detail_mix": 0.25, "curve": 0.6, "height_min": 113.0, "height_max": 126.0}
		BiomeType.SNOW:
			return {"terrain_scale": 0.030, "detail_scale": 0.055, "warp_strength": 4.0, "detail_mix": 0.35, "curve": 0.7, "height_min": 118.0, "height_max": 138.0}
		BiomeType.MOUNTAINS:
			return {"terrain_scale": 0.035, "detail_scale": 0.06, "warp_strength": 5.0, "detail_mix": 0.4, "curve": 0.8, "height_min": 117.0, "height_max": 142.0}
	return {"terrain_scale": 0.025, "detail_scale": 0.05, "warp_strength": 4.0, "detail_mix": 0.3, "curve": 0.7, "height_min": h_min, "height_max": h_max}


func _genereaza_casa(root: Node3D, wx: float, wz: float, h: float, _rng: RandomNumberGenerator) -> void:
	var offsets: Array[Vector2i] = []
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			offsets.append(Vector2i(dx, dz))
	for off in offsets:
		_plaseaza_un_bloc(root, wx + off.x, h + 0.5, wz + off.y, BlockType.WOOD)
	for off in offsets:
		if off.x == 0 and off.y == 0:
			continue
		_plaseaza_un_bloc(root, wx + off.x, h + 1.5, wz + off.y, BlockType.WOOD)
		_plaseaza_un_bloc(root, wx + off.x, h + 2.5, wz + off.y, BlockType.WOOD)
	for off in offsets:
		_plaseaza_un_bloc(root, wx + off.x, h + 3.5, wz + off.y, BlockType.STONE)


func genereaza_structuri_specifice_zonei(root: Node3D, cx: int, cz: int, biome: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(cx, cz)) + world_seed
	var min_x: float = float(cx * chunk_dimensions)
	var max_x: float = float((cx + 1) * chunk_dimensions)
	var min_z: float = float(cz * chunk_dimensions)
	var max_z: float = float((cz + 1) * chunk_dimensions)

	var natural_count: int = _structuri_naturale_count(biome)
	for i in range(natural_count):
		var wx: float = float(rng.randi_range(int(min_x), int(max_x) - 1)) + 0.5
		var wz: float = float(rng.randi_range(int(min_z), int(max_z) - 1)) + 0.5
		var h: float = _sample_surface_height(wx, wz)
		if rng.randi() % 3 < 2:
			_genereaza_copac(root, wx, wz, h, rng)
		else:
			_genereaza_piatra(root, wx, wz, h, rng)

	var prob: float = _structuri_constructii_chance(biome)
	if rng.randf() < prob:
		var wx: float = float(rng.randi_range(int(min_x), int(max_x) - 1)) + 0.5
		var wz: float = float(rng.randi_range(int(min_z), int(max_z) - 1)) + 0.5
		var h: float = _sample_surface_height(wx, wz)
		_genereaza_casa(root, wx, wz, h, rng)

	if not structuri_inamici.is_empty():
		var count: int = _structuri_inamici_count(biome)
		for i in range(count):
			var wx: float = float(rng.randi_range(int(min_x), int(max_x) - 1)) + 0.5
			var wz: float = float(rng.randi_range(int(min_z), int(max_z) - 1)) + 0.5
			var h: float = _sample_surface_height(wx, wz)
			var scena: PackedScene = structuri_inamici[rng.randi() % structuri_inamici.size()]
			var inst: Node3D = scena.instantiate()
			inst.position = Vector3(wx, h, wz)
			inst.rotation.y = rng.randf_range(0.0, TAU)
			root.add_child(inst)


func _structuri_naturale_count(biome: int) -> int:
	var base: int
	match biome:
		BiomeType.FOREST: base = 8
		BiomeType.SWAMP: base = 6
		BiomeType.HILLS: base = 5
		BiomeType.PLAINS: base = 4
		BiomeType.MOUNTAINS: base = 3
		BiomeType.DESERT: base = 2
		BiomeType.SNOW: base = 1
		_: base = 3
	return max(1, int(round(float(base) * _WC.tree_density)))


func _structuri_constructii_chance(biome: int) -> float:
	match biome:
		BiomeType.PLAINS: return 0.5
		BiomeType.HILLS: return 0.3
	return 0.0


func _structuri_inamici_count(biome: int) -> int:
	match biome:
		BiomeType.SWAMP: return 3
		BiomeType.FOREST: return 2
		BiomeType.MOUNTAINS: return 2
	return 0

# --- MULTIPLAYER RPCs ---

func _verifica_multiplayer() -> void:
	if _NM.peer != null:
		set_multiplayer_authority(1)

func _on_terrain_change(player_id: int, pos: Array, block_type: int, action_type: String) -> void:
	if pos.size() != 3:
		return
	var world_pos = Vector3(pos[0], pos[1], pos[2])
	if action_type == "dig":
		sapa_bloc_la_pozitie(world_pos)
	elif action_type == "place":
		_plaseaza_un_bloc(self, world_pos.x, world_pos.y, world_pos.z, block_type)
