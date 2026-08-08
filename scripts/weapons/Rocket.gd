class_name Rocket
extends Projectile

@export var splash_radius: float = 6.0
@export var splash_damage: float = 100.0
## Knockback impulses are scaled up relative to damage falloff so a
## point-blank rocket jump actually launches you - tune this rather than
## splash_damage if jumps feel weak.
@export var knockback_strength: float = 16.0
@export var self_knockback_multiplier: float = 1.3

var _exploded: bool = false

func _on_hit(collider: Object, hit_position: Vector3, hit_normal: Vector3) -> void:
	if _exploded:
		return
	_exploded = true
	_explode(hit_position, hit_normal, collider)

func _explode(hit_position: Vector3, hit_normal: Vector3, collider: Object) -> void:
	_perturb_planet_if_hit(collider)
	_apply_splash(hit_position)
	_spawn_explosion_fx(hit_position, hit_normal)
	queue_free()

func _perturb_planet_if_hit(collider: Object) -> void:
	if collider is StaticBody3D and collider.has_meta("orbital_body"):
		var body: OrbitalBody = collider.get_meta("orbital_body")
		if is_instance_valid(body):
			body.perturb_orbit(0.4)

func _apply_splash(center: Vector3) -> void:
	for node in get_tree().get_nodes_in_group("damageable"):
		if not is_instance_valid(node):
			continue
		var dist: float = node.global_position.distance_to(center)
		if dist > splash_radius:
			continue
		var falloff: float = 1.0 - (dist / splash_radius)
		var is_owner: bool = (node == owner_player)

		# No self damage, but rocket jumping still needs the knockback.
		if not is_owner and node.has_method("apply_damage"):
			var dmg: float = splash_damage * falloff
			if node.has_method("network_apply_damage") and not node.is_multiplayer_authority():
				node.rpc_id(node.get_multiplayer_authority(), "network_apply_damage", dmg, owner_player.get_path() if owner_player else NodePath(), center, "Rocket Launcher")
			else:
				node.apply_damage(dmg, owner_player, center, "Rocket Launcher")

		if node.has_method("apply_impulse"):
			var away: Vector3 = (node.global_position - center)
			var dir: Vector3 = away.normalized() if away.length() > 0.01 else -velocity.normalized()
			var mult: float = self_knockback_multiplier if is_owner else 1.0
			var impulse: Vector3 = dir * knockback_strength * falloff * mult
			if node.has_method("network_apply_impulse") and not node.is_multiplayer_authority():
				node.rpc_id(node.get_multiplayer_authority(), "network_apply_impulse", impulse)
			else:
				node.apply_impulse(impulse)

func _spawn_explosion_fx(pos: Vector3, normal: Vector3) -> void:
	var particles := GPUParticles3D.new()
	get_tree().current_scene.add_child(particles)
	particles.global_position = pos
	var mat := ParticleProcessMaterial.new()
	mat.direction = normal if normal.length() > 0.1 else Vector3.UP
	mat.spread = 60.0
	mat.initial_velocity_min = 4.0
	mat.initial_velocity_max = 10.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.2
	mat.scale_max = 0.5
	particles.process_material = mat
	particles.draw_pass_1 = SphereMesh.new()
	particles.amount = 24
	particles.lifetime = 0.6
	particles.one_shot = true
	particles.emitting = true
	particles.explosiveness = 1.0
	var timer := get_tree().create_timer(1.0)
	timer.timeout.connect(func(): if is_instance_valid(particles): particles.queue_free())
