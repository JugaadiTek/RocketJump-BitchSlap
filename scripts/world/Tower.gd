extends Node3D
## A tower planted on a planet's surface. Height is set by Arena to match
## the host planet's radius (so taller planets get taller towers). The tower
## is made of stacked BoxMesh floors with open doorways at each level so
## players can walk inside and use it for cover or height advantage.
##
## The whole tower is a child of its OrbitalBody, so it orbits with the
## planet automatically, and its local +Y points radially outward (the
## planet surface "up"), which Arena._place_buildings() sets up.

@export var tower_height: float = 30.0    ## set by Arena = planet.radius
@export var floor_count: int = 4          ## number of walkable floors
@export var tower_width: float = 6.0
@export var wall_thickness: float = 0.6
@export var floor_thickness: float = 0.5
@export var doorway_width: float = 3.0
@export var doorway_height: float = 3.5
@export var window_size: float = 2.0

func _ready() -> void:
	_build_tower()

func _build_tower() -> void:
	var floor_height: float = tower_height / float(floor_count)
	# Random tint so each tower looks slightly different
	var tower_color := Color(
		randf_range(0.4, 0.75),
		randf_range(0.4, 0.75),
		randf_range(0.4, 0.75)
	)

	for f in range(floor_count):
		var y_base: float = f * floor_height

		# Floor slab
		if f > 0:
			_add_box(Vector3(0, y_base, 0),
				Vector3(tower_width, floor_thickness, tower_width),
				tower_color)

		# Four walls — each has either a doorway cutout (ground floor, one
		# side) or a window hole cut procedurally via two taller segments.
		var walls: Array[Dictionary] = [
			{"pos": Vector3(0, 0, tower_width * 0.5), "size": Vector3(tower_width, floor_height, wall_thickness), "axis": "z"},
			{"pos": Vector3(0, 0, -tower_width * 0.5), "size": Vector3(tower_width, floor_height, wall_thickness), "axis": "z"},
			{"pos": Vector3(tower_width * 0.5, 0, 0), "size": Vector3(wall_thickness, floor_height, tower_width), "axis": "x"},
			{"pos": Vector3(-tower_width * 0.5, 0, 0), "size": Vector3(wall_thickness, floor_height, tower_width), "axis": "x"},
		]
		for wi in range(walls.size()):
			var w: Dictionary = walls[wi]
			var wpos: Vector3 = w["pos"] + Vector3(0, y_base + floor_height * 0.5, 0)
			var wsize: Vector3 = w["size"]
			var has_doorway: bool = (f == 0 and wi == 0)
			var has_window: bool = (f > 0 and wi == wi % 2)
			if has_doorway:
				_add_doorway_wall(wpos, wsize, tower_color, w["axis"])
			elif has_window:
				_add_window_wall(wpos, wsize, tower_color, w["axis"])
			else:
				_add_box(wpos, wsize, tower_color)

	# Roof
	_add_box(Vector3(0, tower_height + floor_thickness * 0.5, 0),
		Vector3(tower_width, floor_thickness, tower_width),
		tower_color * 0.85)

	# Collision for each floor platform (players can stand on them)
	for f in range(1, floor_count + 1):
		var platform := StaticBody3D.new()
		add_child(platform)
		var cshape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(tower_width - wall_thickness * 2.0, floor_thickness, tower_width - wall_thickness * 2.0)
		cshape.shape = box
		platform.add_child(cshape)
		platform.position = Vector3(0, f * floor_height, 0)
		platform.collision_layer = 1

	# Exterior StaticBody so projectiles/players collide with the tower shell
	var ext_body := StaticBody3D.new()
	add_child(ext_body)
	ext_body.collision_layer = 1
	var ext_shape := CollisionShape3D.new()
	var ext_box := BoxShape3D.new()
	ext_box.size = Vector3(tower_width, tower_height, tower_width)
	ext_shape.shape = ext_box
	ext_body.add_child(ext_shape)
	ext_body.position = Vector3(0, tower_height * 0.5, 0)

func _add_box(pos: Vector3, size: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	add_child(mi)
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	mi.material_override = mat
	mi.position = pos

func _add_doorway_wall(center: Vector3, full_size: Vector3, color: Color, axis: String) -> void:
	var side_w: float = (full_size.x if axis == "z" else full_size.z)
	var half_gap: float = doorway_width * 0.5
	var segment_w: float = (side_w - doorway_width) * 0.5
	if segment_w < 0.05:
		_add_box(center, full_size, color)
		return
	var above_h: float = full_size.y - doorway_height
	if above_h > 0.05:
		var above_pos: Vector3 = center + Vector3(0, (full_size.y - above_h) * 0.5, 0)
		var above_sz: Vector3 = Vector3(full_size.x if axis == "z" else doorway_width, above_h, full_size.z if axis == "x" else doorway_width)
		_add_box(above_pos, above_sz, color)
	var left_offset: float = -(half_gap + segment_w * 0.5)
	var right_offset: float = (half_gap + segment_w * 0.5)
	for offset in [left_offset, right_offset]:
		var seg_pos: Vector3 = center + (Vector3(offset, 0, 0) if axis == "z" else Vector3(0, 0, offset))
		seg_pos.y -= (full_size.y - doorway_height) * 0.5
		var seg_sz: Vector3 = Vector3(segment_w, doorway_height, full_size.z) if axis == "z" else Vector3(full_size.x, doorway_height, segment_w)
		_add_box(seg_pos, seg_sz, color)

func _add_window_wall(center: Vector3, full_size: Vector3, color: Color, axis: String) -> void:
	var below_h: float = (full_size.y - window_size) * 0.5
	if below_h < 0.05:
		_add_box(center, full_size, color)
		return
	var side_w: float = full_size.x if axis == "z" else full_size.z
	var frame_w: float = (side_w - window_size) * 0.5
	# Bottom strip
	_add_box(center + Vector3(0, -(full_size.y * 0.5 - below_h * 0.5), 0),
		Vector3(full_size.x, below_h, full_size.z), color)
	# Top strip
	_add_box(center + Vector3(0, (full_size.y * 0.5 - below_h * 0.5), 0),
		Vector3(full_size.x, below_h, full_size.z), color)
	# Side strips around window
	for s in [-1, 1]:
		var side_offset: float = (window_size * 0.5 + frame_w * 0.5) * s
		var sp: Vector3 = center + (Vector3(side_offset, 0, 0) if axis == "z" else Vector3(0, 0, side_offset))
		var ss: Vector3 = Vector3(frame_w, window_size, full_size.z) if axis == "z" else Vector3(full_size.x, window_size, frame_w)
		_add_box(sp, ss, color)
