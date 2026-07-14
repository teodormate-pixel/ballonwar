class_name CustomVoxelGenerator
extends VoxelGeneratorScript

# Folosim variabile simple pentru frecvențe, ca să nu accesăm resurse globale din thread-uri
var terrain_freq: float = 0.005
var cave_freq: float = 0.03

func _get_used_channels_mask() -> int:
	return 1 << VoxelBuffer.CHANNEL_SDF

# Generarea se face direct, fără stocare intermediară în tablouri (Prevenire Crash)
func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, lod: int) -> void:
	var size = out_buffer.get_size()
	
	# Creăm instanțe locale de Noise UNICE pentru acest Thread curent.
	# Aceasta este CHEIA pentru a preveni crash-ul fără erori în Godot!
	var noise_terrain = FastNoiseLite.new()
	noise_terrain.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_terrain.frequency = terrain_freq
	
	var noise_caves = FastNoiseLite.new()
	noise_caves.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_caves.frequency = cave_freq
	
	# Parcurgem chunk-ul în siguranță
	for z in range(size.z):
		for y in range(size.y):
			for x in range(size.x):
				# Calculăm poziția globală reală pe axele lumii
				var gx = (x + origin_in_voxels.x) << lod
				var gy = (y + origin_in_voxels.y) << lod
				var gz = (z + origin_in_voxels.z) << lod
				
				# 1. Forma de bază a munților (SDF de vară)
				var t_noise = noise_terrain.get_noise_2d(gx, gz) * 35.0
				var base_sdf = gy - t_noise
				
				# 2. Sistemul de peșteri realiste sub pământ
				var final_sdf = base_sdf
				if gy < t_noise + 2.0:
					var c_noise = abs(noise_caves.get_noise_3d(gx, gy, gz))
					if c_noise < 0.11: # Cu cât numărul e mai mic, cu atât peștera e mai strâmtă
						final_sdf = 2.0 # 2.0 în SDF înseamnă AER / Gol organic
				
				# Salvăm valoarea curată în canalul de formă (CHANNEL_SDF)
				out_buffer.set_voxel_f(final_sdf, x, y, z, VoxelBuffer.CHANNEL_SDF)
