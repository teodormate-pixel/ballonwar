extends Area3D

var directie_zbor: Vector3 = Vector3.ZERO
var viteza: float = 30.0
var timp_viata: float = 0.0
var stuck: bool = false
var timp_stuck: float = 0.0
var hit_body: Node3D = null

const IMPACT_SOUND: String = "res://addons/crazygames/arrowhit.wav"

func _ready() -> void:
	collision_layer = 4
	collision_mask = 3
	body_entered.connect(_pe_impact_corp)

func _physics_process(delta: float) -> void:
	if stuck:
		timp_stuck += delta
		if timp_stuck > 15.0:
			queue_free()
		return
	global_position += directie_zbor * viteza * delta
	timp_viata += delta
	if timp_viata > 5.0:
		queue_free()

func _pe_impact_corp(body: Node3D) -> void:
	if stuck:
		return
	stuck = true
	hit_body = body

	if body.has_method("primeste_damage"):
		body.call("primeste_damage", 25)

	_play_sound(IMPACT_SOUND)

	if body is StaticBody3D or body is BlockScena or body is TerenProceduralTerrain:
		reparent(body)
	elif body is CharacterBody3D or body is RigidBody3D:
		reparent(body)
		if body.has_method("inregistreaza_sageata"):
			body.call("inregistreaza_sageata", self)

	monitoring = false
	set_physics_process(false)

func _play_sound(path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var s = load(path) as AudioStream
	var p = AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = -2.0
	get_tree().current_scene.add_child(p)
	p.global_position = global_position
	p.play()
	p.finished.connect(func(): p.queue_free())
