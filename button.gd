extends Button

@onready var _NM = get_node("/root/NetworkManager")
@onready var input_username: LineEdit = get_parent().get_node("LineEdit")
@onready var input_password: LineEdit = get_parent().get_node("LineEdit2")

func _ready() -> void:
	if not _NM.auth_ok.is_connected(_on_auth_ok):
		_NM.auth_ok.connect(_on_auth_ok)
	if not _NM.auth_error.is_connected(_on_auth_error):
		_NM.auth_error.connect(_on_auth_error)
	if not _NM.connection_failed.is_connected(_on_connection_failed):
		_NM.connection_failed.connect(_on_connection_failed)
	if not self.pressed.is_connected(_on_self_pressed):
		self.pressed.connect(_on_self_pressed)

func _on_self_pressed() -> void:
	var nume = input_username.text.strip_edges()
	var parola = input_password.text.strip_edges()
	if nume == "" or parola == "":
		print("[Buton] Introdu un username și o parolă!")
		return
	self.disabled = true
	_NM.connect_and_auth(nume, parola)

func _on_auth_ok(_player_id: int, _username: String, _game_modes: Array) -> void:
	self.disabled = false
	get_tree().change_scene_to_file("res://Meniu.tscn")

func _on_connection_failed(message: String) -> void:
	self.disabled = false
	print("[Buton] Conexiune eșuată: ", message)

func _on_auth_error(message: String) -> void:
	self.disabled = false
	print("[Buton] Eroare: ", message)
