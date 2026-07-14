extends VoxelGeneratorScript

enum M { AIR=0, GRASS=1, DIRT=2, STONE=3, SAND=4, SNOW=5, GRAVEL=6, CLAY=7 }

@export var world_seed: int = 0
@export var water_level: float = 10.0
@export var ph_min: float = -5.0;  @export var ph_max: float = 12.0
@export var dh_min: float = -8.0;  @export var dh_max: float = 8.0
@export var fh_min: float =   0.0;  @export var fh_max: float = 18.0
@export var sh_min: float = -10.0;  @export var sh_max: float = 5.0
@export var hh_min: float =   8.0;  @export var hh_max: float = 22.0
@export var nh_min: float =  15.0;  @export var nh_max: float = 25.0
@export var tf: float = 0.005; @export var bf: float = 0.0012
@export var rf: float = 0.012; @export var ot: float = -0.65; @export var rt: float = 0.46
@export var ridge_strength: float = 0.6
@export var ridge_freq: float = 0.022
@export var ce: bool = true; @export var cf: float = 0.025; @export var ct: float = 0.06; @export var cmd: float = 6.0


func _get_used_channels_mask() -> int:
	return VoxelBuffer.CHANNEL_SDF_BIT | VoxelBuffer.CHANNEL_TYPE_BIT


func _generate_block(out: VoxelBuffer, org: Vector3i, _lod: int) -> void:
	var sz: Vector3i = out.get_size()
	var nh: FastNoiseLite = _noise(world_seed + 1, tf, 6)
	var nb: FastNoiseLite = _noise(world_seed + 3, bf, 3)
	var nr: FastNoiseLite = _noise(world_seed + 5, rf, 2)
	var nc: FastNoiseLite = _noise(world_seed + 7, cf, 3)
	var nd: FastNoiseLite = _noise2(world_seed + 9, 0.035, 3)
	var nw: FastNoiseLite = _smooth(world_seed + 11, 0.006, 2)
	var ng: FastNoiseLite = _ridge(world_seed + 13, ridge_freq, 5)
	for oz in range(sz.z):
		var wz: int = org.z + oz
		for ox in range(sz.x):
			var wx: int = org.x + ox
			var wxf: float = float(wx); var wzf: float = float(wz)
			var br: float = nb.get_noise_2d(wxf, wzf)
			var io: bool = br < ot
			var hm: float; var hx: float; var cv: float; var sm: int
			if io:
				hm = water_level - 12.0; hx = water_level - 3.0; cv = 0.9; sm = M.SAND
			else:
				var hms: Array[float] = [ph_min, dh_min, fh_min, sh_min, hh_min, nh_min]
				var hxs: Array[float] = [ph_max, dh_max, fh_max, sh_max, hh_max, nh_max]
				var cvs: Array[float] = [0.95, 0.92, 0.95, 0.90, 1.05, 1.05]
				var mts: Array[int]   = [M.GRASS, M.SAND, M.GRASS, M.CLAY, M.STONE, M.SNOW]
				hm = _bl(br, hms, ot); hx = _bl(br, hxs, ot); cv = _bl(br, cvs, ot)
				sm = mts[_bi(br, ot)]
			var warp_x: float = nw.get_noise_2d(wxf, wzf) * 14.0
			var warp_z: float = nw.get_noise_2d(wxf + 37.0, wzf - 23.0) * 14.0
			var bn: float = nh.get_noise_2d((wxf + warp_x), (wzf + warp_z))
			var nm: float = clampf(bn * 0.5 + 0.5, 0.0, 1.0)
			nm = pow(nm, cv)
			var alt_frac: float = clampf((_hmax_alt(hx) - 10.0) / 55.0, 0.0, 1.0)
			var ridge_raw: float = ng.get_noise_2d((wxf + warp_x) * 1.3, (wzf + warp_z) * 1.3)
			var ridge: float = pow(absf(ridge_raw), 2.3) * ridge_strength * alt_frac
			var detail: float = nd.get_noise_2d(wxf * 0.035, wzf * 0.035) * 0.08
			nm = clampf(nm + ridge + detail + (ridge * 0.15) * alt_frac, 0.0, 1.0)
			var sy: float = lerpf(hm, hx, nm)
			var ir: bool = false
			if not io:
				var rv: float = nr.get_noise_2d(wxf * 0.35, wzf * 0.35)
				if absf(rv) > rt:
					ir = true; sy = minf(sy, water_level - (absf(rv) - rt) * 15.0)
			var ss: bool = false
			if not io:
				var sr: float = _sa(nh, nb, nw, nd, ng, ot, float(wx + 2), wzf)
				var sf: float = _sa(nh, nb, nw, nd, ng, ot, wxf, float(wz + 2))
				if absf(sy - sr) > 4.0 or absf(sy - sf) > 4.0: ss = true
			var hc: bool = false
			if ce and not io:
				var d: int = int(cmd)
				while d < 90:
					if absf(nc.get_noise_3d(wxf, sy - float(d), wzf)) < ct:
						hc = true
						break
					d += 8
			for oy in range(sz.y):
				var wy: int = org.y + oy; var wyf: float = float(wy)
				var sd: float = sy - wyf
				if wyf < -75.0: sd = 999.0
				var ic: bool = false
				if sd > 0.0 and wyf >= -75.0 and hc:
					var dp: float = sy - wyf
					if dp > cmd:
						if absf(nc.get_noise_3d(wxf, wyf * 0.5, wzf)) < ct:
							sd = -10.0; ic = true
				if wyf < water_level and sy < water_level and not ir and not ic:
					sd = maxf(sd, water_level - wyf)
				var mt: int = M.AIR
				if sd > 0.0:
					var dp: float = sy - wyf
					if ic: mt = M.STONE
					elif ss and dp < 8.0: mt = M.STONE
					elif dp <= 2.0: mt = M.SAND if io else sm
					elif dp <= 6.0: mt = M.DIRT
					elif dp <= 10.0: mt = M.GRAVEL
					else: mt = M.STONE
				out.set_voxel_f(sd, ox, oy, oz, VoxelBuffer.CHANNEL_SDF)
				out.set_voxel(mt, ox, oy, oz, VoxelBuffer.CHANNEL_TYPE)


func _sa(nh: FastNoiseLite, nb: FastNoiseLite, nw: FastNoiseLite, nd: FastNoiseLite, ng: FastNoiseLite, oth: float, wxf: float, wzf: float) -> float:
	var br: float = nb.get_noise_2d(wxf, wzf)
	if br < oth:
		var bn: float = nh.get_noise_2d(wxf, wzf)
		return lerpf(water_level - 12.0, water_level - 3.0, pow(clampf(bn * 0.5 + 0.5, 0.0, 1.0), 0.9))
	var hms: Array[float] = [ph_min, dh_min, fh_min, sh_min, hh_min, nh_min]
	var hxs: Array[float] = [ph_max, dh_max, fh_max, sh_max, hh_max, nh_max]
	var cvs: Array[float] = [0.95, 0.92, 0.95, 0.90, 1.05, 1.05]
	var hm: float = _bl(br, hms, oth); var hx: float = _bl(br, hxs, oth)
	var cv: float = _bl(br, cvs, oth)
	var warp_x: float = nw.get_noise_2d(wxf, wzf) * 14.0
	var warp_z: float = nw.get_noise_2d(wxf + 37.0, wzf - 23.0) * 14.0
	var bn: float = nh.get_noise_2d((wxf + warp_x), (wzf + warp_z))
	var nm: float = clampf(bn * 0.5 + 0.5, 0.0, 1.0)
	nm = pow(nm, cv)
	var alt_frac: float = clampf(_hmax_alt(hx) / 55.0, 0.0, 1.0)
	var ridge_raw: float = ng.get_noise_2d((wxf + warp_x) * 1.3, (wzf + warp_z) * 1.3)
	var ridge: float = pow(absf(ridge_raw), 2.3) * ridge_strength * alt_frac
	var detail: float = nd.get_noise_2d(wxf * 0.035, wzf * 0.035) * 0.05
	nm = clampf(nm + ridge + detail + (ridge * 0.15) * alt_frac, 0.0, 1.0)
	return lerpf(hm, hx, nm)


func _bi(raw: float, oth: float) -> int:
	var t: float = clampf((raw - oth) / (1.0 - oth), 0.0, 1.0)
	if t <= 0.18: return 0
	elif t <= 0.36: return 1
	elif t <= 0.54: return 2
	elif t <= 0.72: return 3
	elif t <= 0.90: return 4
	return 5


func _bl(raw: float, v: Array, oth: float) -> float:
	var t: float = clampf((raw - oth) / (1.0 - oth), 0.0, 1.0)
	var n: int = v.size()
	if n < 2: return v[0] if n > 0 else 0.0
	var seg: float = 1.0 / float(n - 1)
	var idx: int = clampi(int(t / seg), 0, n - 2)
	var lt: float = clampf((t - float(idx) * seg) / seg, 0.0, 1.0)
	return lerpf(v[idx], v[idx + 1], lt)


func _noise(s: int, freq: float, oct: int) -> FastNoiseLite:
	var n: FastNoiseLite = FastNoiseLite.new()
	n.seed = s; n.frequency = freq
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.fractal_octaves = clampi(oct, 1, 6)
	n.fractal_gain = 0.5; n.fractal_lacunarity = 2.0
	return n


func _noise2(s: int, freq: float, oct: int) -> FastNoiseLite:
	var n: FastNoiseLite = FastNoiseLite.new()
	n.seed = s; n.frequency = freq
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.fractal_octaves = clampi(oct, 1, 4)
	n.fractal_gain = 0.5; n.fractal_lacunarity = 2.0
	return n


func _smooth(s: int, freq: float, oct: int) -> FastNoiseLite:
	var n: FastNoiseLite = FastNoiseLite.new()
	n.seed = s; n.frequency = freq
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_octaves = clampi(oct, 1, 3)
	n.fractal_gain = 0.5; n.fractal_lacunarity = 2.0
	return n


func _ridge(s: int, freq: float, oct: int) -> FastNoiseLite:
	var n: FastNoiseLite = FastNoiseLite.new()
	n.seed = s; n.frequency = freq
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.fractal_octaves = clampi(oct, 1, 6)
	n.fractal_gain = 0.5; n.fractal_lacunarity = 2.0
	return n


func _hmax_alt(hx: float) -> float:
	return hx


func get_surface_height_at(wx: float, wz: float) -> float:
	var ns_h: FastNoiseLite = _noise(world_seed + 1, tf, 6)
	var ns_b: FastNoiseLite = _noise(world_seed + 3, bf, 3)
	var ns_w: FastNoiseLite = _smooth(world_seed + 11, 0.006, 2)
	var ns_d: FastNoiseLite = _noise2(world_seed + 9, 0.035, 3)
	var ns_g: FastNoiseLite = _ridge(world_seed + 13, ridge_freq, 5)
	var br: float = ns_b.get_noise_2d(float(wx), float(wz))
	if br < ot:
		return water_level - 8.0
	var hms: Array[float] = [ph_min, dh_min, fh_min, sh_min, hh_min, nh_min]
	var hxs: Array[float] = [ph_max, dh_max, fh_max, sh_max, hh_max, nh_max]
	var cvs: Array[float] = [0.95, 0.92, 0.95, 0.90, 1.05, 1.05]
	var hm: float = _bl(br, hms, ot); var hx: float = _bl(br, hxs, ot)
	var cv: float = _bl(br, cvs, ot)
	var warp_x: float = ns_w.get_noise_2d(float(wx), float(wz)) * 14.0
	var warp_z: float = ns_w.get_noise_2d(float(wx) + 37.0, float(wz) - 23.0) * 14.0
	var bn: float = ns_h.get_noise_2d((float(wx) + warp_x), (float(wz) + warp_z))
	var nm: float = clampf(bn * 0.5 + 0.5, 0.0, 1.0)
	nm = pow(nm, cv)
	var alt_frac: float = clampf((hx - 10.0) / 55.0, 0.0, 1.0)
	var ridge_raw: float = ns_g.get_noise_2d((float(wx) + warp_x) * 1.3, (float(wz) + warp_z) * 1.3)
	var ridge: float = pow(absf(ridge_raw), 2.3) * ridge_strength * alt_frac
	var detail: float = ns_d.get_noise_2d(float(wx) * 0.035, float(wz) * 0.035) * 0.05
	nm = clampf(nm + ridge + detail + (ridge * 0.15) * alt_frac, 0.0, 1.0)
	return lerpf(hm, hx, nm)
