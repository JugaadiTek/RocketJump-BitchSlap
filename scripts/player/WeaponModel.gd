class_name WeaponModel
extends MeshInstance3D
## The gun everyone else sees in a player's hands.
##
## First-person viewmodels live under Head/Camera3D/WeaponManager, which
## Player._ready() hides for every view except the local one - so from outside,
## players used to carry nothing. This sits on the body Model instead and
## restyles itself from whichever weapon is selected, reading that through the
## replicated `current_weapon_index` so remote players and bots are correct too.

## Rough silhouette per weapon, keyed by weapon_name so it stays right no matter
## what order the loadout ends up in.
const SHAPES: Dictionary = {
	"Rocket Launcher": Vector3(0.18, 0.18, 0.9),
	"Railgun": Vector3(0.12, 0.14, 1.15),
	"Slug Launcher": Vector3(0.20, 0.22, 0.7),
	"Grappling Hook": Vector3(0.16, 0.16, 0.5),
	"Space Board": Vector3(0.40, 0.08, 0.95),
	"Planet Buster": Vector3(0.30, 0.30, 1.0),
}

var _player: Player = null
var _material: StandardMaterial3D
var _applied_name: String = ""

func _ready() -> void:
	_player = owner as Player
	# This is the gun OTHER people see. In your own view the first-person
	# viewmodel is the gun, so showing this one too would put a second weapon
	# floating beside your head.
	if _player and _player.is_first_person_view():
		visible = false
		set_process(false)
		return
	mesh = mesh.duplicate()
	_material = StandardMaterial3D.new()
	_material.metallic = 0.4
	_material.roughness = 0.5
	_material.emission_enabled = true
	_material.emission_energy_multiplier = 0.8
	material_override = _material

func _process(_delta: float) -> void:
	if _player == null or _player.is_dead:
		visible = false
		return
	var weapon: Weapon = _player.get_displayed_weapon()
	if weapon == null:
		visible = false
		return
	visible = true
	if weapon.weapon_name == _applied_name:
		return
	_applied_name = weapon.weapon_name
	mesh.size = SHAPES.get(weapon.weapon_name, Vector3(0.16, 0.16, 0.8))
	_material.albedo_color = weapon.weapon_color
	_material.emission = weapon.weapon_color
