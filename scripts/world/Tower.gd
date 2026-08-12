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
##   - an observation deck capping it: wider than the tower below, with a
##     waist-high parapet instead of full walls, so a defender can lean out
##     over the overhang and fire straight down at the planet surface - a
##     normal window only ever looked outward, never down.
##
## Interiors are hollow because every wall panel carries its own collision (see
## Building._add_box); a single tower-sized collision box would seal it shut.

@export var tower_height: float = 30.0    ## set by Arena = host planet's radius
@export var floor_count: int = 4          ## number of walkable floors
@export var tower_width: float = 7.0

## How much wider the observation deck is than the tower it caps.
const DECK_WIDEN: float = 1.6
## Tall enough to lean on and stop a player just walking off the edge, short
## enough to shoot over without needing a window cutout.
const PARAPET_HEIGHT: float = 1.1

func _build() -> void:
	floor_count = maxi(floor_count, 2)
	var floor_height: float = tower_height / float(floor_count)
	var half: float = tower_width * 0.5
	var ladder_shaft: float = minf(2.2, tower_width * 0.34)
	# The shaft sits in the +X/+Z corner, matching the hole
	# Building._add_slab_with_hole() leaves there.
	var shaft_centre := Vector2(half - ladder_shaft * 0.5, half - ladder_shaft * 0.5)

	# Enclosed floors only - the top storey is the open observation deck,
	# built separately below since it's a different shape entirely.
	for f in range(floor_count - 1):
		var y_base: float = f * floor_height

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
			if f == 0 and wi == 0:
				cut = Cutout.DOOR
			elif f > 0 and wi < 2:
				cut = Cutout.WINDOW
			_add_wall(w["centre"], tower_width, floor_height, w["axis"], cut)

		# A lamp per floor, offset away from the ladder shaft.
		_add_interior_light(Vector3(-half * 0.35, y_base + floor_height * 0.72, -half * 0.35),
			floor_height * 1.6, 1.8)

	_build_observation_deck(floor_height, half, shaft_centre, ladder_shaft)

	# The ladder runs from just above the ground to the deck's own slab, so
	# stepping off the top rung puts you on the deck.
	_add_ladder(shaft_centre, 0.2, tower_height - floor_height * 0.5, ladder_shaft)

	# Plinth sinking the flat base into the curved surface.
	_add_foundation(half, half)

## Wider than the tower it caps and open overhead - the widening is what
## clears a firing lane straight down past the tower's own base, which a
## same-width top floor with windows never could no matter how the windows
## were cut, since the tower's own walls were always directly underfoot.
func _build_observation_deck(floor_height: float, half: float, shaft_centre: Vector2, ladder_shaft: float) -> void:
	var deck_y: float = tower_height - floor_height
	var deck_half: float = half * DECK_WIDEN

	# Deck floor, wider than the tower. Building._add_slab_with_hole() always
	# cuts its hole at the slab's OWN +X/+Z corner, which is only right for
	# the tower's own (narrower) floors - the ladder shaft has to land at the
	# SAME xz on every level it passes through, so the deck needs its hole at
	# shaft_centre specifically, not at the wider deck's own corner.
	_add_deck_slab(deck_y, deck_half, shaft_centre, ladder_shaft)

	# Waist-high parapet around the perimeter instead of full walls.
	var rail_y: float = deck_y + floor_thickness * 0.5 + PARAPET_HEIGHT * 0.5
	var walls := [
		{"centre": Vector3(0.0, rail_y, deck_half), "axis": "x"},
		{"centre": Vector3(0.0, rail_y, -deck_half), "axis": "x"},
		{"centre": Vector3(deck_half, rail_y, 0.0), "axis": "z"},
		{"centre": Vector3(-deck_half, rail_y, 0.0), "axis": "z"},
	]
	for w in walls:
		_add_wall(w["centre"], deck_half * 2.0, PARAPET_HEIGHT, w["axis"], Cutout.NONE)

	# Corner posts under the deck's own corners (not the narrower tower's),
	# so the overhang reads as built out and braced rather than floating.
	# _add_box only ever authors axis-aligned (vertical) boxes - an actual
	# angled strut back to the tower isn't something this system can wrap
	# onto the sphere correctly, so straight-down posts are the honest option.
	var brace_height: float = floor_thickness * 2.0
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_add_box(Vector3(sx * deck_half * 0.86, deck_y - brace_height * 0.5, sz * deck_half * 0.86),
				Vector3(0.35, brace_height, 0.35), _tint * 0.8)

	_add_interior_light(Vector3(0.0, deck_y + floor_thickness * 0.5 + 1.6, 0.0), floor_height * 2.2, 2.0)
	_add_roof_flag(deck_y + floor_thickness * 0.5 + PARAPET_HEIGHT)

## Same two-rectangle hole trick as Building._add_slab_with_hole(), just
## generalised to four rectangles around an arbitrary hole centre instead of
## two around a corner - see the call site above for why the deck needs that.
func _add_deck_slab(y: float, deck_half: float, shaft_centre: Vector2, hole: float) -> void:
	var hx0: float = shaft_centre.x - hole * 0.5
	var hx1: float = shaft_centre.x + hole * 0.5
	var hz0: float = shaft_centre.y - hole * 0.5
	var hz1: float = shaft_centre.y + hole * 0.5
	# Left/right strips run the full Z depth; front/back strips fill the
	# remaining Z range directly above/below the hole, between them.
	_add_box(Vector3((-deck_half + hx0) * 0.5, y, 0.0),
		Vector3(hx0 + deck_half, floor_thickness, deck_half * 2.0), _tint * 0.92)
	_add_box(Vector3((hx1 + deck_half) * 0.5, y, 0.0),
		Vector3(deck_half - hx1, floor_thickness, deck_half * 2.0), _tint * 0.92)
	_add_box(Vector3(shaft_centre.x, y, (-deck_half + hz0) * 0.5),
		Vector3(hole, floor_thickness, hz0 + deck_half), _tint * 0.92)
	_add_box(Vector3(shaft_centre.x, y, (hz1 + deck_half) * 0.5),
		Vector3(hole, floor_thickness, deck_half - hz1), _tint * 0.92)

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

## Half-diagonal of the DECK, not the base - it's the wider of the two and the
## one that actually determines how close another structure/impact can get.
func footprint_radius() -> float:
	return tower_width * DECK_WIDEN * 0.7072

## Deck top (its slab plus the parapet standing on it), matching where
## _build_observation_deck() actually finishes now that there's no separate
## roof cap above it.
func structure_height() -> float:
	var floor_height: float = tower_height / float(maxi(floor_count, 2))
	return tower_height - floor_height + floor_thickness * 0.5 + PARAPET_HEIGHT
