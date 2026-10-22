shader_type spatial;
render_mode specular_disabled;

uniform vec4 base_color : source_color = vec4(0.3, 0.5, 0.6, 1.0);
uniform vec4 shadow_tint : source_color = vec4(0.46, 0.57, 0.72, 1.0);
uniform vec4 glow_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float glow_energy : hint_range(0.0, 2.0) = 0.0;
uniform float shade_threshold : hint_range(0.0, 1.0) = 0.35;
uniform float highlight_threshold : hint_range(0.0, 1.0) = 0.75;

void fragment() {
	ALBEDO = base_color.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = glow_color.rgb * glow_energy;
}

void light() {
	float facing = max(dot(NORMAL, LIGHT), 0.0);
	float band = mix(0.40, 0.72, step(shade_threshold, facing));
	band = mix(band, 1.0, step(highlight_threshold, facing));
	vec3 tint = mix(shadow_tint.rgb, vec3(1.0), step(shade_threshold, facing));
	DIFFUSE_LIGHT += tint * LIGHT_COLOR * band * ATTENUATION / PI;
}
