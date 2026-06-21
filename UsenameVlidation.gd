extends Label

@onready var _NM = get_node("/root/NetworkManager")

func _ready() -> void:
	await get_tree().process_frame
	_update_text()
	if not _NM.auth_ok.is_connected(_on_auth_ok):
		_NM.auth_ok.connect(_on_auth_ok)

func _on_auth_ok(_player_id: int, _username: String, _game_modes: Array) -> void:
	_update_text()

func _update_text() -> void:
	text = "Username: " + _NM.username if _NM.is_logged_in() and _NM.username != "" else "Username: Nelogat"
