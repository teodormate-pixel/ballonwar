extends Node3D
# class_name TerenProcedural

enum BlockType { AIR, GRASS, DIRT, STONE, COAL, IRON }

@export var grid_width: int = 32
@export var grid_depth: int = 32
@export var cell_size: float = 1.0
@export var max_height: float = 20.0
@export var noise_scale: float = 0.1
@export var noise_octaves: int = 4

@export var grass_layer_depth: float = 4.0
@export var dirt_layer_depth: float = 7.0
@export var ore_layer_depth: float = 100.0
@export var ore_chance_coal: float = 0.02
@export var ore_chance_iron: float = 0.01

@export var smoothing_passes: int = 2
@export var smoothing_radius: int = 2

@export var dig_radius: float = 2.5
@export var build_radius: float = 2.5

signal terrain_dug(removed_blocks: Dictionary)
signal terrain_built(added_blocks: Dictionary)

var noise: FastNoiseLite = FastNoiseLite.new()
var height_map = []
var top_block_map = []
var mesh_instance: MeshInstance3D
var material: StandardMaterial3D

func _ready() -> void:
	_init_noise()
	_generate_height_map()
	_generate_block_map()
	_apply_smoothing()
	_create_mesh_instance()
	_update_mesh()

func _init_noise() -> void:
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.seed = randi()
	noise.frequency = noise_scale
	noise.fractal_octaves = noise_octaves

func _generate_height_map() -> void:
	height_map.clear()
	for x in range(grid_width):
		height_map.append([])
		for z in range(grid_depth):
			var height_value: float = noise.get_noise_2d(x, z) * max_height
			height_map[x].append(clamp(height_value, 0.0, max_height))

func _generate_block_map() -> void:
	top_block_map.clear()
	for x in range(grid_width):
		top_block_map.append([])
		for z in range(grid_depth):
			var current_height: float = height_map[x][z]
			if current_height < grass_layer_depth:
				top_block_map[x].append(BlockType.GRASS)
			elif current_height < grass_layer_depth + dirt_layer_depth:
				top_block_map[x].append(BlockType.DIRT)
			elif current_height < grass_layer_depth + dirt_layer_depth + ore_layer_depth:
				var r: float = randf()
				if r < ore_chance_coal:
					top_block_map[x].append(BlockType.COAL)
				elif r < ore_chance_coal + ore_chance_iron:
					top_block_map[x].append(BlockType.IRON)
				else:
					top_block_map[x].append(BlockType.STONE)
			else:
				top_block_map[x].append(BlockType.STONE)

func _apply_smoothing() -> void:
	for pass_i in range(smoothing_passes):
		var new_height_map = []
		for x in range(grid_width):
			new_height_map.append([])
			for z in range(grid_depth):
				var sum_heights: float = 0.0
				var count: int = 0
				for dx in range(-smoothing_radius, smoothing_radius + 1):
					for dz in range(-smoothing_radius, smoothing_radius + 1):
						var nx: int = clamp(x + dx, 0, grid_width - 1)
						var nz: int = clamp(z + dz, 0, grid_depth - 1)
						sum_heights += height_map[nx][nz]
						count += 1
				new_height_map[x].append(sum_heights / max(1, count))
		height_map = new_height_map

func _create_mesh_instance() -> void:
	mesh_instance = MeshInstance3D.new()
	material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	mesh_instance.material_override = material
	add_child(mesh_instance)

func _update_mesh() -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x in range(grid_width - 1):
		for z in range(grid_depth - 1):
			var v00: Vector3 = Vector3(x * cell_size, height_map[x][z], z * cell_size)
			var v10: Vector3 = Vector3((x + 1) * cell_size, height_map[x + 1][z], z * cell_size)
			var v11: Vector3 = Vector3((x + 1) * cell_size, height_map[x + 1][z + 1], (z + 1) * cell_size)
			var v01: Vector3 = Vector3(x * cell_size, height_map[x][z + 1], (z + 1) * cell_size)

			var bt00: int = top_block_map[x][z]
			var bt10: int = top_block_map[x + 1][z]
			var bt11: int = top_block_map[x + 1][z + 1]
			var bt01: int = top_block_map[x][z + 1]

			var c00: Color = _color_for_block(bt00)
			var c10: Color = _color_for_block(bt10)
			var c11: Color = _color_for_block(bt11)
			var c01: Color = _color_for_block(bt01)

			# Triangle 1
			st.set_color(c00)
			st.add_vertex(v00)
			st.set_color(c10)
			st.add_vertex(v10)
			st.set_color(c11)
			st.add_vertex(v11)
			# Triangle 2
			st.set_color(c11)
			st.add_vertex(v11)
			st.set_color(c01)
			st.add_vertex(v01)
			st.set_color(c00)
			st.add_vertex(v00)
	st.generate_normals()
	mesh_instance.mesh = st.commit()

func _color_for_block(block_type: int) -> Color:
	match block_type:
		BlockType.GRASS:
			return Color(0.15, 0.45, 0.25)
		BlockType.DIRT:
			return Color(0.38, 0.28, 0.18)
		BlockType.STONE:
			return Color(0.5, 0.5, 0.5)
		BlockType.COAL:
			return Color(0.1, 0.1, 0.1)
		BlockType.IRON:
			return Color(0.8, 0.8, 0.7)
	return Color(1.0, 1.0, 1.0)

func dig_sphere(world_pos: Vector3) -> void:
	var removed: Dictionary = {}
	for x in range(grid_width):
		for z in range(grid_depth):
			var pos: Vector3 = Vector3(x * cell_size, height_map[x][z], z * cell_size)
			if pos.distance_to(world_pos) <= dig_radius:
				removed[Vector2(x, z)] = top_block_map[x][z]
				height_map[x][z] = max(0.0, height_map[x][z] - dig_radius)
	_apply_smoothing()
	_generate_block_map()
	_update_mesh()
	emit_signal("terrain_dug", removed)

func build_sphere(world_pos: Vector3) -> void:
	var added: Dictionary = {}
	for x in range(grid_width):
		for z in range(grid_depth):
			var pos: Vector3 = Vector3(x * cell_size, height_map[x][z], z * cell_size)
			if pos.distance_to(world_pos) <= build_radius:
				height_map[x][z] += build_radius
				added[Vector2(x, z)] = top_block_map[x][z]
	_apply_smoothing()
	_generate_block_map()
	_update_mesh()
	emit_signal("terrain_built", added)

func sapa_bloc(world_pos: Vector3, direction: Vector3) -> int:
	var ix: int = int(floor(world_pos.x / cell_size))
	var iz: int = int(floor(world_pos.z / cell_size))
	if ix < 0 or ix >= grid_width or iz < 0 or iz >= grid_depth:
		return BlockType.AIR
	var btype: int = top_block_map[ix][iz]
	if btype == BlockType.AIR:
		return BlockType.AIR
	height_map[ix][iz] = max(0.0, height_map[ix][iz] - cell_size)
	_apply_smoothing()
	_generate_block_map()
	_update_mesh()
	emit_signal("terrain_dug", {Vector2(ix, iz): btype})
	return btype

func sapa_sfera(world_pos: Vector3, direction: Vector3) -> Array:
	var removed: Dictionary = {}
	for x in range(grid_width):
		for z in range(grid_depth):
			var pos: Vector3 = Vector3(x * cell_size, height_map[x][z], z * cell_size)
			if pos.distance_to(world_pos) <= dig_radius:
				removed[Vector2(x, z)] = top_block_map[x][z]
				height_map[x][z] = max(0.0, height_map[x][z] - dig_radius)
	_apply_smoothing()
	_generate_block_map()
	_update_mesh()
	emit_signal("terrain_dug", removed)
	var blocks: Array = []
	for btype in removed.values():
		blocks.append(btype)
	return blocks
