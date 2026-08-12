extends Node
## Micro-benchmarks for hot paths the PerfProbe mode matrix can't cleanly
## isolate on its own, because they're not "systems you can toggle off" -
## they're specific function calls that fire at a known real-world frequency.
## Each section times the call directly (Time.get_ticks_usec(), same pattern
## every other probe here uses) and extrapolates against that real frequency,
## so the number reported is "ms of budget this costs per second of actual
## play", comparable directly against a 16.67ms (60fps) or 8.33ms (120fps)
## frame budget.
##
## Run with a real renderer or headless - nothing here touches drawing.
## Run: Godot --headless --path . res://tests/AIProbe.tscn

const ARENA := preload("res://scenes/world/Arena.tscn")
const LOG_PATH := "/tmp/rjbs_ai.log"

var _arena: Node3D

func _log(line: String) -> void:
	print(line)
	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(LOG_PATH) else FileAccess.WRITE)
	if f:
		f.seek_end(); f.store_line(line); f.close()

func _ready() -> void:
	seed(20260811)
	_arena = ARENA.instantiate()
	_arena.bot_count = 31
	add_child(_arena)
	# Let bots spawn, choose a planet, fly in, and land - a cold-start scene
	# with everyone still teleporting in from the boundary would understate
	# the LOS raycast cost real mid-match positions produce.
	for i in range(600):
		await get_tree().physics_frame

	_bench_bot_los()
	_bench_gravity_calls()
	_bench_crater_vs_uncoalesced_deform()
	_bench_skull_texture()
	_bench_scoreboard_sort()
	get_tree().quit()

## Bot._find_enemy() - O(bots) candidates, each short-circuited by distance
## before the line-of-sight raycast, so real cost depends on how many
## candidates are actually closer than the current best guess. Timed against
## the real mid-match bot layout above, not a synthetic worst case.
func _bench_bot_los() -> void:
	var bots: Array = _arena.get_node("Bots").get_children()
	var live: Array = []
	for b in bots:
		if is_instance_valid(b) and not b.is_dead:
			live.append(b)
	if live.is_empty():
		_log("AI-LOS  no live bots to benchmark")
		return
	var reps: int = 20
	var t0: int = Time.get_ticks_usec()
	for r in range(reps):
		for b in live:
			b._find_enemy()
	var t1: int = Time.get_ticks_usec()
	var per_sweep_ms: float = (t1 - t0) / 1000.0 / float(reps)
	# Every bot re-targets independently on its own 0.25s timer, so a full
	# "every bot thinks once" sweep like this happens on average once per
	# 0.25s of match time.
	var ms_per_sec_of_play: float = per_sweep_ms / 0.25
	_log("AI-LOS  %d live bots: one full _find_enemy() sweep = %.3fms -> ~%.3fms/s of play (retarget every 0.25s)" % [
		live.size(), per_sweep_ms, ms_per_sec_of_play])

## GravityManager.get_gravity_at()/get_nearest_body() - called unconditionally
## every physics tick by every Player, every Asteroid, and every in-flight
## Projectile. Timed per-call, then extrapolated against a realistic
## concurrent caller count for a busy match.
func _bench_gravity_calls() -> void:
	var sample_pos: Vector3 = Vector3(30, 10, 20)
	var iterations: int = 200000
	var t0: int = Time.get_ticks_usec()
	for i in range(iterations):
		GravityManager.get_gravity_at(sample_pos)
	var t1: int = Time.get_ticks_usec()
	var gravity_us: float = float(t1 - t0) / float(iterations)

	t0 = Time.get_ticks_usec()
	for i in range(iterations):
		GravityManager.get_nearest_body(sample_pos)
	t1 = Time.get_ticks_usec()
	var nearest_us: float = float(t1 - t0) / float(iterations)

	var bodies: int = GravityManager.get_bodies().size()
	var players: int = _arena.get_node("Players").get_child_count() + _arena.get_node("Bots").get_child_count()
	var rocks: int = 0
	var field: Node = _arena.get_node_or_null("DebrisField")
	if field:
		rocks = field.get_child_count()
	# Every player calls get_gravity_at once and get_nearest_body one-to-a-few
	# times (planet frame pick + ground stick) per physics tick; every
	# asteroid calls get_gravity_at once per tick. Projectiles omitted here
	# (count varies second to second with fire rate) - this is the steady-state
	# floor, not the firefight peak.
	var calls_per_tick: int = players * 2 + rocks
	var ms_per_tick: float = calls_per_tick * ((gravity_us + nearest_us) * 0.5) / 1000.0
	_log("GRAVITY %d bodies: get_gravity_at=%.3fus/call  get_nearest_body=%.3fus/call" % [bodies, gravity_us, nearest_us])
	_log("GRAVITY steady-state floor: %d players + %d asteroids -> ~%d O(bodies) calls/tick -> ~%.3fms/tick (%.1fms/s at 60Hz)" % [
		players, rocks, calls_per_tick, ms_per_tick, ms_per_tick * 60.0])

## Rocket._deform_planet_mesh_if_hit() rebuilds the WHOLE planet ArrayMesh on
## every single hit, uncoalesced - unlike OrbitalBody.apply_crater(), which
## batches collider rebuilds on a 0.6s timer. Fires several rockets in a row
## at the same planet (a plausible rocket-jump-heavy firefight) to show the
## accumulated cost the coalescing on the crater path avoids.
func _bench_crater_vs_uncoalesced_deform() -> void:
	var body: OrbitalBody = _arena.get_node("OrbitalBodies/Verdant")
	var out := Vector3(0.3, 1.0, 0.2).normalized()
	var hit: Vector3 = body.global_position + out * body.radius

	var t0: int = Time.get_ticks_usec()
	body.apply_crater(hit, 6.0, 2.0)
	var t1: int = Time.get_ticks_usec()
	_log("DEFORM  OrbitalBody.apply_crater() single call = %.2fms (collider rebuild coalesced, not included here)" % [
		(t1 - t0) / 1000.0])

	# Simulate a burst of rocket hits landing close together, the way a
	# rocket-jump spam or point-blank splash fight would.
	var rocket_scene: PackedScene = load("res://scenes/weapons/Rocket.tscn")
	var rocket: Rocket = rocket_scene.instantiate()
	add_child(rocket)
	var collider: StaticBody3D = body.get_node("StaticBody3D")
	var hits: int = 8
	var per_hit_ms: Array[float] = []
	for i in range(hits):
		var p: Vector3 = hit + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
		var ta: int = Time.get_ticks_usec()
		rocket._deform_planet_mesh_if_hit(collider, p)
		var tb: int = Time.get_ticks_usec()
		per_hit_ms.append((tb - ta) / 1000.0)
	rocket.queue_free()
	var total: float = 0.0
	for v in per_hit_ms:
		total += v
	_log("DEFORM  Rocket._deform_planet_mesh_if_hit() x%d uncoalesced hits = [%s] total=%.2fms (each is a full ArrayMesh rebuild, no batching)" % [
		hits, ", ".join(per_hit_ms.map(func(v): return "%.2f" % v)), total])

## DeathEffect._skull_texture() bakes a fresh 96x96 image per call - unlike
## the analogous OrbitalBody/Asteroid bump/rock textures, it is NOT cached as
## a static var, so it re-pays the same cost on every single death. Timed
## alone, then for a burst of simultaneous deaths (plausible in a chaotic
## planet-buster or bitchslap-chain moment with several respawns landing
## close together).
func _bench_skull_texture() -> void:
	var effect := DeathEffect.new()
	add_child(effect)
	var t0: int = Time.get_ticks_usec()
	var tex: ImageTexture = effect._skull_texture()
	var t1: int = Time.get_ticks_usec()
	_log("SKULL   single _skull_texture() bake = %.3fms (%dx%d, uncached - static var would make every call after the first ~free)" % [
		(t1 - t0) / 1000.0, tex.get_width(), tex.get_height()])

	var burst: int = 8
	t0 = Time.get_ticks_usec()
	for i in range(burst):
		effect._skull_texture()
	t1 = Time.get_ticks_usec()
	_log("SKULL   %d simultaneous deaths' worth of skull bakes = %.3fms total (%.3fms/death)" % [
		burst, (t1 - t0) / 1000.0, (t1 - t0) / 1000.0 / float(burst)])
	effect.queue_free()

## MatchState.get_all_scores() does a full sort_custom over every registered
## player, called unconditionally every physics tick from the LOCAL human's
## own Player._physics_process HUD-update block (not once per player - once
## per second of the ONE local client's own tick rate), regardless of whether
## anything actually changed since the last call.
func _bench_scoreboard_sort() -> void:
	for i in range(32):
		MatchState.register_player(i, "Bot%02d" % i)
		MatchState.scores[i] = randi() % 20
	var iterations: int = 20000
	var t0: int = Time.get_ticks_usec()
	for i in range(iterations):
		MatchState.get_all_scores()
	var t1: int = Time.get_ticks_usec()
	var per_call_us: float = float(t1 - t0) / float(iterations)
	_log("SCOREBOARD get_all_scores() with %d players = %.3fus/call -> %.4fms/s at 60Hz (called every physics tick regardless of change)" % [
		MatchState.registered_players.size(), per_call_us, per_call_us * 60.0 / 1000.0])
	for i in range(32):
		MatchState.unregister_player(i)
	MatchState.reset_scores()
