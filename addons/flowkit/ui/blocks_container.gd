@tool
extends VBoxContainer

func _can_drop_data(at_position: Vector2, data) -> bool:
	if not data is Dictionary:
		return false
	if not data.has("node"):
		return false
	
	var node = data["node"]
	return is_instance_valid(node) and node.get_parent() == self

func _drop_data(at_position: Vector2, data) -> void:
	if not data is Dictionary or not data.has("node"):
		return
	
	var node = data["node"]
	if not is_instance_valid(node) or node.get_parent() != self:
		return
	
	var old_idx = node.get_index()
	var new_idx = _calculate_drop_index(at_position)
	
	if new_idx > old_idx:
		new_idx -= 1
	
	if old_idx != new_idx:
		move_child(node, new_idx)

func _calculate_drop_index(at_position: Vector2) -> int:
	for i in range(get_child_count()):
		var child = get_child(i)
		if not child.visible or child.name == "EmptyLabel":
			continue
		
		var rect = child.get_rect()
		if at_position.y < rect.position.y + rect.size.y * 0.5:
			return i
	
	return get_child_count()
