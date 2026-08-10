class_name PlanetBuster
extends Weapon
## Hold fire while aiming at a planet to lock on. Nothing leaves the barrel
## without a lock - can_fire() gates on it, so an unlocked trigger pull neither
## fires nor consumes this single-use weapon. Once locked, the shell leaves
## slowly and accelerates toward the planet, re-aiming once a second (see
## PlanetBusterProjectile). Cannot lock planets that are too close
## (min_lock_distance) to prevent point-blank suicides.

@export var shell_scene: PackedScene
@export var shell_speed: float = 7.0
@export var min_lock_distance: float = 80.0  ## below this, cannot lock
@export var lock_time_required: float = 1.2  ## seconds of sustained aim to lock

func _init() -> void:
	weapon_name = "Planet Buster"
	fire_cooldown = 2.0
	consumed_on_fire = true
	weapon_color = Color(0.75, 0.25, 0.9)

var _lock_target: OrbitalBody = null
var _lock_progress: float = 0.0
var _last_candidate: OrbitalBody = null

func tick(delta: float, fire_held: bool) -> void:
	if _cooldown_remaining > 0.0:
		_lock_progress = 0.0
		_lock_target = null
		return
	var candidate: OrbitalBody = _get_aimed_planet()
	if candidate != _last_candidate:
		_lock_progress = 0.0
	_last_candidate = candidate
	if candidate and fire_held:
		_lock_progress += delta
		if _lock_progress >= lock_time_required:
			_lock_target = candidate
	else:
		_lock_progress = 0.0
		if not fire_held:
			_lock_target = null

## Returns the planet currently in the player's sights (if valid range),
## or null if nothing lockable is in view.
func _get_aimed_planet() -> OrbitalBody:
	if owner_player == null:
		return null
	var p: Player = owner_player as Player
	if p == null or p.camera == null:
		return null
	var eye: Vector3 = p.camera.global_position
	var forward: Vector3 = -p.camera.global_transform.basis.z
	var best: OrbitalBody = null
	var best_dot: float = 0.85  ## minimum cos(angle) to be "in sights"
	for body in GravityManager.get_bodies():
		if not is_instance_valid(body) or body.is_shattered or not body.can_be_shattered:
			continue
		var dist: float = eye.distance_to(body.global_position) - body.radius
		if dist < min_lock_distance:
			continue
		var to_body: Vector3 = (body.global_position - eye).normalized()
		var dot: float = forward.dot(to_body)
		if dot > best_dot:
			best_dot = dot
			best = body
	return best

func get_lock_progress() -> float:
	return clamp(_lock_progress / lock_time_required, 0.0, 1.0)

func get_lock_target() -> OrbitalBody:
	return _lock_target

func get_aimed_candidate() -> OrbitalBody:
	return _last_candidate

func _do_fire(muzzle_transform: Transform3D, aim_direction: Vector3) -> void:
	if shell_scene == null:
		return
	# Only fire if locked on; if not locked, give feedback but don't consume the weapon
	if _lock_target == null:
		return
	var shell: PlanetBusterProjectile = shell_scene.instantiate()
	_get_projectile_root().add_child(shell)
	shell.global_position = muzzle_transform.origin
	shell.lock_target = _lock_target
	shell.launch(aim_direction * shell_speed, owner_player)
	_lock_target = null
	_lock_progress = 0.0

func can_fire() -> bool:
	return _cooldown_remaining <= 0.0 and _lock_target != null
