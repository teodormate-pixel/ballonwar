extends Resource
class_name FKEventBlock

@export var event_id: String
@export var target_node: NodePath
@export var inputs: Dictionary = {}
@export var conditions: Array[FKEventCondition] = []
@export var actions: Array[FKEventAction] = []
