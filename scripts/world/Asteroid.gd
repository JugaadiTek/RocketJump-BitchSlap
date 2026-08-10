class_name Asteroid
extends CharacterBody3D
## A rock adrift between the planets. Unlike the old decorative MultiMesh field,
## these are real bodies: they fall under GravityManager, players and shots
## collide with them, and when one finally hits a planet it craters the surface
## and shoves the orbit.
##
## CharacterBody3D with move_and_collide, matching Projectile - the swept move is
## what stops a fast-falling rock tunnelling through a planet in one frame.
##
## Being physical is the whole point but it is also the cost, so Arena spawns far
## fewer of these than the old cosmetic field had.

## Below this the rock is treated as a pebble and simply drifts.
@export var radius: float = 1.6
@export var impact_crater_scale: float = 2.2
## A rock predicted to hit within this many seconds lights up as a comet.
@export var comet_warning_time: float = 2.0

var _spin := Vector3.ZERO
var _comet: GPUParticles3D = null
var _glow: OmniLight3D = null
var _shape: CollisionShape3D = null
var _mesh: MeshInstance3D = null

func _ready() -> void:
	# Layer 16: its own layer, so shots (mask 1|2|8) pass by but players still
	# collide. Mask 1 keeps it colliding with planets and structures.
	collision_layer = 16
	collision_mask = 1
	_spin = Vector3(randf_range(-1.4, 1.4), randf_range(-1.4, 1.4), randf_range(-1.4, 1.4))
	_build()

func _build() -> void:
	_shape = CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	_shape.shape = sphere
	add_child(_shape)

	_mesh = MeshInstance3D.new()
	var rock := SphereMesh.new()
	rock.radius = radius
	rock.height = radius * 2.0
	# Coarse and flat-shaded, matching the faceted planets.
	rock.radial_segments = 6
	rock.rings = 4
	var st := SurfaceTool.new()
	st.create_from(rock, 0)
	st.deindex()
	st.generate_normals()
	_mesh.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	var shade: float = randf_range(0.6, 1.2)
	mat.albedo_color = Color(0.42 * shade, 0.37 * shade, 0.36 * shade)
	mat.roughness = 1.0
	_mesh.material_override = mat
	# Non-uniform scale so no two rocks are the same potato.
	_mesh.scale = Vector3(1.0, randf_range(0.65, 1.3), randf_range(0.75, 1.2))
	add_child(_mesh)

func launch(initial_velocity: Vector3) -> void:
	velocity = initial_velocity

func _physics_process(delta: float) -> void:
	velocity += GravityManager.get_gravity_at(global_position) * delta
	rotate_x(_spin.x * delta)
	rotate_y(_spin.y * delta)
	rotate_z(_spin.z * delta)

	_update_comet()

	var hit: KinematicCollision3D = move_and_collide(velocity * delta)
	if hit:
		_impact(hit.get_collider(), hit.get_position())

## Lights the rock up once it is genuinely committed to hitting something, so an
## incoming strike telegraphs itself rather than arriving out of nowhere.
func _update_comet() -> void:
	var body: OrbitalBody = GravityManager.get_nearest_body(global_position)
	var incoming: bool = false
	if body != null:
		var to_surface: Vector3 = body.global_position - global_position
		var distance: float = to_surface.length() - body.radius - radius
		# Closing speed along the line to the planet; negative means receding.
		var closing: float = velocity.dot(to_surface.normalized())
		if closing > 0.5 and distance > 0.0:
			incoming = distance / closing <= comet_warning_time
	if incoming == (_comet != null):
		return
	if incoming:
		_ignite_comet()
	else:
		_extinguish_comet()

func _ignite_comet() -> void:
	_comet = GPUParticles3D.new()
	add_child(_comet)
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 55.0
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 6.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = radius * 0.7
	mat.scale_max = radius * 2.2
	mat.color = Color(1.0, 0.62, 0.18, 0.9)
	_comet.process_material = mat
	var puff := SphereMesh.new()
	puff.radial_segments = 6
	puff.rings = 3
	var puff_mat := StandardMaterial3D.new()
	puff_mat.albedo_color = Color(1.0, 0.5, 0.12, 0.85)
	puff_mat.emission_enabled = true
	puff_mat.emission = Color(1.0, 0.62, 0.2)
	puff_mat.emission_energy_multiplier = 3.5
	puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.material = puff_mat
	_comet.draw_pass_1 = puff
	_comet.amount = 120
	_comet.lifetime = 1.4
	_comet.local_coords = false
	_comet.emitting = true

	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.6, 0.2)
	_glow.light_energy = 3.0
	_glow.omni_range = radius * 14.0
	_glow.shadow_enabled = false
	add_child(_glow)

func _extinguish_comet() -> void:
	if _comet:
		_comet.queue_free()
		_comet = null
	if _glow:
		_glow.queue_free()
		_glow = null

func _impact(collider: Object, point: Vector3) -> void:
	var body: OrbitalBody = null
	if collider is StaticBody3D and collider.has_meta("orbital_body"):
		body = collider.get_meta("orbital_body")
	if body != null and is_instance_valid(body) and not body.is_shattered:
		# Crater scaled by the rock, and an orbital nudge scaled by how hard it
		# came in - a drifting pebble barely registers, a fast one shoves.
		body.apply_crater(point, radius * impact_crater_scale, radius * impact_crater_scale * 0.35)
		body.perturb_orbit(clampf(velocity.length() / 30.0, 0.2, 3.0))
	_spawn_impact_debris(point)
	queue_free()

func _spawn_impact_debris(point: Vector3) -> void:
	var root: Node = get_tree().current_scene
	if root == null:
		return
	var debris := GPUParticles3D.new()
	root.add_child(debris)
	debris.global_position = point
	var mat := ParticleProcessMaterial.new()
	mat.direction = (point - global_position).normalized() if point != global_position else Vector3.UP
	mat.spread = 80.0
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 16.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = radius * 0.2
	mat.scale_max = radius * 0.7
	mat.color = Color(0.55, 0.45, 0.38)
	debris.process_material = mat
	debris.draw_pass_1 = BoxMesh.new()
	debris.amount = 48
	debris.lifetime = 2.2
	debris.one_shot = true
	debris.explosiveness = 0.95
	debris.emitting = true
	var timer := root.get_tree().create_timer(3.0)
	timer.timeout.connect(func(): if is_instance_valid(debris): debris.queue_free())
