class_name BramblesGrenade
extends Projectile
## Lobbed grenade (real ballistic arc, same gravity-affected flight as Rocket)
## that breaks open into a BramblePatch on its first impact - a planet's
## surface, a building, a player, anything.

@export var patch_scene: PackedScene

var _landed: bool = false

func _ready() -> void:
	super._ready()
	affected_by_gravity = true

func _on_hit(collider: Object, hit_position: Vector3, hit_normal: Vector3) -> void:
	if _landed:
		return
	_landed = true
	Sfx.play_3d("collapse", hit_position, 1.05, -3.0)
	_spawn_patch(hit_position, hit_normal, collider)
	queue_free()

## If it landed on a planet, the patch is parented under that OrbitalBody so
## it rides the planet's own spin/orbit exactly like a Building does, instead
## of sitting still in world space while the ground rotates out from under
## it. Anything else (open space, a building, a player) just gets it dropped
## in the shared projectile root at the impact point.
func _spawn_patch(pos: Vector3, normal: Vector3, collider: Object) -> void:
	if patch_scene == null:
		return
	var patch: BramblePatch = patch_scene.instantiate()
	var up: Vector3 = normal.normalized() if normal.length() > 0.1 else Vector3.UP
	if collider is StaticBody3D and (collider as StaticBody3D).has_meta("orbital_body"):
		var body: OrbitalBody = collider.get_meta("orbital_body")
		if is_instance_valid(body) and not body.is_shattered:
			body.add_child(patch)
			patch.global_position = pos + up * 0.05
			patch.up_direction = up
			patch.owner_player = owner_player
			return
	_get_projectile_root().add_child(patch)
	patch.global_position = pos + up * 0.05
	patch.up_direction = up
	patch.owner_player = owner_player

## Mirrors Weapon._get_projectile_root() - see BlackHoleProjectile's identical
## duplicate for why a Projectile needs its own copy of this.
func _get_projectile_root() -> Node:
	var root: Node = get_tree().current_scene
	var container: Node = root.get_node_or_null("Projectiles")
	if container == null:
		container = Node3D.new()
		container.name = "Projectiles"
		root.add_child(container)
	return container
