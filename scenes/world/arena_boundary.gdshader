shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, blend_add, shadows_disabled;

// Sci-fi "force field" boundary shell. Meant to be invisible from inside the
// arena under normal play - it only becomes visible as the camera actually
// gets close to it (i.e. a player has been flung way out toward the edge),
// via a distance-based fade combined with a grid line pattern and an
// occasional glitch-style flicker/offset.

uniform vec4 grid_color : source_color = vec4(0.25, 0.9, 1.0, 1.0);
uniform float grid_scale : hint_range(1.0, 60.0) = 18.0;
uniform float line_width : hint_range(0.01, 0.5) = 0.06;
uniform float fade_distance : hint_range(5.0, 300.0) = 90.0;
uniform float max_alpha : hint_range(0.0, 1.0) = 0.6;
uniform float glitch_speed : hint_range(0.0, 10.0) = 3.0;
uniform float glitch_amount : hint_range(0.0, 1.0) = 0.25;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash1(float n) {
	return fract(sin(n) * 43758.5453123);
}

void fragment() {
	// World-space grid: pick whichever pair of axes is most perpendicular to
	// the local surface normal so the lines stay roughly even-width instead
	// of stretching near the poles of the sphere.
	vec3 n = abs(NORMAL);
	vec3 p = world_pos / grid_scale;
	vec2 grid_uv = n.x > n.y && n.x > n.z ? p.yz : (n.y > n.z ? p.xz : p.xy);
	vec2 g = abs(fract(grid_uv) - 0.5);
	float line = min(g.x, g.y);
	float grid = 1.0 - smoothstep(0.0, line_width, line);

	// Glitch: periodically shift a horizontal band's brightness/opacity.
	float band = floor(world_pos.y * 0.5 + TIME * glitch_speed);
	float glitch_roll = hash1(band + floor(TIME * 5.0));
	float glitch = step(0.85, glitch_roll) * glitch_amount;

	float dist_to_cam = length(world_pos - CAMERA_POSITION_WORLD);
	float proximity = 1.0 - smoothstep(0.0, fade_distance, dist_to_cam);

	// Faint fresnel edge glow on top of the grid so the shell reads as a
	// surface even where no grid line crosses.
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);

	float intensity = clamp(grid * 0.85 + fresnel * 0.25 + glitch, 0.0, 1.5);
	ALBEDO = grid_color.rgb;
	EMISSION = grid_color.rgb * intensity * 2.2;
	ALPHA = clamp(intensity * proximity * max_alpha, 0.0, 1.0);
}
