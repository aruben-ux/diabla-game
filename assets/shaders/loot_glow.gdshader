shader_type spatial;
render_mode cull_back, unshaded;

// Pulsing glow for loot drops
uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float pulse_speed : hint_range(0.5, 5.0) = 2.0;
uniform float pulse_min : hint_range(0.0, 1.0) = 0.4;
uniform float pulse_max : hint_range(0.5, 3.0) = 1.5;
uniform float glow_strength : hint_range(0.0, 3.0) = 1.0;

void fragment() {
	float pulse = mix(pulse_min, pulse_max, (sin(TIME * pulse_speed) + 1.0) * 0.5);
	ALBEDO = base_color.rgb * pulse;
	EMISSION = base_color.rgb * glow_strength * pulse;
}
