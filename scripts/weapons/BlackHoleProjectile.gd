class_name BlackHoleProjectile
extends Projectile
## Slow gravity-affected shot fired by the Black Hole Gun. Flies ballistically
## (no homing, same as a plain Rocket) and opens a BlackHole hazard on impact
## instead of dealing direct damage itself.

@export var black_hole_scene: PackedScene

var _exploded: bool = false

func _on_hit(_collider: Object, hit_position: Vector3, hit_normal: Vector3) -> void:
	if _exploded:
		return
	_exploded = true
	Sfx.play_3d("planet_shatter", hit_position, 1.15, 1.5, 0.05)
	_spawn_black_hole(hit_position, hit_normal)
	queue_free()

func _spawn_black_hole(pos: Vector3, normal: Vector3) -> void:
	if black_hole_scene == null:
		return
	var hole: BlackHole = black_hole_scene.instantiate()
	_get_projectile_root().add_child(hole)
	# Sit a little clear of whatever surface it hit, along the impact normal,
	# so the hazard's own visual/collision isn't clipping straight into a
	# planet's mesh.
	hole.global_position = pos + (normal.normalized() if normal.length() > 0.1 else Vector3.UP) * 0.5
	hole.owner_player = owner_player

## Mirrors Weapon._get_projectile_root() - a Projectile doesn't otherwise have
## it, and this is the one projectile that itself spawns another node needing
## the same shared, player-independent container (see Gunship's identical
## duplicate for the same reason).
func _get_projectile_root() -> Node:
	var root: Node = get_tree().current_scene
	var container: Node = root.get_node_or_null("Projectiles")
	if container == null:
		container = Node3D.new()
		container.name = "Projectiles"
		root.add_child(container)
	return container
