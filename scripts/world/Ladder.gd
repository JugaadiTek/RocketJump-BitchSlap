class_name Ladder
extends Area3D
## A climbable volume. Anything inside it that answers set_ladder()/clear_ladder()
## switches to climbing movement along this node's local +Y - see
## Player._apply_ladder_movement(). Built by Building._add_ladder().
##
## Masks players (layer 2) and NPCs (layer 8) but sits on no layer of its own,
## so it never blocks movement or stops a bullet.

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2 | 8
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body.has_method("set_ladder"):
		body.set_ladder(self)

func _on_body_exited(body: Node3D) -> void:
	if body.has_method("clear_ladder"):
		body.clear_ladder(self)
