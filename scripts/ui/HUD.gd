extends CanvasLayer

@onready var health_bar: ProgressBar = $Root/HealthPanel/HealthBar
@onready var health_label: Label = $Root/HealthPanel/HealthLabel
@onready var current_weapon_label: Label = $Root/WeaponPanel/CurrentWeaponLabel
@onready var weapon_list: VBoxContainer = $Root/WeaponPanel/WeaponList
@onready var kills_label: Label = $Root/KillsPanel/KillsLabel
@onready var scoreboard_panel: PanelContainer = $Root/ScoreboardPanel
@onready var score_scroll: ScrollContainer = $Root/ScoreboardPanel/ScoreboardVBox/ScoreScroll
@onready var score_list: VBoxContainer = $Root/ScoreboardPanel/ScoreboardVBox/ScoreScroll/ScoreList
@onready var charge_bar: ProgressBar = $Root/ChargePanel/ChargeBar
@onready var charge_panel: Control = $Root/ChargePanel
@onready var fps_label: Label = $Root/FpsLabel
@onready var spawn_aim_panel: Control = $Root/SpawnAimPanel
@onready var spawn_timer_label: Label = $Root/SpawnAimPanel/TimerLabel
@onready var lock_indicator: Control = $Root/LockIndicator
@onready var scope_overlay: ColorRect = $Root/ScopeOverlay
@onready var planet_threat_warning: Label = $Root/PlanetThreatWarning


var _my_player_id: int = -1
var _frame_count: int = 0
var _fps_timer: float = 0.0
var _threat_pulse_time: float = 0.0

func set_player_id(pid: int) -> void:
	_my_player_id = pid

func _process(delta: float) -> void:
	# FPS counter — update once per second
	_frame_count += 1
	_fps_timer += delta
	if _fps_timer >= 1.0:
		fps_label.text = "FPS: %d" % _frame_count
		_frame_count = 0
		_fps_timer = 0.0

	if planet_threat_warning.visible:
		# A fast alarm-red pulse rather than a static banner - the label
		# sitting still would read as any other UI panel, not a siren.
		_threat_pulse_time += delta
		var t: float = 0.55 + 0.45 * sin(_threat_pulse_time * 9.0)
		planet_threat_warning.modulate.a = t

## Full-screen railgun optic: transparent inside the lens, blurred and darkened
## outside it (see scenes/ui/scope.gdshader).
func update_scope(active: bool) -> void:
	if scope_overlay:
		scope_overlay.visible = active

func update_charge_bar(charge: float, visible_flag: bool) -> void:
	charge_panel.visible = visible_flag
	if visible_flag:
		charge_bar.value = clamp(charge, 0.0, 1.0)
		charge_bar.modulate = Color(0.4, 0.9, 1.0).lerp(Color(1.0, 1.0, 1.0), charge)

func update_kills(kills: int) -> void:
	kills_label.text = "Kills: %d" % kills

## Highlight the current player's row and scroll it into view.
func update_scoreboard(is_open: bool, entries: Array[Dictionary]) -> void:
	scoreboard_panel.visible = is_open
	if not is_open:
		return

	if score_list.get_child_count() != entries.size():
		for c in score_list.get_children():
			score_list.remove_child(c)
			c.queue_free()
		for _i in range(entries.size()):
			var row := HBoxContainer.new()
			var name_lbl := Label.new()
			name_lbl.name = "Name"
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_lbl.add_theme_font_size_override("font_size", 18)
			row.add_child(name_lbl)
			var score_lbl := Label.new()
			score_lbl.name = "Score"
			score_lbl.custom_minimum_size = Vector2(80, 0)
			score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			score_lbl.add_theme_font_size_override("font_size", 18)
			row.add_child(score_lbl)
			score_list.add_child(row)

	var my_row_y: float = 0.0
	var row_h: float = 26.0
	for i in range(entries.size()):
		var row: HBoxContainer = score_list.get_child(i)
		var name_lbl: Label = row.get_node("Name")
		var score_lbl: Label = row.get_node("Score")
		var entry: Dictionary = entries[i]
		var is_me: bool = (entry["player_id"] == _my_player_id)
		name_lbl.text = ("%s  ◀" if is_me else "%s") % str(entry["name"])
		score_lbl.text = str(entry["score"])
		row.modulate = Color(1.0, 1.0, 0.4, 1.0) if is_me else Color.WHITE
		if is_me:
			my_row_y = i * row_h

	# Scroll so the current player is always visible in the centre of the list
	await get_tree().process_frame
	score_scroll.scroll_vertical = int(max(0.0, my_row_y - score_scroll.size.y * 0.4))

func update_health(current: float, max_health: float) -> void:
	health_bar.max_value = max_health
	health_bar.value = current
	health_label.text = "%d / %d" % [int(round(current)), int(round(max_health))]
	var t: float = clamp(current / max(max_health, 1.0), 0.0, 1.0)
	health_bar.modulate = Color(1.0, 0.35, 0.3).lerp(Color(0.4, 0.95, 0.5), t)

func update_weapons(names: Array[String], colors: Array[Color], current_index: int) -> void:
	if weapon_list.get_child_count() != names.size():
		for c in weapon_list.get_children():
			weapon_list.remove_child(c)
			c.queue_free()
		for _i in range(names.size()):
			var lbl := Label.new()
			lbl.add_theme_font_size_override("font_size", 16)
			weapon_list.add_child(lbl)

	for i in range(names.size()):
		var lbl: Label = weapon_list.get_child(i)
		lbl.text = names[i]
		var is_current: bool = (i == current_index)
		lbl.modulate = colors[i] if is_current else Color(colors[i].r, colors[i].g, colors[i].b, 0.4)
		lbl.add_theme_font_size_override("font_size", 20 if is_current else 15)

	if current_index >= 0 and current_index < names.size():
		current_weapon_label.text = names[current_index]
		current_weapon_label.modulate = colors[current_index]
	else:
		current_weapon_label.text = "-"
		current_weapon_label.modulate = Color.WHITE

## Called by Spawner during the aim window.
func update_spawn_aim(candidate: OrbitalBody, timer: float, max_time: float) -> void:
	spawn_aim_panel.visible = true
	var remaining: float = max_time - timer
	spawn_timer_label.text = "Choose a planet: %.1fs" % remaining

## Called from Player each frame - shows lock-on state for Planet Buster.
func update_lock_indicator(candidate: OrbitalBody, locked: OrbitalBody, lock_progress: float) -> void:
	lock_indicator.visible = (candidate != null)
	if candidate == null:
		return
	lock_indicator.modulate = Color.GREEN if locked != null else Color(1.0, 0.6, 0.1)
	# The progress label reuses the lock_indicator's first Label child
	var lbl: Label = lock_indicator.get_node_or_null("Label")
	if lbl:
		lbl.text = "LOCKED" if locked != null else ("%.0f%%" % (lock_progress * 100))

func hide_spawn_aim() -> void:
	spawn_aim_panel.visible = false

## Called from Player each frame - shows the "PLANET DESTRUCTION IMMINENT"
## banner while this player's own current planet (Player.get_frame_body())
## has an inbound Planet Buster shell locked on (OrbitalBody.is_under_threat).
func update_planet_threat_warning(active: bool) -> void:
	if active == planet_threat_warning.visible:
		return
	planet_threat_warning.visible = active
	_threat_pulse_time = 0.0
