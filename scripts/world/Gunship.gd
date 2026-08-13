class_name Gunship
extends Node3D
## The Artillery Gunship: a very large, slow, black capital ship that drifts
## through the arena on autopilot, always steering clear of every
## OrbitalBody (see GunshipDirector for spawn timing/cadence). While it has
## ever had a driver and still does, or hasn't been boarded yet, it meanders
## and stays inside the arena's own boundary; once abandoned (had a driver,
## no longer does - see is_abandoned()) it gives up and pathfinds its way
## back out, cancelled the instant someone reclaims the seat. Grappleable and
## destructible like anything else in the "damageable"/"grappable" world -
## any existing weapon already works against it for free, the same way
## Rocket/Railgun/Slug/Melee all just check `has_method("apply_damage")`
## rather than special-casing what they're hitting.
##
## Structured the same way OrbitalBody is: this Node3D root is what actually
## moves every physics frame, with a child StaticBody3D providing the real
## collision (grapple-able, walkable, blocks weapon fire) - see
## _autopilot_steer(). Known limitation, called out here rather than left
## silent: unlike OrbitalBody, standing on the hull while it's moving/turning
## does NOT carry a player along (no motion_delta rider system for this one -
## that machinery is planet-specific in Player._update_planet_frame). At this
## ship's tuned cruise speed (6 m/s) and turn rate (12 deg/s) that reads as a
## faint drift underfoot rather than being thrown off, but it is a real,
## deliberate scope cut, not an oversight.
##
## Networking model: authority is always the server (peer 1 - see
## GunshipDirector._spawn_gunship, same "host is peer 1" assumption Arena.gd
## already makes for its own initial player spawn). Flight is NOT replicated:
## every peer runs the identical deterministic avoidance formula off already-
## synchronized OrbitalBody positions - the same "no network sync needed, the
## simulation just doesn't diverge enough to matter" trust every orbiting
## body in this project already relies on (OrbitalBody has no
## MultiplayerSynchronizer of its own either). health/is_destroyed/driver_id
## DO sync (MultiplayerSynchronizer) since those come from player action, not
## pure simulation, and must agree exactly across peers.

signal destroyed(gunship: Gunship)
signal driver_changed(gunship: Gunship, driver_id: int)

@export var max_health: float = 6000.0
@export var cruise_speed: float = 6.0
@export var turn_speed_degrees: float = 12.0
## Steering starts reacting this many multiples of a body's own
## (radius + influence_radius) out - big enough that a slow ship traveling at
## cruise_speed always has room to turn away before it would ever touch a
## planet's surface or a tower's structure_reach.
@export var avoidance_lookout_multiplier: float = 1.6
@export var display_name: String = "Artillery Gunship"
## How far in from each of the arena's six faces (see GravityManager.
## arena_bounds_min/max) containment steering starts pushing back inward -
## generous enough that the ship has room to actually turn at its own slow
## turn_speed_degrees before it would ever reach the real edge.
@export var boundary_containment_margin: float = 100.0

@export_group("Artillery")
@export var artillery_scene: PackedScene
@export var marker_scene: PackedScene
@export var burst_count: int = 3
@export var burst_cooldown: float = 15.0
## Multiple of Rocket.gd's own splash_radius (6.0) - see ArtilleryShell.
@export var blast_radius_multiplier: float = 5.0
@export var marker_aim_range: float = 600.0
@export var marker_spread: float = 14.0 ## how far apart the 3 painted spots land
@export var paint_to_launch_delay: float = 1.0 ## telegraph beat before shells leave the tube

var health: float = 0.0
var is_destroyed: bool = false
## Player.player_id of whoever currently holds the seat, or -1 if empty.
## Synced so every peer's HUD/mount-prompt agrees on whether the seat is free.
var driver_id: int = -1

var _velocity_dir: Vector3 = Vector3.FORWARD
var _burst_cooldown_remaining: float = 0.0
## The driver at the moment a burst was requested, captured in
## _network_request_fire_artillery and threaded through to the shells in
## _launch_burst - resolving it fresh there instead would credit whoever
## happens to be in the seat a second later (paint_to_launch_delay), which
## could be nobody if they'd already dismounted. Bounty tracking (War
## Criminal) and kill credit both depend on this actually being the Player
## who pulled the trigger, not the Gunship itself - see ArtilleryShell.launch().
var _pending_shooter: Node = null
## Set the first time this ship ever gets a driver, and never cleared - what
## distinguishes "abandoned" (had a crew, now doesn't) from "hasn't been
## boarded yet", which stays in its normal meander/stay-in-bounds mode
## instead of immediately heading for the exit the moment it spawns empty.
var _was_ever_driven: bool = false

@onready var static_body: StaticBody3D = $StaticBody3D
@onready var hull_mesh: MeshInstance3D = $StaticBody3D/Hull
@onready var seat_marker: Marker3D = $SeatMarker
@onready var muzzle_marker: Marker3D = $Muzzle
@onready var sync: MultiplayerSynchronizer = $MultiplayerSynchronizer

func _ready() -> void:
	health = max_health
	add_to_group("damageable")
	add_to_group("gunships")
	static_body.set_meta("gunship", self)
	static_body.collision_layer = 1 # world - grapple/walk/weapon-collidable, same as planets/towers
	static_body.collision_mask = 0
	_velocity_dir = -global_transform.basis.z
	_setup_replication()

func _physics_process(delta: float) -> void:
	if is_destroyed:
		return
	if driver_id != -1:
		_was_ever_driven = true
	_autopilot_steer(delta)
	_check_left_arena()
	if _burst_cooldown_remaining > 0.0:
		_burst_cooldown_remaining -= delta

## Had a driver at some point and doesn't anymore - the ship gives up and
## heads for the exit instead of continuing to meander (see _autopilot_steer),
## and GunshipDirector's spawn cooldown restarts once it's actually gone
## (_check_left_arena) exactly as if it had been destroyed. Re-manning the
## seat before it clears the boundary cancels this the very next physics
## frame - is_abandoned() is purely reactive to the current driver_id, there
## is no separate "committed to leaving" flag to un-stick.
func is_abandoned() -> bool:
	return _was_ever_driven and driver_id == -1

## Gone for good, whatever the reason: destroyed, or actually cleared the
## boundary while leaving (see is_abandoned()). Uses the real asymmetric
## per-axis box (GravityManager.is_within_boundary) rather than
## arena_half_extent() - that scalar is deliberately the TIGHTEST of the six
## faces (see its own doc comment) for callers that want one safe sphere
## radius, which in this arena is squashed down to under 100 by how thin the
## orbital disc is on the Y axis alone - useless as "has it actually left",
## it would have despawned a ship still deep in the middle of the real X/Z
## play area.
func _check_left_arena() -> void:
	if not is_abandoned():
		return
	if not GravityManager.is_within_boundary(global_position):
		if driver_id != -1:
			_broadcast_eject_driver.rpc()
		queue_free()

## Reactive steering rather than a pre-planned path, blending three pushes
## with the ship's current heading so it curves smoothly instead of snapping:
##   - obstacle avoidance, always active, pushed away from every nearby body
##     in proportion to how deep inside its "danger zone" the ship is
##   - boundary containment, active while NOT abandoned: pushes back inward
##     once within boundary_containment_margin of any of the arena's six
##     faces, which combined with obstacle avoidance is what actually
##     produces the "meanders around and stays" behaviour - nothing here
##     plans a route, it just never has anywhere safe to go except back in
##   - escape, active only while abandoned: replaces the inward containment
##     push with an outward one (straight away from the arena centre),
##     turning the exact same steering loop into "heads for open space"
##     without needing a separate pathfinding system
## Purely deterministic given the (synchronized) body positions and this
## ship's own already-agreed-on heading/driver state - no randomness, no
## divergence risk between peers.
func _autopilot_steer(delta: float) -> void:
	var avoidance: Vector3 = Vector3.ZERO
	for body in GravityManager.get_bodies():
		if not is_instance_valid(body) or body.is_shattered:
			continue
		var to_ship: Vector3 = global_position - body.global_position
		var dist: float = to_ship.length()
		var danger_radius: float = (body.radius + body.structure_reach + 20.0) * avoidance_lookout_multiplier
		if dist < danger_radius and dist > 0.01:
			var push: float = 1.0 - dist / danger_radius
			avoidance += (to_ship / dist) * push * push

	var boundary: Vector3 = _escape_push() if is_abandoned() else _containment_push()

	var desired: Vector3 = _velocity_dir + avoidance * 3.0 + boundary * 2.5
	if desired.length_squared() > 0.0001:
		desired = desired.normalized()
		var max_step: float = deg_to_rad(turn_speed_degrees) * delta
		var angle: float = _velocity_dir.angle_to(desired)
		if angle > 0.0001:
			var axis: Vector3 = _velocity_dir.cross(desired)
			if axis.length_squared() > 0.0001:
				_velocity_dir = _velocity_dir.rotated(axis.normalized(), minf(angle, max_step)).normalized()

	global_position += _velocity_dir * cruise_speed * delta
	var up_ref: Vector3 = Vector3.UP if absf(_velocity_dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	look_at(global_position + _velocity_dir, up_ref)

## Per-axis push back toward the centre once within boundary_containment_margin
## of any of the six real (asymmetric) faces - see GravityManager.
## arena_bounds_min/max, the same live per-axis box the arena boundary shell
## and spawn points already use, not the squashed single-sphere
## arena_half_extent().
func _containment_push() -> Vector3:
	var bmin: Vector3 = GravityManager.arena_bounds_min()
	var bmax: Vector3 = GravityManager.arena_bounds_max()
	var m: float = maxf(boundary_containment_margin, 1.0)
	var push := Vector3.ZERO
	push.x = _axis_containment(global_position.x, bmin.x, bmax.x, m)
	push.y = _axis_containment(global_position.y, bmin.y, bmax.y, m)
	push.z = _axis_containment(global_position.z, bmin.z, bmax.z, m)
	return push

func _axis_containment(pos: float, lo: float, hi: float, margin: float) -> float:
	if pos > hi - margin:
		return -clampf((pos - (hi - margin)) / margin, 0.0, 1.0)
	if pos < lo + margin:
		return clampf(((lo + margin) - pos) / margin, 0.0, 1.0)
	return 0.0

## Straight away from the arena centre - crude, but this ship has nowhere in
## particular it needs to arrive, just "outside", and obstacle avoidance
## above still keeps it from plowing through a planet on the way.
func _escape_push() -> Vector3:
	return global_position.normalized() if global_position.length() > 1.0 else _velocity_dir

func is_under_threat() -> bool:
	return false # not a planet - Planet Buster siren system doesn't apply here

## ---- Damage / destruction ---------------------------------------------

func apply_damage(amount: float, instigator: Node, _hit_pos: Vector3, _weapon_name: String = "") -> void:
	if is_destroyed or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	if health <= 0.0:
		_die(instigator)

@rpc("any_peer", "call_local", "reliable")
func network_apply_damage(amount: float, instigator_path: NodePath, hit_pos: Vector3, weapon_name: String) -> void:
	if not is_multiplayer_authority():
		return
	apply_damage(amount, get_node_or_null(instigator_path), hit_pos, weapon_name)

func _die(instigator: Node) -> void:
	is_destroyed = true
	health = 0.0
	if driver_id != -1:
		_broadcast_eject_driver.rpc()
	Sfx.play_3d("planet_shatter", global_position, 0.6, 2.0, 0.05)
	Sfx.play_3d("explosion", global_position, 0.8, 3.0)
	_spawn_death_fx()
	destroyed.emit(self)
	static_body.collision_layer = 0
	hull_mesh.visible = false
	var t: SceneTreeTimer = get_tree().create_timer(2.5)
	t.timeout.connect(func(): if is_instance_valid(self): queue_free())

func _spawn_death_fx() -> void:
	var particles := GPUParticles3D.new()
	get_tree().current_scene.add_child(particles)
	particles.global_position = global_position
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.UP
	mat.spread = 180.0
	mat.initial_velocity_min = 6.0
	mat.initial_velocity_max = 22.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 1.5
	mat.scale_max = 4.0
	mat.color = Color(1.0, 0.5, 0.15, 1.0)
	particles.process_material = mat
	particles.draw_pass_1 = SphereMesh.new()
	particles.amount = 48
	particles.lifetime = 1.4
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.emitting = true
	var timer := get_tree().create_timer(2.0)
	timer.timeout.connect(func(): if is_instance_valid(particles): particles.queue_free())

## ---- Driver seat --------------------------------------------------------

func has_driver() -> bool:
	return driver_id != -1

## Any peer may request this (a player walking up and pressing interact) -
## routed to the authority same as every other cross-peer game action in
## this project (see Player.network_apply_damage for the established pattern).
func request_mount(requester_path: NodePath) -> void:
	if not is_multiplayer_authority():
		rpc_id(get_multiplayer_authority(), "_network_request_mount", requester_path)
	else:
		_network_request_mount(requester_path)

@rpc("any_peer", "call_local", "reliable")
func _network_request_mount(requester_path: NodePath) -> void:
	if not is_multiplayer_authority():
		return
	if is_destroyed or has_driver():
		return
	var requester: Node = get_node_or_null(requester_path)
	if requester == null or not ("player_id" in requester):
		return
	_broadcast_set_driver.rpc(requester.player_id)

func request_dismount(requester_id: int) -> void:
	if not is_multiplayer_authority():
		rpc_id(get_multiplayer_authority(), "_network_request_dismount", requester_id)
	else:
		_network_request_dismount(requester_id)

@rpc("any_peer", "call_local", "reliable")
func _network_request_dismount(requester_id: int) -> void:
	if not is_multiplayer_authority():
		return
	if driver_id != requester_id:
		return
	_broadcast_set_driver.rpc(-1)

## Bitchslap takeover - see Melee._resolve_hit(). Forces the seat to the
## attacker regardless of who held it, after the kill has already resolved.
func force_takeover(new_driver_id: int) -> void:
	if not is_multiplayer_authority():
		rpc_id(get_multiplayer_authority(), "_network_force_takeover", new_driver_id)
	else:
		_network_force_takeover(new_driver_id)

@rpc("any_peer", "call_local", "reliable")
func _network_force_takeover(new_driver_id: int) -> void:
	if not is_multiplayer_authority():
		return
	if is_destroyed:
		return
	_broadcast_set_driver.rpc(new_driver_id)

@rpc("authority", "call_local", "reliable")
func _broadcast_set_driver(new_driver_id: int) -> void:
	driver_id = new_driver_id
	driver_changed.emit(self, driver_id)

@rpc("authority", "call_local", "reliable")
func _broadcast_eject_driver() -> void:
	driver_id = -1
	driver_changed.emit(self, driver_id)

## ---- Artillery -----------------------------------------------------------

func get_burst_cooldown_remaining() -> float:
	return _burst_cooldown_remaining

func can_fire_artillery() -> bool:
	return not is_destroyed and _burst_cooldown_remaining <= 0.0

## `aim_from`/`aim_dir` are the driver's own camera ray - only the driver's
## own client has that, so firing is requested (not simulated) on whichever
## peer holds the seat, same any_peer->authority pattern as mount/dismount.
func request_fire_artillery(requester_id: int, aim_from: Vector3, aim_dir: Vector3) -> void:
	if not is_multiplayer_authority():
		rpc_id(get_multiplayer_authority(), "_network_request_fire_artillery", requester_id, aim_from, aim_dir)
	else:
		_network_request_fire_artillery(requester_id, aim_from, aim_dir)

@rpc("any_peer", "call_local", "reliable")
func _network_request_fire_artillery(requester_id: int, aim_from: Vector3, aim_dir: Vector3) -> void:
	if not is_multiplayer_authority():
		return
	if driver_id != requester_id or not can_fire_artillery():
		return
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(aim_from, aim_from + aim_dir * marker_aim_range)
	query.collision_mask = 1
	# The seat sits right on the hull, close enough that a shallow aim angle
	# can clip the ship's own deck before the ray ever gets clear of it -
	# exclude it, the same way every weapon already excludes its own shooter.
	query.exclude = [static_body]
	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return
	var collider: Object = result.collider
	if not (collider is StaticBody3D and (collider as StaticBody3D).has_meta("orbital_body")):
		return
	var body: OrbitalBody = collider.get_meta("orbital_body")
	if not is_instance_valid(body) or body.is_shattered:
		return
	_burst_cooldown_remaining = burst_cooldown
	_pending_shooter = _find_player_node(requester_id)
	if _pending_shooter:
		BountyManager.report_gunship_strike(requester_id)
	var hit_pos: Vector3 = result.position
	var normal: Vector3 = result.normal
	var ref: Vector3 = Vector3.RIGHT if absf(normal.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var tangent_a: Vector3 = normal.cross(ref).normalized()
	var tangent_b: Vector3 = normal.cross(tangent_a).normalized()
	var marker_paths: Array[NodePath] = []
	for i in range(burst_count):
		var jitter: Vector3 = (tangent_a * randf_range(-1.0, 1.0) + tangent_b * randf_range(-1.0, 1.0)) * marker_spread
		var spot_world: Vector3 = (hit_pos + jitter)
		var spot_local: Vector3 = (spot_world - body.global_position).normalized() * body.radius
		marker_paths.append(_spawn_marker(body, spot_local))
	var t: SceneTreeTimer = get_tree().create_timer(paint_to_launch_delay)
	t.timeout.connect(_launch_burst.bind(marker_paths, _pending_shooter))

func _spawn_marker(body: OrbitalBody, local_pos: Vector3) -> NodePath:
	if marker_scene == null:
		return NodePath()
	var marker: Node3D = marker_scene.instantiate()
	body.add_child(marker)
	marker.position = local_pos
	var normal: Vector3 = local_pos.normalized()
	var ref: Vector3 = Vector3.RIGHT if absf(normal.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var bx: Vector3 = normal.cross(ref).normalized()
	var bz: Vector3 = bx.cross(normal).normalized()
	marker.transform.basis = Basis(bx, normal, bz)
	return marker.get_path()

func _launch_burst(marker_paths: Array[NodePath], shooter: Node) -> void:
	if artillery_scene == null or is_destroyed:
		return
	# Credit the driver who actually fired, not this ship - falls back to the
	# ship itself (the old, uncredited behaviour) only if they're gone by now
	# (disconnected between painting and launch; dismounting alone doesn't
	# invalidate the node, just clears driver_id).
	var credited_shooter: Node = shooter if is_instance_valid(shooter) else self
	for path in marker_paths:
		if path.is_empty():
			continue
		var marker: Node3D = get_node_or_null(path)
		if marker == null:
			continue
		var shell: ArtilleryShell = artillery_scene.instantiate()
		_get_projectile_root().add_child(shell)
		shell.global_position = muzzle_marker.global_position
		shell.blast_radius = 6.0 * blast_radius_multiplier # Rocket.splash_radius default, see ArtilleryShell doc
		shell.target_marker_path = marker.get_path()
		var up_launch: Vector3 = (muzzle_marker.global_position - global_position).normalized()
		if up_launch.length_squared() < 0.01:
			up_launch = Vector3.UP
		# Mostly straight up (the telltale artillery lob), but already leaning
		# toward the actual target rather than relying purely on _steer()'s
		# gradual ramp-up to correct a dead-vertical launch - the marked spot
		# can be several hundred metres away (the ship enters from a boundary
		# face, a target can be anywhere including near the arena centre),
		# and every second spent flying straight up first is a second not
		# spent covering that distance within the shell's own lifetime.
		var to_target: Vector3 = (marker.global_position - shell.global_position)
		var lean: Vector3 = to_target.normalized() if to_target.length() > 1.0 else up_launch
		var launch_dir: Vector3 = (up_launch * 0.7 + lean * 0.3).normalized()
		shell.launch(launch_dir * 90.0, credited_shooter)
		Sfx.play_3d("buster_fire", muzzle_marker.global_position, 0.85, 2.0, 0.04)

## Resolves a player_id to its Player node - same "players" group every other
## by-id lookup in this project uses (see Railgun._highlight_other_players).
func _find_player_node(id: int) -> Node:
	for node in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(node) and "player_id" in node and node.player_id == id:
			return node
	return null

## Mirrors Weapon._get_projectile_root() exactly (lazily creates the shared
## container rather than assuming some other weapon has already fired and
## created it first) - a Gunship can be the very first thing to spawn a
## projectile in a match.
func _get_projectile_root() -> Node:
	var root: Node = get_tree().current_scene
	var container: Node = root.get_node_or_null("Projectiles")
	if container == null:
		container = Node3D.new()
		container.name = "Projectiles"
		root.add_child(container)
	return container

func _setup_replication() -> void:
	if sync == null:
		return
	var config := SceneReplicationConfig.new()
	var on_change_props := [".:health", ".:is_destroyed", ".:driver_id"]
	for p in on_change_props:
		var path := NodePath(p)
		config.add_property(path)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	sync.replication_config = config
