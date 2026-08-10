class_name DeathEffect
extends Node3D
## The comic-book kill marker: a jagged action burst, a speech bubble carrying
## the victim's name and a skull, and the gore — blood spray, splatter on the
## ground, and giblets thrown clear.
##
## Spawned into the world at the death spot and freed on a timer. Everything is
## built procedurally: the burst and bubble are generated meshes, and the skull
## is drawn into an ImageTexture rather than typed as an emoji, because the
## bundled font has no glyph for one and it would render as a hollow box.

const LIFETIME: float = 4.5
const SPLATTER_LIFETIME: float = 30.0

const ACTION_WORDS: Array[String] = ["POW!", "BAM!", "SPLAT!", "WHAM!", "KABLAM!", "THWACK!"]
const BURST_COLORS: Array[Color] = [
	Color(1.0, 0.85, 0.1), Color(1.0, 0.45, 0.05), Color(1.0, 0.2, 0.25),
]

var _up: Vector3 = Vector3.UP

## `up` is the victim's own up axis, so the bubble stands upright relative to
## the planet they died on rather than to world Y.
func setup(victim_name: String, up: Vector3, surface_normal: Vector3) -> void:
	_up = up.normalized() if up.length() > 0.001 else Vector3.UP
	_add_action_burst()
	_add_speech_bubble(victim_name)
	_add_blood_spray()
	_add_giblets()
	_add_splatter(surface_normal)

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

func _add_blood_spray() -> void:
	var spray := GPUParticles3D.new()
	add_child(spray)
	var mat := ParticleProcessMaterial.new()
	mat.direction = _up
	mat.spread = 80.0
	mat.initial_velocity_min = 5.0
	mat.initial_velocity_max = 17.0
	mat.gravity = -_up * 14.0
	mat.scale_min = 0.12
	mat.scale_max = 0.42
	mat.color = Color(0.62, 0.03, 0.05)
	spray.process_material = mat
	var drop := SphereMesh.new()
	drop.radial_segments = 5
	drop.rings = 3
	var drop_mat := StandardMaterial3D.new()
	drop_mat.albedo_color = Color(0.5, 0.02, 0.04)
	drop_mat.roughness = 0.25
	drop_mat.metallic = 0.1
	drop.material = drop_mat
	spray.draw_pass_1 = drop
	spray.amount = 160
	spray.lifetime = 1.6
	spray.one_shot = true
	spray.explosiveness = 1.0
	spray.emitting = true
	spray.local_coords = false

## Chunks thrown clear on their own ballistic arcs. Simple integrated motion
## rather than RigidBody3D: a dozen extra physics bodies per death, times 32
## players, is not worth it for debris that lives four seconds.
func _add_giblets() -> void:
	for i in range(randi_range(6, 10)):
		var gib := MeshInstance3D.new()
		var chunk := BoxMesh.new()
		var s: float = randf_range(0.14, 0.36)
		chunk.size = Vector3(s, s * randf_range(0.6, 1.4), s * randf_range(0.7, 1.3))
		gib.mesh = chunk
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(randf_range(0.42, 0.62), randf_range(0.02, 0.09), randf_range(0.04, 0.1))
		mat.roughness = 0.35
		gib.material_override = mat
		gib.position = _up * randf_range(0.4, 1.4)
		add_child(gib)
		var velocity: Vector3 = (_up * randf_range(0.5, 1.2) + Vector3(
			randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		).normalized() * randf_range(6.0, 15.0)
		_fly_giblet(gib, velocity)

func _fly_giblet(gib: MeshInstance3D, velocity: Vector3) -> void:
	var spin := Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	var elapsed: float = 0.0
	while elapsed < LIFETIME and is_instance_valid(gib):
		var delta: float = get_process_delta_time()
		elapsed += delta
		velocity += GravityManager.get_gravity_at(gib.global_position) * delta
		gib.global_position += velocity * delta
		gib.rotate_x(spin.x * delta)
		gib.rotate_y(spin.y * delta)
		gib.rotate_z(spin.z * delta)
		await get_tree().process_frame

## Flat blood decals on the ground, left behind long after the burst has gone.
func _add_splatter(surface_normal: Vector3) -> void:
	var normal: Vector3 = surface_normal.normalized() if surface_normal.length() > 0.001 else _up
	var reference: Vector3 = Vector3.RIGHT if absf(normal.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var bx: Vector3 = normal.cross(reference).normalized()
	var bz: Vector3 = bx.cross(normal).normalized()
	# Parented to the planet, not to this effect, so the stains stay on the
	# surface as it orbits and outlive the four-second burst.
	var host: Node3D = GravityManager.get_nearest_body(global_position)
	var parent: Node3D = host if host else (get_parent() as Node3D)
	for i in range(randi_range(4, 7)):
		var stain := MeshInstance3D.new()
		var quad := QuadMesh.new()
		var s: float = randf_range(0.7, 2.3)
		quad.size = Vector2(s, s * randf_range(0.7, 1.3))
		stain.mesh = quad
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.34, 0.02, 0.03, 0.9)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		stain.material_override = mat
		parent.add_child(stain)
		var spread: Vector3 = (bx * randf_range(-2.0, 2.0) + bz * randf_range(-2.0, 2.0))
		# Quads face +Z, so lay them flat by making +Z the surface normal.
		stain.global_transform = Transform3D(Basis(bx, bz, normal), global_position + spread + normal * 0.06)
		_fade_stain(stain, mat)

func _fade_stain(stain: MeshInstance3D, mat: StandardMaterial3D) -> void:
	await get_tree().create_timer(SPLATTER_LIFETIME * 0.75).timeout
	var fade: float = SPLATTER_LIFETIME * 0.25
	var t: float = 0.0
	while t < fade and is_instance_valid(stain):
		t += get_process_delta_time()
		mat.albedo_color.a = 0.9 * (1.0 - t / fade)
		await get_tree().process_frame
	if is_instance_valid(stain):
		stain.queue_free()
