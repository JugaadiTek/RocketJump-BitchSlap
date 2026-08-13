extends Node3D
## Child of Player (parented under Head/Camera3D so weapon viewmodels ride
## along with camera pitch). Holds weapon instances, handles switching +
## firing input, shows/hides the active weapon's viewmodel, and lets pickups
## (like the Planet Buster pad) grant extra weapons.

@export var rocket_launcher_scene: PackedScene
@export var railgun_scene: PackedScene
@export var slug_launcher_scene: PackedScene
@export var planet_buster_scene: PackedScene
@export var space_board_scene: PackedScene
@export var grappling_hook_scene: PackedScene
@export var black_hole_gun_scene: PackedScene
@export var brambles_launcher_scene: PackedScene

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
	_add_starting_weapon(grappling_hook_scene)
	_add_starting_weapon(space_board_scene)
	# Testing option from the main menu: hand out the pickup-only Planet Buster
	# up front instead of making someone find a pad first.
	if MatchState.start_with_all_weapons:
		grant_weapon("planetbuster")
		grant_weapon("blackholegun")
		grant_weapon("brambleslauncher")
		_current_index = 0
	_update_visibility()

func _add_starting_weapon(scene: PackedScene) -> void:
	if scene == null:
		return
	var weapon: Weapon = scene.instantiate()
	weapon.owner_player = _player
	add_child(weapon)
	_weapons.append(weapon)

func handle_input(delta: float, wants_fire: bool, switch_to_index: int, scroll_direction: int) -> void:
	var switched: bool = false
	var previous_index: int = _current_index
	if switch_to_index >= 0 and switch_to_index < _weapons.size() and switch_to_index != _current_index:
		_current_index = switch_to_index
		switched = true
	elif scroll_direction != 0 and _weapons.size() > 1:
		_current_index = wrapi(_current_index + scroll_direction, 0, _weapons.size())
		switched = true
	if switched:
		# Only the active weapon is ticked, so anything holding persistent state
		# (a grappling hook mid-pull) has to be told it's been put away or it
		# would still be attached when it comes back out.
		if previous_index < _weapons.size():
			_weapons[previous_index].on_holster()
		_update_visibility()

	if _weapons.is_empty():
		return

	var weapon: Weapon = _weapons[_current_index]
	# Always tick the active weapon so charge accumulates while held and
	# drains/resets on release, regardless of cooldown state.
	weapon.tick(delta, wants_fire)

	if wants_fire:
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
		"blackholegun":
			scene = black_hole_gun_scene
		"brambleslauncher":
			scene = brambles_launcher_scene
	if scene == null:
		return
	var weapon: Weapon = scene.instantiate()
	weapon.owner_player = _player
	add_child(weapon)
	_weapons.append(weapon)
	_current_index = _weapons.size() - 1
	_update_visibility()

func get_active_weapon() -> Weapon:
	if _weapons.is_empty():
		return null
	return _weapons[_current_index]

## Applies a selection made elsewhere - specifically a remote peer's replicated
## `current_weapon_index`, since handle_input() only ever runs on the authority
## and remote players would otherwise be stuck showing weapon 0 forever.
func set_current_index(index: int) -> void:
	if _weapons.is_empty():
		return
	var clamped: int = clampi(index, 0, _weapons.size() - 1)
	if clamped == _current_index:
		return
	_weapons[_current_index].on_holster()
	_current_index = clamped
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
