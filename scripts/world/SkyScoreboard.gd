class_name SkyScoreboard
extends Node3D
## A live scoreboard rendered far up the solar system's vertical (+Y) axis
## from OrbitCenter, well outside GravityManager.ARENA_BOUNDARY_RADIUS so it
## never interacts with gravity/boundary logic - visible from anywhere in the
## arena as a landmark in the sky, not something you fly out to read up close.
##
## A sky SHADER can't practically render dynamic text (see the design notes
## this was scoped from), so this is a SubViewport rendering an ordinary
## Control scoreboard, sampled onto a billboarded unshaded quad instead -
## the same "render UI to a viewport, show it in 3D" trick, just aimed
## outward instead of at the player's own HUD.

@export var panel_pixel_size: Vector2i = Vector2i(900, 640)
## World-space size of the quad the viewport texture is painted onto.
@export var world_size: Vector2 = Vector2(110.0, 78.0)
@export var update_interval: float = 0.5

var _viewport: SubViewport
var _rows_label: Label
var _timer: float = 0.0

func _ready() -> void:
	_build()
	MatchState.score_changed.connect(_on_score_changed)
	_refresh()

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= update_interval:
		_timer = 0.0
		_refresh()

func _on_score_changed(_player_id: int, _new_score: int) -> void:
	_refresh()

func _build() -> void:
	_viewport = SubViewport.new()
	_viewport.size = panel_pixel_size
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.07, 0.82)
	bg.size = Vector2(panel_pixel_size)
	_viewport.add_child(bg)

	var margin := MarginContainer.new()
	margin.size = Vector2(panel_pixel_size)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	_viewport.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "SCOREBOARD"
	title.add_theme_font_size_override("font_size", 52)
	title.modulate = Color(1.0, 0.85, 0.3)
	vbox.add_child(title)

	_rows_label = Label.new()
	_rows_label.add_theme_font_size_override("font_size", 34)
	vbox.add_child(_rows_label)

	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = world_size
	quad.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _viewport.get_texture()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material_override = mat
	add_child(quad)

func _refresh() -> void:
	if _rows_label == null:
		return
	var entries: Array[Dictionary] = MatchState.get_all_scores()
	if entries.is_empty():
		_rows_label.text = "(no scores yet)"
		return
	var lines: Array[String] = []
	for i in range(entries.size()):
		var e: Dictionary = entries[i]
		lines.append("%2d. %-16s %d" % [i + 1, str(e["name"]), int(e["score"])])
	_rows_label.text = "\n".join(lines)
