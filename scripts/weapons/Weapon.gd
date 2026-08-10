class_name Weapon
extends Node3D
## Base class for all weapons. WeaponManager holds instances of these as
## children and calls fire()/can_fire() on whichever one is active.
## Subclasses override `_do_fire()`.

signal fired

@export var weapon_name: String = "Weapon"
@export var fire_cooldown: float = 0.8
@export var damage: float = 0.0
## If true, this weapon is removed from the loadout after a single shot
## (used by the Planet Buster, which is pickup-only and rare by design).
@export var consumed_on_fire: bool = false
## Identity color for this weapon - tints its first-person viewmodel meshes
## (any MeshInstance3D under a child node named "ViewModel") and is read by
## the HUD to color-code the weapon list. Set per-subclass in `_init()`.
@export var weapon_color: Color = Color.WHITE

var owner_player: Node = null
var _cooldown_remaining: float = 0.0

func _ready() -> void:
	_apply_weapon_color()

func _apply_weapon_color() -> void:
	var view_model: Node = get_node_or_null("ViewModel")
	if view_model == null:
		return
	for child in view_model.get_children():
		if child is MeshInstance3D:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = weapon_color
			mat.emission_enabled = true
			mat.emission = weapon_color
			mat.emission_energy_multiplier = 1.4
			mat.metallic = 0.3
			mat.roughness = 0.5
			child.material_override = mat

func _process(delta: float) -> void:
	if _cooldown_remaining > 0.0:
		_cooldown_remaining -= delta

## Called every frame by WeaponManager whether or not fire is held.
## Override in subclasses for charge-up logic (see Railgun.gd).
func tick(_delta: float, _fire_held: bool) -> void:
	pass

func can_fire() -> bool:
	return _cooldown_remaining <= 0.0

## `muzzle_transform` is world-space transform of the barrel tip.
## `aim_direction` is the camera's forward vector (precise aim, independent
## of body yaw/pitch limits) - projectiles should launch along this.
func fire(muzzle_transform: Transform3D, aim_direction: Vector3) -> bool:
	if not can_fire():
		return false
	_cooldown_remaining = fire_cooldown
	_do_fire(muzzle_transform, aim_direction)
	fired.emit()
	return true

func _do_fire(_muzzle_transform: Transform3D, _aim_direction: Vector3) -> void:
	pass # override

## Called by WeaponManager when this weapon stops being the active one. Only
## the active weapon gets ticked, so anything with persistent world state needs
## to unwind it here (see GrapplingHook).
func on_holster() -> void:
	pass # override

## Finds (or lazily creates) the shared container new projectiles get parented
## under, so they don't end up nested inside the firing player (which would
## drag them along when the player moves/dies/respawns).
func _get_projectile_root() -> Node:
	var root := get_tree().current_scene
	var container := root.get_node_or_null("Projectiles")
	if container == null:
		container = Node3D.new()
		container.name = "Projectiles"
		root.add_child(container)
	return container
