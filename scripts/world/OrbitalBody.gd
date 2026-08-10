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
## Height of the tallest structure standing on this body, and a cooldown so a
## single grinding encounter between two planets registers once rather than
## every physics frame. See GravityManager._physics_process.
var structure_reach: float = 0.0
var collision_cooldown: float = 0.0
## Baked surface geometry, populated the first time apply_crater() runs.
## Collider rebuilds are coalesced: several craters landing within this window
## produce one triangle-mesh rebuild instead of one each.
const COLLIDER_REBUILD_INTERVAL: float = 0.6
## Surface tessellation. Coarse enough to read as facets, fine enough that a
## crater still has vertices to displace.
const SURFACE_SEGMENTS: int = 36
const SURFACE_RINGS: int = 18
var _atmosphere: MeshInstance3D = null
var _orbit_ring: MeshInstance3D = null
var _ring_drawn_radius: float = 0.0
var _collider_dirty: bool = false
var _collider_rebuild_delay: float = COLLIDER_REBUILD_INTERVAL
var _crater_arrays: Array = []
var _crater_vertices: PackedVector3Array = PackedVector3Array()
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
	_add_atmosphere_shell()
	_add_orbit_ring()
	_rebuild_faceted_surface()

## Faint ring tracing this body's orbital path, the way the concept art draws
## every world on a visible track. Parented to the PIVOT rather than to us, so a
## moon's ring travels with its parent planet instead of being pinned to the
## arena centre.
func _add_orbit_ring() -> void:
	if orbit_pivot == null or orbit_radius <= 0.01:
		return
	_orbit_ring = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.rings = 96
	ring.ring_segments = 4
	_orbit_ring.mesh = ring
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.55, 0.65, 1.0, 0.16)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.5, 0.68, 1.0)
	ring_mat.emission_energy_multiplier = 0.9
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_orbit_ring.material_override = ring_mat
	_orbit_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	orbit_pivot.add_child(_orbit_ring)
	_refresh_orbit_ring()

## TorusMesh lies in its own XZ plane with +Y as the axis, so aligning the ring
## to the orbit is just a matter of pointing its Y at orbit_axis.
func _refresh_orbit_ring() -> void:
	if _orbit_ring == null or not is_instance_valid(_orbit_ring):
		return
	var ring: TorusMesh = _orbit_ring.mesh
	var thickness: float = clampf(orbit_radius * 0.0025, 0.12, 0.6)
	ring.inner_radius = maxf(orbit_radius - thickness, 0.01)
	ring.outer_radius = orbit_radius + thickness
	var axis: Vector3 = orbit_axis.normalized()
	_orbit_ring.transform = Transform3D(Basis(Quaternion(Vector3.UP, axis)), Vector3.ZERO)
	_ring_drawn_radius = orbit_radius

## Thin emissive shell just above the surface, rendered inside-out so only the
## limb shows through - the atmospheric rim glow every planet has in the concept
## art. Front faces are culled, so what you see is the shell's FAR side around
## the planet's edge; that band of backfaces is the glow.
func _add_atmosphere_shell() -> void:
	_atmosphere = MeshInstance3D.new()
	_atmosphere.mesh = SphereMesh.new()
	var tint: Color = Color(0.45, 0.62, 1.0)
	var surface_mat := mesh.get_surface_override_material(0)
	if surface_mat is StandardMaterial3D:
		tint = (surface_mat as StandardMaterial3D).albedo_color.lerp(Color(0.5, 0.7, 1.0), 0.55)
	var shell_mat := StandardMaterial3D.new()
	shell_mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.16)
	shell_mat.emission_enabled = true
	shell_mat.emission = tint
	shell_mat.emission_energy_multiplier = 1.4
	shell_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shell_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shell_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	shell_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	_atmosphere.material_override = shell_mat
	_atmosphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_atmosphere)
	_resize_atmosphere()

func _resize_atmosphere() -> void:
	var shell_mesh: SphereMesh = _atmosphere.mesh
	shell_mesh.radius = radius * 1.05
	shell_mesh.height = radius * 2.1
	shell_mesh.radial_segments = 24
	shell_mesh.rings = 12

func _apply_visual_scale() -> void:
	if not is_inside_tree():
		return
	if collision and collision.shape is SphereShape3D:
		collision.shape.radius = radius
	# Craters edit the surface in place, so regenerating it from a fresh sphere
	# would wipe them. Only rebuild while the surface is still pristine - which
	# is exactly the case that matters, since the only late radius changes come
	# from freshly-spawned shatter fragments.
	if _crater_vertices.is_empty():
		_rebuild_faceted_surface()
	if _atmosphere:
		_resize_atmosphere()

## Rebuilds the surface as flat-shaded facets - the chunky low-poly look the
## concept art uses. Deindexing before generating normals is what does it: with
## no shared vertices every triangle gets its own normal instead of a smoothed
## average. It also leaves an editable ArrayMesh, which is what apply_crater()
## needs anyway.
##
## Tessellation is a balance: coarse enough to read as facets, fine enough that
## a crater has vertices to actually move (at 36x18 the spacing on the largest
## planet is ~7.7m, just under the biggest crater radius).
func _rebuild_faceted_surface() -> void:
	if mesh == null:
		return
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = SURFACE_SEGMENTS
	sphere.rings = SURFACE_RINGS
	var st := SurfaceTool.new()
	st.create_from(sphere, 0)
	st.deindex()
	st.generate_normals()
	mesh.mesh = st.commit()

## Dents the surface where something slammed into it - visibly AND physically.
##
## The mesh starts as a faceted ArrayMesh baked in _ready(), so there are real
## vertices to push. The collider is rebuilt from those same vertices as a
## ConcavePolygonShape3D, which is what lets players actually walk down into a
## crater. That rebuild is the expensive half, so it is deferred and coalesced
## (see _physics_process): a busy respawn wave cratering the same planet several
## times in one second pays for one rebuild, not five.
func apply_crater(world_point: Vector3, crater_radius: float, depth: float) -> void:
	if is_shattered or mesh == null or crater_radius <= 0.01:
		return
	_ensure_deformable_mesh()
	if _crater_vertices.is_empty():
		return

	# Project the impact onto the surface, in the planet's own local space so
	# craters ride along with its orbit and spin.
	var local_hit: Vector3 = (to_local(world_point)).normalized() * radius
	var changed: bool = false
	for i in range(_crater_vertices.size()):
		var v: Vector3 = _crater_vertices[i]
		var dist: float = v.distance_to(local_hit)
		if dist > crater_radius:
			continue
		# Cosine bowl with a raised lip near the rim, so it reads as an impact
		# crater rather than a smooth dimple.
		var t: float = dist / crater_radius
		var bowl: float = cos(t * PI * 0.5)
		var rim: float = -0.28 * sin(t * PI) * t
		var displacement: float = depth * (bowl + rim)
		if absf(displacement) < 0.0005:
			continue
		_crater_vertices[i] = v - v.normalized() * displacement
		changed = true
	if not changed:
		return

	_crater_arrays[Mesh.ARRAY_VERTEX] = _crater_vertices
	_rebuild_cratered_mesh()
	_collider_dirty = true

func _ensure_deformable_mesh() -> void:
	if not _crater_vertices.is_empty():
		return
	var source: Mesh = mesh.mesh
	if source == null or source.get_surface_count() == 0:
		return
	_crater_arrays = source.surface_get_arrays(0)
	_crater_vertices = _crater_arrays[Mesh.ARRAY_VERTEX]

## Normals have to be regenerated from the moved vertices or the crater is
## invisible - the shading, not the silhouette, is what makes it read.
func _rebuild_cratered_mesh() -> void:
	var rebuilt := ArrayMesh.new()
	rebuilt.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _crater_arrays)
	var st := SurfaceTool.new()
	st.create_from(rebuilt, 0)
	st.generate_normals()
	mesh.mesh = st.commit()

## Swaps the perfect SphereShape3D for a triangle mesh built from the cratered
## surface, so craters are walkable terrain rather than paint. Only ever called
## from the coalescing timer in _physics_process - rebuilding a couple of
## thousand triangles is far too expensive to do per impact.
func _rebuild_collider() -> void:
	if mesh == null or mesh.mesh == null:
		return
	var faces: PackedVector3Array = mesh.mesh.get_faces()
	if faces.is_empty():
		return
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	collision.shape = shape

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
	if collision_cooldown > 0.0:
		collision_cooldown -= delta
	# Orbits drift on every spawn landing and jump on a structural collision;
	# refresh the drawn ring once the difference would actually be visible.
	if _orbit_ring and absf(orbit_radius - _ring_drawn_radius) > maxf(orbit_radius * 0.01, 0.25):
		_refresh_orbit_ring()
	if _collider_dirty:
		_collider_rebuild_delay -= delta
		if _collider_rebuild_delay <= 0.0:
			_collider_dirty = false
			_collider_rebuild_delay = COLLIDER_REBUILD_INTERVAL
			_rebuild_collider()
	_update_motion_delta(delta)

## Records a building's height so GravityManager knows how far this body's
## structures stick out when checking whether two planets are grinding together.
func note_structure(height: float) -> void:
	structure_reach = maxf(structure_reach, height)

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

## Two planets have drifted close enough that the buildings on their surfaces
## are colliding. Unlike perturb_orbit()'s sub-1% drift, this is a real impact:
## the outer body is flung further out and slowed, the inner one is dragged in
## and sped up, scaled by their relative mass so a moon bounces off a planet
## rather than the other way round. Also craters both at the contact point.
func structural_collision(other: OrbitalBody) -> void:
	if is_shattered or other.is_shattered or orbit_pivot == null:
		return
	# Mass goes as radius cubed, so a big world barely notices a small one.
	var own_mass: float = pow(radius, 3.0)
	var other_mass: float = pow(other.radius, 3.0)
	var share: float = other_mass / maxf(own_mass + other_mass, 0.001)

	var outward: float = 1.0 if orbit_radius >= other.orbit_radius else -1.0
	var kick: float = clampf(share, 0.0, 0.9) * randf_range(0.04, 0.09)
	orbit_radius = maxf(orbit_radius * (1.0 + outward * kick), radius * 1.5)
	# Pushed outward means slowing down, dragged inward means speeding up.
	orbit_speed *= (1.0 - outward * kick * 0.5)
	orbit_eccentricity = clampf(orbit_eccentricity + share * randf_range(0.01, 0.05), 0.0, 0.7)
	_semi_minor = orbit_radius * (1.0 - orbit_eccentricity)
	# Tilt the orbital plane a little - a glancing blow shouldn't leave both
	# bodies in exactly the same plane they started in.
	orbit_axis = (orbit_axis + Vector3(
		randf_range(-0.05, 0.05), randf_range(-0.05, 0.05), randf_range(-0.05, 0.05)
	) * share).normalized()

	var contact: Vector3 = global_position + (other.global_position - global_position).normalized() * radius
	apply_crater(contact, clampf(radius * 0.3, 2.0, 12.0), clampf(radius * 0.1, 0.8, 4.0))
	_demolish_structures_near(contact, other)
	collision_cooldown = 3.0

## Shears off the buildings actually caught in the encounter - the ones on the
## hemisphere facing the other planet, within reach of its structures. Buildings
## on the far side are untouched.
func _demolish_structures_near(contact: Vector3, other: OrbitalBody) -> void:
	var reach: float = structure_reach + other.structure_reach + other.radius * 0.5
	var tallest_left: float = 0.0
	for child in get_children():
		if not (child is Building):
			continue
		var building: Building = child
		if building.is_demolished():
			continue
		if building.global_position.distance_to(contact) <= reach:
			building.demolish()
		else:
			tallest_left = maxf(tallest_left, building.structure_height())
	# Recompute how far this body's structures now stick out, so a flattened
	# planet stops registering contacts it can no longer physically make.
	structure_reach = tallest_left

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
