extends Node
## Headless probe for the arena/world changes:
##   LAYOUT    - no two bodies overlap, and everything fits inside the boundary
##   BUILDING  - towers are as tall as their planet, and their interiors are
##               actually hollow (the old single collision box sealed them)
##   LADDER    - a player inside a tower's ladder volume can climb to the top
##   SPAWN     - bots run the boundary-launch spawn and land on a planet
##   CRATER    - landing deforms the planet mesh
##
## Run: Godot --headless --path . res://tests/WorldProbe.tscn

const ProbePlayer := preload("res://tests/ProbePlayer.gd")
const ARENA := preload("res://scenes/world/Arena.tscn")
const LOG_PATH := "/tmp/rjbs_world.log"

var _arena: Node3D

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
	_arena.bot_count = 6
	add_child(_arena)
	for i in range(4):
		await get_tree().physics_frame

	# Sampled first: bots choose a planet within 0.5-2.5s and are gone from the
	# boundary long before the later phases finish.
	var bots_at_boundary: int = 0
	var bot_total: int = _arena.get_node("Bots").get_child_count()
	for bot in _arena.get_node("Bots").get_children():
		if bot.global_position.length() > GravityManager.ARENA_BOUNDARY_RADIUS * 0.85:
			bots_at_boundary += 1
	_log("SPAWN   %d/%d bots start on the boundary shell (spawn flow, not teleported in)" % [
		bots_at_boundary, bot_total])

	_test_layout()
	_test_buildings()
	await _test_ladder()
	await _test_spawn_and_crater()
	_test_foundations()
	_test_health_packs()
	_test_spin_axes()
	await _test_structural_collision()
	get_tree().quit()

## Bodies must not intersect, and nothing may sit outside the arena boundary.
func _test_layout() -> void:
	var bodies: Array[OrbitalBody] = GravityManager.get_bodies()
	var worst_overlap: float = -INF
	var worst_pair: String = ""
	var furthest: float = 0.0
	for i in range(bodies.size()):
		for j in range(i + 1, bodies.size()):
			var a: OrbitalBody = bodies[i]
			var b: OrbitalBody = bodies[j]
			var gap: float = a.global_position.distance_to(b.global_position) - a.radius - b.radius
			if -gap > worst_overlap:
				worst_overlap = -gap
				worst_pair = "%s/%s" % [a.name, b.name]
	for body in bodies:
		furthest = maxf(furthest, body.global_position.length() + body.radius)
	_log("LAYOUT  %d bodies; tightest pair %s with %.1fm clearance; furthest reach %.0fm of %.0fm boundary" % [
		bodies.size(), worst_pair, -worst_overlap, furthest, GravityManager.ARENA_BOUNDARY_RADIUS])

## Towers should match their planet's radius, and an interior point must be
## free of collision - that is what "navigable" means here.
func _test_buildings() -> void:
	var space := get_viewport().world_3d.direct_space_state
	var checked: int = 0
	var hollow: int = 0
	var height_report: Array[String] = []
	for body in GravityManager.get_bodies():
		for child in body.get_children():
			if not (child is Tower):
				continue
			checked += 1
			height_report.append("%s:%.0f(r%.0f)" % [body.name, child.tower_height, body.radius])
			# A point inside the ground floor, half a metre up from its base.
			var inside: Vector3 = child.global_transform * Vector3(0.0, 1.6, 0.0)
			var query := PhysicsShapeQueryParameters3D.new()
			var probe_shape := SphereShape3D.new()
			probe_shape.radius = 0.35
			query.shape = probe_shape
			query.transform = Transform3D(Basis(), inside)
			query.collision_mask = 1
			if space.intersect_shape(query, 1).is_empty():
				hollow += 1
	_log("BUILDING %d towers, %d with a clear interior; heights vs planet radius = [%s]" % [
		checked, hollow, ", ".join(height_report)])
	var bunkers: int = 0
	for body in GravityManager.get_bodies():
		for child in body.get_children():
			if child is Bunker:
				bunkers += 1
	_log("BUILDING %d bunkers placed" % bunkers)

## Drop a player into a tower's ladder volume and hold "climb".
func _test_ladder() -> void:
	var tower: Tower = null
	var host: OrbitalBody = null
	for body in GravityManager.get_bodies():
		for child in body.get_children():
			if child is Tower and tower == null:
				tower = child
				host = body
	if tower == null:
		_log("LADDER  no tower found to test")
		return
	var ladder: Ladder = null
	for child in tower.get_children():
		if child is Ladder:
			ladder = child
	if ladder == null:
		_log("LADDER  tower has no ladder volume")
		return

	var scene: PackedScene = load("res://scenes/player/Player.tscn")
	var player: Player = scene.instantiate()
	player.set_script(ProbePlayer)
	_arena.get_node("Players").add_child(player)
	player.player_id = 98
	await get_tree().physics_frame
	player.disable_spawner()

	# Start at the bottom of the shaft.
	var shaft_bottom: Vector3 = ladder.global_transform * Vector3(0.0, -ladder.get_child(0).shape.size.y * 0.5 + 1.0, 0.0)
	player.global_position = shaft_bottom
	player.reset_frame()
	for i in range(20):
		await get_tree().physics_frame
	var on_ladder: bool = player._is_on_ladder()
	var start_height: float = _local_height(player, tower)
	player.probe_move = Vector2(0.0, 1.0)   # forward == climb up
	# Peak, not final: the ladder ends below the roof, so once the player climbs
	# off the top rung normal movement resumes and they drop onto the top floor.
	var peak: float = start_height
	for i in range(420):
		await get_tree().physics_frame
		peak = maxf(peak, _local_height(player, tower))
	player.probe_move = Vector2.ZERO
	_log("LADDER  detected=%s climbed %.1fm -> peak %.1fm of a %.0fm tower (ladder tops out at %.1fm)" % [
		on_ladder, start_height, peak, tower.tower_height,
		tower.tower_height - (tower.tower_height / float(tower.floor_count)) * 0.5])
	player.queue_free()

func _local_height(player: Player, tower: Tower) -> float:
	return (tower.global_transform.affine_inverse() * player.global_position).y

## Bots should fly the boundary-launch spawn and land, cratering as they touch.
func _test_spawn_and_crater() -> void:
	var bots: Array = _arena.get_node("Bots").get_children()
	if bots.is_empty():
		_log("SPAWN   no bots spawned")
		return
	# Let them choose, fly in and land.
	for i in range(600):
		await get_tree().physics_frame
	var landed: int = 0
	for bot in bots:
		if not is_instance_valid(bot):
			continue
		var body: OrbitalBody = GravityManager.get_nearest_body(bot.global_position)
		if body and (bot.global_position.distance_to(body.global_position) - body.radius) < 6.0:
			landed += 1
	_log("SPAWN   %d/%d bots are now on a planet surface" % [landed, bots.size()])

	var cratered: int = 0
	for body in GravityManager.get_bodies():
		if body.mesh.mesh is ArrayMesh:
			cratered += 1
	_log("CRATER  %d planets have had their mesh deformed by landings" % cratered)


## Buildings must not float: with a flat base on a curved planet, the outer
## corners hang by the sagitta unless a foundation fills that gap.
func _test_foundations() -> void:
	var worst_gap: float = 0.0
	var worst: String = ""
	var checked: int = 0
	for body in GravityManager.get_bodies():
		for child in body.get_children():
			if not (child is Building):
				continue
			checked += 1
			var footprint: float = child.footprint_radius()
			# Lowest point of geometry, measured along the building's own down
			# axis, versus where the planet surface actually is at that corner.
			var sagitta: float = body.radius - sqrt(maxf(body.radius * body.radius - footprint * footprint, 0.0))
			var lowest: float = 0.0
			for piece in child.get_children():
				if piece is MeshInstance3D and piece.mesh is BoxMesh:
					lowest = minf(lowest, piece.position.y - piece.mesh.size.y * 0.5)
			# A gap remains only if the geometry stops short of the corner drop.
			var gap: float = sagitta - (-lowest)
			if gap > worst_gap:
				worst_gap = gap
				worst = "%s/%s" % [body.name, child.get_class()]
	_log("FOUNDATION %d buildings; largest remaining corner gap %.2fm%s" % [
		checked, worst_gap, (" (" + worst + ")") if worst != "" else ""])

func _test_health_packs() -> void:
	var report: Array[String] = []
	var total: int = 0
	for body in GravityManager.get_bodies():
		var n: int = 0
		for child in body.get_children():
			if child is HealthPack:
				n += 1
		total += n
		if n > 0:
			report.append("%s(r%.0f):%d" % [body.name, body.radius, n])
	_log("HEALTH  %d packs total, scaled by planet size = [%s]" % [total, ", ".join(report)])

func _test_spin_axes() -> void:
	var distinct: Array[String] = []
	var all_polar: bool = true
	for body in GravityManager.get_bodies():
		var axis: Vector3 = body.spin_axis.normalized()
		if absf(axis.dot(Vector3.UP)) < 0.99:
			all_polar = false
		distinct.append("%.2f,%.2f,%.2f" % [axis.x, axis.y, axis.z])
	_log("SPIN    all-polar=%s; axes = [%s]" % [all_polar, ", ".join(distinct.slice(0, 5)) + ", ..."])

## Force two planets together and confirm both orbits take a real kick.
func _test_structural_collision() -> void:
	var bodies: Array[OrbitalBody] = GravityManager.get_bodies()
	var a: OrbitalBody = null
	var b: OrbitalBody = null
	for body in bodies:
		if body.is_shattered or body.orbit_pivot == null or body.structure_reach <= 0.0:
			continue
		if a == null:
			a = body
		elif b == null and body.orbit_pivot == a.orbit_pivot:
			b = body
	if a == null or b == null:
		_log("IMPACT  could not find two independent bodies with structures")
		return
	var before := {"a_r": a.orbit_radius, "a_s": a.orbit_speed, "b_r": b.orbit_radius, "b_s": b.orbit_speed}
	# Drop b's orbit onto a's so their structures overlap on the next scan.
	b.orbit_radius = a.orbit_radius
	b.orbit_axis = a.orbit_axis
	b._orbit_angle = a._orbit_angle
	b._semi_minor = b.orbit_radius
	# Let GravityManager's pair scan notice them.
	for i in range(6):
		await get_tree().physics_frame
	_log("IMPACT  %s orbit %.1f->%.1f speed %.4f->%.4f | %s orbit %.1f->%.1f speed %.4f->%.4f" % [
		a.name, before["a_r"], a.orbit_radius, before["a_s"], a.orbit_speed,
		b.name, before["b_r"], b.orbit_radius, before["b_s"], b.orbit_speed])
	_log("IMPACT  both cooldowns armed (a=%.1fs b=%.1fs) so one encounter registers once" % [
		a.collision_cooldown, b.collision_cooldown])
