extends Node3D
## Child of Player (parented under Head/Camera3D so weapon viewmodels ride
## along with camera pitch). Holds weapon instances, handles switching +
## firing input, shows/hides the active weapon's viewmodel, and lets pickups
## (like the Planet Buster pad) grant extra weapons.

@export var rocket_launcher_scene: PackedScene
@export var railgun_scene: PackedScene
@export var slug_launcher_scene: PackedScene
@export var planet_buster_scene: PackedScene

var _weapons: Array[Weapon] = []
var _current_index: int = 0

## WeaponManager lives several levels under the Player root (Head/Camera3D/
## WeaponManager), so `get_parent()` alone won't reach it - `owner` is set by
## Godot to the scene root for every node saved inside Player.tscn, which is
## exactly the Player instance regardless of nesting depth.
@onready var _player: Player = owner as Player

func _ready() -> void:
	_add_starting_weapon(rocket_launcher_scene)
	_add_starting_weapon(railgun_scene)
	_add_starting_weapon(slug_launcher_scene)
	_update_visibility()

func _add_starting_weapon(scene: PackedScene) -> void:
	if scene == null:
		return
	var weapon: Weapon = scene.instantiate()
	weapon.owner_player = _player
	add_child(weapon)
	_weapons.append(weapon)

func handle_input(_delta: float, wants_fire: bool, switch_to_index: int, scroll_direction: int) -> void:
	var switched: bool = false
	if switch_to_index >= 0 and switch_to_index < _weapons.size() and switch_to_index != _current_index:
		_current_index = switch_to_index
		switched = true
	elif scroll_direction != 0 and _weapons.size() > 1:
		_current_index = wrapi(_current_index + scroll_direction, 0, _weapons.size())
		switched = true
	if switched:
		_update_visibility()

	if _weapons.is_empty():
		return
	if wants_fire:
		var weapon: Weapon = _weapons[_current_index]
		var fired: bool = weapon.fire(_player.get_muzzle_transform(), _player.get_look_direction())
		if fired and weapon.consumed_on_fire:
			_remove_current_weapon()

func _remove_current_weapon() -> void:
	var weapon: Weapon = _weapons[_current_index]
	_weapons.remove_at(_current_index)
	weapon.queue_free()
	_current_index = clamp(_current_index, 0, max(_weapons.size() - 1, 0))
	_update_visibility()

## Only the active weapon's viewmodel is shown, and only to the local
## first-person view - other players just see this player's body Model, not
## a floating gun (see Player._ready(), which hides WeaponManager entirely
## for non-authority instances).
func _update_visibility() -> void:
	for i in range(_weapons.size()):
		_weapons[i].visible = (i == _current_index)

func grant_weapon(id: String) -> void:
	var scene: PackedScene = null
	match id:
		"planetbuster":
			scene = planet_buster_scene
	if scene == null:
		return
	var weapon: Weapon = scene.instantiate()
	weapon.owner_player = _player
	add_child(weapon)
	_weapons.append(weapon)
	_current_index = _weapons.size() - 1
	_update_visibility()

func get_current_weapon_name() -> String:
	if _weapons.is_empty():
		return ""
	return _weapons[_current_index].weapon_name

func get_weapon_names() -> Array[String]:
	var names: Array[String] = []
	for w in _weapons:
		names.append(w.weapon_name)
	return names

func get_weapon_colors() -> Array[Color]:
	var colors: Array[Color] = []
	for w in _weapons:
		colors.append(w.weapon_color)
	return colors

func get_current_index() -> int:
	return _current_index
