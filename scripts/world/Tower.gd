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

	# The ladder runs from just above the ground to the top floor's slab, so
	# stepping off the top rung puts you on the top floor.
	_add_ladder(shaft_centre, 0.2, tower_height - floor_height * 0.5, ladder_shaft)

	# Roof.
	_add_box(Vector3(0.0, tower_height + floor_thickness * 0.5, 0.0),
		Vector3(tower_width, floor_thickness, tower_width), _tint * 0.82)

	# Plinth sinking the flat base into the curved surface.
	_add_foundation(half, half)

func footprint_radius() -> float:
	return tower_width * 0.7072

func structure_height() -> float:
	return tower_height + floor_thickness
