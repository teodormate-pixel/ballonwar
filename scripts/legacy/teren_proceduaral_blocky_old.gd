extends Node3D
# class_name TerenProcedural

enum BlockType { AIR, DIRT, STONE, COAL, IRON }

@export var chunk_dimensions: int = 32
@export var max_height_blocks: int = 50
@export var dirt_height_ratio: float = 0.6
@export var ore_chance_coal: float = 0.02
@export var ore_chance_iron: float = 0.01
@export var distanta_randare: int = 2
@export var interact_distance: float = 12.0
@export var ray_step: float = 0.25

var zgomot: FastNoiseLite = FastNoiseLite.new()
var chunk_jucator_vechi: Vector2i = Vector2i(-999, -999)
var nod_jucator: CharacterBody3D = null
var chunk_blocks: Dictionary = {}
var chunk_multimesh_instances: Dictionary = {}
var material_dirt: StandardMaterial3D
var material_stone: StandardMaterial3D
var material_coal: StandardMaterial3D
var material_iron: StandardMaterial3D
var cube_mesh: BoxMesh = BoxMesh.new()

func _ready() -> void:
	_init_materials()
	zgomot.noise_type = FastNoiseLite.TYPE_PERLIN
	zgomot.seed = randi()
	zgomot.frequency = 0.05
	cube_mesh.size = Vector3.ONE
	cautare_jucator_securizata()
	_actualizeaza_chunk_uri(Vector2i.ZERO)

func _physics_process(_delta: float) -> void:
	if nod_jucator == null:
		cautare_jucator_securizata()
		return
	var cx: int = int(floor(nod_jucator.global_position.x / chunk_dimensions))
	var cz: int = int(floor(nod_jucator.global_position.z / chunk_dimensions))
	var chunk_curent: Vector2i = Vector2i(cx, cz)
	if chunk_curent != chunk_jucator_vechi:
		_actualizeaza_chunk_uri(chunk_curent)
		chunk_jucator_vechi = chunk_curent

func _init_materials() -> void:
	material_dirt = StandardMaterial3D.new()
	material_dirt.albedo_color = Color(0.6, 0.4, 0.2)
	material_dirt.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED

	material_stone = StandardMaterial3D.new()
	material_stone.albedo_color = Color(0.5, 0.5, 0.5)
	material_stone.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED

	material_coal = StandardMaterial3D.new()
	material_coal.albedo_color = Color(0.1, 0.1, 0.1)
	material_coal.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED

	material_iron = StandardMaterial3D.new()
	material_iron.albedo_color = Color(0.7, 0.7, 0.8)
	material_iron.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED

func cautare_jucator_securizata() -> void:
	var jucatori: Array = get_tree().get_nodes_in_group("Jucator")
	if jucatori.size() > 0:
		nod_jucator = jucatori[0] as CharacterBody3D

func _actualizeaza_chunk_uri(centru_chunk: Vector2i) -> void:
	var chei_necesare: Array = []
	for x_offset in range(-distanta_randare, distanta_randare + 1):
		for z_offset in range(-distanta_randare, distanta_randare + 1):
			var coord: Vector2i = Vector2i(centru_chunk.x + x_offset, centru_chunk.y + z_offset)
			var key: String = "%d,%d" % [coord.x, coord.y]
			chei_necesare.append(key)
			if not chunk_blocks.has(key):
				_genereaza_singur_chunk(coord.x, coord.y, key)
	for existing_key in chunk_blocks.keys():
		if not chei_necesare.has(existing_key):
			_clear_chunk_visuals(existing_key)
			chunk_blocks.erase(existing_key)

func _genereaza_singur_chunk(cx: int, cz: int, key: String) -> void:
	var origin: Vector3 = Vector3(cx * chunk_dimensions, 0, cz * chunk_dimensions)
	var grid: Array = []
	for x in range(chunk_dimensions):
		grid.append([])
		for y in range(max_height_blocks):
			grid[x].append([])
			for z in range(chunk_dimensions):
				var world_x: float = origin.x + x
				var world_z: float = origin.z + z
				var height_noise: float = clamp(zgomot.get_noise_2d(world_x, world_z) * max_height_blocks, 0, max_height_blocks - 1)
				if y > height_noise:
					grid[x][y].append(BlockType.AIR)
				else:
					if y < height_noise * dirt_height_ratio:
						grid[x][y].append(BlockType.DIRT)
					else:
						var rnd: float = randf()
						if rnd < ore_chance_coal:
							grid[x][y].append(BlockType.COAL)
						elif rnd < ore_chance_coal + ore_chance_iron:
							grid[x][y].append(BlockType.IRON)
						else:
							grid[x][y].append(BlockType.STONE)
	chunk_blocks[key] = grid
	_rebuild_chunk_visuals(key)

func _rebuild_chunk_visuals(key: String) -> void:
	if not chunk_blocks.has(key):
		return
	_clear_chunk_visuals(key)
	var origin: Vector3 = _chunk_origin_from_key(key)
	var transforms_by_type: Dictionary = {
		BlockType.DIRT: [],
		BlockType.STONE: [],
		BlockType.COAL: [],
		BlockType.IRON: []
	}
	var grid: Array = chunk_blocks[key]
	for x in range(chunk_dimensions):
		for y in range(max_height_blocks):
			for z in range(chunk_dimensions):
				var ttype: int = grid[x][y][z]
				if ttype != BlockType.AIR:
					var transform: Transform3D = Transform3D.IDENTITY
					transform.origin = origin + Vector3(x + 0.5, y + 0.5, z + 0.5)
					if transforms_by_type.has(ttype):
						transforms_by_type[ttype].append(transform)
	var inst_dict: Dictionary = {}
	for btype in transforms_by_type.keys():
		var trs: Array = transforms_by_type[btype]
		if trs.size() == 0:
			continue
		var mminst: MultiMeshInstance3D = MultiMeshInstance3D.new()
		var mm: MultiMesh = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = cube_mesh
		mm.instance_count = trs.size()
		for i in range(trs.size()):
			mm.set_instance_transform(i, trs[i])
		mminst.multimesh = mm
		mminst.material_override = _material_for_block(btype)
		add_child(mminst)
		inst_dict[btype] = mminst
	chunk_multimesh_instances[key] = inst_dict

func _clear_chunk_visuals(key: String) -> void:
	if not chunk_multimesh_instances.has(key):
		return
	var inst_dict: Dictionary = chunk_multimesh_instances[key]
	for node in inst_dict.values():
		if is_instance_valid(node):
			node.queue_free()
	chunk_multimesh_instances.erase(key)

func _chunk_origin_from_key(key: String) -> Vector3:
	var parts: Array = key.split(",")
	var cx: int = int(parts[0])
	var cz: int = int(parts[1])
	return Vector3(cx * chunk_dimensions, 0, cz * chunk_dimensions)

func _material_for_block(block_type: int) -> StandardMaterial3D:
	match block_type:
		BlockType.DIRT: return material_dirt
		BlockType.STONE: return material_stone
		BlockType.COAL: return material_coal
		BlockType.IRON: return material_iron
	return material_dirt

func _world_to_grid_info(pos: Vector3):
	var ix: int = int(floor(pos.x))
	var iy: int = int(floor(pos.y))
	var iz: int = int(floor(pos.z))
	if iy < 0 or iy >= max_height_blocks:
		return null
	var chunk_x: int = int(floor(float(ix) / float(chunk_dimensions)))
	var chunk_z: int = int(floor(float(iz) / float(chunk_dimensions)))
	var local_x: int = ix - chunk_x * chunk_dimensions
	var local_z: int = iz - chunk_z * chunk_dimensions
	if local_x < 0 or local_x >= chunk_dimensions or local_z < 0 or local_z >= chunk_dimensions:
		return null
	return {
		"chunk_key": "%d,%d" % [chunk_x, chunk_z],
		"local_x": local_x,
		"local_y": iy,
		"local_z": local_z,
		"world": Vector3(ix, iy, iz)
	}

func ray_pick_block(start: Vector3, direction: Vector3, max_distance: float = 0.0):
	if direction == Vector3.ZERO:
		return null
	var dir: Vector3 = direction.normalized()
	var travel_distance: float = 0.0
	var max_dist: float = max_distance if max_distance > 0.0 else interact_distance
	while travel_distance <= max_dist:
		var current_pos: Vector3 = start + dir * travel_distance
		var info: Dictionary = _world_to_grid_info(current_pos)
		if info != null and chunk_blocks.has(info["chunk_key"]):
			var block_type: int = chunk_blocks[info["chunk_key"]][info["local_x"]][info["local_y"]][info["local_z"]]
			if block_type != BlockType.AIR:
				var placement_dist: float = max(travel_distance - ray_step, 0.0)
				var placement_pos: Vector3 = start + dir * placement_dist
				var placement_info: Dictionary = _world_to_grid_info(placement_pos)
				return {
					"hit": info,
					"placement": placement_info
				}
		travel_distance += ray_step
	return null

func sapa_bloc(start: Vector3, direction: Vector3) -> int:
	var result: Dictionary = ray_pick_block(start, direction, interact_distance)
	if result == null:
		return BlockType.AIR
	var info: Dictionary = result["hit"]
	var chunk_key: String = info["chunk_key"]
	if not chunk_blocks.has(chunk_key):
		return BlockType.AIR
	var block_type: int = chunk_blocks[chunk_key][info["local_x"]][info["local_y"]][info["local_z"]]
	if block_type == BlockType.AIR:
		return BlockType.AIR
	chunk_blocks[chunk_key][info["local_x"]][info["local_y"]][info["local_z"]] = BlockType.AIR
	_rebuild_chunk_visuals(chunk_key)
	return block_type

func adauga_bloc(start: Vector3, direction: Vector3, block_type: int) -> bool:
	var result: Dictionary = ray_pick_block(start, direction, interact_distance)
	if result == null:
		return false
	var placement: Dictionary = result["placement"]
	if placement == null:
		return false
	var chunk_key: String = placement["chunk_key"]
	if not chunk_blocks.has(chunk_key):
		return false
	var local_x: int = placement["local_x"]
	var local_y: int = placement["local_y"]
	var local_z: int = placement["local_z"]
	if local_y < 0 or local_y >= max_height_blocks:
		return false
	if chunk_blocks[chunk_key][local_x][local_y][local_z] != BlockType.AIR:
		return false
	chunk_blocks[chunk_key][local_x][local_y][local_z] = block_type
	_rebuild_chunk_visuals(chunk_key)
	return true

func get_block_name(block_type: int) -> String:
	match block_type:
		BlockType.DIRT: return "Dirt"
		BlockType.STONE: return "Stone"
		BlockType.COAL: return "Coal"
		BlockType.IRON: return "Iron"
	return "Unknown"
