shader_type canvas_item;

// Railgun scope overlay. The lens is a circle at screen centre showing the
// (FOV-zoomed) view untouched; everything outside it is progressively blurred
// and darkened, so the eye is pulled to what you're aiming at.
//
// The blur is done with textureLod against the screen texture's mipmap chain
// rather than a multi-tap gather: one sample per pixel, and the LOD can ramp
// smoothly with distance from the lens edge, which a fixed-radius blur cannot.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float scope_radius : hint_range(0.05, 0.6) = 0.32;
uniform float edge_softness : hint_range(0.001, 0.2) = 0.05;
uniform float blur_strength : hint_range(0.0, 6.0) = 4.0;
uniform float outside_darkness : hint_range(0.0, 1.0) = 0.72;
uniform float ring_thickness : hint_range(0.0, 0.05) = 0.006;
uniform vec4 reticle_color : source_color = vec4(0.35, 0.85, 1.0, 1.0);

void fragment() {
	// Aspect-correct so the lens stays circular on any window shape.
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 centered = SCREEN_UV - vec2(0.5);
	centered.x *= aspect;
	float d = length(centered);

	float outside = smoothstep(scope_radius, scope_radius + edge_softness, d);

	vec3 blurred = textureLod(screen_tex, SCREEN_UV, blur_strength * outside).rgb;
	blurred = mix(blurred, vec3(0.0), outside * outside_darkness);

	// Bright ring marking the lens edge.
	float ring = smoothstep(ring_thickness, 0.0, abs(d - scope_radius));
	vec3 col = mix(blurred, reticle_color.rgb, ring * 0.9);

	// Crosshair inside the lens, with a gap at dead centre so it never covers
	// the thing being aimed at.
	float thin = 0.0011 * aspect;
	float gap = step(0.022, d);
	float lens = 1.0 - step(scope_radius * 0.93, d);
	float cross_line = max(
		smoothstep(thin, 0.0, abs(centered.x)),
		smoothstep(thin, 0.0, abs(centered.y))) * gap * lens;
	col = mix(col, reticle_color.rgb, cross_line * 0.75);

	COLOR = vec4(col, max(max(outside, ring), cross_line));
}
