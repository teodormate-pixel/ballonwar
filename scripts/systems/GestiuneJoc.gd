extends Node

var _NM = null
var gestiune_nod: Node3D = null


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	_NM = get_node("/root/NetworkManager")


func initializare(nod_lume: Node3D) -> void:
	gestiune_nod = nod_lume
	if _NM and _NM.room_id != "":
		if not _NM.connection_failed.is_connected(_server_disconnected):
			_NM.connection_failed.connect(_server_disconnected)

func _reset() -> void:
	if _NM.connection_failed.is_connected(_server_disconnected):
		_NM.connection_failed.disconnect(_server_disconnected)
	cleanup()


func cleanup() -> void:
	gestiune_nod = null
	if _NM and _NM.has_method("disconnect_from_game"):
		_NM.disconnect_from_game()


func _server_disconnected(_msg: String = "") -> void:
	cleanup()
	var scena = get_tree().current_scene
	if scena and scena.name == "Lume":
		get_tree().change_scene_to_file("res://scenes/menu/Meniu.tscn")


func actualizeaza_pozitie_jucator(id: int, pos: Vector3, rot_y: float, mod: int = 0, arma: int = 0) -> void:
	if gestiune_nod == null:
		return
	var players = gestiune_nod.get_node_or_null("Players")
	if not players:
		return
	var p = players.get_node_or_null(str(id))
	if not p:
		return
	if p.has_method("set_target_position"):
		p.set_target_position(pos, rot_y)
	if p.has_method("set_weapon_state"):
		p.set_weapon_state(mod, arma)


func get_player_name_for_id(id: int) -> String:
	if id <= 1:
		return _NM.username if _NM.is_logged_in() and _NM.username != "" else "Host"
	return "Player " + str(id)
