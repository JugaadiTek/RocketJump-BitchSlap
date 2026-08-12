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

## Fixed, independent hard edge used ONLY to eject a planet whose own orbit
## has drifted this far out (see OrbitalBody._check_boundary()). Deliberately
## NOT the same value the player/projectile boundary flexes around below -
## that box is partly DERIVED from this body's own position, so using it to
## also decide when this body gets ejected would be circular (the box would
## just keep growing to always contain whatever's drifting outward). Comfortably
## past the outermost body's normal reach (Halcyon: orbit_radius 440 + radius
## 36 = 476).
const ARENA_BOUNDARY_RADIUS: float = 535.0

## Clearance kept beyond the furthest planet's own reach when sizing the
## single arena-wide boundary box (see arena_half_extent()).
const BOUNDARY_MARGIN: float = 50.0

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

## The SINGLE box that bounds the whole arena, still just one box (not one
## per planet - it never shows up as a wall in open space between two
## worlds), but no longer a symmetric cube sized to whichever single body
## reaches furthest out in ANY direction. Each of the six faces now sits
## BOUNDARY_MARGIN beyond whichever body reaches furthest in THAT specific
## cardinal direction (+X/-X/+Y/-Y/+Z/-Z) - i.e. every face independently
## hugs the planet closest to defining it, instead of every face being
## pushed out to match the single most extreme body in the whole arena. A
## constellation with one far-flung outlier used to inflate the box on all
## six sides at once; now only the sides that outlier actually reaches out
## toward move.
##
## Cached per physics frame: every player and every projectile calls this
## (via is_within_boundary()) once each physics tick, plus the boundary shell
## once per render frame. Nothing that feeds this changes except during a
## physics step, so recomputing per-caller was pure waste - with 31 bots and
## a handful of projectiles all doing their own O(bodies) scan every tick,
## that waste was enough to show up as real frame-time spikes in a sustained
## firefight (measured: dropped a "sustained" PerfProbe run from ~230/2400
## frames over 20ms back down to baseline, ~5/2400).
var _cached_bounds_min: Vector3 = Vector3.ZERO
var _cached_bounds_max: Vector3 = Vector3.ZERO
var _bounds_frame: int = -1

func _update_bounds() -> void:
	var frame: int = Engine.get_physics_frames()
	if frame == _bounds_frame:
		return
	_bounds_frame = frame
	var bmax := Vector3.ZERO
	var bmin := Vector3.ZERO
	for body in _bodies:
		if not is_instance_valid(body) or body.is_shattered:
			continue
		var reach: float = body.radius + body.structure_reach
		var p: Vector3 = body.global_position
		bmax.x = maxf(bmax.x, p.x + reach)
		bmax.y = maxf(bmax.y, p.y + reach)
		bmax.z = maxf(bmax.z, p.z + reach)
		bmin.x = minf(bmin.x, p.x - reach)
		bmin.y = minf(bmin.y, p.y - reach)
		bmin.z = minf(bmin.z, p.z - reach)
	_cached_bounds_max = bmax + Vector3.ONE * BOUNDARY_MARGIN
	_cached_bounds_min = bmin - Vector3.ONE * BOUNDARY_MARGIN

## The box's max corner (+X/+Y/+Z faces).
func arena_bounds_max() -> Vector3:
	_update_bounds()
	return _cached_bounds_max

## The box's min corner (-X/-Y/-Z faces).
func arena_bounds_min() -> Vector3:
	_update_bounds()
	return _cached_bounds_min

## Largest half-extent that's still guaranteed inside the box on EVERY axis -
## the tightest of the six face distances. The box is asymmetric now, so
## there's no single "the" half-extent; this is the safe scalar fallback for
## callers that just want one sphere-safe number (e.g. Spawner's boundary-shell
## spawn point), not a claim that every face is actually this close.
func arena_half_extent() -> float:
	_update_bounds()
	return minf(
		minf(_cached_bounds_max.x, -_cached_bounds_min.x),
		minf(minf(_cached_bounds_max.y, -_cached_bounds_min.y), minf(_cached_bounds_max.z, -_cached_bounds_min.z)))

## True if `pos` is inside the arena-wide box (see arena_bounds_min/max).
func is_within_boundary(pos: Vector3) -> bool:
	_update_bounds()
	return (pos.x >= _cached_bounds_min.x and pos.x <= _cached_bounds_max.x
		and pos.y >= _cached_bounds_min.y and pos.y <= _cached_bounds_max.y
		and pos.z >= _cached_bounds_min.z and pos.z <= _cached_bounds_max.z)

## The human sitting at this screen - the single Player with
## is_first_person_view() true, or null (offline bot-only matches, a
## dedicated host with no local player). For purely-local rendering decisions
## that have no reason to be shared/networked state, since every client
## already runs its own independent copy of the world - the arena boundary
## shell and OrbitalBody's atmosphere glow both use this rather than reacting
## to "any player", which used to make them flicker based on bots elsewhere
## that had nothing to do with what the person watching was actually doing.
func find_local_viewer() -> Player:
	for player in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(player) and player is Player and (player as Player).is_first_person_view():
			return player
	return null
