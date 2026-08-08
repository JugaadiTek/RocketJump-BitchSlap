class_name Railgun
extends Weapon

@export var max_range: float = 500.0
@export var beam_scene: PackedScene ## optional cosmetic beam, see scenes/weapons/RailBeam.tscn

func _init() -> void:
	weapon_name = "Railgun"
	fire_cooldown = 1.4
	damage = 80.0

func _do_fire(muzzle_transform: Transform3D, aim_direction: Vector3) -> void:
	var space_state := get_world_3d().direct_space_state
	var from: Vector3 = muzzle_transform.origin
	var to: Vector3 = from + aim_direction * max_range
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1 | 2 | 8 # world, players, npcs
	if owner_player:
		query.exclude = [owner_player]
	var result: Dictionary = space_state.intersect_ray(query)

	var end_point: Vector3 = to
	if not result.is_empty():
		end_point = result.position
		var collider: Object = result.collider
		if collider and collider.has_method("apply_damage"):
			if collider.has_method("network_apply_damage") and not collider.is_multiplayer_authority():
				collider.rpc_id(collider.get_multiplayer_authority(), "network_apply_damage", damage, owner_player.get_path() if owner_player else NodePath(), end_point, weapon_name)
			else:
				collider.apply_damage(damage, owner_player, end_point, weapon_name)

	_spawn_beam(from, end_point)

func _spawn_beam(from: Vector3, to: Vector3) -> void:
	if beam_scene:
		var beam := beam_scene.instantiate()
		_get_projectile_root().add_child(beam)
		if beam.has_method("setup"):
			beam.setup(from, to)
		return
	# Fallback beam if no dedicated scene is assigned: a thin stretched box.
	var beam := MeshInstance3D.new()
	_get_projectile_root().add_child(beam)
	var length: float = from.distance_to(to)
	var box := BoxMesh.new()
	box.size = Vector3(0.06, 0.06, length)
	beam.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.9, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.9, 1.0)
	mat.emission_energy_multiplier = 4.0
	beam.material_override = mat
	beam.global_position = from.lerp(to, 0.5)
	if length > 0.01:
		beam.look_at(to, Vector3.UP if abs((to - from).normalized().dot(Vector3.UP)) < 0.99 else Vector3.RIGHT)
	var timer := get_tree().create_timer(0.12)
	timer.timeout.connect(func(): if is_instance_valid(beam): beam.queue_free())
