extends Resource
class_name FKEventCondition

@export var condition_id: String
@export var target_node: NodePath
@export var inputs: Dictionary = {}
@export var negated: bool = false
@export var actions: Array[FKEventAction] = []
