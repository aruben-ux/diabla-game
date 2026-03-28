shader_type spatial;
render_mode unshaded, cull_front;

// Outline drawn by rendering back faces slightly expanded
uniform vec4 outline_color : source_color = vec4(1.0, 0.8, 0.2, 1.0);
uniform float outline_width : hint_range(0.0, 0.1) = 0.025;

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
