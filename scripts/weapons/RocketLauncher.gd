class_name RocketLauncher
extends Weapon

@export var rocket_scene: PackedScene
@export var rocket_speed: float = 16.0

func _init() -> void:
	weapon_name = "Rocket Launcher"
	fire_cooldown = 0.9
	weapon_color = Color(0.95, 0.4, 0.1)

func _do_fire(muzzle_transform: Transform3D, aim_direction: Vector3) -> void:
	if rocket_scene == null:
		push_warning("RocketLauncher has no rocket_scene assigned")
		return
	var rocket: Rocket = rocket_scene.instantiate()
	_get_projectile_root().add_child(rocket)
	rocket.global_position = muzzle_transform.origin
	rocket.launch(aim_direction * rocket_speed, owner_player)
