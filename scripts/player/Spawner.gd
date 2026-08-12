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

## Kept inside the LIVE arena boundary by this much, not a fixed distance from
## a hard-coded planet reach. GravityManager.arena_half_extent() flexes with
## whatever currently reaches furthest out (including a tower's own
## structure_reach, which can now be several times a planet's radius) - a
## fixed SPAWN_RADIUS chosen "clear of Halcyon" back when nothing reached
## past ~476 stayed fixed at 505 even once a tall tower pushed the real
## boundary out past 650, which put every spawn well inside the live play
## area instead of at its edge.
const SPAWN_BOUNDARY_MARGIN: float = 30.0
## Absolute floor so a tiny/collapsed arena can't produce a degenerate (or
## negative) spawn radius.
const MIN_SPAWN_RADIUS: float = 100.0
## Default seconds to pick a planet; the actual window comes from the spawning
## entity (Player.get_spawn_aim_window()), which bots shorten drastically.
const AIM_WINDOW: float = 10.0
const LOCK_CONE_COS: float = 0.93   ## cos(~21°) threshold for "in sights"
const LAUNCH_SPEED: float = 130.0
const MIN_LOCK_DISTANCE_FROM_PLAYER: float = 60.0
## How far behind the player the trail is emitted. The smoke is deliberately
## thick, so emitting it at the player's own origin filled the camera and made
## the 130 m/s flight in unflyable - it has to start well behind the head.
const TRAIL_TRAIL_DISTANCE: float = 14.0

var player: Player = null
var _aim_timer: float = 0.0
var _active: bool = false
var _locked_body: OrbitalBody = null
var _launching: bool = false
var _launch_target: OrbitalBody = null
var _trail: GPUParticles3D = null
var _aim_window: float = AIM_WINDOW

## Re-entry from the arena edge. Same launch, trail and landing as a spawn, but
## starting from wherever the player already is and with no aim window: they get
## flung at a random planet immediately rather than hanging on the boundary.
func start_boundary_return(p: Player) -> void:
	player = p
	_active = true
	_launching = true
	_aim_timer = 0.0
	_locked_body = null
	_aim_window = 0.0
	var target: OrbitalBody = _random_target()
	if target == null:
		_active = false
		_launching = false
		return
	_begin_launch(target)

func _random_target() -> OrbitalBody:
	var usable: Array[OrbitalBody] = []
	for body in GravityManager.get_bodies():
		if is_instance_valid(body) and not body.is_shattered and body.radius >= 5.0:
			usable.append(body)
	if usable.is_empty():
		return GravityManager.get_nearest_body(player.global_position)
	return usable[randi() % usable.size()]

func start_spawn(p: Player) -> void:
	player = p
	_active = true
	_aim_timer = 0.0
	_locked_body = null
	_launching = false
	_aim_window = p.get_spawn_aim_window()
	_place_at_boundary()

## Distance from the arena origin to spawn at: a point at this radius is
## guaranteed inside GravityManager's box boundary (any point on a sphere of
## radius R has every axis component <= R, so R <= half_extent keeps it
## inside on every axis), staying SPAWN_BOUNDARY_MARGIN clear of the live edge
## instead of a distance chosen once for whatever reached furthest out at the
## time.
static func _spawn_radius() -> float:
	return maxf(GravityManager.arena_half_extent() - SPAWN_BOUNDARY_MARGIN, MIN_SPAWN_RADIUS)

func _place_at_boundary() -> void:
	# Random point on boundary sphere
	var rand_dir := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
	player.global_position = rand_dir * _spawn_radius()
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

	var timed_out: bool = (_aim_timer >= _aim_window)
	var chosen: OrbitalBody = _locked_body if _locked_body else (player.pick_spawn_target() if timed_out else null)

	if chosen:
		_begin_launch(chosen)

	# Push HUD crosshair state
	if player.hud and player.hud.has_method("update_spawn_aim"):
		player.hud.update_spawn_aim(candidate, _aim_timer, _aim_window)

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
		# Punch a crater where we touched down, sized against the planet so a
		# pebble gets a dimple and a big world gets a proper bowl.
		var crater_radius: float = clampf(_launch_target.radius * 0.22, 1.5, 9.0)
		_launch_target.apply_crater(player.global_position, crater_radius, crater_radius * 0.32)
	_spawn_landing_fx()
	player._impulse_grace_remaining = 0.1
	spawn_complete.emit()

## Keeps the emitter trailing behind the player along the flight path, in the
## player's own local space (the node is parented to them).
func _position_trail(travel_dir: Vector3) -> void:
	if _trail == null or not is_instance_valid(_trail):
		return
	_trail.position = player.to_local(player.global_position - travel_dir * TRAIL_TRAIL_DISTANCE)

func _spawn_trail() -> void:
	_trail = GPUParticles3D.new()
	player.add_child(_trail)
	_trail.position = Vector3(0, 0, TRAIL_TRAIL_DISTANCE)
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 11.0
	mat.gravity = Vector3.ZERO
	# Emitted from a sphere rather than a point so the column has real girth
	# instead of being a thin thread of billboards.
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 3.2
	# Big, long-lived puffs that keep growing: at 130 m/s the trail has to be
	# thick and slow-fading to read as a smoke column rather than a dotted line.
	mat.scale_min = 2.2
	mat.scale_max = 5.5
	mat.scale_curve = _growth_curve()
	# Each particle picks a colour along this ramp and then ages along it too:
	# hot red at the nose, orange through the middle, cooling to grey smoke.
	mat.color_ramp = _smoke_ramp()
	_trail.process_material = mat
	var puff := SphereMesh.new()
	puff.radial_segments = 8
	puff.rings = 4
	var puff_mat := StandardMaterial3D.new()
	puff_mat.vertex_color_use_as_albedo = true
	puff_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.85)
	puff_mat.emission_enabled = true
	puff_mat.emission = Color(1.0, 0.35, 0.1, 1.0)
	puff_mat.emission_energy_multiplier = 1.6
	puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	puff.material = puff_mat
	_trail.draw_pass_1 = puff
	_trail.amount = 420
	_trail.lifetime = 3.2
	_trail.fixed_fps = 0
	_trail.emitting = true
	_trail.local_coords = false

## Red -> orange -> grey -> transparent, the life of one puff of exhaust smoke.
func _smoke_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_offset(0, 0.0)
	gradient.set_color(0, Color(1.0, 0.18, 0.05, 1.0))
	gradient.add_point(0.25, Color(1.0, 0.48, 0.10, 0.95))
	gradient.add_point(0.55, Color(0.85, 0.42, 0.22, 0.8))
	gradient.add_point(0.8, Color(0.42, 0.40, 0.40, 0.55))
	gradient.set_offset(1, 1.0)
	gradient.set_color(1, Color(0.25, 0.24, 0.24, 0.0))
	var tex := GradientTexture1D.new()
	tex.gradient = gradient
	return tex

## Puffs swell as they age, the way real exhaust billows out behind a vehicle.
func _growth_curve() -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.35))
	curve.add_point(Vector2(0.4, 0.9))
	curve.add_point(Vector2(1.0, 1.0))
	var tex := CurveTexture.new()
	tex.curve = curve
	return tex

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
