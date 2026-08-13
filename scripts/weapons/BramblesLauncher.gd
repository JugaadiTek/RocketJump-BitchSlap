class_name BramblesLauncher
extends Weapon
## Pickup-only (see PlanetBusterPickup.gd/BramblesLauncherPickup.tscn). Lobs a
## BramblesGrenade in an arc; it breaks open into a BramblePatch hazard on
## whatever it lands on.

@export var grenade_scene: PackedScene
@export var throw_speed: float = 22.0
## Fraction of straight-line aim direction converted into upward lift, so the
## shot actually arcs instead of flying flat like a rocket.
@export var arc_lift: float = 0.45

func _init() -> void:
	weapon_name = "Brambles Launcher"
	fire_cooldown = 3.0
	weapon_color = Color(0.45, 0.65, 0.15)

func _do_fire(muzzle_transform: Transform3D, aim_direction: Vector3) -> void:
	if grenade_scene == null:
		push_warning("BramblesLauncher has no grenade_scene assigned")
		return
	aim_direction = _apply_aim_assist(muzzle_transform.origin, aim_direction, 120.0)
	var launch_dir: Vector3 = (aim_direction + Vector3.UP * arc_lift).normalized()
	var grenade: BramblesGrenade = grenade_scene.instantiate()
	_get_projectile_root().add_child(grenade)
	grenade.global_position = muzzle_transform.origin
	grenade.launch(launch_dir * throw_speed, owner_player)
	Sfx.play_3d("rocket_fire", muzzle_transform.origin, 1.15, -3.0)
