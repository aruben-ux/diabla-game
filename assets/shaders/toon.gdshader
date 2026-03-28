shader_type spatial;
render_mode cull_back;

// Toon/cel shader with rim lighting
uniform vec4 albedo_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float rim_power : hint_range(0.0, 8.0) = 3.0;
uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.4;
uniform float bands : hint_range(1.0, 8.0) = 3.0;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.8;

void fragment() {
	ALBEDO = albedo_color.rgb;
	METALLIC = metallic_value;
	ROUGHNESS = roughness_value;
}

void light() {
	// Cel shading: quantize diffuse into bands
	float NdotL = dot(NORMAL, LIGHT);
	float intensity = clamp(NdotL, 0.0, 1.0);
	intensity = floor(intensity * bands) / bands;

	DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR * intensity * ALBEDO;

	// Rim lighting
	float rim = 1.0 - dot(NORMAL, VIEW);
	rim = pow(rim, rim_power);
	DIFFUSE_LIGHT += rim * rim_color.rgb * rim_strength * ATTENUATION;
}
