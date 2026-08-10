class_name OrbitalBody
extends Node3D

signal shattered(body: OrbitalBody)
signal fragment_spawned(fragment: OrbitalBody)

@export_group("Shape")
@export var radius: float = 40.0:
	set(v):
		radius = v
		_apply_visual_scale()

@export_group("Gravity")
@export var surface_gravity: float = 20.0
@export var influence_radius: float = 220.0

@export_group("Orbit")
@export var orbit_pivot: Node3D
@export var orbit_radius: float = 0.0
## Semi-minor axis: if 0, orbit is circular. Set to a fraction of orbit_radius
## (e.g. 0.6) for an ellipse. Perturb_orbit can drift this over time.
@export var orbit_eccentricity: float = 0.0
@export var orbit_speed: float = 0.0
@export var orbit_axis: Vector3 = Vector3.UP
@export var orbit_start_angle: float = 0.0

@export_group("Self rotation")
@export var spin_axis: Vector3 = Vector3.UP
@export var spin_speed: float = 0.1

@export_group("Destructible")
@export var can_be_shattered: bool = true
@export var fragment_count_min: int = 2
@export var fragment_count_max: int = 4

var is_shattered: bool = false
## Rigid motion of this body between the previous physics frame and the current
## one, expressed as a transform that maps a point's old world position to its
## new one. Planets here orbit at up to ~12 m/s - faster than a player can run -
## and spin on top of that, so anything standing on one has to be carried by
## this delta or the surface simply slides out from under it (Player owns that;
## see Player._update_planet_frame).
var motion_delta: Transform3D = Transform3D.IDENTITY
var _prev_global_transform: Transform3D = Transform3D.IDENTITY
var _motion_delta_time: float = 0.0
var _orbit_angle: float = 0.0
## Bodies with eccentricity use semi-major (orbit_radius) and semi-minor
## (_semi_minor) axes to trace an ellipse instead of a circle.
var _semi_minor: float = 0.0
var _orbit_template: PackedScene = null  # set by Arena to allow fragment spawning

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var collision: CollisionShape3D = $StaticBody3D/CollisionShape3D
@onready var static_body: StaticBody3D = $StaticBody3D

func _ready() -> void:
	mesh.mesh = mesh.mesh.duplicate()
	var mat: Material = mesh.get_surface_override_material(0)
	if mat:
		mesh.set_surface_override_material(0, mat.duplicate())
	collision.shape = collision.shape.duplicate()

	add_to_group("orbital_bodies")
	_orbit_angle = orbit_start_angle
	_semi_minor = orbit_radius * (1.0 - clamp(orbit_eccentricity, 0.0, 0.95))
	_apply_visual_scale()
	static_body.set_meta("orbital_body", self)
	GravityManager.register_body(self)
	if orbit_pivot:
		_update_orbit_position()
	# Riders read motion_delta during their own _physics_process, so every body
	# must have finished moving before any player runs. Tree order already puts
	# OrbitalBodies ahead of Players in Arena.tscn, but an explicit priority
	# means that stays true if the scene is ever reordered.
	process_physics_priority = -10
	_prev_global_transform = global_transform

func _apply_visual_scale() -> void:
	if not is_inside_tree():
		return
	if mesh and mesh.mesh:
		mesh.mesh.radius = radius
		mesh.mesh.height = radius * 2.0
	if collision and collision.shape is SphereShape3D:
		collision.shape.radius = radius

func _physics_process(delta: float) -> void:
	if is_shattered:
		motion_delta = Transform3D.IDENTITY
		_motion_delta_time = 0.0
		return
	if orbit_pivot and orbit_speed != 0.0:
		_orbit_angle += orbit_speed * delta
		_update_orbit_position()
		_check_boundary()
	if spin_speed != 0.0:
		rotate(spin_axis.normalized(), spin_speed * delta)
	_update_motion_delta(delta)

func _update_motion_delta(delta: float) -> void:
	motion_delta = global_transform * _prev_global_transform.affine_inverse()
	motion_delta.basis = motion_delta.basis.orthonormalized()
	_prev_global_transform = global_transform
	_motion_delta_time = delta

## World-space velocity of the point on (or above) this body that currently sits
## at `world_point`, combining orbital travel and self-rotation. Used to convert
## player velocity in and out of this body's reference frame.
func get_point_velocity(world_point: Vector3) -> Vector3:
	if _motion_delta_time <= 0.0:
		return Vector3.ZERO
	return ((motion_delta * world_point) - world_point) / _motion_delta_time

func _update_orbit_position() -> void:
	var axis := orbit_axis.normalized()
	var reference := Vector3.RIGHT if abs(axis.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var tangent_a := axis.cross(reference).normalized()
	var tangent_b := axis.cross(tangent_a).normalized()
	## Ellipse: a*cos(θ) along tangent_a, b*sin(θ) along tangent_b
	var a: float = orbit_radius
	var b: float = _semi_minor if _semi_minor > 0.0 else orbit_radius
	var offset := (tangent_a * cos(_orbit_angle) * a + tangent_b * sin(_orbit_angle) * b)
	global_position = orbit_pivot.global_position + offset

func _check_boundary() -> void:
	if global_position.length() <= GravityManager.ARENA_BOUNDARY_RADIUS:
		return
	if not can_be_shattered:
		return
	_shatter_to_fragments()

func perturb_orbit(impact_strength: float = 1.0) -> void:
	if is_shattered or orbit_pivot == null:
		return
	var strength_mult: float = clamp(impact_strength, 0.0, 3.0)
	var pct: float = randf_range(0.0001, 0.001) * strength_mult
	var sign_r: float = 1.0 if randf() < 0.5 else -1.0
	var sign_s: float = 1.0 if randf() < 0.5 else -1.0
	orbit_radius = max(orbit_radius * (1.0 + sign_r * pct), radius * 1.5)
	orbit_speed *= (1.0 + sign_s * pct)
	# Drift eccentricity slightly over time for emergent ellipses
	orbit_eccentricity = clamp(orbit_eccentricity + randf_range(-0.002, 0.003) * strength_mult, 0.0, 0.7)
	_semi_minor = orbit_radius * (1.0 - orbit_eccentricity)
	if randf() < 0.15:
		orbit_axis = (orbit_axis + Vector3(
			randf_range(-0.01, 0.01), randf_range(-0.01, 0.01), randf_range(-0.01, 0.01)
		)).normalized()

func shatter(blast_radius: float, blast_damage: float) -> void:
	if is_shattered:
		return
	is_shattered = true
	shattered.emit(self)
	static_body.set_collision_layer_value(1, false)
	static_body.set_collision_mask_value(1, false)
	mesh.visible = false
	_spawn_debris()
	for node in get_tree().get_nodes_in_group("damageable"):
		if not is_instance_valid(node):
			continue
		var dist: float = node.global_position.distance_to(global_position)
		if dist <= blast_radius:
			var falloff: float = 1.0 - (dist / blast_radius)
			if node.has_method("apply_damage"):
				node.apply_damage(blast_damage * falloff, self, global_position)
	_spawn_moon_fragments()
	await get_tree().create_timer(4.0).timeout
	GravityManager.unregister_body(self)
	queue_free()

## Spawns 2-5 smaller orbiting bodies that become moons of nearby planets.
## Called on Planet Buster destruction AND boundary ejection.
func _spawn_moon_fragments() -> void:
	if _orbit_template == null:
		return
	var count: int = randi_range(fragment_count_min, fragment_count_max)
	var bodies := GravityManager.get_bodies()
	# Pick the nearest non-shattered body to adopt each fragment as a moon
	for i in range(count):
		var frag: OrbitalBody = _orbit_template.instantiate()
		get_tree().current_scene.get_node_or_null("Arena/OrbitalBodies").add_child(frag) if get_tree().current_scene.has_node("Arena/OrbitalBodies") else get_tree().current_scene.add_child(frag)
		# Fragment radius = 20-40% of the parent
		frag.radius = randf_range(radius * 0.2, radius * 0.4)
		frag.surface_gravity = surface_gravity * (frag.radius / radius)
		frag.influence_radius = frag.radius * 3.5
		frag.can_be_shattered = true
		frag._orbit_template = _orbit_template
		# Random color variation of the parent
		var base_color: Color = Color(randf_range(0.2, 0.9), randf_range(0.2, 0.9), randf_range(0.2, 0.9))
		frag.radius = frag.radius  # trigger setter
		var frag_mesh: MeshInstance3D = frag.get_node_or_null("MeshInstance3D")
		if frag_mesh:
			var frag_mat := StandardMaterial3D.new()
			frag_mat.albedo_color = base_color
			frag_mesh.set_surface_override_material(0, frag_mat)
		# Pick a target parent body to orbit
		var host: OrbitalBody = _pick_fragment_host(bodies, frag.radius)
		if host == null:
			host = bodies[0] if not bodies.is_empty() else null
		if host:
			frag.orbit_pivot = host
			frag.orbit_radius = host.radius * randf_range(1.8, 3.5)
			frag.orbit_speed = randf_range(0.1, 0.3) * (1.0 if randf() < 0.5 else -1.0)
			frag.orbit_axis = Vector3(randf_range(-0.3, 0.3), 1.0, randf_range(-0.3, 0.3)).normalized()
			frag.orbit_start_angle = randf_range(0.0, TAU)
		frag.spin_speed = randf_range(0.03, 0.12) * (1.0 if randf() < 0.5 else -1.0)
		frag.global_position = global_position + Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20))
		fragment_spawned.emit(frag)

func _shatter_to_fragments() -> void:
	## Called when orbit drifts past arena boundary
	shatter(radius * 1.5, 50.0)

func _pick_fragment_host(bodies: Array[OrbitalBody], frag_radius: float) -> OrbitalBody:
	var best: OrbitalBody = null
	var best_score: float = INF
	for body in bodies:
		if body == self or body.is_shattered or not is_instance_valid(body):
			continue
		if body.radius < frag_radius * 2.0:
			continue
		var dist: float = body.global_position.distance_to(global_position)
		if dist < best_score:
			best_score = dist
			best = body
	return best

func _spawn_debris() -> void:
	var particles := GPUParticles3D.new()
	add_child(particles)
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = radius * 0.5
	mat.initial_velocity_max = radius * 1.5
	mat.gravity = Vector3.ZERO
	mat.scale_min = radius * 0.05
	mat.scale_max = radius * 0.15
	particles.process_material = mat
	particles.draw_pass_1 = BoxMesh.new()
	particles.amount = 64
	particles.lifetime = 3.0
	particles.one_shot = true
	particles.emitting = true
	particles.explosiveness = 1.0
