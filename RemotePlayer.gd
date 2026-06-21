extends Node3D

var player_name: String = "":
	set(v):
		player_name = v
		if name_label:
			name_label.text = v
var name_label: Label3D = null
var culoare: Color = Color(0.3, 0.6, 1.0)
var target_pos: Vector3
var target_rot_y: float

var _first_sync: bool = true
var inventar: Inventar = null
var player_config: Dictionary = {}
var arma_arbaleta: MeshInstance3D = null
var arma_sabie: MeshInstance3D = null
var arma_sapa: Node3D = null
var arma_ciocan: Node3D = null

func _ready() -> void:
	var peer_id = -1
	if name.is_valid_int():
		peer_id = name.to_int()
	if peer_id > 0 and culoare == Color(0.3, 0.6, 1.0):
		var hue = fmod(peer_id * 0.17, 1.0)
		culoare = Color.from_hsv(hue, 0.7, 0.9)
		var _GJ = get_node_or_null("/root/GestiuneJoc")
		if _GJ and _GJ.has_method("get_player_name_for_id"):
			player_name = _GJ.get_player_name_for_id(peer_id)
	inventar = Inventar.new()
	_generate_body()
	_generate_weapons()
	name_label = Label3D.new()
	name_label.text = player_name
	name_label.position.y = 2.4
	name_label.font_size = 48
	name_label.outline_size = 1
	name_label.outline_modulate = Color(0, 0, 0)
	name_label.modulate = Color(1, 1, 1)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(name_label)
	add_to_group("Jucator")
	target_pos = global_position
	target_rot_y = rotation.y
	_show_weapon(0, 0)

func _generate_body() -> void:
	var mesh = MeshInstance3D.new()
	var capsula = CapsuleMesh.new()
	capsula.radius = 0.5
	capsula.height = 2.0
	var mat = StandardMaterial3D.new()
	mat.albedo_color = culoare
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	capsula.material = mat
	mesh.mesh = capsula
	add_child(mesh)

func _make_mat(color: Color) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func _generate_weapons() -> void:
	arma_arbaleta = MeshInstance3D.new()
	var b = BoxMesh.new()
	b.size = Vector3(0.15, 0.15, 0.8)
	b.material = _make_mat(Color(0.4, 0.25, 0.15))
	arma_arbaleta.mesh = b
	arma_arbaleta.position = Vector3(0.3, 0.9, -0.6)
	add_child(arma_arbaleta)

	arma_sabie = MeshInstance3D.new()
	var s = BoxMesh.new()
	s.size = Vector3(0.06, 0.8, 0.06)
	s.material = _make_mat(Color(0.7, 0.7, 0.75))
	arma_sabie.mesh = s
	arma_sabie.position = Vector3(0.3, 1.0, -0.5)
	arma_sabie.rotation.x = deg_to_rad(-20)
	add_child(arma_sabie)

	arma_sapa = Node3D.new()
	var mana = MeshInstance3D.new()
	var mm = BoxMesh.new()
	mm.size = Vector3(0.05, 0.35, 0.05)
	mm.material = _make_mat(Color(0.5, 0.3, 0.15))
	mana.mesh = mm
	mana.position = Vector3(0, 0, 0)
	arma_sapa.add_child(mana)
	var cap = MeshInstance3D.new()
	var cm = BoxMesh.new()
	cm.size = Vector3(0.25, 0.08, 0.18)
	cm.material = _make_mat(Color(0.5, 0.5, 0.5))
	cap.mesh = cm
	cap.position = Vector3(0, 0.2, 0)
	arma_sapa.add_child(cap)
	arma_sapa.position = Vector3(0.25, 0.95, -0.55)
	arma_sapa.rotation.x = deg_to_rad(-30)
	add_child(arma_sapa)

	arma_ciocan = Node3D.new()
	var mana2 = MeshInstance3D.new()
	var mm2 = BoxMesh.new()
	mm2.size = Vector3(0.05, 0.3, 0.05)
	mm2.material = _make_mat(Color(0.5, 0.3, 0.15))
	mana2.mesh = mm2
	mana2.position = Vector3(0, 0, 0)
	arma_ciocan.add_child(mana2)
	var cap2 = MeshInstance3D.new()
	var cm2 = BoxMesh.new()
	cm2.size = Vector3(0.2, 0.12, 0.3)
	cm2.material = _make_mat(Color(0.35, 0.35, 0.38))
	cap2.mesh = cm2
	cap2.position = Vector3(0, 0.2, 0)
	arma_ciocan.add_child(cap2)
	arma_ciocan.position = Vector3(0.25, 0.95, -0.55)
	arma_ciocan.rotation.x = deg_to_rad(-30)
	add_child(arma_ciocan)

func _show_weapon(mod: int, arma: int) -> void:
	var lupta = mod == 2
	var sapa = mod == 0
	var construieste = mod == 1
	var arbaleta = lupta and arma == 0
	var sabie = lupta and arma == 1
	if is_instance_valid(arma_arbaleta): arma_arbaleta.visible = arbaleta
	if is_instance_valid(arma_sabie): arma_sabie.visible = sabie
	if is_instance_valid(arma_sapa): arma_sapa.visible = sapa
	if is_instance_valid(arma_ciocan): arma_ciocan.visible = construieste

func set_weapon_state(mod: int, arma: int) -> void:
	_show_weapon(mod, arma)

func _process(delta: float) -> void:
	if _first_sync:
		return
	global_position = target_pos
	rotation.y = lerpf(rotation.y, target_rot_y, min(1.0, delta * 25.0))

func set_target_position(pos: Vector3, rot_y: float) -> void:
	if _first_sync:
		_first_sync = false
	target_pos = pos
	target_rot_y = rot_y
	global_position = pos

func apply_config(config: Dictionary) -> void:
	player_config = config
	if config.has("model_path"):
		var model_path: String = config["model_path"]
		print("RemotePlayer: would load model from ", model_path)
