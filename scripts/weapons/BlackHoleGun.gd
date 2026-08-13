class_name BlackHoleGun
extends Weapon
## Pickup-only heavy weapon (granted the same way the Planet Buster is - see
## PlanetBusterPickup.gd, now generalized to grant any weapon id). Fires a
## slow, gravity-affected projectile that opens a BlackHole wherever it lands.

@export var projectile_scene: PackedScene
@export var projectile_speed: float = 34.0

func _init() -> void:
	weapon_name = "Black Hole Gun"
	fire_cooldown = 6.0 # heavy weapon, deliberately rare to fire again
	weapon_color = Color(0.6, 0.15, 0.9)

func _do_fire(muzzle_transform: Transform3D, aim_direction: Vector3) -> void:
	if projectile_scene == null:
		push_warning("BlackHoleGun has no projectile_scene assigned")
		return
	aim_direction = _apply_aim_assist(muzzle_transform.origin, aim_direction)
	var proj: BlackHoleProjectile = projectile_scene.instantiate()
	_get_projectile_root().add_child(proj)
	proj.global_position = muzzle_transform.origin
	proj.launch(aim_direction * projectile_speed, owner_player)
	Sfx.play_3d("buster_fire", muzzle_transform.origin, 0.7, -4.0, 0.05)
