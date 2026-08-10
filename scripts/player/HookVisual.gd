class_name HookVisual
extends Node3D
## Draws the grappling cable for the Player it hangs off - including other
## people's and the bots'.
##
## It deliberately does NOT live inside the weapon viewmodel: Player._ready()
## hides the whole WeaponManager subtree for every view except the local one, so
## a cable parented there would only ever be visible to the person firing it.
## Instead this sits under the Player root and renders purely from the two
## replicated fields `hook_active` / `hook_end`, which means remote peers and
## locally-simulated bots all show their grapples with no extra plumbing.

@onready var _cable: MeshInstance3D = $Cable
@onready var _hook_head: MeshInstance3D = $HookHead

var _player: Player = null

func _ready() -> void:
	_player = owner as Player
	_cable.visible = false
	_hook_head.visible = false

## Driven from _process rather than _physics_process so the cable tracks the
## muzzle smoothly at render rate instead of stepping at 60Hz.
func _process(_delta: float) -> void:
	if _player == null or not _player.hook_active or _player.is_dead:
		_cable.visible = false
		_hook_head.visible = false
		return

	var start: Vector3 = _player.get_muzzle_transform().origin
	var end: Vector3 = _player.hook_end
	_hook_head.visible = true
	_hook_head.global_position = end

	var span: Vector3 = end - start
	var length: float = span.length()
	if length < 0.05:
		_cable.visible = false
		return
	# Stretch the unit-height cylinder along the span by scaling its Y axis.
	var axis_y: Vector3 = span / length
	var reference: Vector3 = Vector3.RIGHT if absf(axis_y.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var axis_x: Vector3 = axis_y.cross(reference).normalized()
	var axis_z: Vector3 = axis_x.cross(axis_y).normalized()
	_cable.visible = true
	_cable.global_transform = Transform3D(Basis(axis_x, axis_y * length, axis_z), start + span * 0.5)
