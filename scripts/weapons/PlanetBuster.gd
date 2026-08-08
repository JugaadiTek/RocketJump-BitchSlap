class_name PlanetBuster
extends Weapon

@export var shell_scene: PackedScene
@export var shell_speed: float = 7.0

func _init() -> void:
	weapon_name = "Planet Buster"
	fire_cooldown = 2.0
	consumed_on_fire = true

func _do_fire(muzzle_transform: Transform3D, aim_direction: Vector3) -> void:
	if shell_scene == null:
		push_warning("PlanetBuster has no shell_scene assigned")
		return
	var shell: PlanetBusterProjectile = shell_scene.instantiate()
	_get_projectile_root().add_child(shell)
	shell.global_position = muzzle_transform.origin
	shell.launch(aim_direction * shell_speed, owner_player)
