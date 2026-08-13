class_name Bot
extends Player

enum AiState { WANDER, ENGAGE, FLEE }

## Loadout slots, matching the order WeaponManager._ready() adds them.
const WEAPON_ROCKET := 0
const WEAPON_RAILGUN := 1
const WEAPON_SLUG := 2
const WEAPON_GRAPPLE := 3
const WEAPON_BOARD := 4

const BOT_NAMES: Array[String] = [
	"Xargon", "Blastrix", "Voidwing", "Krak", "Zephyra", "Pulsar", "Nibor",
	"Strikex", "Nullform", "Cygnia", "Mortex", "Vox", "Skullfire", "Zaptor",
	"Grimweld", "Nebulax", "Smashkov", "Phaseron", "Quakron", "Rocketrix",
	"Boneclaw", "Craterface", "Voidmaw", "Starbane", "Killswitch", "Driftex",
	"Pyroclaw", "Gorgax", "Splinter", "Desolax", "Wraithex", "Blasteroid"
]

@export var sight_range: float = 180.0
@export var max_turn_speed_degrees: float = 220.0
@export var wander_interval: float = 5.0
@export var retarget_interval: float = 0.25
@export var preferred_combat_range_min: float = 8.0
@export var preferred_combat_range_max: float = 40.0
## Base accuracy: 0 = perfect, higher = more error in degrees
@export var aim_error_min_deg: float = 2.0
@export var aim_error_max_deg: float = 14.0

var _state: AiState = AiState.WANDER
var _target: Player = null
var _wander_point: Vector3 = Vector3.ZERO
var _retarget_timer: float = 0.0
var _wander_timer: float = 0.0
var _strafe_dir: float = 1.0

var _ai_move_axis := Vector2.ZERO
var _ai_desired_dir: Vector3 = Vector3.ZERO
var _ai_wants_fire: bool = false
var _ai_wants_jump: bool = false
var _ai_wants_melee: bool = false
var _ai_weapon_index: int = -1
## Fire is pulsed rather than held: the railgun only shoots on RELEASE (it
## charges while held), so a bot that held the trigger forever would charge to
## full and never actually fire. Other weapons just get a natural burst rhythm
## out of the same mechanism.
var _fire_holding: bool = false
var _fire_phase: float = 0.0

func _uses_mouse_look() -> bool:
	return false

## Bots take the same boundary-launch spawn as humans, but choose fast: 31 of
## them sitting out the full 10s human aim window would leave the arena empty.
func get_spawn_aim_window() -> float:
	return randf_range(0.5, 2.5)

## Spread across the whole arena instead of all defaulting to the nearest rock.
func pick_spawn_target() -> OrbitalBody:
	var bodies: Array[OrbitalBody] = GravityManager.get_bodies()
	var usable: Array[OrbitalBody] = []
	for body in bodies:
		if is_instance_valid(body) and not body.is_shattered and body.radius >= 5.0:
			usable.append(body)
	if usable.is_empty():
		return super.pick_spawn_target()
	return usable[randi() % usable.size()]

func _is_local_view() -> bool:
	return false

func _ready() -> void:
	## Pick a random bot name if none assigned yet
	if display_name == "Player":
		display_name = BOT_NAMES[randi() % BOT_NAMES.size()]
	# Stagger re-targeting across a random phase instead of every bot starting
	# at the same _retarget_timer = 0.0 and counting down by the same shared
	# delta every tick after that - left alone, that keeps them permanently
	# lockstepped, so a full match's worth of _find_enemy() line-of-sight
	# raycasts (measured: ~30 bots, 0.73ms) all land on the SAME physics frame
	# every 0.25s instead of being spread across it. A one-time random offset
	# here keeps every bot's own 0.25s cadence but at a different phase, so
	# the same total cost lands as a steady trickle instead of a periodic burst.
	_retarget_timer = randf_range(0.0, retarget_interval)
	super._ready()

func _physics_process(delta: float) -> void:
	if is_multiplayer_authority() and not is_dead:
		_think(delta)
		_steer_toward(_ai_desired_dir, delta)
	super._physics_process(delta)

func _think(delta: float) -> void:
	_retarget_timer -= delta
	if _retarget_timer <= 0.0:
		_retarget_timer = retarget_interval
		_target = _find_enemy()
		var here: OrbitalBody = get_frame_body()
		if here != null and is_instance_valid(here) and here.is_under_threat():
			# Survival beats a fight in progress - a bot mid-ENGAGE on a planet
			# that's about to come apart drops its target and runs instead.
			_state = AiState.FLEE
		else:
			_state = AiState.ENGAGE if _target != null else AiState.WANDER

	_ai_wants_fire = false
	_ai_wants_melee = false
	_ai_wants_jump = false
	_ai_weapon_index = -1

	match _state:
		AiState.FLEE:
			_do_flee(delta)
		AiState.ENGAGE:
			if is_instance_valid(_target) and not _target.is_dead:
				_do_engage(delta)
			else:
				_do_wander(delta)
		_:
			_do_wander(delta)

	_update_fire_pulse(delta)

## A Planet Buster shell has this bot's current planet locked - get off it.
## Reaches for the Space Board (free 6-axis flight, see SpaceBoard.gd) and
## flies straight along the surface normal rather than trying to out-walk a
## planet-sized explosion. _retarget_timer re-checks is_under_threat() every
## retarget_interval, so this naturally clears back to WANDER/ENGAGE once
## either the bot has cleared the body or the threat itself resolves.
func _do_flee(_delta: float) -> void:
	var body: OrbitalBody = get_frame_body()
	if body == null or not is_instance_valid(body):
		# Already off the surface - keep flying straight until the next
		# think() re-evaluates.
		_ai_desired_dir = get_look_direction()
	else:
		_ai_desired_dir = (global_position - body.global_position).normalized()
	_ai_move_axis = Vector2(0.0, 1.0)
	_ai_weapon_index = WEAPON_BOARD
	_ai_wants_jump = true

func _do_engage(_delta: float) -> void:
	var eye: Vector3 = camera.global_position
	var dist: float = eye.distance_to(_target.global_position)

	## Lead the target for slow weapons (rocket, slug)
	var aim_pos: Vector3 = _predict_target_pos(dist)

	var to_aim: Vector3 = aim_pos - eye
	## Apply random accuracy error
	var error_rad: float = deg_to_rad(randf_range(aim_error_min_deg, aim_error_max_deg))
	var perp: Vector3 = to_aim.cross(Vector3.UP)
	if perp.length_squared() < 0.001:
		perp = to_aim.cross(Vector3.RIGHT)
	perp = perp.normalized()
	var error_angle: float = randf_range(-error_rad, error_rad)
	to_aim = to_aim.rotated(perp.normalized(), error_angle)
	_ai_desired_dir = to_aim.normalized()

	var forward_amount: float = 0.0
	if dist > preferred_combat_range_max:
		forward_amount = 1.0
	elif dist < preferred_combat_range_min:
		forward_amount = -1.0
	if randf() < 0.01:
		_strafe_dir *= -1.0
	_ai_move_axis = Vector2(_strafe_dir * 0.7, forward_amount)

	if dist < 3.0:
		_ai_wants_melee = true
	else:
		_ai_weapon_index = _choose_weapon(dist)

	var facing_error_deg: float = rad_to_deg(get_look_direction().angle_to(_ai_desired_dir))
	var aimed: bool = facing_error_deg <= aim_error_max_deg * 0.5 + 4.0
	# The board and the hook are traversal tools, not shots - they get used to
	# reach the fight rather than only when perfectly on target.
	if _ai_weapon_index == WEAPON_BOARD or _ai_weapon_index == WEAPON_GRAPPLE:
		aimed = facing_error_deg <= 35.0
	_ai_wants_fire = aimed and _fire_holding

	if randf() < 0.004:
		_ai_wants_jump = true

## Picks the right tool for the range, and reaches for the traversal gear when
## there is real distance to close rather than only ever trading shots.
func _choose_weapon(dist: float) -> int:
	# Adrift in open space with the target far off: ride the board over.
	if dist > 60.0 and _distance_to_nearest_surface() > 10.0:
		return WEAPON_BOARD
	# Far, but with ground nearby to bite into: swing across on the hook.
	if dist > 85.0:
		return WEAPON_GRAPPLE
	if dist > 50.0:
		return WEAPON_RAILGUN
	if dist > preferred_combat_range_min:
		return WEAPON_SLUG if randf() < 0.3 else WEAPON_ROCKET
	return WEAPON_ROCKET

## Alternates the trigger so charge-on-release weapons actually discharge.
func _update_fire_pulse(delta: float) -> void:
	_fire_phase -= delta
	if _fire_phase > 0.0:
		return
	_fire_holding = not _fire_holding
	match _ai_weapon_index:
		WEAPON_RAILGUN:
			# Long enough to build most of a charge, then a clean release.
			_fire_phase = randf_range(0.9, 1.6) if _fire_holding else 0.3
		WEAPON_BOARD:
			_fire_phase = randf_range(1.2, 2.2) if _fire_holding else 0.2
		WEAPON_GRAPPLE:
			# The hook detaches on release, so hold long enough for a real pull.
			_fire_phase = randf_range(1.0, 2.0) if _fire_holding else 0.7
		_:
			_fire_phase = randf_range(0.3, 0.7) if _fire_holding else randf_range(0.2, 0.5)

## Predict where a slow projectile will intercept the target.
func _predict_target_pos(dist_to_target: float) -> Vector3:
	if _target == null or not is_instance_valid(_target):
		return Vector3.ZERO
	## Only lead for slow weapons (rocket ~26, slug ~10); railgun is instant
	var weapon_speed: float = 26.0
	if _ai_weapon_index == WEAPON_RAILGUN:
		return _target.global_position  ## hitscan, no lead needed
	if _ai_weapon_index == WEAPON_SLUG:
		weapon_speed = 10.0
	var time_to_hit: float = dist_to_target / max(weapon_speed, 1.0)
	return _target.global_position + _target.get_world_velocity() * time_to_hit

func _do_wander(_delta: float) -> void:
	_wander_timer -= _delta
	if _wander_timer <= 0.0 or global_position.distance_to(_wander_point) < 4.0:
		_wander_timer = wander_interval
		_wander_point = _pick_wander_point()

	var to_point: Vector3 = _wander_point - global_position
	if to_point.length() > 0.5:
		_ai_desired_dir = to_point.normalized()
		_ai_move_axis = Vector2(0.0, 1.0)
	else:
		_ai_desired_dir = get_look_direction()
		_ai_move_axis = Vector2.ZERO
	if randf() < 0.002:
		_ai_wants_jump = true

func _pick_wander_point() -> Vector3:
	var body: OrbitalBody = GravityManager.get_nearest_body(global_position)
	if body == null:
		return global_position + (-global_transform.basis.z) * 10.0
	var rand_dir := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
	return body.global_position + rand_dir * (body.radius + 1.5)

## Bots target any damageable node that isn't themselves — including other bots.
func _find_enemy() -> Player:
	var best: Player = null
	var best_dist: float = sight_range
	var eye: Vector3 = camera.global_position
	for node in get_tree().get_nodes_in_group("players"):
		if node == self or not is_instance_valid(node):
			continue
		if "is_dead" in node and node.is_dead:
			continue
		var dist: float = eye.distance_to(node.global_position)
		if dist > best_dist:
			continue
		if _has_line_of_sight(eye, node.global_position):
			best_dist = dist
			best = node
	return best

func _has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var result: Dictionary = space_state.intersect_ray(query)
	return result.is_empty()

func _steer_toward(desired_dir: Vector3, delta: float) -> void:
	if desired_dir.length_squared() < 0.0001:
		return
	var max_step: float = deg_to_rad(max_turn_speed_degrees) * delta
	var up: Vector3 = up_direction
	var current_forward: Vector3 = -global_transform.basis.z
	var cf_flat: Vector3 = (current_forward - up * current_forward.dot(up))
	var df_flat: Vector3 = (desired_dir - up * desired_dir.dot(up))
	if cf_flat.length_squared() > 0.0001 and df_flat.length_squared() > 0.0001:
		cf_flat = cf_flat.normalized()
		df_flat = df_flat.normalized()
		var yaw_angle: float = cf_flat.angle_to(df_flat)
		var yaw_sign: float = 1.0 if cf_flat.cross(df_flat).dot(up) >= 0.0 else -1.0
		var yaw_step: float = min(yaw_angle, max_step) * yaw_sign
		global_transform.basis = global_transform.basis.rotated(up, yaw_step).orthonormalized()

	var desired_pitch: float = asin(clamp(desired_dir.dot(up), -1.0, 1.0))
	var pitch_limit: float = deg_to_rad(pitch_limit_degrees)
	desired_pitch = clamp(desired_pitch, -pitch_limit, pitch_limit)
	head.rotation.x = move_toward(head.rotation.x, desired_pitch, max_step)

func _get_move_axis() -> Vector2: return _ai_move_axis
func _get_look_delta() -> Vector2: return Vector2.ZERO
func _wants_jump() -> bool: return _ai_wants_jump
func _wants_descend() -> bool: return false
func _wants_fire() -> bool: return _ai_wants_fire
func _wants_aim() -> bool: return false
func _wants_scoreboard() -> bool: return false
func _wants_melee() -> bool: return _ai_wants_melee
func _wants_interact() -> bool: return false ## bots never crew the Gunship
func _get_weapon_switch() -> int: return _ai_weapon_index
func _get_weapon_scroll() -> int: return 0
