extends Node3D
class_name SpawnerInamici

func _ready() -> void:
	var mesh_node: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.4
	sphere.rings = 8
	sphere.radial_segments = 16
	mesh_node.mesh = sphere
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0, 0)
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mesh_node.material_override = mat
	add_child(mesh_node)

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
	var scena_balon = load("res://InamicBalon.tscn") as PackedScene
	if scena_balon:
		var b = scena_balon.instantiate()
		# Îl adăugăm în rădăcina lumii pentru a se mișca independent
		get_parent().add_child(b)
		# Balonul apare chiar din poziția spawnerului suspendat în aer
		b.global_position = global_position + Vector3(0, 15.0, 0)
		print("Un nou balon inamic a fost generat din cer!")
	else:
		print("Eroare: Nu s-a găsit fișierul res://InamicBalon.tscn în proiect!")
