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
const DEEP_SPACE_MAX_DISTANCE: float = 420.0

## Hard edge of playable space, measured from the arena center (world
## origin). Beyond this, Player._apply_arena_bounds() fires a strong push
## back toward the nearest planet, and ArenaBoundary.gd's shell becomes
## visible nearby. Comfortably past the outermost body (Halcyon: orbit_radius
## 440 + radius 36 = 476 max reach).
const ARENA_BOUNDARY_RADIUS: float = 535.0

var _bodies: Array[OrbitalBody] = []
## Last frame's separation per body pair, so a structural collision only counts
## while the two are actually closing on each other.
var _previous_separation: Dictionary = {}

## Two planets whose buildings are grinding into each other both take an orbital
## kick. Checked here rather than with real collision shapes because the towers
## are static geometry on kinematic bodies - nothing in the physics engine is
## watching for planet-on-planet contact, and with ~11 bodies the pair scan is
## far cheaper than making them all colliding rigid bodies.
func _physics_process(_delta: float) -> void:
	for i in range(_bodies.size()):
		var a: OrbitalBody = _bodies[i]
		if not is_instance_valid(a) or a.is_shattered or a.collision_cooldown > 0.0:
			continue
		for j in range(i + 1, _bodies.size()):
			var b: OrbitalBody = _bodies[j]
			if not is_instance_valid(b) or b.is_shattered or b.collision_cooldown > 0.0:
				continue
			# A moon orbiting its own parent is permanently "near" it; only count
			# bodies that are genuinely independent of one another.
			if a.orbit_pivot == b or b.orbit_pivot == a:
				continue
			var contact_distance: float = a.radius + a.structure_reach + b.radius + b.structure_reach
			var separation: float = a.global_position.distance_to(b.global_position)
			if separation > contact_distance:
				_previous_separation[[a, b]] = separation
				continue
			# Only fire while they are still CLOSING. Two bodies parked at a
			# constant separation (a phase-locked pair, or one left overlapping
			# after an earlier hit) would otherwise register a fresh collision
			# every cooldown and walk their orbits apart without end.
			var was: float = _previous_separation.get([a, b], separation + 1.0)
			_previous_separation[[a, b]] = separation
			# Needs a real closing rate, not float jitter around a fixed distance.
			if separation >= was - 0.05:
				continue
			a.structural_collision(b)
			b.structural_collision(a)

func register_body(body: OrbitalBody) -> void:
	if not _bodies.has(body):
		_bodies.append(body)

func unregister_body(body: OrbitalBody) -> void:
	_bodies.erase(body)
	for key in _previous_separation.keys():
		if key.has(body):
			_previous_separation.erase(key)

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
