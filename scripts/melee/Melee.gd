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

## First-person hand model, a plain child of WeaponManager (see Player.tscn) -
## nesting it there means it's automatically hidden for non-local views the
## same way every weapon viewmodel already is (Player._ready() hides
## WeaponManager wholesale for anyone who isn't looking through this exact
## camera), without Melee needing to duplicate that check itself.
@onready var _view_model: Node3D = _player.get_node_or_null("Head/Camera3D/WeaponManager/MeleeViewModel")

## Local-space poses the hand tweens through: pulled back for the windup,
## thrown hard across and through the view for the slap itself, then a short
## overshoot/settle on impact before it's hidden again. Numbers are hand-fit
## against the viewmodel's own scale (see Player.tscn's BoxMesh_slap_* sizes),
## not derived from anything - purely "does this read as a big haymaker".
const _REST_POS := Vector3(0.32, -0.34, -0.18)
const _WINDUP_POS := Vector3(0.5, 0.22, 0.08)
const _WINDUP_ROT := Vector3(-0.35, 0.95, -0.3)
const _SLAP_POS := Vector3(-0.42, -0.06, -0.62)
const _SLAP_ROT := Vector3(0.15, -0.9, 0.35)
const _SLAM_POS := Vector3(-0.16, -0.22, -0.7)
const _SLAM_ROT := Vector3(0.3, -0.55, 0.1)

func _process(delta: float) -> void:
	if _cooldown_remaining > 0.0:
		_cooldown_remaining -= delta

## `forced_target`, when given, skips _find_target()'s own range/cone re-scan
## and slaps that exact target instead - used by GrapplingHook, which already
## knows precisely who it just reeled to point-blank range. Re-running
## _find_target() there was whiffing in practice: a pulled target arrives
## along the line TOWARD the shooter's position, not necessarily inside the
## shooter's current look-direction cone, so the independent re-check could
## (and in testing, reliably did) reject the very target the pull just
## delivered. Still validated for liveness so a target that died or was freed
## between the pull and this call is a harmless no-op, same as a manual miss.
func try_activate(forced_target: Player = null) -> void:
	if state != State.IDLE or _cooldown_remaining > 0.0:
		return
	var target: Player = forced_target if forced_target != null else _find_target()
	if target == null or not is_instance_valid(target) or target.is_dead:
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
	_animate_hand()
	state = State.WINDUP
	await get_tree().create_timer(windup_time).timeout
	state = State.SLAP
	await get_tree().create_timer(slap_time).timeout
	state = State.SLAM
	_resolve_hit(target)
	await get_tree().create_timer(slam_time).timeout
	state = State.IDLE

## Fire-and-forget swing, run purely on the attacker's own first-person view
## (the same way weapon fire/reload never animates for anyone else - other
## players only ever see the result, the replicated corpse launch in
## _resolve_hit). Timed to line up with the windup/slap/slam durations above
## rather than driven by the state enum directly, so it can't drift out of
## sync with _run_sequence even if a designer retunes those export vars.
func _animate_hand() -> void:
	if _view_model == null or not _player.is_first_person_view():
		return
	_view_model.visible = true
	_view_model.position = _REST_POS
	_view_model.rotation = Vector3.ZERO
	var tw: Tween = create_tween()
	tw.tween_property(_view_model, "position", _WINDUP_POS, windup_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_view_model, "rotation", _WINDUP_ROT, windup_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# The slap itself: thrown hard and fast, the whole point being violent.
	tw.tween_property(_view_model, "position", _SLAP_POS, slap_time).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_view_model, "rotation", _SLAP_ROT, slap_time).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tw.tween_property(_view_model, "position", _SLAM_POS, slam_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_view_model, "rotation", _SLAM_ROT, slam_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		if is_instance_valid(_view_model):
			_view_model.visible = false)

## A small, brief camera kick right on impact - nothing else drives
## Camera3D.position (look is all done through Head's rotation and the
## camera's own FOV), so nudging it here for a couple of frames and tweening
## it back can't fight any other system.
func _camera_punch() -> void:
	if not _player.is_first_person_view() or _player.camera == null:
		return
	var cam: Camera3D = _player.camera
	var rest: Vector3 = Vector3.ZERO
	cam.position = Vector3(0.0, -0.06, 0.05)
	var tw: Tween = create_tween()
	tw.tween_property(cam, "position", rest, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _resolve_hit(target: Player) -> void:
	if not is_instance_valid(target) or target.is_dead:
		return
	_camera_punch()

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
