extends Control

@onready var status_label: Label = $StatusLabel
@onready var ip_input: LineEdit = $LeftPanel/IPInput
@onready var password_input: LineEdit = $LeftPanel/PasswordInput
@onready var host_btn: Button = $LeftPanel/HostBtn
@onready var join_btn: Button = $LeftPanel/JoinBtn
@onready var back_btn: Button = $LeftPanel/BackBtn
@onready var server_list: ItemList = $RightPanel/ServerList
@onready var refresh_btn: Button = $RightPanel/RefreshBtn
@onready var master_url_input: LineEdit = $RightPanel/MasterURLInput
@onready var room_code_label: Label = $LeftPanel/RoomCodeLabel
@onready var start_btn: Button = get_node_or_null("LeftPanel/StartBtn")
@onready var game_mode_opt: OptionButton = get_node_or_null("LeftPanel/GameModeOpt")
@onready var seed_input: LineEdit = $LeftPanel/SeedInput
@onready var max_players_spin: SpinBox = $LeftPanel/MaxPlayersSpin

var _selected_ip: String = ""
var _ultimele_public: Array = []
var _char_select: Panel = null
var _in_room: bool = false
@onready var _NM = get_node("/root/NetworkManager")
@onready var _WC = get_node("/root/WorldConfig")

func _ready() -> void:
	_NM.auth_ok.connect(_on_auth_ok)
	_NM.auth_error.connect(_on_auth_error)
	_NM.room_created.connect(_on_room_created)
	_NM.joined.connect(_on_joined)
	_NM.game_started.connect(_on_game_started)
	_NM.connection_failed.connect(_on_connection_failed)
	_NM.room_list.connect(_on_room_list)
	_NM.player_joined.connect(_on_player_joined)
	_NM.player_left.connect(_on_player_left)
	_NM.player_ready.connect(_on_player_ready)
	_NM.game_starting.connect(_on_game_starting)
	_NM.disconnected.connect(_on_disconnected)
	host_btn.pressed.connect(_on_host)
	join_btn.pressed.connect(_on_join)
	back_btn.pressed.connect(_on_back)
	refresh_btn.pressed.connect(_on_refresh)
	if start_btn:
		start_btn.pressed.connect(_on_start_game)
		start_btn.visible = false
	server_list.item_activated.connect(_on_server_selected)
	var lan_timer = Timer.new()
	lan_timer.timeout.connect(_lan_refresh)
	lan_timer.wait_time = 3.0
	lan_timer.autostart = true
	add_child(lan_timer)
	room_code_label.text = ""
	ip_input.placeholder_text = "Room code or game name"

	_build_char_select()

	if _NM.is_logged_in():
		status_label.text = "Connected as " + _NM.username
		host_btn.disabled = false
		join_btn.disabled = false
		_populate_game_modes()
	else:
		status_label.text = "Connecting to server..."
		_NM.connect_to_server()
		host_btn.disabled = true
		join_btn.disabled = true

func _build_char_select():
	_char_select = preload("res://CharacterSelect.gd").new()
	_char_select.name = "CharacterSelect"
	_char_select.anchor_left = 0.0
	_char_select.anchor_top = 0.0
	_char_select.anchor_right = 1.0
	_char_select.anchor_bottom = 0.0
	_char_select.offset_top = 640
	_char_select.offset_bottom = 700
	add_child(_char_select)
	_char_select.confirmed.connect(_on_char_confirmed)

func _populate_game_modes():
	if game_mode_opt and _NM.game_modes.size() > 0:
		game_mode_opt.clear()
		game_mode_opt.disabled = false
		for gm in _NM.game_modes:
			if gm is Dictionary and gm.has("name"):
				game_mode_opt.add_item(gm["name"], game_mode_opt.get_item_count())
				var idx = game_mode_opt.get_item_count() - 1
				game_mode_opt.set_item_metadata(idx, gm.get("id", "free_for_all"))

func _lan_refresh() -> void:
	if _NM.get_lan_servers().size() > 0 or _ultimele_public.size() == 0:
		_reload_list(_ultimele_public)

func _on_auth_ok(_player_id: int, _username: String, game_modes: Array) -> void:
	status_label.text = "Connected as " + _username
	host_btn.disabled = false
	join_btn.disabled = false
	if game_mode_opt:
		game_mode_opt.clear()
		game_mode_opt.disabled = false
		for gm in game_modes:
			if gm is Dictionary and gm.has("name"):
				game_mode_opt.add_item(gm["name"], game_mode_opt.get_item_count())
				var idx = game_mode_opt.get_item_count() - 1
				game_mode_opt.set_item_metadata(idx, gm.get("id", "free_for_all"))

func _on_auth_error(msg: String) -> void:
	status_label.text = "Auth failed: " + msg
	host_btn.disabled = true
	join_btn.disabled = true

func _on_host() -> void:
	var passwd = password_input.text.strip_edges()
	var room_name = ip_input.text.strip_edges()
	if room_name.is_empty():
		room_name = _NM.get_player_name() + "'s Game"
	if room_name.length() > 30:
		room_name = room_name.substr(0, 30)
	var game_mode = "free_for_all"
	if game_mode_opt and game_mode_opt.get_selected_id() >= 0:
		game_mode = game_mode_opt.get_item_metadata(game_mode_opt.get_selected_id())
	var seed = int(seed_input.text.strip_edges()) if not seed_input.text.strip_edges().is_empty() else randi()
	var max_players = int(max_players_spin.value)
	status_label.text = "Creating room (" + game_mode + ")..."
	_NM.create_room(room_name, passwd, {"game_mode": game_mode, "seed": seed, "max_players": max_players})

func _on_join() -> void:
	var room_id = _selected_ip if _selected_ip != "" else ip_input.text.strip_edges()
	if room_id.is_empty():
		status_label.text = "Enter a room code!"
		return
	var passwd = password_input.text.strip_edges()
	status_label.text = "Joining room..."
	_NM.join_room(room_id, passwd)

func _on_room_created(room_id: String, _player_id: int, settings: Dictionary, _players: Array) -> void:
	var gm_name = _get_game_mode_name(settings.get("game_mode", ""))
	room_code_label.text = "Room: " + room_id + "  [" + gm_name + "]"
	status_label.text = "Select your character and press CONFIRM"
	if start_btn:
		start_btn.visible = true
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(room_id)
	host_btn.disabled = true
	join_btn.disabled = true
	_in_room = true

func _on_joined(_room_id: String, _player_id: int, _players: Array, settings: Dictionary, _seed: int) -> void:
	var gm_name = _get_game_mode_name(settings.get("game_mode", ""))
	status_label.text = "Joined! Select your character and press CONFIRM"
	room_code_label.text = "Room: " + _room_id + "  [" + gm_name + "]"
	host_btn.disabled = true
	join_btn.disabled = true
	_in_room = true

func _on_player_joined(pid: int, name: String) -> void:
	status_label.text = name + " joined the room"

func _on_player_left(pid: int) -> void:
	status_label.text = "A player left"

func _on_game_starting(countdown: int) -> void:
	status_label.text = "Game starting in " + str(countdown) + "..."

func _on_game_started(seed: int, _terrain_mods: Array) -> void:
	status_label.text = "Game started!"
	_WC.world_seed = seed
	get_tree().change_scene_to_file("res://lume.tscn")

func _on_player_ready(pid: int, character_id: int, name: String) -> void:
	var char_name = _get_char_name(character_id)
	if pid == _NM.player_id:
		_char_select.set_ready_status("Ready (" + char_name + ")")
	else:
		_char_select.set_ready_status(name + " ready (" + char_name + ")")

func _on_start_game() -> void:
	if _NM.is_host:
		status_label.text = "Starting game..."
		_NM.start_game()
		if start_btn:
			start_btn.visible = false

func _on_char_confirmed(cid: int):
	status_label.text = "Ready with " + _get_char_name(cid)
	_NM.send_ready(cid)

func _get_char_name(cid: int) -> String:
	var CD = get_node("/root/CharacterData")
	for c in CD.characters:
		if c["id"] == cid:
			return c["name"]
	return "Character"

func _on_back() -> void:
	_NM.disconnect_from_game()
	_in_room = false
	_char_select.set_ready_status("")
	get_tree().change_scene_to_file("res://Meniu.tscn")

func _on_connection_failed(msg: String) -> void:
	status_label.text = "Failed: " + msg

func _on_disconnected() -> void:
	status_label.text = "Disconnected"
	host_btn.disabled = true
	join_btn.disabled = true
	_in_room = false
	_char_select.set_ready_status("")

func _on_refresh() -> void:
	server_list.clear()
	status_label.text = "Fetching server list..."
	_NM.fetch_server_list()

func _reload_list(servers: Array = []) -> void:
	server_list.clear()
	var lan = _NM.get_lan_servers()
	var has_lan = not lan.is_empty()
	var has_public = not servers.is_empty()
	if has_lan:
		server_list.add_item("--- LAN ---")
		server_list.set_item_metadata(server_list.get_item_count() - 1, {"separator": true})
		for s in lan:
			var has_pw = s.get("has_password", false)
			var lock = " [LOCK]" if has_pw else ""
			var label = "[LAN]" + lock + " " + s.get("host_name", "Unnamed") + "  (" + str(s.get("player_count", 1)) + "/8)"
			server_list.add_item(label)
			var idx = server_list.get_item_count() - 1
			server_list.set_item_metadata(idx, {"room_id": s.get("room_id", ""), "has_password": has_pw})
	if has_public:
		server_list.add_item("--- PUBLIC ---")
		server_list.set_item_metadata(server_list.get_item_count() - 1, {"separator": true})
		for s in servers:
			var has_pw = s.get("has_password", false)
			var lock = " [LOCK]" if has_pw else ""
			var gm_name = s.get("game_mode_name", "")
			var gm_tag = " [" + gm_name + "]" if gm_name else ""
			var label = s.get("name", "Unnamed") + gm_tag + " [" + s.get("room_id", "????") + "]" + lock + "  (" + str(s.get("player_count", 1)) + "/" + str(s.get("max_players", 8)) + ")"
			server_list.add_item(label)
			var idx = server_list.get_item_count() - 1
			server_list.set_item_metadata(idx, {"room_id": s.get("room_id", ""), "has_password": has_pw})
	if not has_lan and not has_public:
		status_label.text = "No servers found."
	else:
		var count_str = ""
		if has_lan:
			count_str += str(lan.size()) + " LAN"
		if has_lan and has_public:
			count_str += " + "
		if has_public:
			count_str += str(servers.size()) + " public"
		status_label.text = "Found " + count_str + " server(s). Double-click to join."

func _on_room_list(rooms: Array) -> void:
	_ultimele_public = rooms
	_reload_list(rooms)

func _get_game_mode_name(mode_id: String) -> String:
	for gm in _NM.game_modes:
		if gm is Dictionary and gm.get("id", "") == mode_id:
			return gm.get("name", mode_id)
	return mode_id

func _on_server_selected(index: int) -> void:
	var meta = server_list.get_item_metadata(index)
	if meta is Dictionary and meta.has("separator"):
		return
	if meta is Dictionary and meta.has("room_id"):
		_selected_ip = meta["room_id"]
		if meta.has("has_password") and meta["has_password"]:
			status_label.text = "Room has password — enter it in the Password field"
		_on_join()
