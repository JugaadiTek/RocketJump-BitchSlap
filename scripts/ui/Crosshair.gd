extends Control
## Simple custom-drawn "+" crosshair, always centered on screen. Deliberately
## not a texture so size/thickness/gap are cheap to tune from the editor.

@export var line_length: float = 9.0
@export var thickness: float = 2.0
@export var gap: float = 5.0
@export var color: Color = Color(1, 1, 1, 0.85)
@export var dot_radius: float = 1.5

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _draw() -> void:
	var center: Vector2 = size / 2.0
	draw_line(center + Vector2(0, -gap), center + Vector2(0, -gap - line_length), color, thickness)
	draw_line(center + Vector2(0, gap), center + Vector2(0, gap + line_length), color, thickness)
	draw_line(center + Vector2(-gap, 0), center + Vector2(-gap - line_length, 0), color, thickness)
	draw_line(center + Vector2(gap, 0), center + Vector2(gap + line_length, 0), color, thickness)
	if dot_radius > 0.0:
		draw_circle(center, dot_radius, color)
