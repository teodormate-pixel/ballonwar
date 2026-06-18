extends Node

signal player_joined(id: int)
signal player_left(id: int)
signal connection_success()
signal connection_failed(msg: String)
signal server_created()
signal server_list_received(servers: Array)

var peer: ENetMultiplayerPeer = null
var is_host: bool = false
var minha_id: int = 1
var jogadores: Dictionary = {}
var lobby_password: String = ""
var server_name: String = "Balloon War"
var public_server: bool = false
var server_id: String = ""
var _lobby_timer: float = 0.0
var _cleanup_pending: bool = false
var _cleanup_timer: float = 0.0
var LAN_BROADCAST_INTERVAL: float = 2.0
var _lan_timer: float = 0.0
var _lan_servers: Dictionary = {}
var _lan_recv: PacketPeerUDP = null
var _lan_recv_ok: bool = false
var _lan_send: PacketPeerUDP = null

const PORTO_PADRAO: int = 8912
const LOBBY_PING_SEC: float = 20.0
const LAN_PORT: int = 8913
var SUPABASE_URL: String = ""
var SUPABASE_KEY: String = ""

func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	_citeste_config()
	_start_lan_listener()

func _process(delta: float) -> void:
	if public_server and is_host:
		_lobby_timer += delta
		if _lobby_timer >= LOBBY_PING_SEC:
			_lobby_timer = 0.0
			_lobby_ping()
	if _cleanup_pending:
		_cleanup_timer += delta
		if _cleanup_timer >= 20.0:
			_cleanup_pending = false
			_lobby_unregister()
	if is_host:
		_lan_broadcast(delta)
	_lan_poll()

func get_player_name() -> String:
	var pname = database.nume_jucator_logat
	return pname if pname != "" else "Player"

func host_game(port: int = PORTO_PADRAO, password: String = "", is_public: bool = false, room_name: String = "") -> void:
	if peer:
		disconnect_from_game()
	lobby_password = password
	public_server = is_public
	server_name = room_name if room_name != "" else get_player_name() + "'s Game"
	peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(port, 8)
	if err != OK:
		connection_failed.emit("Failed to create server: " + str(err))
		peer = null
		return
	multiplayer.multiplayer_peer = peer
	is_host = true
	minha_id = 1
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	server_created.emit()
	if public_server:
		_lobby_register(port)

func join_game(ip: String, port: int = PORTO_PADRAO, password: String = "") -> void:
	if peer:
		disconnect_from_game()
	lobby_password = password
	peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(ip, port)
	if err != OK:
		connection_failed.emit("Failed to connect: " + str(err))
		peer = null
		return
	multiplayer.multiplayer_peer = peer
	is_host = false
	if not multiplayer.connected_to_server.is_connected(_on_connected_ok):
		multiplayer.connected_to_server.connect(_on_connected_ok, CONNECT_ONE_SHOT)
	if not multiplayer.connection_failed.is_connected(_on_connect_fail):
		multiplayer.connection_failed.connect(_on_connect_fail, CONNECT_ONE_SHOT)

func disconnect_from_game() -> void:
	if public_server and is_host:
		_lobby_unregister()
	public_server = false
	server_id = ""
	multiplayer.multiplayer_peer = null
	if peer:
		peer.close()
		peer = null
	is_host = false
	jogadores.clear()

func _on_peer_connected(id: int) -> void:
	_cleanup_pending = false
	_cleanup_timer = 0.0
	player_joined.emit(id)

func _on_peer_disconnected(id: int) -> void:
	player_left.emit(id)
	jogadores.erase(id)
	if public_server and is_host and jogadores.is_empty():
		_cleanup_pending = true
		_cleanup_timer = 0.0

func _on_connected_ok() -> void:
	if lobby_password != "":
		rpc_id(1, "_verifica_parola", lobby_password, get_player_name())
	else:
		rpc_id(1, "_verifica_parola", "", get_player_name())

func _on_connect_fail() -> void:
	connection_failed.emit("Connection refused or timed out")

@rpc("any_peer")
func _verifica_parola(passwd: String, player_name: String) -> void:
	if not is_host:
		return
	var sender = multiplayer.get_remote_sender_id()
	if lobby_password != "" and passwd != lobby_password:
		rpc_id(sender, "_parola_respinsa")
		disconnect_peer(sender)
		return
	var wc = get_node_or_null("/root/WorldConfig")
	var seed_val = wc.world_seed if wc else 0
	rpc_id(sender, "_parola_acceptata", player_name, seed_val)

@rpc
func _parola_acceptata(_player_name: String, world_seed_val: int = 0) -> void:
	if not is_host:
		var wc = get_node_or_null("/root/WorldConfig")
		if wc:
			wc.world_seed = world_seed_val
		connection_success.emit()

@rpc
func _parola_respinsa() -> void:
	connection_failed.emit("Wrong password!")
	disconnect_from_game()

func disconnect_peer(id: int) -> void:
	if peer and is_host:
		peer.disconnect_peer(id, 0)

func _citeste_config() -> void:
	var cfg = ConfigFile.new()
	var err = cfg.load("res://config.cfg")
	if err == OK:
		SUPABASE_URL = cfg.get_value("supabase", "url", "")
		SUPABASE_KEY = cfg.get_value("supabase", "key", "")
		if SUPABASE_URL == "" or SUPABASE_KEY == "":
			public_server = false

# --- SUPABASE LOBBY ---

func _supabase_request(path: String, method: int, body: String = "", callback: Callable = Callable()) -> void:
	var http = HTTPRequest.new()
	http.request_completed.connect(_on_http_done.bind(http, callback))
	add_child(http)
	var headers = [
		"Content-Type: application/json",
		"apikey: " + SUPABASE_KEY,
		"Authorization: Bearer " + SUPABASE_KEY,
		"Prefer: return=minimal"
	]
	var url = SUPABASE_URL + "/rest/v1/" + path
	http.request(url, headers, method, body)

func _on_http_done(result: int, _code: int, _headers: Array, body: PackedByteArray, http_node: HTTPRequest, callback: Callable) -> void:
	if is_instance_valid(http_node):
		http_node.queue_free()
	if result == HTTPRequest.RESULT_SUCCESS:
		var json = JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK and json.data != null:
			if callback.is_valid():
				callback.call(json.data)
			return
	if callback.is_valid():
		callback.call([])

func _lobby_register(port: int) -> void:
	server_id = get_player_name() + "_" + str(Time.get_unix_time_from_system())
	var body = JSON.stringify({
		"id": server_id,
		"host_name": server_name,
		"ip": "0.0.0.0",
		"port": port,
		"has_password": lobby_password != "",
		"player_count": 1,
		"max_players": 8,
		"version": "1.0",
		"updated_at": Time.get_datetime_string_from_system()
	})
	_supabase_request("lobbies", HTTPClient.METHOD_POST, body)

func _lobby_ping() -> void:
	if server_id == "":
		return
	var body = JSON.stringify({
		"player_count": multiplayer.get_peers().size() + 1,
		"updated_at": Time.get_datetime_string_from_system()
	})
	_supabase_request("lobbies?id=eq." + server_id, HTTPClient.METHOD_PATCH, body)

func _lobby_unregister() -> void:
	if server_id == "":
		return
	_supabase_request("lobbies?id=eq." + server_id, HTTPClient.METHOD_DELETE)

func fetch_server_list() -> void:
	_supabase_request(
		"lobbies?order=updated_at.desc&limit=50",
		HTTPClient.METHOD_GET,
		"",
		func(data): server_list_received.emit(data if data is Array else [])
	)

# --- LAN DISCOVERY ---

func _start_lan_listener() -> void:
	_lan_send = PacketPeerUDP.new()
	_lan_send.set_broadcast_enabled(true)
	_lan_recv = PacketPeerUDP.new()
	_lan_recv.set_broadcast_enabled(true)
	var err = _lan_recv.bind(LAN_PORT, "0.0.0.0")
	if err == OK:
		_lan_recv_ok = true

func _lan_broadcast(delta: float) -> void:
	if not is_host:
		return
	_lan_timer += delta
	if _lan_timer < LAN_BROADCAST_INTERVAL:
		return
	_lan_timer = 0.0
	var data = JSON.stringify({
		"type": "lan_broadcast",
		"name": server_name,
		"port": PORTO_PADRAO,
		"has_password": lobby_password != "",
		"player_count": multiplayer.get_peers().size() + 1,
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
			if d.get("type", "") == "lan_broadcast" and d.has("name"):
				var key = sender_ip + ":" + str(d.get("port", PORTO_PADRAO))
				d["ip"] = sender_ip
				_lan_servers[key] = d
				_lan_servers[key]["updated_at"] = Time.get_unix_time_from_system()

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
			"port": _lan_servers[key].get("port", PORTO_PADRAO),
			"has_password": _lan_servers[key].get("has_password", false),
			"player_count": _lan_servers[key].get("player_count", 1),
			"max_players": _lan_servers[key].get("max_players", 8),
			"lan": true
		})
	for key in to_remove:
		_lan_servers.erase(key)
	return result
