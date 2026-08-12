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
## Nearest-body lookups scan every planet, and with a hundred rocks doing it
## twice a frame that adds up fast. Rocks move slowly relative to the planets, so
## the answer is cached and refreshed a few times a second instead.
var _near_body: OrbitalBody = null
var _near_refresh: float = 0.0

## Every rock used to bake its own SphereMesh (SurfaceTool + deindex +
## generate_normals, ~110 times at DebrisField spawn) AND get its own unique
## StandardMaterial3D. Identical mesh data baked 110 times over is wasted CPU
## at load, and 110 distinct materials is 110 things the renderer can't batch
## together even though the rocks are visually near-identical - same failure
## mode the buildings had before that pass (see CHANGELOG). Both are now
## built once and shared: a single unit-radius mesh sized per-rock via node
## scale, and a small fixed pool of materials so the shade variety survives
## without the draw-call cost scaling with rock_count.
static var _shared_rock_mesh: ArrayMesh = null
static var _shared_rock_materials: Array[StandardMaterial3D] = []
static var _shared_comet_mesh: SphereMesh = null
static var _shared_comet_material: StandardMaterial3D = null

static func _get_rock_mesh() -> ArrayMesh:
	if _shared_rock_mesh == null:
		var rock := SphereMesh.new()
		rock.radius = 1.0
		rock.height = 2.0
		# Coarse and flat-shaded, matching the faceted planets.
		rock.radial_segments = 6
		rock.rings = 4
		var st := SurfaceTool.new()
		st.create_from(rock, 0)
		st.deindex()
		st.generate_normals()
		_shared_rock_mesh = st.commit()
	return _shared_rock_mesh

static func _get_rock_material() -> StandardMaterial3D:
	if _shared_rock_materials.is_empty():
		for i in range(5):
			var shade: float = lerp(0.6, 1.2, float(i) / 4.0)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.42 * shade, 0.37 * shade, 0.36 * shade)
			mat.roughness = 1.0
			_shared_rock_materials.append(mat)
	return _shared_rock_materials[randi() % _shared_rock_materials.size()]

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
	_mesh.mesh = _get_rock_mesh()
	_mesh.material_override = _get_rock_material()
	# Radius and the non-uniform potato stretch both fold into node scale now
	# that the mesh itself is a shared unit sphere.
	_mesh.scale = Vector3(radius, radius * randf_range(0.65, 1.3), radius * randf_range(0.75, 1.2))
	add_child(_mesh)

func launch(initial_velocity: Vector3) -> void:
	velocity = initial_velocity

func _physics_process(delta: float) -> void:
	_near_refresh -= delta
	if _near_refresh <= 0.0:
		_near_refresh = randf_range(0.25, 0.45)
		_near_body = GravityManager.get_nearest_body(global_position)
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
	var body: OrbitalBody = _near_body if is_instance_valid(_near_body) else null
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

static func _get_comet_puff() -> SphereMesh:
	if _shared_comet_mesh == null:
		_shared_comet_mesh = SphereMesh.new()
		_shared_comet_mesh.radial_segments = 6
		_shared_comet_mesh.rings = 3
		_shared_comet_material = StandardMaterial3D.new()
		_shared_comet_material.albedo_color = Color(1.0, 0.5, 0.12, 0.85)
		_shared_comet_material.emission_enabled = true
		_shared_comet_material.emission = Color(1.0, 0.62, 0.2)
		_shared_comet_material.emission_energy_multiplier = 3.5
		_shared_comet_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shared_comet_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shared_comet_mesh.material = _shared_comet_material
	return _shared_comet_mesh

## A rock can ignite/extinguish repeatedly as it grazes past a planet without
## ever actually hitting it, so this (and the particle mesh/material above)
## stays shared and rebuilt from radius-relative scale rather than allocating
## fresh resources per ignition.
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
	_comet.draw_pass_1 = _get_comet_puff()
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
