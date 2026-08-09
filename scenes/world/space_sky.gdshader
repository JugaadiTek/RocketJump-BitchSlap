shader_type sky;

// Exaggerated, stylized deep-space backdrop: dense twinkling stars over
// layered colorful nebula clouds. Fully procedural (hash/noise based) so it
// needs no external texture and looks the same regardless of resolution.

uniform float star_density : hint_range(0.0, 1.0) = 0.75;
uniform float star_brightness : hint_range(0.0, 6.0) = 3.0;
uniform float nebula_intensity : hint_range(0.0, 3.0) = 1.6;
uniform vec4 space_color : source_color = vec4(0.01, 0.01, 0.035, 1.0);
uniform vec4 nebula_color_a : source_color = vec4(0.55, 0.1, 0.65, 1.0);
uniform vec4 nebula_color_b : source_color = vec4(0.08, 0.35, 0.75, 1.0);
uniform vec4 nebula_color_c : source_color = vec4(0.85, 0.25, 0.35, 1.0);

float hash13(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z
	);
}

float fbm(vec3 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 5; i++) {
		value += amplitude * noise3(p);
		p *= 2.02;
		amplitude *= 0.5;
	}
	return value;
}

// Sharp, sparse bright points on a 3D grid built from the view direction -
// gives a dense, evenly-spread starfield without visible seams at the poles.
float stars(vec3 dir, float scale, float density, float brightness_mult) {
	vec3 p = dir * scale;
	vec3 cell = floor(p);
	vec3 local = fract(p) - 0.5;
	float h = hash13(cell);
	float present = step(1.0 - density * 0.05, h);
	float d = length(local);
	float core = smoothstep(0.5, 0.0, d * 9.0);
	float twinkle = 0.6 + 0.4 * hash13(cell + vec3(3.7, 1.3, 9.1));
	return present * core * twinkle * brightness_mult;
}

void sky() {
	vec3 dir = EYEDIR;

	// Nebula: three broad, softly-colored noise layers blended together,
	// deliberately saturated/bright ("exaggerated") rather than realistic.
	float n1 = fbm(dir * 2.2 + vec3(12.3, 4.1, 77.0));
	float n2 = fbm(dir * 3.6 + vec3(91.0, 33.0, 5.0));
	float n3 = fbm(dir * 5.5 + vec3(5.0, 66.0, 21.0));

	vec3 nebula = nebula_color_a.rgb * pow(clamp(n1, 0.0, 1.0), 2.2);
	nebula += nebula_color_b.rgb * pow(clamp(n2, 0.0, 1.0), 2.6) * 0.9;
	nebula += nebula_color_c.rgb * pow(clamp(n3, 0.0, 1.0), 3.0) * 0.7;
	nebula *= nebula_intensity;

	// Two star layers at different scales read as both "distant haze" and
	// "bright close stars" instead of one uniform speckle size.
	float s = 0.0;
	s += stars(dir, 220.0, star_density, 1.0);
	s += stars(dir + vec3(50.0), 420.0, star_density * 0.6, 0.6);

	vec3 col = space_color.rgb + nebula + vec3(s) * star_brightness;
	COLOR = col;
}
