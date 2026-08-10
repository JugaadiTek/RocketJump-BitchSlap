extends Node
## Headless movement regression probe.
##
## Drops a scripted Player onto a fast-orbiting planet and measures the three
## surface bugs directly:
##   BOUNCE  - how often is_on_floor() drops out while just running
##   SLIDE   - how far the planet's surface drifts under a standing player
##   WALL    - forward progress achieved running each of 8 compass headings
##
## Run: Godot --headless --path . res://tests/MovementProbe.tscn

const ProbePlayer := preload("res://tests/ProbePlayer.gd")
const ARENA := preload("res://scenes/world/Arena.tscn")
## Per-phase progress output, so a run that stalls says where.
const VERBOSE := true
## Results also go to a file, flushed per line: a probe run that has to be
## killed for hanging would otherwise lose everything to stdout pipe buffering,
## which is exactly the run whose output matters most.
const LOG_PATH := "/tmp/rjbs_probe.log"

func _log(line: String) -> void:
	print(line)
	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(LOG_PATH) else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(line)
		f.close()

var _arena: Node3D
var _player: Player
var _body: OrbitalBody

func _ready() -> void:
	# Arena scatters towers/pads at random surface positions; fix the seed so
	# baseline and fixed runs face an identical world.
	seed(20260811)
	_arena = ARENA.instantiate()
	# Strip the AI: 31 bots add nothing to a movement probe but a lot of noise.
	_arena.bot_count = 0
	add_child(_arena)
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Ferrum: orbit_radius 230 at 0.0525 rad/s = ~12 m/s of orbital travel,
	# comfortably faster than max_ground_speed (9). This is the case that made
	# all three bugs reproduce.
	_body = _arena.get_node("OrbitalBodies/Ferrum")
	_clear_surface_obstacles()

	var scene: PackedScene = load("res://scenes/player/Player.tscn")
	_player = scene.instantiate()
	_player.set_script(ProbePlayer)
	_arena.get_node("Players").add_child(_player)
	_player.player_id = 99
	await get_tree().physics_frame

	await _run_all()
	get_tree().quit()

## Removes the towers and pads the arena scatters over the test planet. They're
## legitimate solid geometry, so running into one is a real collision - but it
## would masquerade as an "invisible wall" in the heading sweep below.
func _clear_surface_obstacles() -> void:
	var removed: int = 0
	for child in _body.get_children():
		if child is MeshInstance3D or child is StaticBody3D or child is Marker3D:
			continue
		child.queue_free()
		removed += 1
	if VERBOSE:
		_log("  [setup] removed %d surface obstacles from %s (radius %.1f)" % [removed, _body.name, _body.radius])

## Teleports the probe onto the planet's surface and lets it settle.
func _place_on_surface() -> void:
	_player.probe_move = Vector2.ZERO
	_player.disable_spawner()
	var out: Vector3 = Vector3(0.3, 1.0, 0.2).normalized()
	_player.global_position = _body.global_position + out * (_body.radius + 1.2)
	_player.velocity = Vector3.ZERO
	_player.reset_frame()
	# Face along a tangent so "forward" is a real running direction.
	# Right-handed basis with Y = out and -Z = the chosen tangent. Building it as
	# Basis(out.cross(fwd), out, -fwd) instead mirrors the basis (det -1), which
	# silently reverses which way every local-axis rotation turns.
	var fwd: Vector3 = out.cross(Vector3.RIGHT).normalized()
	var basis_z: Vector3 = -fwd
	var basis_x: Vector3 = out.cross(basis_z).normalized()
	_player.global_transform.basis = Basis(basis_x, out, basis_z).orthonormalized()
	for i in range(90):
		await get_tree().physics_frame
	if VERBOSE:
		_log("  [settled] altitude=%.3f on_floor=%s" % [
			_player.global_position.distance_to(_body.global_position) - _body.radius,
			_player.is_on_floor()])

func _run_all() -> void:
	await _test_bounce()
	await _test_slide()
	await _test_wall()

## BUG 1 - running across the surface should never leave the ground.
func _test_bounce() -> void:
	await _place_on_surface()
	_player.probe_move = Vector2(0.0, 1.0)
	var airborne_frames: int = 0
	var takeoffs: int = 0
	var max_altitude: float = 0.0
	var was_on_floor: bool = true
	for i in range(600):
		await get_tree().physics_frame
		var alt: float = _player.global_position.distance_to(_body.global_position) - _body.radius
		max_altitude = maxf(max_altitude, alt)
		var on_floor: bool = _player.is_on_floor()
		if VERBOSE and i % 120 == 0:
			_log("  [bounce %d/600] altitude=%.3f on_floor=%s speed=%.1f" % [i, alt, on_floor, _player.velocity.length()])
		if not on_floor:
			airborne_frames += 1
			if was_on_floor:
				takeoffs += 1
		was_on_floor = on_floor
	_player.probe_move = Vector2.ZERO
	_log("BOUNCE  takeoffs=%d airborne_frames=%d/600 peak_altitude=%.3fm" % [takeoffs, airborne_frames, max_altitude])

## BUG 2 - standing still should stay put relative to the planet, not have the
## planet slide out from underneath.
func _test_slide() -> void:
	await _place_on_surface()
	_player.probe_move = Vector2.ZERO
	# Track the fixed point on the planet we started above, in the planet's own
	# local space, so the planet's orbit and spin are both accounted for.
	var anchor_local: Vector3 = _body.global_transform.affine_inverse() * _player.global_position
	var world_travel: float = 0.0
	var start_world: Vector3 = _player.global_position
	for i in range(300):
		await get_tree().physics_frame
	var anchor_now: Vector3 = _body.global_transform * anchor_local
	var drift: float = _player.global_position.distance_to(anchor_now)
	world_travel = _player.global_position.distance_to(start_world)
	_log("SLIDE   drift_vs_planet=%.3fm over 5s (planet itself moved %.1fm)" % [drift, world_travel])

## BUG 3 - every heading should make real progress; an invisible wall shows up
## as one or more headings with near-zero distance covered.
func _test_wall() -> void:
	var results: Array[String] = []
	var worst: float = INF
	for h in range(8):
		await _place_on_surface()
		var yaw: float = TAU * float(h) / 8.0
		_player.rotate_object_local(Vector3.UP, yaw)
		for i in range(20):
			await get_tree().physics_frame
		_player.probe_move = Vector2(0.0, 1.0)
		var start_local: Vector3 = _body.global_transform.affine_inverse() * _player.global_position
		var wall_frames: int = 0
		var blocker: String = ""
		for i in range(180):
			await get_tree().physics_frame
			if _player.is_on_wall():
				wall_frames += 1
				var c: Object = _player.get_last_slide_collision().get_collider() if _player.get_slide_collision_count() > 0 else null
				if c and blocker == "":
					blocker = str((c as Node).get_path()) if c is Node else str(c)
		var end_local: Vector3 = _body.global_transform.affine_inverse() * _player.global_position
		_player.probe_move = Vector2.ZERO
		if VERBOSE and wall_frames > 0:
			_log("  [heading %d] blocked on a wall for %d/180 frames by %s" % [h, wall_frames, blocker])
		# Great-circle distance travelled across the planet's own surface.
		var travelled: float = start_local.normalized().angle_to(end_local.normalized()) * _body.radius
		worst = minf(worst, travelled)
		results.append("%.1f" % travelled)
	_log("WALL    surface_metres_per_heading(8x3s) = [%s]  worst=%.1fm" % [", ".join(results), worst])
