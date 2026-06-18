extends Resource
class_name FKCondition

func get_id() -> String:
    return ""

func get_name() -> String:
    return ""

func get_inputs() -> Array[Dictionary]:
    return []

func get_supported_types() -> Array[String]:
    return []

func check(node: Node, inputs: Dictionary) -> bool:
    return false
