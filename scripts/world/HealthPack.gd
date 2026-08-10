class_name HealthPack
extends Area3D
## Surface pickup that tops a player back up. Scattered by Arena, more of them
## on bigger planets, and parented to the OrbitalBody so it orbits and spins
## along with the ground it sits on.
##
## Only consumed if it actually does something: a player already at full health
## walks straight over it and leaves it for someone who needs it.

@export var heal_amount: float = 35.0
@export var respawn_time: float = 25.0
@export var bob_height: float = 0.18
@export var spin_speed: float = 1.8

@onready var visual: Node3D = $Visual

var _available: bool = true
var _time: float = 0.0
var _visual_rest_y: float = 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if visual:
		_visual_rest_y = visual.position.y

func _process(delta: float) -> void:
	if not _available or visual == null:
		return
	# Bob and spin so it catches the eye against a static surface.
	_time += delta
	visual.position.y = _visual_rest_y + sin(_time * 2.4) * bob_height
	visual.rotate_y(spin_speed * delta)

func _on_body_entered(body: Node3D) -> void:
	if not _available or not body.has_method("heal"):
		return
	# Authority-only: the peer simulating that player owns its health, and
	# heal() returns false when they're already full, which leaves the pack up.
	if not body.is_multiplayer_authority():
		return
	if not body.heal(heal_amount):
		return
	Sfx.play_3d("health", global_position, 1.0, -2.0)
	_set_available(false)
	await get_tree().create_timer(respawn_time).timeout
	if is_instance_valid(self):
		_set_available(true)

func _set_available(value: bool) -> void:
	_available = value
	if visual:
		visual.visible = value
	# Deferred: _set_available() is reached from inside the body_entered
	# signal, and Area3D refuses a direct write to `monitoring` while it is
	# mid-dispatch of that signal.
	set_deferred("monitoring", value)
