extends Node3D

@onready var _NM = get_node("/root/NetworkManager")
@onready var _GJ = get_node("/root/GestiuneJoc")

const REMOTE_PLAYER = preload("res://scenes/entities/RemotePlayer.tscn")

var _remote_players: Dictionary = {}
var _teren_node: Node = null
var _players_node: Node3D = null
var _loading_layer: CanvasLayer = null
var _loading_root: Control = null
var _loading_label: Label = null
var _loading_bar: ProgressBar = null
var _loading_hint: Label = null
var _terrain_ready: bool = false


func _ready() -> void:
	_GJ.initializare(self)
	_build_loading_ui()
	_update_loading_ui(0.0, 0, 1, "Preparing terrain...")
	_attach_terrain_signals()


func _build_loading_ui() -> void:
	_loading_layer = CanvasLayer.new()
	_loading_layer.name = "LoadingLayer"
	_loading_layer.layer = 256
	add_child(_loading_layer)

	_loading_root = Control.new()
	_loading_root.name = "LoadingRoot"
	_loading_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_layer.add_child(_loading_root)

	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.02, 0.05, 0.65)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_root.add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_root.add_child(center)

	var stack := VBoxContainer.new()
	stack.custom_minimum_size = Vector2(560, 120)
	stack.add_theme_constant_override("separation", 8)
	center.add_child(stack)

	_loading_label = Label.new()
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.add_theme_font_size_override("font_size", 28)
	stack.add_child(_loading_label)

	_loading_bar = ProgressBar.new()
	_loading_bar.custom_minimum_size = Vector2(560, 24)
	_loading_bar.min_value = 0.0
	_loading_bar.max_value = 100.0
	_loading_bar.value = 0.0
	_loading_bar.show_percentage = false
	stack.add_child(_loading_bar)

	_loading_hint = Label.new()
	_loading_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_hint.add_theme_font_size_override("font_size", 16)
	stack.add_child(_loading_hint)


func _attach_terrain_signals() -> void:
	_teren_node = get_node_or_null("Teren")
	if _teren_node == null:
		call_deferred("_attach_terrain_signals")
		return
	if _teren_node.has_signal("generation_progress") and not _teren_node.generation_progress.is_connected(_on_terrain_generation_progress):
		_teren_node.generation_progress.connect(_on_terrain_generation_progress)
	if _teren_node.has_signal("terrain_ready") and not _teren_node.terrain_ready.is_connected(_on_terrain_ready):
		_teren_node.terrain_ready.connect(_on_terrain_ready)


func _update_loading_ui(progress: float, loaded_chunks: int, total_chunks: int, phase: String) -> void:
	if _loading_root == null:
		return
	_loading_root.visible = true
	if _loading_label:
		_loading_label.text = phase if not phase.is_empty() else "Generating terrain..."
	if _loading_bar:
		_loading_bar.value = clamp(progress, 0.0, 1.0) * 100.0
	if _loading_hint:
		_loading_hint.text = "%d / %d chunks" % [loaded_chunks, max(1, total_chunks)]


func _on_terrain_generation_progress(progress: float, loaded_chunks: int, total_chunks: int, phase: String) -> void:
	_update_loading_ui(progress, loaded_chunks, total_chunks, phase)


func _on_terrain_ready() -> void:
	if _terrain_ready:
		return
	_terrain_ready = true
	if _loading_label:
		_loading_label.text = "World ready"
	if _loading_hint:
		_loading_hint.text = ""
	if _loading_bar:
		_loading_bar.value = 100.0
	await get_tree().create_timer(0.2).timeout
	if is_instance_valid(_loading_root):
		_loading_root.visible = false

	var gs = get_node_or_null("/root/GlobalSettings")
	if gs and gs.get("last_game_mode") != "creator":
		var sm = get_node_or_null("/root/SaveManager")
		if sm and sm.has_save():
			var data = sm.load_game()
			if data.has("player"):
				var player = get_tree().get_first_node_in_group("Jucator")
				if player and player.has_method("load_save_data"):
					player.load_save_data(data["player"])


func _get_terrain_height_at(x: float, z: float) -> float:
	if _teren_node and _teren_node.has_method("get_surface_height_at"):
		return _teren_node.get_surface_height_at(x, z)
	return 0.0


func _on_state_update(tick: int, players: Array) -> void:
	var seen_ids: Dictionary = {}
	var my_id = _NM.player_id if _NM else 0
	for p_data in players:
		var pid = p_data.get("id", 0) if p_data is Dictionary else 0
		if pid == 0:
			continue
		if pid == my_id:
			continue
		seen_ids[pid] = true
		var rp = _remote_players.get(pid)
		if not rp:
			rp = REMOTE_PLAYER.instantiate()
			rp.name = str(pid)
			if not _players_node:
				_players_node = get_node_or_null("Players") as Node3D
				if not _players_node:
					_players_node = Node3D.new()
					_players_node.name = "Players"
					add_child(_players_node)
			_players_node.add_child(rp)
			_remote_players[pid] = rp

		var pos_data = p_data.get("pos", [])
		if pos_data.size() == 3:
			var pos = Vector3(pos_data[0], pos_data[1], pos_data[2])
			rp.set_target_position(pos, p_data.get("rot", 0.0))
		rp.set_weapon_state(p_data.get("weapon", 0), p_data.get("characterId", 1))
		if p_data.has("name"):
			rp.player_name = p_data["name"]

	for pid in _remote_players.keys():
		if not seen_ids.has(pid):
			var rp = _remote_players[pid]
			if is_instance_valid(rp):
				rp.queue_free()
			_remote_players.erase(pid)


func _on_connection_failed(_msg: String) -> void:
	if _GJ:
		_GJ.cleanup()
	get_tree().change_scene_to_file("res://scenes/menu/Meniu.tscn")
