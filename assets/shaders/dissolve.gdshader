shader_type spatial;
render_mode cull_disabled, unshaded;

// Dissolve death effect
uniform vec4 albedo_color : source_color = vec4(0.7, 0.15, 0.15, 1.0);
uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 edge_color : source_color = vec4(1.0, 0.3, 0.0, 1.0);
uniform float edge_width : hint_range(0.0, 0.2) = 0.05;
uniform float noise_scale : hint_range(1.0, 20.0) = 8.0;

// Simple hash noise
float hash(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

void fragment() {
	float noise = hash(VERTEX * noise_scale);

	if (noise < dissolve_amount) {
		discard;
	}

	// Edge glow near dissolve boundary
	float edge = smoothstep(dissolve_amount - edge_width, dissolve_amount, noise);
	vec3 final_color = mix(edge_color.rgb, albedo_color.rgb, edge);

	ALBEDO = final_color;
	EMISSION = edge_color.rgb * (1.0 - edge) * 2.0;
}
