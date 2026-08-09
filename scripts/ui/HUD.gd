extends CanvasLayer
## Local-only HUD, instantiated by Player.gd for the authority player only.
## Player._physics_process() pushes updates in every frame; see
## update_health() / update_weapons().

@onready var health_bar: ProgressBar = $Root/HealthPanel/HealthBar
@onready var health_label: Label = $Root/HealthPanel/HealthLabel
@onready var current_weapon_label: Label = $Root/WeaponPanel/CurrentWeaponLabel
@onready var weapon_list: VBoxContainer = $Root/WeaponPanel/WeaponList
@onready var kills_label: Label = $Root/KillsPanel/KillsLabel
@onready var scoreboard_panel: PanelContainer = $Root/ScoreboardPanel
@onready var score_list: VBoxContainer = $Root/ScoreboardPanel/ScoreboardVBox/ScoreList
@onready var charge_bar: ProgressBar = $Root/ChargePanel/ChargeBar
@onready var charge_panel: Control = $Root/ChargePanel

func update_charge_bar(charge: float, visible_flag: bool) -> void:
	charge_panel.visible = visible_flag
	if visible_flag:
		charge_bar.value = clamp(charge, 0.0, 1.0)
		# Cyan at low charge, white at full — matches railgun beam color
		charge_bar.modulate = Color(0.4, 0.9, 1.0).lerp(Color(1.0, 1.0, 1.0), charge)

func update_kills(kills: int) -> void:
	kills_label.text = "Kills: %d" % kills

## `entries` is MatchState.get_all_scores(): Array[{player_id, name, score}],
## already sorted highest-first.
func update_scoreboard(is_open: bool, entries: Array[Dictionary]) -> void:
	scoreboard_panel.visible = is_open
	if not is_open:
		return

	if score_list.get_child_count() != entries.size():
		for c in score_list.get_children():
			score_list.remove_child(c)
			c.queue_free()
		for i in range(entries.size()):
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

	for i in range(entries.size()):
		var row: HBoxContainer = score_list.get_child(i)
		var name_lbl: Label = row.get_node("Name")
		var score_lbl: Label = row.get_node("Score")
		name_lbl.text = str(entries[i]["name"])
		score_lbl.text = str(entries[i]["score"])

func update_health(current: float, max_health: float) -> void:
	health_bar.max_value = max_health
	health_bar.value = current
	health_label.text = "%d / %d" % [int(round(current)), int(round(max_health))]
	# Flash red-ish as health drops so damage is felt without a separate popup system.
	var t: float = clamp(current / max(max_health, 1.0), 0.0, 1.0)
	health_bar.modulate = Color(1.0, 0.35, 0.3).lerp(Color(0.4, 0.95, 0.5), t)

func update_weapons(names: Array[String], colors: Array[Color], current_index: int) -> void:
	if weapon_list.get_child_count() != names.size():
		for c in weapon_list.get_children():
			weapon_list.remove_child(c)
			c.queue_free()
		for i in range(names.size()):
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
