shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2DArray terrain_albedo : source_color, filter_linear_mipmap;
uniform sampler2DArray terrain_normal : hint_normal, filter_linear_mipmap;
uniform sampler2DArray terrain_height : hint_default_white, filter_linear_mipmap;
uniform float texture_scale : hint_range(0.01, 0.5) = 0.1;
uniform float triplanar_sharpness : hint_range(1.0, 20.0) = 10.0;
uniform float displacement_scale : hint_range(0.0, 2.0) = 0.15;

varying vec3 v_wpos;

void vertex() {
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float block_idx = round(COLOR.a * 3.0);
	vec2 uv = wpos.xz * texture_scale;
	float h = texture(terrain_height, vec3(uv, block_idx)).r;
	VERTEX.y += (h - 0.5) * displacement_scale;
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float block_idx = round(COLOR.a * 3.0);
	vec3 wpos = v_wpos;
	vec3 wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);

	vec3 blend = abs(wnorm);
	blend = pow(blend, vec3(triplanar_sharpness));
	blend /= (blend.x + blend.y + blend.z);

	float s = texture_scale;
	vec2 uv_x = wpos.zy * s;
	vec2 uv_y = wpos.xz * s;
	vec2 uv_z = wpos.xy * s;

	vec3 albedo = texture(terrain_albedo, vec3(uv_x, block_idx)).rgb * blend.x
				+ texture(terrain_albedo, vec3(uv_y, block_idx)).rgb * blend.y
				+ texture(terrain_albedo, vec3(uv_z, block_idx)).rgb * blend.z;

	vec3 nrm_x = texture(terrain_normal, vec3(uv_x, block_idx)).rgb * 2.0 - 1.0;
	vec3 nrm_y = texture(terrain_normal, vec3(uv_y, block_idx)).rgb * 2.0 - 1.0;
	vec3 nrm_z = texture(terrain_normal, vec3(uv_z, block_idx)).rgb * 2.0 - 1.0;
	vec3 bump = normalize(nrm_x * blend.x + nrm_y * blend.y + nrm_z * blend.z);

	ALBEDO = albedo;
	ROUGHNESS = 0.75;
	NORMAL_MAP = bump;
}
