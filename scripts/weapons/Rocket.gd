class_name Rocket
extends Projectile

@export var splash_radius: float = 6.0
@export var splash_damage: float = 100.0
@export var knockback_strength: float = 16.0
@export var self_knockback_multiplier: float = 1.3
@export var deform_depth: float = 0.4 ## how deep the blast crater pushes surface verts inward

var _exploded: bool = false
var _trail_particles: GPUParticles3D = null

func _ready() -> void:
	super._ready()
	_spawn_trail()

func _spawn_trail() -> void:
	_trail_particles = GPUParticles3D.new()
	add_child(_trail_particles)
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 22.0
	mat.initial_velocity_min = 0.5
	mat.initial_velocity_max = 2.5
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.08
	mat.scale_max = 0.25
	mat.color = Color(0.6, 0.6, 0.6, 0.7)
	_trail_particles.process_material = mat
	_trail_particles.draw_pass_1 = SphereMesh.new()
	_trail_particles.amount = 12
	_trail_particles.lifetime = 0.55
	_trail_particles.fixed_fps = 30
	_trail_particles.emitting = true
	_trail_particles.local_coords = false

func _on_hit(collider: Object, hit_position: Vector3, hit_normal: Vector3) -> void:
	if _exploded:
		return
	_exploded = true
	Sfx.play_3d("explosion", hit_position, 1.0, 6.0)
	_explode(hit_position, hit_normal, collider)

func _explode(hit_position: Vector3, hit_normal: Vector3, collider: Object) -> void:
	_perturb_planet_if_hit(collider)
	_deform_planet_mesh_if_hit(collider, hit_position)
	_apply_splash(hit_position)
	_spawn_explosion_fx(hit_position, hit_normal)
	queue_free()

func _perturb_planet_if_hit(collider: Object) -> void:
	if collider is StaticBody3D and collider.has_meta("orbital_body"):
		var body: OrbitalBody = collider.get_meta("orbital_body")
		if is_instance_valid(body):
			body.perturb_orbit(0.4)

func _deform_planet_mesh_if_hit(collider: Object, hit_position: Vector3) -> void:
	if not (collider is StaticBody3D and collider.has_meta("orbital_body")):
		return
	var body: OrbitalBody = collider.get_meta("orbital_body")
	if not is_instance_valid(body):
		return
	var mi: MeshInstance3D = body.get_node_or_null("MeshInstance3D")
	if mi == null:
		return
	# Convert primitive mesh to editable ArrayMesh on first rocket hit.
	if not (mi.mesh is ArrayMesh):
		var st := SurfaceTool.new()
		st.create_from(mi.mesh, 0)
		mi.mesh = st.commit()
	var arr_mesh: ArrayMesh = mi.mesh as ArrayMesh
	if arr_mesh == null or arr_mesh.get_surface_count() == 0:
		return
	var arrays: Array = arr_mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[ArrayMesh.ARRAY_VERTEX]
	var local_hit: Vector3 = mi.to_local(hit_position)
	var deform_r: float = splash_radius * 1.2
	for i in range(verts.size()):
		var dist: float = verts[i].distance_to(local_hit)
		if dist < deform_r:
			var t: float = 1.0 - (dist / deform_r)
			verts[i] += verts[i].normalized() * (-deform_depth * t * t)
	arrays[ArrayMesh.ARRAY_VERTEX] = verts
	arr_mesh.clear_surfaces()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

func _apply_splash(center: Vector3) -> void:
	for node in get_tree().get_nodes_in_group("damageable"):
		if not is_instance_valid(node):
			continue
		var dist: float = node.global_position.distance_to(center)
		if dist > splash_radius:
			continue
		var falloff: float = 1.0 - (dist / splash_radius)
		var is_owner: bool = (node == owner_player)
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
