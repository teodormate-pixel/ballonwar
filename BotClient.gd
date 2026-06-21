extends Node

var conectat: bool = false
var player_local: Node = null
var tinta: Node = null
var distanta_oprire: float = 2.0
var timer_schimb_tinta: float = 0.0

func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	var args = OS.get_cmdline_args()
	var connect_arg = ""
	for a in args:
		if a.begins_with("--bot-connect="):
			connect_arg = a.trim_prefix("--bot-connect=")
			break
	if connect_arg.is_empty():
		return
	print("BotClient: will connect to ", connect_arg)
	var parts = connect_arg.split(":")
	var ip = parts[0] if parts.size() > 0 else "127.0.0.1"
	var port = int(parts[1]) if parts.size() > 1 else 8912
	_calibraseste_si_conecteaza(ip, port)

func _calibraseste_si_conecteaza(ip: String, port: int) -> void:
	print("BotClient: connecting to ", ip, ":", port)
	var _NM = get_node_or_null("/root/NetworkManager")
	if not _NM:
		await get_tree().process_frame
		_NM = get_node_or_null("/root/NetworkManager")
		if not _NM:
			print("BotClient: NetworkManager not found!")
			return
	_NM.auth_ok.connect(_on_bot_auth)
	_NM.game_started.connect(_on_bot_game_started)
	_NM.connection_failed.connect(func(msg): print("BotClient: connection failed: ", msg))
	_NM.server_url = "ws://" + ip + ":" + str(port)
	_NM.connect_to_server()

func _on_bot_auth(player_id: int, username: String, _game_modes: Array) -> void:
	print("BotClient: authed as ", username, ", creating/joining room...")
	_NM.create_room("Bot Room", "", {"max_players": 8})

func _on_bot_game_started(seed: int, terrain_mods: Array) -> void:
	print("BotClient: game started! Loading lume.tscn...")
	conectat = true
	get_tree().change_scene_to_file("res://lume.tscn")
	await get_tree().create_timer(2.0).timeout
	_gaseste_player()

func _gaseste_player() -> void:
	print("BotClient: searching for local player...")
	var jucatori = get_tree().get_nodes_in_group("Jucator")
	print("BotClient: found ", jucatori.size(), " nodes in group Jucator")
	for j in jucatori:
		print("BotClient: node ", j.name, " este_jucator_local=", j.este_jucator_local if "este_jucator_local" in j else "N/A")
		if j.has_method("get_script") and "este_jucator_local" in j and j.este_jucator_local:
			player_local = j
			print("BotClient: found local player: ", j.name)
			break
	if not player_local:
		print("BotClient: local player not found, retrying in 0.5s...")
		await get_tree().create_timer(0.5).timeout
		_gaseste_player()
	else:
		print("BotClient: ready, moving towards nearest remote player")

func _process(_delta: float) -> void:
	if not conectat or not player_local:
		return
	var _GJ = get_node_or_null("/root/GestiuneJoc")
	if not _GJ:
		return
	var cea_mai_aproape: Node = null
	var dist_min: float = INF
	var player_pos = player_local.global_position
	for id in _GJ.jucatori_indepartati:
		var p = _GJ.jucatori_indepartati[id]
		if not is_instance_valid(p):
			continue
		var d = player_pos.distance_to(p.global_position)
		if d < dist_min:
			dist_min = d
			cea_mai_aproape = p
	if not cea_mai_aproape:
		player_local.bot_move_dir = Vector2.ZERO
		player_local.bot_jump = false
		return
	var target_pos = cea_mai_aproape.global_position
	var dir = player_pos.direction_to(target_pos)
	dir.y = 0.0
	if dist_min > distanta_oprire:
		player_local.bot_move_dir = Vector2(dir.x, dir.z)
	else:
		player_local.bot_move_dir = Vector2.ZERO
	if dist_min < 1.5:
		player_local.bot_jump = true
	else:
		player_local.bot_jump = false