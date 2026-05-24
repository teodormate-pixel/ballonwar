extends CharacterBody3D

const VITEZA = 7.0 
const FORTA_SARITURA = 5.5
var gravitate = ProjectSettings.get_setting("physics/3d/default_gravity")

const SENSIBILITATE_MOUSE = 0.002

var spawnat_corect: bool = false

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Resetăm forțat orice blocare din editor
	self.collision_layer = 1
	self.collision_mask = 1
	
	# Curățăm și forțăm o capsulă de coliziune curată
	var col_shape = get_node_or_null("CollisionShape")
	if col_shape == null:
		col_shape = get_node_or_null("CollisionShape3D")
		
	if col_shape:
		col_shape.transform = Transform3D.IDENTITY 
		var noua_capsula = CapsuleShape3D.new()
		noua_capsula.radius = 0.5
		noua_capsula.height = 2.0
		col_shape.shape = noua_capsula

	if has_node("Cap"):
		$Cap.transform = Transform3D.IDENTITY
		$Cap.position.y = 1.5 
	if has_node("Cap/Camera3D"):
		$Cap/Camera3D.transform = Transform3D.IDENTITY


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if has_node("Cap") and has_node("Cap/Camera3D"):
			rotate_y(-event.relative.x * SENSIBILITATE_MOUSE)
			$Cap.rotate_x(-event.relative.y * SENSIBILITATE_MOUSE)
			$Cap.rotation.x = clamp($Cap.rotation.x, deg_to_rad(-89), deg_to_rad(89))


func _physics_process(delta: float) -> void:
	# Sistemul asincron de spawn sigur
	if not spawnat_corect:
		var teren = get_parent().get_node_or_null("TereProcedural")
		if teren == null:
			teren = get_parent().get_node_or_null("TereProcedural")
		
		if teren == null or !("teren_este_gata" in teren) or teren.teren_este_gata == false:
			velocity = Vector3.ZERO
			return
		
		var spawn_x: float = (teren.dimensiune_teren * teren.dimensiune_celula) / 2.0
		var spawn_z: float = (teren.dimensiune_teren * teren.dimensiune_celula) / 2.0
		var inaltime_y: float = teren.zgomot.get_noise_2d(spawn_x, spawn_z) * teren.inaltime_maxima
		
		global_position = Vector3(spawn_x, inaltime_y + 4.0, spawn_z)
		velocity = Vector3.ZERO
		spawnat_corect = true
		print("[Jucător] Poziționat stabil pe pământ.")
		return

	# --- GRAVITAȚIE DIRECTĂ (FORȚATĂ PRIN COORDONATE) ---
	if not is_on_floor():
		velocity.y -= gravitate * delta
		global_position.y -= gravitate * delta # Forțare manuală cădere
	else:
		velocity.y = 0 

	# Săritură directă hardware
	if Input.is_key_pressed(KEY_SPACE) and is_on_floor():
		velocity.y = FORTA_SARITURA
		global_position.y += 0.2 # Impuls inițial manual

	# --- CITIRE DIRECTĂ TASTATURĂ ---
	var in_x: float = 0.0
	var in_z: float = 0.0
	
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		in_z -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		in_z += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		in_x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		in_x += 1.0

	var direction = (transform.basis * Vector3(in_x, 0, in_z)).normalized()
	
	# --- MIȘCARE DIRECTĂ PRIN POZIȚIE GLOBALĂ (Ocolește blocajele) ---
	if direction != Vector3.ZERO:
		velocity.x = direction.x * VITEZA
		velocity.z = direction.z * VITEZA
		
		# Mutăm poziția în mod absolut pe axele X și Z
		global_position.x += direction.x * VITEZA * delta
		global_position.z += direction.z * VITEZA * delta
	else:
		velocity.x = 0
		velocity.z = 0

	# Apelăm și funcția nativă ca să păstrăm intactă coliziunea cu dealurile
	move_and_slide()

	# ESCAPE pentru mouse
	if Input.is_action_just_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
