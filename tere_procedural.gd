extends StaticBody3D

@export var dimensiune_teren: int = 250     
@export var dimensiune_celula: float = 1.0   
@export var inaltime_maxima: float = 25.0   
@export_color_no_alpha var culoare_teren: Color = Color("2e6f40")

var zgomot: FastNoiseLite
var teren_este_gata: bool = false # Semnalizator pentru jucător

@onready var mesh_vizual: MeshInstance3D = $MeshVizual
@onready var forma_fizica: CollisionShape3D = $FormaFizica

func _ready() -> void:
	_configureaza_zgomot()
	_genereaza_teren()

func _configureaza_zgomot() -> void:
	zgomot = FastNoiseLite.new()
	zgomot.seed = randi() 
	zgomot.noise_type = FastNoiseLite.TYPE_PERLIN
	zgomot.frequency = 0.015 

func _genereaza_teren() -> void:
	var a_mesh = ArrayMesh.new()
	var surface_array = []
	surface_array.resize(Mesh.ARRAY_MAX)
	
	var vertices = PackedVector3Array()
	var indices = PackedInt32Array()
	
	for z in range(dimensiune_teren + 1):
		for x in range(dimensiune_teren + 1):
			var pos_x = x * dimensiune_celula
			var pos_z = z * dimensiune_celula
			var inaltime_y = zgomot.get_noise_2d(pos_x, pos_z) * inaltime_maxima
			vertices.append(Vector3(pos_x, inaltime_y, pos_z))
			
	for z in range(dimensiune_teren):
		for x in range(dimensiune_teren):
			var i = x + z * (dimensiune_teren + 1)
			indices.append(i)
			indices.append(i + dimensiune_teren + 1)
			indices.append(i + 1)
			indices.append(i + 1)
			indices.append(i + dimensiune_teren + 1)
			indices.append(i + dimensiune_teren + 2)
			
	surface_array[Mesh.ARRAY_VERTEX] = vertices
	surface_array[Mesh.ARRAY_INDEX] = indices
	
	a_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_array)
	mesh_vizual.mesh = a_mesh
	
	var material_nou = StandardMaterial3D.new()
	material_nou.albedo_color = culoare_teren
	material_nou.roughness = 0.85
	mesh_vizual.material_override = material_nou
	
	# Generăm coliziunea stabilă
	var forma_fizionomie = ConcavePolygonShape3D.new()
	forma_fizionomie.set_faces(a_mesh.get_faces())
	forma_fizica.shape = forma_fizionomie
	self.collision_layer = 1
	
	# Forțăm motorul fizic să proceseze noua structură a pământului
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	# Anunțăm că tot terenul este gata și solid
	teren_este_gata = true
	print("[Teren] Generat complet și pregătit pentru jucător!")
