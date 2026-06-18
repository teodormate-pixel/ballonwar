extends Button

func _ready() -> void:
	pressed.connect(_on_press)

func _on_press() -> void:
	get_tree().change_scene_to_file("res://Creator.tscn")
