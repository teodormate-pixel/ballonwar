extends Resource
class_name StructureData

@export var structure_name: String = "Structure"
@export var blocks: Array = []

func get_block_count() -> int:
	return blocks.size()

func add_block(bt: int, x: int, y: int, z: int) -> void:
	blocks.append({"x": x, "y": y, "z": z, "type": bt})

func clone() -> StructureData:
	var copy = StructureData.new()
	copy.structure_name = structure_name
	for b in blocks:
		copy.blocks.append(b.duplicate())
	return copy

func to_json_dict() -> Dictionary:
	return {"name": structure_name, "blocks": blocks.duplicate(true)}

static func from_json_dict(data: Dictionary) -> StructureData:
	var s = StructureData.new()
	s.structure_name = data.get("name", "Structure")
	s.blocks = data.get("blocks", [])
	return s

func save_to_file(path: String) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(to_json_dict(), "\t"))

static func load_from_file(path: String) -> StructureData:
	var file = FileAccess.open(path, FileAccess.READ)
	if file:
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK:
			return from_json_dict(json.data)
	return null
