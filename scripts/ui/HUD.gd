extends CanvasLayer
## Local-only HUD, instantiated by Player.gd for the authority player only.
## Player._physics_process() pushes updates in every frame; see
## update_health() / update_weapons().

@onready var health_bar: ProgressBar = $Root/HealthPanel/HealthBar
@onready var health_label: Label = $Root/HealthPanel/HealthLabel
@onready var current_weapon_label: Label = $Root/WeaponPanel/CurrentWeaponLabel
@onready var weapon_list: VBoxContainer = $Root/WeaponPanel/WeaponList

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
