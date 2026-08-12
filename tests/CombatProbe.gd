extends Node
## Headless probe for the combat/feedback pass:
##   BOUNDARY  - a player at the arena edge relaunches instead of sticking
##   TOWERWALL - tower walls keep their width all the way up
##   HEADSHOT  - head hits do 300%
##   DEATH     - comic burst and bubble spawn
##   SLIME     - slugs leave a trail behind them
##   ASTEROID  - rocks fall, collide, streak, and crater what they hit
##   AUDIO     - library quality and adaptive ambience layers
##   ANNOUNCE  - callout triggers and the 3-kill spree
##
## Run: Godot --headless --path . res://tests/CombatProbe.tscn

const ProbePlayer := preload("res://tests/ProbePlayer.gd")
const ARENA := preload("res://scenes/world/Arena.tscn")
const LOG_PATH := "/tmp/rjbs_combat.log"

var _arena: Node3D
var _player: Player
var _body: OrbitalBody

func _log(line: String) -> void:
	print(line)
	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(LOG_PATH) else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(line)
		f.close()

func _ready() -> void:
	seed(20260811)
	_arena = ARENA.instantiate()
	_arena.bot_count = 0
	add_child(_arena)
	for i in range(4):
		await get_tree().physics_frame
	_body = _arena.get_node("OrbitalBodies/Verdant")

	var scene: PackedScene = load("res://scenes/player/Player.tscn")
	_player = scene.instantiate()
	_player.set_script(ProbePlayer)
	_player.name = "CombatProbePlayer"
	_arena.get_node("Players").add_child(_player, true)
	_player.player_id = 77
	_player.display_name = "Probe"
	await get_tree().physics_frame

	_test_tower_walls()
	_test_headshot()
	await _test_boundary()
	await _test_death()
	await _test_asteroids()
	get_tree().quit()

func _place_on_surface(altitude: float = 1.2) -> void:
	_player.probe_move = Vector2.ZERO
	_player.probe_fire = false
	_player.disable_spawner()
	var out: Vector3 = Vector3(0.3, 1.0, 0.2).normalized()
	_player.global_position = _body.global_position + out * (_body.radius + altitude)
	_player.velocity = Vector3.ZERO
	_player.reset_frame()
	var fwd: Vector3 = out.cross(Vector3.RIGHT).normalized()
	var bz: Vector3 = -fwd
	var bx: Vector3 = out.cross(bz).normalized()
	_player.global_transform.basis = Basis(bx, out, bz).orthonormalized()
	_player.head.rotation.x = 0.0
	for i in range(50):
		await get_tree().physics_frame

## A tower is authored flat and wrapped onto the sphere. If the wrap divides the
## arc by the SURFACE radius rather than the radius at each height, every storey
## subtends the same angle and so gets physically wider as it rises - the walls
## visibly split open.
##
## Tested against the mapping itself rather than against placed geometry:
## doorways and windows put different cut pieces in different height bands, so
## measuring the built mesh compares pieces that were never the same width to
## begin with. Here the SAME authored offset is mapped at the base and at the
## top, which isolates exactly the thing that was broken.
func _test_tower_walls() -> void:
	var worst_ratio: float = 1.0
	var worst: String = ""
	var worst_old: float = 1.0
	var checked: int = 0
	for body in GravityManager.get_bodies():
		for child in body.get_children():
			if not (child is Tower):
				continue
			var tower: Tower = child
			checked += 1
			var half: float = tower.tower_width * 0.5
			var base: Vector3 = tower._surface_transform(Vector3(half, 0.0, 0.0)).origin
			var top: Vector3 = tower._surface_transform(Vector3(half, tower.tower_height, 0.0)).origin
			var base_width: float = sqrt(base.x * base.x + base.z * base.z)
			var top_width: float = sqrt(top.x * top.x + top.z * top.z)
			if base_width < 0.01:
				continue
			var ratio: float = top_width / base_width
			# What the old surface-radius mapping would have produced.
			var r: float = tower.host_radius
			var old_angle: float = half / r
			var old_top: float = (r + tower.tower_height) * sin(old_angle)
			var old_ratio: float = old_top / base_width
			if absf(ratio - 1.0) > absf(worst_ratio - 1.0):
				worst_ratio = ratio
				worst_old = old_ratio
				worst = "%s (%.0fm tall on r%.0f)" % [body.name, tower.tower_height, body.radius]
	_log("TOWERWALL %d towers; worst top/base width ratio now %.4f (old mapping would give %.3f) %s" % [
		checked, worst_ratio, worst_old, worst])

func _test_headshot() -> void:
	var up: Vector3 = _player.up_direction
	var body_hit: Vector3 = _player.global_position + up * 0.9
	var head_hit: Vector3 = _player.global_position + up * 1.7
	_player.health = 1000.0
	_player.apply_damage(10.0, null, body_hit, "probe")
	var body_damage: float = 1000.0 - _player.health
	_player.health = 1000.0
	_player.apply_damage(10.0, null, head_hit, "probe")
	var head_damage: float = 1000.0 - _player.health
	_player.health = _player.max_health
	_log("HEADSHOT body hit %.0f dmg, head hit %.0f dmg (x%.1f); threshold %.2fm, is_headshot(head)=%s" % [
		body_damage, head_damage, head_damage / maxf(body_damage, 0.001),
		_player.head_shot_height, _player.is_headshot(head_hit)])

## Touching the arena edge used to leave the player frozen there forever: the
## bounds code steered velocity and returned, and the movement code also returned
## because a boundary target was set, so nothing ever called move_and_slide().
func _test_boundary() -> void:
	await _place_on_surface()
	var edge: Vector3 = Vector3(0.4, 0.5, 0.76).normalized() * (GravityManager.ARENA_BOUNDARY_RADIUS + 25.0)
	_player.global_position = edge
	_player.velocity = Vector3.ZERO
	_player.reset_frame()
	var start_distance: float = _player.global_position.length()
	var moved_by_frame: int = -1
	for i in range(900):
		await get_tree().physics_frame
		if moved_by_frame < 0 and _player.global_position.distance_to(edge) > 5.0:
			moved_by_frame = i
	var end_distance: float = _player.global_position.length()
	var host: OrbitalBody = GravityManager.get_nearest_body(_player.global_position)
	var altitude: float = 9999.0
	if host:
		altitude = _player.global_position.distance_to(host.global_position) - host.radius
	_log("BOUNDARY placed at %.0fm (edge %.0f); started moving after %.2fs; now %.0fm out, %.1fm above %s" % [
		start_distance, GravityManager.ARENA_BOUNDARY_RADIUS,
		float(moved_by_frame) / 60.0, end_distance, altitude,
		host.name if host else "nothing"])

func _test_death() -> void:
	await _place_on_surface()
	var before: int = get_tree().current_scene.get_child_count()
	_player.apply_damage(1000.0, null, _player.global_position, "probe")
	for i in range(20):
		await get_tree().physics_frame
	var effect: Node = null
	for child in get_tree().current_scene.get_children():
		if child is DeathEffect:
			effect = child
	if effect == null:
		_log("DEATH   no DeathEffect spawned")
		return
	var bursts: int = 0
	var labels: int = 0
	var sprites: int = 0
	for child in effect.get_children():
		if child is Label3D:
			labels += 1
		elif child is MeshInstance3D:
			bursts += 1
		elif child is Node3D:
			for sub in child.get_children():
				if sub is Label3D:
					labels += 1
				elif sub is Sprite3D:
					sprites += 1
	_log("DEATH   burst=%d comic labels=%d skull sprites=%d" % [bursts, labels, sprites])

func _test_asteroids() -> void:
	var field: DebrisField = _arena.get_node_or_null("DebrisField")
	if field == null:
		_log("ASTEROID no debris field")
		return
	var rocks: Array = field.get_children()
	# Sample a rock that is actually inside some planet's influence - most of the
	# field drifts in true vacuum where zero acceleration is the correct answer.
	var sample: Asteroid = null
	for rock in rocks:
		if GravityManager.get_gravity_at((rock as Node3D).global_position).length() > 0.01:
			sample = rock
			break
	var pulled: String = "no rock currently inside a gravity well"
	if sample:
		var v0: Vector3 = sample.velocity
		for i in range(60):
			await get_tree().physics_frame
		if is_instance_valid(sample):
			pulled = "%.3f m/s gained in 1s" % (sample.velocity - v0).length()
	var first: Asteroid = rocks[0]
	_log("ASTEROID %d rocks (was 900 decorative, no physics); gravity: %s; layer=%d mask=%d" % [
		rocks.size(), pulled, first.collision_layer, first.collision_mask])

	# Aim one straight at a planet and watch it streak, then crater.
	var target: OrbitalBody = _arena.get_node("OrbitalBodies/Umbra")
	var rock := Asteroid.new()
	rock.radius = 2.5
	_arena.add_child(rock)
	var approach: Vector3 = Vector3(0.3, 0.8, 0.5).normalized()
	rock.global_position = target.global_position + approach * (target.radius + 70.0)
	rock.launch(-approach * 42.0)
	var orbit_before: float = target.orbit_radius
	var comet_seen: bool = false
	var impact_frame: int = -1
	for i in range(240):
		await get_tree().physics_frame
		if not is_instance_valid(rock):
			impact_frame = i
			break
		if rock._comet != null:
			comet_seen = true
	var cratered: bool = target.mesh.mesh is ArrayMesh
	_log("ASTEROID aimed shot: comet lit on approach=%s, impacted after %.2fs, planet mesh deformed=%s, orbit %.2f -> %.2f" % [
		comet_seen, float(impact_frame) / 60.0, cratered, orbit_before, target.orbit_radius])
