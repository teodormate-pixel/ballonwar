shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 water_color : source_color = vec4(0.05, 0.30, 0.65, 0.75);
uniform sampler2D water_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D water_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D water_roughness : source_color, filter_linear_mipmap;
uniform float wave_speed : hint_range(0.0, 3.0) = 0.5;
uniform float wave_strength : hint_range(0.0, 0.15) = 0.04;
uniform float tex_scale : hint_range(0.005, 0.1) = 0.015;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.6;

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv1 = v_world_pos.xz * tex_scale;
	vec2 uv2 = v_world_pos.xz * tex_scale * 0.7 + vec2(0.31, 0.47);
	float t = TIME * wave_speed;

	vec2 wave_uv1 = uv1 + vec2(t * 0.12, t * 0.08);
	vec2 wave_uv2 = uv2 + vec2(-t * 0.09, t * 0.11);

	vec3 n1 = texture(water_normal, wave_uv1).rgb * 2.0 - 1.0;
	vec3 n2 = texture(water_normal, wave_uv2).rgb * 2.0 - 1.0;
	vec3 blended_normal = normalize(mix(n1, n2, 0.5) * normal_strength);

	float wave = sin(uv1.x * 8.0 + t * 1.5) * 0.5 + 0.5;
	wave += cos(uv2.y * 6.0 + t * 1.2) * 0.5;
	wave += sin((uv1.x + uv1.y) * 5.0 + t * 1.8) * 0.3;
	wave = wave / 1.3;

	vec4 albedo_sample = texture(water_albedo, mix(wave_uv1, wave_uv2, 0.3));
	float rough = texture(water_roughness, wave_uv1).r;

	ALBEDO = mix(water_color.rgb, albedo_sample.rgb, 0.4);
	NORMAL_MAP = blended_normal;
	ROUGHNESS = mix(0.05, rough, 0.3);
	METALLIC = 0.85;
	SPECULAR = 0.8;
	ALPHA = water_color.a * (0.9 + wave * wave_strength);
}
