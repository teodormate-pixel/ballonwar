extends CharacterBody3D
class_name Jucator

const VITEZA: float = 7.0
const FORTA_SARITURA: float = 5.5
var gravitate: float = ProjectSettings.get_setting("physics/3d/default_gravity")

const SENSIBILITATE_MOUSE = 0.002
var spawnat_corect: bool = false

enum ModCamera { FIRST_PERSON, THIRD_PERSON, FREECAM }
var mod_curent: ModCamera = ModCamera.FIRST_PERSON

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

func _ready() -> void:
	get_tree().paused = false
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
		$Cap/Camera3D.fov = FOV_NORMAL
	_actualizeaza_pozitie_camera()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_C and mod_curent != ModCamera.FREECAM:
		if mod_curent == ModCamera.FIRST_PERSON:
			mod_curent = ModCamera.THIRD_PERSON
			distanta_camera_curenta = 3.5 
			rotatie_camera_y = rotation.y
			fov_curent = FOV_NORMAL
		else:
			mod_curent = ModCamera.FIRST_PERSON
			shift_lock_activ = false 
			rotation.y = rotatie_camera_y
			$Cap.rotation.y = 0
			fov_curent = FOV_NORMAL
		_actualizeaza_pozitie_camera()
		_actualizeaza_mod_mouse()

	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		if mod_curent != ModCamera.FREECAM:
			mod_curent = ModCamera.FREECAM
			shift_lock_activ = false
			fov_curent = FOV_NORMAL
			if has_node("Cap/Camera3D"):
				pozitie_salvata_camera = $Cap/Camera3D.global_position
		else:
			mod_curent = ModCamera.FIRST_PERSON
		_actualizeaza_pozitie_camera()
		_actualizeaza_mod_mouse()

	if event is InputEventKey and event.pressed and event.keycode == KEY_SHIFT and mod_curent == ModCamera.THIRD_PERSON:
		shift_lock_activ = not shift_lock_activ
		if shift_lock_activ:
			rotation.y = rotatie_camera_y
			$Cap.rotation.y = 0
		_actualizeaza_pozitie_camera()
		_actualizeaza_mod_mouse()

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if mod_curent == ModCamera.THIRD_PERSON:
				distanta_camera_curenta -= VITEZA_ZOOM
				if distanta_camera_curenta <= ZOOM_MIN:
					mod_curent = ModCamera.FIRST_PERSON
					shift_lock_activ = false
					rotation.y = rotatie_camera_y
					$Cap.rotation.y = 0
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
		var se_poate_roti = (mod_curent == ModCamera.FIRST_PERSON) or shift_lock_activ or (mod_curent == ModCamera.FREECAM) or (mod_curent == ModCamera.THIRD_PERSON and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))
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

	if has_node("Cap/Camera3D"):
		$Cap/Camera3D.fov = lerp($Cap/Camera3D.fov, fov_curent, 10.0 * delta)

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
		if has_node("Cap/Camera3D"):
			$Cap/Camera3D.global_position = pozitie_salvata_camera
			$Cap/Camera3D.global_transform.basis = Basis.from_euler(Vector3(rotatie_camera_x, rotatie_camera_y, 0))
		return

	if not is_on_floor():
		velocity.y -= gravitate * delta
	else:
		velocity.y = -0.1

	if has_node("Cap"):
		if mod_curent == ModCamera.FIRST_PERSON or shift_lock_activ:
			rotation.y = rotatie_camera_y
			$Cap.rotation.y = 0 
		else:
			$Cap.global_transform.basis = Basis.from_euler(Vector3(0, rotatie_camera_y, 0))
		$Cap.rotation.x = rotatie_camera_x

	var input_dir = Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): input_dir.z -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): input_dir.z += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): input_dir.x += 1.0
		
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
		camera.rotation = Vector3.ZERO
	elif mod_curent == ModCamera.THIRD_PERSON:
		if shift_lock_activ:
			camera.position = Vector3(OFFSET_UMAR_SHIFT_LOCK.x, OFFSET_UMAR_SHIFT_LOCK.y, distanta_camera_curenta)
		else:
			camera.position = Vector3(0, 0, distanta_camera_curenta)
		camera.rotation = Vector3.ZERO

func _actualizeaza_mod_mouse() -> void:
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
