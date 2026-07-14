extends Node3D
class_name SpawnerInamici

var cronometru: float = 0.0
var timp_urmator_spawn: float = 5.0

func _physics_process(delta: float) -> void:
	# Numărăm secundele în mod asincron, fără să blocăm fizica lumii
	cronometru += delta
	if cronometru >= timp_urmator_spawn:
		cronometru = 0.0
		timp_urmator_spawn = randf_range(15.0, 30.0)
		_genereaza_balon()

func _genereaza_balon() -> void:
	# Încărcăm asincron scena inamicului pe care ai salvat-o în proiect
	var scena_balon = load("res://scenes/entities/InamicBalon.tscn") as PackedScene
	if scena_balon:
		var b = scena_balon.instantiate()
		# Îl adăugăm în rădăcina lumii pentru a se mișca independent
		get_parent().add_child(b)
		# Balonul apare chiar din poziția spawnerului suspendat în aer
		b.global_position = global_position + Vector3(0, 15.0, 0)
		print("Un nou balon inamic a fost generat din cer!")
	else:
		print("Eroare: Nu s-a găsit fișierul res://scenes/entities/InamicBalon.tscn în proiect!")
