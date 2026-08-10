class_name Building
extends Node3D
## Shared construction kit for the structures Arena scatters over each planet.
##
## A building is a child of its OrbitalBody, so it orbits and spins with the
## planet for free, and its local +Y points radially outward (the planet's "up"
## at that spot) - Arena._build_buildings() sets that basis up.
##
## Every solid piece goes through _add_box(), which adds a mesh AND a matching
## collision box to one shared StaticBody3D. That is what makes interiors
## enterable: a single body-sized collision box would fill the inside, so walls
## have to be collided with individually.
##
## Subclasses override _build(). Set exported properties BEFORE add_child() -
## add_child() runs _ready() synchronously, and _ready() builds the geometry, so
## anything assigned afterwards is silently ignored.

@export var wall_thickness: float = 0.5
@export var floor_thickness: float = 0.45
@export var doorway_width: float = 3.0
@export var doorway_height: float = 3.2
@export var window_width: float = 2.4
@export var window_height: float = 1.8
@export var window_sill: float = 1.1  ## height of the window opening's lower edge

enum Cutout { NONE, DOOR, WINDOW }

var _body: StaticBody3D
var _tint: Color = Color.WHITE

func _ready() -> void:
	_body = StaticBody3D.new()
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	_tint = Color(randf_range(0.38, 0.72), randf_range(0.38, 0.72), randf_range(0.40, 0.75))
	_build()

func _build() -> void:
	pass # override

## One solid piece: a visible box plus matching collision on the shared body.
func _add_box(pos: Vector3, size: Vector3, color: Color, solid: bool = true) -> void:
	if size.x <= 0.01 or size.y <= 0.01 or size.z <= 0.01:
		return
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
	if not solid:
		return
	var cshape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cshape.shape = box
	cshape.position = pos
	_body.add_child(cshape)

## A wall panel spanning `span` metres horizontally, `height` tall, centred on
## `center`. `axis` is the axis the wall RUNS ALONG ("x" or "z"); its thickness
## lies on the other one. A cutout is assembled from solid pieces around the
## hole rather than subtracted, since box collision can't have holes.
func _add_wall(center: Vector3, span: float, height: float, axis: String, cutout: Cutout) -> void:
	match cutout:
		Cutout.DOOR:
			var door_w: float = minf(doorway_width, span - wall_thickness * 2.0)
			var door_h: float = minf(doorway_height, height - 0.2)
			if door_w <= 0.2 or door_h <= 0.2:
				_wall_piece(center, span, height, axis, 0.0, 0.0)
				return
			var jamb: float = (span - door_w) * 0.5
			_wall_piece(center, jamb, door_h, axis, -(door_w + jamb) * 0.5, (door_h - height) * 0.5)
			_wall_piece(center, jamb, door_h, axis, (door_w + jamb) * 0.5, (door_h - height) * 0.5)
			_wall_piece(center, span, height - door_h, axis, 0.0, door_h * 0.5)
		Cutout.WINDOW:
			var win_w: float = minf(window_width, span - wall_thickness * 2.0)
			var win_h: float = minf(window_height, height - 0.4)
			var sill: float = clampf(window_sill, 0.1, height - win_h - 0.1)
			if win_w <= 0.2 or win_h <= 0.2:
				_wall_piece(center, span, height, axis, 0.0, 0.0)
				return
			var header: float = height - sill - win_h
			var pier: float = (span - win_w) * 0.5
			# Below the opening, above it, then the piers either side.
			_wall_piece(center, span, sill, axis, 0.0, (sill - height) * 0.5)
			_wall_piece(center, span, header, axis, 0.0, (height - header) * 0.5)
			var mid_v: float = sill + win_h * 0.5 - height * 0.5
			_wall_piece(center, pier, win_h, axis, -(win_w + pier) * 0.5, mid_v)
			_wall_piece(center, pier, win_h, axis, (win_w + pier) * 0.5, mid_v)
		_:
			_wall_piece(center, span, height, axis, 0.0, 0.0)

func _wall_piece(center: Vector3, span: float, height: float, axis: String, h_offset: float, v_offset: float) -> void:
	if span <= 0.01 or height <= 0.01:
		return
	var size: Vector3 = Vector3(span, height, wall_thickness) if axis == "x" else Vector3(wall_thickness, height, span)
	var offset: Vector3 = Vector3(h_offset, v_offset, 0.0) if axis == "x" else Vector3(0.0, v_offset, h_offset)
	_add_box(center + offset, size, _tint)

## A floor slab with a square opening in its +X/+Z corner for the ladder shaft
## to pass through. Assembled from two rectangles, which is the fewest boxes
## that leaves exactly that corner open.
func _add_slab_with_hole(y: float, half: float, hole: float) -> void:
	var main_span: float = (half * 2.0) - hole
	if main_span <= 0.01:
		_add_box(Vector3(0, y, 0), Vector3(half * 2.0, floor_thickness, half * 2.0), _tint * 0.92)
		return
	# Strip covering everything left of the hole column.
	_add_box(Vector3(-half + main_span * 0.5, y, 0.0),
		Vector3(main_span, floor_thickness, half * 2.0), _tint * 0.92)
	# The rest of the hole's column, minus the hole itself.
	_add_box(Vector3(half - hole * 0.5, y, -half + main_span * 0.5),
		Vector3(hole, floor_thickness, main_span), _tint * 0.92)

## Rungs plus the climb volume that Player switches to ladder movement inside.
## `xz` is the shaft centre in local space; the climb runs from `from_y` to
## `to_y` along local +Y.
func _add_ladder(xz: Vector2, from_y: float, to_y: float, shaft: float) -> void:
	var height: float = to_y - from_y
	if height <= 0.1:
		return
	var rung_color: Color = Color(0.75, 0.62, 0.3)
	# Rails and rungs are cosmetic only - climbing is driven by the Ladder area,
	# and solid rungs would just snag the player against the shaft wall.
	var rail_offset: float = shaft * 0.28
	for side in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		add_child(rail)
		var rail_mesh := BoxMesh.new()
		rail_mesh.size = Vector3(0.09, height, 0.09)
		rail.mesh = rail_mesh
		var rail_mat := StandardMaterial3D.new()
		rail_mat.albedo_color = rung_color
		rail.material_override = rail_mat
		rail.position = Vector3(xz.x + rail_offset * side, from_y + height * 0.5, xz.y)
	var rung_count: int = int(height / 0.4)
	for i in range(rung_count):
		var rung := MeshInstance3D.new()
		add_child(rung)
		var rung_mesh := BoxMesh.new()
		rung_mesh.size = Vector3(rail_offset * 2.0, 0.06, 0.06)
		rung.mesh = rung_mesh
		var rung_mat := StandardMaterial3D.new()
		rung_mat.albedo_color = rung_color
		rung.material_override = rung_mat
		rung.position = Vector3(xz.x, from_y + 0.4 * float(i) + 0.2, xz.y)

	var zone := Ladder.new()
	add_child(zone)
	var zshape := CollisionShape3D.new()
	var zbox := BoxShape3D.new()
	zbox.size = Vector3(shaft * 0.9, height, shaft * 0.9)
	zshape.shape = zbox
	zone.add_child(zshape)
	zone.position = Vector3(xz.x, from_y + height * 0.5, xz.y)
