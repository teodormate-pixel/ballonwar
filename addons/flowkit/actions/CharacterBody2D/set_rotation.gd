extends FKAction

func get_id() -> String:
	return "set_rotation"

func get_name() -> String:
	return "Set Rotation"

func get_inputs() -> Array[Dictionary]:
	return [
		{"name": "Rotation", "type": "Float"},
	]

func get_supported_types() -> Array[String]:
	return ["CharacterBody2D"]

func execute(node: Node, inputs: Dictionary) -> void:
	if not node is CharacterBody2D:
		return
	
	var body: CharacterBody2D = node as CharacterBody2D
	var rotation_value: float = float(inputs.get("Rotation", 0))
	
	body.rotation = rotation_value
