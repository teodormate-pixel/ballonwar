extends Area3D

var directie_zbor: Vector3 = Vector3.ZERO
var viteza: float = 30.0 # Poți mări viteza la 30 sau 40 dacă vrei să zboare mai rapid!
var timp_viata: float = 0.0

func _ready() -> void:
	# Activăm straturile fizice direct din cod pentru siguranță
	self.collision_layer = 4
	self.collision_mask = 3 # Scanează solul (1) și inamicii (2)
	
	# Conectăm semnalul de coliziune nativ
	body_entered.connect(_pe_impact_corp)

func _physics_process(delta: float) -> void:
	# Mișcare liniară fluidă pe axa camerei, fără trecere prin pereți
	global_position += directie_zbor * viteza * delta
	
	# Siguranță: Se șterge singură din memorie după 5 secunde dacă zboară spre cer
	timp_viata += delta
	if timp_viata > 5.0:
		queue_free()

func _pe_impact_corp(body: Node3D) -> void:
	# Verificăm dacă am lovit un balon inamic și îi dăm damage
	if body.has_method("primeste_damage"):
		body.call("primeste_damage", 25)
		
	# Redăm sunetul de impact/pop automat de pe hard-disk
	var cale_sunet = "res://sunet_impact.wav"
	if ResourceLoader.exists(cale_sunet):
		var s = load(cale_sunet) as AudioStream
		var p = AudioStreamPlayer3D.new()
		p.stream = s
		p.volume_db = 2.0
		get_tree().current_scene.add_child(p)
		p.global_position = global_position
		p.play()
		p.finished.connect(func(): p.queue_free())
		
	# Săgeata se distruge instantaneu după ce și-a făcut datoria, lăsând ecranul curat
	queue_free()
