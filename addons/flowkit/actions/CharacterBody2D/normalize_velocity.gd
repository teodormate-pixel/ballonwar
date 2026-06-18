extends FKAction

func get_id() -> String:
	return "normalize_velocity"

func get_name() -> String:
	return "Normalize Velocity"

func get_inputs() -> Array[Dictionary]:
	return []

func get_supported_types() -> Array[String]:
	return ["CharacterBody2D"]

func execute(node: Node, inputs: Dictionary) -> void:
	if not node is CharacterBody2D:
		return
	
	var body: CharacterBody2D = node as CharacterBody2D
	
	body.velocity = body.velocity.normalized()
