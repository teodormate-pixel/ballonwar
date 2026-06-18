extends Control

@onready var status_label: Label = $StatusLabel
@onready var ip_input: LineEdit = $LeftPanel/IPInput
@onready var password_input: LineEdit = $LeftPanel/PasswordInput
@onready var host_btn: Button = $LeftPanel/HostBtn
@onready var join_btn: Button = $LeftPanel/JoinBtn
@onready var back_btn: Button = $LeftPanel/BackBtn
@onready var public_check: CheckBox = $LeftPanel/PublicCheck
@onready var server_list: ItemList = $RightPanel/ServerList
var _selected_ip: String = ""
@onready var refresh_btn: Button = $RightPanel/RefreshBtn
@onready var master_url_input: LineEdit = $RightPanel/MasterURLInput
var _ultimele_public: Array = []
@onready var _NM = get_node("/root/NetworkManager")
@onready var _WC = get_node("/root/WorldConfig")

func _ready() -> void:
	_NM.server_created.connect(_on_server_created)
	_NM.connection_success.connect(_on_connection_success)
	_NM.connection_failed.connect(_on_connection_failed)
	_NM.server_list_received.connect(_on_server_list)
	host_btn.pressed.connect(_on_host)
	join_btn.pressed.connect(_on_join)
	back_btn.pressed.connect(_on_back)
	refresh_btn.pressed.connect(_on_refresh)
	server_list.item_activated.connect(_on_server_selected)
	var lan_timer = Timer.new()
	lan_timer.timeout.connect(_lan_refresh)
	lan_timer.wait_time = 3.0
	lan_timer.autostart = true
	add_child(lan_timer)

func _lan_refresh() -> void:
	if _NM.get_lan_servers().size() > 0 or _ultimele_public.size() == 0:
		_reload_list(_ultimele_public)

func _on_host() -> void:
	var passwd = password_input.text.strip_edges()
	var is_public = public_check.button_pressed
	var room_name = ip_input.text.strip_edges()
	if room_name.is_empty():
		room_name = _NM.get_player_name() + "'s Game"
	if room_name.length() > 30:
		room_name = room_name.substr(0, 30)
	status_label.text = "Creating server..."
	_NM.host_game(_NM.PORTO_PADRAO, passwd, is_public, room_name)

func _on_join() -> void:
	var ip = _selected_ip if _selected_ip != "" else ip_input.text.strip_edges()
	if ip.is_empty():
		status_label.text = "Enter an IP address!"
		return
	if not "." in ip:
		ip = "127.0.0.1"
	var passwd = password_input.text.strip_edges()
	_NM.join_game(ip, _NM.PORTO_PADRAO, passwd)

func _on_back() -> void:
	_NM.disconnect_from_game()
	get_tree().change_scene_to_file("res://Meniu.tscn")

func _on_server_created() -> void:
	status_label.text = "Server created!"
	_WC.world_seed = randi()
	get_tree().change_scene_to_file("res://lume.tscn")

func _on_connection_success() -> void:
	status_label.text = "Connected! Loading world..."
	get_tree().change_scene_to_file("res://lume.tscn")

func _on_connection_failed(msg: String) -> void:
	status_label.text = "Failed: " + msg

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
			var lock = " [LOCK]" if s.get("has_password", false) else ""
			var label = "[LAN]" + lock + " " + s.get("host_name", "Unnamed") + "  (" + str(s.get("player_count", 1)) + "/" + str(s.get("max_players", 8)) + ")"
			server_list.add_item(label)
			var idx = server_list.get_item_count() - 1
			server_list.set_item_metadata(idx, {"ip": s.get("ip", "0.0.0.0"), "port": s.get("port", _NM.PORTO_PADRAO)})
	if has_public:
		server_list.add_item("--- PUBLIC ---")
		server_list.set_item_metadata(server_list.get_item_count() - 1, {"separator": true})
		for s in servers:
			var lock = " [LOCK]" if s.get("has_password", false) else ""
			var label = s.get("host_name", s.get("name", "Unnamed")) + lock + "  (" + str(s.get("player_count", 0)) + "/" + str(s.get("max_players", 8)) + ")"
			server_list.add_item(label)
			var idx = server_list.get_item_count() - 1
			server_list.set_item_metadata(idx, {"ip": s.get("ip", "0.0.0.0"), "port": s.get("port", _NM.PORTO_PADRAO)})
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

func _on_server_list(servers: Array) -> void:
	_ultimele_public = servers
	_reload_list(servers)

func _on_server_selected(index: int) -> void:
	var meta = server_list.get_item_metadata(index)
	if meta is Dictionary and meta.has("separator"):
		return
	if meta is Dictionary and meta.has("ip"):
		_selected_ip = meta["ip"]
		var name = server_list.get_item_text(index)
		status_label.text = "Selected \"" + name + "\". Click Join or double-click again."

func _on_http_done(_result: int, _code: int, _headers: Array, _body: PackedByteArray) -> void:
	pass
