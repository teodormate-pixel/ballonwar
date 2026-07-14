extends Node

@onready var _NM = get_node("/root/NetworkManager")
var nivel: int = 1
var bani: int = 0
var inventar: Array = []

func _ready() -> void:
	_NM.load_data_result.connect(_on_data_loaded)
	_NM.auth_ok.connect(_on_auth_ok)

func _on_auth_ok(_player_id: int, _username: String, _game_modes: Array) -> void:
	_NM.load_player_data()

func _on_data_loaded(success: bool, data: Dictionary) -> void:
	if not success or data.is_empty():
		print("[Data] Nu există date salvate.")
		return
	nivel = data.get("nivel", 1)
	bani = data.get("bani", 0)
	inventar = data.get("inventar", [])
	print("=== DATE ÎNCĂRCATE ===")
	print("Nivel: ", nivel, " Bani: ", bani, " Inventar: ", inventar)
