class_name Bot
extends Player
## Basic opponent AI. Reuses 100% of Player's movement/gravity/weapon code -
## it only overrides the `_get_*` input hooks to feed in AI-computed values
## instead of reading Input/mouse, plus its own yaw/pitch aiming since it has
## no mouse delta to work with (see `_steer_toward` below).
##
## Behavior is a minimal two-state loop: WANDER when no enemy is visible,
## ENGAGE when one is. Good enough to populate an arena and shoot back;
## not meant to be a competitive bot.

enum AiState { WANDER, ENGAGE }

@export var sight_range: float = 55.0
@export var max_turn_speed_degrees: float = 220.0
@export var wander_interval: float = 5.0
@export var retarget_interval: float = 0.25
@export var preferred_combat_range_min: float = 8.0
@export var preferred_combat_range_max: float = 24.0
@export var fire_angle_tolerance_degrees: float = 7.0

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

func _uses_mouse_look() -> bool:
	return false

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
		_state = AiState.ENGAGE if _target != null else AiState.WANDER

	_ai_wants_fire = false
	_ai_wants_melee = false
	_ai_wants_jump = false
	_ai_weapon_index = -1

	if _state == AiState.ENGAGE and is_instance_valid(_target) and not _target.is_dead:
		_do_engage(delta)
	else:
		_do_wander(delta)

func _do_engage(_delta: float) -> void:
	var eye: Vector3 = camera.global_position
	var to_target: Vector3 = _target.global_position - eye
	var dist: float = to_target.length()
	_ai_desired_dir = to_target.normalized()

	# Movement: hold a preferred range, strafing to make ourselves a harder target.
	var forward_amount: float = 0.0
	if dist > preferred_combat_range_max:
		forward_amount = 1.0
	elif dist < preferred_combat_range_min:
		forward_amount = -1.0
	if randf() < 0.01:
		_strafe_dir *= -1.0
	_ai_move_axis = Vector2(_strafe_dir * 0.7, forward_amount)

	# Weapon choice: melee if grabbing range, rocket mid-range, rail long range.
	if dist < 3.0:
		_ai_wants_melee = true
	elif dist < 28.0:
		_ai_weapon_index = 0 # rocket launcher
	else:
		_ai_weapon_index = 1 # railgun

	var facing_error_deg: float = rad_to_deg(get_look_direction().angle_to(_ai_desired_dir))
	if facing_error_deg <= fire_angle_tolerance_degrees:
		_ai_wants_fire = true

	if randf() < 0.004:
		_ai_wants_jump = true

func _do_wander(delta: float) -> void:
	_wander_timer -= delta
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
	var rand_dir: Vector3 = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
	if rand_dir.length_squared() < 0.001:
		rand_dir = Vector3.UP
	rand_dir = rand_dir.normalized()
	return body.global_position + rand_dir * (body.radius + 1.5)

func _find_enemy() -> Player:
	var best: Player = null
	var best_dist: float = sight_range
	var eye: Vector3 = camera.global_position
	for node in get_tree().get_nodes_in_group("players"):
		if node == self or not is_instance_valid(node):
			continue
		if node.is_dead:
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
	query.collision_mask = 1 # world/planets only
	var result: Dictionary = space_state.intersect_ray(query)
	return result.is_empty()

## Turns the bot's body (yaw) and head (pitch) toward `desired_dir`, clamped
## to max_turn_speed_degrees per second. Uses Godot's documented right-hand
## rotation convention directly instead of routing through the mouse-delta
## abstraction, since there's no real mouse input to fake here.
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

## ---- Input hooks ---------------------------------------------------------
func _get_move_axis() -> Vector2:
	return _ai_move_axis

func _get_look_delta() -> Vector2:
	return Vector2.ZERO # steering is applied directly in _steer_toward

func _wants_jump() -> bool:
	return _ai_wants_jump

func _wants_fire() -> bool:
	return _ai_wants_fire

func _wants_aim() -> bool:
	return false # bots don't ADS in this starter version

func _wants_melee() -> bool:
	return _ai_wants_melee

func _get_weapon_switch() -> int:
	return _ai_weapon_index

func _get_weapon_scroll() -> int:
	return 0 # bots pick weapons directly via _get_weapon_switch instead
