extends Area3D
## Sits on a planet's surface. Empty most of a match; becomes available on a
## long timer and grants a weapon (WeaponManager.grant_weapon's id - defaults
## to the Planet Buster, this script's original and only use, but any other
## pickup-only weapon reuses the exact same scene/script with `weapon_id`
## overridden - see BlackHoleGunPickup.tscn/BramblesLauncherPickup.tscn).

@export var weapon_id: String = "planetbuster"
@export var respawn_time: float = 180.0
@export_group("First availability")
@export var initial_delay: float = 60.0

@onready var visual: Node3D = $Visual

var _available: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_set_available(false)
	await get_tree().create_timer(initial_delay).timeout
	_set_available(true)

func _on_body_entered(body: Node3D) -> void:
	if not _available:
		return
	if body.has_method("grant_weapon") and body.is_multiplayer_authority():
		body.grant_weapon(weapon_id)
		_set_available(false)
		await get_tree().create_timer(respawn_time).timeout
		_set_available(true)

func _set_available(value: bool) -> void:
	_available = value
	if visual:
		visual.visible = value
	# Deferred: _set_available() is reached from inside the body_entered
	# signal, and Area3D refuses a direct write to `monitoring` while it is
	# mid-dispatch of that signal.
	set_deferred("monitoring", value)
