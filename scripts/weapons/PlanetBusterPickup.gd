extends Area3D
## Sits on a planet's surface. Empty most of a match; becomes available on a
## long timer and grants the Planet Buster to the first player who touches it.

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
		body.grant_weapon("planetbuster")
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
