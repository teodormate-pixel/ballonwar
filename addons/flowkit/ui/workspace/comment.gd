@tool
extends MarginContainer

func _get_drag_data(at_position: Vector2):
	var preview := duplicate()
	preview.modulate.a = 0.5
	set_drag_preview(preview)
	return self
