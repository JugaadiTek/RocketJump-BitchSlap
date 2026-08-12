class_name PlanetBusterProjectile
extends Projectile
## The siege shell. It leaves the barrel slowly and then accelerates in a
## straight line, recomputing its heading toward the locked planet once a second
## rather than continuously — so it flies a visible chain of straight legs that
## kink at each course update, and closes faster and faster until it lands.

@export var planet_blast_radius: float = 90.0
@export var planet_blast_damage: float = 500.0
@export var direct_hit_damage: float = 150.0
@export var direct_hit_radius: float = 12.0
## Constant acceleration along the current heading, held all the way to impact.
@export var acceleration: float = 24.0
@export var max_speed: float = 260.0
## Seconds between heading recalculations. The planet keeps orbiting between
## them, which is what gives the flight path its stepped, deliberate look.
@export var course_update_interval: float = 1.0

var lock_target: OrbitalBody = null
var _exploded: bool = false
var _course_dir: Vector3 = Vector3.ZERO
var _course_timer: float = 0.0

func _ready() -> void:
	super._ready()
	# A guided shell owns its own path; letting the arena's gravity bend it too
	# would fight the once-a-second course corrections.
	affected_by_gravity = false
	inherit_shooter_velocity = false
	_course_timer = course_update_interval
	_spawn_smoke_trail()

## A siege shell crossing hundreds of metres should be visible from anywhere in
## the arena - the trail is the telegraph that gives everyone a chance to react
## before a planet comes apart. Emitted in world space (local_coords off) so it
## hangs in the sky behind the shell rather than dragging along with it.
func _spawn_smoke_trail() -> void:
	var smoke := GPUParticles3D.new()
	add_child(smoke)
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 60.0
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 7.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 2.0
	mat.scale_max = 5.5
	mat.color = Color(0.72, 0.24, 0.95, 0.85)
	smoke.process_material = mat
	var puff := SphereMesh.new()
	puff.radial_segments = 8
	puff.rings = 4
	var puff_mat := StandardMaterial3D.new()
	puff_mat.albedo_color = Color(0.55, 0.18, 0.85, 0.75)
	puff_mat.emission_enabled = true
	puff_mat.emission = Color(0.75, 0.3, 1.0, 1.0)
	puff_mat.emission_energy_multiplier = 2.5
	puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.material = puff_mat
	smoke.draw_pass_1 = puff
	smoke.amount = 320
	smoke.lifetime = 4.5
	smoke.local_coords = false
	smoke.emitting = true

func _steer(delta: float) -> void:
	if _course_dir.length_squared() < 0.0001:
		_course_dir = velocity.normalized() if velocity.length() > 0.01 else -global_transform.basis.z

	_course_timer -= delta
	if _course_timer <= 0.0:
		_course_timer = course_update_interval
		if lock_target != null and is_instance_valid(lock_target) and not lock_target.is_shattered:
			var to_target: Vector3 = lock_target.global_position - global_position
			if to_target.length_squared() > 0.0001:
				_course_dir = to_target.normalized()

	var speed: float = min(velocity.length() + acceleration * delta, max_speed)
	velocity = _course_dir * speed
	# Keep the shell's mesh pointing where it's actually going.
	if speed > 0.01:
		look_at(global_position + _course_dir, Vector3.UP if absf(_course_dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT)

func _on_hit(collider: Object, hit_position: Vector3, _hit_normal: Vector3) -> void:
	if _exploded:
		return
	_exploded = true
	if collider is StaticBody3D and collider.has_meta("orbital_body"):
		var body: OrbitalBody = collider.get_meta("orbital_body")
		if is_instance_valid(body) and body.can_be_shattered:
			body.shatter(planet_blast_radius, planet_blast_damage, owner_player, "Planet Buster")
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
