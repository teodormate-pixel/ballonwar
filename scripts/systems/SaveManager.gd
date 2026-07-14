extends Node

const SAVE_DIR: String = "user://save/"
const SAVE_FILE: String = "savegame.json"
const AUTO_SAVE_INTERVAL: float = 60.0
var _auto_save_timer: float = 0.0
var save_enabled: bool = true

func _ready() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)

func _process(delta: float) -> void:
	if not save_enabled:
		return
	_auto_save_timer += delta
	if _auto_save_timer >= AUTO_SAVE_INTERVAL:
		_auto_save_timer = 0.0
		auto_save()

func save_game(player_data: Dictionary) -> bool:
	var data: Dictionary = {
		"version": 1,
		"timestamp": Time.get_unix_time_from_system(),
		"player": player_data,
		"world_seed": 0,
	}
	var wc = get_node_or_null("/root/WorldConfig")
	if wc and wc.get("world_seed"):
		data["world_seed"] = wc.world_seed

	var file = FileAccess.open(SAVE_DIR + SAVE_FILE, FileAccess.WRITE)
	if not file:
		return false
	var json_str = JSON.new().stringify(data, "\t")
	file.store_string(json_str)
	file.close()
	return true

func load_game() -> Dictionary:
	var file = FileAccess.open(SAVE_DIR + SAVE_FILE, FileAccess.READ)
	if not file:
		return {}
	var text = file.get_as_text()
	file.close()
	var json = JSON.new()
	var err = json.parse(text)
	if err != OK:
		return {}
	return json.data if json.data is Dictionary else {}

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_DIR + SAVE_FILE)

func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_DIR + SAVE_FILE)

func auto_save() -> void:
	var player = get_tree().get_first_node_in_group("Jucator") as Node
	if not player or not player.has_method("get_save_data"):
		return
	if player.get("mort") == true:
		return
	save_game(player.call("get_save_data"))
