shader_type sky;

// Exaggerated, stylized deep-space backdrop: dense twinkling stars over
// layered colorful nebula clouds. Fully procedural (hash/noise based) so it
// needs no external texture and looks the same regardless of resolution.

uniform float star_density : hint_range(0.0, 1.0) = 0.9;
uniform float star_brightness : hint_range(0.0, 12.0) = 7.0;
uniform float star_size : hint_range(1.0, 12.0) = 5.0;  // lower = bigger stars
uniform float nebula_intensity : hint_range(0.0, 3.0) = 1.35;
uniform vec4 space_color : source_color = vec4(0.016, 0.01, 0.045, 1.0);
// Deep violet void with vivid cloud cores, matching the concept art: richer
// than a near-black sky, but nowhere near the flat magenta wash that reading
// the nebula too brightly produces.
uniform vec4 nebula_color_a : source_color = vec4(0.42, 0.12, 0.62, 1.0);
uniform vec4 nebula_color_b : source_color = vec4(0.08, 0.24, 0.58, 1.0);
uniform vec4 nebula_color_c : source_color = vec4(0.55, 0.14, 0.34, 1.0);

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
float stars(vec3 dir, float scale, float density, float brightness_mult, float size) {
	vec3 p = dir * scale;
	vec3 cell = floor(p);
	vec3 local = fract(p) - 0.5;
	float h = hash13(cell);
	float present = step(1.0 - density * 0.05, h);
	float d = length(local);
	// `size` divides the falloff distance, so a smaller value spreads each
	// star's core over more of its cell and reads as a bigger point of light.
	float core = smoothstep(0.5, 0.0, d * size);
	// A soft halo around the core gives the brighter stars visible glare
	// instead of leaving them as hard specks.
	float halo = smoothstep(0.5, 0.0, d * size * 0.35) * 0.35;
	float twinkle = 0.55 + 0.45 * hash13(cell + vec3(3.7, 1.3, 9.1));
	return present * (core + halo) * twinkle * brightness_mult;
}

void sky() {
	vec3 dir = EYEDIR;

	// Nebula: three broad, softly-colored noise layers blended together,
	// deliberately saturated/bright ("exaggerated") rather than realistic.
	float n1 = fbm(dir * 2.2 + vec3(12.3, 4.1, 77.0));
	float n2 = fbm(dir * 3.6 + vec3(91.0, 33.0, 5.0));
	float n3 = fbm(dir * 5.5 + vec3(5.0, 66.0, 21.0));

	// Higher exponents than a natural falloff would use: they crush the faint
	// haze to true black while leaving the cloud cores bright, which is what
	// gives the backdrop its contrast rather than an even purple wash.
	vec3 nebula = nebula_color_a.rgb * pow(clamp(n1, 0.0, 1.0), 2.6);
	nebula += nebula_color_b.rgb * pow(clamp(n2, 0.0, 1.0), 3.0) * 0.9;
	nebula += nebula_color_c.rgb * pow(clamp(n3, 0.0, 1.0), 3.4) * 0.7;
	nebula *= nebula_intensity;

	// Two star layers at different scales read as both "distant haze" and
	// "bright close stars" instead of one uniform speckle size.
	float s = 0.0;
	s += stars(dir, 220.0, star_density, 1.0, star_size);
	s += stars(dir + vec3(50.0), 420.0, star_density * 0.6, 0.55, star_size * 1.5);

	vec3 col = space_color.rgb + nebula + vec3(s) * star_brightness;
	COLOR = col;
}
