extends Node3D
class_name SpawnerInamic

# --- VARIABILE PENTRU INSPECTOR ---
@export var model_spawner: PackedScene 
@export var model_inamic: PackedScene  
@export var nod_jucator: CharacterBody3D 

var timp_urmator_spawn: float = 4.0
var cronometru: float = 0.0

func _ready() -> void:
	# Încărcăm modelul vizual .glb al clădirii spawnerului
	if model_spawner != null:
		var instanta_vizuala = model_spawner.instantiate()
		add_child.call_deferred(instanta_vizuala)
	
	# Căutăm automat jucătorul în grup dacă nu a fost pus în Inspector
	if nod_jucator == null:
		var jucatori = get_tree().get_nodes_in_group("Jucator")
		if jucatori.size() > 0:
			nod_jucator = jucatori[0] as CharacterBody3D

	# Pre-încărcare model în placa video pentru a elimina total lagul de pe ecran
	if model_inamic != null:
		var pre_incarcare = model_inamic.instantiate()
		add_child(pre_incarcare)
		pre_incarcare.queue_free()

	# Așteptăm 1.5 secunde pentru siguranța generării terenului, apoi fixăm poziția în centrul real
	get_tree().create_timer(1.5).timeout.connect(_fixeaza_spawner_in_centru)
	_reseteaza_timer()

func _fixeaza_spawner_in_centru() -> void:
	var inaltime_y = 12.0
	var centru_x = 0.0
	var centru_z = 0.0
	
	var teren = get_tree().current_scene.find_child("TerenProcedural", true, false)
	if teren and "dimensiune_teren" in teren and "dimensiune_celula" in teren:
		# REPARARE CENTRU: Calculăm mijlocul perfect al gridului (Lățime totală / 2)
		centru_x = (teren.dimensiune_teren * teren.dimensiune_celula) / 2.0
		centru_z = (teren.dimensiune_teren * teren.dimensiune_celula) / 2.0
		
		# Aflăm înălțimea solului exact din mijlocul hărții folosind zgomotul tău procedural
		if teren.has_method("get_surface_height_at"):
			# Use terrain's surface height function for exact Y
			var center_height: float = teren.get_surface_height_at(centru_x, centru_z)
			inaltime_y = center_height + 10.0
	else:
		# Valori de rezervă dacă terenul nu este găsit în ierarhie
		if nod_jucator:
			inaltime_y = nod_jucator.global_position.y + 8.0
			centru_x = 30.0
			centru_z = 30.0

	# REPARAT DEFINITIV: Spawnerul se mută în mijlocul geografic al terenului și rămâne FIX acolo!
	global_position = Vector3(centru_x, inaltime_y, centru_z)
	print("Spawnerul s-a fixat la centrul real al hărții: ", global_position)

func _physics_process(delta: float) -> void:
	# Buclă simplă de timp: doar numără secundele fără să modifice vreodată poziția clădirii
	cronometru += delta
	if cronometru >= timp_urmator_spawn:
		_spawneaza_inamic()
		_reseteaza_timer()

func _reseteaza_timer() -> void:
	cronometru = 0.0
	# Interval de spawn dinamic între 4 și 8 secunde
	timp_urmator_spawn = randf_range(4.0, 8.0)

func _spawneaza_inamic() -> void:
	if model_inamic == null: 
		return
	
	# Încărcăm scriptul nativ al balonului
	var script_balon = load("res://scripts/combat/InamicBalon.gd")
	if script_balon == null:
		print("Eroare critică: Fișierul InamicBalon.gd nu a fost găsit în proiect!")
		return
		
	var inamic = CharacterBody3D.new()
	inamic.name = "BalonInamic_" + str(randi())
	inamic.collision_layer = 2
	inamic.collision_mask = 3
	inamic.set_script(script_balon)
	
	# Pasăm datele către scriptul balonului în spațiul offline
	inamic.model_vizual = model_inamic
	inamic.jucator_tinta = nod_jucator
	
	# Baloanele apar direct din poziția spawnerului fixat în centrul aerian
	inamic.position = position
	get_parent().add_child.call_deferred(inamic)
