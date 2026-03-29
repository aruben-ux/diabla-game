shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back;

// Base wall appearance
uniform vec4 albedo_color : source_color = vec4(0.55, 0.50, 0.42, 1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float roughness : hint_range(0.0, 1.0) = 0.8;
uniform float normal_scale : hint_range(0.0, 2.0) = 0.4;
uniform vec3 uv1_scale = vec3(0.5, 0.5, 0.5);

// Occlusion uniforms — updated each frame by the camera script
uniform vec3 camera_pos = vec3(0.0);
uniform vec3 player_pos = vec3(0.0);
uniform float fade_radius : hint_range(0.5, 8.0) = 3.5;
uniform float min_alpha : hint_range(0.0, 0.5) = 0.15;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Triplanar UV
	vec3 tri_pos = world_pos * uv1_scale;
	vec3 tri_normal = abs(NORMAL);
	tri_normal = normalize(max(tri_normal, vec3(0.001)));
	float tri_sum = tri_normal.x + tri_normal.y + tri_normal.z;
	tri_normal /= tri_sum;

	vec4 col_x = texture(albedo_texture, tri_pos.yz);
	vec4 col_y = texture(albedo_texture, tri_pos.xz);
	vec4 col_z = texture(albedo_texture, tri_pos.xy);
	vec4 tex_col = col_x * tri_normal.x + col_y * tri_normal.y + col_z * tri_normal.z;

	ALBEDO = albedo_color.rgb * tex_col.rgb;
	ROUGHNESS = roughness;

	// Normal map (triplanar)
	vec3 nm_x = texture(normal_texture, tri_pos.yz).rgb;
	vec3 nm_y = texture(normal_texture, tri_pos.xz).rgb;
	vec3 nm_z = texture(normal_texture, tri_pos.xy).rgb;
	vec3 nm = nm_x * tri_normal.x + nm_y * tri_normal.y + nm_z * tri_normal.z;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = normal_scale;

	// --- Occlusion fade ---
	// Find the closest point on the camera-to-player line segment to this fragment
	vec3 cam_to_player = player_pos - camera_pos;
	float line_len_sq = dot(cam_to_player, cam_to_player);

	float alpha = 1.0;

	if (line_len_sq > 0.01) {
		vec3 cam_to_frag = world_pos - camera_pos;
		float t = clamp(dot(cam_to_frag, cam_to_player) / line_len_sq, 0.0, 1.0);
		vec3 closest_point = camera_pos + cam_to_player * t;
		float dist = length(world_pos - closest_point);

		// Fade walls that are close to the line between camera and player
		// But only if the fragment is between the camera and a bit past the player
		if (dist < fade_radius && t > 0.05 && t < 0.95) {
			float fade = smoothstep(0.0, fade_radius, dist);
			alpha = mix(min_alpha, 1.0, fade);
		}
	}

	ALPHA = alpha;
}
