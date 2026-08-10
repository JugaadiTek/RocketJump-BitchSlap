extends Node
## Performance breakdown, run with a REAL renderer (headless reports no draw
## calls). Places the camera on a planet surface looking along it, so the sample
## reflects what a player actually sees rather than empty space.
##
## Pass a mode with `-- <mode>`; each disables one system so its cost can be read
## off as the difference from `all`:
##   all | no-asteroids | no-buildings | no-lights | no-packs | bare

const ARENA := preload("res://scenes/world/Arena.tscn")
const ProbePlayer := preload("res://tests/ProbePlayer.gd")
const LOG_PATH := "/tmp/rjbs_perf.log"

var _arena: Node3D
var _mode: String = "all"

func _log(line: String) -> void:
	print(line)
	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(LOG_PATH) else FileAccess.WRITE)
	if f:
		f.seek_end(); f.store_line(line); f.close()

func _ready() -> void:
	seed(20260811)
	# Vsync caps every configuration at the refresh rate, which hides how much
	# headroom there actually is. Off, so the numbers reflect real capacity.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_mode = args[0]

	_arena = ARENA.instantiate()
	add_child(_arena)
	for i in range(10):
		await get_tree().physics_frame

	_apply_mode()

	# Put a camera on Verdant's surface, looking along it at the buildings.
	var body: OrbitalBody = _arena.get_node("OrbitalBodies/Verdant")
	var scene: PackedScene = load("res://scenes/player/Player.tscn")
	var player: Player = scene.instantiate()
	player.set_script(ProbePlayer)
	player.name = "PerfCam"
	_arena.get_node("Players").add_child(player, true)
	await get_tree().physics_frame
	player.disable_spawner()
	var out: Vector3 = Vector3(0.3, 1.0, 0.2).normalized()
	player.global_position = body.global_position + out * (body.radius + 2.0)
	player.camera.current = true
	var tangent: Vector3 = out.cross(Vector3.RIGHT).normalized()
	player.global_transform.basis = Basis(out.cross(-tangent).normalized(), out, -tangent).orthonormalized()

	# Let the match get going: bots fly in, land, and start fighting, so the
	# sample covers deaths, gore, respawn trails and projectiles - not an empty
	# arena sitting still.
	var settle: int = 900 if _mode == "sustained" else 90
	for i in range(settle):
		await get_tree().process_frame

	# Wall-clock frame deltas: averages hide hitching, and hitching is what a
	# player actually feels. Track the worst frames and how often they occur.
	var frames: Array[float] = []
	var calls := 0.0
	var sample_frames: int = 2400 if _mode == "sustained" else 400
	for i in range(sample_frames):
		await get_tree().process_frame
		frames.append(get_process_delta_time() * 1000.0)
		calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	frames.sort()
	var n: int = frames.size()
	var total: float = 0.0
	var spikes: int = 0
	for t in frames:
		total += t
		if t > 20.0:
			spikes += 1
	var mean: float = total / float(n)
	_log("%-16s mean=%5.2fms (%.0f fps)  p95=%5.2f  worst=%6.2f  spikes>20ms=%d/%d  draws=%4d  nodes=%d" % [
		_mode, mean, 1000.0 / mean, frames[int(n * 0.95)], frames[n - 1], spikes, n,
		int(calls / float(n)), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	get_tree().quit()

func _apply_mode() -> void:
	match _mode:
		"no-asteroids", "bare":
			var field: Node = _arena.get_node_or_null("DebrisField")
			if field: field.free()
	match _mode:
		"no-buildings", "bare":
			for b in _find(Building): b.free()
	match _mode:
		"no-packs", "bare":
			for p in _find(HealthPack): p.free()
	match _mode:
		"no-lights", "bare":
			for l in _find_lights(): l.free()
	match _mode:
		# Planets keep their analytic SphereShape3D instead of being rebuilt as a
		# ~1300-triangle concave mesh once craters land on them.
		"sphere-colliders":
			for b in _find(OrbitalBody): b.set_meta("no_crater_collider", true)
		"no-players":
			for p in get_tree().get_nodes_in_group("players"): p.free()
			_arena.bot_count = 0

func _find(type) -> Array:
	var out: Array = []
	for n in _all(_arena):
		if is_instance_of(n, type):
			out.append(n)
	return out

func _find_lights() -> Array:
	var out: Array = []
	for n in _all(_arena):
		if n is OmniLight3D:
			out.append(n)
	return out

func _all(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out
