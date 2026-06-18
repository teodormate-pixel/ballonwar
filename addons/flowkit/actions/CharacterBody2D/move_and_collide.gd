extends FKAction

func get_id() -> String:
	return "move_and_collide"

func get_name() -> String:
	return "Move and Collide"

func get_inputs() -> Array[Dictionary]:
	return [
		{"name": "X", "type": "Float"},
		{"name": "Y", "type": "Float"},
	]

func get_supported_types() -> Array[String]:
	return ["CharacterBody2D"]

func execute(node: Node, inputs: Dictionary) -> void:
	if not node is CharacterBody2D:
		return
	
	var body: CharacterBody2D = node as CharacterBody2D
	var x: float = float(inputs.get("X", 0))
	var y: float = float(inputs.get("Y", 0))

	body.move_and_collide(Vector2(x, y))
