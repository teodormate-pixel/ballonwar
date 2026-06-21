extends Node

@onready var _NM = get_node("/root/NetworkManager")

func _ready() -> void:
	await get_tree().process_frame
	if _NM.is_logged_in():
		queue_free()
		return
	if _NM.auth_ok.is_connected(_on_auth_ok):
		return
	_NM.auth_ok.connect(_on_auth_ok, CONNECT_ONE_SHOT)
	_NM.try_autologin()

func _on_auth_ok(_player_id: int, _username: String, _game_modes: Array) -> void:
	print("[Auto-Login] Autentificare reușită.")
	var scena: String = get_tree().current_scene.scene_file_path if get_tree().current_scene else ""
	if scena != "res://lume.tscn":
		get_tree().change_scene_to_file("res://Meniu.tscn")
	queue_free()
