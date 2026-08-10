extends Node
## "The Bitchslap" - child of Player. Grabs the nearest enemy in a short
## cone in front of the attacker, then (after a brief grab/slap/piston-slam
## beat meant for animation hooks) instakills them and launches their body.
##
## Aim mostly DOWN (into the planet you're standing on) -> the victim gets
## launched straight out along their local "up", i.e. blasted off into orbit.
## Aim outward/sideways -> they go flying horizontally and can smack into
## another planet, perturbing its orbit just like a rocket would.
##
## The kill itself is resolved as soon as the grab connects (this is a
## starter kit, not a fully rewindable-hit-registration netcode); the
## windup/slap/slam timers below exist so you have clean hook points to
## trigger animations, camera shake, and SFX without touching the logic.

@export var corpse_scene: PackedScene
@export var grab_range: float = 3.0
@export var grab_cone_degrees: float = 50.0
@export var windup_time: float = 0.12
@export var slap_time: float = 0.1
@export var slam_time: float = 0.08
@export var cooldown: float = 0.9

@export_group("Launch")
@export var downward_slap_dot_threshold: float = 0.45 ## how "down" you must aim to trigger the orbit launch
@export var orbit_launch_strength: float = 26.0
@export var outward_launch_strength: float = 20.0
@export var outward_launch_lift: float = 6.0 ## small upward component so bodies arc instead of skimming the ground

enum State { IDLE, WINDUP, SLAP, SLAM }
var state: State = State.IDLE

@onready var _player: Player = get_parent()
var _cooldown_remaining: float = 0.0

func _process(delta: float) -> void:
	if _cooldown_remaining > 0.0:
		_cooldown_remaining -= delta

func try_activate() -> void:
	if state != State.IDLE or _cooldown_remaining > 0.0:
		return
	var target: Player = _find_target()
	if target == null:
		return
	_cooldown_remaining = cooldown
	Sfx.play_3d("slap", _player.global_position, 1.0, 2.0)
	_run_sequence(target)

func _find_target() -> Player:
	var forward: Vector3 = _player.get_look_direction()
	var origin: Vector3 = _player.global_position
	var best: Player = null
	var best_dist: float = grab_range
	for node in get_tree().get_nodes_in_group("players"):
		if node == _player or not is_instance_valid(node):
			continue
		if "is_dead" in node and node.is_dead:
			continue
		var to_node: Vector3 = node.global_position - origin
		var dist: float = to_node.length()
		if dist > grab_range or dist < 0.01:
			continue
		var angle_deg: float = rad_to_deg(forward.angle_to(to_node.normalized()))
		if angle_deg > grab_cone_degrees * 0.5:
			continue
		if dist < best_dist:
			best_dist = dist
			best = node
	return best

func _run_sequence(target: Player) -> void:
	state = State.WINDUP
	await get_tree().create_timer(windup_time).timeout
	state = State.SLAP
	await get_tree().create_timer(slap_time).timeout
	state = State.SLAM
	_resolve_hit(target)
	await get_tree().create_timer(slam_time).timeout
	state = State.IDLE

func _resolve_hit(target: Player) -> void:
	if not is_instance_valid(target) or target.is_dead:
		return

	var forward: Vector3 = _player.get_look_direction()
	var attacker_up: Vector3 = _player.up_direction
	var is_downward: bool = forward.dot(-attacker_up) > downward_slap_dot_threshold

	var target_up: Vector3 = -GravityManager.get_gravity_at(target.global_position)
	target_up = target_up.normalized() if target_up.length() > 0.0001 else attacker_up

	var impulse: Vector3
	if is_downward:
		impulse = target_up * orbit_launch_strength
	else:
		var flat_forward: Vector3 = (forward - target_up * forward.dot(target_up))
		flat_forward = flat_forward.normalized() if flat_forward.length() > 0.01 else forward
		impulse = flat_forward * outward_launch_strength + target_up * outward_launch_lift

	var target_pos: Vector3 = target.global_position
	var target_basis: Basis = target.global_transform.basis

	# Kill: massive damage so it always overkills regardless of current health.
	var lethal_damage: float = target.max_health * 10.0
	if target.is_multiplayer_authority():
		target.apply_damage(lethal_damage, _player, target_pos, "The Bitchslap")
	else:
		target.rpc_id(target.get_multiplayer_authority(), "network_apply_damage", lethal_damage, _player.get_path(), target_pos, "The Bitchslap")

	_broadcast_spawn_corpse.rpc(target_pos, target_basis, impulse)

@rpc("any_peer", "call_local", "reliable")
func _broadcast_spawn_corpse(pos: Vector3, basis: Basis, impulse: Vector3) -> void:
	if corpse_scene == null:
		return
	var corpse := corpse_scene.instantiate()
	get_tree().current_scene.add_child(corpse)
	corpse.global_transform = Transform3D(basis, pos)
	if corpse.has_method("launch"):
		corpse.launch(impulse)
