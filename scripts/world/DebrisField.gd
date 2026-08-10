class_name DebrisField
extends MultiMeshInstance3D
## The drifting asteroid rubble that fills the space between planets in the
## concept art. Purely decorative - no collision, no gravity - so it costs a
## single draw call for the whole field via MultiMesh rather than a node each.
##
## Rocks are scattered through the shell the planets orbit in, but pushed clear
## of every orbital track so nothing appears to be embedded in a planet's path.

@export var rock_count: int = 900
@export var inner_radius: float = 60.0
@export var outer_radius: float = 520.0
@export var min_scale: float = 0.6
@export var max_scale: float = 4.5
## Rocks are nudged out of any band a planet sweeps through, plus this margin.
@export var orbit_clearance: float = 14.0
## Slow tumble of the whole field, so the backdrop is never quite static.
@export var drift_speed: float = 0.006

func _ready() -> void:
	var rock := SphereMesh.new()
	rock.radius = 1.0
	rock.height = 2.0
	# Deliberately coarse: at this distance the faceting reads as rock, and it
	# matches the low-poly planets.
	rock.radial_segments = 5
	rock.rings = 3

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.34, 0.31, 0.33)
	mat.roughness = 1.0
	mat.vertex_color_use_as_albedo = true
	material_override = mat

	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = rock
	multimesh.instance_count = rock_count

	var occupied: Array[float] = _orbit_radii()
	for i in range(rock_count):
		multimesh.set_instance_transform(i, _scatter(occupied))
		# Slight per-rock tint variation, warm to cold, so the field doesn't
		# read as one flat grey mass.
		var shade: float = randf_range(0.55, 1.25)
		multimesh.set_instance_color(i, Color(0.42 * shade, 0.37 * shade, 0.36 * shade))

func _process(delta: float) -> void:
	rotate(Vector3.UP, drift_speed * delta)

func _orbit_radii() -> Array[float]:
	var radii: Array[float] = []
	for body in GravityManager.get_bodies():
		if is_instance_valid(body) and body.orbit_radius > 0.01:
			radii.append(body.global_position.length())
	return radii

func _scatter(occupied: Array[float]) -> Transform3D:
	var distance: float = randf_range(inner_radius, outer_radius)
	# Shove the rock to the nearer edge of any orbital band it landed inside.
	for r in occupied:
		if absf(distance - r) < orbit_clearance:
			distance = r + (orbit_clearance if distance >= r else -orbit_clearance)
	var direction := Vector3(
		randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)
	).normalized()
	# Flattened toward the orbital plane so the field reads as a disc of rubble
	# rather than an even sphere of it.
	direction.y *= randf_range(0.15, 0.55)
	direction = direction.normalized()

	var basis := Basis.from_euler(Vector3(
		randf_range(0.0, TAU), randf_range(0.0, TAU), randf_range(0.0, TAU)))
	var scale: float = randf_range(min_scale, max_scale)
	# Non-uniform scale so no two rocks are the same potato.
	basis = basis.scaled(Vector3(scale, scale * randf_range(0.6, 1.3), scale * randf_range(0.7, 1.2)))
	return Transform3D(basis, direction * distance)
