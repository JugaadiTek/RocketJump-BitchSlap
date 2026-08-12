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

enum State { FLYING, SLITHERING }

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

var _hp: float = 25.0

var _state: State = State.FLYING
var _landed_body: OrbitalBody = null
var _surface_normal: Vector3 = Vector3.UP
var _target: Node3D = null

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
	match _state:
		State.FLYING:
			_process_flying(delta)
		State.SLITHERING:
			_process_slithering(delta)

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

	if _target != null and (not is_instance_valid(_target) or ("is_dead" in _target and _target.is_dead)):
		_target = null
	if _target == null:
		_target = _find_target()

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
	var new_dir: Vector3 = desired_dir if (angle <= max_turn or angle < 0.0001) else current_dir.slerp(desired_dir, max_turn / angle)

	velocity = new_dir * slither_speed
	var motion: Vector3 = velocity * delta
	var collision: KinematicCollision3D = move_and_collide(motion)
	if collision:
		var collider: Object = collision.get_collider()
		if collider and collider != owner_player and collider.has_method("apply_damage"):
			_hit_player(collider, collision.get_position())
			return

	# Re-snap exactly onto the current surface radius every frame so the
	# slug hugs the curve instead of drifting off it tangentially.
	var new_to_center: Vector3 = global_position - _landed_body.global_position
	if new_to_center.length_squared() > 0.0001:
		global_position = _landed_body.global_position + new_to_center.normalized() * (_landed_body.radius + 0.06)


	if new_dir.length_squared() > 0.0001:
		look_at(global_position + new_dir, _surface_normal)

func _find_target() -> Node3D:
	var best: Node3D = null
	var best_dist: float = tracking_range
	for node in get_tree().get_nodes_in_group("damageable"):
		if node == owner_player or not is_instance_valid(node):
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
