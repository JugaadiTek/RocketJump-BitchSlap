class_name ArtilleryShell
extends Projectile
## The Gunship's own artillery round. Launched nearly straight up from the
## ship's muzzle at real physics (affected_by_gravity stays true, unlike the
## Planet Buster's shell) so it genuinely arcs - up, over, and back down -
## rather than flying a guided straight line. A gentle, ramping homing nudge
## (see _steer) keeps real multi-body gravity along the way from carrying it
## off the painted mark; without it the same physics that makes the arc look
## good would just as easily miss a body drifting under its own orbit.
## Terminal guidance close-in guarantees the actual hit, the same lesson
## PlanetBusterProjectile's own miss-fix already applied here from the start
## rather than discovering it the hard way twice.

## Multiple of Rocket.gd's own splash_radius (6.0), set by Gunship when it
## instances this scene - see Gunship.blast_radius_multiplier.
@export var blast_radius: float = 30.0
@export var blast_damage: float = 260.0
@export var deform_depth: float = 3.5
## How hard this kicks the target planet's orbit - Rocket.gd uses 0.4 for a
## direct hit; an artillery-scale blast (5x the radius) shakes it much harder.
@export var orbit_perturb_strength: float = 2.2

var target_marker_path: NodePath = NodePath()
var _life: float = 0.0
var _exploded: bool = false

func _ready() -> void:
	super._ready()
	affected_by_gravity = true
	inherit_shooter_velocity = false
	# The ship can be clear on the far side of the arena from whatever planet
	# its driver painted (spawns pin to a boundary face - see
	# GunshipDirector._boundary_entry_point - while a target could be
	# anywhere, including near the centre), a gap of several hundred metres
	# that a slow launch speed with a short fuse would time out over before
	# ever arriving - a "the burst just fizzles for no visible reason" bug
	# that's easy to miss testing at close range and only shows up at the
	# game's actual scale. Generous on both counts for exactly that reason.
	lifetime = 26.0

func _steer(delta: float) -> void:
	_life += delta
	if target_marker_path.is_empty():
		return
	var target: Node3D = get_node_or_null(target_marker_path)
	if target == null or not is_instance_valid(target):
		return
	var to_target: Vector3 = target.global_position - global_position
	var dist: float = to_target.length()
	if dist < 0.01 or velocity.length() < 0.01:
		return
	# Ramps from "barely nudging" (the ballistic arc reads as real physics)
	# to "fully committed" once close, exactly the terminal-guidance pattern
	# PlanetBusterProjectile uses so a real hit is guaranteed instead of
	# merely likely.
	var homing_strength: float = clampf(_life / 1.5, 0.0, 1.0)
	if dist < blast_radius * 2.0:
		homing_strength = 1.0
	var desired_dir: Vector3 = to_target.normalized()
	var blended: Vector3 = velocity.normalized().lerp(desired_dir, clampf(homing_strength * delta * 3.0, 0.0, 1.0))
	if blended.length_squared() > 0.0001:
		velocity = blended.normalized() * velocity.length()

func _on_hit(collider: Object, hit_position: Vector3, hit_normal: Vector3) -> void:
	if _exploded:
		return
	_exploded = true
	Sfx.play_3d("explosion", hit_position, 0.6, 4.0)
	Sfx.play_3d("planet_shatter", hit_position, 0.9, 1.5, 0.05)
	_perturb_and_deform(collider, hit_position)
	_apply_blast(hit_position)
	_spawn_nuke_fx(hit_position, hit_normal)
	# The mark is gone the instant it's actually hit, rather than waiting out
	# ArtilleryMarker's own fallback timeout.
	if not target_marker_path.is_empty():
		var marker: Node = get_node_or_null(target_marker_path)
		if marker:
			marker.queue_free()
	queue_free()

func _expire() -> void:
	# A shell that ran out its (generous) lifetime without ever resolving -
	# still detonate wherever it ended up rather than silently vanishing, so
	# a painted mark always eventually gets something to show for it.
	if not _exploded:
		_on_hit(null, global_position, Vector3.UP)
	else:
		super._expire()

func _perturb_and_deform(collider: Object, hit_position: Vector3) -> void:
	if not (collider is StaticBody3D and (collider as StaticBody3D).has_meta("orbital_body")):
		return
	var body: OrbitalBody = collider.get_meta("orbital_body")
	if not is_instance_valid(body) or body.is_shattered:
		return
	body.perturb_orbit(orbit_perturb_strength)
	body.apply_crater(hit_position, blast_radius, deform_depth)

func _apply_blast(center: Vector3) -> void:
	for node in get_tree().get_nodes_in_group("damageable"):
		if not is_instance_valid(node):
			continue
		var dist: float = node.global_position.distance_to(center)
		if dist > blast_radius:
			continue
		var falloff: float = 1.0 - (dist / blast_radius)
		if node.has_method("apply_damage"):
			var dmg: float = blast_damage * falloff
			if node.has_method("network_apply_damage") and not node.is_multiplayer_authority():
				node.rpc_id(node.get_multiplayer_authority(), "network_apply_damage", dmg, owner_player.get_path() if owner_player else NodePath(), center, "Artillery Gunship")
			else:
				node.apply_damage(dmg, owner_player, center, "Artillery Gunship")
		if node.has_method("apply_impulse"):
			var away: Vector3 = node.global_position - center
			var dir: Vector3 = away.normalized() if away.length() > 0.01 else Vector3.UP
			var impulse: Vector3 = dir * 30.0 * falloff
			if node.has_method("network_apply_impulse") and not node.is_multiplayer_authority():
				node.rpc_id(node.get_multiplayer_authority(), "network_apply_impulse", impulse)
			else:
				node.apply_impulse(impulse)

## A proper nuke: bright flash, expanding shockwave ring, and a rising-
## column-then-spreading-cap mushroom cloud - three cheap primitive/particle
## pieces layered together, the same "build it from primitives + tweens"
## convention every other explosion in this project already follows
## (Rocket._spawn_explosion_fx, OrbitalBody.shatter's debris).
func _spawn_nuke_fx(pos: Vector3, normal: Vector3) -> void:
	var up: Vector3 = normal if normal.length() > 0.1 else Vector3.UP
	_spawn_flash(pos)
	_spawn_shockwave(pos, up)
	_spawn_mushroom_cloud(pos, up)

func _spawn_flash(pos: Vector3) -> void:
	var flash := MeshInstance3D.new()
	get_tree().current_scene.add_child(flash)
	flash.global_position = pos
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	flash.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.95, 0.75, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.9, 0.6)
	mat.emission_energy_multiplier = 8.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash.material_override = mat
	var tw: Tween = flash.create_tween()
	tw.tween_property(flash, "scale", Vector3.ONE * blast_radius * 1.1, 0.25).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.3)
	tw.tween_callback(flash.queue_free)

func _spawn_shockwave(pos: Vector3, up: Vector3) -> void:
	var ring := MeshInstance3D.new()
	get_tree().current_scene.add_child(ring)
	ring.global_position = pos
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	ring.mesh = torus
	var ref: Vector3 = Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var bx: Vector3 = up.cross(ref).normalized()
	var bz: Vector3 = bx.cross(up).normalized()
	ring.global_transform.basis = Basis(bx, up, bz)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.55, 0.2, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.15)
	mat.emission_energy_multiplier = 4.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = mat
	var tw: Tween = ring.create_tween()
	tw.tween_property(ring, "scale", Vector3.ONE * blast_radius * 2.2, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.9)
	tw.tween_callback(ring.queue_free)

func _spawn_mushroom_cloud(pos: Vector3, up: Vector3) -> void:
	var stem := GPUParticles3D.new()
	get_tree().current_scene.add_child(stem)
	stem.global_position = pos
	var stem_mat := ParticleProcessMaterial.new()
	stem_mat.direction = up
	stem_mat.spread = 8.0
	stem_mat.initial_velocity_min = blast_radius * 0.9
	stem_mat.initial_velocity_max = blast_radius * 1.3
	stem_mat.gravity = -up * 2.0 # slows rather than falls, so the column holds its shape
	stem_mat.scale_min = 1.5
	stem_mat.scale_max = 3.0
	stem_mat.color = Color(0.32, 0.28, 0.24, 0.92)
	stem.process_material = stem_mat
	stem.draw_pass_1 = SphereMesh.new()
	stem.amount = 40
	stem.lifetime = 2.2
	stem.one_shot = true
	stem.explosiveness = 0.7
	stem.emitting = true

	var cap := GPUParticles3D.new()
	get_tree().current_scene.add_child(cap)
	cap.global_position = pos + up * blast_radius * 1.6
	var cap_mat := ParticleProcessMaterial.new()
	cap_mat.direction = up
	cap_mat.spread = 100.0
	cap_mat.initial_velocity_min = blast_radius * 0.6
	cap_mat.initial_velocity_max = blast_radius * 1.1
	cap_mat.gravity = Vector3.ZERO
	cap_mat.scale_min = 2.5
	cap_mat.scale_max = 5.0
	cap_mat.color = Color(0.55, 0.45, 0.35, 0.85)
	cap.process_material = cap_mat
	cap.draw_pass_1 = SphereMesh.new()
	cap.amount = 60
	cap.lifetime = 2.6
	cap.one_shot = true
	cap.explosiveness = 0.85
	cap.emitting = false
	var delay: SceneTreeTimer = get_tree().create_timer(0.35)
	delay.timeout.connect(func(): if is_instance_valid(cap): cap.emitting = true)

	var cleanup: SceneTreeTimer = get_tree().create_timer(3.2)
	cleanup.timeout.connect(func():
		if is_instance_valid(stem):
			stem.queue_free()
		if is_instance_valid(cap):
			cap.queue_free())
