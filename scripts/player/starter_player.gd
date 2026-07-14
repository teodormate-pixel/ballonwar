extends CharacterBody3D
class_name StarterPlayer
@onready var _NM = get_node("/root/NetworkManager")
@onready var _GJ = get_node("/root/GestiuneJoc")
const TEREN_SCRIPT_PATH: String = "res://scripts/legacy/teren_proceduaral.gd"
const TEREN_SCRIPT_PATH_ALT: String = "res://scripts/legacy/voxel_terrain_manager.gd"
const SPAWN_HEIGHT_OFFSET: float = 25.0
# Inventar is resolved via class_name Inventar in inventar.gd
const BlockScenaScene = preload("res://scenes/entities/BlockScena.tscn")

enum BlockType { AIR, GRASS, DIRT, STONE, COAL, IRON, COPPER, GOLD, DIAMOND, WOOD, LEAF }

const VITEZA: float = 7.0
const FORTA_SARITURA: float = 5.5
const WATER_LEVEL: float = 10.0
const WORLD_BOTTOM: float = -80.0
const VITEZA_INOT: float = 5.0
var gravitate: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var in_apa: bool = false

const SENSIBILITATE_MOUSE = 0.002
var spawnat_corect: bool = false

enum ModCamera { FIRST_PERSON, THIRD_PERSON, FREECAM }
var mod_curent: ModCamera = ModCamera.FIRST_PERSON

enum ModArma { ARBALETA, SABIE }
enum DigMode { CUBE, SPHERE }
enum ModInteractiune { SAPA, CONSTRUIESTE, COMBAT }
var dig_mode: DigMode = DigMode.CUBE
var mod_interactiune: ModInteractiune = ModInteractiune.SAPA
var arma_curenta: ModArma = ModArma.ARBALETA

var shift_lock_activ: bool = false

var distanta_camera_curenta: float = 3.5
const ZOOM_MIN: float = 0.5      
const ZOOM_MAX: float = 12.0     
const VITEZA_ZOOM: float = 0.5   

const FOV_NORMAL: float = 75.0   
var fov_curent: float = 75.0
const FOV_MIN_ZOOM: float = 20.0 
const VITEZA_FOV_ZOOM: float = 5.0

const VITEZA_FREECAM: float = 15.0
var pozitie_salvata_camera: Vector3 = Vector3.ZERO

const OFFSET_UMAR_SHIFT_LOCK: Vector3 = Vector3(0.6, 0.2, 0.0) 

var rotatie_camera_x: float = 0.0
var rotatie_camera_y: float = 0.0

# --- ATRIBUTE COMBAT ADĂUGATE ---
var viata_jucator: float = 100.0
var baloane_sparte: int = 0
var distanta_atac_sabie: float = 3.5
var damage_sabie: int = 50
var label_debug: Label = null
var scor_curent: int = 0


@export_group("Sloturi Modele Viitoare")
@export var model_jucator_viitor: Node3D = null     # Trage corpul .glb aici
@export var model_arc_viitor: Node3D = null         # Trage arcul .glb aici
@export var model_sabie_viitor: Node3D = null       # Trage sabia .glb aici
@export var model_sapa_viitor: Node3D = null        # Trage sapa .glb aici
@export var model_ciocan_viitor: Node3D = null      # Trage ciocanul .glb aici

@export_group("Proiectile si Viteze")
@export var model_glont: PackedScene
@export var VITEZA_GLONT: float = 25.0
var lista_gloante_active: Array = []

var inventar: Inventar = null
var teren_procedural: Node = null
var _terrain_manager: VoxelLodTerrain = null
var _frozen_spawn: bool = false
var _material_cache: Dictionary = {}
@onready var _camera: Camera3D = get_node_or_null("Cap/SpringArm3D/Camera3D")
@onready var _cap_node: Node3D = get_node_or_null("Cap")
var arma_arbaleta_generata: MeshInstance3D = null
var arma_sabie_generata: MeshInstance3D = null
var arma_sapa_generata: Node3D = null
var arma_ciocan_generata: Node3D = null
var blocuri_placute: Dictionary = {}
var blueprints_disponibile: Array = []
var blueprint_selectat: int = -1
var label_structura: Label = null
var este_jucator_local: bool = false
var _sync_timer: float = 0.0
var mort: bool = false
var spectate_btn: Button = null
var spectate_targets: Array = []
var spectate_idx: int = -1
var _game_over_panel: Panel = null
var _score_saved_label: Label = null

func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	global_position.y = 150.0
	if has_node("/root/MusicManager"):
		get_node("/root/MusicManager").start_music()
	get_tree().paused = false
	if not DisplayServer.get_name() == "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	floor_snap_length = 0.2
	floor_max_angle = deg_to_rad(89)
	self.collision_layer = 1
	self.collision_mask = 1
	
	var col_shape: CollisionShape3D = get_node_or_null("CollisionShape") as CollisionShape3D
	if col_shape == null:
		col_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col_shape:
		col_shape.transform = Transform3D.IDENTITY
		var noua_capsula: CapsuleShape3D = CapsuleShape3D.new()
		noua_capsula.radius = 0.5
		noua_capsula.height = 2.0
		col_shape.shape = noua_capsula

	if has_node("Cap"):
		$Cap.transform = Transform3D.IDENTITY
		$Cap.position.y = 1.5
	if has_node("Cap/SpringArm3D/Camera3D"):
		$Cap/SpringArm3D/Camera3D.transform = Transform3D.IDENTITY
		$Cap/SpringArm3D/Camera3D.near = 0.3
		$Cap/SpringArm3D/Camera3D.far = 200.0
		$Cap/SpringArm3D/Camera3D.fov = FOV_NORMAL
		
		
	# FABRICARE AUTOMATĂ CORP VIZIBIL ÎN LIPSA MODELULUI .GLB
	if model_jucator_viitor == null:
		var corp_mesh = MeshInstance3D.new()
		var capsula_geometrie = CapsuleMesh.new()
		capsula_geometrie.radius = 0.5
		capsula_geometrie.height = 2.0
		var mat_corp = StandardMaterial3D.new()
		mat_corp.albedo_color = Color(0.2, 0.4, 0.8)
		mat_corp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		capsula_geometrie.material = mat_corp
		corp_mesh.mesh = capsula_geometrie
		add_child(corp_mesh)
		
	# Creare HUD Label text
	label_debug = Label.new()
	label_debug.position = Vector2(20, 20)
	label_debug.add_theme_color_override("font_color", Color(0, 1, 0))
	var interfata = get_node_or_null("Interfata") as Control
	if interfata:
		interfata.add_child(label_debug)
		inventar = Inventar.new()
		interfata.add_child(inventar)
		label_structura = Label.new()
		label_structura.position = Vector2(20, 50)
		label_structura.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
		label_structura.add_theme_font_size_override("font_size", 16)
		label_structura.visible = false
		interfata.add_child(label_structura)
		var leave_btn = interfata.get_node_or_null("LeaveBtn")
		if leave_btn:
			leave_btn.pressed.connect(_leave_game)
		spectate_btn = Button.new()
		spectate_btn.text = "Spectate"
		spectate_btn.position = Vector2(16, 64)
		spectate_btn.size = Vector2(100, 32)
		spectate_btn.visible = false
		spectate_btn.pressed.connect(_on_spectate)
		interfata.add_child(spectate_btn)
		if _NM and not _NM.save_data_result.is_connected(_on_save_game_score_result):
			_NM.save_data_result.connect(_on_save_game_score_result)

	_incarca_blueprints()
	_genereaza_arme_automate_cod()
	_actualizeaza_pozitie_camera()
	_actualizeaza_vizual_arme()
	_actualizeaza_text_debug()
	add_to_group("Jucator")
	_locate_terrain_node()
	if _try_spawn_above_terrain():
		spawnat_corect = true
	este_jucator_local = true
	if _NM.room_id != "":
		send_player_config()

var player_config: Dictionary = {}

func send_player_config() -> void:
	pass

func _incarca_blueprints() -> void:
	blueprints_disponibile.clear()
	var dir = DirAccess.open("res://resources/blueprints")
	if dir:
		dir.list_dir_begin()
		var f = dir.get_next()
		while f != "":
			if f.ends_with(".json"):
				var bp = StructureData.load_from_file("res://blueprints/" + f)
				if bp:
					blueprints_disponibile.append(bp)
			f = dir.get_next()
		dir.list_dir_end()


func _genereaza_arme_automate_cod() -> void:
	var nod_cap = get_node_or_null("Cap")
	if not nod_cap: return
	
	if model_arc_viitor == null:
		arma_arbaleta_generata = MeshInstance3D.new()
		var mesh_arbaleta = BoxMesh.new()
		mesh_arbaleta.size = Vector3(0.15, 0.15, 0.8)
		arma_arbaleta_generata.mesh = mesh_arbaleta
		var mat_arbaleta = StandardMaterial3D.new()
		mat_arbaleta.albedo_color = Color(0.4, 0.25, 0.15)
		mat_arbaleta.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		arma_arbaleta_generata.material_override = mat_arbaleta
		nod_cap.add_child(arma_arbaleta_generata)
		arma_arbaleta_generata.position = Vector3(0.3, -0.3, -0.6)

	if model_sabie_viitor == null:
		arma_sabie_generata = MeshInstance3D.new()
		var mesh_sabie = BoxMesh.new()
		mesh_sabie.size = Vector3(0.06, 0.8, 0.06)
		arma_sabie_generata.mesh = mesh_sabie
		var mat_sabie = StandardMaterial3D.new()
		mat_sabie.albedo_color = Color(0.7, 0.7, 0.75)
		mat_sabie.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		arma_sabie_generata.material_override = mat_sabie
		nod_cap.add_child(arma_sabie_generata)
		arma_sabie_generata.position = Vector3(0.3, -0.2, -0.5)
		arma_sabie_generata.rotation.x = deg_to_rad(-20)

	if model_sapa_viitor == null:
		arma_sapa_generata = Node3D.new()
		var mana = MeshInstance3D.new()
		var mesh_mana = BoxMesh.new()
		mesh_mana.size = Vector3(0.05, 0.35, 0.05)
		mana.mesh = mesh_mana
		var mat_mana = StandardMaterial3D.new()
		mat_mana.albedo_color = Color(0.5, 0.3, 0.15)
		mat_mana.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		mana.material_override = mat_mana
		mana.position = Vector3(0, 0, 0)
		arma_sapa_generata.add_child(mana)
		var cap = MeshInstance3D.new()
		var mesh_cap = BoxMesh.new()
		mesh_cap.size = Vector3(0.25, 0.08, 0.18)
		cap.mesh = mesh_cap
		var mat_cap = StandardMaterial3D.new()
		mat_cap.albedo_color = Color(0.5, 0.5, 0.5)
		mat_cap.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		cap.material_override = mat_cap
		cap.position = Vector3(0, 0.2, 0)
		arma_sapa_generata.add_child(cap)
		nod_cap.add_child(arma_sapa_generata)
		arma_sapa_generata.position = Vector3(0.25, -0.25, -0.55)
		arma_sapa_generata.rotation.x = deg_to_rad(-30)
	else:
		arma_sapa_generata = model_sapa_viitor

	if model_ciocan_viitor == null:
		arma_ciocan_generata = Node3D.new()
		var mana2 = MeshInstance3D.new()
		var mesh_mana2 = BoxMesh.new()
		mesh_mana2.size = Vector3(0.05, 0.3, 0.05)
		mana2.mesh = mesh_mana2
		var mat_mana2 = StandardMaterial3D.new()
		mat_mana2.albedo_color = Color(0.5, 0.3, 0.15)
		mat_mana2.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		mana2.material_override = mat_mana2
		mana2.position = Vector3(0, 0, 0)
		arma_ciocan_generata.add_child(mana2)
		var cap2 = MeshInstance3D.new()
		var mesh_cap2 = BoxMesh.new()
		mesh_cap2.size = Vector3(0.2, 0.12, 0.3)
		cap2.mesh = mesh_cap2
		var mat_cap2 = StandardMaterial3D.new()
		mat_cap2.albedo_color = Color(0.35, 0.35, 0.38)
		mat_cap2.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		cap2.material_override = mat_cap2
		cap2.position = Vector3(0, 0.2, 0)
		arma_ciocan_generata.add_child(cap2)
		nod_cap.add_child(arma_ciocan_generata)
		arma_ciocan_generata.position = Vector3(0.25, -0.25, -0.55)
		arma_ciocan_generata.rotation.x = deg_to_rad(-30)
	else:
		arma_ciocan_generata = model_ciocan_viitor

func _unhandled_input(event: InputEvent) -> void:
	if mort and event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_cycle_spectate_target()
		return
	# Ciclu rapid pentru modul principal: sapă -> construiește -> combat
	if event is InputEventKey and event.pressed and event.keycode == KEY_V:
		mod_interactiune = _urmatorul_mod_interactiune(mod_interactiune)
		_actualizeaza_vizual_arme()
		_actualizeaza_text_debug()
		return

	# DIG mode (KEY_M) and BUILD mode (KEY_Z) shortcuts
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_M:
			mod_interactiune = ModInteractiune.SAPA
			_actualizeaza_vizual_arme()
			_actualizeaza_text_debug()
			_incearca_sapa_bloc()
			return
		elif event.keycode == KEY_Z:
			mod_interactiune = ModInteractiune.CONSTRUIESTE
			_actualizeaza_vizual_arme()
			_actualizeaza_text_debug()
			_incearca_construi_bloc()
			return
		elif event.keycode == KEY_B:
			dig_mode = DigMode.SPHERE if dig_mode == DigMode.CUBE else DigMode.CUBE
			_actualizeaza_text_debug()
			return
		elif event.keycode == KEY_X:
			mod_interactiune = ModInteractiune.COMBAT
			_actualizeaza_vizual_arme()
			_actualizeaza_text_debug()
			return
		elif event.keycode == KEY_T:
			if mod_interactiune == ModInteractiune.CONSTRUIESTE:
				if blueprints_disponibile.is_empty():
					_incarca_blueprints()
				if blueprints_disponibile.size() > 0:
					if blueprint_selectat < blueprints_disponibile.size() - 1:
						blueprint_selectat += 1
					else:
						blueprint_selectat = -1
					_actualizeaza_label_structura()
			return
	
	# INVENTORY (TASTA I)
	if event is InputEventKey and event.pressed and event.keycode == KEY_I:
		if inventar:
			inventar.toggle_inventory()
		return

	# SCHIMBARE SELECȚIE INVENTAR (TASTELE 1-7)
	if event is InputEventKey and event.pressed:
		var selection_index: int = _keycode_to_inventory_index(event.keycode)
		if selection_index >= 0 and inventar:
			inventar.select_block_index(selection_index)
			return
	# SCHIMBARE ARMA AUTOMATĂ (TASTA Q)
	if event is InputEventKey and event.pressed and event.keycode == KEY_Q:
		arma_curenta = ModArma.SABIE if arma_curenta == ModArma.ARBALETA else ModArma.ARBALETA
		_actualizeaza_vizual_arme()
		return

	# SĂPARE / ATAC (CLICK STÂNGA)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if mod_curent != ModCamera.FREECAM:
			if not _inventar_deschis():
				if mod_interactiune == ModInteractiune.SAPA and _incearca_sapa_bloc():
					return
				if mod_interactiune == ModInteractiune.CONSTRUIESTE and _incearca_construi_bloc():
					return
				if mod_interactiune == ModInteractiune.COMBAT:
					if arma_curenta == ModArma.ARBALETA:
						_trage_proiectil()
					else:
						_ataca_sabie()
			return

	if event is InputEventKey and event.pressed and event.keycode == KEY_C and mod_curent != ModCamera.FREECAM:
		if mod_curent == ModCamera.FIRST_PERSON:
			mod_curent = ModCamera.THIRD_PERSON
			distanta_camera_curenta = 3.5 
			rotatie_camera_y = rotation.y
			fov_curent = FOV_NORMAL
		else:
			mod_curent = ModCamera.FIRST_PERSON
			shift_lock_activ = false 
			rotatie_camera_x = 0.0
			rotation.y = rotatie_camera_y
			$Cap.rotation.x = 0
			$Cap.rotation.y = 0
			fov_curent = FOV_NORMAL
		_actualizeaza_pozitie_camera()
		_actualizeaza_mod_mouse()

	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		if mod_curent != ModCamera.FREECAM:
			mod_curent = ModCamera.FREECAM
			shift_lock_activ = false
			fov_curent = FOV_NORMAL
			if has_node("Cap/SpringArm3D/Camera3D"):
				pozitie_salvata_camera = $Cap/SpringArm3D/Camera3D.global_position
			rotatie_camera_y = rotation.y
		else:
			mod_curent = ModCamera.FIRST_PERSON
			rotatie_camera_x = 0.0
			rotation.y = rotatie_camera_y
			$Cap.rotation.x = 0
			$Cap.rotation.y = 0
		_actualizeaza_pozitie_camera()
		_actualizeaza_mod_mouse()

	if event is InputEventKey and event.pressed and event.keycode == KEY_SHIFT and mod_curent == ModCamera.THIRD_PERSON:
		shift_lock_activ = not shift_lock_activ
		if shift_lock_activ:
			rotation.y = rotatie_camera_y
			$Cap.rotation.y = 0
		_actualizeaza_pozitie_camera()
		_actualizeaza_mod_mouse()

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if mod_curent == ModCamera.FIRST_PERSON and not _inventar_deschis():
			if mod_interactiune != ModInteractiune.COMBAT:
				if blueprint_selectat >= 0 and blueprint_selectat < blueprints_disponibile.size():
					_incearca_plaseaza_structura()
				else:
					_incearca_construi_bloc()
				return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if mod_curent == ModCamera.THIRD_PERSON:
				distanta_camera_curenta -= VITEZA_ZOOM
				if distanta_camera_curenta <= ZOOM_MIN:
					mod_curent = ModCamera.FIRST_PERSON
					shift_lock_activ = false
					rotatie_camera_x = 0.0
					rotation.y = rotatie_camera_y
					$Cap.rotation.x = 0
					$Cap.rotation.y = 0
					fov_curent = FOV_NORMAL
			elif mod_curent == ModCamera.FIRST_PERSON:
				fov_curent -= VITEZA_FOV_ZOOM
				fov_curent = clamp(fov_curent, FOV_MIN_ZOOM, FOV_NORMAL)
			_actualizeaza_pozitie_camera()
			_actualizeaza_mod_mouse()
				
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mod_curent == ModCamera.FIRST_PERSON:
				if fov_curent < FOV_NORMAL:
					fov_curent += VITEZA_FOV_ZOOM
					fov_curent = clamp(fov_curent, FOV_MIN_ZOOM, FOV_NORMAL)
				else:
					mod_curent = ModCamera.THIRD_PERSON
					rotatie_camera_y = rotation.y
					distanta_camera_curenta = ZOOM_MIN + VITEZA_ZOOM
			else:
				distanta_camera_curenta += VITEZA_ZOOM
				distanta_camera_curenta = clamp(distanta_camera_curenta, ZOOM_MIN, ZOOM_MAX)
			_actualizeaza_pozitie_camera()
			_actualizeaza_mod_mouse()

		elif event.button_index == MOUSE_BUTTON_RIGHT and mod_curent == ModCamera.THIRD_PERSON and not shift_lock_activ:
			_actualizeaza_mod_mouse()

	if event is InputEventMouseMotion:
		var se_poate_roti = (mod_curent == ModCamera.FIRST_PERSON) or shift_lock_activ or (mod_curent == ModCamera.FREECAM) or (mod_curent == ModCamera.THIRD_PERSON and (shift_lock_activ or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED))
		if se_poate_roti and has_node("Cap"):
			rotatie_camera_y -= event.relative.x * SENSIBILITATE_MOUSE
			rotatie_camera_x -= event.relative.y * SENSIBILITATE_MOUSE
			rotatie_camera_x = clamp(rotatie_camera_x, deg_to_rad(-89), deg_to_rad(89))
func _inventar_deschis() -> bool:
	return inventar and inventar.inventory_open

func _obtine_camera_activa() -> Camera3D:
	if not has_node("Cap/SpringArm3D/Camera3D"):
		return null
	return $Cap/SpringArm3D/Camera3D as Camera3D

func _incearca_sapa_bloc() -> bool:
	if inventar == null:
		return false
	var cam_node: Camera3D = _obtine_camera_activa()
	if cam_node == null or teren_procedural == null or inventar == null:
		return false
	var directie: Vector3 = (-cam_node.global_transform.basis.z).normalized()
	var from = cam_node.global_position
	var to = from + directie * 10.0

	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space.intersect_ray(query)

	if not result.is_empty():
		var collider = result.collider
		if collider is BlockScena:
			var key = str(collider.position)
			var este_plasat_jucator = key in blocuri_placute
			blocuri_placute.erase(key)
			if not este_plasat_jucator and teren_procedural:
				teren_procedural.marcheaza_bloc_sters(collider.position)
			var bt = collider.block_type
			collider.queue_free()
			inventar.add_block(bt)
			_reda_sunet("res://addons/ziva_agent/audio/knock.wav", cam_node.global_position)
			return true

		if collider.is_in_group("Digable"):
			collider.queue_free()
			_reda_sunet("res://addons/ziva_agent/audio/knock.wav", cam_node.global_position)
			return true

		var parinte_diggable = _gaseste_diggable(collider)
		if parinte_diggable:
			parinte_diggable.queue_free()
			_reda_sunet("res://addons/ziva_agent/audio/knock.wav", cam_node.global_position)
			return true

	var bloc: int = BlockType.AIR
	if dig_mode == DigMode.CUBE:
		bloc = teren_procedural.sapa_bloc(cam_node.global_position, directie)
		if bloc != BlockType.AIR:
			inventar.add_block(bloc)
			_reda_sunet("res://addons/ziva_agent/audio/knock.wav", cam_node.global_position)
			return true
	else:
		var removed_blocks: Array = teren_procedural.sapa_sfera(cam_node.global_position, directie)
		if removed_blocks.size() > 0:
			for btype in removed_blocks:
				inventar.add_block(btype if btype != 0 else BlockType.STONE)
			_reda_sunet("res://addons/ziva_agent/audio/knock.wav", cam_node.global_position)
			return true
	return false

func _gaseste_diggable(node: Node) -> Node:
	var current: Node = node
	while current:
		if current.is_in_group("Digable"):
			return current
		current = current.get_parent()
	return null

func _incearca_construi_bloc() -> bool:
	if inventar == null:
		return false
	var cam_node: Camera3D = _obtine_camera_activa()
	if cam_node == null or teren_procedural == null or inventar == null:
		return false
	var selected_block: int = inventar.get_selected_block_type()
	if not inventar.try_use_selected_block():
		return false
	var directie: Vector3 = (-cam_node.global_transform.basis.z).normalized()

	var from = cam_node.global_position
	var to = from + directie * 10.0

	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space.intersect_ray(query)

	if result.is_empty():
		inventar.add_block(selected_block)
		return false

	var place_pos = result.position + result.normal * 0.5
	place_pos = Vector3(
		floor(place_pos.x) + 0.5,
		floor(place_pos.y) + 0.5,
		floor(place_pos.z) + 0.5
	)

	var key = str(place_pos)
	if key in blocuri_placute:
		inventar.add_block(selected_block)
		return false

	var block = BlockScenaScene.instantiate()
	block.block_type = selected_block
	block.position = place_pos
	block.add_to_group("Digable")

	var mesh = block.get_node("Mesh") as MeshInstance3D
	if mesh:
		mesh.material_override = _get_block_material(selected_block)

	get_parent().add_child(block)
	blocuri_placute[key] = block
	if _NM.room_id != "":
		_NM.send_terrain_modify([place_pos.x, place_pos.y, place_pos.z], "place", selected_block)
	_reda_sunet("res://addons/ziva_agent/audio/knock.wav", cam_node.global_position)
	return true

func _actualizeaza_label_structura() -> void:
	if label_structura == null:
		return
	if blueprint_selectat >= 0 and blueprint_selectat < blueprints_disponibile.size():
		var bp = blueprints_disponibile[blueprint_selectat]
		label_structura.text = "STRUCTURA: " + bp.structure_name + " (" + str(bp.blocks.size()) + " blocuri)"
		label_structura.visible = true
	else:
		label_structura.visible = false

func _incearca_plaseaza_structura() -> void:
	if blueprint_selectat < 0 or blueprint_selectat >= blueprints_disponibile.size():
		return
	if inventar == null or teren_procedural == null:
		return
	var bp = blueprints_disponibile[blueprint_selectat]
	var cam_node: Camera3D = _obtine_camera_activa()
	if cam_node == null:
		return
	var directie: Vector3 = (-cam_node.global_transform.basis.z).normalized()
	var from = cam_node.global_position
	var to = from + directie * 12.0
	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space.intersect_ray(query)
	if result.is_empty():
		return
	var base_pos = Vector3(
		floor(result.position.x + result.normal.x * 0.5) + 0.5,
		floor(result.position.y + result.normal.y * 0.5) + 0.5,
		floor(result.position.z + result.normal.z * 0.5) + 0.5
	)
	var blocuri_necesare = {}
	for bd in bp.blocks:
		var bt = bd.type
		if bt > 0:
			blocuri_necesare[bt] = blocuri_necesare.get(bt, 0) + 1
	var avail = true
	for bt in blocuri_necesare:
		if not inventar.has_blocks(bt, blocuri_necesare[bt]):
			avail = false
			break
	if not avail:
		if label_structura:
			label_structura.text = "NU AI BLOCURI SUFICIENTE!"
			label_structura.modulate = Color(1, 0.3, 0.3)
			await get_tree().create_timer(1.5).timeout
			if label_structura:
				label_structura.modulate = Color(1, 1, 1)
				_actualizeaza_label_structura()
		return
	for bt in blocuri_necesare:
		for _i in range(blocuri_necesare[bt]):
			inventar.try_use_block_type(bt)
	for bd in bp.blocks:
		if bd.type <= 0:
			continue
		var pos = base_pos + Vector3(bd.x, bd.y, bd.z)
		var key = str(pos)
		if key in blocuri_placute:
			continue
		var block = BlockScenaScene.instantiate()
		block.block_type = bd.type
		block.position = pos
		block.add_to_group("Digable")
		var mesh = block.get_node("Mesh") as MeshInstance3D
		if mesh:
			mesh.material_override = _get_block_material(bd.type)
		get_parent().add_child(block)
		blocuri_placute[key] = block
		if _NM.room_id != "":
			_NM.send_terrain_modify([pos.x, pos.y, pos.z], "place", bd.type)

func _keycode_to_inventory_index(keycode: int) -> int:
	match keycode:
		KEY_1: return 0
		KEY_2: return 1
		KEY_3: return 2
		KEY_4: return 3
		KEY_5: return 4
		KEY_6: return 5
		KEY_7: return 6
	return -1

func _urmatorul_mod_interactiune(curent: ModInteractiune) -> ModInteractiune:
	match curent:
		ModInteractiune.SAPA:
			return ModInteractiune.CONSTRUIESTE
		ModInteractiune.CONSTRUIESTE:
			return ModInteractiune.COMBAT
		ModInteractiune.COMBAT:
			return ModInteractiune.SAPA
	return ModInteractiune.SAPA


func _actualizeaza_text_debug() -> void:
	if label_debug == null:
		return
	var arma_text = "SABIE ⚔️" if arma_curenta == ModArma.SABIE else "ARBALETA 🏹"
	var dig_label = "Cube" if dig_mode == DigMode.CUBE else "Sphere"
	var mod_text = "SAPA" if mod_interactiune == ModInteractiune.SAPA else "CONSTRUIESTE" if mod_interactiune == ModInteractiune.CONSTRUIESTE else "COMBAT"
	var apa_text = " | 🌊 APA" if in_apa else ""
	label_debug.text = "HP: %d | SCOR: %d | ARMA: %s | DIG: %s | MOD: %s%s" % [
		viata_jucator, baloane_sparte,
		arma_text,
		dig_label,
		mod_text,
		apa_text
	]

func _get_block_material(block_type: int) -> StandardMaterial3D:
	if _material_cache.has(block_type):
		return _material_cache[block_type]
	var mat = StandardMaterial3D.new()
	mat.albedo_color = _culoare_bloc(block_type)
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	_material_cache[block_type] = mat
	return mat

func _culoare_bloc(block_type: int) -> Color:
	match block_type:
		BlockType.GRASS: return Color(0.28, 0.70, 0.24)
		BlockType.DIRT: return Color(0.58, 0.40, 0.24)
		BlockType.STONE: return Color(0.52, 0.52, 0.52)
		BlockType.COAL: return Color(0.15, 0.15, 0.15)
		BlockType.IRON: return Color(0.70, 0.55, 0.35)
		BlockType.COPPER: return Color(0.85, 0.50, 0.25)
		BlockType.GOLD: return Color(0.85, 0.72, 0.15)
		BlockType.DIAMOND: return Color(0.20, 0.60, 0.80)
		BlockType.WOOD: return Color(0.50, 0.30, 0.15)
		BlockType.LEAF: return Color(0.15, 0.55, 0.15)
	return Color(0.8, 0.8, 0.8)

func _physics_process(delta: float) -> void:
	if label_debug:
		_actualizeaza_text_debug()

	if _NM.room_id != "" and este_jucator_local and not mort:
		_sync_timer += delta
		if _sync_timer >= 0.05:
			_sync_timer = 0.0
			var keys = {
				"forward": Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP),
				"back": Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN),
				"left": Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT),
				"right": Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT),
			}
			var actions = {
				"jump": Input.is_action_just_pressed("ui_accept") or Input.is_key_pressed(KEY_SPACE),
				"fire": Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),
				"interact": Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT),
				"weapon": 0 if arma_curenta == ModArma.ARBALETA else 1,
			}
			_NM.send_input(keys, rotatie_camera_x, actions, global_position.x, global_position.y, global_position.z)

	# INITIALIZE SPAWN ABOVE THE TERRAIN (with freeze-gate for SDF terrain)
	if not spawnat_corect:
		_locate_terrain_node()
		if teren_procedural == null or not _try_spawn_above_terrain():
			velocity = Vector3.ZERO
			return

	if _camera:
		_camera.fov = fov_curent if mod_curent == ModCamera.FIRST_PERSON else FOV_NORMAL

	if mort and spectate_idx >= 0 and spectate_idx < spectate_targets.size():
		_spectate_follow(delta)
		return

	if mod_curent == ModCamera.FREECAM:
		velocity = Vector3.ZERO
		var f_dir = Vector3.ZERO
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): f_dir.z -= 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): f_dir.z += 1.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): f_dir.x -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): f_dir.x += 1.0
		if f_dir != Vector3.ZERO:
			f_dir = f_dir.normalized()
			var fly_basis = Basis.from_euler(Vector3(rotatie_camera_x, rotatie_camera_y, 0))
			pozitie_salvata_camera += fly_basis * f_dir * VITEZA_FREECAM * delta
		if _camera:
			_camera.global_position = pozitie_salvata_camera
			_camera.global_transform.basis = Basis.from_euler(Vector3(rotatie_camera_x, rotatie_camera_y, 0))
		return

	in_apa = global_position.y < WATER_LEVEL

	if _cap_node:
		if mod_curent == ModCamera.FIRST_PERSON or shift_lock_activ:
			rotation.y = rotatie_camera_y
			_cap_node.rotation.y = 0
		else:
			_cap_node.global_transform.basis = Basis.from_euler(Vector3(0, rotatie_camera_y, 0))
		_cap_node.rotation.x = rotatie_camera_x

	# Aliniem și armele generate din cod după unghiul camerei
	if is_instance_valid(arma_arbaleta_generata): arma_arbaleta_generata.rotation.x = rotatie_camera_x
	if is_instance_valid(arma_sabie_generata): arma_sabie_generata.rotation.x = rotatie_camera_x + deg_to_rad(-20)

	var input_dir = Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): input_dir.z -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): input_dir.z += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): input_dir.x += 1.0

	var direction: Vector3 = Vector3.ZERO
	var camera_basis = Basis.from_euler(Vector3(0, rotatie_camera_y, 0))

	if in_apa:
		if input_dir != Vector3.ZERO:
			input_dir = input_dir.normalized()
			var full_basis = Basis.from_euler(Vector3(rotatie_camera_x, rotatie_camera_y, 0))
			direction = full_basis * input_dir
		var buoyancy: float = gravitate * 0.7
		velocity.y -= (gravitate - buoyancy) * delta
		if Input.is_key_pressed(KEY_SPACE):
			velocity.y = VITEZA_INOT
		if Input.is_key_pressed(KEY_SHIFT):
			velocity.y = -VITEZA_INOT
		velocity.x = direction.x * VITEZA_INOT
		velocity.z = direction.z * VITEZA_INOT
		_gestioneaza_rotatie_corp_la_mers(direction, delta)
	else:
		if not is_on_floor():
			velocity.y -= gravitate * delta
		else:
			velocity.y = -0.1
		if input_dir != Vector3.ZERO:
			input_dir = input_dir.normalized()
			direction = camera_basis * input_dir
			direction.y = 0.0
			direction = direction.normalized()
		_gestioneaza_rotatie_corp_la_mers(direction, delta)
		velocity.x = direction.x * VITEZA
		velocity.z = direction.z * VITEZA
		if is_on_floor() and (Input.is_action_just_pressed("ui_accept") or Input.is_key_pressed(KEY_SPACE)):
			velocity.y = FORTA_SARITURA

	move_and_slide()

	if global_position.y < WORLD_BOTTOM:
		global_position.y = 150.0
		velocity = Vector3.ZERO

	if Input.is_action_just_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			_actualizeaza_mod_mouse()

	var i = lista_gloante_active.size() - 1
	while i >= 0:
		var g = lista_gloante_active[i]
		if is_instance_valid(g.nod):
			g.nod.global_position += g.dir * VITEZA_GLONT * delta
			i -= 1
		else:
			lista_gloante_active.remove_at(i)
			i -= 1

func _actualizeaza_pozitie_camera() -> void:
	if mod_curent == ModCamera.FREECAM:
		return
	var spring_arm: SpringArm3D = $Cap/SpringArm3D as SpringArm3D
	if mod_curent == ModCamera.FIRST_PERSON:
		spring_arm.spring_length = 0.0
	elif mod_curent == ModCamera.THIRD_PERSON:
		spring_arm.spring_length = distanta_camera_curenta
	# Camera3D transform is handled by the SpringArm3D node automatically

func _actualizeaza_mod_mouse() -> void:
	if _inventar_deschis():
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return
	if mod_curent == ModCamera.FIRST_PERSON or shift_lock_activ or mod_curent == ModCamera.FREECAM:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _gestioneaza_rotatie_corp_la_mers(directie_miscare: Vector3, delta: float) -> void:
	if mod_curent == ModCamera.THIRD_PERSON and not shift_lock_activ and directie_miscare != Vector3.ZERO:
		var unghi_tinta = atan2(-directie_miscare.x, -directie_miscare.z)
		rotation.y = lerp_angle(rotation.y, unghi_tinta, 15.0 * delta)
		$Cap.rotation.y = 0.0

func _actualizeaza_vizual_arme() -> void:
	var lupta_activa = (mod_interactiune == ModInteractiune.COMBAT)
	var sapa_activa = (mod_interactiune == ModInteractiune.SAPA)
	var construieste_activa = (mod_interactiune == ModInteractiune.CONSTRUIESTE)
	var arb_activa = lupta_activa and (arma_curenta == ModArma.ARBALETA)
	var sab_activa = lupta_activa and (arma_curenta == ModArma.SABIE)
	if is_instance_valid(arma_arbaleta_generata): arma_arbaleta_generata.visible = arb_activa
	if is_instance_valid(arma_sabie_generata): arma_sabie_generata.visible = sab_activa
	if is_instance_valid(model_arc_viitor): model_arc_viitor.visible = arb_activa
	if is_instance_valid(model_sabie_viitor): model_sabie_viitor.visible = sab_activa
	if is_instance_valid(arma_sapa_generata): arma_sapa_generata.visible = sapa_activa
	if is_instance_valid(arma_ciocan_generata): arma_ciocan_generata.visible = construieste_activa

func incrementeaza_scor(puncte: int = 1) -> void:
	scor_curent += puncte
	baloane_sparte += puncte
	_actualizeaza_text_debug()
func _trage_proiectil() -> void:

	var scena_sageata = load("res://scenes/entities/SageataProiectil.tscn") as PackedScene
	var cam_node = get_node_or_null("Cap/SpringArm3D/Camera3D") as Camera3D
	if not scena_sageata or not cam_node: return
	
	var nod_recul = model_arc_viitor if is_instance_valid(model_arc_viitor) else arma_arbaleta_generata
	if is_instance_valid(nod_recul):
		var tween = create_tween()
		tween.tween_property(nod_recul, "position:z", -0.4, 0.05)
		tween.tween_property(nod_recul, "position:z", -0.6, 0.15)

	_reda_sunet("res://addons/crazygames/rele.wav", cam_node.global_position)

	var s = scena_sageata.instantiate()
	get_parent().add_child(s)
	s.global_position = cam_node.global_position
	s.global_transform.basis = cam_node.global_transform.basis
	s.rotate_object_local(Vector3.UP, deg_to_rad(90)) 
	s.set("directie_zbor", -cam_node.global_transform.basis.z.normalized())

func _ataca_sabie() -> void:
	var cam_node = get_node_or_null("Cap/SpringArm3D/Camera3D") as Camera3D
	if not cam_node: return
	
	var nod_taiere = model_sabie_viitor if is_instance_valid(model_sabie_viitor) else arma_sabie_generata
	if is_instance_valid(nod_taiere):
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(nod_taiere, "rotation:x", deg_to_rad(45), 0.08)
		tween.tween_property(nod_taiere, "position:z", -0.7, 0.08)
		var tween_back = create_tween()
		tween_back.set_parallel(true)
		tween_back.tween_property(nod_taiere, "rotation:x", deg_to_rad(-20), 0.12).set_delay(0.08)
		tween_back.tween_property(nod_taiere, "position:z", -0.5, 0.12).set_delay(0.08)

	var spatiu = get_world_3d().direct_space_state
	var start = cam_node.global_position
	var sfarsit = start + (-cam_node.global_transform.basis.z.normalized() * distanta_atac_sabie)
	var p = PhysicsRayQueryParameters3D.create(start, sfarsit)
	p.collision_mask = 2
	var r = spatiu.intersect_ray(p)
	if not r.is_empty() and is_instance_valid(r.collider):
		if r.collider.has_method("primeste_damage"):
			r.collider.call("primeste_damage", damage_sabie)

func primeste_damage(cantitate: float) -> void:
	if mort:
		return
	viata_jucator -= cantitate
	if viata_jucator <= 0 and not mort:
		call_deferred("_on_player_died")

func _on_player_died() -> void:
	mort = true
	get_tree().paused = false
	var interfata = get_node_or_null("Interfata") as Control
	if not interfata:
		_GJ.cleanup()
		get_tree().change_scene_to_file("res://scenes/menu/Meniu.tscn")
		return
	var crosshair = interfata.get_node_or_null("Crosshair")
	if crosshair:
		crosshair.visible = false
	if label_debug:
		label_debug.visible = false
	if spectate_btn:
		spectate_btn.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	_arata_game_over(interfata)
	_salveaza_scor_initial()

func _arata_game_over(interfata: Control) -> void:
	if _game_over_panel:
		return
	_game_over_panel = Panel.new()
	var screen_size = get_viewport().get_visible_rect().size
	_game_over_panel.size = Vector2(400, 300)
	_game_over_panel.position = Vector2(
		(screen_size.x - 400) / 2,
		(screen_size.y - 300) / 2
	)
	_game_over_panel.modulate = Color(0, 0, 0, 0.85)

	var title = Label.new()
	title.text = "GAME OVER"
	title.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
	title.add_theme_font_size_override("font_size", 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 20)
	title.size = Vector2(400, 50)
	_game_over_panel.add_child(title)

	var scor_label = Label.new()
	scor_label.text = "SCOR: %d\nBALOANE SPARTE: %d" % [scor_curent, baloane_sparte]
	scor_label.add_theme_color_override("font_color", Color(1, 1, 1))
	scor_label.add_theme_font_size_override("font_size", 22)
	scor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scor_label.position = Vector2(0, 90)
	scor_label.size = Vector2(400, 60)
	_game_over_panel.add_child(scor_label)

	_score_saved_label = Label.new()
	_score_saved_label.text = "Se salveaza scorul..."
	_score_saved_label.add_theme_color_override("font_color", Color(1, 1, 0))
	_score_saved_label.add_theme_font_size_override("font_size", 16)
	_score_saved_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_saved_label.position = Vector2(0, 170)
	_score_saved_label.size = Vector2(400, 30)
	_game_over_panel.add_child(_score_saved_label)

	interfata.add_child(_game_over_panel)

func _salveaza_scor_initial() -> void:
	if not _NM.is_logged_in():
		_set_save_label("Neautentificat", Color(1, 0.5, 0))
		return
	if not _NM.load_data_result.is_connected(_on_incarca_date_scor):
		_NM.load_data_result.connect(_on_incarca_date_scor)
	_NM.load_player_data()

func _on_incarca_date_scor(success: bool, data: Dictionary) -> void:
	if _NM.load_data_result.is_connected(_on_incarca_date_scor):
		_NM.load_data_result.disconnect(_on_incarca_date_scor)

	var high_score = data.get("high_score", 0) if success else 0
	var total_kills = data.get("total_kills", 0) if success else 0
	var new_high = max(scor_curent, high_score)
	var new_total = total_kills + baloane_sparte

	var save_data = data.duplicate() if success else {}
	save_data["score"] = scor_curent
	save_data["high_score"] = new_high
	save_data["total_kills"] = new_total

	_NM.save_player_data(save_data)

func _on_save_game_score_result(success: bool) -> void:
	if success:
		_set_save_label("Scor salvat!", Color(0, 1, 0))
	else:
		_set_save_label("Eroare la salvare!", Color(1, 0, 0))

func _set_save_label(text: String, color: Color) -> void:
	if _score_saved_label:
		_score_saved_label.text = text
		_score_saved_label.add_theme_color_override("font_color", color)

func _on_spectate() -> void:
	if spectate_btn:
		spectate_btn.visible = false
	_cycle_spectate_target()

func _cycle_spectate_target() -> void:
	spectate_targets = get_tree().get_nodes_in_group("Jucator")
	spectate_targets.erase(self)
	if spectate_targets.is_empty():
		mod_curent = ModCamera.FREECAM
		if has_node("Cap/SpringArm3D/Camera3D"):
			pozitie_salvata_camera = $Cap/SpringArm3D/Camera3D.global_position
		if label_debug:
			label_debug.text = "SPECTATE (nimeni)"
		return
	spectate_idx = (spectate_idx + 1) % spectate_targets.size()
	if label_debug:
		label_debug.text = "URMĂREȘTE: " + spectate_targets[spectate_idx].name

func _spectate_follow(_delta: float) -> void:
	if not mort or spectate_idx < 0 or spectate_idx >= spectate_targets.size():
		return
	var target = spectate_targets[spectate_idx]
	if not is_instance_valid(target):
		_cycle_spectate_target()
		return
	var cam = get_node_or_null("Cap/SpringArm3D/Camera3D") as Camera3D
	if not cam:
		return
	var offset = Vector3(3, 2, 0).rotated(Vector3.UP, rotation.y)
	cam.global_position = target.global_position + offset
	cam.look_at(target.global_position)

# -- TERRAIN NODE LOOKUP AND SPAWN HELPERS --
func _is_procedural_terrain_node(node: Node) -> bool:
	if node == null:
		return false
	var script_ref = node.get_script()
	if script_ref == null:
		return false
	return script_ref.resource_path == TEREN_SCRIPT_PATH or script_ref.resource_path == TEREN_SCRIPT_PATH_ALT

func _locate_terrain_node() -> void:
	if teren_procedural != null:
		return
	var parent_node = get_parent()
	if parent_node == null:
		return
	for node_name in ["Teren", "TerenProcedural"]:
		var candidate = parent_node.get_node_or_null(node_name)
		if _is_procedural_terrain_node(candidate):
			teren_procedural = candidate
			return
		if candidate is VoxelLodTerrain:
			_terrain_manager = candidate as VoxelLodTerrain
			teren_procedural = candidate
			_terrain_manager.register_frozen_player(self)
			_frozen_spawn = true
			return
	for child in parent_node.get_children():
		if _is_procedural_terrain_node(child):
			teren_procedural = child
			return
		if child is VoxelLodTerrain:
			_terrain_manager = child as VoxelLodTerrain
			teren_procedural = child
			_terrain_manager.register_frozen_player(self)
			_frozen_spawn = true
			return

func _get_terrain_spawn_height() -> float:
	if teren_procedural == null:
		return 0.0
	if _terrain_manager != null and _terrain_manager.has_method("get_surface_height_at"):
		var h: Variant = _terrain_manager.call("get_surface_height_at", global_position.x, global_position.z)
		if typeof(h) == TYPE_FLOAT or typeof(h) == TYPE_INT:
			return float(h)
	if teren_procedural.has_method("get_surface_height_at"):
		var h = teren_procedural.call("get_surface_height_at", global_position.x, global_position.z)
		if typeof(h) == TYPE_FLOAT or typeof(h) == TYPE_INT:
			return float(h)
	var noise = teren_procedural.get("zgomot")
	var max_h = teren_procedural.get("max_height_blocks")
	if noise != null and noise.has_method("get_noise_2d") and max_h != null:
		return clamp(noise.get_noise_2d(global_position.x, global_position.z) * float(max_h), 0.0, float(max_h))
	return 0.0

func _try_spawn_above_terrain() -> bool:
	if _frozen_spawn:
		if _terrain_manager and _terrain_manager.is_spawn_ready():
			_frozen_spawn = false
			_terrain_manager.unregister_frozen_player(self)
		else:
			velocity = Vector3.ZERO
			return false

	var height = _get_terrain_spawn_height()
	if height <= 0.0:
		return false
	global_position.y = height + SPAWN_HEIGHT_OFFSET
	velocity = Vector3.ZERO
	spawnat_corect = true
	return true

func _leave_game() -> void:
	_NM.leave_room()
	_NM.disconnect_from_game()
	if has_node("/root/MusicManager"):
		get_node("/root/MusicManager").stop_music()
	get_tree().change_scene_to_file("res://scenes/menu/Meniu.tscn")

var _audio_pool: Array = []

func _reda_sunet(cale: String, pozitie: Vector3, volum: float = -3.0) -> void:
	if not ResourceLoader.exists(cale):
		return
	var s = load(cale) as AudioStream
	if not s:
		return
	var p: AudioStreamPlayer3D = null
	for ap in _audio_pool:
		if not ap.playing:
			p = ap
			break
	if not p:
		p = AudioStreamPlayer3D.new()
		p.finished.connect(_returneaza_audio.bind(p))
		get_parent().add_child(p)
		_audio_pool.append(p)
	p.stream = s
	p.volume_db = volum
	p.global_position = pozitie
	p.play()

func _returneaza_audio(p: AudioStreamPlayer3D) -> void:
	p.stream = null
