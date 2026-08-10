extends Node
## Times each phase of Arena construction. Everything in this arena is generated
## procedurally at load - planets baked to faceted meshes, buildings welded from
## boxes, asteroids built one node at a time - so scene-entry cost is where the
## work actually lands, not the steady-state frame.

const ARENA := preload("res://scenes/world/Arena.tscn")
const LOG_PATH := "/tmp/rjbs_load.log"

func _log(line: String) -> void:
	print(line)
	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(LOG_PATH) else FileAccess.WRITE)
	if f:
		f.seek_end(); f.store_line(line); f.close()

func _ready() -> void:
	seed(20260811)
	var t0: int = Time.get_ticks_usec()
	var arena: Node3D = ARENA.instantiate()
	var t_inst: int = Time.get_ticks_usec()
	add_child(arena)
	var t_ready: int = Time.get_ticks_usec()
	await get_tree().process_frame
	await get_tree().process_frame
	var t_first: int = Time.get_ticks_usec()

	_log("LOAD    instantiate=%.0fms  _ready (build everything)=%.0fms  first frames=%.0fms  TOTAL=%.0fms" % [
		(t_inst - t0) / 1000.0, (t_ready - t_inst) / 1000.0,
		(t_first - t_ready) / 1000.0, (t_first - t0) / 1000.0])

	# Cost of the per-impact collider rebuild, which runs in GDScript.
	var body: OrbitalBody = arena.get_node("OrbitalBodies/Verdant")
	var out := Vector3(0.3, 1.0, 0.2).normalized()
	var t1: int = Time.get_ticks_usec()
	body.apply_crater(body.global_position + out * body.radius, 8.0, 3.0)
	var t2: int = Time.get_ticks_usec()
	body._rebuild_collider()
	var t3: int = Time.get_ticks_usec()
	var tris: int = body.mesh.mesh.get_faces().size() / 3
	_log("CRATER  mesh deform+normals=%.1fms  collider rebuild=%.1fms  (%d triangles per planet)" % [
		(t2 - t1) / 1000.0, (t3 - t2) / 1000.0, tris])

	# One building, rebuilt in isolation.
	var tower := Tower.new()
	tower.tower_height = 30.0
	tower.floor_count = 3
	tower.tower_width = 8.0
	tower.host_radius = 30.0
	var t4: int = Time.get_ticks_usec()
	add_child(tower)
	var t5: int = Time.get_ticks_usec()
	_log("BUILD   one tower=%.1fms  (13 buildings ~= %.0fms of load)" % [
		(t5 - t4) / 1000.0, (t5 - t4) / 1000.0 * 13.0])
	get_tree().quit()
