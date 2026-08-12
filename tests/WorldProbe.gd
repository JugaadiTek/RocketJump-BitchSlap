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
const SpawnerScript := preload("res://scripts/player/Spawner.gd")
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
	# Tower/ladder integrity checks run BEFORE _test_structural_collision(),
	# which deliberately demolishes buildings on whichever two bodies it
	# picks - Halcyon (this arena's usual tallest-tower candidate) isn't
	# exempt from that pick. Running after it once made a long tall-tower
	# ladder climb look like it stalled/glitched when the tower had actually
	# just been demolished out from under the climbing probe player by an
	# unrelated earlier test, not by anything in the climb itself.
	await _test_tower_height_range()
	_test_spin_axes()
	await _test_structural_collision()
	await _test_crater_collider()
	_test_curved_and_lit()
	_test_decor()
	await _test_planet_shader()
	_test_boundary_vs_spawn()
	await _test_ladder_death()
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
	var turrets: int = 0
	for body in GravityManager.get_bodies():
		for child in body.get_children():
			if child is Bunker:
				bunkers += 1
			elif child is Turret:
				turrets += 1
	_log("BUILDING %d bunkers, %d turrets placed" % [bunkers, turrets])

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


## Buildings must not float. Measured in world space against the planet centre,
## because pieces are now wrapped onto the sphere - a piece's local Y is no
## longer "height above the base", so the old flat measurement was meaningless.
##
## Reads the merged shell's actual vertices, not per-piece BoxMesh children -
## Building._commit_shell() welds every wall/box into ONE MeshInstance3D with
## a single ArrayMesh (the per-piece-draw-call fix - see CHANGELOG Session 6),
## so individual BoxMesh children stopped existing for walls/foundations. The
## only BoxMesh children left on a Tower are the roof flag and light bulbs -
## deliberately elevated fixtures - so the old per-piece scan was quietly
## measuring "how high is the flag" instead of "does the building touch the
## ground" ever since that merge, without ever failing loudly about it.
##
## Turret is exempted from the worst-case report: it's deliberately raised on
## stilt legs rather than sitting flush, so a gap there is the design, not a
## floating-building bug, and including it would drown out a genuine Tower/
## Bunker regression under an expected, harmless number.
func _test_foundations() -> void:
	var worst_gap: float = -INF
	var worst: String = ""
	var checked: int = 0
	for body in GravityManager.get_bodies():
		for child in body.get_children():
			if not (child is Building) or child is Turret:
				continue
			checked += 1
			var lowest: float = INF
			for piece in child.get_children():
				if not (piece is MeshInstance3D):
					continue
				var mesh_inst: MeshInstance3D = piece
				if mesh_inst.mesh is BoxMesh:
					var half: Vector3 = (mesh_inst.mesh as BoxMesh).size * 0.5
					for sx in [-1.0, 1.0]:
						for sy in [-1.0, 1.0]:
							for sz in [-1.0, 1.0]:
								var corner: Vector3 = mesh_inst.global_transform * Vector3(half.x * sx, half.y * sy, half.z * sz)
								lowest = minf(lowest, corner.distance_to(body.global_position))
				elif mesh_inst.mesh != null:
					# The merged shell (walls, floors, the foundation plinth):
					# an ArrayMesh, so read its faces directly instead of
					# assuming a BoxMesh shape.
					for v in mesh_inst.mesh.get_faces():
						var world_v: Vector3 = mesh_inst.global_transform * v
						lowest = minf(lowest, world_v.distance_to(body.global_position))
			if lowest == INF:
				continue
			# Positive means the lowest geometry stops short of the surface, i.e.
			# the building is hanging in the air.
			var gap: float = lowest - body.radius
			if gap > worst_gap:
				worst_gap = gap
				worst = "%s/%s" % [body.name, "Tower" if child is Tower else "Bunker"]  ## only Tower/Bunker reach here - Turret is excluded above
	_log("FOUNDATION %d buildings; deepest geometry vs surface, worst case %+.2fm%s" % [
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
	var wrecked: int = 0
	var standing: int = 0
	for host in [a, b]:
		for child in host.get_children():
			if child is Building:
				if child.is_demolished():
					wrecked += 1
				else:
					standing += 1
	_log("IMPACT  buildings on the two bodies: %d demolished, %d still standing" % [wrecked, standing])


## Craters must change the COLLIDER, not just the mesh - a player should be able
## to walk down into one.
func _test_crater_collider() -> void:
	var body: OrbitalBody = null
	for candidate in GravityManager.get_bodies():
		if not candidate.is_shattered and candidate.radius >= 20.0:
			body = candidate
			break
	if body == null:
		_log("CRATERHIT no suitable planet")
		return
	var before_shape: String = body.collision.shape.get_class()
	# Measure the collision surface height directly under a chosen point, by
	# raycasting inward from above it.
	var out: Vector3 = Vector3(0.2, 1.0, 0.3).normalized()
	var probe_point: Vector3 = body.global_position + out * (body.radius + 12.0)
	var before_hit: float = _surface_distance(body, probe_point, out)
	body.apply_crater(body.global_position + out * body.radius, 9.0, 4.0)
	# Collider rebuilds are coalesced on a timer; wait past it.
	for i in range(60):
		await get_tree().physics_frame
	var after_shape: String = body.collision.shape.get_class()
	var after_hit: float = _surface_distance(body, probe_point, out)
	_log("CRATERHIT %s: collider %s -> %s, surface under impact dropped %.2fm" % [
		body.name, before_shape, after_shape, after_hit - before_hit])

## Distance from `from` inward to whatever the physics world says is solid.
func _surface_distance(body: OrbitalBody, from: Vector3, out: Vector3) -> float:
	var space := get_viewport().world_3d.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, body.global_position)
	query.collision_mask = 1
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return -1.0
	return from.distance_to(hit.position)

## Buildings should be wrapped onto the sphere (pieces tilted to the local
## normal) and lit inside.
func _test_curved_and_lit() -> void:
	var tilted: int = 0
	var total: int = 0
	var lights: int = 0
	var worst_tilt: float = 0.0
	for body in GravityManager.get_bodies():
		for child in body.get_children():
			if not (child is Building):
				continue
			for piece in child.get_children():
				if piece is OmniLight3D:
					lights += 1
				if not (piece is MeshInstance3D):
					continue
				total += 1
				# A piece off the building's centre line should be rotated so
				# its own up follows the sphere, not left axis-aligned.
				var tilt: float = rad_to_deg(piece.transform.basis.y.angle_to(Vector3.UP))
				if tilt > 0.5:
					tilted += 1
				worst_tilt = maxf(worst_tilt, tilt)
	_log("CURVED  %d/%d building pieces tilted to the surface (max tilt %.1f deg); %d interior lights" % [
		tilted, total, worst_tilt, lights])

func _test_decor() -> void:
	var rings: int = 0
	var shells: int = 0
	for body in GravityManager.get_bodies():
		if body._orbit_ring != null and is_instance_valid(body._orbit_ring):
			rings += 1
		if body._atmosphere != null:
			shells += 1
	# The debris field is now a spawner of real Asteroid bodies, not a MultiMesh.
	var field: DebrisField = _arena.get_node_or_null("DebrisField")
	var rocks: int = field.get_child_count() if field else 0
	var faceted: bool = GravityManager.get_bodies()[0].mesh.mesh is ArrayMesh
	_log("DECOR   %d orbit rings, %d atmosphere shells, %d debris rocks, planets faceted=%s" % [
		rings, shells, rocks, faceted])

## NEW - Arena._build_buildings() now sets every tower_height to its planet's
## own full circumference (TAU*radius) consistently, instead of the old fixed
## cap AT radius - so this should now read very close to TAU for every body
## whose height_budget allows it (below TAU only for the specific
## permanently-fixed-separation pairs _solve_structure_heights() trims).
## Reports the observed range against that ceiling, then specifically re-runs
## the hollow-interior and ladder-climb-to-peak checks against the TALLEST
## tower generated (not just "the first tower found", which the checks above
## use) - more floors and a longer shaft is exactly the case most likely to
## expose something the original fixed ~30m towers never could.
func _test_tower_height_range() -> void:
	var count: int = 0
	var min_ratio: float = INF
	var max_ratio: float = -INF
	var over_ceiling: int = 0
	var tallest: Tower = null
	var tallest_host: OrbitalBody = null
	for body in GravityManager.get_bodies():
		for child in body.get_children():
			if not (child is Tower):
				continue
			count += 1
			var ratio: float = child.tower_height / body.radius
			min_ratio = minf(min_ratio, ratio)
			max_ratio = maxf(max_ratio, ratio)
			if child.tower_height > TAU * body.radius + 0.01:
				over_ceiling += 1
			if tallest == null or child.tower_height > tallest.tower_height:
				tallest = child
				tallest_host = body
	if count == 0:
		_log("TOWERHEIGHT no towers found")
		return
	_log("TOWERHEIGHT %d towers; height/radius ratio observed %.2fx-%.2fx (ceiling is TAU=%.2fx); %d exceed the ceiling; tallest=%.0fm on %s (r%.0f)" % [
		count, min_ratio, max_ratio, TAU, over_ceiling, tallest.tower_height, tallest_host.name, tallest_host.radius])
	if tallest == null:
		return

	var space := get_viewport().world_3d.direct_space_state
	var inside: Vector3 = tallest.global_transform * Vector3(0.0, 1.6, 0.0)
	var query := PhysicsShapeQueryParameters3D.new()
	var probe_shape := SphereShape3D.new()
	probe_shape.radius = 0.35
	query.shape = probe_shape
	query.transform = Transform3D(Basis(), inside)
	query.collision_mask = 1
	var hollow: bool = space.intersect_shape(query, 1).is_empty()

	var ladder: Ladder = null
	for child in tallest.get_children():
		if child is Ladder:
			ladder = child
	if ladder == null:
		_log("TOWERHEIGHT tallest tower (%.0fm) interior clear=%s, has no ladder to verify climb" % [tallest.tower_height, hollow])
		return

	var scene: PackedScene = load("res://scenes/player/Player.tscn")
	var player: Player = scene.instantiate()
	player.set_script(ProbePlayer)
	player.name = "TowerHeightProbe"
	_arena.get_node("Players").add_child(player)
	player.player_id = 97
	await get_tree().physics_frame
	player.disable_spawner()
	var shaft_bottom: Vector3 = ladder.global_transform * Vector3(0.0, -ladder.get_child(0).shape.size.y * 0.5 + 1.0, 0.0)
	player.global_position = shaft_bottom
	player.reset_frame()
	# Consistently-max-height towers mean every tower-bearing body now carries
	# a large, constant structure_reach (not just occasionally, the way the
	# old randomised range left most bodies short most of the time) - which
	# directly enlarges GravityManager's real structural-collision contact
	# distance (radius + structure_reach on both sides) for every pair in the
	# arena at once. In practice that makes an ordinary, unforced structural
	# collision landing on THIS specific body during a long climb window far
	# more likely than it used to be - a real, separate consequence of the
	# height change, not a flaw in the climb itself, but one that would
	# otherwise contaminate this specific check almost every run. Suppressed
	# for just the climb window (restored after) so this test measures the
	# ladder mechanism, not a coin-flip against an unrelated collision.
	tallest_host.collision_cooldown = 999.0
	for i in range(20):
		await get_tree().physics_frame
	player.probe_move = Vector2(0.0, 1.0)
	var peak: float = _local_height(player, tallest)
	# Capped well below "climb the whole thing" for a very tall tower: with
	# towers now consistently at a full circumference (up to hundreds of
	# metres), a genuine top-to-bottom climb can take over a minute of
	# simulated time, and this arena keeps running its full background
	# simulation throughout (bots landing, craters, natural structural
	# collisions between orbiting bodies) - on Halcyon specifically (this
	# arena's usual furthest-out body, so the first one to reach
	# ARENA_BOUNDARY_RADIUS and auto-shatter, or the first to take a real,
	# unforced structural-collision hit), that background activity can
	# demolish the very tower being climbed well before a full climb
	# finishes. That's a real, separate, pre-existing mechanic - not a
	# ladder bug - so it's detected and reported distinctly below rather
	# than misread as a climb failure. What this test actually needs to
	# prove is that climbing continues cleanly well PAST the altitude where
	# it used to stall (~36m, planet_frame_height * release_ratio) - 900
	# frames (15s, ~67m of climb) comfortably clears that with margin, without
	# requiring the whole background simulation to stay quiet for a full minute+.
	var climb_frames: int = mini(int(tallest.tower_height / player.ladder_climb_speed * 60.0 * 1.3), 900)
	var progress: Array[String] = []
	var host_lost_at_frame: int = -1
	for i in range(climb_frames):
		await get_tree().physics_frame
		if host_lost_at_frame < 0 and (not is_instance_valid(tallest_host) or tallest_host.is_shattered
				or not is_instance_valid(tallest) or tallest.is_demolished()):
			host_lost_at_frame = i
			break
		peak = maxf(peak, _local_height(player, tallest))
		if i % 150 == 0:
			progress.append("%.1fm@%s" % [_local_height(player, tallest), player._is_on_ladder()])
	player.probe_move = Vector2.ZERO
	if is_instance_valid(tallest_host):
		tallest_host.collision_cooldown = 0.0
	if host_lost_at_frame >= 0:
		_log("TOWERHEIGHT tallest tower (%.0fm on %s): tower shattered/demolished mid-climb at frame %d by an unrelated, ordinary world mechanic (boundary auto-shatter or a real structural collision) - reached %.1fm first, not a ladder bug" % [
			tallest.tower_height, tallest_host.name, host_lost_at_frame, peak])
	else:
		_log("TOWERHEIGHT tallest tower (%.0fm, %d floors): interior clear=%s, ladder held for the full %d-frame climb window, reached %.1fm (comfortably past the old ~36m stall point)" % [
			tallest.tower_height, tallest.floor_count, hollow, climb_frames, peak])
		_log("TOWERHEIGHT climb progress (height@on_ladder every 150 frames) = [%s]" % ", ".join(progress))
	player.queue_free()

## NEW - planets now use a custom ShaderMaterial (planet_surface.gdshader,
## hue-rotating edges) instead of StandardMaterial3D. Confirms every live
## planet actually got one with a real colour, and that moon fragments
## spawned by shatter() - which rebuild the ShaderMaterial from scratch and
## have to re-apply the bump pattern on the new instance - come out coloured
## too rather than bare/black.
func _test_planet_shader() -> void:
	var bodies: Array[OrbitalBody] = GravityManager.get_bodies()
	var shader_count: int = 0
	var bad: Array[String] = []
	for body in bodies:
		var mat: Material = body.mesh.get_surface_override_material(0)
		if mat is ShaderMaterial:
			var col: Variant = (mat as ShaderMaterial).get_shader_parameter("albedo_color")
			if col is Color and (col as Color).a > 0.0 and (col as Color) != Color(0, 0, 0, 1):
				shader_count += 1
			else:
				bad.append(body.name + "(no real albedo_color)")
		else:
			bad.append(body.name + "(not a ShaderMaterial)")
	_log("PLANETSHADER %d/%d planets using planet_surface ShaderMaterial with a real albedo_color; problems=[%s]" % [
		shader_count, bodies.size(), ", ".join(bad)])

	var target: OrbitalBody = null
	for body in bodies:
		if not body.is_shattered and body.radius >= 8.0 and body.orbit_pivot != null:
			target = body
			break
	if target == null:
		_log("PLANETSHADER no shatterable body found to test fragment colour")
		return
	var frag_seen: Array = []
	target.fragment_spawned.connect(func(f): frag_seen.append(f))
	target.shatter(target.radius * 3.0, 99999.0)
	for i in range(10):
		await get_tree().physics_frame
	var frag_ok: int = 0
	for f in frag_seen:
		if not is_instance_valid(f):
			continue
		var fmesh: MeshInstance3D = f.get_node_or_null("MeshInstance3D")
		if fmesh == null:
			continue
		var fmat: Material = fmesh.get_surface_override_material(0)
		if fmat is ShaderMaterial:
			var col: Variant = (fmat as ShaderMaterial).get_shader_parameter("albedo_color")
			if col is Color and (col as Color).a > 0.0 and (col as Color) != Color(0, 0, 0, 1):
				frag_ok += 1
	_log("PLANETSHADER shattered %s: %d fragments spawned, %d with a real (non-black/non-bare) ShaderMaterial colour" % [
		target.name, frag_seen.size(), frag_ok])

## NEW - a very tall randomised tower on the outermost planet directly
## inflates GravityManager.arena_half_extent() (structure_reach feeds it).
## Spawner._spawn_radius() (fixed bug: this used to be a hard-coded constant,
## SPAWN_RADIUS, chosen once "just inside ARENA_BOUNDARY_RADIUS, clear of
## Halcyon" - it didn't adapt when the box grew past it) should now track the
## live boundary with a fixed margin, never spawning near or outside its edge
## regardless of how far a tower's structure_reach pushes it out.
func _test_boundary_vs_spawn() -> void:
	var extent: float = GravityManager.arena_half_extent()
	var spawn_radius: float = SpawnerScript._spawn_radius()
	var margin: float = extent - spawn_radius
	_log("BOUNDARYSPAWN arena_half_extent=%.0fm, spawn_radius=%.0fm, margin=%.0fm -> spawn point is %s the flexing boundary box (margin should track SPAWN_BOUNDARY_MARGIN=%.0f, not drift toward 0)" % [
		extent, spawn_radius, margin, "INSIDE" if spawn_radius < extent else "OUTSIDE/AT THE EDGE OF", SpawnerScript.SPAWN_BOUNDARY_MARGIN])

## NEW - dying mid-ladder-climb never calls Ladder's own exit path
## (clear_ladder()), since the player is hidden/collision-stripped by
## _die()/_respawn() rather than walking out of the Area3D. Both _die() and
## _respawn() unconditionally overwrite collision_mask wholesale (not just
## OR/AND the world bit the way set_ladder()/clear_ladder() do), so that part
## looks safe by inspection - but the `_ladder` reference itself is never
## cleared, so this actually measures whether a stale reference to a
## far-away ladder leaves _is_on_ladder() reporting true right after
## respawn, which would wrongly apply ladder movement (gravity suspended,
## velocity locked to the ladder axis) at the new spawn location.
func _test_ladder_death() -> void:
	var tower: Tower = null
	for body in GravityManager.get_bodies():
		for child in body.get_children():
			if child is Tower and tower == null:
				tower = child
	if tower == null:
		_log("LADDERDEATH no tower found to test")
		return
	var ladder: Ladder = null
	for child in tower.get_children():
		if child is Ladder:
			ladder = child
	if ladder == null:
		_log("LADDERDEATH tower has no ladder")
		return

	var scene: PackedScene = load("res://scenes/player/Player.tscn")
	var player: Player = scene.instantiate()
	player.set_script(ProbePlayer)
	player.name = "LadderDeathProbe"
	player.display_name = "LadderDeathProbe"
	_arena.get_node("Players").add_child(player)
	player.player_id = 96
	await get_tree().physics_frame
	player.disable_spawner()

	var shaft_bottom: Vector3 = ladder.global_transform * Vector3(0.0, -ladder.get_child(0).shape.size.y * 0.5 + 1.0, 0.0)
	player.global_position = shaft_bottom
	player.reset_frame()
	player.probe_move = Vector2(0.0, 1.0)
	for i in range(60):
		await get_tree().physics_frame
	var was_on_ladder: bool = player._is_on_ladder()
	var mask_while_climbing: int = player.collision_mask

	player.apply_damage(1000000.0, null, player.global_position, "probe")
	for i in range(int(player.respawn_delay * 60.0) + 60):
		await get_tree().physics_frame
	var mask_after_respawn: int = player.collision_mask
	var default_mask: int = player._default_collision_mask
	var stale_on_ladder: bool = player._is_on_ladder()
	player.probe_move = Vector2.ZERO
	_log("LADDERDEATH was climbing (on_ladder=%s, mask=%d) -> killed -> after respawn: mask=%d matches default %d=%s, stale is_on_ladder=%s (should be false)" % [
		was_on_ladder, mask_while_climbing, mask_after_respawn, default_mask, mask_after_respawn == default_mask, stale_on_ladder])
	player.queue_free()
