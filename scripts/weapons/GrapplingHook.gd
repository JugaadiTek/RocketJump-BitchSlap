class_name GrapplingHook
extends Weapon
## Fires a raycast. Hits:
##   - Static geometry (planet, tower): reels the player toward the hit point
##     at pull_speed m/s, grants impulse_grace so ground-stick doesn't fight it.
##   - Player/Bot: pulls THEM toward the shooter at the same speed.
## Release fire to detach. Re-fire while attached to jump to a new point.

@export var max_range: float = 300.0
@export var pull_speed: float = 35.0
@export var pull_timeout: float = 6.0  ## auto-detach after this many seconds

func _init() -> void:
	weapon_name = "Grappling Hook"
	fire_cooldown = 0.4
	weapon_color = Color(0.85, 0.5, 0.15)

enum HookState { IDLE, PULLING_SELF, PULLING_TARGET }
var _hook_state: HookState = HookState.IDLE
var _hook_point: Vector3 = Vector3.ZERO
var _pull_target: Node3D = null  ## non-null when pulling another player/bot
var _pull_timer: float = 0.0
var _prev_fire_held: bool = false
var _rope_end: Vector3 = Vector3.ZERO

func tick(delta: float, fire_held: bool) -> void:
	var just_released: bool = not fire_held and _prev_fire_held
	_prev_fire_held = fire_held

	if _hook_state != HookState.IDLE:
		_pull_timer -= delta
		if just_released or _pull_timer <= 0.0:
			_detach()
			return
		_do_pull(delta)

func _do_pull(delta: float) -> void:
	if owner_player == null:
		return
	var p: Player = owner_player as Player
	if p == null:
		return

	if _hook_state == HookState.PULLING_SELF:
		var to_point: Vector3 = _hook_point - p.global_position
		if to_point.length() < 2.0:
			_detach()
			return
		p.velocity = p.velocity.lerp(to_point.normalized() * pull_speed, 0.25)
		p._impulse_grace_remaining = max(p._impulse_grace_remaining, 0.1)
		_rope_end = _hook_point

	elif _hook_state == HookState.PULLING_TARGET:
		if not is_instance_valid(_pull_target) or ("is_dead" in _pull_target and _pull_target.is_dead):
			_detach()
			return
		var to_player: Vector3 = p.global_position - _pull_target.global_position
		if to_player.length() < 3.0:
			_detach()
			return
		if _pull_target.has_method("apply_impulse"):
			_pull_target.apply_impulse(to_player.normalized() * pull_speed * delta * 6.0)
		_rope_end = _pull_target.global_position

func _detach() -> void:
	_hook_state = HookState.IDLE
	_pull_target = null

func can_fire() -> bool:
	return _cooldown_remaining <= 0.0

func _do_fire(muzzle_transform: Transform3D, aim_direction: Vector3) -> void:
	_detach()
	var space_state := get_world_3d().direct_space_state
	var from: Vector3 = muzzle_transform.origin
	var to: Vector3 = from + aim_direction * max_range
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1 | 2 | 8
	if owner_player:
		query.exclude = [owner_player]
	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return
	var collider: Object = result.collider
	if collider is StaticBody3D:
		_hook_state = HookState.PULLING_SELF
		_hook_point = result.position
		_pull_timer = pull_timeout
	elif collider and collider.has_method("apply_impulse"):
		_hook_state = HookState.PULLING_TARGET
		_pull_target = collider as Node3D
		_pull_timer = pull_timeout

func get_rope_end() -> Vector3:
	return _rope_end

func is_attached() -> bool:
	return _hook_state != HookState.IDLE
