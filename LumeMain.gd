extends Node3D

@onready var _NM = get_node("/root/NetworkManager")
@onready var _GJ = get_node("/root/GestiuneJoc")

const REMOTE_PLAYER = preload("res://RemotePlayer.tscn")

var _remote_players: Dictionary = {}
var _debug_label: Label = null
var _teren_node: Node = null
var _players_node: Node3D = null

func _ready() -> void:
	_GJ.initializare(self)

	var canvas = CanvasLayer.new()
	canvas.name = "DebugCanvas"
	canvas.layer = 128
	var label = Label.new()
	label.name = "Dbg"
	label.position = Vector2(10, 10)
	label.add_theme_color_override("font_color", Color(0, 1, 0))
	label.add_theme_font_size_override("font_size", 20)
	label.text = "Loading..."
	canvas.add_child(label)
	add_child(canvas)
	_debug_label = label

	_teren_node = get_node_or_null("Teren")

	if _NM:
		_NM.state_update.connect(_on_state_update)
		_NM.connection_failed.connect(_on_connection_failed)
		label.text = "State connected. ID=" + str(_NM.player_id) + " Room=" + _NM.room_id

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

	if _debug_label:
		_debug_label.text = "RPlayers: " + str(_remote_players.size()) + "/" + str(players.size()) + " my_id=" + str(my_id) + " tick=" + str(tick)

func _on_connection_failed(msg: String) -> void:
	if _GJ:
		_GJ.cleanup()
	get_tree().change_scene_to_file("res://Meniu.tscn")
