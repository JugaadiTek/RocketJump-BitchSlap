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

## The shell leaves the barrel at a deliberately slow 7 m/s (see PlanetBuster)
## and doesn't inherit the shooter's own velocity. A player moving forward at
## even a modest clip in open space - Space Board flight, boundary-launch
## momentum, a recent rocket-jump - easily outpaces that and drifts back into
## the shell within the first frame or two, since nothing but distance kept
## them apart. Projectile._on_hit() has no owner check, so that self-touch
## used to read as a stray hit: _on_hit fires, it's not a shatterable planet,
## so it does a harmless _small_splash and queue_free()s - the shell simply
## vanishes without ever reaching the planet it was locked onto. Excluding the
## shooter from the shell's own collision for its whole flight (not just the
## first few frames, unlike the generic muzzle-clearance trick other weapons
## rely on) removes the false hit entirely rather than trying to outrun it.
func launch(initial_velocity: Vector3, shooter: Node) -> void:
	super.launch(initial_velocity, shooter)
	if shooter is CollisionObject3D:
		add_collision_exception_with(shooter)

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

	var target_valid: bool = lock_target != null and is_instance_valid(lock_target) and not lock_target.is_shattered

	# Terminal guidance: the once-a-second re-aim is what gives long-range
	# flight its visible kinked path, but locking a heading a full second out
	# let a moving target - especially a small, fast-orbiting moon like
	# Cinder_Moon (radius 3, ~10-16 m/s combining its own orbit with its
	# already-orbiting parent's) - drift clear of its own radius before the
	# next scheduled correction ever landed, so the shell sailed past and
	# expired or splashed on nothing. This was the "sometimes misses planets"
	# bug. A shot fired at close range starts this uncorrected: the very
	# first heading is whatever the player was aiming at the moment of lock,
	# and nothing re-checks it until the first full course_update_interval
	# has elapsed - so a nearby, fast target can already be missed and moving
	# away again before guidance ever gets a second look. The fix is a wide,
	# generous proximity radius (not tied to the current, possibly-still-slow
	# closing speed) that switches to continuous (every physics frame)
	# course correction well before the shell could plausibly reach the
	# target, so there's no window for an uncorrected close-range pass.
	var terminal: bool = false
	if target_valid:
		var dist: float = global_position.distance_to(lock_target.global_position)
		terminal = dist < maxf(lock_target.radius * 4.0, 50.0)

	_course_timer -= delta
	if terminal or _course_timer <= 0.0:
		_course_timer = course_update_interval
		if target_valid:
			_course_dir = _lead_direction_to_target()

	var speed: float = min(velocity.length() + acceleration * delta, max_speed)
	velocity = _course_dir * speed
	# Keep the shell's mesh pointing where it's actually going.
	if speed > 0.01:
		look_at(global_position + _course_dir, Vector3.UP if absf(_course_dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT)

## Aims at where the target WILL be when the shell arrives, not where it is
## right now - a pure-pursuit heading (old behaviour) systematically lags a
## moving target by one whole course_update_interval of its own travel,
## which is exactly what let small/fast-orbiting bodies dodge a "locked on"
## shot. get_point_velocity() already combines orbital travel and
## self-rotation for any world point, so the same call used to move players
## with the ground under them works here to predict the body's centre.
func _lead_direction_to_target() -> Vector3:
	var target_vel: Vector3 = lock_target.get_point_velocity(lock_target.global_position)
	var to_target: Vector3 = lock_target.global_position - global_position
	var time_to_intercept: float = _estimate_arrival_time(to_target.length())
	var predicted: Vector3 = lock_target.global_position + target_vel * time_to_intercept
	var lead_dir: Vector3 = predicted - global_position
	return lead_dir.normalized() if lead_dir.length_squared() > 0.0001 else to_target.normalized()

## How long the shell itself will take to cover `dist` at its own constant
## acceleration, starting from its current speed - solving
## dist = v0*t + 0.5*a*t^2 for t, rather than just dist/current_speed. The
## shell spends most of a close-range shot still speeding up (7 m/s at the
## muzzle, ramping toward max_speed at 24 m/s^2), so dividing by the
## instantaneous speed alone hugely overestimates time-to-arrival early in
## the flight, which over-leads the target and can throw the aim out past it
## on the far side instead of short of it.
func _estimate_arrival_time(dist: float) -> float:
	if dist <= 0.01:
		return 0.0
	var v0: float = velocity.length()
	if acceleration <= 0.001:
		return dist / maxf(v0, 1.0)
	# Quadratic solve for dist = v0*t + 0.5*a*t^2, assuming the acceleration
	# holds the whole way (it's exact until max_speed is hit, an overestimate
	# past that - fine, since a shell that far out gets another correction
	# well before it matters). Clamped to a sane ceiling so a near-stationary
	# shell against a very distant target doesn't produce a wild lead.
	var disc: float = v0 * v0 + 2.0 * acceleration * dist
	return clampf((sqrt(maxf(disc, 0.0)) - v0) / acceleration, 0.0, course_update_interval * 6.0)

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
