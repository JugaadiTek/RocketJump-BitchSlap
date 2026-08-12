class_name Turret
extends Building
## A small firing platform raised on four stilt legs, reached by a short
## flight of steps rather than a ladder - a third silhouette alongside
## Tower (tall, multi-storey, roofed) and Bunker (squat, sealed, ground
## level): short, exposed, and quick to clear. No interior, no ladder - the
## platform itself IS the whole structure.

@export var platform_width: float = 6.0
@export var leg_height: float = 3.0

func _build() -> void:
	var half: float = platform_width * 0.5

	_add_box(Vector3(0.0, leg_height, 0.0),
		Vector3(platform_width, floor_thickness, platform_width), _tint * 0.92)

	# Four corner legs, pulled in slightly from the platform's own edge so
	# they read as supports rather than posts hanging off the corners.
	var leg_half: float = half - 0.4
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_add_box(Vector3(sx * leg_half, leg_height * 0.5, sz * leg_half),
				Vector3(0.5, leg_height, 0.5), _tint * 0.78)

	# Low rail on three sides; the fourth is left open for the steps up.
	var rail_h: float = 1.0
	var rail_y: float = leg_height + floor_thickness * 0.5 + rail_h * 0.5
	_add_wall(Vector3(0.0, rail_y, half), platform_width, rail_h, "x", Cutout.NONE)
	_add_wall(Vector3(half, rail_y, 0.0), platform_width, rail_h, "z", Cutout.NONE)
	_add_wall(Vector3(-half, rail_y, 0.0), platform_width, rail_h, "z", Cutout.NONE)

	_add_steps(-half, leg_height, platform_width * 0.6)
	_add_interior_light(Vector3(0.0, leg_height + 1.6, 0.0), platform_width * 2.5, 1.8)

## A stepped climb rather than a smooth ramp - _add_box only ever authors
## axis-aligned boxes (see Building._append_box), so a sloped surface isn't
## something this system can draw; stacked steps are the honest option, same
## call Tower.gd's corner braces make for the same reason.
func _add_steps(edge_z: float, total_height: float, width: float) -> void:
	var steps: int = maxi(int(total_height / 0.5), 3)
	var step_h: float = total_height / float(steps)
	var step_depth: float = 0.7
	for i in range(steps):
		var y: float = step_h * (float(i) + 0.5)
		var z: float = edge_z - step_depth * (float(steps - i) - 0.5)
		_add_box(Vector3(0.0, y, z), Vector3(width, step_h, step_depth), _tint * 0.85)

## Platform half-diagonal plus the run of the steps out in front of it.
func footprint_radius() -> float:
	return platform_width * 0.7072 + 2.0

func structure_height() -> float:
	return leg_height + floor_thickness + 1.0
