class_name PlanetBusterProjectile
extends Projectile

@export var planet_blast_radius: float = 90.0
@export var planet_blast_damage: float = 500.0
@export var direct_hit_damage: float = 150.0
@export var direct_hit_radius: float = 12.0
@export var steer_rate: float = 0.35  ## slerp factor per frame toward target

var lock_target: OrbitalBody = null
var _exploded: bool = false

func _steer(_delta: float) -> void:
	if lock_target == null or not is_instance_valid(lock_target) or lock_target.is_shattered:
		return
	var to_target: Vector3 = (lock_target.global_position - global_position).normalized()
	var current_dir: Vector3 = velocity.normalized() if velocity.length() > 0.01 else to_target
	var new_dir: Vector3 = current_dir.slerp(to_target, steer_rate)
	velocity = new_dir.normalized() * velocity.length()

func _on_hit(collider: Object, hit_position: Vector3, _hit_normal: Vector3) -> void:
	if _exploded:
		return
	_exploded = true
	if collider is StaticBody3D and collider.has_meta("orbital_body"):
		var body: OrbitalBody = collider.get_meta("orbital_body")
		if is_instance_valid(body) and body.can_be_shattered:
			body.shatter(planet_blast_radius, planet_blast_damage)
		else:
			_small_splash(hit_position)
	else:
		_small_splash(hit_position)
	queue_free()

func _small_splash(center: Vector3) -> void:
	for node in get_tree().get_nodes_in_group("damageable"):
		if not is_instance_valid(node) or node == owner_player:
			continue
		var dist: float = node.global_position.distance_to(center)
		if dist > direct_hit_radius:
			continue
		var falloff: float = 1.0 - (dist / direct_hit_radius)
		if node.has_method("apply_damage"):
			var dmg: float = direct_hit_damage * falloff
			if node.has_method("network_apply_damage") and not node.is_multiplayer_authority():
				node.rpc_id(node.get_multiplayer_authority(), "network_apply_damage", dmg, owner_player.get_path() if owner_player else NodePath(), center, "Planet Buster")
			else:
				node.apply_damage(dmg, owner_player, center, "Planet Buster")
