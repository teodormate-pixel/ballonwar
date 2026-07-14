extends Button

@export_file("*.tscn") var calea_catre_scena: String = "res://scenes/world/lume.tscn"

var _loading_root: Control = null
var _loading_label: Label = null
var _loading_bar: ProgressBar = null
var _load_done: bool = false
var _scene_packed: PackedScene = null


func _ready() -> void:
	pressed.connect(_on_button_pressed)


func _on_button_pressed() -> void:
	if calea_catre_scena == "":
		return
	_build_loading_ui()
	ResourceLoader.load_threaded_request(calea_catre_scena, "PackedScene")
	set_process(true)


func _process(_delta: float) -> void:
	if _load_done:
		return
	var progress: Array = []
	var status: int = ResourceLoader.load_threaded_get_status(calea_catre_scena, progress)
	if status == 1:
		var pct: float = progress[0] if progress.size() > 0 else 0.0
		if _loading_bar:
			_loading_bar.value = pct * 100.0
		if _loading_label:
			_loading_label.text = "Loading... %d%%" % [pct * 100]
	elif status == 3:
		_load_done = true
		_scene_packed = ResourceLoader.load_threaded_get(calea_catre_scena)
		if _loading_label:
			_loading_label.text = "Entering world..."
		if _loading_bar:
			_loading_bar.value = 100.0
		set_process(false)
		get_tree().change_scene_to_packed(_scene_packed)


func _build_loading_ui() -> void:
	disabled = true

	var layer := CanvasLayer.new()
	layer.name = "MenuLoadingLayer"
	layer.layer = 257
	get_tree().current_scene.add_child(layer)

	_loading_root = Control.new()
	_loading_root.name = "MenuLoadingRoot"
	_loading_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_root.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(_loading_root)

	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.7)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_root.add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_root.add_child(center)

	var stack := VBoxContainer.new()
	stack.custom_minimum_size = Vector2(400, 80)
	stack.add_theme_constant_override("separation", 12)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(stack)

	_loading_label = Label.new()
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.add_theme_font_size_override("font_size", 24)
	_loading_label.text = "Loading..."
	_loading_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(_loading_label)

	_loading_bar = ProgressBar.new()
	_loading_bar.custom_minimum_size = Vector2(400, 20)
	_loading_bar.min_value = 0.0
	_loading_bar.max_value = 100.0
	_loading_bar.value = 0.0
	_loading_bar.show_percentage = false
	_loading_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(_loading_bar)


func _cleanup_loading() -> void:
	if _loading_root != null and is_instance_valid(_loading_root):
		var parent: CanvasLayer = _loading_root.get_parent() as CanvasLayer
		if parent != null and is_instance_valid(parent):
			parent.queue_free()
	_loading_root = null
	_loading_label = null
	_loading_bar = null
