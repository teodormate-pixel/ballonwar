class_name TerenProceduralTerrain
extends Node3D
@onready var _NM = get_node("/root/NetworkManager")
@onready var _WC = get_node("/root/WorldConfig")

signal generation_progress(progress: float, loaded_chunks: int, total_chunks: int, phase: String)
signal terrain_ready

enum BlockType { AIR, GRASS, DIRT, STONE, COAL, IRON, COPPER, GOLD, DIAMOND, WOOD, LEAF }
enum BiomeType { PLAINS, FOREST, HILLS, DESERT, SWAMP, SNOW, MOUNTAINS, OCEAN, RIVER }

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
@export var biome_frequency: float = 0.0035
@export var biome_amplitude: float = 3.0

@export var ore_frequency: float = 0.04
@export var ore_vertical_frequency: float = 0.05

@export var ridge_frequency: float = 0.025
@export var ridge_strength: float = 0.8
@export var ridge_mix: float = 0.05

@export var lod_enabled: bool = false
@export var lod_distances: Array = [0.0, 30.0, 60.0]
@export var lod_resolutions: Array = [1, 2, 4]
@export var mobile_mode: bool = false
@export var generation_time_budget_ms: int = 8
@export var water_patch_resolution: int = 4

@export_group("Pesteri")
@export var cave_enabled: bool = true
@export var cave_frequency: float = 0.025
@export var cave_threshold: float = 0.35
@export var cave_surface_multiplier: float = 5.0
@export var cave_max_depth: int = 48
@export var cave_min_y: int = 8
@export var cave_entrance_chance: float = 0.01
@export var cave_entrance_depth: int = 24
@export var cave_entrance_width: int = 2
@export var cave_branching_iterations: int = 3

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
var river_noise: FastNoiseLite = FastNoiseLite.new()
var ocean_mask_noise: FastNoiseLite = FastNoiseLite.new()
var cave_noise: FastNoiseLite = FastNoiseLite.new()
var cave_system: CaveSystem

var chunk_jucator_vechi: Vector2i = Vector2i(-999, -999)
var chunk_centrul_activ: Vector2i = Vector2i.ZERO
var nod_jucator: CharacterBody3D = null

var chunk_visuals: Dictionary = {}
var _pending_post_sync: Array = []
var _pending_post_sync_keys: Dictionary = {}
var chunk_overrides: Dictionary = {}
var modified_block_visuals: Dictionary = {}
var chunk_generation_queue: Array = []
var chunk_generation_pending: Dictionary = {}
var blocuri_structuri_sterse: Dictionary = {}
var generating_chunk: bool = false
var highlight_block: MeshInstance3D = null

var cave_wall_nodes: Dictionary = {}
var chunk_caves_generated: Dictionary = {}
var smooth_cave_meshes: Dictionary = {}
var _pending_cave_mesh_queue: Array = []
var _cave_mesh_tasks: Dictionary = {}
var _cave_mesh_mutex: Mutex

var _cave_carving_queue: Array = []
var _cave_carving_tasks: Dictionary = {}
var _cave_carving_mutex: Mutex

var generation_target_chunks: int = 0
var generation_completed_chunks: int = 0
var generation_order_counter: int = 0
var initial_generation_started: bool = false
var terrain_ready_emitted: bool = false
var _player_spawn_chunk: Vector2i = Vector2i.ZERO

var last_dug_world_pos: Vector3 = Vector3.ZERO

var generation_mutex: Mutex
var generation_tasks: Dictionary = {}  # key -> Dictionary with done flag + result
var block_multimesh_material: StandardMaterial3D
var _sync_budget_ms: int = 4

const MAX_THREADS: int = 4

var material_grass: StandardMaterial3D
var material_dirt: StandardMaterial3D
var material_stone: StandardMaterial3D
var material_coal: StandardMaterial3D
var material_iron: StandardMaterial3D
var material_copper: StandardMaterial3D
var material_gold: StandardMaterial3D
var material_diamond: StandardMaterial3D
var material_water
var chunk_material: ShaderMaterial
var cave_material: StandardMaterial3D
var cube_mesh: BoxMesh = BoxMesh.new()

const BIOME_CENTERS: Dictionary = {
	0: -0.22,
	1: -0.08,
	2: 0.04,
	3: 0.16,
	4: 0.28,
	5: 0.40,
	6: 0.52,
	7: -0.34
}
const WATER_LEVEL: float = 66.0
const BIOME_BLEND_SPREAD: float = 0.25
const BlockScenaScene = preload("res://scenes/entities/BlockScena.tscn")

func _ready() -> void:
	generation_mutex = Mutex.new()
	_cave_mesh_mutex = Mutex.new()
	_cave_carving_mutex = Mutex.new()
	lod_enabled = false
	mobile_mode = true
	cave_enabled = _WC.cave_enabled
	cave_enabled = false # disabled until terrain is stable
	_init_materials()
	block_multimesh_material = _make_material(Color.WHITE)
	block_multimesh_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if _WC.world_seed != 0:
		world_seed = _WC.world_seed
	surface_min_height = _WC.surface_min_height
	surface_max_height = _WC.surface_max_height
	terrain_frequency = _WC.terrain_frequency
	terrain_detail_frequency = _WC.terrain_frequency * 1.5
	terrain_warp_strength = _WC.terrain_warp_strength
	terrain_curve = _WC.terrain_curve
	biome_frequency = _WC.biome_frequency
	biome_amplitude = _WC.biome_amplitude
	ridge_strength = _WC.ridge_strength
	ridge_mix = _WC.ridge_mix
	_init_noise()
	_populeaza_structuri_default()
	cube_mesh.size = Vector3.ONE
	highlight_block = _create_highlight_block()
	call_deferred("_begin_initial_generation")
	if _NM.room_id != "":
		_NM.terrain_change.connect(_on_terrain_change)


func _begin_initial_generation() -> void:
	if initial_generation_started:
		return
	initial_generation_started = true
	cautare_jucator_securizata()
	var start_chunk: Vector2i = Vector2i.ZERO
	if nod_jucator != null:
		start_chunk = Vector2i(
			int(floor(nod_jucator.global_position.x / float(chunk_dimensions))),
			int(floor(nod_jucator.global_position.z / float(chunk_dimensions)))
		)
	chunk_centrul_activ = start_chunk
	chunk_jucator_vechi = start_chunk
	_player_spawn_chunk = start_chunk
	_actualizeaza_chunk_uri(start_chunk)
	generation_target_chunks = max(1, chunk_generation_queue.size())
	generation_completed_chunks = 0
	_emit_generation_progress("Generating terrain...")
	call_deferred("_process_chunk_queue")


func _emit_generation_progress(phase: String = "") -> void:
	if terrain_ready_emitted:
		return
	var total: int = max(1, generation_target_chunks)
	var progress: float = clamp(float(generation_completed_chunks) / float(total), 0.0, 1.0)
	generation_progress.emit(progress, generation_completed_chunks, total, phase)


func _mark_terrain_ready() -> void:
	if terrain_ready_emitted:
		return
	terrain_ready_emitted = true
	var total: int = max(1, generation_target_chunks)
	generation_progress.emit(1.0, total, total, "World ready")
	terrain_ready.emit()


func _chunk_generation_priority(cx: int, cz: int) -> int:
	var center: Vector2i = chunk_centrul_activ
	var base_dist: int = abs(cx - center.x) + abs(cz - center.y)
	if nod_jucator != null and is_instance_valid(nod_jucator):
		var dir: Vector3 = -nod_jucator.global_transform.basis.z
		var dx: float = float(cx - center.x)
		var dz: float = float(cz - center.y)
		var dot: float = dx * dir.x + dz * dir.z
		var bonus: int = int(-dot * 2.0)
		base_dist = maxi(0, base_dist + bonus)
	return base_dist


func _sort_chunk_generation(a: Dictionary, b: Dictionary) -> bool:
	var priority_a: int = int(a.get("priority", 0))
	var priority_b: int = int(b.get("priority", 0))
	if priority_a == priority_b:
		return int(a.get("order", 0)) < int(b.get("order", 0))
	return priority_a < priority_b


func _populeaza_structuri_default() -> void:
	var default_inamici: Array[String] = ["res://scenes/entities/InamicBalon.tscn", "res://scenes/entities/SpawnerInamici.tscn"]
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
	material_grass = _make_pbr_material(Color(0.28, 0.70, 0.24))
	material_grass.uv1_triplanar = true
	material_grass.uv1_triplanar_sharpness = 6.0
	material_grass.uv1_scale = Vector3(0.02, 0.02, 0.02)
	_apply_pbr_texture(material_grass,
		"res://assets/textures/Poliigon_GrassPatchyGround_4585/2K/Poliigon_GrassPatchyGround_4585_BaseColor.jpg",
		"res://assets/textures/Poliigon_GrassPatchyGround_4585/2K/Poliigon_GrassPatchyGround_4585_Normal.png",
		"res://assets/textures/Poliigon_GrassPatchyGround_4585/2K/Poliigon_GrassPatchyGround_4585_Roughness.jpg")

	material_dirt = _make_pbr_material(Color(0.58, 0.40, 0.24))
	material_dirt.uv1_triplanar = true
	material_dirt.uv1_triplanar_sharpness = 6.0
	material_dirt.uv1_scale = Vector3(0.02, 0.02, 0.02)
	_apply_pbr_texture(material_dirt,
		"res://assets/textures/GroundSand005/GroundSand005_COL_2K.jpg",
		"res://assets/textures/GroundSand005/GroundSand005_NRM_2K.jpg",
		"res://assets/textures/GroundSand005/GroundSand005_GLOSS_2K.jpg")

	material_stone = _make_pbr_material(Color(0.52, 0.52, 0.52))
	material_stone.uv1_triplanar = true
	material_stone.uv1_triplanar_sharpness = 6.0
	material_stone.uv1_scale = Vector3(0.02, 0.02, 0.02)
	_apply_pbr_texture(material_stone,
		"res://assets/textures/rocks_ground_04_2k.blend/textures/rocks_ground_04_diff_2k.jpg",
		"res://assets/textures/rocks_ground_04_2k.blend/textures/rocks_ground_04_nor_gl_2k.png",
		"res://assets/textures/rocks_ground_04_2k.blend/textures/rocks_ground_04_rough_2k.jpg")

	material_coal = _make_pbr_material(Color(0.12, 0.12, 0.12))
	material_coal.metallic = 0.1

	material_iron = _make_pbr_material(Color(0.72, 0.72, 0.78))
	material_iron.metallic = 0.35

	material_copper = _make_pbr_material(Color(0.78, 0.48, 0.30))
	material_copper.metallic = 0.4

	material_gold = _make_pbr_material(Color(0.90, 0.78, 0.18))
	material_gold.metallic = 0.7
	material_gold.roughness = 0.25

	material_diamond = _make_pbr_material(Color(0.35, 0.85, 0.95))
	material_diamond.metallic = 0.5
	material_diamond.roughness = 0.1

	if ResourceLoader.exists("res://resources/materials/water.tres"):
		material_water = load("res://resources/materials/water.tres")
		if material_water is StandardMaterial3D:
			material_water.render_priority = 1
			material_water.metallic = 0.3
			material_water.roughness = 0.05
			material_water.albedo_color = Color(0.12, 0.35, 0.55, 0.75)
	else:
		material_water = ShaderMaterial.new()
		material_water.shader = preload("res://resources/water_shader.gdshader")
		material_water.set_shader_parameter("water_color", Color(0.08, 0.42, 0.76, 0.82))
		material_water.set_shader_parameter("wave_speed", 0.45)
		material_water.set_shader_parameter("wave_strength", 0.16)

	chunk_material = _build_chunk_shader_material()

	cave_material = StandardMaterial3D.new()
	cave_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	cave_material.vertex_color_use_as_albedo = true
	cave_material.albedo_color = Color(0.42, 0.42, 0.46)
	cave_material.roughness = 0.85
	cave_material.metallic = 0.05
	cave_material.uv1_triplanar = true
	cave_material.uv1_triplanar_sharpness = 6.0
	cave_material.uv1_scale = Vector3(0.02, 0.02, 0.02)
	_apply_pbr_texture(cave_material,
		"res://assets/textures/rocks_ground_04_2k.blend/textures/rocks_ground_04_diff_2k.jpg",
		"res://assets/textures/rocks_ground_04_2k.blend/textures/rocks_ground_04_nor_gl_2k.png",
		"res://assets/textures/rocks_ground_04_2k.blend/textures/rocks_ground_04_rough_2k.jpg")
	cave_material.emission_enabled = true
	cave_material.emission_energy_multiplier = 0.04
	cave_material.cull_mode = BaseMaterial3D.CULL_DISABLED


func _make_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.roughness = 0.85
	mat.metallic = 0.0
	mat.vertex_color_use_as_albedo = true
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	return mat

func _make_pbr_material(color: Color, roughness: float = 0.9, metallic: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.roughness = roughness
	mat.metallic = metallic
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	return mat

func _build_chunk_shader_material() -> ShaderMaterial:
	var albedo_images: Array[Image] = []
	var normal_images: Array[Image] = []
	var height_images: Array[Image] = []
	var TEX_SIZE := Vector2i(256, 256)
	# 0: Grass
	albedo_images.append(_load_img_resized("res://assets/textures/Poliigon_GrassPatchyGround_4585/2K/Poliigon_GrassPatchyGround_4585_BaseColor.jpg", TEX_SIZE))
	normal_images.append(_load_img_resized("res://assets/textures/Poliigon_GrassPatchyGround_4585/2K/Poliigon_GrassPatchyGround_4585_Normal.png", TEX_SIZE))
	height_images.append(_load_img_resized("res://assets/textures/Poliigon_GrassPatchyGround_4585/2K/Poliigon_GrassPatchyGround_4585_Displacement.png", TEX_SIZE))
	# 1: Dirt
	albedo_images.append(_load_img_resized("res://assets/textures/GroundSand005/GroundSand005_COL_2K.jpg", TEX_SIZE))
	normal_images.append(_load_img_resized("res://assets/textures/GroundSand005/GroundSand005_NRM_2K.jpg", TEX_SIZE))
	height_images.append(_load_img_resized("res://assets/textures/GroundSand005/GroundSand005_DISP_2K.jpg", TEX_SIZE))
	# 2: Stone
	albedo_images.append(_load_img_resized("res://assets/textures/rocks_ground_04_2k.blend/textures/rocks_ground_04_diff_2k.jpg", TEX_SIZE))
	normal_images.append(_load_img_resized("res://assets/textures/rocks_ground_04_2k.blend/textures/rocks_ground_04_nor_gl_2k.png", TEX_SIZE))
	height_images.append(_load_img_resized("res://assets/textures/rocks_ground_04_2k.blend/textures/rocks_ground_04_disp_2k.png", TEX_SIZE))

	var albedo_arr := Texture2DArray.new()
	albedo_arr.create_from_images(albedo_images)
	var normal_arr := Texture2DArray.new()
	normal_arr.create_from_images(normal_images)
	var height_arr := Texture2DArray.new()
	height_arr.create_from_images(height_images)

	var mat := ShaderMaterial.new()
	mat.shader = preload("res://resources/terrain_shader.gdshader")
	mat.set_shader_parameter("terrain_albedo", albedo_arr)
	mat.set_shader_parameter("terrain_normal", normal_arr)
	mat.set_shader_parameter("terrain_height", height_arr)
	mat.set_shader_parameter("texture_scale", 0.1)
	mat.set_shader_parameter("displacement_scale", 0.08)
	return mat

func _load_img_resized(path: String, target_size: Vector2i) -> Image:
	var img := Image.new()
	var err: Error = img.load(path)
	if err != OK:
		img = Image.create(target_size.x, target_size.y, false, Image.FORMAT_RGBA8)
		img.fill(Color.GRAY)
		return img
	if img.get_size() != target_size:
		img.resize(target_size.x, target_size.y, Image.INTERPOLATE_BILINEAR)
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img

func _apply_pbr_texture(mat: StandardMaterial3D, albedo_path: String, normal_path: String, rough_path: String) -> void:
	var albedo_tex: Texture2D = _load_tex(albedo_path)
	if albedo_tex != null:
		mat.albedo_texture = albedo_tex
	var normal_tex: Texture2D = _load_tex(normal_path)
	if normal_tex != null:
		mat.normal_enabled = true
		mat.normal_texture = normal_tex
	var rough_tex: Texture2D = _load_tex(rough_path)
	if rough_tex != null:
		mat.roughness_texture = rough_tex

func _load_tex(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var ext: String = path.get_extension().to_lower()
	if ext in ["exr", "tiff", "tif"]:
		var img: Image = Image.new()
		var err: Error = img.load(path)
		if err != OK:
			return null
		return ImageTexture.create_from_image(img)
	return load(path) as Texture2D

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
	river_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	river_noise.seed = world_seed + 613
	river_noise.frequency = 0.01
	river_noise.fractal_octaves = 3
	river_noise.fractal_gain = 0.5
	river_noise.fractal_lacunarity = 2.0
	ocean_mask_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	ocean_mask_noise.seed = world_seed + 701
	ocean_mask_noise.frequency = 0.001
	ocean_mask_noise.fractal_octaves = 2
	ocean_mask_noise.fractal_gain = 0.5
	ocean_mask_noise.fractal_lacunarity = 2.0
	ore_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	ore_noise.seed = world_seed + 307
	ore_noise.frequency = ore_frequency
	ore_noise.fractal_octaves = 3
	ore_noise.fractal_gain = 0.5
	ore_noise.fractal_lacunarity = 2.0
	cave_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	cave_noise.seed = world_seed + 811
	cave_noise.frequency = cave_frequency
	cave_noise.fractal_octaves = 3
	cave_noise.fractal_gain = 0.5
	cave_noise.fractal_lacunarity = 2.0
	if cave_enabled:
		cave_system = CaveSystem.new()
		cave_system.chunk_dimensions = chunk_dimensions
		cave_system.max_height_blocks = max_height_blocks
		cave_system.cave_min_y = cave_min_y
		cave_system.cave_max_depth = cave_max_depth
		cave_system.cave_threshold = cave_threshold
		cave_system.cave_enabled = cave_enabled
		cave_system.init_noise(world_seed)
		if cave_system.has_signal("generation_progress"):
			cave_system.generation_progress.connect(_on_cave_progress)
		add_child(cave_system)


func _on_cave_progress(progress: float) -> void:
	_emit_generation_progress("Carving caves...")


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
			_clear_cave_walls(existing_key)


func _enqueue_chunk_generation(cx: int, cz: int, key: String) -> void:
	if chunk_generation_pending.has(key):
		return
	var data: Dictionary = {
		"cx": cx,
		"cz": cz,
		"key": key,
		"priority": _chunk_generation_priority(cx, cz),
		"order": generation_order_counter
	}
	generation_order_counter += 1
	chunk_generation_queue.append(data)
	chunk_generation_pending[key] = data
	chunk_generation_queue.sort_custom(Callable(self, "_sort_chunk_generation"))
	if not terrain_ready_emitted:
		generation_target_chunks = max(generation_target_chunks, generation_completed_chunks + chunk_generation_queue.size())
		_emit_generation_progress("Preparing terrain...")


func _capture_noise_params() -> Dictionary:
	return {
		"seed": world_seed,
		"terrain_frequency": terrain_frequency,
		"terrain_detail_frequency": terrain_detail_frequency,
		"terrain_warp_frequency": terrain_warp_frequency,
		"terrain_warp_strength": terrain_warp_strength,
		"terrain_curve": terrain_curve,
		"biome_frequency": biome_frequency,
		"biome_amplitude": biome_amplitude,
		"ore_frequency": ore_frequency,
		"ridge_frequency": ridge_frequency,
		"ridge_strength": ridge_strength,
		"ridge_mix": ridge_mix,
		"surface_min_height": surface_min_height,
		"surface_max_height": surface_max_height,
		"chunk_dimensions": chunk_dimensions,
		"max_height_blocks": max_height_blocks,
		"surface_resolution": surface_resolution,
		"grass_layers": grass_layers,
		"dirt_layers": dirt_layers,
		"WATER_LEVEL": WATER_LEVEL,
		"BIOME_CENTERS": BIOME_CENTERS,
		"BIOME_BLEND_SPREAD": BIOME_BLEND_SPREAD,
		"mobile_mode": mobile_mode,
	}


func _thread_create_noise(params: Dictionary) -> Array:
	var tn := FastNoiseLite.new()
	tn.noise_type = FastNoiseLite.TYPE_PERLIN
	tn.seed = params.seed
	tn.frequency = params.terrain_frequency
	tn.fractal_octaves = 4 if params.get("mobile_mode", false) else 5
	tn.fractal_gain = 0.5
	tn.fractal_lacunarity = 2.0
	var dn := FastNoiseLite.new()
	dn.noise_type = FastNoiseLite.TYPE_PERLIN
	dn.seed = params.seed + 101
	dn.frequency = params.terrain_detail_frequency
	dn.fractal_octaves = 2 if params.get("mobile_mode", false) else 3
	dn.fractal_gain = 0.5
	dn.fractal_lacunarity = 2.0
	var wn := FastNoiseLite.new()
	wn.noise_type = FastNoiseLite.TYPE_PERLIN
	wn.seed = params.seed + 211
	wn.frequency = params.terrain_warp_frequency
	wn.fractal_octaves = 2
	wn.fractal_gain = 0.5
	wn.fractal_lacunarity = 2.0
	var bn := FastNoiseLite.new()
	bn.noise_type = FastNoiseLite.TYPE_PERLIN
	bn.seed = params.seed + 419
	bn.frequency = params.biome_frequency
	bn.fractal_octaves = 3
	bn.fractal_gain = 0.5
	bn.fractal_lacunarity = 2.0
	var rn := FastNoiseLite.new()
	rn.noise_type = FastNoiseLite.TYPE_PERLIN
	rn.seed = params.seed + 307
	rn.frequency = params.ridge_frequency
	rn.fractal_octaves = 4
	rn.fractal_gain = 0.5
	rn.fractal_lacunarity = 2.0
	var mn := FastNoiseLite.new()
	mn.noise_type = FastNoiseLite.TYPE_PERLIN
	mn.seed = params.seed + 509
	mn.frequency = 0.08
	mn.fractal_octaves = 2
	mn.fractal_gain = 0.5
	mn.fractal_lacunarity = 2.0
	var on := FastNoiseLite.new()
	on.noise_type = FastNoiseLite.TYPE_PERLIN
	on.seed = params.seed + 307
	on.frequency = params.ore_frequency
	on.fractal_octaves = 3
	on.fractal_gain = 0.5
	on.fractal_lacunarity = 2.0
	return [tn, dn, wn, bn, rn, mn, on]


func _thread_get_biome_weights(wx: int, wz: int, bn: FastNoiseLite, params: Dictionary) -> Array:
	var raw: float = bn.get_noise_2d(float(wx) * params.biome_amplitude, float(wz) * params.biome_amplitude)
	var result: Array = []
	var total_weight: float = 0.0
	var centers: Dictionary = params.BIOME_CENTERS
	var spread: float = params.BIOME_BLEND_SPREAD
	for biome_id: int in centers:
		var center: float = centers[biome_id]
		var dist: float = abs(raw - center)
		var weight: float = 1.0 - dist / spread
		weight = max(weight, 0.0)
		weight = weight * weight * (3.0 - 2.0 * weight)
		if weight > 0.001:
			result.append({"biome": biome_id, "weight": weight})
			total_weight += weight
	if total_weight > 0.0:
		for entry in result:
			entry["weight"] /= total_weight
	return result


func _thread_get_dominant_biome(wx: int, wz: int, bn: FastNoiseLite, params: Dictionary) -> int:
	var weights: Array = _thread_get_biome_weights(wx, wz, bn, params)
	if weights.is_empty():
		return 0
	var best: int = weights[0]["biome"]
	var best_w: float = weights[0]["weight"]
	for entry in weights:
		if entry["weight"] > best_w:
			best_w = entry["weight"]
			best = entry["biome"]
	return best


func _thread_get_biome_profile(biome: int, params: Dictionary) -> Dictionary:
	match biome:
		0: return {"terrain_scale": 0.025, "detail_scale": 0.05, "warp_strength": 4.0, "detail_mix": 0.3, "curve": 0.7, "height_min": 68.0, "height_max": 80.0}
		1: return {"terrain_scale": 0.028, "detail_scale": 0.055, "warp_strength": 4.5, "detail_mix": 0.35, "curve": 0.7, "height_min": 70.0, "height_max": 82.0}
		2: return {"terrain_scale": 0.030, "detail_scale": 0.06, "warp_strength": 5.0, "detail_mix": 0.4, "curve": 0.75, "height_min": 72.0, "height_max": 86.0}
		3: return {"terrain_scale": 0.022, "detail_scale": 0.04, "warp_strength": 2.0, "detail_mix": 0.2, "curve": 0.65, "height_min": 67.0, "height_max": 78.0}
		4: return {"terrain_scale": 0.024, "detail_scale": 0.045, "warp_strength": 3.0, "detail_mix": 0.25, "curve": 0.6, "height_min": 64.0, "height_max": 72.0}
		5: return {"terrain_scale": 0.030, "detail_scale": 0.055, "warp_strength": 4.0, "detail_mix": 0.35, "curve": 0.7, "height_min": 70.0, "height_max": 84.0}
		6: return {"terrain_scale": 0.035, "detail_scale": 0.06, "warp_strength": 5.0, "detail_mix": 0.4, "curve": 0.8, "height_min": 72.0, "height_max": 90.0}
		7: return {"terrain_scale": 0.01, "detail_scale": 0.02, "warp_strength": 1.0, "detail_mix": 0.05, "curve": 0.3, "height_min": 40.0, "height_max": 55.0}
	return {"terrain_scale": 0.025, "detail_scale": 0.05, "warp_strength": 4.0, "detail_mix": 0.3, "curve": 0.7, "height_min": float(params.surface_min_height), "height_max": float(params.surface_max_height)}


func _thread_surface_height(wx: int, wz: int, noise_arr: Array, params: Dictionary) -> float:
	var tn: FastNoiseLite = noise_arr[0]
	var dn: FastNoiseLite = noise_arr[1]
	var wn: FastNoiseLite = noise_arr[2]
	var bn: FastNoiseLite = noise_arr[3]
	var rn: FastNoiseLite = noise_arr[4]
	var mn: FastNoiseLite = noise_arr[5]
	var wfx: float = float(wx)
	var wfz: float = float(wz)
	var weights: Array = _thread_get_biome_weights(wx, wz, bn, params)
	if weights.is_empty():
		return float(params.surface_min_height)
	var dominant: int = _thread_get_dominant_biome(wx, wz, bn, params)
	if dominant == 7:
		return params.WATER_LEVEL - 2.0 + absf(bn.get_noise_2d(wfx * 0.01, wfz * 0.01)) * 1.0
	var blended_scale: float = 0.0
	var blended_detail_scale: float = 0.0
	var blended_warp_strength: float = 0.0
	var blended_detail_mix: float = 0.0
	var blended_curve: float = 0.0
	var blended_height_min: float = 0.0
	var blended_height_max: float = 0.0
	for entry in weights:
		var profile: Dictionary = _thread_get_biome_profile(entry["biome"], params)
		var w: float = entry["weight"]
		blended_scale += float(profile["terrain_scale"]) * w
		blended_detail_scale += float(profile["detail_scale"]) * w
		blended_warp_strength += float(profile["warp_strength"]) * w
		blended_detail_mix += float(profile["detail_mix"]) * w
		blended_curve += float(profile["curve"]) * w
		blended_height_min += float(profile["height_min"]) * w
		blended_height_max += float(profile["height_max"]) * w
	var h_min: float = clamp(blended_height_min, 0.0, float(params.max_height_blocks - 1))
	var h_max: float = clamp(blended_height_max, h_min, float(params.max_height_blocks - 1))
	var warp_x: float = wn.get_noise_2d(wfx, wfz) * blended_warp_strength
	var warp_z: float = wn.get_noise_2d(wfx + 37.0, wfz - 23.0) * blended_warp_strength
	var base_noise: float = tn.get_noise_2d((wfx + warp_x) * blended_scale, (wfz + warp_z) * blended_scale)
	var detail: float = dn.get_noise_2d(wfx * blended_detail_scale, wfz * blended_detail_scale) * blended_detail_mix
	var ridge_raw: float = rn.get_noise_2d(wfx * blended_scale * 1.5, wfz * blended_scale * 1.5)
	var ridge: float = pow(1.0 - abs(ridge_raw), 2.0) * params.ridge_mix
	var micro: float = mn.get_noise_2d(wfx, wfz) * 1.5
	var combined: float = clamp(base_noise * 0.60 + detail + ridge + micro * 0.15, -1.0, 1.0)
	var smooth_value: float = combined * 0.5 + 0.5
	smooth_value = smooth_value * smooth_value * (3.0 - 2.0 * smooth_value)
	smooth_value = pow(smooth_value, blended_curve)
	return lerp(h_min, h_max, smooth_value)


func _thread_adjust_height(h: float, wx: int, wz: int, cx: int, cz: int, overrides: Dictionary, params: Dictionary) -> float:
	if overrides.is_empty():
		return h
	var local_x: int = wx - cx * int(params.chunk_dimensions)
	var local_z: int = wz - cz * int(params.chunk_dimensions)
	if local_x < 0 or local_x >= int(params.chunk_dimensions) or local_z < 0 or local_z >= int(params.chunk_dimensions):
		return h
	var test_y: int = int(floor(h))
	var ok: String = "%d,%d,%d" % [local_x, test_y, local_z]
	if overrides.has(ok) and int(overrides[ok]) == 0:
		for y in range(test_y - 1, int(params.surface_min_height) - 2, -1):
			var k: String = "%d,%d,%d" % [local_x, y, local_z]
			if not overrides.has(k):
				return float(y + 1)
			if int(overrides[k]) != 0:
				return float(y + 1)
		return max(float(params.surface_min_height), float(params.WATER_LEVEL) - 2.0)
	return h


func _adjust_column_height(h: float, wx: int, wz: int, world_overrides: Dictionary, params: Dictionary) -> float:
	var test_y: int = int(floor(h))
	var ok: String = "%d,%d,%d" % [wx, test_y, wz]
	if world_overrides.has(ok) and int(world_overrides[ok]) == 0:
		for y in range(test_y - 1, int(params.surface_min_height) - 2, -1):
			var k: String = "%d,%d,%d" % [wx, y, wz]
			if not world_overrides.has(k):
				return float(y + 1)
			if int(world_overrides[k]) != 0:
				return float(y + 1)
		return max(float(params.surface_min_height), float(params.WATER_LEVEL) - 2.0)
	return h


func _generate_chunk_worker(gen_data: Dictionary) -> void:
	var cx: int = gen_data.cx
	var cz: int = gen_data.cz
	var key: String = gen_data.key
	var lod_mult: int = gen_data.get("lod_mult", 1)
	var params: Dictionary = gen_data.params
	var overrides: Dictionary = gen_data.get("overrides", {})
	var world_overrides: Dictionary = gen_data.get("world_overrides", {})
	var step_count: int = max(1, params.surface_resolution)
	var lod_step: int = max(1, lod_mult)
	var extra: int = 1
	var sample_count: int = int(floor(float(params.chunk_dimensions * step_count) / float(lod_step))) + extra * 2
	if sample_count < 1:
		sample_count = 1
	var start_x: float = float(cx * params.chunk_dimensions) - float(extra * lod_step) / float(step_count)
	var start_z: float = float(cz * params.chunk_dimensions) - float(extra * lod_step) / float(step_count)
	var noise_arr: Array = _thread_create_noise(params)

	var col_min_x: int = int(floor(start_x))
	var col_min_z: int = int(floor(start_z))
	var col_max_x: int = int(ceil(start_x + float(sample_count * lod_step) / float(step_count)))
	var col_max_z: int = int(ceil(start_z + float(sample_count * lod_step) / float(step_count)))
	var col_w: int = col_max_x - col_min_x + 2
	var col_h: int = col_max_z - col_min_z + 2

	var col_heights: PackedFloat64Array = PackedFloat64Array()
	col_heights.resize(col_w * col_h)
	var use_world_ov: bool = not world_overrides.is_empty()
	var orig_heights: PackedFloat64Array = PackedFloat64Array()
	if use_world_ov:
		orig_heights.resize(col_w * col_h)
	for ci in range(col_w):
		for cj in range(col_h):
			var wx: int = col_min_x + ci
			var wz: int = col_min_z + cj
			var h: float = _thread_surface_height(wx, wz, noise_arr, params)
			if use_world_ov:
				orig_heights[ci + cj * col_w] = h
				h = _adjust_column_height(h, wx, wz, world_overrides, params)
			col_heights[ci + cj * col_w] = h

	# Smooth digs: create a bowl-shaped depression around dug blocks
	if use_world_ov:
		var smoothed := PackedFloat64Array()
		smoothed.resize(col_w * col_h)
		for i in range(col_w * col_h):
			smoothed[i] = col_heights[i]
		for ci in range(2, col_w - 2):
			for cj in range(2, col_h - 2):
				var idx: int = ci + cj * col_w
				var drop: float = orig_heights[idx] - col_heights[idx]
				if drop > 0.01:
					var low: float = col_heights[idx]
					var high: float = orig_heights[idx]
					var radius: float = 2.5
					for ndi in range(-2, 3):
						for ndj in range(-2, 3):
							var ni: int = ci + ndi
							var nj: int = cj + ndj
							if ni < 0 or ni >= col_w or nj < 0 or nj >= col_h:
								continue
							var nidx: int = ni + nj * col_w
							if ndi == 0 and ndj == 0:
								smoothed[nidx] = low
							else:
								var d: float = sqrt(float(ndi * ndi + ndj * ndj))
								var t: float = d / radius
								if t < 1.0:
									var smooth_t: float = t * t * (3.0 - 2.0 * t)
									var target: float = lerp(low, high, smooth_t)
									if target < smoothed[nidx]:
										smoothed[nidx] = target
		col_heights = smoothed

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var heights: PackedFloat64Array = PackedFloat64Array()
	var height_count: int = (sample_count + 1) * (sample_count + 1)
	heights.resize(height_count)
	for x in range(sample_count + 1):
		var wx: float = start_x + float(x * lod_step) / float(step_count)
		for z in range(sample_count + 1):
			var wz: float = start_z + float(z * lod_step) / float(step_count)
			var ix: int = int(floor(wx))
			var iz: int = int(floor(wz))
			var tx: float = wx - float(ix)
			var tz: float = wz - float(iz)
			var cx0: int = ix - col_min_x
			var cz0: int = iz - col_min_z
			var h00: float = col_heights[cx0 + cz0 * col_w]
			var h10: float = col_heights[cx0 + 1 + cz0 * col_w]
			var h01: float = col_heights[cx0 + (cz0 + 1) * col_w]
			var h11: float = col_heights[cx0 + 1 + (cz0 + 1) * col_w]
			var h: float = lerp(lerp(h00, h10, tx), lerp(h01, h11, tx), tz)
			heights[x + z * (sample_count + 1)] = h

	var tri_start: int = extra
	var tri_end: int = sample_count - extra
	if not overrides.is_empty():
		for z in range(sample_count + 1):
			var base_z: int = z * (sample_count + 1)
			if heights[(tri_end - 1) + base_z] < heights[tri_end + base_z]:
				heights[tri_end + base_z] = heights[(tri_end - 1) + base_z]
			if heights[(tri_start + 1) + base_z] < heights[tri_start + base_z]:
				heights[tri_start + base_z] = heights[(tri_start + 1) + base_z]
		for x in range(sample_count + 1):
			if heights[x + (tri_end - 1) * (sample_count + 1)] < heights[x + tri_end * (sample_count + 1)]:
				heights[x + tri_end * (sample_count + 1)] = heights[x + (tri_end - 1) * (sample_count + 1)]
			if heights[x + (tri_start + 1) * (sample_count + 1)] < heights[x + tri_start * (sample_count + 1)]:
				heights[x + tri_start * (sample_count + 1)] = heights[x + (tri_start + 1) * (sample_count + 1)]

	var normals: PackedVector3Array = PackedVector3Array()
	normals.resize(height_count)
	var step_world: float = float(lod_step) / float(step_count)
	for x in range(sample_count + 1):
		for z in range(sample_count + 1):
			var xm: int = max(0, x - 1)
			var xp: int = min(sample_count, x + 1)
			var zm: int = max(0, z - 1)
			var zp: int = min(sample_count, z + 1)
			var hL: float = heights[xm + z * (sample_count + 1)]
			var hR: float = heights[xp + z * (sample_count + 1)]
			var hD: float = heights[x + zm * (sample_count + 1)]
			var hU: float = heights[x + zp * (sample_count + 1)]
			normals[x + z * (sample_count + 1)] = Vector3((hL - hR) / step_world, 2.0, (hD - hU) / step_world).normalized()

	var vpos: PackedVector3Array = PackedVector3Array()
	var vnrm: PackedVector3Array = PackedVector3Array()
	var vcol: PackedColorArray = PackedColorArray()
	for x in range(tri_start, tri_end):
		var x0: float = start_x + float(x * lod_step) / float(step_count)
		var x1: float = start_x + float((x + 1) * lod_step) / float(step_count)
		for z in range(tri_start, tri_end):
			var z0: float = start_z + float(z * lod_step) / float(step_count)
			var z1: float = start_z + float((z + 1) * lod_step) / float(step_count)
			var idx00: int = x + z * (sample_count + 1)
			var idx10: int = x + 1 + z * (sample_count + 1)
			var idx01: int = x + (z + 1) * (sample_count + 1)
			var idx11: int = x + 1 + (z + 1) * (sample_count + 1)
			var h00: float = heights[idx00]
			var h10: float = heights[idx10]
			var h01: float = heights[idx01]
			var h11: float = heights[idx11]
			var n00: Vector3 = normals[idx00]
			var n10: Vector3 = normals[idx10]
			var n01: Vector3 = normals[idx01]
			var n11: Vector3 = normals[idx11]
			var col00: Color = _thread_surface_color(h00, int(x0), int(z0), n00, noise_arr, params, cx, cz, overrides)
			var col10: Color = _thread_surface_color(h10, int(x1), int(z0), n10, noise_arr, params, cx, cz, overrides)
			var col01: Color = _thread_surface_color(h01, int(x0), int(z1), n01, noise_arr, params, cx, cz, overrides)
			var col11: Color = _thread_surface_color(h11, int(x1), int(z1), n11, noise_arr, params, cx, cz, overrides)
			vpos.push_back(Vector3(x0, h00, z0)); vnrm.push_back(n00); vcol.push_back(col00)
			vpos.push_back(Vector3(x1, h10, z0)); vnrm.push_back(n10); vcol.push_back(col10)
			vpos.push_back(Vector3(x0, h01, z1)); vnrm.push_back(n01); vcol.push_back(col01)
			vpos.push_back(Vector3(x1, h10, z0)); vnrm.push_back(n10); vcol.push_back(col10)
			vpos.push_back(Vector3(x1, h11, z1)); vnrm.push_back(n11); vcol.push_back(col11)
			vpos.push_back(Vector3(x0, h01, z1)); vnrm.push_back(n01); vcol.push_back(col01)

	var height_map: PackedFloat64Array = PackedFloat64Array()
	height_map.resize((sample_count - extra * 2 + 1) * (sample_count - extra * 2 + 1))
	for x in range(tri_start, tri_end + 1):
		for z in range(tri_start, tri_end + 1):
			var h: float = heights[x + z * (sample_count + 1)]
			height_map[(x - tri_start) + (z - tri_start) * (sample_count - extra * 2 + 1)] = h

	var result_data: Dictionary = {
		"key": key, "cx": cx, "cz": cz,
		"vpos": vpos, "vnrm": vnrm, "vcol": vcol,
		"height_map": height_map,
		"height_map_res": sample_count - extra * 2 + 1,
		"lod_mult": lod_mult
	}

	generation_mutex.lock()
	generation_tasks[key] = result_data
	generation_mutex.unlock()


func _thread_surface_color(height: float, wx: int, wz: int, _normal: Vector3, noise_arr: Array, params: Dictionary, cx: int, cz: int, overrides: Dictionary) -> Color:
	var bn: FastNoiseLite = noise_arr[3]
	var noise_h: float = _thread_surface_height(wx, wz, noise_arr, params)
	if not overrides.is_empty():
		var local_x: int = wx - cx * int(params.chunk_dimensions)
		var local_z: int = wz - cz * int(params.chunk_dimensions)
		if local_x >= 0 and local_x < int(params.chunk_dimensions) and local_z >= 0 and local_z < int(params.chunk_dimensions):
			var sy: int = int(round(height)) - 1
			if sy >= 0 and sy < params.max_height_blocks:
				var ok: String = "%d,%d,%d" % [local_x, sy, local_z]
				if overrides.has(ok):
					var bt: int = int(overrides[ok])
					if bt != 0:
						return _thread_block_type_color(bt)
	if height < noise_h:
		var sy: int = int(round(height)) - 1
		if sy >= 0 and sy < params.max_height_blocks:
			var bt: int = _thread_get_base_block_type(wx, sy, wz, noise_arr, params)
			if bt != 0:
				return _thread_block_type_color(bt)
	var biome: int = _thread_get_dominant_biome(wx, wz, bn, params)
	return _thread_biome_color(biome, height)


func _thread_biome_color(biome: int, height: float) -> Color:
	match biome:
		5: return Color(0.95, 0.97, 1.0, 2.0 / 3.0)
		6:
			var blend: float = clamp((height - 180.0) / 60.0, 0.0, 1.0)
			var c := Color(0.45, 0.45, 0.45).lerp(Color(0.7, 0.7, 0.7), blend)
			c.a = 2.0 / 3.0
			return c
		3: return Color(0.85, 0.74, 0.42, 1.0 / 3.0)
		4: return Color(0.35, 0.50, 0.28, 0.0)
		1: return Color(0.25, 0.55, 0.20, 0.0)
		2: return Color(0.50, 0.60, 0.25, 0.0)
		7: return Color(0.10, 0.25, 0.50, 0.0)
	return Color(0.28, 0.70, 0.24, 0.0)


func _thread_block_type_color(block_type: int) -> Color:
	var tex_slot: float = 2.0
	var tint := Color.WHITE
	match block_type:
		1: tex_slot = 0.0; tint = Color.WHITE
		2: tex_slot = 1.0; tint = Color.WHITE
		3: tex_slot = 2.0; tint = Color.WHITE
		4: tex_slot = 2.0; tint = Color(0.25, 0.25, 0.25)
		5: tex_slot = 2.0; tint = Color(0.85, 0.85, 0.92)
		6: tex_slot = 2.0; tint = Color(0.92, 0.58, 0.38)
		7: tex_slot = 2.0; tint = Color(1.0, 0.88, 0.25)
		8: tex_slot = 2.0; tint = Color(0.45, 0.92, 1.0)
		9: tex_slot = 2.0; tint = Color(0.55, 0.35, 0.15)
		10: tex_slot = 0.0; tint = Color(0.18, 0.55, 0.18)
	tint.a = tex_slot / 3.0
	return tint


func _thread_get_base_block_type(wx: int, wy: int, wz: int, noise_arr: Array, params: Dictionary) -> int:
	if wy < 0 or wy >= params.max_height_blocks:
		return 0
	var on: FastNoiseLite = noise_arr[6]
	var surface_y: float = _thread_surface_height(wx, wz, noise_arr, params)
	if float(wy) > surface_y:
		return 0
	var depth: int = int(surface_y) - wy
	if depth < params.grass_layers:
		return 1
	if depth < params.grass_layers + params.dirt_layers:
		return 2
	var ore_value: float = absf(on.get_noise_3d(float(wx), float(wy), float(wz)))
	if ore_value > 0.85: return 8
	if ore_value > 0.78: return 7
	if ore_value > 0.68: return 5
	if ore_value > 0.57: return 6
	if ore_value > 0.43: return 4
	if depth < 10 and int(surface_y) - wy < 5: return 1
	return 3


func _sync_generation_results() -> void:
	var results_to_process: Array = []
	generation_mutex.lock()
	for key in generation_tasks:
		results_to_process.append(generation_tasks[key])
	generation_mutex.unlock()
	var sync_start: int = Time.get_ticks_msec()
	var processed_in_frame: int = 0
	const MAX_SYNC_PER_FRAME: int = 2
	for result_data in results_to_process:
		if _sync_budget_ms > 0 and processed_in_frame > 0:
			if Time.get_ticks_msec() - sync_start >= _sync_budget_ms:
				break
		if processed_in_frame >= MAX_SYNC_PER_FRAME:
			break
		if not result_data.has("vpos"):
			continue
		var key: String = result_data.key
		var cx: int = result_data.cx
		var cz: int = result_data.cz
		var lod_mult: int = result_data.get("lod_mult", 1)
		if not _is_chunk_within_render_distance(cx, cz):
			generation_mutex.lock()
			generation_tasks.erase(key)
			generation_mutex.unlock()
			continue
		_clear_chunk_visuals(key)
		var root := Node3D.new()
		root.name = "Chunk_%s" % key.replace(",", "_")
		add_child(root)
		chunk_visuals[key] = {"root": root, "lod": 0, "mesh_instance": null, "collision_body": null, "multimesh": null}
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var vpos: PackedVector3Array = result_data.vpos
		var vnrm: PackedVector3Array = result_data.vnrm
		var vcol: PackedColorArray = result_data.vcol
		for i in range(vpos.size()):
			st.set_normal(vnrm[i])
			st.set_color(vcol[i])
			st.add_vertex(vpos[i])
		st.index()
		var mesh: ArrayMesh = st.commit()
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.mesh = mesh
		mesh_inst.material_override = chunk_material
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_inst.name = "Mesh"
		root.add_child(mesh_inst)
		chunk_visuals[key]["mesh_instance"] = mesh_inst
		if lod_mult <= 1:
			var body := StaticBody3D.new()
			body.collision_layer = 1
			body.collision_mask = 1
			var used_heightmap: bool = false
			if result_data.has("height_map") and result_data.has("height_map_res"):
				var hm: PackedFloat64Array = result_data["height_map"]
				var hres: int = int(result_data["height_map_res"])
				if hres >= 2 and hm.size() == hres * hres:
					var fd := PackedFloat32Array()
					fd.resize(hm.size())
					for i in range(hm.size()):
						fd[i] = float(hm[i])
					var shape := HeightMapShape3D.new()
					shape.map_width = hres
					shape.map_depth = hres
					shape.map_data = fd
					var cs := CollisionShape3D.new()
					cs.shape = shape
					cs.position = Vector3(float(cx * chunk_dimensions) + float(int(hres / 2)), 0.0, float(cz * chunk_dimensions) + float(int(hres / 2)))
					body.add_child(cs)
					used_heightmap = true
			if not used_heightmap and vpos.size() >= 3:
				var cs := CollisionShape3D.new()
				var shape := ConcavePolygonShape3D.new()
				shape.set_faces(vpos)
				cs.shape = shape
				body.add_child(cs)
			root.add_child(body)
			chunk_visuals[key]["collision_body"] = body
		_chunk_setup_multimesh(root, key)
		if not _pending_post_sync_keys.has(key):
			_pending_post_sync_keys[key] = true
			_pending_post_sync.append({"key": key, "root": root, "cx": cx, "cz": cz})
		generation_mutex.lock()
		generation_tasks.erase(key)
		generation_mutex.unlock()


func _chunk_setup_multimesh(root: Node3D, key: String) -> void:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "BlockMultiMesh"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = cube_mesh
	mmi.multimesh = mm
	mmi.material_override = block_multimesh_material
	root.add_child(mmi)
	chunk_visuals[key]["multimesh"] = mmi


func _process_pending_post_sync() -> void:
	var ps_start: int = Time.get_ticks_msec()
	var processed_this_tick: int = 0
	const MAX_POST_SYNC_PER_FRAME: int = 2
	while not _pending_post_sync.is_empty():
		if processed_this_tick >= MAX_POST_SYNC_PER_FRAME:
			break
		if _sync_budget_ms > 0 and processed_this_tick > 0:
			if Time.get_ticks_msec() - ps_start >= _sync_budget_ms:
				break
		var entry: Dictionary = _pending_post_sync.pop_front()
		var key: String = entry.key
		_pending_post_sync_keys.erase(key)
		var root: Node3D = entry.root
		var cx: int = entry.cx
		var cz: int = entry.cz
		if not chunk_visuals.has(key) or not is_instance_valid(root):
			continue
		_clear_cave_walls(key)
		_build_water_surface(root, cx, cz)
		var biome: int = get_dominant_biome_at(cx * chunk_dimensions + int(chunk_dimensions * 0.5), cz * chunk_dimensions + int(chunk_dimensions * 0.5))
		genereaza_structuri_specifice_zonei(root, cx, cz, biome)
		_genereaza_pesteri(cx, cz)
		_sync_modified_blocks_from_overrides(key)
		processed_this_tick += 1
		if not terrain_ready_emitted:
			generation_completed_chunks = min(generation_completed_chunks + 1, max(1, generation_target_chunks))
			_emit_generation_progress("Generating terrain...")
			if cx == _player_spawn_chunk.x and cz == _player_spawn_chunk.y:
				_mark_terrain_ready()


func _process_chunk_queue() -> void:
	if not initial_generation_started:
		return
	_sync_generation_results()
	_process_pending_post_sync()
	_sync_cave_carving_results()
	_process_cave_carving_queue()
	_sync_cave_mesh_results()
	_process_cave_mesh_queue()
	if generating_chunk:
		return
	generating_chunk = true
	var frame_start: int = Time.get_ticks_msec()
	var processed_this_pass: int = 0
	var max_launch: int = MAX_THREADS
	var active_count: int = 0
	for k in generation_tasks:
		active_count += 1
	max_launch = maxi(1, MAX_THREADS - active_count)
	while not chunk_generation_queue.is_empty() and max_launch > 0:
		if generation_time_budget_ms > 0 and processed_this_pass > 0:
			if Time.get_ticks_msec() - frame_start >= generation_time_budget_ms:
				break
		var data: Dictionary = chunk_generation_queue.pop_front()
		chunk_generation_pending.erase(data["key"])
		if not _is_chunk_within_render_distance(data["cx"], data["cz"]):
			continue
		var lod_mult: int = _compute_lod_mult_for_chunk(data["cx"], data["cz"])
		if lod_mult > 1 and lod_mult > data.get("lod_mult", 1):
			data["lod_mult"] = lod_mult
		var gen_data: Dictionary = {
			"cx": data["cx"], "cz": data["cz"], "key": data["key"],
			"lod_mult": lod_mult,
			"params": _capture_noise_params()
		}
		var world_overrides: Dictionary = {}
		for rdx in range(-1, 2):
			for rdz in range(-1, 2):
				var nkey: String = _chunk_key(data["cx"] + rdx, data["cz"] + rdz)
				var no: Dictionary = _get_override_dict(nkey, false)
				if no.is_empty():
					continue
				for ok in no:
					var parts: PackedStringArray = ok.split(",")
					if parts.size() == 3:
						var wx: int = (data["cx"] + rdx) * chunk_dimensions + int(parts[0])
						var wy: int = int(parts[1])
						var wz: int = (data["cz"] + rdz) * chunk_dimensions + int(parts[2])
						world_overrides["%d,%d,%d" % [wx, wy, wz]] = no[ok]
		if not world_overrides.is_empty():
			gen_data["world_overrides"] = world_overrides
		generation_mutex.lock()
		generation_tasks[data["key"]] = {"_placeholder": true}
		generation_mutex.unlock()
		WorkerThreadPool.add_task(_generate_chunk_worker.bind(gen_data), 0, "chunk_gen")
		max_launch -= 1
		processed_this_pass += 1
	generating_chunk = false
	if chunk_generation_queue.is_empty() and generation_tasks.is_empty() and _pending_post_sync.is_empty() and _cave_carving_queue.is_empty() and _cave_carving_tasks.is_empty() and _pending_cave_mesh_queue.is_empty() and _cave_mesh_tasks.is_empty():
		_mark_terrain_ready()
	if processed_this_pass > 0 or not generation_tasks.is_empty() or not _pending_post_sync.is_empty() or not _cave_carving_queue.is_empty() or not _cave_carving_tasks.is_empty() or not _pending_cave_mesh_queue.is_empty() or not _cave_mesh_tasks.is_empty():
		call_deferred("_process_chunk_queue")

func _process_cave_mesh_queue() -> void:
	if _pending_cave_mesh_queue.is_empty():
		return
	var cm_start: int = Time.get_ticks_msec()
	var launched: int = 0
	const MAX_LAUNCH_PER_FRAME: int = 3
	while not _pending_cave_mesh_queue.is_empty():
		if launched >= MAX_LAUNCH_PER_FRAME:
			break
		if launched > 0:
			if Time.get_ticks_msec() - cm_start >= generation_time_budget_ms:
				break
		var entry: Dictionary = _pending_cave_mesh_queue.pop_front()
		var key: String = entry.key
		if not chunk_caves_generated.has(key):
			continue
		_cave_mesh_mutex.lock()
		_cave_mesh_tasks[key] = {"_placeholder": true}
		_cave_mesh_mutex.unlock()
		WorkerThreadPool.add_task(_cave_mesh_worker.bind(entry), 0, "cave_mesh")
		launched += 1

func _cave_mesh_worker(entry: Dictionary) -> void:
	var key: String = entry.key
	var cx: int = entry.cx
	var cz: int = entry.cz
	var carved: Dictionary = entry.carved
	var lod_mult: int = entry.get("lod_mult", 1)

	var min_bound: Vector3i = Vector3i(cx * chunk_dimensions, cave_min_y, cz * chunk_dimensions)
	var max_bound: Vector3i = Vector3i((cx + 1) * chunk_dimensions - 1, max_height_blocks - 1, (cz + 1) * chunk_dimensions - 1)

	var mesh_data: Dictionary = CaveSystem.extract_cave_mesh_data_static(carved, min_bound, max_bound)

	_cave_mesh_mutex.lock()
	_cave_mesh_tasks[key] = {"mesh_data": mesh_data, "cx": cx, "cz": cz, "done": true}
	_cave_mesh_mutex.unlock()

func _sync_cave_mesh_results() -> void:
	var completed: Array = []
	_cave_mesh_mutex.lock()
	for key in _cave_mesh_tasks:
		var task: Dictionary = _cave_mesh_tasks[key]
		if task.get("done", false):
			completed.append({"key": key, "task": task})
			_cave_mesh_tasks.erase(key)
	_cave_mesh_mutex.unlock()

	var sync_start: int = Time.get_ticks_msec()
	var processed: int = 0
	const MAX_CAVE_SYNC_PER_FRAME: int = 2
	for entry in completed:
		if processed >= MAX_CAVE_SYNC_PER_FRAME:
			break
		if processed > 0:
			if Time.get_ticks_msec() - sync_start >= _sync_budget_ms:
				break
		var key: String = entry.key
		var task: Dictionary = entry.task
		var mesh_data: Dictionary = task.mesh_data
		var cx: int = task.cx
		var cz: int = task.cz

		var mesh: ArrayMesh = CaveSystem.build_cave_mesh_from_data(mesh_data)
		if mesh.get_surface_count() == 0:
			processed += 1
			continue

		var shape: ConcavePolygonShape3D = null
		var lod_mult: int = _compute_lod_mult_for_chunk(cx, cz)
		if lod_mult <= 1:
			shape = mesh.create_trimesh_shape()

		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = cave_material
		mi.name = "CaveWallsSmooth"
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

		var cave_root := Node3D.new()
		cave_root.name = "Cave_%d_%d" % [cx, cz]
		cave_root.add_child(mi)

		if shape != null:
			var body := StaticBody3D.new()
			body.name = "CaveCollision"
			body.collision_layer = 1
			body.collision_mask = 1
			var cs := CollisionShape3D.new()
			cs.shape = shape
			body.add_child(cs)
			cave_root.add_child(body)

		add_child(cave_root)
		cave_wall_nodes[key] = cave_root
		smooth_cave_meshes[key] = mesh
		processed += 1


func _compute_lod_mult_for_chunk(cx: int, cz: int) -> int:
	if not lod_enabled or nod_jucator == null:
		return 1
	var dx: float = float(cx * chunk_dimensions) + float(chunk_dimensions) / 2.0 - nod_jucator.global_position.x
	var dz: float = float(cz * chunk_dimensions) + float(chunk_dimensions) / 2.0 - nod_jucator.global_position.z
	var dist: float = sqrt(dx * dx + dz * dz)
	if dist >= 60.0:
		return 4
	if dist >= 30.0:
		return 2
	return 1


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


func _is_river_at(wx: int, wz: int) -> bool:
	return absf(river_noise.get_noise_2d(float(wx) * 0.6, float(wz) * 0.6)) > 0.45 \
		and absf(river_noise.get_noise_2d(float(wx) * 2.0, float(wz) * 2.0)) > 0.2

func _surface_color_for_biome(height: float, wx: int, wz: int, normal: Vector3) -> Color:
	var noise_h: float = _surface_height_from_noise(wx, wz)
	if _is_river_at(wx, wz):
		return Color(0.15, 0.30, 0.55)
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
	if biome == BiomeType.OCEAN:
		return Color(0.10, 0.25, 0.50)
	if biome == BiomeType.RIVER:
		return Color(0.15, 0.30, 0.55)
	return Color(0.28, 0.70, 0.24)


func _clear_chunk_visuals(key: String) -> void:
	if not chunk_visuals.has(key):
		return
	var data: Dictionary = chunk_visuals[key]
	if data.has("root") and is_instance_valid(data["root"]):
		data["root"].queue_free()
	_cleanup_modified_blocks_for_chunk(key)
	chunk_visuals.erase(key)

func _clear_cave_walls(key: String) -> void:
	if cave_wall_nodes.has(key):
		var node: Node3D = cave_wall_nodes[key]
		if is_instance_valid(node):
			node.queue_free()
		cave_wall_nodes.erase(key)
	chunk_caves_generated.erase(key)
	smooth_cave_meshes.erase(key)
	_cave_mesh_mutex.lock()
	_cave_mesh_tasks.erase(key)
	_cave_mesh_mutex.unlock()
	_cave_carving_mutex.lock()
	_cave_carving_tasks.erase(key)
	_cave_carving_queue = _cave_carving_queue.filter(func(e): return e.key != key)
	_cave_carving_mutex.unlock()


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
	var mmi: MultiMeshInstance3D = chunk_visuals.get(key, {}).get("multimesh")
	if mmi != null and mmi.multimesh != null:
		mmi.multimesh.instance_count = 0


func _get_effective_height(wx: int, wz: int) -> float:
	var noise_h: float = _surface_height_from_noise(wx, wz)
	var key: String = _chunk_key(int(floor(float(wx) / float(chunk_dimensions))), int(floor(float(wz) / float(chunk_dimensions))))
	var overrides: Dictionary = _get_override_dict(key, false)
	if overrides.is_empty():
		return noise_h
	var surface_y: int = int(floor(noise_h))
	if surface_y >= 1 and surface_y < max_height_blocks:
		if get_block_type_at(wx, surface_y, wz) == BlockType.AIR:
			return float(surface_y - 1)
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


func _surface_height_from_noise_with_float(world_x: float, world_z: float) -> float:
	return _surface_height_from_noise(int(round(world_x)), int(round(world_z)))

func _set_cave_block(world_x: int, world_y: int, world_z: int, _block_type: int) -> void:
	_set_override_for_world(world_x, world_y, world_z, BlockType.AIR)
	_remove_block_visual(world_x, world_y, world_z)

func _surface_height_from_noise(world_x: int, world_z: int) -> float:
	var wx: float = float(world_x)
	var wz: float = float(world_z)
	var weights: Array = get_biome_weights(world_x, world_z)
	if weights.is_empty():
		return float(surface_min_height)

	var dominant: int = get_dominant_biome_at(world_x, world_z)
	if dominant == BiomeType.OCEAN:
		return WATER_LEVEL - 2.0 + absf(biome_noise.get_noise_2d(wx * 0.01, wz * 0.01)) * 1.0

	var river_val: float = river_noise.get_noise_2d(wx * 0.6, wz * 0.6)
	var is_river: bool = absf(river_val) > 0.45 and absf(river_noise.get_noise_2d(wx * 2.0, wz * 2.0)) > 0.2
	if is_river:
		var river_depth: float = (absf(river_val) - 0.45) * 6.0
		return WATER_LEVEL - min(river_depth, 3.0)

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


func _add_visible_block(_block_type: int, world_x: int, world_y: int, world_z: int) -> void:
	var key: String = "%d,%d,%d" % [world_x, world_y, world_z]
	if modified_block_visuals.has(key):
		return
	var ckey: String = _chunk_key_from_world(world_x, world_z)
	var body := StaticBody3D.new()
	body.position = Vector3(world_x + 0.5, world_y + 0.5, world_z + 0.5)
	body.add_to_group("Digable")
	var cs := CollisionShape3D.new()
	cs.shape = BoxShape3D.new()
	body.add_child(cs)
	add_child(body)
	modified_block_visuals[key] = body
	_rebuild_chunk_multimesh(ckey)


func _remove_block_visual(world_x: int, world_y: int, world_z: int) -> void:
	var key: String = "%d,%d,%d" % [world_x, world_y, world_z]
	if not modified_block_visuals.has(key):
		return
	var body: StaticBody3D = modified_block_visuals[key]
	if is_instance_valid(body):
		body.queue_free()
	modified_block_visuals.erase(key)
	var ckey: String = _chunk_key_from_world(world_x, world_z)
	_rebuild_chunk_multimesh(ckey)


func _chunk_key_from_world(world_x: int, world_z: int) -> String:
	var cx: int = int(floor(float(world_x) / float(chunk_dimensions)))
	var cz: int = int(floor(float(world_z) / float(chunk_dimensions)))
	return _chunk_key(cx, cz)


func _rebuild_chunk_multimesh(chunk_key: String) -> void:
	if not chunk_visuals.has(chunk_key):
		return
	var mmi: MultiMeshInstance3D = chunk_visuals[chunk_key].get("multimesh")
	if mmi == null or mmi.multimesh == null:
		return
	var overrides: Dictionary = _get_override_dict(chunk_key, false)
	if overrides.is_empty():
		mmi.multimesh.instance_count = 0
		return
	var blocks: Array = []
	for ok in overrides:
		var bt: int = int(overrides[ok])
		if bt != BlockType.AIR:
			blocks.append({"key": ok, "type": bt})
	var mm: MultiMesh = mmi.multimesh
	mm.instance_count = blocks.size()
	var parts2: PackedStringArray = chunk_key.split(",")
	if parts2.size() != 2:
		return
	var cx: int = int(parts2[0])
	var cz: int = int(parts2[1])
	for i in range(blocks.size()):
		var parts: PackedStringArray = blocks[i]["key"].split(",")
		var local_x: int = int(parts[0])
		var wy: int = int(parts[1])
		var local_z: int = int(parts[2])
		var wx: float = float(cx * chunk_dimensions + local_x) + 0.5
		var wz: float = float(cz * chunk_dimensions + local_z) + 0.5
		var t := Transform3D()
		t.origin = Vector3(wx, float(wy) + 0.5, wz)
		mm.set_instance_transform(i, t)
		mm.set_instance_color(i, _block_type_color(blocks[i]["type"]))


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
	var chunk_x: int = int(floor(float(world_x) / float(chunk_dimensions)))
	var chunk_z: int = int(floor(float(world_z) / float(chunk_dimensions)))
	var key: String = _chunk_key(chunk_x, chunk_z)
	var overrides: Dictionary = _get_override_dict(key, false)
	if overrides.is_empty():
		return int(floor(_surface_height_from_noise(world_x, world_z)))
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


func _is_at_chunk_edge(world_x: int, world_z: int) -> bool:
	var cx: int = int(floor(float(world_x) / float(chunk_dimensions)))
	var cz: int = int(floor(float(world_z) / float(chunk_dimensions)))
	var local_x: int = world_x - cx * chunk_dimensions
	var local_z: int = world_z - cz * chunk_dimensions
	return local_x <= 1 or local_x >= chunk_dimensions - 2 or local_z <= 1 or local_z >= chunk_dimensions - 2


func sapa_bloc(start: Vector3, direction: Vector3) -> int:
	if direction == Vector3.ZERO:
		return BlockType.AIR
	var hit: Variant = ray_pick_block(start, direction)
	if hit == null or hit is bool:
		return BlockType.AIR
	var world_pos: Vector3 = hit["hit"]["world"]
	last_dug_world_pos = world_pos
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
	var cx: int = int(floor(float(wx) / float(chunk_dimensions)))
	var cz: int = int(floor(float(wz) / float(chunk_dimensions)))
	var local_x: int = wx - cx * chunk_dimensions
	var local_z: int = wz - cz * chunk_dimensions
	if local_x <= 1 and wx > 0:
		_dig_neighbor_block(wx - 1, wy, wz)
		if local_x == 0:
			_enqueue_chunk_generation(cx - 1, cz, _chunk_key(cx - 1, cz))
	if local_x >= chunk_dimensions - 2:
		_dig_neighbor_block(wx + 1, wy, wz)
		if local_x >= chunk_dimensions - 1:
			_enqueue_chunk_generation(cx + 1, cz, _chunk_key(cx + 1, cz))
		if local_x == chunk_dimensions - 2:
			_dig_neighbor_block(wx + 2, wy, wz)
			_enqueue_chunk_generation(cx + 1, cz, _chunk_key(cx + 1, cz))
	if local_z <= 1 and wz > 0:
		_dig_neighbor_block(wx, wy, wz - 1)
		if local_z == 0:
			_enqueue_chunk_generation(cx, cz - 1, _chunk_key(cx, cz - 1))
	if local_z >= chunk_dimensions - 2:
		_dig_neighbor_block(wx, wy, wz + 1)
		if local_z >= chunk_dimensions - 1:
			_enqueue_chunk_generation(cx, cz + 1, _chunk_key(cx, cz + 1))
		if local_z == chunk_dimensions - 2:
			_dig_neighbor_block(wx, wy, wz + 2)
			_enqueue_chunk_generation(cx, cz + 1, _chunk_key(cx, cz + 1))
	var surf_h: float = _surface_height_from_noise(wx, wz)
	var at_edge: bool = _is_at_chunk_edge(wx, wz)
	if wy >= int(surf_h) - 2 or at_edge:
		_request_rebuild_for_world(wx, wz, chunk_dimensions if at_edge else 0)
	return block

func _dig_neighbor_block(adj_x: int, wy: int, wz: int) -> void:
	var surf_h: float = _surface_height_from_noise(adj_x, wz)
	var dig_y: int = int(floor(surf_h))
	var nblock: int = get_block_type_at(adj_x, dig_y, wz)
	if nblock != BlockType.AIR:
		_set_override_for_world(adj_x, dig_y, wz, BlockType.AIR)
		_remove_block_visual(adj_x, dig_y, wz)


func sapa_sfera(start: Vector3, direction: Vector3, raza_sfera: float = 3.0) -> Array:
	if direction == Vector3.ZERO:
		return []
	var hit: Variant = ray_pick_block(start, direction)
	if hit == null or hit is bool:
		return []
	var world_pos: Vector3 = hit["hit"]["world"]
	last_dug_world_pos = world_pos
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
	var surf_h: float = _surface_height_from_noise(wx, wz)
	var at_edge: bool = _is_at_chunk_edge(wx, wz)
	if wy >= int(surf_h) - 2 or at_edge:
		_request_rebuild_for_world(wx, wz, chunk_dimensions if at_edge else 0)
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
	if ocean_mask_noise.get_noise_2d(float(world_x), float(world_z)) < -0.5:
		return BiomeType.OCEAN
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
		BiomeType.OCEAN:
			return "Ocean"
		BiomeType.RIVER:
			return "River"
	return "Unknown"



func _get_biome_profile(biome: int) -> Dictionary:
	var h_min: float = float(surface_min_height)
	var h_max: float = float(surface_max_height)
	match biome:
		BiomeType.PLAINS:
			return {"terrain_scale": 0.025, "detail_scale": 0.05, "warp_strength": 4.0, "detail_mix": 0.3, "curve": 0.7, "height_min": 68.0, "height_max": 80.0}
		BiomeType.FOREST:
			return {"terrain_scale": 0.028, "detail_scale": 0.055, "warp_strength": 4.5, "detail_mix": 0.35, "curve": 0.7, "height_min": 70.0, "height_max": 82.0}
		BiomeType.HILLS:
			return {"terrain_scale": 0.030, "detail_scale": 0.06, "warp_strength": 5.0, "detail_mix": 0.4, "curve": 0.75, "height_min": 72.0, "height_max": 86.0}
		BiomeType.DESERT:
			return {"terrain_scale": 0.022, "detail_scale": 0.04, "warp_strength": 2.0, "detail_mix": 0.2, "curve": 0.65, "height_min": 67.0, "height_max": 78.0}
		BiomeType.SWAMP:
			return {"terrain_scale": 0.024, "detail_scale": 0.045, "warp_strength": 3.0, "detail_mix": 0.25, "curve": 0.6, "height_min": 64.0, "height_max": 72.0}
		BiomeType.SNOW:
			return {"terrain_scale": 0.030, "detail_scale": 0.055, "warp_strength": 4.0, "detail_mix": 0.35, "curve": 0.7, "height_min": 70.0, "height_max": 84.0}
		BiomeType.MOUNTAINS:
			return {"terrain_scale": 0.035, "detail_scale": 0.06, "warp_strength": 5.0, "detail_mix": 0.4, "curve": 0.8, "height_min": 72.0, "height_max": 90.0}
		BiomeType.OCEAN:
			return {"terrain_scale": 0.01, "detail_scale": 0.02, "warp_strength": 1.0, "detail_mix": 0.05, "curve": 0.3, "height_min": 40.0, "height_max": 55.0}
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
		if h <= WATER_LEVEL + 0.5:
			continue
		if rng.randi() % 3 < 2:
			_genereaza_copac(root, wx, wz, h, rng)
		else:
			_genereaza_piatra(root, wx, wz, h, rng)

	var prob: float = _structuri_constructii_chance(biome)
	if rng.randf() < prob:
		var wx: float = float(rng.randi_range(int(min_x), int(max_x) - 1)) + 0.5
		var wz: float = float(rng.randi_range(int(min_z), int(max_z) - 1)) + 0.5
		var h: float = _sample_surface_height(wx, wz)
		if h <= WATER_LEVEL + 0.5:
			return
		_genereaza_casa(root, wx, wz, h, rng)

	if not structuri_inamici.is_empty():
		var count: int = _structuri_inamici_count(biome)
		for i in range(count):
			var wx: float = float(rng.randi_range(int(min_x), int(max_x) - 1)) + 0.5
			var wz: float = float(rng.randi_range(int(min_z), int(max_z) - 1)) + 0.5
			var h: float = _sample_surface_height(wx, wz)
			if h <= WATER_LEVEL + 0.5:
				continue
			var scena: PackedScene = structuri_inamici[rng.randi() % structuri_inamici.size()]
			var wrapper := Node3D.new()
			wrapper.position = Vector3(wx, h, wz)
			wrapper.rotation.y = rng.randf_range(0.0, TAU)
			var inst: Node3D = scena.instantiate()
			wrapper.add_child(inst)
			root.add_child(wrapper)


func _structuri_naturale_count(biome: int) -> int:
	var base: int
	match biome:
		BiomeType.FOREST: base = 4
		BiomeType.SWAMP: base = 3
		BiomeType.HILLS: base = 2
		BiomeType.PLAINS: base = 2
		BiomeType.MOUNTAINS: base = 1
		BiomeType.DESERT: base = 1
		BiomeType.SNOW: base = 0
		BiomeType.OCEAN: base = 0
		BiomeType.RIVER: base = 0
		_: base = 1
	return max(0, int(round(float(base) * _WC.tree_density)))


func _structuri_constructii_chance(biome: int) -> float:
	match biome:
		BiomeType.PLAINS: return 0.5
		BiomeType.HILLS: return 0.3
		BiomeType.OCEAN: return 0.0
		BiomeType.RIVER: return 0.0
	return 0.0


func _structuri_inamici_count(biome: int) -> int:
	match biome:
		BiomeType.SWAMP: return 3
		BiomeType.FOREST: return 2
		BiomeType.MOUNTAINS: return 2
		BiomeType.OCEAN: return 0
		BiomeType.RIVER: return 0
	return 0

# --- MULTIPLAYER RPCs ---

func _chunk_has_water_areas(cx: int, cz: int) -> bool:
	var cells: int = maxi(1, water_patch_resolution)
	var cell_size: float = float(chunk_dimensions) / float(cells)
	var start_x: float = float(cx * chunk_dimensions)
	var start_z: float = float(cz * chunk_dimensions)
	for ix in range(cells + 1):
		for iz in range(cells + 1):
			var sample_x: float = start_x + float(ix) * cell_size
			var sample_z: float = start_z + float(iz) * cell_size
			if _surface_height_from_noise(int(sample_x), int(sample_z)) < WATER_LEVEL:
				return true
	return false


func _build_water_surface(root: Node3D, cx: int, cz: int) -> void:
	if not is_instance_valid(root):
		return
	var water_mesh: ArrayMesh = _build_water_patch_mesh(cx, cz)
	if water_mesh == null:
		return
	var water := MeshInstance3D.new()
	water.name = "WaterChunk"
	water.mesh = water_mesh
	water.material_override = material_water
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(water)

func _build_water_patch_mesh(cx: int, cz: int) -> ArrayMesh:
	var cells: int = maxi(1, water_patch_resolution)
	var cell_size: float = float(chunk_dimensions) / float(cells)
	var start_x: float = float(cx * chunk_dimensions)
	var start_z: float = float(cz * chunk_dimensions)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var added: bool = false
	for ix in range(cells):
		for iz in range(cells):
			var x0: float = start_x + float(ix) * cell_size
			var x1: float = x0 + cell_size
			var z0: float = start_z + float(iz) * cell_size
			var z1: float = z0 + cell_size
			var h00: float = _surface_height_from_noise(int(x0), int(z0))
			var h10: float = _surface_height_from_noise(int(x1), int(z0))
			var h01: float = _surface_height_from_noise(int(x0), int(z1))
			var h11: float = _surface_height_from_noise(int(x1), int(z1))
			var h_center: float = _surface_height_from_noise(int((x0 + x1) * 0.5), int((z0 + z1) * 0.5))
			var lowest: float = min(min(h00, h10), min(h01, h11))
			lowest = min(lowest, h_center)
			if lowest > WATER_LEVEL + 0.2:
				continue
			var y: float = WATER_LEVEL + 0.08
			var p00 := Vector3(x0, y, z0)
			var p10 := Vector3(x1, y, z0)
			var p01 := Vector3(x0, y, z1)
			var p11 := Vector3(x1, y, z1)
			var uv_scale: float = 0.08
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(x0 * uv_scale, z0 * uv_scale))
			st.add_vertex(p00)
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(x1 * uv_scale, z0 * uv_scale))
			st.add_vertex(p10)
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(x0 * uv_scale, z0 * uv_scale))
			st.add_vertex(p01)
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(x1 * uv_scale, z0 * uv_scale))
			st.add_vertex(p10)
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(x1 * uv_scale, z1 * uv_scale))
			st.add_vertex(p11)
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(x0 * uv_scale, z0 * uv_scale))
			st.add_vertex(p01)
			added = true
	if added:
		st.generate_tangents()
		st.index()
		return st.commit()
	return null

func _surface_flow_vector(world_x: int, world_z: int) -> Vector2:
	var sample_distance: int = 2
	var h_l: float = _surface_height_from_noise(world_x - sample_distance, world_z)
	var h_r: float = _surface_height_from_noise(world_x + sample_distance, world_z)
	var h_d: float = _surface_height_from_noise(world_x, world_z - sample_distance)
	var h_u: float = _surface_height_from_noise(world_x, world_z + sample_distance)
	var flow: Vector2 = Vector2(h_l - h_r, h_d - h_u)
	if flow.length() < 0.001:
		return Vector2.ZERO
	return flow.normalized()


func _build_smart_cave_path(world_x: int, world_z: int, surface_y: float, rng: RandomNumberGenerator, width_override: int = -1, depth_override: int = -1) -> Array:
	var entrance_width: int = cave_entrance_width if width_override < 0 else width_override
	var entrance_depth: int = cave_entrance_depth if depth_override < 0 else depth_override
	var flow: Vector2 = _surface_flow_vector(world_x, world_z)
	if flow == Vector2.ZERO:
		flow = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
	if flow.length() < 0.001:
		flow = Vector2(0.0, 1.0)
	flow = flow.normalized()
	var perpendicular: Vector2 = Vector2(-flow.y, flow.x)
	var start_y: float = surface_y + 1.4
	var target_y: float = max(float(cave_min_y + 2), surface_y - float(entrance_depth))
	var water_floor: float = float(WATER_LEVEL) - 0.75
	if target_y < water_floor:
		target_y = water_floor
	var path_length: int = max(10, entrance_depth + 4)
	var path_points: Array = []
	var distance_scale: float = max(float(entrance_depth) * 0.8, 6.0)
	var sway_scale: float = float(max(entrance_width, 1)) * 0.35
	for i in range(path_length):
		var t: float = 0.0 if path_length <= 1 else float(i) / float(path_length - 1)
		var eased: float = t * t * (3.0 - 2.0 * t)
		var forward: float = eased * distance_scale
		var sway: float = sin(t * PI) * sway_scale
		var x: float = float(world_x) + 0.5 + flow.x * forward + perpendicular.x * sway
		var z: float = float(world_z) + 0.5 + flow.y * forward + perpendicular.y * sway
		var y: float = lerp(start_y, target_y, eased)
		path_points.append(Vector3(x, y, z))
	return path_points


func _carve_tunnel_path(path_points: Array, carved: Dictionary, radius_start: float, radius_end: float) -> Dictionary:
	var affected: Dictionary = {}
	if path_points.is_empty():
		return affected
	for i in range(path_points.size()):
		var center: Vector3 = path_points[i]
		var path_t: float = 0.0 if path_points.size() <= 1 else float(i) / float(path_points.size() - 1)
		var radius: float = lerp(radius_start, radius_end, path_t)
		if i == 0:
			radius += 0.5
		elif i == path_points.size() - 1:
			radius += 0.25
		var radius_i: int = int(ceil(radius))
		var center_x: int = int(round(center.x))
		var center_y: int = int(round(center.y))
		var center_z: int = int(round(center.z))
		for dx in range(-radius_i, radius_i + 1):
			for dy in range(-radius_i, radius_i + 1):
				for dz in range(-radius_i, radius_i + 1):
					var dist_sq: float = float(dx * dx + dy * dy + dz * dz)
					if dist_sq > radius * radius:
						continue
					var wx: int = center_x + dx
					var wy: int = center_y + dy
					var wz: int = center_z + dz
					if wy < cave_min_y or wy >= max_height_blocks:
						continue
					var ekey: String = "%d,%d,%d" % [wx, wy, wz]
					if carved.has(ekey):
						continue
					if get_block_type_at(wx, wy, wz) == BlockType.AIR:
						continue
					_set_override_for_world(wx, wy, wz, BlockType.AIR)
					_remove_block_visual(wx, wy, wz)
					carved[ekey] = true
					affected[_chunk_key(int(floor(float(wx) / float(chunk_dimensions))), int(floor(float(wz) / float(chunk_dimensions))))] = true
	return affected


func _carve_smart_cave_entrance(world_x: int, world_z: int, surface_y: float, carved: Dictionary, rng: RandomNumberGenerator, width_override: int = -1, depth_override: int = -1) -> Dictionary:
	var path_points: Array = _build_smart_cave_path(world_x, world_z, surface_y, rng, width_override, depth_override)
	var entrance_width: int = cave_entrance_width if width_override < 0 else width_override
	var tunnel_radius: float = float(entrance_width) + 2.5
	var affected: Dictionary = _carve_tunnel_path(path_points, carved, tunnel_radius, tunnel_radius * 0.6)
	# Carve wide surface opening
	var surf_x: int = world_x
	var surf_z: int = world_z
	var sy: int = int(round(surface_y))
	var opening_r: int = entrance_width + 2
	for dx in range(-opening_r, opening_r + 1):
		for dz in range(-opening_r, opening_r + 1):
			var d2: float = float(dx * dx + dz * dz)
			if d2 > float(opening_r * opening_r):
				continue
			for dy in range(0, 4):
				var wx: int = surf_x + dx
				var wy: int = sy + dy
				var wz: int = surf_z + dz
				if wy < cave_min_y or wy >= max_height_blocks:
					continue
				var ek: String = "%d,%d,%d" % [wx, wy, wz]
				if carved.has(ek):
					continue
				if get_block_type_at(wx, wy, wz) == BlockType.AIR:
					continue
				_set_override_for_world(wx, wy, wz, BlockType.AIR)
				_remove_block_visual(wx, wy, wz)
				carved[ek] = true
				affected[_chunk_key(int(floor(float(wx) / float(chunk_dimensions))), int(floor(float(wz) / float(chunk_dimensions))))] = true
	if not path_points.is_empty():
		var end: Vector3 = path_points[path_points.size() - 1]
		var chamber_r: float = float(entrance_width) + 4.0
		var ex: int = int(round(end.x))
		var ey: int = int(round(end.y))
		var ez: int = int(round(end.z))
		var ri: int = int(ceil(chamber_r))
		for dx in range(-ri, ri + 1):
			for dy in range(-ri, ri + 1):
				for dz in range(-ri, ri + 1):
					var d2: float = float(dx * dx + dy * dy + dz * dz)
					if d2 > chamber_r * chamber_r:
						continue
					var wx: int = ex + dx
					var wy: int = ey + dy
					var wz: int = ez + dz
					if wy < cave_min_y or wy >= max_height_blocks:
						continue
					var ek: String = "%d,%d,%d" % [wx, wy, wz]
					if carved.has(ek):
						continue
					if get_block_type_at(wx, wy, wz) == BlockType.AIR:
						continue
					_set_override_for_world(wx, wy, wz, BlockType.AIR)
					_remove_block_visual(wx, wy, wz)
					carved[ek] = true
					affected[_chunk_key(int(floor(float(wx) / float(chunk_dimensions))), int(floor(float(wz) / float(chunk_dimensions))))] = true
	return affected


func _queue_chunk_rebuilds_from_keys(keys: Dictionary) -> void:
	for ck in keys:
		var parts: PackedStringArray = ck.split(",")
		if parts.size() == 2:
			_enqueue_chunk_generation(int(parts[0]), int(parts[1]), ck)


func deschide_intrare_pestera(world_x: int, world_z: int, width_override: int = -1, depth_override: int = -1) -> bool:
	if not cave_enabled:
		return false
	var surface_y: float = _surface_height_from_noise(world_x, world_z)
	if surface_y <= float(cave_min_y + 2):
		return false
	var carved: Dictionary = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(world_x, world_z)) + world_seed
	var affected: Dictionary = _carve_smart_cave_entrance(world_x, world_z, surface_y, carved, rng, width_override, depth_override)
	if carved.is_empty():
		return false
	_queue_chunk_rebuilds_from_keys(affected)
	if not chunk_generation_queue.is_empty():
		call_deferred("_process_chunk_queue")
	return true


func _genereaza_pesteri(cx: int, cz: int) -> void:
	if not cave_enabled or cave_system == null:
		return
	var key: String = _chunk_key(cx, cz)
	if chunk_caves_generated.has(key):
		return

	var min_x: int = cx * chunk_dimensions
	var max_x: int = min_x + chunk_dimensions - 1
	var min_z: int = cz * chunk_dimensions
	var max_z: int = min_z + chunk_dimensions - 1

	var key_seed: int = hash(Vector2i(cx, cz)) + world_seed
	var local_rng := RandomNumberGenerator.new()
	local_rng.seed = key_seed

	# Pre-sample height map (fast on main thread)
	var height_samples: Dictionary = {}
	var surface_base_y: float = 0.0
	var total_samples: int = 0
	for wx in range(min_x, max_x + 1):
		for wz in range(min_z, max_z + 1):
			var h: float = _surface_height_from_noise(wx, wz)
			height_samples["%d,%d" % [wx, wz]] = h
			if wx % 4 == 0 and wz % 4 == 0:
				surface_base_y += h
				total_samples += 1
	if total_samples > 0:
		surface_base_y /= float(total_samples)

	# Generate L-System segments (fast on main thread)
	var segments: Array = []
	if surface_base_y > 50.0:
		var num_roots: int = 1 if surface_base_y < 65.0 else (2 if local_rng.randf() < 0.3 else 1)
		for ri in range(num_roots):
			var sx: float = float(local_rng.randi_range(min_x + 2, max_x - 2))
			var sz: float = float(local_rng.randi_range(min_z + 2, max_z - 2))
			var base_h: float = _surface_height_from_noise(int(round(sx)), int(round(sz)))
			if base_h < 40.0:
				continue
			var start_y: float = base_h - 4.0 - local_rng.randf() * 6.0
			var start_dir: Vector3 = Vector3(local_rng.randf_range(-0.3, 0.3), -0.6 - local_rng.randf() * 0.3, local_rng.randf_range(-0.3, 0.3)).normalized()
			var start_pos: Vector3 = Vector3(sx, start_y, sz)

			var branch_segments: Array = cave_system.lsystem_generate(key_seed + ri * 100, cave_branching_iterations + local_rng.randi() % 2, start_pos, start_dir)
			for seg in branch_segments:
				segments.append(seg)

			if local_rng.randf() < 0.15:
				var river_dir: Vector3 = Vector3(local_rng.randf_range(-0.5, 0.5), -0.1, local_rng.randf_range(-0.5, 0.5)).normalized()
				var river_start: Vector3 = start_pos + Vector3(local_rng.randf_range(-5.0, 5.0), -3.0, local_rng.randf_range(-5.0, 5.0))
				var river_segments: Array = cave_system.lsystem_generate_underground_river(key_seed + ri * 100 + 37, river_start, river_dir)
				for seg in river_segments:
					segments.append(seg)

	if segments.is_empty():
		chunk_caves_generated[key] = {}
		return

	if segments.size() > 120:
		segments.resize(120)

	# Queue carving work for worker thread
	var params: Dictionary = {
		"key": key, "cx": cx, "cz": cz,
		"world_seed": world_seed,
		"height_samples": height_samples.duplicate(),
		"segments": segments.duplicate(),
		"chunk_dimensions": chunk_dimensions,
		"max_height_blocks": max_height_blocks,
		"cave_min_y": cave_min_y,
		"cave_max_depth": cave_max_depth,
		"water_level": WATER_LEVEL,
		"segments_copy": segments.duplicate()
	}
	_cave_carving_mutex.lock()
	_cave_carving_queue.append(params)
	_cave_carving_mutex.unlock()


func _cave_carving_worker(cparams: Dictionary) -> void:
	var key: String = cparams.key
	var result: Dictionary = CaveSystem.compute_carved_blocks_static(cparams)
	_cave_carving_mutex.lock()
	if _cave_carving_tasks.has(key) and typeof(_cave_carving_tasks[key]) == TYPE_DICTIONARY and _cave_carving_tasks[key].get("_placeholder", false):
		_cave_carving_tasks[key] = {"result": result, "key": key, "cx": cparams.cx, "cz": cparams.cz, "segments": cparams.segments_copy, "done": true}
	_cave_carving_mutex.unlock()


func _process_cave_carving_queue() -> void:
	if _cave_carving_queue.is_empty():
		return
	var cc_start: int = Time.get_ticks_msec()
	var launched: int = 0
	const MAX_CARVE_LAUNCH: int = 2
	while not _cave_carving_queue.is_empty():
		if launched >= MAX_CARVE_LAUNCH:
			break
		if launched > 0:
			if Time.get_ticks_msec() - cc_start >= generation_time_budget_ms:
				break
		var entry: Dictionary = _cave_carving_queue.pop_front()
		var key: String = entry.key
		_cave_carving_mutex.lock()
		_cave_carving_tasks[key] = {"_placeholder": true}
		_cave_carving_mutex.unlock()
		WorkerThreadPool.add_task(_cave_carving_worker.bind(entry), 0, "cave_carve")
		launched += 1


func _sync_cave_carving_results() -> void:
	var completed: Array = []
	_cave_carving_mutex.lock()
	for key in _cave_carving_tasks:
		var task: Dictionary = _cave_carving_tasks[key]
		if task.get("done", false):
			completed.append(task)
			_cave_carving_tasks.erase(key)
	_cave_carving_mutex.unlock()

	var sync_start: int = Time.get_ticks_msec()
	var processed: int = 0
	const MAX_SYNC: int = 2
	for task in completed:
		if processed >= MAX_SYNC:
			break
		if processed > 0:
			if Time.get_ticks_msec() - sync_start >= _sync_budget_ms:
				break
		var key: String = task.key
		var cx: int = task.cx
		var cz: int = task.cz
		var result: Dictionary = task.result
		var segments: Array = task.segments
		var carved_blocks: Array = result.get("blocks", [])
		var has_caves: bool = result.get("has_caves", false)

		# Mark as generated (even if empty, to avoid re-processing)
		var carved: Dictionary = {}
		for cb in carved_blocks:
			var ck: String = "%d,%d,%d" % [cb.x, cb.y, cb.z]
			carved[ck] = true
			_set_cave_block(cb.x, cb.y, cb.z, 0)
		chunk_caves_generated[key] = carved

		if not has_caves or carved.is_empty():
			processed += 1
			continue

		# Create sloped entrances instead of vertical shafts
		_create_cave_entrances_for_chunk(cx, cz, segments, carved)

		# Queue mesh extraction (same as before)
		var lod_mult: int = _compute_lod_mult_for_chunk(cx, cz)
		_pending_cave_mesh_queue.append({
			"key": key, "cx": cx, "cz": cz,
			"carved": carved, "lod_mult": lod_mult
		})
		processed += 1


func _create_cave_entrances_for_chunk(cx: int, cz: int, segments: Array, carved: Dictionary) -> void:
	if segments.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(cx, cz)) + world_seed + 777

	var candidates: Array = []
	for seg in segments:
		var seg_y: float = seg.a.y
		var sx: int = int(round(seg.a.x))
		var sz: int = int(round(seg.a.z))
		var surface_y: float = _surface_height_from_noise(sx, sz)
		var depth: float = surface_y - seg_y
		if depth > 2.0 and depth < 30.0:
			candidates.append({"seg": seg, "sx": sx, "sz": sz, "surface_y": surface_y, "depth": depth})

	if candidates.is_empty():
		return

	candidates.shuffle()
	var max_entrances: int = mini(2, candidates.size())
	for ei in range(max_entrances):
		var cand: Dictionary = candidates[ei]
		var carved_local: Dictionary = {}
		var entrance_depth: int = maxi(12, int(cand.depth) + 6)
		var entrance_width: int = cave_entrance_width + 1
		_carve_smart_cave_entrance(cand.sx, cand.sz, cand.surface_y, carved_local, rng, entrance_width, entrance_depth)
		for ck in carved_local:
			carved[ck] = true


func _verifica_multiplayer() -> void:
	if _NM._ws != null:
		set_multiplayer_authority(1)

func _on_terrain_change(_player_id: int, pos: Array, block_type: int, action_type: String) -> void:
	if pos.size() != 3:
		return
	var world_pos = Vector3(pos[0], pos[1], pos[2])
	if action_type == "dig":
		sapa_bloc_la_pozitie(world_pos)
	elif action_type == "place":
		_plaseaza_un_bloc(self, world_pos.x, world_pos.y, world_pos.z, block_type)
