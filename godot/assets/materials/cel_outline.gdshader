shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;

uniform vec4 outline_color : source_color = vec4(0.035, 0.055, 0.09, 1.0);
uniform float outline_width : hint_range(0.0, 0.04) = 0.008;

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
