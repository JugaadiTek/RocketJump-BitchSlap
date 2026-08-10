class_name GrapplingHook
extends Weapon
## Fires a physical hook head that pays out a visible cable as it flies, then
## bites whatever the shot was aimed at:
##   - Static geometry (planet, tower): reels the player toward the anchor at
##     pull_speed m/s, granting impulse_grace so ground-stick doesn't fight it.
##   - Player/Bot: pulls THEM toward the shooter at the same speed.
## A shot that hits nothing still throws the full length of cable and reels it
## back in. Release fire to detach and retract; the hook can't be re-fired until
## the cable is fully back, so holding fire keeps the current bite rather than
## re-hooking every cooldown.

@export var max_range: float = 300.0
@export var pull_speed: float = 35.0
@export var pull_timeout: float = 6.0  ## auto-detach after this many seconds
@export var hook_travel_speed: float = 220.0  ## m/s, cable pay-out and reel-in rate

func _init() -> void:
	weapon_name = "Grappling Hook"
	fire_cooldown = 0.4
	weapon_color = Color(0.85, 0.5, 0.15)

enum HookState { IDLE, FLYING, PULLING_SELF, PULLING_TARGET, RETRACTING }
## What the hook will bite once it finishes flying out.
enum HookBite { NONE, ANCHOR, TARGET }

var _hook_state: HookState = HookState.IDLE
var _pending_bite: HookBite = HookBite.NONE
## Current world position of the hook head - the far end of the drawn cable.
var _hook_pos: Vector3 = Vector3.ZERO
## The anchor is stored as a node plus a local-space offset rather than a world
## point, because every planet in this arena orbits and spins: a cable pinned to
## a fixed world position would visibly tear away from the rock it bit into.
var _anchor_node: Node3D = null
var _anchor_local: Vector3 = Vector3.ZERO
var _pull_target: Node3D = null  ## non-null when pulling another player/bot
var _pull_timer: float = 0.0
var _prev_fire_held: bool = false
var _rope_end: Vector3 = Vector3.ZERO


func tick(delta: float, fire_held: bool) -> void:
	var just_released: bool = not fire_held and _prev_fire_held
	_prev_fire_held = fire_held

	match _hook_state:
		HookState.FLYING:
			if just_released:
				_begin_retract()
			else:
				_advance_hook(delta, _current_anchor_point())
		HookState.PULLING_SELF, HookState.PULLING_TARGET:
			_pull_timer -= delta
			if just_released or _pull_timer <= 0.0:
				_begin_retract()
			else:
				_do_pull(delta)
		HookState.RETRACTING:
			_advance_hook(delta, _muzzle_point())

	_update_cable()

## Moves the hook head toward `goal`, returning it to IDLE (retracting) or
## biting (flying out) once it gets there.
func _advance_hook(delta: float, goal: Vector3) -> void:
	var to_goal: Vector3 = goal - _hook_pos
	var step: float = hook_travel_speed * delta
	if to_goal.length() <= step:
		_hook_pos = goal
		if _hook_state == HookState.RETRACTING:
			_hook_state = HookState.IDLE
		else:
			if _pending_bite != HookBite.NONE:
				Sfx.play_3d("grapple_hit", _hook_pos, 1.0, -1.0)
			_on_hook_landed()
		return
	_hook_pos += to_goal.normalized() * step

func _on_hook_landed() -> void:
	match _pending_bite:
		HookBite.ANCHOR:
			_hook_state = HookState.PULLING_SELF
			_pull_timer = pull_timeout
		HookBite.TARGET:
			if is_instance_valid(_pull_target):
				_hook_state = HookState.PULLING_TARGET
				_pull_timer = pull_timeout
			else:
				_begin_retract()
		_:
			_begin_retract()

func _begin_retract() -> void:
	_hook_state = HookState.RETRACTING
	_pull_target = null
	_anchor_node = null
	_pending_bite = HookBite.NONE

func _do_pull(delta: float) -> void:
	if owner_player == null:
		return
	var p: Player = owner_player as Player
	if p == null:
		return

	if _hook_state == HookState.PULLING_SELF:
		var anchor: Vector3 = _current_anchor_point()
		_hook_pos = anchor
		var to_point: Vector3 = anchor - p.global_position
		if to_point.length() < 2.0:
			_begin_retract()
			return
		# The anchor is a world point, so reel in world space and let the player
		# convert back into whatever planet frame it's riding.
		p.set_world_velocity(p.get_world_velocity().lerp(to_point.normalized() * pull_speed, 0.25))
		p._impulse_grace_remaining = max(p._impulse_grace_remaining, 0.1)

	elif _hook_state == HookState.PULLING_TARGET:
		if not is_instance_valid(_pull_target) or ("is_dead" in _pull_target and _pull_target.is_dead):
			_begin_retract()
			return
		_hook_pos = _pull_target.global_position
		var to_player: Vector3 = p.global_position - _pull_target.global_position
		if to_player.length() < 3.0:
			_begin_retract()
			return
		if _pull_target.has_method("apply_impulse"):
			_pull_target.apply_impulse(to_player.normalized() * pull_speed * delta * 6.0)

## Where the far end of the cable should currently be: the anchor point carried
## along by whatever node it bit into, the live position of a hooked player, or
## (for a shot that hit nothing) the point in space the cable was thrown at.
func _current_anchor_point() -> Vector3:
	if _pending_bite == HookBite.TARGET and is_instance_valid(_pull_target):
		return _pull_target.global_position
	if _anchor_node != null and is_instance_valid(_anchor_node):
		return _anchor_node.global_transform * _anchor_local
	return _rope_end

func _muzzle_point() -> Vector3:
	if owner_player and owner_player.has_method("get_muzzle_transform"):
		return owner_player.get_muzzle_transform().origin
	return global_position

## Publishes the cable's far end onto the Player, where HookVisual draws it and
## the MultiplayerSynchronizer replicates it. Rendering deliberately does not
## happen here: this node lives inside the weapon viewmodel, which is hidden for
## every view but the local one, so a cable drawn here would be invisible to
## everybody else.
func _update_cable() -> void:
	var p: Player = owner_player as Player
	if p == null:
		return
	if _hook_state == HookState.IDLE:
		p.hook_active = false
		return
	_rope_end = _hook_pos
	p.hook_active = true
	p.hook_end = _hook_pos

## Only fireable from a standing start: while a cable is out, holding fire keeps
## the current bite instead of re-hooking, and releasing retracts it.
func can_fire() -> bool:
	return _hook_state == HookState.IDLE and _cooldown_remaining <= 0.0

func _do_fire(muzzle_transform: Transform3D, aim_direction: Vector3) -> void:
	var space_state := get_world_3d().direct_space_state
	var from: Vector3 = muzzle_transform.origin
	var to: Vector3 = from + aim_direction * max_range
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1 | 2 | 8
	if owner_player:
		query.exclude = [owner_player]
	var result: Dictionary = space_state.intersect_ray(query)

	_hook_pos = from
	_anchor_node = null
	_pull_target = null
	_pending_bite = HookBite.NONE
	_rope_end = to

	if not result.is_empty():
		var collider: Object = result.collider
		_rope_end = result.position
		if collider is StaticBody3D:
			_pending_bite = HookBite.ANCHOR
			_anchor_node = collider as Node3D
			_anchor_local = _anchor_node.global_transform.affine_inverse() * result.position
		elif collider and collider.has_method("apply_impulse"):
			_pending_bite = HookBite.TARGET
			_pull_target = collider as Node3D

	_hook_state = HookState.FLYING
	Sfx.play_3d("grapple_fire", from, 1.0, -3.0)
	_update_cable()

func on_holster() -> void:
	# Nothing ticks a holstered weapon, so snap all the way back to IDLE rather
	# than retracting - otherwise the hook would still be biting when it's next
	# brought out.
	_begin_retract()
	_hook_state = HookState.IDLE
	_update_cable()

func get_rope_end() -> Vector3:
	return _rope_end

func is_attached() -> bool:
	return _hook_state == HookState.PULLING_SELF or _hook_state == HookState.PULLING_TARGET
