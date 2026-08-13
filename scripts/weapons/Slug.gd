class_name Slug
extends Projectile
## The "alien slug": launched as a plain gravity-affected shot (no homing
## yet) - it only wakes up and starts hunting once it actually lands on a
## planet's surface, at which point it switches to crawling along that
## curved surface toward the nearest enemy rather than flying at them.
##
## Two states:
##   FLYING     - ballistic flight, same as a rocket. No homing. If it hits
##                a player directly during this phase it still damages them
##                (it's still a projectile), it just isn't actively chasing.
##   SLITHERING - glued to whatever body it landed on, crawling across the
##                tangent plane toward the nearest target, re-snapping to
##                the exact surface radius every frame so it "slithers"
##                along the curve instead of tunneling through it.
##   CLIMBING   - a SLITHERING slug that has crawled into a building's wall
##                (rather than the planet surface it landed on) switches here:
##                it hugs that wall instead, re-snapping via a short raycast
##                against the building's own collision each frame instead of
##                against a planet radius, and biases its desired direction
##                upward toward the target's height so it climbs rather than
##                just pacing the wall's base. Falls back to SLITHERING on the
##                planet surface if it climbs off the top/side of the wall.

enum State { FLYING, SLITHERING, CLIMBING }

@export var damage: float = 40.0
@export var turn_rate_degrees: float = 220.0
## How far a landed slug will look for someone to crawl at. Deliberately long -
## a slug that only noticed you inside 45m was easy to simply walk away from.
@export var tracking_range: float = 140.0
@export var slither_speed: float = 11.0
## Extra gravity felt while flying above `space_altitude`. A slug fired between
## planets should visibly fall into whichever well it passes, arcing around it,
## rather than sailing past on a nearly straight line. Bumped from 3.4: at the
## old value a slug fired across open space still crossed most planets'
## influence radius on a nearly flat line and sailed past into the void -
## the extra pull needed to be strong enough to actually bend that into a
## planet-finding arc, not just a cosmetic wobble.
@export var space_gravity_multiplier: float = 6.5
@export var space_altitude: float = 15.0
@export var max_hp: float = 25.0  ## slugs can be shot and killed mid-flight
## How far above the wall's base a climbing slug can drag itself before giving
## up and dropping back to ground-level slithering (buildings vary a lot in
## height; this caps how far a slug will chase up a tower rather than letting
## it climb forever).
@export var max_climb_height: float = 22.0
## How often (seconds) a landed slug re-evaluates the best available target,
## even while its current one is still valid - lets it switch off a target
## that's gone out of reach/line-of-sight for something closer instead of
## committing to the first thing it ever saw.
@export var retarget_interval: float = 0.75

var _hp: float = 25.0

var _state: State = State.FLYING
var _landed_body: OrbitalBody = null
var _surface_normal: Vector3 = Vector3.UP
var _target: Node3D = null
var _retarget_timer: float = 0.0

## Set while CLIMBING: the building's shared StaticBody3D being scaled, the
## point it first grabbed the wall at (climb progress is measured radially
## outward from the host planet relative to this - buildings are planted
## with local +Y radially out, so "outward" is "up the building"), and the
## planet the building stands on (for that radial reference).
var _climb_body: StaticBody3D = null
var _climb_start_pos: Vector3 = Vector3.ZERO
var _climb_host_body: OrbitalBody = null
## Radial "up" direction captured once at the moment it grabbed the wall, not
## re-derived from the current (already-on-the-wall) position every frame -
## re-deriving it that way fed back into itself just enough (each frame's tiny
## position nudge very slightly changing the "radial" reference for the next)
## to occasionally wander off true vertical over a couple of seconds instead
## of holding a stable climb line. Still re-projected onto the CURRENT
## surface_normal's tangent plane every frame (see _steer_climbing), so it
## still bends correctly with the wall's own curvature-compensated tilt as
## height increases - only the underlying reference direction itself is fixed.
var _climb_up_ref: Vector3 = Vector3.UP

func _ready() -> void:
	super._ready()
	_hp = max_hp
	add_to_group("damageable")

## Other weapons (not other slugs) can damage and destroy a slug in flight.
func apply_damage(amount: float, _instigator: Node, _hit_pos: Vector3, weapon_name: String = "") -> void:
	if weapon_name == "Slug Launcher":
		return  # slugs are immune to their own weapon
	_hp -= amount
	if _hp <= 0.0:
		_expire()

func _physics_process(delta: float) -> void:
	_life_remaining -= delta
	if _life_remaining <= 0.0:
		_expire()
		return
	# Past the arena's outer edge - see Projectile._physics_process. A
	# SLITHERING slug is always glued to the surface of whatever it landed on
	# so this only ever actually bites during FLYING, but checking
	# unconditionally is cheap and keeps this in sync with the base class.
	if not GravityManager.is_within_boundary(global_position):
		_expire()
		return
	match _state:
		State.FLYING:
			_process_flying(delta)
		State.SLITHERING:
			_process_slithering(delta)
		State.CLIMBING:
			_process_climbing(delta)

func _process_flying(delta: float) -> void:
	if affected_by_gravity:
		velocity += GravityManager.get_gravity_at(global_position) * _flight_gravity_multiplier() * delta
	var motion: Vector3 = velocity * delta
	var collision: KinematicCollision3D = move_and_collide(motion)
	if collision == null:
		return
	var collider: Object = collision.get_collider()
	if collider is StaticBody3D and collider.has_meta("orbital_body"):
		_land_on_surface(collider.get_meta("orbital_body"), collision.get_position(), collision.get_normal())
	elif collider and collider != owner_player and collider.has_method("apply_damage"):
		_hit_player(collider, collision.get_position())
	elif collider is StaticBody3D:
		# A Tower/Bunker/Turret wall, or any other plain building StaticBody3D
		# (no orbital_body meta, no apply_damage) - start climbing it instead
		# of dying against it. Anything neither a planet, a player, nor a
		# StaticBody3D (a trigger volume, say) still falls through to expire
		# below, same as a shot that misses everything already does.
		_start_climbing(collider, collision.get_position(), collision.get_normal())
	else:
		_expire()

## Gravity bites harder the further from any surface the slug is, which is what
## turns a shot fired from open space into a curving dive into the nearest well
## instead of a flat line across the arena.
func _flight_gravity_multiplier() -> float:
	var body: OrbitalBody = GravityManager.get_nearest_body(global_position)
	if body == null:
		return gravity_multiplier
	var altitude: float = global_position.distance_to(body.global_position) - body.radius
	if altitude <= space_altitude:
		return gravity_multiplier
	return gravity_multiplier * space_gravity_multiplier

func _land_on_surface(body: OrbitalBody, hit_pos: Vector3, hit_normal: Vector3) -> void:
	_state = State.SLITHERING
	_landed_body = body
	_surface_normal = hit_normal.normalized() if hit_normal.length() > 0.1 else (hit_pos - body.global_position).normalized()
	up_direction = _surface_normal
	velocity = Vector3.ZERO
	global_position = body.global_position + _surface_normal * (body.radius + 0.06)
	# Once slithering, the surface is tracked by direct reprojection every
	# frame (see _process_slithering) rather than physics collision against
	# it - colliding with the very body you're gliding along would truncate
	# your tangential motion to almost nothing every single frame. Keep
	# colliding with players/npcs only, for hit detection.
	collision_mask = 2 | 8

func _process_slithering(delta: float) -> void:
	if not is_instance_valid(_landed_body) or _landed_body.is_shattered:
		_expire()
		return

	var to_center: Vector3 = global_position - _landed_body.global_position
	if to_center.length_squared() < 0.0001:
		to_center = _surface_normal
	_surface_normal = to_center.normalized()
	up_direction = _surface_normal

	_update_target(delta)

	var new_dir: Vector3 = _steer_toward_target(delta)

	velocity = new_dir * slither_speed
	var motion: Vector3 = velocity * delta
	var collision: KinematicCollision3D = move_and_collide(motion)
	if collision:
		var collider: Object = collision.get_collider()
		if collider and collider != owner_player and collider.has_method("apply_damage"):
			_hit_player(collider, collision.get_position())
			return

	# A building wall a body-length ahead, in the direction we're actually
	# crawling - move_and_collide above can't see it (collision_mask excludes
	# layer 1 while slithering, on purpose - see _land_on_surface), so pathing
	# onto one has to be a deliberate probe instead. Planet surface hits
	# (orbital_body meta) are the ground we're already on, not a wall to climb.
	if new_dir.length_squared() > 0.0001:
		var probe: Dictionary = _probe_wall(new_dir, slither_speed * delta + 0.6)
		if not probe.is_empty():
			_start_climbing(probe.collider, probe.position, probe.normal)
			return

	# Re-snap exactly onto the current surface radius every frame so the
	# slug hugs the curve instead of drifting off it tangentially.
	var new_to_center: Vector3 = global_position - _landed_body.global_position
	if new_to_center.length_squared() > 0.0001:
		global_position = _landed_body.global_position + new_to_center.normalized() * (_landed_body.radius + 0.06)

	if new_dir.length_squared() > 0.0001:
		look_at(global_position + new_dir, _surface_normal)

## Shared target-refresh for SLITHERING/CLIMBING: drops a dead/invalid target
## immediately, but otherwise only re-evaluates on `retarget_interval` rather
## than every frame, so a slug doesn't flicker between two similarly-close
## targets - it commits, but periodically checks whether something better
## (closer, or just newly in range/line of sight) has shown up.
func _update_target(delta: float) -> void:
	if _target != null and (not is_instance_valid(_target) or ("is_dead" in _target and _target.is_dead)):
		_target = null
	_retarget_timer -= delta
	if _target == null or _retarget_timer <= 0.0:
		_retarget_timer = retarget_interval
		var candidate: Node3D = _find_target()
		if candidate != null:
			_target = candidate

## Desired tangential direction (toward `_target`, projected onto the plane
## perpendicular to `_surface_normal`, or the current heading if there's no
## target), turned toward at up to `turn_rate_degrees`/sec. Used identically
## by SLITHERING (surface_normal = planet radial) and CLIMBING (surface_normal
## = the wall's own normal) - chasing the target's raw position and only
## discarding the normal component is what makes CLIMBING drift upward
## without any separate "climb toward height" logic: a target standing higher
## up the wall pulls the tangential component up right along with it.
func _steer_toward_target(delta: float) -> Vector3:
	var desired_dir: Vector3
	if _target:
		var to_target: Vector3 = _target.global_position - global_position
		desired_dir = to_target - _surface_normal * to_target.dot(_surface_normal)
	else:
		desired_dir = velocity - _surface_normal * velocity.dot(_surface_normal)
	if desired_dir.length_squared() < 0.0001:
		var fallback: Vector3 = global_transform.basis.x
		desired_dir = fallback - _surface_normal * fallback.dot(_surface_normal)
	desired_dir = desired_dir.normalized() if desired_dir.length_squared() > 0.0001 else -global_transform.basis.z

	var current_dir: Vector3 = velocity.normalized() if velocity.length() > 0.01 else desired_dir
	var max_turn: float = deg_to_rad(turn_rate_degrees) * delta
	var angle: float = current_dir.angle_to(desired_dir)
	return desired_dir if (angle <= max_turn or angle < 0.0001) else current_dir.slerp(desired_dir, max_turn / angle)

## CLIMBING's own steering, separate from SLITHERING's _steer_toward_target():
## a wall panel is flat and BOUNDED (a window/doorway cutout or the panel's
## own edge can be a meter away in any lateral direction), unlike a planet's
## continuous sphere - chasing the target's raw direction the way SLITHERING
## does walks a climbing slug off the edge of the panel almost immediately.
## Climbs mostly straight up the wall instead (matches how a real panel is
## shaped: much taller than any one piece is wide), with just enough lateral
## pull toward the target to end up above them rather than climbing blind.
func _steer_climbing(delta: float) -> Vector3:
	var up_tangent: Vector3 = _climb_up_ref - _surface_normal * _climb_up_ref.dot(_surface_normal)
	up_tangent = up_tangent.normalized() if up_tangent.length_squared() > 0.0001 else Vector3.RIGHT

	var target_tangent: Vector3 = Vector3.ZERO
	if _target:
		var to_target: Vector3 = _target.global_position - global_position
		var raw: Vector3 = to_target - _surface_normal * to_target.dot(_surface_normal)
		if raw.length_squared() > 0.0001:
			target_tangent = raw.normalized()

	# A real wall panel is only a few meters wide - even a modest constant
	# lateral pull toward the target, sustained over a few seconds of
	# climbing, walks the slug straight off the side edge into open air (no
	# probe hit there at all) well before it reaches anything worth climbing
	# for. A restoring pull back toward the vertical line it first grabbed
	# the wall on keeps the target-homing purely a light nudge instead.
	var side_axis: Vector3 = _surface_normal.cross(up_tangent).normalized()
	var side_drift: float = (global_position - _climb_start_pos).dot(side_axis)
	var side_restore: float = -clampf(side_drift / 2.5, -1.0, 1.0)

	var desired_dir: Vector3 = (up_tangent * 0.82 + target_tangent * 0.12 + side_axis * side_restore * 0.3)
	desired_dir = desired_dir.normalized() if desired_dir.length_squared() > 0.0001 else up_tangent

	var current_dir: Vector3 = velocity.normalized() if velocity.length() > 0.01 else desired_dir
	var max_turn: float = deg_to_rad(turn_rate_degrees) * delta
	var angle: float = current_dir.angle_to(desired_dir)
	return desired_dir if (angle <= max_turn or angle < 0.0001) else current_dir.slerp(desired_dir, max_turn / angle)

## Short ray in direction `dir` looking for a wall to climb - a StaticBody3D
## that isn't the planet we're already standing on. Empty dict if nothing's
## there (or it's just more of the same planet surface).
func _probe_wall(dir: Vector3, distance: float) -> Dictionary:
	var space_state := get_world_3d().direct_space_state
	var from: Vector3 = global_position + _surface_normal * 0.15
	var query := PhysicsRayQueryParameters3D.create(from, from + dir.normalized() * distance)
	query.collision_mask = 1
	query.exclude = [self]
	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return {}
	var collider: Object = result.collider
	if collider is StaticBody3D and not collider.has_meta("orbital_body"):
		return result
	return {}

func _start_climbing(body: StaticBody3D, hit_pos: Vector3, hit_normal: Vector3) -> void:
	_state = State.CLIMBING
	_climb_body = body
	_climb_start_pos = hit_pos
	_climb_host_body = GravityManager.get_nearest_body(hit_pos)
	_climb_up_ref = (hit_pos - _climb_host_body.global_position).normalized() if is_instance_valid(_climb_host_body) else Vector3.UP
	_surface_normal = hit_normal.normalized() if hit_normal.length() > 0.1 else -velocity.normalized()
	up_direction = _surface_normal
	velocity = Vector3.ZERO
	global_position = hit_pos + _surface_normal * 0.06
	# Same as SLITHERING: the wall is tracked by direct reprojection
	# (_probe_wall re-snap below), not physics collision against it.
	collision_mask = 2 | 8

func _process_climbing(delta: float) -> void:
	if not is_instance_valid(_climb_body):
		_give_up_climbing()
		return

	_update_target(delta)
	var new_dir: Vector3 = _steer_climbing(delta)

	velocity = new_dir * slither_speed
	var motion: Vector3 = velocity * delta
	var collision: KinematicCollision3D = move_and_collide(motion)
	if collision:
		var collider: Object = collision.get_collider()
		if collider and collider != owner_player and collider.has_method("apply_damage"):
			_hit_player(collider, collision.get_position())
			return

	# Re-snap onto the wall by probing straight into it along the last known
	# normal - this is what lets the slug follow the wall around shallow
	# curvature/corners instead of drifting off at a tangent. Losing the wall
	# entirely (climbed over the top, or past a corner too sharp to follow)
	# drops it back to FLYING so gravity takes back over instead of leaving it
	# stuck floating at the last surface point.
	var result: Dictionary = _probe_climb_surface()
	if result.is_empty():
		_give_up_climbing()
		return
	_surface_normal = result.normal.normalized() if result.normal.length() > 0.1 else _surface_normal
	up_direction = _surface_normal
	global_position = result.position + _surface_normal * 0.06

	# Radial-outward progress from the host planet, since a building's "up"
	# is that planet's local radial direction (see Building.gd) rather than
	# world +Y. Climbed high enough for long enough without reaching the
	# target - give up and go back to hunting at ground level instead of
	# scaling the whole tower forever.
	if is_instance_valid(_climb_host_body):
		var radial: Vector3 = (global_position - _climb_host_body.global_position).normalized()
		var climbed: float = (global_position - _climb_start_pos).dot(radial)
		if climbed > max_climb_height:
			_give_up_climbing()
			return

	if new_dir.length_squared() > 0.0001:
		look_at(global_position + new_dir, _surface_normal)

## Looks for the wall straight ahead along the last known surface normal,
## same as SLITHERING's own re-snap - but tries a small cross-pattern of
## points around the current position (not just the exact center), not just
## once: a wall built from several curvature-compensated segments
## (Building._segments_for) can have a hairline seam between adjacent pieces,
## and a single ray landing exactly on one is enough to miss both. Returns
## the first hit against `_climb_body`, or {} if the wall's genuinely gone
## (an edge, a corner, or the open observation deck above the top floor).
func _probe_climb_surface() -> Dictionary:
	var space_state := get_world_3d().direct_space_state
	var side_axis: Vector3 = _surface_normal.cross(global_transform.basis.y)
	if side_axis.length_squared() < 0.0001:
		side_axis = _surface_normal.cross(Vector3.RIGHT)
	side_axis = side_axis.normalized() if side_axis.length_squared() > 0.0001 else Vector3.RIGHT
	var up_axis: Vector3 = _surface_normal.cross(side_axis).normalized()
	var offsets: Array[Vector3] = [
		Vector3.ZERO, side_axis * 0.25, -side_axis * 0.25, up_axis * 0.25, -up_axis * 0.25,
	]
	for offset in offsets:
		var center: Vector3 = global_position + offset
		var query := PhysicsRayQueryParameters3D.create(center + _surface_normal * 0.9, center - _surface_normal * 0.9)
		query.collision_mask = 1
		query.exclude = [self]
		var result: Dictionary = space_state.intersect_ray(query)
		if not result.is_empty() and result.collider == _climb_body:
			return result
	return {}

## Drops off the wall back into FLYING, carrying current tangential speed, so
## gravity/the planet below take back over instead of the slug getting stuck.
func _give_up_climbing() -> void:
	_state = State.FLYING
	_climb_body = null
	collision_mask = 1 | 2 | 8

func _find_target() -> Node3D:
	var best: Node3D = null
	var best_dist: float = tracking_range
	for node in get_tree().get_nodes_in_group("damageable"):
		# Slug itself is in "damageable" too (so other weapons can shoot it
		# down mid-flight - see apply_damage above); excluding only
		# owner_player left a slug with no owner_player set (bypassed launch(),
		# as WeaponProbe's SLUGTOWER test does) free to "target" itself at
		# distance 0, every single check.
		if node == owner_player or node == self or not is_instance_valid(node):
			continue
		if "is_dead" in node and node.is_dead:
			continue
		var dist: float = global_position.distance_to(node.global_position)
		if dist > tracking_range:
			continue
		if dist < best_dist:
			best_dist = dist
			best = node
	return best

func _hit_player(collider: Object, hit_position: Vector3) -> void:
	if collider.has_method("network_apply_damage") and not collider.is_multiplayer_authority():
		collider.rpc_id(collider.get_multiplayer_authority(), "network_apply_damage", damage, owner_player.get_path() if owner_player else NodePath(), hit_position, "Slug Launcher")
	else:
		collider.apply_damage(damage, owner_player, hit_position, "Slug Launcher")
	queue_free()
