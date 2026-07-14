extends CharacterBody3D
class_name InamicBalon

var model_vizual: PackedScene
var jucator_tinta: Node3D = null
var _teren_ref: Node = null
var _camera_ref: Camera3D = null

var viteza_miscare: float = 3.2
var viata_inamica: float = 100.0
var timp_reincarcare_atac: float = 1.2
var cronometru_atac: float = 0.0
@export var puncte_valoare: int = 10
var tip_inamic: String = "normal"

var sageti_incordate: Array = []

const POP_SOUND: String = "res://assets/images/assest/balloon-pop-48030 (1).wav"

const DROP_TABLE: Dictionary = {
	"normal": [{"type": 3, "min": 1, "max": 3, "chance": 0.6}],
	"rapid": [{"type": 4, "min": 1, "max": 2, "chance": 0.5}],
	"mare": [{"type": 5, "min": 1, "max": 4, "chance": 0.7}, {"type": 7, "min": 1, "max": 1, "chance": 0.2}],
}

func _ready() -> void:
	collision_layer = 2
	collision_mask = 3
	Callable(self, "_incarca_vizual_asincron").call_deferred()

func _incarca_vizual_asincron() -> void:
	if model_vizual != null and is_inside_tree():
		add_child(model_vizual.instantiate())
	if not has_node("CollisionShape3D"):
		var col = CollisionShape3D.new()
		col.name = "CollisionShape3D"
		var forma_sfera = SphereShape3D.new()
		forma_sfera.radius = 0.95
		col.shape = forma_sfera
		add_child(col)

func configura(tip: String) -> void:
	tip_inamic = tip
	match tip:
		"rapid":
			viteza_miscare = 5.5
			viata_inamica = 60.0
			puncte_valoare = 15
		"mare":
			viteza_miscare = 2.0
			viata_inamica = 200.0
			puncte_valoare = 30
		_:
			viteza_miscare = 3.2
			viata_inamica = 100.0
			puncte_valoare = 10

func inregistreaza_sageata(sageata: Node3D) -> void:
	sageti_incordate.append(sageata)

func _elibereaza_sagetile() -> void:
	for s in sageti_incordate:
		if is_instance_valid(s):
			var world = get_parent()
			if world:
				s.reparent(world)
				s.set_physics_process(true)
				s.set("stuck", false)
				var dir = Vector3(randf_range(-1, 1), randf_range(0.2, 1), randf_range(-1, 1)).normalized()
				s.set("directie_zbor", dir * 0.5)
				s.set("viteza", 15.0)
				s.set("timp_viata", 0.0)
	sageti_incordate.clear()

func _physics_process(delta: float) -> void:
	if not is_inside_tree():
		return

	if cronometru_atac > 0.0:
		cronometru_atac -= delta

	if jucator_tinta == null or not is_instance_valid(jucator_tinta):
		var jucatori: Array = get_tree().get_nodes_in_group("Jucator")
		if jucatori.size() > 0:
			jucator_tinta = jucatori[0]
		else:
			if is_inside_tree():
				move_and_slide()
			return

	if not is_instance_valid(jucator_tinta):
		if is_inside_tree():
			move_and_slide()
		return

	if not _camera_ref or not is_instance_valid(_camera_ref):
		_camera_ref = jucator_tinta.get_node_or_null("Cap/SpringArm3D/Camera3D") as Camera3D
	var pozitie_ochi: Vector3 = _camera_ref.global_position if _camera_ref else jucator_tinta.global_position + Vector3(0, 1.5, 0)

	var distanta: float = global_position.distance_to(pozitie_ochi)

	if distanta > 3.0:
		var dir: Vector3 = (pozitie_ochi - global_position).normalized()
		velocity = dir * viteza_miscare

		var dir_2d: Vector3 = Vector3(dir.x, 0, dir.z).normalized()
		if dir_2d.length() > 0.001:
			rotation.y = lerp_angle(rotation.y, atan2(-dir_2d.x, -dir_2d.z), 8.0 * delta)
	else:
		velocity = Vector3.ZERO

		if cronometru_atac <= 0.0:
			if jucator_tinta.has_method("primeste_damage"):
				jucator_tinta.primeste_damage(10)
				cronometru_atac = timp_reincarcare_atac

	if is_inside_tree():
		move_and_slide()
		_limiteaza_pozitie_pe_harta()

func _limiteaza_pozitie_pe_harta() -> void:
	if not is_inside_tree() or get_tree() == null:
		return
	if not _teren_ref:
		var scena_principala = get_tree().current_scene
		if scena_principala == null:
			return
		_teren_ref = scena_principala.find_child("TerenProcedural", true, false)
	if _teren_ref and "dimensiune_teren" in _teren_ref and "dimensiune_celula" in _teren_ref:
		var marime_maxima_harta: float = (_teren_ref.dimensiune_teren * _teren_ref.dimensiune_celula) / 2.0
		var limita_sigura: float = marime_maxima_harta - 3.0
		global_position.x = clamp(global_position.x, -limita_sigura, limita_sigura)
		global_position.z = clamp(global_position.z, -limita_sigura, limita_sigura)

func primeste_damage(cantitate: float) -> void:
	viata_inamica -= cantitate
	_efect_lovitura()
	if viata_inamica <= 0:
		_elibereaza_sagetile()
		_reda_sunet_spargere()
		_efect_moarte()
		_recompenseaza_jucator()
		_drop_loot()
		queue_free()

func _efect_lovitura() -> void:
	modulate = Color(1, 0.3, 0.3)
	var tw = create_tween()
	tw.tween_property(self, "modulate", Color.WHITE, 0.15)

func _efect_moarte() -> void:
	if not is_inside_tree():
		return
	var gp = GPUParticles3D.new()
	gp.one_shot = true
	gp.emitting = true
	gp.amount = 15
	gp.lifetime = 0.8
	var proc = GpuParticles3D.new()
	gp.process_material = ParticleProcessMaterial.new()
	gp.process_material.velocity_min = Vector3(-3, 1, -3)
	gp.process_material.velocity_max = Vector3(3, 5, 3)
	gp.process_material.color = Color(1, 0.3, 0.1)
	gp.process_material.scale_min = 0.3
	gp.process_material.scale_max = 0.6
	gp.position = global_position
	get_parent().add_child(gp)
	gp.finished.connect(gp.queue_free)

func _drop_loot() -> void:
	var drops = DROP_TABLE.get(tip_inamic, DROP_TABLE["normal"])
	for entry in drops:
		if randf() < entry["chance"]:
			var count = randi_range(entry["min"], entry["max"])
			var player = jucator_tinta
			if player and player.has_method("add_block_to_inventory"):
				player.call("add_block_to_inventory", entry["type"], count)

func _reda_sunet_spargere() -> void:
	if not ResourceLoader.exists(POP_SOUND):
		return
	var s = load(POP_SOUND) as AudioStream
	var p = AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = -3.0
	get_parent().add_child(p)
	p.global_position = global_position
	p.play()
	p.finished.connect(p.queue_free)

func _recompenseaza_jucator() -> void:
	if not is_instance_valid(jucator_tinta):
		return
	if jucator_tinta.has_method("incrementeaza_scor"):
		jucator_tinta.call("incrementeaza_scor", puncte_valoare)
