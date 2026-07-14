class_name SmoothTerrainGenerator
extends VoxelGeneratorScript

@export var world_seed: int = 0
@export var terrain_frequency: float = 0.002
@export var terrain_amplitude: float = 55.0
@export var water_level: float = -15.0

func _get_used_channels_mask() -> int:
	return VoxelBuffer.CHANNEL_SDF_BIT

func _generate_block(out_buffer: VoxelBuffer, origin: Vector3i, _lod: int) -> void:
	var sz: Vector3i = out_buffer.get_size()
	var ns: FastNoiseLite = FastNoiseLite.new()
	ns.seed = world_seed + 1
	ns.frequency = terrain_frequency
	ns.noise_type = FastNoiseLite.TYPE_SIMPLEX
	for oz in range(sz.z):
		var wz: int = origin.z + oz
		for ox in range(sz.x):
			var wx: int = origin.x + ox
			var surface_y: float = ns.get_noise_2d(float(wx), float(wz)) * terrain_amplitude
			for oy in range(sz.y):
				var wy: int = origin.y + oy
				var sdf: float = surface_y - float(wy)
				out_buffer.set_voxel_f(sdf, ox, oy, oz, VoxelBuffer.CHANNEL_SDF)

func get_surface_height_at(wx: float, wz: float) -> float:
	var ns: FastNoiseLite = FastNoiseLite.new()
	ns.seed = world_seed + 1
	ns.frequency = terrain_frequency
	ns.noise_type = FastNoiseLite.TYPE_SIMPLEX
	return ns.get_noise_2d(float(wx), float(wz)) * terrain_amplitude
