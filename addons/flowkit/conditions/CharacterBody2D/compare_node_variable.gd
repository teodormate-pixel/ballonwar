extends FKCondition

func get_id() -> String:
	return "is_on_floor"

func get_name() -> String:
	return "Is on Floor"

func get_inputs() -> Array[Dictionary]:
	return []

func get_supported_types() -> Array[String]:
	return ["CharacterBody2D"]

func check(node: Node, inputs: Dictionary) -> bool:
	if not node is CharacterBody2D:
		return false

	var body: CharacterBody2D = node as CharacterBody2D

	return body.is_on_floor()