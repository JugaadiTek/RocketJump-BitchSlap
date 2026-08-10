extends Node
## GravityManager (autoload)
##
## Central registry of every OrbitalBody in the arena. Anything that needs to
## fall (players, rockets, slugs, corpses...) asks this singleton "what's the
## gravity at this point?" instead of using Godot's built-in gravity.
##
## This is intentionally NOT a real N-body simulation - see OrbitalBody.gd for
## why. Each body just pulls things toward its center with an inverse-square
## falloff that fades out completely past `influence_radius`, so a player
## drifting in open space between planets doesn't get inexplicably yanked by
## something on the far side of the arena.

## Fallback pull (m/s^2) applied when a point is outside every body's
## influence radius, so players who rocket-jump way out into open space drift
## slowly back toward the arena instead of floating away forever.
const DEEP_SPACE_PULL: float = 0.6
const DEEP_SPACE_MAX_DISTANCE: float = 525.0

## Hard edge of playable space, measured from the arena center (world
## origin). Beyond this, Player._apply_arena_bounds() fires a strong push
## back toward the nearest planet, and ArenaBoundary.gd's shell becomes
## visible nearby. Comfortably past the outermost body (Halcyon: orbit_radius
## 570 + radius 36 = 606 max reach).
const ARENA_BOUNDARY_RADIUS: float = 665.0

var _bodies: Array[OrbitalBody] = []

func register_body(body: OrbitalBody) -> void:
	if not _bodies.has(body):
		_bodies.append(body)

func unregister_body(body: OrbitalBody) -> void:
	_bodies.erase(body)

func get_bodies() -> Array[OrbitalBody]:
	return _bodies

## Returns the summed gravity vector (m/s^2, points TOWARD the pulling mass)
## at `global_pos`. Magnitude is the acceleration; callers do
## `velocity += get_gravity_at(pos) * delta`.
func get_gravity_at(global_pos: Vector3) -> Vector3:
	var total := Vector3.ZERO
	var any_influence := false
	for body in _bodies:
		if not is_instance_valid(body) or body.is_shattered:
			continue
		var to_body := body.global_position - global_pos
		var dist := to_body.length()
		if dist > body.influence_radius:
			continue
		any_influence = true
		var clamped_dist: float = max(dist, body.radius * 0.5)
		var falloff := (body.radius * body.radius) / (clamped_dist * clamped_dist)
		var strength: float = body.surface_gravity * falloff
		# Smoothly fade to zero as we approach influence_radius instead of a
		# hard cutoff, so bodies don't feel like they have an invisible wall.
		var fade: float = clamp((body.influence_radius - dist) / (body.influence_radius * 0.25), 0.0, 1.0)
		total += to_body.normalized() * strength * fade
	if not any_influence:
		var dist_from_center := global_pos.length()
		if dist_from_center > DEEP_SPACE_MAX_DISTANCE:
			total += (-global_pos).normalized() * DEEP_SPACE_PULL
	return total

## Returns the nearest body to a point (or null), useful for AI / spawn logic
## and for deciding which planet's surface a player last stood on.
func get_nearest_body(global_pos: Vector3) -> OrbitalBody:
	var nearest: OrbitalBody = null
	var nearest_dist := INF
	for body in _bodies:
		if not is_instance_valid(body) or body.is_shattered:
			continue
		var d := body.global_position.distance_to(global_pos) - body.radius
		if d < nearest_dist:
			nearest_dist = d
			nearest = body
	return nearest
