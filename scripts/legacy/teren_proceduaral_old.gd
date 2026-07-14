
extends Node3D
# class_name TerenProcedural

# --- CONFIGURĂRI MINECRAFT INFINIT ---
@export var dimensiune_chunk: float = 32.0    # 32x32 metri per chunk
@export var distanta_randare: int = 2         # Chunks încărcați în jurul tău
@export var inaltime_maxima: float = 16.0     # Înălțimea maximă a munților

# --- CONFIGURĂRI COPACI ȘI IARBĂ ---
@export var densitate_copaci: float = 0.10     # 0.0 - 1.0, cât de des apar copacii
@export var densitate_iarba: float = 0.2       # 0.0 - 1.0, cât de des apare iarba
@export var inaltime_copac: float = 4.0       # Înălțimea copacilor

var zgomot: FastNoiseLite = FastNoiseLite.new()
var zgomot_copaci: FastNoiseLite = FastNoiseLite.new()  # Noise separat pentru copaci
var chunk_uri_incarcate: Dictionary = {}    
var spawner_e_gata_pe_chunk: Dictionary = {} 

var chunk_jucator_vechi: Vector2i = Vector2i(-999, -999)
var nod_jucator: CharacterBody3D = null

var teren_este_gata: bool = false
var material_sol: StandardMaterial3D = StandardMaterial3D.new()
var material_copac_trunchi: StandardMaterial3D = StandardMaterial3D.new()
var material_copac_frunze: StandardMaterial3D = StandardMaterial3D.new()
var material_iarba: StandardMaterial3D = StandardMaterial3D.new()

func _ready() -> void:
	# Configurare material sol (iarbă)
	material_sol.albedo_color = Color(0.15, 0.55, 0.15) 
	material_sol.roughness = 0.85
	material_sol.cull_mode = StandardMaterial3D.CULL_DISABLED 
	material_sol.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	
	# Materiale copac
	material_copac_trunchi.albedo_color = Color(0.4, 0.25, 0.1)  # Maro
	material_copac_trunchi.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	
	material_copac_frunze.albedo_color = Color(0.1, 0.5, 0.1)  # Verde închis
	material_copac_frunze.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	
	# Material iarbă
	material_iarba.albedo_color = Color(0.2, 0.6, 0.1)  # Verde deschis
	material_iarba.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	
	# GENERARE NATURALĂ: Setări profesionale pentru munți și văi line, organice
	zgomot.noise_type = FastNoiseLite.TYPE_PERLIN
	zgomot.seed = randi()
	zgomot.frequency = 0.007 # Frecvență mică = munți mari naturali distanțați, nu trepte!
	zgomot.fractal_octaves = 4
	
	# Noise pentru distribuția copacilor (folosit pentru a evita zonele goale)
	zgomot_copaci.noise_type = FastNoiseLite.TYPE_PERLIN
	zgomot_copaci.seed = randi()
	zgomot_copaci.frequency = 0.05
	
	_cauta_jucator_securizat()
	_actualizeaza_chunk_uri(Vector2i.ZERO)
	teren_este_gata = true

func _physics_process(_delta: float) -> void:
	if nod_jucator == null:
		_cauta_jucator_securizat()
		return

	var cx = floor(nod_jucator.global_position.x / dimensiune_chunk)
	var cz = floor(nod_jucator.global_position.z / dimensiune_chunk)
	var chunk_curent = Vector2i(cx, cz)

	# ÎNCĂRCARE INFINITĂ LA MARGINE: Generează munți noi când te miști
	if chunk_curent != chunk_jucator_vechi:
		_actualizeaza_chunk_uri(chunk_curent)
		chunk_jucator_vechi = chunk_curent

func _cauta_jucator_securizat() -> void:
	var jucatori = get_tree().get_nodes_in_group("Jucator")
	if jucatori.size() > 0:
		nod_jucator = jucatori[0] as CharacterBody3D
	else:
		var scena_principala = get_tree().current_scene
		if scena_principala:
			nod_jucator = scena_principala.get_node_or_null("StarterPlayer") as CharacterBody3D

func _actualizeaza_chunk_uri(centru_chunk: Vector2i) -> void:
	var chei_necesare: Array = []

	for x in range(-distanta_randare, distanta_randare + 1):
		for y in range(-distanta_randare, distanta_randare + 1):
			var coord_chunk = Vector2i(centru_chunk.x + x, centru_chunk.y + y)
			var cheie = "%d,%d" % [coord_chunk.x, coord_chunk.y]
			chei_necesare.append(cheie)

			if not chunk_uri_incarcate.has(cheie):
				_genereaza_singur_chunk(coord_chunk.x, coord_chunk.y, cheie)

	for cheie_activa in chunk_uri_incarcate.keys():
		if not chei_necesare.has(cheie_activa):
			if is_instance_valid(chunk_uri_incarcate[cheie_activa]):
				chunk_uri_incarcate[cheie_activa].queue_free()
			chunk_uri_incarcate.erase(cheie_activa)

func _genereaza_singur_chunk(cx: int, cz: int, cheie: String) -> void:
	var corp_static = StaticBody3D.new()
	corp_static.name = "Chunk_" + cheie
	corp_static.collision_layer = 1 
	corp_static.collision_mask = 7
	
	# Nod separat pentru vegetație (nu are coliziune cu terenul)
	var nod_vegetatie = Node3D.new()
	nod_vegetatie.name = "Vegetatie_" + cheie
	corp_static.add_child(nod_vegetatie)
	
	var start_x = cx * dimensiune_chunk
	var start_z = cz * dimensiune_chunk
	var rezolutie: int = 8 # Densitatea de poligoane (triunghiuri) per munte
	
	# MATRICE DE PUNCTE 3D FLUIDE: Generăm mai întâi rețeaua ondulată natural după Noise
	var puncte: Array = []
	for x in range(rezolutie + 1):
		puncte.append([])
		for z in range(rezolutie + 1):
			var px = start_x + (x * (dimensiune_chunk / rezolutie))
			var pz = start_z + (z * (dimensiune_chunk / rezolutie))
			var py = zgomot.get_noise_2d(px, pz) * inaltime_maxima
			puncte[x].append(Vector3(px, py, pz))

	# RECONSTRUCȚIE PRIN TRIUNGHIURI INDEXATE: Uniunea fină a punctelor (stil relief muntos)
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	for x in range(rezolutie):
		for z in range(rezolutie):
			var p00 = puncte[x][z]
			var p10 = puncte[x+1][z]
			var p01 = puncte[x][z+1]
			var p11 = puncte[x+1][z+1]
			
			# Desenăm poligoanele netede
			st.set_normal(Vector3.UP)
			st.add_vertex(p00)
			st.set_normal(Vector3.UP)
			st.add_vertex(p10)
			st.set_normal(Vector3.UP)
			st.add_vertex(p01)
			
			st.set_normal(Vector3.UP)
			st.add_vertex(p10)
			st.set_normal(Vector3.UP)
			st.add_vertex(p11)
			st.set_normal(Vector3.UP)
			st.add_vertex(p01)
			
	st.generate_normals()
	var mesh_final = st.commit()
	
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh_final
	mesh_instance.material_override = material_sol # Forțează iarbă verde opacă
	mesh_instance.custom_aabb = mesh_final.get_aabb()
	corp_static.add_child(mesh_instance)
	
	# Coliziune fluidă exact după relieful muntelui! Săgețile se înfig perfect
	var forma_col = CollisionShape3D.new()
	forma_col.shape = mesh_final.create_trimesh_shape()
	corp_static.add_child(forma_col)
	
	add_child(corp_static)
	
	# --- GENEZARE COPACI ȘI IARBĂ ---
	# Plasăm copaci și iarbă doar în chunk-urile non-centrale pentru a evita spawn-ul
	if cx != 0 or cz != 0:
		var pas_copaci = max(2, int(8.0 / densitate_copaci))
		var pas_iarba = max(1, int(2.0 / densitate_iarba))
		
		for x in range(0, int(dimensiune_chunk), pas_copaci):
			for z in range(0, int(dimensiune_chunk), pas_copaci):
				var px = start_x + x + randf_range(-1.0, 1.0)
				var pz = start_z + z + randf_range(-1.0, 1.0)
				
				# Folosim noise-ul de copaci pentru distribuție naturală
				var val_copac = zgomot_copaci.get_noise_2d(px, pz)
				var inaltime_sol = zgomot.get_noise_2d(px, pz) * inaltime_maxima
				
				# Plasează copac doar dacă nu e prea sus pe munți și noise e pozitiv
				if val_copac > (1.0 - densitate_copaci) and inaltime_sol < inaltime_maxima * 0.7:
					_creaza_copac(nod_vegetatie, px, pz)
		
		# Iarbă pretutindeni (include și lângă copaci)
		for x in range(0, int(dimensiune_chunk), pas_iarba):
			for z in range(0, int(dimensiune_chunk), pas_iarba):
				var px = start_x + x + randf_range(-0.3, 0.3)
				var pz = start_z + z + randf_range(-0.3, 0.3)
				var inaltime_sol = zgomot.get_noise_2d(px, pz) * inaltime_maxima
				
				# Iarba doar la înălțimi medii spre joase
				if inaltime_sol < inaltime_maxima * 0.8:
					_creaza_iarba(nod_vegetatie, px, pz)
	
	# SPAWNER LA FIECARE 5 CHUNK-URI
	if not spawner_e_gata_pe_chunk.has(cheie):
		spawner_e_gata_pe_chunk[cheie] = true
		if (cx != 0 or cz != 0) and (cx % 5 == 0) and (cz % 5 == 0):
			_plaseaza_spawner_pe_chunk(start_x + (dimensiune_chunk / 2.0), start_z + (dimensiune_chunk / 2.0))
			
			# Funcție liberă pentru structurile tale viitoare
			var inaltime_centru = zgomot.get_noise_2d(start_x + (dimensiune_chunk / 2.0), start_z + (dimensiune_chunk / 2.0)) * inaltime_maxima
			_genereaza_structuri_viitoare(start_x + (dimensiune_chunk / 2.0), inaltime_centru, start_z + (dimensiune_chunk / 2.0))

func _plaseaza_spawner_pe_chunk(pos_x: float, pos_z: float) -> void:
	var scena_spawner = load("res://SpawnerInamici.tscn") as PackedScene
	if scena_spawner:
		var s = scena_spawner.instantiate()
		get_parent().add_child.call_deferred(s)
		var inaltime_sol = zgomot.get_noise_2d(pos_x, pos_z) * inaltime_maxima
		s.position = Vector3(pos_x, inaltime_sol + 8.0, pos_z)

func _genereaza_structuri_viitoare(px: float, py: float, pz: float) -> void:
	pass

func _creaza_copac(parent_node: Node3D, px: float, pz: float) -> void:
	var inaltime_sol = zgomot.get_noise_2d(px, pz) * inaltime_maxima
	var offset_y = inaltime_sol + 0.1
	
	# Trunchiul copacului
	var trunchi = MeshInstance3D.new()
	var cilinder = CylinderMesh.new()
	cilinder.top_radius = 0.2
	cilinder.bottom_radius = 0.3
	cilinder.height = inaltime_copac
	trunchi.mesh = cilinder
	trunchi.material_override = material_copac_trunchi
	trunchi.position = Vector3(px, offset_y + (inaltime_copac / 2.0), pz)
	trunchi.rotation.y = randf_range(0, TAU)
	parent_node.add_child(trunchi)
	
	# Frunzele (o sferă mare în vârf)
	var frunze = MeshInstance3D.new()
	var sfera = SphereMesh.new()
	sfera.radius = 1.5
	sfera.height = 3.0
	frunze.mesh = sfera
	frunze.material_override = material_copac_frunze
	frunze.position = Vector3(px, offset_y + inaltime_copac + 1.0, pz)
	frunze.rotation.y = randf_range(0, TAU)
	parent_node.add_child(frunze)
	
	# Coliziune pentru trunchi (ca jucătorul să nu treacă prin copac)
	var col_trunchi = StaticBody3D.new()
	var col_forma = CollisionShape3D.new()
	var forma_col = CylinderShape3D.new()
	forma_col.radius = 0.4
	forma_col.height = inaltime_copac + 1.0
	col_forma.shape = forma_col
	col_trunchi.add_child(col_forma)
	col_trunchi.position = Vector3(px, offset_y + (inaltime_copac / 2.0), pz)
	col_trunchi.collision_layer = 1
	col_trunchi.collision_mask = 7
	add_child(col_trunchi)

func _creaza_iarba(parent_node: Node3D, px: float, pz: float) -> void:
	var inaltime_sol = zgomot.get_noise_2d(px, pz) * inaltime_maxima
	
	# Plante mici de iarbă
	for _i in range(3):
		var iarba = MeshInstance3D.new()
		var blade = BoxMesh.new()
		blade.size = Vector3(0.05, 0.3 + randf() * 0.3, 0.05)
		iarba.mesh = blade
		iarba.material_override = material_iarba
		iarba.position = Vector3(
			px + randf_range(-0.5, 0.5),
			inaltime_sol + 0.15,
			pz + randf_range(-0.5, 0.5)
		)
		iarba.rotation.y = randf_range(0, TAU)
		iarba.rotation.x = randf_range(-0.2, 0.2)
		parent_node.add_child(iarba)
