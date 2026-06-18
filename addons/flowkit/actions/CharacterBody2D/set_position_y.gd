extends FKAction

func get_id() -> String:
	return "set_position_y"

func get_name() -> String:
	return "Set Y Position"

func get_inputs() -> Array[Dictionary]:
	return [
		{"name": "Y", "type": "Float"}
	]

func get_supported_types() -> Array[String]:
	return ["CharacterBody2D"]

func execute(node: Node, inputs: Dictionary) -> void:
	if not node is CharacterBody2D:
		return
	
	var body: CharacterBody2D = node as CharacterBody2D
	var y: float = float(inputs.get("Y", 0))
	
	body.position.y = y
