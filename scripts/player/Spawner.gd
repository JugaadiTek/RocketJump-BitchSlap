extends Node
## Handles the full spawn/respawn flow:
##   1. Player appears at a point on the arena boundary sphere, facing
##      the arena center.
##   2. For 10s they can aim at any planet and hold fire (crosshair turns
##      green with lock box when a planet is in view) to choose it.
##   3. If they don't choose, the nearest planet is auto-selected.
##   4. They launch on a fast trajectory toward the chosen planet, leaving
##      a particle trail, land with a smoke-bomb FX, and perturb the
##      planet's orbit 0.1%-0.3%.

signal spawn_complete

const SPAWN_RADIUS: float = 615.0   ## just inside ARENA_BOUNDARY_RADIUS
const AIM_WINDOW: float = 10.0      ## seconds to pick a planet
const LOCK_CONE_COS: float = 0.93   ## cos(~21°) threshold for "in sights"
const LAUNCH_SPEED: float = 130.0
const MIN_LOCK_DISTANCE_FROM_PLAYER: float = 60.0

var player: Player = null
var _aim_timer: float = 0.0
var _active: bool = false
var _locked_body: OrbitalBody = null
var _launching: bool = false
var _launch_target: OrbitalBody = null
var _trail: GPUParticles3D = null

func start_spawn(p: Player) -> void:
	player = p
	_active = true
	_aim_timer = 0.0
	_locked_body = null
	_launching = false
	_place_at_boundary()

func _place_at_boundary() -> void:
	# Random point on boundary sphere
	var rand_dir := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
	player.global_position = rand_dir * SPAWN_RADIUS
	# Face inward toward arena center
	var inward: Vector3 = -rand_dir
	var ref: Vector3 = Vector3.RIGHT if abs(inward.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var bx: Vector3 = inward.cross(ref).normalized()
	var bz: Vector3 = bx.cross(inward).normalized()
	player.global_transform.basis = Basis(bx, inward, bz).orthonormalized()
	player.velocity = Vector3.ZERO

func _physics_process(delta: float) -> void:
	if not _active or player == null or not is_instance_valid(player):
		return

	if _launching:
		_update_launch(delta)
		return

	_aim_timer += delta
	var candidate: OrbitalBody = _get_aimed_planet()

	# Fire held + valid candidate = lock on
	if candidate and player._wants_fire():
		_locked_body = candidate

	var timed_out: bool = (_aim_timer >= AIM_WINDOW)
	var chosen: OrbitalBody = _locked_body if _locked_body else (GravityManager.get_nearest_body(player.global_position) if timed_out else null)

	if chosen:
		_begin_launch(chosen)

	# Push HUD crosshair state
	if player.hud and player.hud.has_method("update_spawn_aim"):
		player.hud.update_spawn_aim(candidate, _aim_timer, AIM_WINDOW)

func _get_aimed_planet() -> OrbitalBody:
	if player.camera == null:
		return null
	var eye: Vector3 = player.camera.global_position
	var forward: Vector3 = -player.camera.global_transform.basis.z
	var best: OrbitalBody = null
	var best_dot: float = LOCK_CONE_COS
	for body in GravityManager.get_bodies():
		if not is_instance_valid(body) or body.is_shattered:
			continue
		var dist: float = eye.distance_to(body.global_position) - body.radius
		if dist < MIN_LOCK_DISTANCE_FROM_PLAYER:
			continue
		var to_body: Vector3 = (body.global_position - eye).normalized()
		var dot: float = forward.dot(to_body)
		if dot > best_dot:
			best_dot = dot
			best = body
	return best

func _begin_launch(target: OrbitalBody) -> void:
	_launching = true
	_launch_target = target
	_spawn_trail()
	player._impulse_grace_remaining = 20.0  # suppress ground-stick for the whole flight
	player.velocity = Vector3.ZERO

func _update_launch(delta: float) -> void:
	if not is_instance_valid(_launch_target) or _launch_target.is_shattered:
		_finish_spawn()
		return
	var to_target: Vector3 = _launch_target.global_position - player.global_position
	var dist_to_surface: float = to_target.length() - _launch_target.radius
	if dist_to_surface <= 3.0:
		_finish_spawn()
		return
	var dir: Vector3 = to_target.normalized()
	var current_dir: Vector3 = player.velocity.normalized() if player.velocity.length() > 0.1 else dir
	var steered: Vector3 = current_dir.slerp(dir, 0.20)
	player.velocity = steered.normalized() * LAUNCH_SPEED
	player.move_and_slide()

func _finish_spawn() -> void:
	_active = false
	_launching = false
	if _trail and is_instance_valid(_trail):
		_trail.emitting = false
	if _launch_target and is_instance_valid(_launch_target):
		_launch_target.perturb_orbit(randf_range(1.0, 3.0))
	_spawn_landing_fx()
	player._impulse_grace_remaining = 0.1
	spawn_complete.emit()

func _spawn_trail() -> void:
	_trail = GPUParticles3D.new()
	player.add_child(_trail)
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 25.0
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 4.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.15
	mat.scale_max = 0.4
	mat.color = Color(0.5, 0.8, 1.0, 0.85)
	_trail.process_material = mat
	_trail.draw_pass_1 = SphereMesh.new()
	_trail.amount = 20
	_trail.lifetime = 0.8
	_trail.fixed_fps = 30
	_trail.emitting = true
	_trail.local_coords = false

func _spawn_landing_fx() -> void:
	var particles := GPUParticles3D.new()
	player.get_tree().current_scene.add_child(particles)
	particles.global_position = player.global_position
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 70.0
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 12.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.3
	mat.scale_max = 1.2
	mat.color = Color(0.5, 0.5, 0.55, 0.9)
	particles.process_material = mat
	particles.draw_pass_1 = SphereMesh.new()
	particles.amount = 40
	particles.lifetime = 1.5
	particles.one_shot = true
	particles.emitting = true
	particles.explosiveness = 0.9
	var timer := player.get_tree().create_timer(2.5)
	timer.timeout.connect(func(): if is_instance_valid(particles): particles.queue_free())
