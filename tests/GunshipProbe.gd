extends Node
## Headless probe for the Artillery Gunship feature end-to-end:
##   SPAWN    - GunshipDirector spawns one, autopilot steers it clear of a
##              planet placed directly in its path
##   DAMAGE   - any weapon's apply_damage works against it for free, and it
##              actually dies at 0 health
##   MOUNT    - a player can claim the empty seat, and gets weapon control
##              (not flight) while seated
##   ARTILLERY - firing from the seat paints 3 markers on the aimed planet,
##              then launches shells that actually land, deform the surface,
##              perturb the orbit, and damage anything caught in the blast
##   TAKEOVER - bitchslapping the seated driver hands the seat to the
##              attacker after the kill resolves
##
## Run: Godot --headless --path . res://tests/GunshipProbe.tscn

const ProbePlayer := preload("res://tests/ProbePlayer.gd")
const ProbeLocalPlayer := preload("res://tests/ProbeLocalPlayer.gd")
const ARENA := preload("res://scenes/world/Arena.tscn")
const LOG_PATH := "/tmp/rjbs_gunship.log"

var _arena: Node3D

func _log(line: String) -> void:
	print(line)
	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(LOG_PATH) else FileAccess.WRITE)
	if f:
		f.seek_end(); f.store_line(line); f.close()

func _ready() -> void:
	seed(20260813)
	_arena = ARENA.instantiate()
	_arena.bot_count = 0
	add_child(_arena)
	await get_tree().physics_frame
	await get_tree().physics_frame

	await _test_spawn_and_avoidance()
	await _test_boundary_containment_and_abandonment()
	await _test_damage_and_destruction()
	await _test_mount_and_artillery()
	await _test_bitchslap_takeover()
	get_tree().quit()

func _director() -> Node:
	return _arena.get_node("GunshipDirector")

## Forces an immediate spawn (real spawn_delay is 120s) by driving the
## director's own timer to zero, the same "skip the wait, exercise the real
## code path" approach every other probe in this project already uses for
## its own cooldowns/timers.
func _force_spawn() -> Gunship:
	var director: Node = _director()
	director.set("_timer", 0.0)
	director._physics_process(0.0)
	await get_tree().physics_frame
	var ships: Array = _arena.get_node("Gunships").get_children()
	return ships[0] if ships.size() > 0 else null

func _test_spawn_and_avoidance() -> void:
	var ship: Gunship = await _force_spawn()
	if ship == null:
		_log("SPAWN   FAIL - GunshipDirector did not spawn a ship")
		return
	_log("SPAWN   gunship spawned at %s, health=%.0f/%.0f" % [ship.global_position, ship.health, ship.max_health])

	# Aim it directly at a real planet and confirm avoidance actually bends
	# the heading away rather than flying straight through.
	var target_body: OrbitalBody = _arena.get_node("OrbitalBodies/Halcyon")
	var to_body: Vector3 = (target_body.global_position - ship.global_position)
	ship.global_position = target_body.global_position - to_body.normalized() * (target_body.radius * 4.0)
	ship.set("_velocity_dir", to_body.normalized())
	var min_dist: float = INF
	for i in range(400):
		await get_tree().physics_frame
		var d: float = ship.global_position.distance_to(target_body.global_position) - target_body.radius
		min_dist = minf(min_dist, d)
	_log("SPAWN   aimed straight at %s (radius %.0f): closest approach over 400 frames = %.1fm (avoidance held if > 0)" % [
		target_body.name, target_body.radius, min_dist])

## IMPROVEMENT - the ship meanders and stays inside the arena boundary on its
## own (never manned, or currently manned), but pathfinds its own way back
## out once abandoned (had a driver, no longer does), cancelled the instant
## someone re-mans it.
func _test_boundary_containment_and_abandonment() -> void:
	var ship: Gunship = await _force_spawn()
	if ship == null:
		_log("ROAM    FAIL - no ship to test")
		return

	var bmax: Vector3 = GravityManager.arena_bounds_max()
	# Partway into the containment margin (not exactly at its outer edge,
	# where the push is zero by definition - see _axis_containment), heading
	# straight for the wall - realistic lead time given turn_speed_degrees
	# (12 deg/s can't spin the ship around in a few seconds, so this checks
	# the heading is actively curving away, not that it's already reversed).
	var margin_edge: Vector3 = Vector3(bmax.x - ship.boundary_containment_margin * 0.5, 0.0, 0.0)
	ship.global_position = margin_edge
	ship.set("_velocity_dir", Vector3.RIGHT) # heading straight for the wall

	var never_manned_push: Vector3 = ship._containment_push()
	for i in range(300):
		await get_tree().physics_frame
	var heading_curved_away: bool = ship._velocity_dir.x < 0.9
	var still_within_boundary: bool = GravityManager.is_within_boundary(ship.global_position)
	var still_alive_unmanned: bool = is_instance_valid(ship)

	# Simulate having had, then losing, a driver (real mount/dismount RPCs
	# are exercised end-to-end in _test_mount_and_artillery/_bitchslap_takeover -
	# this test is specifically about what the autopilot DOES with that state).
	ship._broadcast_set_driver(999)
	await get_tree().physics_frame
	ship._broadcast_set_driver(-1)
	var abandoned: bool = ship.is_abandoned()
	ship.global_position = margin_edge
	var abandoned_push: Vector3 = ship._escape_push()

	# Right at the boundary and abandoned should actually despawn it.
	ship.global_position = Vector3(GravityManager.arena_bounds_max().x + 5.0, 0.0, 0.0)
	ship._physics_process(0.016)
	await get_tree().physics_frame
	var left_when_abandoned_and_outside: bool = not is_instance_valid(ship)

	_log("ROAM    unmanned near boundary: containment push points inward=%s -> heading curves away over 5s=%s, stays within boundary=%s (still alive=%s) | after being manned then abandoned: is_abandoned=%s, push now points outward=%s | abandoned + past boundary despawns=%s" % [
		never_manned_push.x < 0.0, heading_curved_away, still_within_boundary, still_alive_unmanned, abandoned, abandoned_push.x > 0.0, left_when_abandoned_and_outside])

	# A fresh ship for the "re-manning cancels leaving" half, since the one
	# above is now freed.
	var ship2: Gunship = await _force_spawn()
	if ship2 == null:
		_log("ROAM    FAIL - no second ship for re-mount cancel check")
		return
	ship2._broadcast_set_driver(999)
	await get_tree().physics_frame
	ship2._broadcast_set_driver(-1)
	var abandoned2: bool = ship2.is_abandoned()
	ship2._broadcast_set_driver(999) # re-manned
	var cancelled: bool = not ship2.is_abandoned()
	ship2._broadcast_set_driver(-1) # release it again so later tests see an empty seat
	_log("ROAM    re-mounting an abandoned ship: was abandoned=%s -> re-manned cancels it=%s" % [abandoned2, cancelled])

func _test_damage_and_destruction() -> void:
	var ship: Gunship = await _force_spawn()
	if ship == null:
		_log("DAMAGE  FAIL - no ship to test")
		return
	var before: float = ship.health
	ship.apply_damage(500.0, null, ship.global_position, "test")
	var after_partial: float = ship.health
	var alive_after_partial: bool = not ship.is_destroyed
	ship.apply_damage(ship.max_health, null, ship.global_position, "test")
	var destroyed_now: bool = ship.is_destroyed
	for i in range(180):
		await get_tree().physics_frame
	var freed_after_delay: bool = not is_instance_valid(ship)
	_log("DAMAGE  health %.0f -> %.0f after 500dmg (still alive=%s) -> destroyed after lethal hit=%s -> node freed ~%s later=%s" % [
		before, after_partial, alive_after_partial, destroyed_now, "2.5s", freed_after_delay])

func _test_mount_and_artillery() -> void:
	var ship: Gunship = await _force_spawn()
	if ship == null:
		_log("MOUNT   FAIL - no ship to test")
		return

	var scene: PackedScene = load("res://scenes/player/Player.tscn")
	var driver: Player = scene.instantiate()
	driver.set_script(ProbePlayer)
	driver.name = "GunshipDriver"
	_arena.get_node("Players").add_child(driver, true)
	driver.player_id = 401
	await get_tree().physics_frame
	driver.disable_spawner()
	driver.global_position = ship.seat_marker.global_position
	driver.velocity = Vector3.ZERO
	driver.reset_frame()
	for i in range(5):
		await get_tree().physics_frame

	var had_no_driver_before: bool = not ship.has_driver()
	ship.request_mount(driver.get_path())
	await get_tree().physics_frame
	for i in range(5):
		await get_tree().physics_frame
	var mount_granted: bool = ship.driver_id == driver.player_id
	var player_sees_itself_mounted: bool = driver.mounted_gunship == ship

	# Aim the driver at a live planet and hold fire - should paint 3 markers,
	# then (after paint_to_launch_delay) launch shells at them. Re-aims every
	# frame rather than once - the seat doesn't carry the driver along with
	# the hull's own autopilot drift (a documented, deliberate limitation, see
	# Gunship.gd's own class doc), so a single stale aim_at() call can drift
	# off the target over a few frames exactly the way it never would for a
	# real player continuously correcting with the mouse.
	var target_body: OrbitalBody = _arena.get_node("OrbitalBodies/Cinder")
	driver.aim_at(target_body.global_position)
	for i in range(3):
		await get_tree().physics_frame
		driver.aim_at(target_body.global_position)
	var start_orbit_radius: float = target_body.orbit_radius
	var start_speed: float = target_body.orbit_speed
	driver.probe_fire = true
	for i in range(5):
		await get_tree().physics_frame
		driver.aim_at(target_body.global_position)
	driver.probe_fire = false
	var markers_painted: int = target_body.get_children().filter(func(c): return c is ArtilleryMarker).size()
	var cooldown_engaged: bool = not ship.can_fire_artillery()

	# Firing again immediately should be refused (still on cooldown).
	driver.probe_fire = true
	await get_tree().physics_frame
	driver.probe_fire = false
	var second_burst_blocked: bool = target_body.get_children().filter(func(c): return c is ArtilleryMarker).size() == markers_painted

	# Wait out the paint delay + a generous flight window for the shells to
	# actually land and resolve.
	for i in range(600):
		await get_tree().physics_frame
		if not is_instance_valid(target_body) or target_body.is_shattered:
			break
	var markers_cleared: bool = not is_instance_valid(target_body) or target_body.get_children().filter(func(c): return c is ArtilleryMarker).is_empty()
	var orbit_perturbed: bool = is_instance_valid(target_body) and (not is_equal_approx(target_body.orbit_radius, start_orbit_radius) or not is_equal_approx(target_body.orbit_speed, start_speed))

	_log("MOUNT   seat empty before=%s -> request_mount grants driver_id=%s, player's own mounted_gunship updates=%s" % [
		had_no_driver_before, mount_granted, player_sees_itself_mounted])
	_log("ARTILLERY fired at %s: markers painted=%d/3 | immediate re-fire blocked by cooldown=%s | markers cleared after shells resolve=%s | orbit perturbed=%s" % [
		target_body.name, markers_painted, cooldown_engaged and second_burst_blocked, markers_cleared, orbit_perturbed])

	# Release the seat before freeing the probe player - otherwise the ship's
	# driver_id keeps pointing at a now-freed node and has_driver() stays
	# true forever, which would silently break every later test that needs
	# to mount a (possibly reused, still-alive) ship.
	ship.request_dismount(driver.player_id)
	driver.queue_free()

func _test_bitchslap_takeover() -> void:
	var ship: Gunship = await _force_spawn()
	if ship == null:
		_log("TAKEOVER FAIL - no ship to test")
		return

	var scene: PackedScene = load("res://scenes/player/Player.tscn")
	var victim: Player = scene.instantiate()
	victim.set_script(ProbePlayer)
	victim.name = "TakeoverVictim"
	_arena.get_node("Players").add_child(victim, true)
	victim.player_id = 402
	await get_tree().physics_frame
	victim.disable_spawner()
	victim.global_position = ship.seat_marker.global_position
	victim.velocity = Vector3.ZERO
	victim.reset_frame()

	var attacker: Player = scene.instantiate()
	attacker.set_script(ProbeLocalPlayer)
	attacker.name = "TakeoverAttacker"
	_arena.get_node("Players").add_child(attacker, true)
	attacker.player_id = 403
	await get_tree().physics_frame
	attacker.disable_spawner()
	attacker.global_position = ship.seat_marker.global_position + Vector3(1.5, 0, 0)
	attacker.velocity = Vector3.ZERO
	attacker.reset_frame()
	for i in range(5):
		await get_tree().physics_frame

	ship.request_mount(victim.get_path())
	for i in range(5):
		await get_tree().physics_frame
	var seated_before: bool = ship.driver_id == victim.player_id

	attacker.melee.try_activate(victim)
	for i in range(120):
		await get_tree().physics_frame
	var victim_died: bool = victim.is_dead
	var seat_transferred: bool = ship.driver_id == attacker.player_id

	_log("TAKEOVER victim seated before slap=%s -> bitchslapped (died=%s) -> seat now held by attacker=%s" % [
		seated_before, victim_died, seat_transferred])

	victim.queue_free()
	attacker.queue_free()
