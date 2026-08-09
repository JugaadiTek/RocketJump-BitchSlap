extends Area3D
## Steps on -> launches straight along this pad's own local up (so tilting
## the pad in the editor changes launch direction). Uses apply_impulse(),
## the same mechanism as rocket splash and melee launches, which is what
## grants the brief exemption from Player's ground-stick correction - see
## Player._apply_ground_stick().

@export var launch_speed: float = 34.0
@export var retrigger_cooldown: float = 0.75

var _cooldowns: Dictionary = {} # body -> seconds remaining

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	if _cooldowns.is_empty():
		return
	for body in _cooldowns.keys():
		_cooldowns[body] -= delta
		if _cooldowns[body] <= 0.0:
			_cooldowns.erase(body)

func _on_body_entered(body: Node3D) -> void:
	if not body.has_method("apply_impulse"):
		return
	if not body.is_multiplayer_authority():
		return
	if _cooldowns.has(body):
		return
	_cooldowns[body] = retrigger_cooldown
	var launch_dir: Vector3 = global_transform.basis.y.normalized()
	body.apply_impulse(launch_dir * launch_speed)
