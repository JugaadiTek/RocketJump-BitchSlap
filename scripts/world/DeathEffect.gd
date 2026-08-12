class_name DeathEffect
extends Node3D
## The comic-book kill marker: a jagged action burst and a speech bubble
## carrying the victim's name and a skull.
##
## Spawned into the world at the death spot and freed on a timer. Everything is
## built procedurally: the burst and bubble are generated meshes, and the skull
## is drawn into an ImageTexture rather than typed as an emoji, because the
## bundled font has no glyph for one and it would render as a hollow box.

const LIFETIME: float = 4.5

const ACTION_WORDS: Array[String] = ["POW!", "BAM!", "SPLAT!", "WHAM!", "KABLAM!", "THWACK!"]
const BURST_COLORS: Array[Color] = [
	Color(1.0, 0.85, 0.1), Color(1.0, 0.45, 0.05), Color(1.0, 0.2, 0.25),
]

var _up: Vector3 = Vector3.UP

## `up` is the victim's own up axis, so the bubble stands upright relative to
## the planet they died on rather than to world Y.
func setup(victim_name: String, up: Vector3) -> void:
	_up = up.normalized() if up.length() > 0.001 else Vector3.UP
	_add_action_burst()
	_add_speech_bubble(victim_name)

func _ready() -> void:
	await get_tree().create_timer(LIFETIME).timeout
	queue_free()

## Ragged star polygon, drawn double-sided and unshaded so it reads as flat ink
## from any angle.
func _add_action_burst() -> void:
	var points: int = 11
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outer: float = 2.4
	var inner: float = 1.15
	for i in range(points * 2):
		var a0: float = TAU * float(i) / float(points * 2)
		var a1: float = TAU * float(i + 1) / float(points * 2)
		var r0: float = outer * randf_range(0.82, 1.0) if i % 2 == 0 else inner
		var r1: float = inner if i % 2 == 0 else outer * randf_range(0.82, 1.0)
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(cos(a0) * r0, sin(a0) * r0, 0.0))
		st.add_vertex(Vector3(cos(a1) * r1, sin(a1) * r1, 0.0))
	st.generate_normals()
	var burst := MeshInstance3D.new()
	burst.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	var col: Color = BURST_COLORS[randi() % BURST_COLORS.size()]
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.2
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	burst.material_override = mat
	burst.position = _up * 1.0
	add_child(burst)

	var word := Label3D.new()
	word.text = ACTION_WORDS[randi() % ACTION_WORDS.size()]
	word.font_size = 160
	word.outline_size = 40
	word.modulate = Color(1, 1, 1)
	word.outline_modulate = Color(0.05, 0.02, 0.05)
	word.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	word.no_depth_test = true
	word.pixel_size = 0.008
	word.position = _up * 1.0
	add_child(word)

func _add_speech_bubble(victim_name: String) -> void:
	var bubble := Node3D.new()
	bubble.position = _up * 3.2
	add_child(bubble)

	var plate := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(4.4, 1.5)
	plate.mesh = quad
	var plate_mat := StandardMaterial3D.new()
	plate_mat.albedo_color = Color(0.97, 0.96, 0.93)
	plate_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	plate_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	plate_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	plate.material_override = plate_mat
	bubble.add_child(plate)

	var label := Label3D.new()
	label.text = victim_name
	label.font_size = 90
	label.outline_size = 0
	label.modulate = Color(0.08, 0.06, 0.1)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.006
	label.position = Vector3(-0.5, 0.0, 0.02)
	bubble.add_child(label)

	var skull := Sprite3D.new()
	skull.texture = _skull_texture()
	skull.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	skull.no_depth_test = true
	skull.pixel_size = 0.011
	skull.position = Vector3(1.55, 0.0, 0.02)
	bubble.add_child(skull)

## Draws a skull into an image. Deliberately not an emoji: the bundled font has
## no glyph for one, so it would come out as a hollow rectangle.
func _skull_texture() -> ImageTexture:
	var size: int = 96
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var bone := Color(0.1, 0.08, 0.12)
	var half: float = size * 0.5
	for y in range(size):
		for x in range(size):
			var fx: float = (float(x) - half) / half
			var fy: float = (float(y) - half) / half
			# Cranium: a slightly squashed disc in the upper two thirds.
			var in_skull: bool = (fx * fx) / 0.62 + ((fy + 0.18) * (fy + 0.18)) / 0.75 <= 1.0
			# Jaw: a narrower block hanging below it.
			if not in_skull and absf(fx) < 0.42 and fy > 0.3 and fy < 0.78:
				in_skull = true
			if not in_skull:
				continue
			# Eye sockets and nose punched back out.
			var eye_l: bool = ((fx + 0.27) * (fx + 0.27)) / 0.032 + ((fy + 0.08) * (fy + 0.08)) / 0.05 <= 1.0
			var eye_r: bool = ((fx - 0.27) * (fx - 0.27)) / 0.032 + ((fy + 0.08) * (fy + 0.08)) / 0.05 <= 1.0
			var nose: bool = absf(fx) < 0.09 and fy > 0.18 and fy < 0.34
			var teeth: bool = fy > 0.42 and fy < 0.72 and absf(fmod(fx * 6.0 + 60.0, 1.0) - 0.5) < 0.16
			if eye_l or eye_r or nose or teeth:
				continue
			img.set_pixel(x, y, bone)
	return ImageTexture.create_from_image(img)
