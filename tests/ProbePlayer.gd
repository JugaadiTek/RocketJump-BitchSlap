extends Player
## Player driven by the headless probe instead of by hardware input. Overrides
## the same `_get_*`/`_wants_*` hooks Bot.gd does, so it exercises the real
## movement code path.

var probe_move: Vector2 = Vector2.ZERO
var probe_jump: bool = false
var probe_descend: bool = false
var probe_fire: bool = false
var probe_switch: int = -1
var probe_aim: bool = false

func _is_local_view() -> bool: return false
func _uses_mouse_look() -> bool: return false

func _get_move_axis() -> Vector2: return probe_move
func _get_look_delta() -> Vector2: return Vector2.ZERO
func _wants_jump() -> bool: return probe_jump
func _wants_descend() -> bool: return probe_descend
func _wants_fire() -> bool: return probe_fire
func _wants_aim() -> bool: return probe_aim
func _wants_melee() -> bool: return false
func _wants_scoreboard() -> bool: return false
func _get_weapon_scroll() -> int: return 0

## One-shot: consumed like a key press so it doesn't re-switch every frame.
func _get_weapon_switch() -> int:
	var s: int = probe_switch
	probe_switch = -1
	return s

## Points the camera at a world position by yawing the body and pitching the
## head, the same two axes mouse-look drives.
func aim_at(point: Vector3) -> void:
	var to: Vector3 = point - camera.global_position
	if to.length_squared() < 0.0001:
		return
	var up: Vector3 = global_transform.basis.y
	var flat: Vector3 = to - up * to.dot(up)
	if flat.length_squared() > 0.0001:
		var fwd: Vector3 = -global_transform.basis.z
		rotate_object_local(Vector3.UP, fwd.signed_angle_to(flat.normalized(), up))
	head.rotation.x = asin(clampf(to.normalized().dot(up), -1.0, 1.0))

## The spawn sequence flies the player in from the boundary over ~10s; the probe
## teleports it into place instead.
func disable_spawner() -> void:
	if _spawner:
		_spawner._active = false
		_spawner._launching = false
	_impulse_grace_remaining = 0.0

## `set()` rather than direct assignment so this same probe can also be run
## against the pre-fix Player, which has no planet-frame state at all.
func reset_frame() -> void:
	set("_frame_body", null)
	set("_platform_velocity", Vector3.ZERO)
	_has_aligned_once = false
