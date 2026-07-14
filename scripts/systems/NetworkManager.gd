extends Node

signal auth_ok(player_id, username, game_modes)
signal auth_error(message)
signal registration_result(success: bool, message: String)
signal save_data_result(success: bool)
signal load_data_result(success: bool, data: Dictionary)
signal delete_account_result(success: bool, message: String)
signal room_created(room_id, player_id, settings, players)
signal joined(room_id, player_id, players, settings, seed)
signal player_joined(player_id, name)
signal player_left(player_id)
signal player_ready(player_id, character_id, name)
signal game_starting(countdown)
signal game_started(seed, terrain_modifications)
signal state_update(tick, players)
signal terrain_change(player_id, pos, block_type, action_type)
signal chat(player_id, name, message)
signal room_list(rooms)
signal room_closed(message)
signal disconnected()
signal connection_failed(message)
signal server_list_received(servers)

var player_id: int = 0
var username: String = ""
var room_id: String = ""
var is_host: bool = false
var game_modes: Array = []
var _session_username: String = ""
var _session_password: String = ""
var _logged_in: bool = false

const DEFAULT_SERVER_URL: String = "ws://62.171.162.154:8765"
const CRED_FILE: String = "user://credentials.dat"
var server_url: String = DEFAULT_SERVER_URL

var _ws: WebSocketPeer = null
var _connecting: bool = false
var _connect_time: float = 0.0
var _keepalive_time: int = 0
var _pending_messages: Array = []
var _auth_sent: bool = false
var _autologin_attempted: bool = false

# LAN discovery
var _lan_servers: Dictionary = {}
var _lan_recv: PacketPeerUDP = null
var _lan_send: PacketPeerUDP = null
var _lan_timer: float = 0.0
var _lan_recv_ok: bool = false
const LAN_PORT: int = 8913
const LAN_BROADCAST_INTERVAL: float = 2.0

func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	_start_lan_listener()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		disconnect_from_game()

func _process(delta: float) -> void:
	_lan_broadcast(delta)
	_lan_poll()
	_poll_ws()

func is_logged_in() -> bool:
	return _logged_in

func get_player_name() -> String:
	return _session_username

# --- Account System ---

func try_autologin() -> void:
	if _autologin_attempted:
		return
	_autologin_attempted = true
	var cred = _load_credentials()
	if cred.size() == 2:
		connect_and_auth(cred[0], cred[1])

func connect_and_auth(user: String, password_to_use: String) -> void:
	_session_username = user
	_session_password = password_to_use
	connect_to_server()

func register_user(username_to_register: String, password_to_register: String) -> void:
	_send_when_ready({"type": "register_user", "username": username_to_register, "password": password_to_register})

func save_player_data(data: Dictionary) -> void:
	_send({"type": "save_data", "data": data})

func load_player_data() -> void:
	_send({"type": "load_data"})

func delete_account() -> void:
	_send({"type": "delete_account"})

func connect_to_server() -> void:
	if _ws:
		_ws.close()
		_ws = null
	_ws = WebSocketPeer.new()
	_connect_time = Time.get_ticks_msec()
	_connecting = true
	_keepalive_time = 0
	_auth_sent = false
	var err = _ws.connect_to_url(server_url)
	if err != OK:
		_connecting = false
		connection_failed.emit("Cannot connect: " + str(err))

func auth(password: String = "") -> void:
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_send({"type": "auth", "username": get_player_name(), "password": password})
		return
	_session_username = get_player_name()
	_session_password = password
	connect_to_server()

# --- Credentials local storage ---

func _save_credentials(username_to_save: String, password_to_save: String) -> void:
	var file = FileAccess.open(CRED_FILE, FileAccess.WRITE)
	if file:
		var cred = {"u": username_to_save, "p": password_to_save}
		file.store_string(Marshalls.variant_to_base64(cred))
		file.close()

func _load_credentials() -> Array:
	var file = FileAccess.open(CRED_FILE, FileAccess.READ)
	if file:
		var raw = file.get_as_text()
		file.close()
		var cred = Marshalls.base64_to_variant(raw)
		if cred is Dictionary and cred.has("u") and cred.has("p"):
			return [cred["u"], cred["p"]]
	return []

func _delete_credentials() -> void:
	DirAccess.remove_absolute(CRED_FILE)

func create_room(room_name: String = "", password: String = "", settings: Dictionary = {}, room_seed: int = 0) -> void:
	if room_seed == 0:
		room_seed = randi()
	_send({
		"type": "create_room",
		"name": room_name if room_name else get_player_name() + "'s Game",
		"password": password if password else "",
		"settings": settings,
		"seed": room_seed
	})

func join_room(room_id_to_join: String, password: String = "") -> void:
	_send({"type": "join_room", "room_id": room_id_to_join, "password": password})

func leave_room() -> void:
	_send({"type": "leave_room"})

func send_ready(character_id: int) -> void:
	_send({"type": "player_ready", "character_id": character_id})

func start_game() -> void:
	_send({"type": "start_game"})

func send_input(keys: Dictionary, rot_x: float, actions: Dictionary = {}, pos_x: float = 0.0, pos_y: float = 0.0, pos_z: float = 0.0) -> void:
	_send({
		"type": "player_input",
		"keys": keys,
		"rot_x": rot_x,
		"actions": actions,
		"pos": [pos_x, pos_y, pos_z]
	})

func send_terrain_modify(pos: Array, action_type: String, block_type: int = 0) -> void:
	_send({"type": "terrain_modify", "pos": pos, "action_type": action_type, "block_type": block_type})

func send_chat(message: String) -> void:
	_send({"type": "chat", "message": message})

func fetch_server_list() -> void:
	_send({"type": "list_rooms"})

func disconnect_from_game() -> void:
	is_host = false
	player_id = 0
	username = ""
	room_id = ""
	_logged_in = false
	_pending_messages.clear()
	_connecting = false
	_auth_sent = false
	_session_username = ""
	_session_password = ""
	if _ws:
		_ws.close()
		_ws = null

func get_lan_servers() -> Array:
	var now = Time.get_unix_time_from_system()
	var result = []
	var to_remove = []
	for key in _lan_servers:
		if now - _lan_servers[key].get("updated_at", 0) > 8:
			to_remove.append(key)
			continue
		result.append({
			"host_name": _lan_servers[key].get("name", "Unnamed"),
			"ip": _lan_servers[key].get("ip", "0.0.0.0"),
			"room_id": _lan_servers[key].get("room_id", ""),
			"player_count": _lan_servers[key].get("player_count", 1),
			"max_players": _lan_servers[key].get("max_players", 8),
			"lan": true
		})
	for key in to_remove:
		_lan_servers.erase(key)
	return result

# --- Internal ---

func _poll_ws() -> void:
	if _ws == null:
		return
	_ws.poll()
	var state = _ws.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if _connecting and not _auth_sent:
			_auth_sent = true
			_send({"type": "auth", "username": _session_username, "password": _session_password})

		var now = Time.get_ticks_msec()
		if now - _keepalive_time > 8000:
			_keepalive_time = now
			_ws.put_packet(JSON.stringify({"type": "ping"}).to_utf8_buffer())

		if _pending_messages.size() > 0:
			for msg in _pending_messages:
				_send(msg)
			_pending_messages.clear()

		while _ws.get_available_packet_count() > 0:
			var raw = _ws.get_packet().get_string_from_utf8()
			var msg = JSON.parse_string(raw)
			if msg is Dictionary:
				_handle_message(msg)

	elif state == WebSocketPeer.STATE_CONNECTING:
		if Time.get_ticks_msec() - _connect_time > 10000:
			_ws.close()
			_connecting = false
			connection_failed.emit("Timeout connecting to server")

	elif state == WebSocketPeer.STATE_CLOSED or state == WebSocketPeer.STATE_CLOSING:
		if _connecting:
			_connecting = false
			connection_failed.emit("Connection failed")
		_ws = null

func _send(data: Dictionary) -> void:
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var buf = JSON.stringify(data).to_utf8_buffer()
		_ws.put_packet(buf)
		_ws.poll()
	else:
		_send_when_ready(data)

func _send_when_ready(data: Dictionary) -> void:
	if not _ws or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		_pending_messages.append(data)
		connect_to_server()

func _handle_message(msg: Dictionary) -> void:
	var msg_type = msg.get("type", "")

	match msg_type:
		"pong":
			pass

		"auth_ok":
			player_id = msg.get("player_id", 0)
			username = msg.get("username", "")
			game_modes = msg.get("game_modes", [])
			_connecting = false
			_logged_in = true
			_save_credentials(_session_username, _session_password)
			auth_ok.emit(player_id, username, game_modes)

		"auth_error":
			_connecting = false
			auth_error.emit(msg.get("message", "Auth failed"))

		"register_result":
			registration_result.emit(msg.get("success", false), msg.get("message", ""))

		"save_data_result":
			save_data_result.emit(msg.get("success", false))

		"load_data_result":
			load_data_result.emit(msg.get("success", false), msg.get("data", {}))

		"delete_account_result":
			var ok = msg.get("success", false)
			if ok:
				_delete_credentials()
				disconnect_from_game()
			delete_account_result.emit(ok, msg.get("message", ""))

		"room_created":
			room_id = msg.get("room_id", "")
			player_id = msg.get("player_id", player_id)
			is_host = true
			room_created.emit(room_id, player_id, msg.get("settings", {}), msg.get("players", []))

		"joined":
			room_id = msg.get("room_id", "")
			player_id = msg.get("player_id", player_id)
			is_host = false
			joined.emit(room_id, player_id, msg.get("players", []), msg.get("settings", {}), msg.get("seed", 0))

		"player_joined":
			player_joined.emit(msg.get("player_id", 0), msg.get("name", ""))

		"player_left":
			player_left.emit(msg.get("player_id", 0))

		"player_ready":
			player_ready.emit(msg.get("player_id", 0), msg.get("character_id", 1), msg.get("name", ""))

		"game_starting":
			game_starting.emit(msg.get("countdown", 3))

		"game_started":
			game_started.emit(msg.get("seed", 0), msg.get("terrain_modifications", []))

		"state_update":
			state_update.emit(msg.get("tick", 0), msg.get("players", []))

		"terrain_change":
			terrain_change.emit(msg.get("player_id", 0), msg.get("pos", []), msg.get("block_type", 0), msg.get("action_type", ""))

		"chat":
			chat.emit(msg.get("player_id", 0), msg.get("name", ""), msg.get("message", ""))

		"room_list":
			room_list.emit(msg.get("rooms", []))

		"room_closed":
			room_closed.emit(msg.get("message", "Room closed"))
			room_id = ""
			is_host = false

		"error":
			connection_failed.emit(msg.get("message", "Server error"))

		_:
			print("NetworkManager: unknown message type: ", msg_type)

# --- LAN (unchanged) ---

func _start_lan_listener() -> void:
	_lan_send = PacketPeerUDP.new()
	_lan_send.set_broadcast_enabled(true)
	_lan_recv = PacketPeerUDP.new()
	_lan_recv.set_broadcast_enabled(true)
	var err = _lan_recv.bind(LAN_PORT, "0.0.0.0")
	if err == OK:
		_lan_recv_ok = true

func _lan_broadcast(delta: float) -> void:
	if not is_host or room_id.is_empty():
		return
	_lan_timer += delta
	if _lan_timer < LAN_BROADCAST_INTERVAL:
		return
	_lan_timer = 0.0
	var data = JSON.stringify({
		"type": "lan_broadcast",
		"name": get_player_name() + "'s Game",
		"port": 0,
		"room_id": room_id,
		"player_count": 1,
		"max_players": 8
	})
	_lan_send.set_dest_address("255.255.255.255", LAN_PORT)
	_lan_send.put_packet(data.to_utf8_buffer())

func _lan_poll() -> void:
	if not _lan_recv_ok or not _lan_recv:
		return
	while _lan_recv.get_available_packet_count() > 0:
		var packet = _lan_recv.get_packet()
		var sender_ip = _lan_recv.get_packet_ip()
		var text = packet.get_string_from_utf8()
		var json = JSON.new()
		if json.parse(text) == OK and json.data is Dictionary:
			var d = json.data
			if d.get("type", "") == "lan_broadcast" and d.has("room_id"):
				var room = d["room_id"]
				if room.is_empty():
					continue
				var key = sender_ip + ":" + room
				d["room_id"] = room
				d["ip"] = sender_ip
				_lan_servers[key] = d.duplicate()
				_lan_servers[key]["updated_at"] = Time.get_unix_time_from_system()
