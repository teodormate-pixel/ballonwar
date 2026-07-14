
extends VoxelLodTerrain

func _ready():
	# 1. Configuram mesher-ul nativ pentru teren neted
	self.mesher = VoxelMesherTransvoxel.new()
	
	# 2. Cream generatorul grafic nativ
	var graph_generator = VoxelGeneratorGraph.new()
	
	# 3. Folosim sistemul simplu bazat pe string-uri (nume text) pentru a adăuga nodurile.
	# Această metodă evită complet erorile de constante de tipul NODE_INPUT_X.
	var x_id = graph_generator.create_node("InputX", Vector2(0, 0))
	var y_id = graph_generator.create_node("InputY", Vector2(0, 50))
	var z_id = graph_generator.create_node("InputZ", Vector2(0, 100))
	
	# Zgomot 2D pentru munții line ai verii
	var noise2d_id = graph_generator.create_node("FastNoise2D", Vector2(200, 0))
	graph_generator.set_node_param(noise2d_id, 0, 0.005) # Frecvența dealurilor
	graph_generator.connect_node_output(x_id, 0, noise2d_id, 0)
	graph_generator.connect_node_output(z_id, 0, noise2d_id, 1)
	
	# Înmulțim zgomotul 2D pentru munti mai înalți
	var multiply_id = graph_generator.create_node("Multiply", Vector2(400, 0))
	graph_generator.set_node_param(multiply_id, 0, 45.0) # Amplitudinea înălțimii
	graph_generator.connect_node_output(noise2d_id, 0, multiply_id, 0)
	
	# Scădem înălțimea Y reală din valoarea munților (Apar dealurile și văile)
	var base_sdf_id = graph_generator.create_node("Subtract", Vector2(600, 20))
	graph_generator.connect_node_output(multiply_id, 0, base_sdf_id, 0)
	graph_generator.connect_node_output(y_id, 0, base_sdf_id, 1)
	
	# Zgomot 3D pentru galerii și peșteri realiste
	var noise3d_id = graph_generator.create_node("FastNoise3D", Vector2(300, 200))
	graph_generator.set_node_param(noise3d_id, 0, 0.03) # Frecvența peșterilor
	graph_generator.connect_node_output(x_id, 0, noise3d_id, 0)
	graph_generator.connect_node_output(y_id, 0, noise3d_id, 1)
	graph_generator.connect_node_output(z_id, 0, noise3d_id, 2)
	
	# Transformăm în valori absolute (Cavități/Tuburi de peșteră)
	var abs_id = graph_generator.create_node("Abs", Vector2(500, 250))
	graph_generator.connect_node_output(noise3d_id, 0, abs_id, 0)
	
	# Setăm mărimea galeriilor (Unde zgomotul este mai mic de 0.12, avem goluri)
	var cave_threshold_id = graph_generator.create_node("LessThan", Vector2(700, 250))
	graph_generator.set_node_param(cave_threshold_id, 0, 0.12)
	graph_generator.connect_node_output(abs_id, 0, cave_threshold_id, 0)
	
	# Combinăm suprafața (dealurile) cu peșterile din adâncuri
	var final_mix_id = graph_generator.create_node("SdfMax", Vector2(900, 100))
	graph_generator.connect_node_output(base_sdf_id, 0, final_mix_id, 0)
	graph_generator.connect_node_output(cave_threshold_id, 0, final_mix_id, 1)
	
	# Nodul de ieșire final obligatoriu
	var output_id = graph_generator.create_node("OutputSDF", Vector2(1100, 100))
	graph_generator.connect_node_output(final_mix_id, 0, output_id, 0)
	
	# Compilăm și activăm structura nativă
	graph_generator.compile()
	self.generator = graph_generator
