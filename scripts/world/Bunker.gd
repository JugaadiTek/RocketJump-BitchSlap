class_name Bunker
extends Building
## A low, wide, single-storey strongpoint: doorways on two opposite sides so it
## can't be camped from one angle alone, and firing windows all round. Squat
## enough to fight over rather than from above, which makes it the close-quarters
## counterpart to Tower's height advantage.
##
## Small planets get these instead of towers, where a radius-tall tower would be
## a stub barely worth entering.

@export var bunker_width: float = 11.0
@export var bunker_depth: float = 8.0
@export var bunker_height: float = 4.0

func _build() -> void:
	var half_w: float = bunker_width * 0.5
	var half_d: float = bunker_depth * 0.5
	var mid_y: float = bunker_height * 0.5

	# Long sides: a doorway through one, a window through the other.
	_add_wall(Vector3(0.0, mid_y, half_d), bunker_width, bunker_height, "x", Cutout.DOOR)
	_add_wall(Vector3(0.0, mid_y, -half_d), bunker_width, bunker_height, "x", Cutout.DOOR)
	# Short sides: firing windows.
	_add_wall(Vector3(half_w, mid_y, 0.0), bunker_depth, bunker_height, "z", Cutout.WINDOW)
	_add_wall(Vector3(-half_w, mid_y, 0.0), bunker_depth, bunker_height, "z", Cutout.WINDOW)

	# Roof - solid, and a place to stand on if you can get up there.
	_add_box(Vector3(0.0, bunker_height + floor_thickness * 0.5, 0.0),
		Vector3(bunker_width + wall_thickness, floor_thickness, bunker_depth + wall_thickness),
		_tint * 0.82)

	# A waist-high block inside, so the interior itself has something to break
	# line of sight against rather than being one empty room.
	_add_box(Vector3(0.0, 0.6, 0.0), Vector3(bunker_width * 0.35, 1.2, bunker_depth * 0.3), _tint * 1.08)

	# Two lamps so the single room isn't lit from a single hard point.
	_add_interior_light(Vector3(-bunker_width * 0.28, bunker_height * 0.78, 0.0), bunker_width, 1.5)
	_add_interior_light(Vector3(bunker_width * 0.28, bunker_height * 0.78, 0.0), bunker_width, 1.5)

	# Plinth sinking the flat base into the curved surface.
	_add_foundation(bunker_width * 0.5, bunker_depth * 0.5)

func footprint_radius() -> float:
	return sqrt(bunker_width * bunker_width + bunker_depth * bunker_depth) * 0.5

func structure_height() -> float:
	return bunker_height + floor_thickness
