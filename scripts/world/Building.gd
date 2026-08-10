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
## _add_box() also WRAPS each piece onto the planet. A building is authored flat,
## as if on a tangent plane, then every piece is remapped onto the sphere and
## tilted to the local normal (see _surface_transform). Pieces wide enough to
## visibly sag are split into segments first, so a floor slab follows the
## curvature instead of cutting a chord through it. On a small planet, where a
## building can span a serious fraction of the circumference, this is the
## difference between a structure that sits on the world and one that stabs
## through it.
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
## Radius of the planet this is standing on. Arena sets it before add_child();
## the foundation needs it to work out how far the surface falls away under the
## building's flat base.
@export var host_radius: float = 40.0

enum Cutout { NONE, DOOR, WINDOW }

## How far a piece may sag away from the true surface before it gets subdivided.
const CURVE_TOLERANCE: float = 0.25
## Cap on subdivision per axis, so a big slab on a tiny planet can't explode into
## hundreds of boxes.
const MAX_CURVE_SEGMENTS: int = 5

var _body: StaticBody3D
var _tint: Color = Color.WHITE
var _demolished: bool = false

func _ready() -> void:
	_body = StaticBody3D.new()
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	_tint = Color(randf_range(0.38, 0.72), randf_range(0.38, 0.72), randf_range(0.40, 0.75))
	_build()

func _build() -> void:
	pass # override

## Half the footprint's diagonal - how far the outermost corner reaches from the
## centre. Subclasses override; the foundation and Arena both need it.
func footprint_radius() -> float:
	return 4.0

## Fills the gap under a flat-based building sitting on a curved planet.
##
## The base plane is tangent to the sphere at the centre point, so the surface
## drops away toward the corners by the sagitta - which is why buildings looked
## like they were floating on their outer edges. A plinth extending that far
## below the base plane meets the surface at the corners and is buried
## everywhere else, so the building reads as sunk into the ground rather than
## perched on it. Stepped in two tiers so it looks deliberate.
func _add_foundation(half_x: float, half_z: float) -> void:
	var corner: float = sqrt(half_x * half_x + half_z * half_z)
	var sagitta: float = host_radius - sqrt(maxf(host_radius * host_radius - corner * corner, 0.0))
	var depth: float = sagitta + 0.6
	if depth <= 0.05:
		return
	# Outer tier: full footprint, reaching all the way down to the corner gap.
	_add_box(Vector3(0.0, -depth * 0.5, 0.0),
		Vector3(half_x * 2.0 + wall_thickness, depth, half_z * 2.0 + wall_thickness), _tint * 0.7)
	# Inner tier sits proud of it, giving the base a stepped plinth silhouette.
	_add_box(Vector3(0.0, -depth * 0.18, 0.0),
		Vector3(half_x * 2.3, depth * 0.36, half_z * 2.3), _tint * 0.78)

## Brings the building down. Called when the planet it stands on grinds against
## another planet's structures - the towers involved shear off rather than
## clipping through each other.
func demolish() -> void:
	if _demolished:
		return
	_demolished = true
	Sfx.play_3d("collapse", global_position, 1.0, 6.0)
	_spawn_rubble()
	# Collision first, so nothing is left standing invisibly in the way.
	for child in _body.get_children():
		child.queue_free()
	for child in get_children():
		if child is MeshInstance3D or child is OmniLight3D or child is Ladder:
			child.queue_free()

func is_demolished() -> bool:
	return _demolished

func _spawn_rubble() -> void:
	var debris := GPUParticles3D.new()
	add_child(debris)
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 75.0
	mat.initial_velocity_min = 4.0
	mat.initial_velocity_max = 18.0
	mat.gravity = Vector3(0, -6, 0)
	mat.scale_min = 0.3
	mat.scale_max = 1.4
	mat.angular_velocity_min = -220.0
	mat.angular_velocity_max = 220.0
	mat.color = _tint
	debris.process_material = mat
	debris.draw_pass_1 = BoxMesh.new()
	debris.amount = 90
	debris.lifetime = 3.5
	debris.one_shot = true
	debris.explosiveness = 0.9
	debris.emitting = true
	debris.local_coords = false

	# A flattened footprint left behind, so the site still reads as cover.
	var fp: float = footprint_radius() * 0.7
	_add_box(Vector3(0.0, 0.35, 0.0), Vector3(fp, 0.7, fp), _tint * 0.6)

## Tallest point above the surface, used to work out when two planets have
## brought their structures into contact (see GravityManager).
func structure_height() -> float:
	return 4.0

## One solid piece, wrapped onto the planet: split into as many segments as the
## curvature needs, each placed and tilted to sit on the real surface.
func _add_box(pos: Vector3, size: Vector3, color: Color, solid: bool = true) -> void:
	if size.x <= 0.01 or size.y <= 0.01 or size.z <= 0.01:
		return
	var segs_x: int = _segments_for(size.x)
	var segs_z: int = _segments_for(size.z)
	var step := Vector3(size.x / float(segs_x), size.y, size.z / float(segs_z))
	for ix in range(segs_x):
		for iz in range(segs_z):
			var offset := Vector3(
				(float(ix) + 0.5) * step.x - size.x * 0.5,
				0.0,
				(float(iz) + 0.5) * step.z - size.z * 0.5)
			_emit_piece(pos + offset, step, color, solid)

## How many segments a span of `extent` needs before its chord sits within
## CURVE_TOLERANCE of the real surface.
func _segments_for(extent: float) -> int:
	if host_radius <= 0.01 or extent <= 0.01:
		return 1
	for n in range(1, MAX_CURVE_SEGMENTS + 1):
		var half: float = extent / float(n) * 0.5
		if half >= host_radius:
			continue
		var sag: float = host_radius - sqrt(maxf(host_radius * host_radius - half * half, 0.0))
		if sag <= CURVE_TOLERANCE:
			return n
	return MAX_CURVE_SEGMENTS

func _emit_piece(pos: Vector3, size: Vector3, color: Color, solid: bool) -> void:
	var xform: Transform3D = _surface_transform(pos)
	var mi := MeshInstance3D.new()
	add_child(mi)
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	mi.material_override = mat
	mi.transform = xform
	if not solid:
		return
	var cshape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cshape.shape = box
	cshape.transform = xform
	_body.add_child(cshape)

## Maps a position authored on a flat tangent plane onto the actual sphere.
##
## The building's origin sits on the surface with +Y radially out, so the planet
## centre is at local (0, -host_radius, 0). A point `local_pos` is treated as
## "walk `arc` metres across the surface, then rise `y` metres" - the horizontal
## offset becomes an arc angle rather than a straight chord, and the piece is
## rotated so its own up matches the surface normal there.
func _surface_transform(local_pos: Vector3) -> Transform3D:
	var r: float = host_radius
	var flat := Vector3(local_pos.x, 0.0, local_pos.z)
	var arc: float = flat.length()
	if r <= 0.01 or arc < 0.0001:
		return Transform3D(Basis(), local_pos)
	var axis: Vector3 = Vector3.UP.cross(flat / arc)
	if axis.length_squared() < 0.000001:
		return Transform3D(Basis(), local_pos)
	axis = axis.normalized()
	var dir: Vector3 = Vector3.UP.rotated(axis, arc / r)
	var centre := Vector3(0.0, -r, 0.0)
	return Transform3D(Basis(Quaternion(Vector3.UP, dir)), centre + dir * (r + local_pos.y))

## Warm interior light. Buildings read as inhabited from outside and are
## actually navigable inside, rather than being black boxes you enter blind.
func _add_interior_light(pos: Vector3, range_m: float, energy: float = 1.6) -> void:
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.82, 0.55)
	lamp.light_energy = energy
	lamp.omni_range = range_m
	# Shadows off: a handful of these per building across a dozen buildings is
	# cheap only as long as none of them are casting.
	lamp.shadow_enabled = false
	lamp.transform = _surface_transform(pos)
	add_child(lamp)
	# A small emissive panel so the light source is visible, and so the windows
	# glow from outside the way the concept art's structures do.
	var bulb := MeshInstance3D.new()
	var bulb_mesh := BoxMesh.new()
	bulb_mesh.size = Vector3(0.35, 0.1, 0.35)
	bulb.mesh = bulb_mesh
	var bulb_mat := StandardMaterial3D.new()
	bulb_mat.albedo_color = Color(1.0, 0.9, 0.7)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1.0, 0.82, 0.55)
	bulb_mat.emission_energy_multiplier = 4.0
	bulb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bulb.material_override = bulb_mat
	bulb.transform = _surface_transform(pos)
	add_child(bulb)

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
