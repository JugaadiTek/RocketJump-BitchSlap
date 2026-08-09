class_name Player
extends CharacterBody3D
## Shared player controller for both the local human and NPC bots (see
## scripts/ai/Bot.gd, which extends this and overrides the `_get_*` input
## hooks below instead of reading the Input singleton).
##
## Movement is a Quake3-style accelerate/friction model running in the
## tangent plane of whatever "up" the current gravity source defines, which
## is what lets players run around the outside of a sphere. The body's own
## `up_direction` is updated every physics frame from GravityManager, and the
## whole transform is smoothly re-orthogonalized to match - see
## `_align_body_to_up()`.

## ---- Tuning -----------------------------------------------------------
@export_group("Movement")
@export var max_ground_speed: float = 9.0
@export var ground_accel: float = 14.0
@export var ground_friction: float = 8.0
@export var air_accel: float = 8.0
@export var air_speed_cap: float = 15.0 ## classic Q3 "aircap" trick, lets strafe-jumping exceed max_ground_speed
## Target apex height (meters) for a normal jump. Actual jump speed is
## derived from this and the LOCAL planet's gravity each time you jump, so
## a hop feels like a consistent Quake-3 hop everywhere instead of turning
## into a moon-launch on a small/low-gravity body.
@export var jump_height: float = 1.1
@export var align_to_gravity_speed: float = 10.0 ## rad/sec, how fast the body re-levels on a new planet

@export_group("Ground Stick")
## Within this many meters of a planet's surface, an extra corrective pull
## is applied on top of normal gravity so ordinary running/jumping can never
## build up enough outward speed to skim off into orbit. Suspended briefly
## after apply_impulse() (rocket splash, melee, jump pads) so those
## launches actually carry.
@export var ground_stick_range: float = 3.0
@export var ground_stick_accel: float = 45.0
@export var impulse_grace_duration: float = 2.0

@export_group("Arena Bounds")
@export var boundary_launch_speed: float = 120.0
@export var boundary_landing_slowdown: float = 22.0 ## decel applied near the target planet's surface

@export_group("Look")
@export var mouse_sensitivity: float = 0.0025
@export var pitch_limit_degrees: float = 89.0

@export_group("Aim (ADS)")
@export var hipfire_fov_degrees: float = 88.0
@export var ads_fov_degrees: float = 45.0
@export var ads_sensitivity_multiplier: float = 0.45
@export var ads_transition_speed: float = 12.0 ## higher = snappier zoom in/out

@export_group("Health")
@export var max_health: float = 100.0
@export var respawn_delay: float = 3.0

## ---- Runtime state -----------------------------------------------------
var health: float = 100.0
var is_dead: bool = false
var is_aiming: bool = false
var current_gravity: Vector3 = Vector3.ZERO
var last_damage_instigator_path: NodePath
var _impulse_grace_remaining: float = 0.0
var _boundary_target: OrbitalBody = null  # non-null while being guided back from the boundary

## Identity for scoring/display - distinct from multiplayer_authority (a
## networking concept). Bots default to authority id 1 in offline play, same
## as the real local player, so authority alone can't tell them apart; Arena
## assigns each spawned Player/Bot a unique player_id (real peer id for
## humans, a negative id for bots) right after instancing it.
var player_id: int = -1
var display_name: String = "Player"

var _mouse_delta := Vector2.ZERO
var _pending_weapon_scroll: int = 0
var _has_aligned_once := false
var _default_collision_layer: int
var _default_collision_mask: int
var _prev_edge_states: Dictionary = {}

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var muzzle: Marker3D = $Head/Camera3D/Muzzle
@onready var weapon_manager: Node3D = $Head/Camera3D/WeaponManager
@onready var melee: Node = $Melee
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var model: Node3D = $Model
@onready var sync: MultiplayerSynchronizer = $MultiplayerSynchronizer

var hud: CanvasLayer = null

func _ready() -> void:
	health = max_health
	_default_collision_layer = collision_layer
	_default_collision_mask = collision_mask
	add_to_group("players")
	add_to_group("damageable")
	_setup_replication()
	# is_multiplayer_authority() means "this peer simulates this body" - true
	# for bots too (they're simulated locally/by the host). _is_local_view()
	# separately means "this is the human sitting at THIS screen", which
	# Bot.gd overrides to always be false. Without that second check, bots
	# would default to the same authority id as the real player in offline
	# play and each spawn their own camera/HUD/mouse-capture.
	if is_multiplayer_authority() and _is_local_view():
		if camera:
			camera.current = true
			camera.fov = hipfire_fov_degrees
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_setup_hud()
	else:
		if camera:
			camera.current = false
		if weapon_manager:
			weapon_manager.visible = false

## True for the human-controlled local view; Bot overrides this to false. Not
## to be confused with is_multiplayer_authority(), which controls whether
## movement/combat logic runs on this peer and must stay true for bots.
func _is_local_view() -> bool:
	return true

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if not _uses_mouse_look():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_delta += event.relative
	if event is InputEventMouseButton and event.pressed:
		# Scroll wheel clicks are transient (no sustained "held" state), so
		# they have to be caught here rather than polled in _get_weapon_scroll().
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_pending_weapon_scroll += 1
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_pending_weapon_scroll -= 1
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

## True for the human-controlled subclass usage; Bot overrides this to false
## so it doesn't fight the mouse-delta based look with its own aim logic.
func _uses_mouse_look() -> bool:
	return true

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	if is_dead:
		return

	current_gravity = GravityManager.get_gravity_at(global_position)
	var new_up: Vector3 = -current_gravity.normalized() if current_gravity.length() > 0.0001 else up_direction
	_align_body_to_up(new_up, delta)
	up_direction = new_up

	if _impulse_grace_remaining > 0.0:
		_impulse_grace_remaining -= delta
	else:
		_apply_ground_stick(delta)
	_apply_arena_bounds()

	_apply_aim(delta)
	_apply_look(delta)
	_apply_movement(new_up, delta)

	if _wants_melee():
		melee.try_activate()
	weapon_manager.handle_input(delta, _wants_fire(), _get_weapon_switch(), _get_weapon_scroll())

	if hud:
		hud.update_health(health, max_health)
		hud.update_weapons(weapon_manager.get_weapon_names(), weapon_manager.get_weapon_colors(), weapon_manager.get_current_index())
		hud.update_kills(MatchState.get_score(player_id))
		hud.update_scoreboard(_wants_scoreboard(), MatchState.get_all_scores())
		# Charge bar: visible only when the active weapon supports it
		var active_weapon = weapon_manager._weapons[weapon_manager.get_current_index()] if not weapon_manager._weapons.is_empty() else null
		if active_weapon and active_weapon.has_method("get_charge"):
			hud.update_charge_bar(active_weapon.get_charge(), true)
		else:
			hud.update_charge_bar(0.0, false)

## Extra corrective pull toward the nearest planet's center whenever close
## to its surface, so normal running/jumping can't accumulate enough
## outward speed to skim off into an accidental orbit (see class doc). Not
## applied while _impulse_grace_remaining is active.
func _apply_ground_stick(delta: float) -> void:
	var body: OrbitalBody = GravityManager.get_nearest_body(global_position)
	if body == null or body.is_shattered:
		return
	var dist_to_surface: float = global_position.distance_to(body.global_position) - body.radius
	if dist_to_surface > ground_stick_range:
		return
	var to_center: Vector3 = (body.global_position - global_position)
	if to_center.length_squared() < 0.0001:
		return
	velocity += to_center.normalized() * ground_stick_accel * delta

## Distance from the nearest planet's surface, or INF if there's no body at
## all (shouldn't happen in this arena, but keeps callers safe).
func _distance_to_nearest_surface() -> float:
	var body: OrbitalBody = GravityManager.get_nearest_body(global_position)
	if body == null or body.is_shattered:
		return INF
	return global_position.distance_to(body.global_position) - body.radius

## Hard edge of the arena. Two phases:
##   LAUNCH  — first frame outside the boundary: snap velocity to a fast
##             straight shot aimed at the nearest planet's center. The
##             impulse grace exempts this from ground-stick so it carries.
##   GUIDE   — every subsequent frame: steer the velocity vector to track
##             the (moving) planet as it orbits, so the player arrives even
##             if the planet moved significantly during the transit.
##   LAND    — once within landing_range of the surface, smoothly decelerate
##             to a safe touchdown speed and clear _boundary_target so normal
##             movement resumes.
func _apply_arena_bounds() -> void:
	const LANDING_RANGE: float = 18.0   # metres from surface, start decelerating
	const LANDING_SPEED: float = 10.0   # speed to decelerate toward during landing

	if global_position.length() > GravityManager.ARENA_BOUNDARY_RADIUS:
		if _boundary_target == null:
			# First frame outside - choose target and launch
			_boundary_target = GravityManager.get_nearest_body(global_position)
		if _boundary_target == null or _boundary_target.is_shattered:
			_boundary_target = null
			return
		var to_target: Vector3 = _boundary_target.global_position - global_position
		if to_target.length_squared() < 0.0001:
			return
		velocity = to_target.normalized() * boundary_launch_speed
		_impulse_grace_remaining = max(_impulse_grace_remaining, impulse_grace_duration)
		return

	# Inside boundary - if we have an active target we're mid-flight; keep guiding
	if _boundary_target == null:
		return
	if _boundary_target.is_shattered:
		_boundary_target = null
		return

	var to_target: Vector3 = _boundary_target.global_position - global_position
	var dist_to_surface: float = to_target.length() - _boundary_target.radius

	if dist_to_surface <= LANDING_RANGE:
		# Managed landing: progressively decelerate toward landing speed to
		# avoid slamming full-speed into the surface. Once nearly touching
		# the surface influence zone, clear the override and let normal
		# physics take over.
		var t: float = clamp(dist_to_surface / LANDING_RANGE, 0.0, 1.0)
		var desired_speed: float = lerp(LANDING_SPEED, boundary_launch_speed * 0.6, t)
		var dir: Vector3 = to_target.normalized()
		velocity = velocity.lerp(dir * desired_speed, clamp(boundary_landing_slowdown * get_physics_process_delta_time(), 0.0, 1.0))
		move_and_slide()
		if dist_to_surface <= ground_stick_range * 1.5:
			_boundary_target = null
	else:
		# Mid-flight: keep steering toward the (orbiting) target. Using
		# slerp on the direction instead of a hard set means gradual
		# course corrections are smooth rather than abrupt snaps.
		var current_speed: float = max(velocity.length(), boundary_launch_speed)
		var desired_dir: Vector3 = to_target.normalized()
		var current_dir: Vector3 = velocity.normalized() if velocity.length() > 0.1 else desired_dir
		var steered_dir: Vector3 = current_dir.slerp(desired_dir, 0.18)
		velocity = steered_dir.normalized() * current_speed
		move_and_slide()

## Right-click ADS: smoothly zooms the camera FOV and (via _apply_look)
## drops mouse sensitivity to match, like a standard FPS aim-down-sights.
func _apply_aim(delta: float) -> void:
	is_aiming = _wants_aim()
	if camera == null:
		return
	var target_fov: float = ads_fov_degrees if is_aiming else hipfire_fov_degrees
	var t: float = clamp(ads_transition_speed * delta, 0.0, 1.0)
	camera.fov = lerp(camera.fov, target_fov, t)

func _align_body_to_up(new_up: Vector3, delta: float) -> void:
	var current_up: Vector3 = global_transform.basis.y
	if not _has_aligned_once:
		# Snap instantly on spawn so we don't visibly tip over on load.
		_has_aligned_once = true
		if current_up.dot(new_up) < 0.9999:
			var axis: Vector3 = current_up.cross(new_up)
			if axis.length_squared() < 0.000001:
				axis = global_transform.basis.x
			axis = axis.normalized()
			var q := Quaternion(axis, current_up.angle_to(new_up))
			global_transform.basis = (Basis(q) * global_transform.basis).orthonormalized()
		return
	if current_up.dot(new_up) > 0.999999:
		return
	var rotation_axis: Vector3 = current_up.cross(new_up)
	if rotation_axis.length_squared() < 0.000001:
		rotation_axis = global_transform.basis.x
	rotation_axis = rotation_axis.normalized()
	var angle_to_target: float = current_up.angle_to(new_up)
	var max_angle_this_frame: float = align_to_gravity_speed * delta
	var t: float = min(angle_to_target, max_angle_this_frame)
	var q := Quaternion(rotation_axis, t)
	global_transform.basis = (Basis(q) * global_transform.basis).orthonormalized()

func _apply_look(_delta: float) -> void:
	var look: Vector2 = _get_look_delta()
	if look == Vector2.ZERO:
		return
	var sensitivity: float = mouse_sensitivity * (ads_sensitivity_multiplier if is_aiming else 1.0)
	rotate_object_local(Vector3.UP, -look.x * sensitivity)
	var pitch_limit: float = deg_to_rad(pitch_limit_degrees)
	head.rotation.x = clamp(head.rotation.x - look.y * sensitivity, -pitch_limit, pitch_limit)

func _apply_movement(up: Vector3, delta: float) -> void:
	# While being guided home from the boundary, normal player input doesn't
	# steer - _apply_arena_bounds() owns the velocity entirely until landing.
	if _boundary_target != null:
		return

	var forward: Vector3 = -global_transform.basis.z
	var right: Vector3 = global_transform.basis.x

	var move_axis: Vector2 = _get_move_axis()
	if move_axis.length() > 1.0:
		move_axis = move_axis.normalized()
	var wish_dir: Vector3 = (forward * move_axis.y + right * move_axis.x)
	if wish_dir.length_squared() > 0.0001:
		wish_dir = wish_dir.normalized()

	var vel_up: float = velocity.dot(up)
	var vel_horizontal: Vector3 = velocity - up * vel_up

	if is_on_floor():
		vel_horizontal = _apply_friction(vel_horizontal, ground_friction, delta)
		vel_horizontal = _q3_accelerate(wish_dir, max_ground_speed, ground_accel, vel_horizontal, delta)
		if _wants_jump():
			var g_mag: float = max(current_gravity.length(), 4.0)
			vel_up = sqrt(2.0 * g_mag * jump_height)
	else:
		vel_horizontal = _q3_air_accelerate(wish_dir, max_ground_speed, air_accel, air_speed_cap, vel_horizontal, delta)

	vel_up += current_gravity.dot(up) * delta
	velocity = vel_horizontal + up * vel_up
	move_and_slide()

func _apply_friction(vel: Vector3, friction: float, delta: float) -> Vector3:
	var speed: float = vel.length()
	if speed < 0.001:
		return Vector3.ZERO
	var drop: float = speed * friction * delta
	var new_speed: float = max(speed - drop, 0.0)
	return vel * (new_speed / speed)

func _q3_accelerate(wish_dir: Vector3, wish_speed: float, accel: float, vel: Vector3, delta: float) -> Vector3:
	var current_speed: float = vel.dot(wish_dir)
	var add_speed: float = wish_speed - current_speed
	if add_speed <= 0.0:
		return vel
	var accel_speed: float = min(accel * wish_speed * delta, add_speed)
	return vel + wish_dir * accel_speed

## The classic Q3 "PM_AirAccelerate": the wishspeed used to compute how much
## speed we're allowed to *add* is capped (air_speed_cap), but the magnitude
## of the acceleration itself still uses the full wish_speed. That mismatch
## is exactly what makes disciplined strafe-jumping gain speed over time.
func _q3_air_accelerate(wish_dir: Vector3, wish_speed: float, accel: float, speed_cap: float, vel: Vector3, delta: float) -> Vector3:
	var capped_wish_speed: float = min(wish_speed, speed_cap)
	var current_speed: float = vel.dot(wish_dir)
	var add_speed: float = capped_wish_speed - current_speed
	if add_speed <= 0.0:
		return vel
	var accel_speed: float = min(accel * wish_speed * delta, add_speed)
	return vel + wish_dir * accel_speed

## ---- Input hooks (override in Bot.gd) -------------------------------------
## These read hardware state directly (Input.is_physical_key_pressed /
## is_mouse_button_pressed) instead of named InputMap actions. Named actions
## depend on project.godot's [input] section parsing correctly - which is a
## hand-authored resource format that's sensitive to exact Godot-build
## property sets and can silently fail on a different engine version - so
## gameplay-critical input intentionally does not depend on it at all here.
## WASD / Space / F / number keys / mouse buttons are effectively hardcoded;
## remapping them means editing the keycodes below.
func _get_move_axis() -> Vector2:
	return Vector2(
		(1.0 if Input.is_physical_key_pressed(KEY_D) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_A) else 0.0),
		(1.0 if Input.is_physical_key_pressed(KEY_W) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_S) else 0.0)
	)

func _get_look_delta() -> Vector2:
	var d := _mouse_delta
	_mouse_delta = Vector2.ZERO
	return d

func _wants_jump() -> bool:
	return Input.is_physical_key_pressed(KEY_SPACE)

func _wants_fire() -> bool:
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

func _wants_aim() -> bool:
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)

func _wants_scoreboard() -> bool:
	return Input.is_physical_key_pressed(KEY_TAB)

func _wants_melee() -> bool:
	return _just_pressed("melee", Input.is_physical_key_pressed(KEY_F))

func _get_weapon_switch() -> int:
	if _just_pressed("wpn0", Input.is_physical_key_pressed(KEY_1)):
		return 0
	if _just_pressed("wpn1", Input.is_physical_key_pressed(KEY_2)):
		return 1
	if _just_pressed("wpn2", Input.is_physical_key_pressed(KEY_3)):
		return 2
	if _just_pressed("wpn3", Input.is_physical_key_pressed(KEY_4)):
		return 3
	return -1

## Returns -1 / 0 / +1: scroll-wheel weapon cycling, layered on top of the
## direct number-key switch above. Fed by _unhandled_input(), since wheel
## clicks are transient events rather than a sustained "held" state.
func _get_weapon_scroll() -> int:
	var s: int = sign(_pending_weapon_scroll)
	_pending_weapon_scroll = 0
	return s

## Manual edge-detection helper ("was this false last frame, true now") for
## the raw-polled keys above, replacing what Input.is_action_just_pressed()
## would normally give for free with a named action.
func _just_pressed(id: String, pressed_now: bool) -> bool:
	var was_pressed: bool = _prev_edge_states.get(id, false)
	_prev_edge_states[id] = pressed_now
	return pressed_now and not was_pressed

## ---- Combat --------------------------------------------------------------

## Direct velocity change - used for rocket-jump splash, bitchslap launches,
## and jump pads. Grants a brief exemption from ground-stick (see
## _apply_ground_stick) so the launch actually carries instead of being
## immediately corrected back down while still near the surface.
func apply_impulse(force: Vector3) -> void:
	if is_dead:
		return
	velocity += force
	_impulse_grace_remaining = impulse_grace_duration

@rpc("any_peer", "call_local", "reliable")
func network_apply_impulse(force: Vector3) -> void:
	if not is_multiplayer_authority():
		return
	apply_impulse(force)

func apply_damage(amount: float, instigator: Node, _hit_pos: Vector3, weapon_name: String = "") -> void:
	if is_dead or amount <= 0.0:
		return
	health -= amount
	if instigator:
		last_damage_instigator_path = instigator.get_path()
	if health <= 0.0:
		_die(instigator, weapon_name)

@rpc("any_peer", "call_local", "reliable")
func network_apply_damage(amount: float, instigator_path: NodePath, hit_pos: Vector3, weapon_name: String) -> void:
	if not is_multiplayer_authority():
		return
	var instigator: Node = get_node_or_null(instigator_path)
	apply_damage(amount, instigator, hit_pos, weapon_name)

func _die(instigator: Node, weapon_name: String) -> void:
	is_dead = true
	health = 0.0
	velocity = Vector3.ZERO
	visible = false
	collision_layer = 0
	collision_mask = 1 # still collides with world/planets so we don't fall through, but hits nothing else
	var killer_id: int = -1
	if instigator and "player_id" in instigator:
		killer_id = instigator.player_id
	MatchState.report_frag(player_id, killer_id, weapon_name)
	await get_tree().create_timer(respawn_delay).timeout
	_respawn()

func _respawn() -> void:
	var sp: Node3D = MatchState.get_random_spawn_point()
	if sp:
		global_position = sp.global_position
		global_transform.basis = sp.global_transform.basis
		_has_aligned_once = false
	health = max_health
	is_dead = false
	visible = true
	collision_layer = _default_collision_layer
	collision_mask = _default_collision_mask
	velocity = Vector3.ZERO

func get_look_direction() -> Vector3:
	return -camera.global_transform.basis.z

func get_muzzle_transform() -> Transform3D:
	return muzzle.global_transform

func grant_weapon(id: String) -> void:
	weapon_manager.grant_weapon(id)

const HUD_SCENE: PackedScene = preload("res://scenes/ui/HUD.tscn")

func _setup_hud() -> void:
	hud = HUD_SCENE.instantiate()
	add_child(hud)

## Sets up what gets replicated to other peers. Position/rotation/velocity
## sync continuously so remote players look reasonably smooth; health and
## death state only sync on change since they're infrequent and reliable.
func _setup_replication() -> void:
	if sync == null:
		return
	var config := SceneReplicationConfig.new()
	var always_props := [".:transform", ".:velocity"]
	var on_change_props := [".:health", ".:is_dead", ".:visible"]
	for p in always_props:
		var path := NodePath(p)
		config.add_property(path)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	for p in on_change_props:
		var path := NodePath(p)
		config.add_property(path)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	sync.replication_config = config
