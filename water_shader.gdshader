shader_type spatial;
render_mode unshaded, blend_mix;

uniform vec4 water_color : source_color = vec4(0.05, 0.40, 0.75, 0.75);
uniform float wave_speed : hint_range(0.0, 3.0) = 0.6;
uniform float wave_strength : hint_range(0.0, 0.15) = 0.06;

void fragment() {
	vec2 uv = UV * 4.0;
	float wave = sin(uv.x * 2.0 + TIME * wave_speed) * 0.5 + 0.5;
	wave += cos(uv.y * 1.7 + TIME * wave_speed * 0.8) * 0.5;
	wave += sin((uv.x + uv.y) * 1.3 + TIME * wave_speed * 1.2) * 0.3;
	wave = wave / 1.3;
	float alpha_wave = water_color.a * (0.85 + wave * wave_strength);
	ALBEDO = water_color.rgb;
	ALPHA = alpha_wave;
}
