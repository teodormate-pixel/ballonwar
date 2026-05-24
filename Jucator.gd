extends CharacterBody3D
class_name Jucator

const VITEZA: float = 7.0
const FORTA_SARITURA: float = 5.5
var gravitate: float = ProjectSettings.get_setting("physics/3d/default_gravity")

const SENSIBILITATE_MOUSE = 0.002
var spawnat_corect: bool = false

# --- VARIABILE STIL ROBLOX CAMERA ---
enum ModCamera { FIRST_PERSON, THIRD_PERSON }
var mod_curent: ModCamera = ModCamera.FIRST_PERSON

var shift_lock_activ: bool = false
const DISTANTA_THIRD_PERSON: float = 3.5  
const OFFSET_UMAR_SHIFT_LOCK: Vector3 = Vector3(0.6, 0.2, 0.0) 

var rotatie_camera_x: float = 0.0
var rotatie_camera_y: float = 0.0

func _ready() -> void:
	get_tree().paused = false
	# Inițializăm mouse-ul în mod capturat la start (First Person)
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
	if has_node("Cap/Camera3D"):
		$Cap/Camera3D.transform = Transform3D.IDENTITY
		$Cap/Camera3D.near = 0.3
		$Cap/Camera3D.far = 200.0
		
	_actualizeaza_pozitie_camera()

func _unhandled_input(event: InputEvent) -> void:
	# Schimbare mod Cameră la tasta C
	if event is InputEventKey and event.pressed and event.keycode == KEY_C:
		if mod_curent == ModCamera.FIRST_PERSON:
			mod_curent = ModCamera.THIRD_PERSON
			rotatie_camera_y = rotation.y
			print("[Cameră] Trecere pe Third Person")
		else:
			mod_curent = ModCamera.FIRST_PERSON
			shift_lock_activ = false 
			rotation.y = rotatie_camera_y
			$Cap.rotation.y = 0
			print("[Cameră] Revenire în First Person")
		_actualizeaza_pozitie_camera()
		_actualizeaza_mod_mouse()

	# Activare / Dezactivare Shift Lock la tasta Shift
	if event is InputEventKey and event.pressed and event.keycode == KEY_SHIFT and mod_curent == ModCamera.THIRD_PERSON:
		shift_lock_activ = not shift_lock_activ
		if shift_lock_activ:
			rotation.y = rotatie_camera_y
			$Cap.rotation.y = 0
		print("[Shift Lock] ", "ACTIVAT" if shift_lock_activ else "DEZACTIVAT")
		_actualizeaza_pozitie_camera()
		_actualizeaza_mod_mouse()

	# NOU: Ascultăm când jucătorul apasă sau eliberează Click Dreapta (Doar în Third Person liber)
	if event is InputEventMouseButton and mod_curent == ModCamera.THIRD_PERSON and not shift_lock_activ:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_actualizeaza_mod_mouse()

	# Rotația camerei cu mouse-ul
	if event is InputEventMouseMotion:
		# REPARARE LOGICĂ CLICK DREAPTA / SHIFT LOCK:
		# Permitem rotația doar dacă suntem în First Person, sau în Shift Lock, sau dacă ținem apăsat Click Dreapta în Third Person simplu
		var se_poate_roti = (mod_curent == ModCamera.FIRST_PERSON) or shift_lock_activ or (mod_curent == ModCamera.THIRD_PERSON and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))
		
		if se_poate_roti and has_node("Cap"):
			rotatie_camera_y -= event.relative.x * SENSIBILITATE_MOUSE
			rotatie_camera_x -= event.relative.y * SENSIBILITATE_MOUSE
			rotatie_camera_x = clamp(rotatie_camera_x, deg_to_rad(-89), deg_to_rad(89))

func _physics_process(delta: float) -> void:
	var teren: Node3D = get_parent().get_node_or_null("TerenProcedural") as Node3D
	
	if not spawnat_corect:
		if teren == null or not ("teren_este_gata" in teren and teren.teren_este_gata):
			velocity = Vector3.ZERO
			return
		
		var spawn_x: float = 0.0
		var spawn_z: float = 0.0
		var offset_zgomot_x = (teren.dimensiune_teren * teren.dimensiune_celula) / 2.0
		var offset_zgomot_z = (teren.dimensiune_teren * teren.dimensiune_celula) / 2.0
		var inaltime_y = teren.zgomot.get_noise_2d(offset_zgomot_x, offset_zgomot_z) * teren.inaltime_maxima
		
		global_position = Vector3(spawn_x, inaltime_y + 15.0, spawn_z)
		velocity = Vector3.ZERO
		spawnat_corect = true
		return

	if not is_on_floor():
		velocity.y -= gravitate * delta
	else:
		velocity.y = -0.1

	# Aplicare rotații pe ierarhia de noduri 3D
	if has_node("Cap"):
		if mod_curent == ModCamera.FIRST_PERSON or shift_lock_activ:
			rotation.y = rotatie_camera_y
			$Cap.rotation.y = 0 
		else:
			$Cap.global_transform.basis = Basis.from_euler(Vector3(0, rotatie_camera_y, 0))
		
		$Cap.rotation.x = rotatie_camera_x

	# Citire taste mișcare
	var input_dir = Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_dir.z -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_dir.z += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_dir.x += 1.0
		
	var direction: Vector3 = Vector3.ZERO
	if input_dir != Vector3.ZERO:
		input_dir = input_dir.normalized()
		
		var camera_basis = Basis.from_euler(Vector3(0, rotatie_camera_y, 0))
		direction = camera_basis * input_dir
		direction.y = 0.0
		direction = direction.normalized()

	_gestioneaza_rotatie_corp_la_mers(direction, delta)

	velocity.x = direction.x * VITEZA
	velocity.z = direction.z * VITEZA

	if is_on_floor() and (Input.is_action_just_pressed("ui_accept") or Input.is_key_pressed(KEY_SPACE)):
		velocity.y = FORTA_SARITURA

	move_and_slide()

	# Lăsăm tasta ESC (ui_cancel) să poată elibera mouse-ul manual în orice situație
	if Input.is_action_just_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			_actualizeaza_mod_mouse()

func _actualizeaza_pozitie_camera() -> void:
	if not has_node("Cap/Camera3D"): return
	var camera = $Cap/Camera3D
	
	if mod_curent == ModCamera.FIRST_PERSON:
		camera.position = Vector3.ZERO
	elif mod_curent == ModCamera.THIRD_PERSON:
		if shift_lock_activ:
			camera.position = Vector3(OFFSET_UMAR_SHIFT_LOCK.x, OFFSET_UMAR_SHIFT_LOCK.y, DISTANTA_THIRD_PERSON)
		else:
			camera.position = Vector3(0, 0, DISTANTA_THIRD_PERSON)
	camera.rotation = Vector3.ZERO

# NOU: Funcție automată care blochează sau deblochează cursorul mouse-ului în funcție de mod și click-uri
func _actualizeaza_mod_mouse() -> void:
	if mod_curent == ModCamera.FIRST_PERSON or shift_lock_activ:
		# Blocat permanent în centru
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		# În Third Person liber: ascundem mouse-ul doar dacă jucătorul ține apăsat Click Dreapta
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _gestioneaza_rotatie_corp_la_mers(directie_miscare: Vector3, delta: float) -> void:
	if mod_curent == ModCamera.THIRD_PERSON and not shift_lock_activ and directie_miscare != Vector3.ZERO:
		var unghi_tinta = atan2(-directie_miscare.x, -directie_miscare.z)
		rotation.y = lerp_angle(rotation.y, unghi_tinta, 15.0 * delta)
		$Cap.rotation.y = 0.0
