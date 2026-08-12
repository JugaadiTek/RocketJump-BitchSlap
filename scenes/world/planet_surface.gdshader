shader_type spatial;

// Planet surface: the low-poly facets are the mesh itself (flat per-triangle
// normals baked in OrbitalBody._rebuild_faceted_surface), this only adds the
// engraved triangular hull-plating detail on top. A plain StandardMaterial3D
// can bump-map the facet edges but can't shift their COLOR relative to
// albedo_color, which varies per planet - true hue rotation needs the actual
// HSV math below, not just a multiply, or every differently-tinted planet
// would need its own baked texture.
//
// normal_texture is the shared triangular-lattice tile OrbitalBody.gd bakes
// once (see _build_bump_texture): RGB is the tangent-space normal for the
// embossed edges, and - repurposing the channel a plain normal map would
// leave unused - ALPHA carries the same edge distance field as a plain 0-1
// mask, which is what drives the hue shift below.

uniform vec4 albedo_color : source_color = vec4(0.55, 0.5, 0.48, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.38;
uniform float metallic : hint_range(0.0, 1.0) = 0.2;
uniform sampler2D normal_texture;
uniform float normal_scale : hint_range(-16.0, 16.0) = 0.375;
uniform vec2 uv_scale = vec2(4.0, 4.0);
// How far around the hue wheel the triangle edges shift from the planet's
// own base colour, in degrees - 0 at a cell's centre, full strength right on
// the edge line.
uniform float hue_shift_degrees : hint_range(0.0, 180.0) = 45.0;

vec3 rgb2hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 k = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
	return c.z * mix(k.xxx, clamp(p - k.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	vec4 packed_tex = texture(normal_texture, UV * uv_scale);
	float edge = packed_tex.a;

	vec3 hsv = rgb2hsv(albedo_color.rgb);
	hsv.x = fract(hsv.x + (hue_shift_degrees / 360.0) * edge);
	ALBEDO = hsv2rgb(hsv);

	ROUGHNESS = roughness;
	METALLIC = metallic;
	NORMAL_MAP = packed_tex.rgb;
	NORMAL_MAP_DEPTH = normal_scale;
}
