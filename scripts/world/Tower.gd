class_name Tower
extends Building
## A multi-storey tower planted on a planet's surface, as tall as the planet's
## own radius (Arena sets tower_height = body.radius), so bigger worlds get
## proportionally bigger landmarks.
##
## Layout, ground up:
##   - ground floor with a doorway on one side, open to the planet surface
##   - intermediate floors, each a slab with a corner opening for the ladder,
##     and a firing window on two sides for cover mid-climb
##   - a ladder running the full height through those corner openings
##   - a top floor with windows on all four sides to shoot out of
##   - a solid roof capping it
##
## Interiors are hollow because every wall panel carries its own collision (see
## Building._add_box); a single tower-sized collision box would seal it shut.

@export var tower_height: float = 30.0    ## set by Arena = host planet's radius
@export var floor_count: int = 4          ## number of walkable floors
@export var tower_width: float = 7.0

func _build() -> void:
	floor_count = maxi(floor_count, 2)
	var floor_height: float = tower_height / float(floor_count)
	var half: float = tower_width * 0.5
	var ladder_shaft: float = minf(2.2, tower_width * 0.34)
	# The shaft sits in the +X/+Z corner, matching the hole
	# Building._add_slab_with_hole() leaves there.
	var shaft_centre := Vector2(half - ladder_shaft * 0.5, half - ladder_shaft * 0.5)

	for f in range(floor_count):
		var y_base: float = f * floor_height
		var is_top: bool = (f == floor_count - 1)

		# Slab underfoot for every floor above the ground (the planet surface
		# serves as the ground floor's own footing).
		if f > 0:
			_add_slab_with_hole(y_base, half, ladder_shaft)

		# Four walls. Wall i alternates between running along X and along Z.
		var mid_y: float = y_base + floor_height * 0.5
		var walls := [
			{"centre": Vector3(0.0, mid_y, half), "axis": "x"},
			{"centre": Vector3(0.0, mid_y, -half), "axis": "x"},
			{"centre": Vector3(half, mid_y, 0.0), "axis": "z"},
			{"centre": Vector3(-half, mid_y, 0.0), "axis": "z"},
		]
		for wi in range(walls.size()):
			var w: Dictionary = walls[wi]
			var cut: Cutout = Cutout.NONE
			if is_top:
				# Top floor: windows all round, the firing position the ladder
				# exists to reach.
				cut = Cutout.WINDOW
			elif f == 0 and wi == 0:
				cut = Cutout.DOOR
			elif f > 0 and wi < 2:
				cut = Cutout.WINDOW
			_add_wall(w["centre"], tower_width, floor_height, w["axis"], cut)

		# A lamp per floor, offset away from the ladder shaft.
		_add_interior_light(Vector3(-half * 0.35, y_base + floor_height * 0.72, -half * 0.35),
			floor_height * 1.6, 1.8)

	# The ladder runs from just above the ground to the top floor's slab, so
	# stepping off the top rung puts you on the top floor.
	_add_ladder(shaft_centre, 0.2, tower_height - floor_height * 0.5, ladder_shaft)

	# Roof.
	_add_box(Vector3(0.0, tower_height + floor_thickness * 0.5, 0.0),
		Vector3(tower_width, floor_thickness, tower_width), _tint * 0.82)

	_add_roof_flag(tower_height + floor_thickness)

	# Plinth sinking the flat base into the curved surface.
	_add_foundation(half, half)

## Mast and pennant on the roof - the silhouette detail that makes a planet's
## skyline read as occupied at a distance.
func _add_roof_flag(base_y: float) -> void:
	var mast_height: float = clampf(tower_height * 0.22, 1.6, 4.5)
	_add_box(Vector3(0.0, base_y + mast_height * 0.5, 0.0),
		Vector3(0.12, mast_height, 0.12), Color(0.7, 0.7, 0.75), false)
	var flag := MeshInstance3D.new()
	var flag_mesh := BoxMesh.new()
	flag_mesh.size = Vector3(mast_height * 0.55, mast_height * 0.32, 0.05)
	flag.mesh = flag_mesh
	var flag_mat := StandardMaterial3D.new()
	var flag_color := Color(0.85, 0.12, 0.16) if randf() < 0.6 else Color(0.15, 0.4, 0.9)
	flag_mat.albedo_color = flag_color
	flag_mat.emission_enabled = true
	flag_mat.emission = flag_color
	flag_mat.emission_energy_multiplier = 0.8
	flag_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	flag.material_override = flag_mat
	flag.transform = _surface_transform(Vector3(mast_height * 0.32, base_y + mast_height * 0.82, 0.0))
	add_child(flag)

func footprint_radius() -> float:
	return tower_width * 0.7072

func structure_height() -> float:
	return tower_height + floor_thickness
