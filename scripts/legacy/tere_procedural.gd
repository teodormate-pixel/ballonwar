extends Node3D

# --- SETĂRI PENTRU DIMENSIUNEA GLOBALĂ ---
@export var dimensiune_teren_chunks: int = 16 
@export var dimensiune_chunk_celule: int = 32 
@export var dimensiune_celula: float = 1.5    
@export var inaltime_maxima: float = 35.0     

@export_color_no_alpha var culoare_teren: Color = Color("2e6f40") # Verdele de bază pentru sol

# --- SETĂRI DETALII IARBĂ 3D OPTIMIZATĂ ---
@export var densitate_iarba_per_chunk: int = 1200 # Iarba deasă pe fiecare bucată

# NOU: O listă de nuanțe diferite de verde pentru un aspect 100% natural
var nuante_verde: Array[Color] = [
	Color("23522a"), # Verde închis standard
	Color("2e6636"), # Verde mediu viu
	Color("3b7d45"), # Verde deschis/proaspăt
	Color("4a783b"), # Verde măsliniu/pădure
	Color("57732a")  # Verde-gălbui (iarbă ușor uscată de soare)
]

var zgomot: FastNoiseLite
var teren_este_gata: bool = false 

var dimensiune_teren: int:
	get:
		return dimensiune_teren_chunks * dimensiune_chunk_celule

func _ready() -> void:
	_configureaza_zgomot()
	_genereaza_toate_chunkurile()

func _configureaza_zgomot() -> void:
	zgomot = FastNoiseLite.new()
	zgomot.seed = Time.get_ticks_msec() + randi()
	zgomot.noise_type = FastNoiseLite.TYPE_PERLIN
	zgomot.frequency = 0.005 

func _genereaza_toate_chunkurile() -> void:
	var material_sol = StandardMaterial3D.new()
	material_sol.albedo_color = culoare_teren
	material_sol.roughness = 0.9

	var material_iarba_3d = StandardMaterial3D.new()
	# IMPORTANT: Nu mai setăm albedo_color fix aici, lăsăm culorile din MultiMesh să controleze nuanța!
	material_iarba_3d.vertex_color_use_as_albedo = true # Activează suportul pentru nuanțe diferite
	material_iarba_3d.roughness = 1.0
	material_iarba_3d.cull_mode = BaseMaterial3D.CULL_DISABLED

	for cz in range(dimensiune_teren_chunks):
		for cx in range(dimensiune_teren_chunks):
			_creaza_chunk(cx, cz, material_sol, material_iarba_3d)
			
	await get_tree().physics_frame
	
	teren_este_gata = true
	print("[Teren Nuante] Harta s-a generat! Fiecare fir de iarbă are o nuanță unică de verde.")

func _creaza_chunk(chunk_x: int, chunk_z: int, mat_sol: Material, mat_iarba: Material) -> void:
	var chunk_body = StaticBody3D.new()
	chunk_body.collision_layer = 1
	chunk_body.collision_mask = 1
	add_child(chunk_body)
	
	var chunk_global_x = chunk_x * dimensiune_chunk_celule * dimensiune_celula
	var chunk_global_z = chunk_z * dimensiune_chunk_celule * dimensiune_celula
	chunk_body.global_position = Vector3(chunk_global_x, 0, chunk_global_z)

	var start_celula_x = chunk_x * dimensiune_chunk_celule
	var start_celula_z = chunk_z * dimensiune_chunk_celule
	
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var vertices_lista = PackedVector3Array()
	
	for z in range(dimensiune_chunk_celule + 1):
		for x in range(dimensiune_chunk_celule + 1):
			var celula_globala_x = (start_celula_x + x) * dimensiune_celula
			var celula_globala_z = (start_celula_z + z) * dimensiune_celula
			
			var inaltime_y = zgomot.get_noise_2d(celula_globala_x, celula_globala_z) * inaltime_maxima
			
			var local_x = x * dimensiune_celula
			var local_z = z * dimensiune_celula
			vertices_lista.append(Vector3(local_x, inaltime_y, local_z))

	for z in range(dimensiune_chunk_celule):
		for x in range(dimensiune_chunk_celule):
			var i_stanga_sus = x + z * (dimensiune_chunk_celule + 1)
			var i_dreapta_sus = (x + 1) + z * (dimensiune_chunk_celule + 1)
			var i_stanga_jos = x + (z + 1) * (dimensiune_chunk_celule + 1)
			var i_dreapta_jos = (x + 1) + (z + 1) * (dimensiune_chunk_celule + 1)
			
			st.add_vertex(vertices_lista[i_stanga_sus])
			st.add_vertex(vertices_lista[i_dreapta_sus])
			st.add_vertex(vertices_lista[i_stanga_jos])
			
			st.add_vertex(vertices_lista[i_dreapta_sus])
			st.add_vertex(vertices_lista[i_dreapta_jos])
			st.add_vertex(vertices_lista[i_stanga_jos])

	st.generate_normals()
	var a_mesh = st.commit()
	
	var mi = MeshInstance3D.new()
	mi.mesh = a_mesh
	mi.material_override = mat_sol
	
	var marime_chunk_metri = dimensiune_chunk_celule * dimensiune_celula
	mi.custom_aabb = AABB(Vector3(0, -inaltime_maxima, 0), Vector3(marime_chunk_metri, inaltime_maxima * 2, marime_chunk_metri))
	chunk_body.add_child(mi)
	
	# =====================================================================
	# GENERARE IARBĂ CU NUANȚE DE VERDE DINAMICE
	# =====================================================================
	if densitate_iarba_per_chunk > 0:
		var multimesh_instance = MultiMeshInstance3D.new()
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		
		# NOU: Îi spunem lui MultiMesh că vrem să dăm culori diferite fiecărui fir în parte!
		mm.use_colors = true
		
		var st_fir = SurfaceTool.new()
		st_fir.begin(Mesh.PRIMITIVE_TRIANGLES)
		
		var w: float = 0.12
		var h: float = 0.35
		
		st_fir.add_vertex(Vector3(-w, 0, 0))
		st_fir.add_vertex(Vector3(w, 0, 0))
		st_fir.add_vertex(Vector3(0, h, 0))
		
		st_fir.add_vertex(Vector3(-w * 0.5, 0, w * 0.86))
		st_fir.add_vertex(Vector3(w * 0.5, 0, -w * 0.86))
		st_fir.add_vertex(Vector3(0, h, 0))
		
		st_fir.add_vertex(Vector3(-w * 0.5, 0, -w * 0.86))
		st_fir.add_vertex(Vector3(w * 0.5, 0, w * 0.86))
		st_fir.add_vertex(Vector3(0, h, 0))
		
		st_fir.generate_normals()
		var model_fir_mesh = st_fir.commit()
		model_fir_mesh.surface_set_material(0, mat_iarba)
		
		mm.mesh = model_fir_mesh
		mm.instance_count = densitate_iarba_per_chunk
		
		for j in range(densitate_iarba_per_chunk):
			var rand_x = randf_range(0, marime_chunk_metri)
			var rand_z = randf_range(0, marime_chunk_metri)
			
			var global_x = chunk_global_x + rand_x
			var global_z = chunk_global_z + rand_z
			var inaltime_y = zgomot.get_noise_2d(global_x, global_z) * inaltime_maxima
			
			var pos = Vector3(rand_x, inaltime_y, rand_z)
			var rot_y = randf_range(0, PI)
			
			var scara_x_z = randf_range(0.8, 1.2)
			var scara_inaltime_y = randf_range(0.5, 1.8) 
			var scale_vec = Vector3(scara_x_z, scara_inaltime_y, scara_x_z)
			
			var xform = Transform3D().rotated(Vector3.UP, rot_y).scaled(scale_vec)
			xform.origin = pos
			
			mm.set_instance_transform(j, xform)
			
			# NOU: Alegem o nuanță la întâmplare din lista noastră de verzi pentru acest fir!
			var culoare_aleatorie = nuante_verde[randi() % nuante_verde.size()]
			mm.set_instance_color(j, culoare_aleatorie)
			
		multimesh_instance.multimesh = mm
		chunk_body.add_child(multimesh_instance)
	# =====================================================================
	
	# Pasul 4: Configurare formă de coliziune (HeightMap)
	var col_shape = CollisionShape3D.new()
	var forma_grosime = HeightMapShape3D.new()
	forma_grosime.map_width = dimensiune_chunk_celule + 1
	forma_grosime.map_depth = dimensiune_chunk_celule + 1
	
	var date_inaltime = PackedFloat32Array()
	date_inaltime.resize((dimensiune_chunk_celule + 1) * (dimensiune_chunk_celule + 1))
	for i in range(vertices_lista.size()):
		date_inaltime[i] = vertices_lista[i].y
		
	forma_grosime.map_data = date_inaltime
	col_shape.shape = forma_grosime
	col_shape.scale = Vector3(dimensiune_celula, 1.0, dimensiune_celula)
	
	var jumatate_chunk_x = marime_chunk_metri / 2.0
	var jumatate_chunk_z = marime_chunk_metri / 2.0
	col_shape.position = Vector3(jumatate_chunk_x, 0, jumatate_chunk_z)
	chunk_body.add_child(col_shape)
