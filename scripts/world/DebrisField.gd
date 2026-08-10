class_name DebrisField
extends Node3D
## Spawns the drifting rock field between the planets.
##
## These used to be one decorative MultiMesh. They are now real Asteroid bodies:
## they fall under gravity, players and structures collide with them, they streak
## as comets on final approach, and they crater whatever they land on. That is a
## great deal more expensive per rock, which is exactly why there are far fewer
## of them than the cosmetic field had.

@export var rock_count: int = 110
@export var inner_radius: float = 70.0
@export var outer_radius: float = 500.0
@export var min_radius: float = 0.8
@export var max_radius: float = 3.4
## Rocks are nudged out of any band a planet sweeps through, plus this margin,
## so none of them start already inside a world.
@export var orbit_clearance: float = 18.0
## Rocks are given a slow tangential drift, so the field lazily orbits instead of
## raining straight inward the moment the match starts.
@export var drift_speed_min: float = 1.5
@export var drift_speed_max: float = 6.0

func _ready() -> void:
	var occupied: Array[Vector2] = _orbit_bands()
	for i in range(rock_count):
		var rock := Asteroid.new()
		rock.radius = randf_range(min_radius, max_radius)
		add_child(rock)
		var position: Vector3 = _scatter(occupied)
		rock.global_position = position
		# Tangential to the arena centre, so it drifts around rather than in.
		var outward: Vector3 = position.normalized()
		var tangent: Vector3 = outward.cross(Vector3.UP)
		if tangent.length_squared() < 0.001:
			tangent = outward.cross(Vector3.RIGHT)
		tangent = tangent.normalized()
		rock.launch(tangent * randf_range(drift_speed_min, drift_speed_max)
			+ outward * randf_range(-0.6, 0.6))

## Each entry is (distance of the body's orbit from the arena centre, how much
## room to leave around it). The room has to include the planet's own radius -
## clearing a flat margin from the orbit line still dropped rocks inside a 44m
## world, which then simply fell in on the first frame.
func _orbit_bands() -> Array[Vector2]:
	var bands: Array[Vector2] = []
	for body in GravityManager.get_bodies():
		if is_instance_valid(body):
			bands.append(Vector2(body.global_position.length(),
				body.radius + body.structure_reach + orbit_clearance))
	return bands

func _scatter(occupied: Array[Vector2]) -> Vector3:
	var distance: float = randf_range(inner_radius, outer_radius)
	# Shove the rock to the nearer edge of any orbital band it landed inside.
	for band in occupied:
		if absf(distance - band.x) < band.y:
			distance = band.x + (band.y if distance >= band.x else -band.y)
	var direction := Vector3(
		randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)
	).normalized()
	# Flattened toward the orbital plane so the field reads as a disc of rubble
	# rather than an even sphere of it.
	direction.y *= randf_range(0.15, 0.55)
	return direction.normalized() * distance
