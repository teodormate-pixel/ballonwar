shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_disabled;

// =============================================================================
// Voxel Terrain Multi-Material Shader — Triplanar PBR
// =============================================================================
// Blends between Grass (flat surface), Stone (steep/deep), Dirt (transition),
// Sand (desert, low altitude), Snow (high altitude) based on world normal
// angle and surface depth estimate.
// =============================================================================

// ---- Grass (Poliigon) ----
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D grass_rough : source_color, filter_linear_mipmap_anisotropic;

// ---- Stone (Rock) ----
uniform sampler2D stone_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D stone_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D stone_rough : source_color, filter_linear_mipmap_anisotropic;

// ---- Dirt ----
uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D dirt_rough : source_color, filter_linear_mipmap_anisotropic;

// ---- Sand ----
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D sand_rough : source_color, filter_linear_mipmap_anisotropic;

// ---- Snow ----
uniform sampler2D snow_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D snow_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D snow_rough : source_color, filter_linear_mipmap_anisotropic;

// ---- Controls ----
uniform float tex_scale : hint_range(0.001, 0.1) = 0.02;
uniform float stone_slope : hint_range(0.0, 1.0) = 0.45;

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying vec3 v_local_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = mat3(MODEL_MATRIX) * NORMAL.xyz;
	v_local_pos = VERTEX.xyz;
}

// ---- triplanar sample ----
vec4 triplanar_albedo(sampler2D tex, vec3 pos, vec3 normal) {
	normal = abs(normalize(normal));
	normal = pow(normal, vec3(6.5));
	normal /= (normal.x + normal.y + normal.z);
	vec3 s = pos * tex_scale;
	vec4 cx = texture(tex, s.yz);
	vec4 cy = texture(tex, s.xz);
	vec4 cz = texture(tex, s.xy);
	return cx * normal.x + cy * normal.y + cz * normal.z;
}

vec3 triplanar_normal(sampler2D tex, vec3 pos, vec3 blend) {
	vec3 s = pos * tex_scale;
	vec3 samp_x = texture(tex, s.yz).rgb * 2.0 - 1.0;
	vec3 samp_y = texture(tex, s.xz).rgb * 2.0 - 1.0;
	vec3 samp_z = texture(tex, s.xy).rgb * 2.0 - 1.0;
	return samp_x * blend.x + samp_y * blend.y + samp_z * blend.z;
}

vec3 blend_weights(vec3 normal) {
	normal = abs(normalize(normal));
	normal = pow(normal, vec3(4.0));
	normal /= (normal.x + normal.y + normal.z);
	return normal;
}

void fragment() {
	vec3 N = normalize(v_world_normal);
	float steepness = 1.0 - abs(N.y);
	float height = v_world_pos.y;
	vec3 bw = blend_weights(N);

	// ---- Determine material blend factors ----
	// Below Y=-10: everything is stone (underground)
	float underground = smoothstep(-10.0, -25.0, height);

	// Stone: steep cliffs + underground
	float stone_w = smoothstep(stone_slope, stone_slope + 0.25, steepness);
	stone_w = max(stone_w, underground);

	// Snow: high altitude, flat, not underground
	float snow_w = smoothstep(35.0, 60.0, height);
	snow_w *= smoothstep(0.5, 0.0, steepness);
	snow_w *= 1.0 - underground;

	// Sand: low altitude, flat, not underground
	float sand_w = smoothstep(10.0, -5.0, height);
	sand_w *= smoothstep(0.5, 0.0, steepness);
	sand_w -= snow_w;
	sand_w = max(sand_w, 0.0);
	sand_w *= 1.0 - underground;

	// Dirt: transition layer below grass
	float dirt_w = smoothstep(-14.0, -18.0, height);
	dirt_w -= stone_w;
	dirt_w = max(dirt_w, 0.0);
	dirt_w *= smoothstep(0.5, 0.0, steepness);
	dirt_w *= 1.0 - underground;

	// Grass: default for flat surfaces at mid altitude, not underground
	float grass_w = 1.0 - (stone_w + snow_w + sand_w + dirt_w);
	grass_w = max(grass_w, 0.0);
	grass_w *= 1.0 - underground;
	grass_w *= smoothstep(0.6, 0.0, steepness); // only flat surfaces

	// Normalize weights
	float total = grass_w + dirt_w + stone_w + sand_w + snow_w;
	if (total > 0.001) {
		grass_w /= total; dirt_w /= total; stone_w /= total;
		sand_w /= total; snow_w /= total;
	} else {
		grass_w = 1.0;
	}

	// ---- Sample textures ----
	vec4 grass_col  = triplanar_albedo(grass_albedo, v_world_pos, N);
	vec3 grass_nrm  = triplanar_normal(grass_normal, v_world_pos, bw);
	float grass_ro  = triplanar_albedo(grass_rough, v_world_pos, N).r;

	vec4 stone_col  = triplanar_albedo(stone_albedo, v_world_pos, N);
	vec3 stone_nrm  = triplanar_normal(stone_normal, v_world_pos, bw);
	float stone_ro  = triplanar_albedo(stone_rough, v_world_pos, N).r;

	vec4 dirt_col   = triplanar_albedo(dirt_albedo, v_world_pos, N);
	vec3 dirt_nrm   = triplanar_normal(dirt_normal, v_world_pos, bw);
	float dirt_ro   = triplanar_albedo(dirt_rough, v_world_pos, N).r;

	vec4 sand_col   = triplanar_albedo(sand_albedo, v_world_pos, N);
	vec3 sand_nrm   = triplanar_normal(sand_normal, v_world_pos, bw);
	float sand_ro   = triplanar_albedo(sand_rough, v_world_pos, N).r;

	vec4 snow_col   = triplanar_albedo(snow_albedo, v_world_pos, N);
	vec3 snow_nrm   = triplanar_normal(snow_normal, v_world_pos, bw);
	float snow_ro   = triplanar_albedo(snow_rough, v_world_pos, N).r;

	// ---- Blend ----
	ALBEDO = (grass_col.rgb * grass_w + dirt_col.rgb * dirt_w +
	          stone_col.rgb * stone_w + sand_col.rgb * sand_w +
	          snow_col.rgb * snow_w);

	vec3 blend_nrm = grass_nrm * grass_w + dirt_nrm * dirt_w +
	                 stone_nrm * stone_w + sand_nrm * sand_w +
	                 snow_nrm * snow_w;
	NORMAL_MAP = vec3(normalize(blend_nrm));

	ROUGHNESS = grass_ro * grass_w + dirt_ro * dirt_w +
	            stone_ro * stone_w + sand_ro * sand_w +
	            snow_ro * snow_w;

	METALLIC = 0.0;
	AO = 1.0;
	SPECULAR = 0.5;
}
