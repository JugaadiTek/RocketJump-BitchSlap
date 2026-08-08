extends Node
## Child of Player. Holds weapon instances, handles switching + firing input,
## and lets pickups (like the Planet Buster pad) grant extra weapons.

@export var rocket_launcher_scene: PackedScene
@export var railgun_scene: PackedScene
@export var slug_launcher_scene: PackedScene
@export var planet_buster_scene: PackedScene

var _weapons: Array[Weapon] = []
var _current_index: int = 0

@onready var _player: Player = get_parent()

func _ready() -> void:
	_add_starting_weapon(rocket_launcher_scene)
	_add_starting_weapon(railgun_scene)
	_add_starting_weapon(slug_launcher_scene)

func _add_starting_weapon(scene: PackedScene) -> void:
	if scene == null:
		return
	var weapon: Weapon = scene.instantiate()
	weapon.owner_player = _player
	add_child(weapon)
	_weapons.append(weapon)

func handle_input(_delta: float, wants_fire: bool, switch_to_index: int) -> void:
	if switch_to_index >= 0 and switch_to_index < _weapons.size():
		_current_index = switch_to_index
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

func get_current_weapon_name() -> String:
	if _weapons.is_empty():
		return ""
	return _weapons[_current_index].weapon_name
