class_name SlugLauncher
extends Weapon

@export var slug_scene: PackedScene
@export var slug_speed: float = 10.0

func _init() -> void:
	weapon_name = "Slug Launcher"
	fire_cooldown = 1.1
	weapon_color = Color(0.3, 0.85, 0.35)

func _do_fire(muzzle_transform: Transform3D, aim_direction: Vector3) -> void:
	if slug_scene == null:
		push_warning("SlugLauncher has no slug_scene assigned")
		return
	var slug: Slug = slug_scene.instantiate()
	_get_projectile_root().add_child(slug)
	slug.global_position = muzzle_transform.origin
	slug.launch(aim_direction * slug_speed, owner_player)
