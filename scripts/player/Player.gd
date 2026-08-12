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
## How fast the *target* up itself eases toward a new one, in 1/sec. Entering a
## planet's well swaps the reference for "up" from summed gravity to that
## planet's radial direction, which is a step change; easing the target as well
## as the body's rotation turns that step into a glide. Lower = gentler.
@export var up_blend_rate: float = 4.5

@export_group("Ground Stick")
## Within this many meters of a planet's surface, an extra corrective pull
## is applied on top of normal gravity so ordinary running/jumping can never
## build up enough outward speed to skim off into orbit. Suspended briefly
## after apply_impulse() (rocket splash, melee, jump pads) so those
## launches actually carry.
@export var ground_stick_range: float = 3.0
@export var ground_stick_accel: float = 45.0
@export var impulse_grace_duration: float = 2.0

@export_group("Planet Frame")
## Height above a planet's surface within which that planet becomes the
## player's reference frame: the player is carried by its orbit and spin, and
## `velocity` is stored relative to it. Planets here travel at up to ~12 m/s -
## faster than max_ground_speed - so without this the surface slides out from
## under you and the leading hemisphere behaves like a moving wall.
@export var planet_frame_height: float = 26.0
## The frame is only released past `planet_frame_height * this`, so a player
## hovering right at the edge (or midway between two close bodies) doesn't
## flip-flop between frames every frame.
@export var planet_frame_release_ratio: float = 1.4

@export_group("Ladders")
## Inside a building's Ladder volume, movement switches to climbing along the
## ladder's own axis: forward/back (or jump/crouch) climbs, strafe slides you
## off onto a floor.
@export var ladder_climb_speed: float = 4.5
@export var ladder_lateral_speed: float = 2.5

@export_group("Space Board")
## Free-flight tuning, used while the Space Board is the selected weapon
## (see _apply_flight_movement).
@export var board_accel: float = 42.0
@export var board_max_speed: float = 60.0
@export var board_damping: float = 1.6
@export var board_gravity_scale: float = 0.12

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
## Height above the player's feet, along their own up axis, at which a hit counts
## as a headshot. Matches the head sphere in Player.tscn (centre 1.68, r 0.28).
@export var head_shot_height: float = 1.42
@export var head_shot_multiplier: float = 3.0
@export var respawn_delay: float = 3.0

## ---- Runtime state -----------------------------------------------------
var health: float = 100.0
var is_dead: bool = false
var is_aiming: bool = false
var current_gravity: Vector3 = Vector3.ZERO
var last_damage_instigator_path: NodePath
var _impulse_grace_remaining: float = 0.0
## The planet whose reference frame we're currently riding, and that frame's
## world velocity at our position. While _frame_body is set, `velocity` is
## RELATIVE to it - use get_world_velocity() for anything that needs world space.
var _frame_body: OrbitalBody = null
var _platform_velocity: Vector3 = Vector3.ZERO
## The Ladder volume we're currently standing in, if any (set by Ladder.gd).
var _ladder: Node3D = null
## Eased "up", chasing the raw target from _get_up_direction() - see _smoothed_up.
var _up_smoothed: Vector3 = Vector3.ZERO
var _was_grounded: bool = true
var _airborne_speed: float = 0.0

## Grappling cable state, written by GrapplingHook and read by HookVisual.
## Replicated (see _setup_replication) so everyone can see who is grappling
## what, not just the person holding the hook.
var hook_active: bool = false
var hook_end: Vector3 = Vector3.ZERO

## Which weapon this player has out. Replicated so WeaponModel can show everyone
## else what they're carrying - handle_input() only runs on the authority, so a
## remote player's own WeaponManager would never switch on its own.
var current_weapon_index: int = 0

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
var _spawner: Node = null

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
	if is_multiplayer_authority():
		_start_spawn_sequence()

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
	_update_planet_frame(delta)
	var new_up: Vector3 = _smoothed_up(delta)
	_align_body_to_up(new_up, delta)
	up_direction = new_up

	var flying: bool = _is_flight_mode()
	var climbing: bool = _is_on_ladder() and not flying
	if _impulse_grace_remaining > 0.0:
		_impulse_grace_remaining -= delta
	elif not flying and not climbing:
		_apply_ground_stick(delta)
	_apply_arena_bounds()

	_apply_aim(delta)
	_apply_look(delta)
	if flying:
		_apply_flight_movement(new_up, delta)
	elif climbing:
		_apply_ladder_movement(delta)
	else:
		_apply_movement(new_up, delta)

	if _wants_melee():
		melee.try_activate()
	if not _is_spawning():
		weapon_manager.handle_input(delta, _wants_fire(), _get_weapon_switch(), _get_weapon_scroll())

	if hud:
		hud.update_health(health, max_health)
		hud.update_weapons(weapon_manager.get_weapon_names(), weapon_manager.get_weapon_colors(), weapon_manager.get_current_index())
		hud.update_kills(MatchState.get_score(player_id))
		hud.update_scoreboard(_wants_scoreboard(), MatchState.get_all_scores())
		# Charge bar: visible only when the active weapon supports it
		var active_weapon: Weapon = weapon_manager.get_active_weapon()
		if active_weapon and active_weapon.has_method("get_charge"):
			hud.update_charge_bar(active_weapon.get_charge(), true)
		else:
			hud.update_charge_bar(0.0, false)
		hud.update_scope(active_weapon != null and active_weapon.has_method("is_scoped") and active_weapon.is_scoped())
		# Planet buster lock-on indicator
		if active_weapon and active_weapon is PlanetBuster:
			hud.update_lock_indicator(active_weapon.get_aimed_candidate(), active_weapon.get_lock_target(), active_weapon.get_lock_progress())
		else:
			hud.update_lock_indicator(null, null, 0.0)
		# Spawn aim window
		if _is_spawning() and _spawner:
			pass  # Spawner calls hud.update_spawn_aim directly
		else:
			hud.hide_spawn_aim()

## Picks the planet we're currently "on" and rides it.
##
## Planets in this arena orbit at up to ~12 m/s and spin on top of that, while
## max_ground_speed is 9 - and a StaticBody3D that is teleported each frame
## gives CharacterBody3D no platform velocity at all. Left alone that produces
## every one of the surface bugs at once: the ground slides out from under a
## standing player, the leading hemisphere shoves into them like an invisible
## wall they can't out-run, and the repeated depenetration reads as bouncing.
##
## So while within `planet_frame_height` of a body's surface we treat that body
## as the local inertial frame: the player's whole transform is carried by the
## planet's per-frame rigid motion, and `velocity` is stored relative to the
## planet rather than to the world. Handing over between frames adds/removes the
## frame velocity so world momentum stays continuous (a Galilean shift, so
## impulses and gravity need no adjustment).
func _update_planet_frame(delta: float) -> void:
	var body: OrbitalBody = GravityManager.get_nearest_body(global_position)
	if body != null:
		# Hysteresis: hold on to the frame we already have a little past the
		# acquire range so a player hovering at the edge, or sitting midway
		# between two close bodies, doesn't flip frames every frame.
		var limit: float = planet_frame_height
		if body == _frame_body:
			limit *= planet_frame_release_ratio
		if (global_position.distance_to(body.global_position) - body.radius) > limit:
			body = null

	if body != _frame_body:
		if _frame_body != null and is_instance_valid(_frame_body):
			velocity += _frame_body.get_point_velocity(global_position)
		_frame_body = body
		if _frame_body != null:
			velocity -= _frame_body.get_point_velocity(global_position)

	if _frame_body == null:
		_platform_velocity = Vector3.ZERO
		return

	_platform_velocity = _frame_body.get_point_velocity(global_position)
	var carried: Transform3D = _frame_body.motion_delta * global_transform
	carried.basis = carried.basis.orthonormalized()
	global_transform = carried

## World-space velocity, i.e. `velocity` plus the motion of the planet whose
## frame we're riding. Anything that leaves the player and lives in world space
## (projectiles inheriting muzzle velocity, AI lead prediction) wants this, not
## the frame-relative `velocity`.
func get_world_velocity() -> Vector3:
	return velocity + _platform_velocity

## Inverse of get_world_velocity(): assign a world-space velocity, converting it
## into the current planet frame.
func set_world_velocity(world_velocity: Vector3) -> void:
	velocity = world_velocity - _platform_velocity

## "Up" is the radial direction away from the planet we're standing on, not the
## direction of summed gravity. Those differ wherever a second body's influence
## overlaps (moons, and the Alpha/Beta binary), and a tilted up_direction makes
## CharacterBody3D classify the sphere underfoot as a wall past floor_max_angle -
## which is felt as an invisible wall partway around a planet. Falls back to
## gravity in open space, where there's no surface to be radial to.
## The up we actually use, eased toward the raw target rather than snapped to
## it. Crossing into a planet's influence swaps the definition of "up" from
## summed gravity to that planet's radial direction in a single frame; feeding
## that step straight into up_direction and _align_body_to_up() is what made
## entering a gravity well jolt. Easing here means the body's re-levelling
## chases a target that is itself already moving smoothly.
func _smoothed_up(delta: float) -> Vector3:
	var target: Vector3 = _get_up_direction()
	if not _has_aligned_once or _up_smoothed.length_squared() < 0.0001:
		_up_smoothed = target
		return target
	# Exponential approach: frame-rate independent, and eases out naturally as
	# it converges instead of stopping dead like a constant-rate turn.
	var t: float = 1.0 - exp(-up_blend_rate * delta)
	if _up_smoothed.dot(target) < -0.9999:
		# Exactly antipodal - slerp has no defined arc, so nudge off the pole.
		_up_smoothed = (_up_smoothed + global_transform.basis.x * 0.01).normalized()
	_up_smoothed = _up_smoothed.slerp(target, t).normalized()
	return _up_smoothed

func _get_up_direction() -> Vector3:
	if _frame_body != null and is_instance_valid(_frame_body) and not _frame_body.is_shattered:
		var radial: Vector3 = global_position - _frame_body.global_position
		if radial.length_squared() > 0.0001:
			return radial.normalized()
	if current_gravity.length() > 0.0001:
		return -current_gravity.normalized()
	return up_direction

## True while the Space Board is out, which swaps the grounded Q3 movement model
## for free 6-axis flight (see _apply_flight_movement).
func _is_flight_mode() -> bool:
	if is_dead or _is_spawning():
		return false
	var active: Weapon = weapon_manager.get_active_weapon() if weapon_manager else null
	return active != null and active.has_method("is_flight_active") and active.is_flight_active()

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

## Hard edge of the arena. Crossing it hands the player straight to the Spawner,
## which flings them at a randomly chosen planet on the same trailed launch a
## respawn uses - no aim window, no choice.
##
## The previous version steered velocity itself and returned early, while
## _apply_movement ALSO returned early because a boundary target was set. Between
## them nothing ever called move_and_slide(), so a player who touched the edge
## simply stopped dead there and stayed stuck.
func _apply_arena_bounds() -> void:
	if global_position.length() <= GravityManager.ARENA_BOUNDARY_RADIUS:
		return
	if _spawner == null or _is_spawning():
		return
	_spawner.start_boundary_return(self)

## Right-click ADS: smoothly zooms the camera FOV and (via _apply_look)
## drops mouse sensitivity to match, like a standard FPS aim-down-sights.
func _apply_aim(delta: float) -> void:
	is_aiming = _wants_aim()
	if camera == null:
		return
	# A weapon with its own optic (the railgun scope) owns the FOV while it's
	# out; running the generic ADS zoom too would make the two lerps fight.
	var active: Weapon = weapon_manager.get_active_weapon() if weapon_manager else null
	if active and active.overrides_aim_fov():
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
	# Exponential approach rather than a flat rad/sec sweep: a constant-rate turn
	# arrives at full speed and stops dead, which is the jolt you feel landing on
	# a new planet. This eases out into alignment, and is still capped by
	# align_to_gravity_speed for very large reorientations.
	var eased: float = angle_to_target * (1.0 - exp(-align_to_gravity_speed * delta))
	var t: float = min(angle_to_target, maxf(eased, 0.0))
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
	var forward: Vector3 = -global_transform.basis.z
	var right: Vector3 = global_transform.basis.x

	var move_axis: Vector2 = _get_move_axis()
	if move_axis.length() > 1.0:
		move_axis = move_axis.normalized()
	# Flatten the wish direction into the tangent plane. The body's basis lags
	# the true "up" slightly (it re-levels at align_to_gravity_speed), so on a
	# curved surface `forward` tilts off the tangent - and feeding that straight
	# into the accelerate step injects an outward component into the horizontal
	# velocity, which pops the player off the ground as a steady bounce.
	var wish_dir: Vector3 = (forward * move_axis.y + right * move_axis.x)
	wish_dir -= up * wish_dir.dot(up)
	if wish_dir.length_squared() > 0.0001:
		wish_dir = wish_dir.normalized()
	else:
		wish_dir = Vector3.ZERO

	var vel_up: float = velocity.dot(up)
	var vel_horizontal: Vector3 = velocity - up * vel_up

	# Landing thump, scaled by impact speed. Tracked here rather than from
	# is_on_floor() alone so a hard rocket-jump landing sounds different from
	# stepping off a kerb.
	var grounded: bool = is_on_floor()
	if grounded and not _was_grounded and _airborne_speed > 6.0:
		# Ceiling trimmed from +2 to 0 - see OrbitalBody.shatter()'s
		# planet_shatter call for why headroom on top of an already
		# near-full-scale synthesised sound matters.
		Sfx.play_3d("land", global_position, 1.0, clampf(-18.0 + _airborne_speed * 0.5, -18.0, 0.0))
	_was_grounded = grounded
	_airborne_speed = 0.0 if grounded else maxf(_airborne_speed, absf(vel_up))

	if is_on_floor():
		vel_horizontal = _apply_friction(vel_horizontal, ground_friction, delta)
		vel_horizontal = _q3_accelerate(wish_dir, max_ground_speed, ground_accel, vel_horizontal, delta)
		if _wants_jump():
			var g_mag: float = max(current_gravity.length(), 4.0)
			vel_up = sqrt(2.0 * g_mag * jump_height)
			Sfx.play_3d("jump", global_position, 1.0, -12.0)
		else:
			# Discard any leftover outward speed while grounded. Running over a
			# curved, moving surface keeps generating small positive vel_up from
			# collision response; without this it accumulates into a hop.
			vel_up = min(vel_up, 0.0)
	else:
		vel_horizontal = _q3_air_accelerate(wish_dir, max_ground_speed, air_accel, air_speed_cap, vel_horizontal, delta)

	vel_up += current_gravity.dot(up) * delta
	velocity = vel_horizontal + up * vel_up
	move_and_slide()

## Space Board flight: full 6-axis freedom instead of the tangent-plane ground
## model. WASD thrusts along the camera's own axes (so looking up and holding
## forward climbs), jump/crouch thrust along the current up, and gravity is
## nearly cancelled so a held direction actually holds. Drag rather than a hard
## speed clamp does most of the limiting, which keeps steering responsive.
func _apply_flight_movement(up: Vector3, delta: float) -> void:
	var cam_basis: Basis = camera.global_transform.basis if camera else global_transform.basis
	var move_axis: Vector2 = _get_move_axis()
	if move_axis.length() > 1.0:
		move_axis = move_axis.normalized()

	var wish: Vector3 = (-cam_basis.z) * move_axis.y + cam_basis.x * move_axis.x
	var vertical: float = (1.0 if _wants_jump() else 0.0) - (1.0 if _wants_descend() else 0.0)
	wish += up * vertical
	if wish.length_squared() > 1.0:
		wish = wish.normalized()

	velocity += wish * board_accel * delta
	velocity += current_gravity * board_gravity_scale * delta
	velocity = _apply_friction(velocity, board_damping, delta)
	if velocity.length() > board_max_speed:
		velocity = velocity.normalized() * board_max_speed
	move_and_slide()

## ---- Ladders --------------------------------------------------------------
## Called by Ladder.gd as we enter/leave a building's climb volume.
func set_ladder(ladder: Node3D) -> void:
	_ladder = ladder

func clear_ladder(ladder: Node3D) -> void:
	if _ladder == ladder:
		_ladder = null

func _is_on_ladder() -> bool:
	if is_dead or _is_spawning():
		return false
	return _ladder != null and is_instance_valid(_ladder)

## Climbing suspends gravity entirely and drives velocity straight from input
## along the ladder's own axis - a Q3 accelerate model would just slide you off
## the rungs. Strafing still works so you can step out onto a floor, and the
## planet-frame carry keeps the ladder under you as its planet orbits.
func _apply_ladder_movement(delta: float) -> void:
	var axis: Vector3 = _ladder.global_transform.basis.y.normalized()
	var move: Vector2 = _get_move_axis()
	var climb: float = move.y
	if _wants_jump():
		climb = 1.0
	elif _wants_descend():
		climb = -1.0

	var lateral: Vector3 = global_transform.basis.x * move.x * ladder_lateral_speed
	lateral -= axis * lateral.dot(axis)
	velocity = axis * climb * ladder_climb_speed + lateral
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
## WASD / Space / V / number keys / mouse buttons are effectively hardcoded;
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

## Space Board only: thrust "down" along the current up direction.
func _wants_descend() -> bool:
	return Input.is_physical_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_C)

func _wants_fire() -> bool:
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

func _wants_aim() -> bool:
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)

func _wants_scoreboard() -> bool:
	return Input.is_physical_key_pressed(KEY_TAB)

func _wants_melee() -> bool:
	return _just_pressed("melee", Input.is_physical_key_pressed(KEY_V))

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

func apply_damage(amount: float, instigator: Node, hit_pos: Vector3, weapon_name: String = "") -> void:
	if is_dead or amount <= 0.0:
		return
	var headshot: bool = is_headshot(hit_pos)
	if headshot:
		amount *= head_shot_multiplier
	health -= amount
	if instigator:
		last_damage_instigator_path = instigator.get_path()
	if health <= 0.0:
		_die(instigator, weapon_name)

## A hit counts as a headshot by its height along this player's own up axis,
## rather than by which collider was struck: the body is one CharacterBody3D
## with two shapes, and Godot's move/raycast results don't say which shape of a
## multi-shape body was hit.
func is_headshot(hit_pos: Vector3) -> bool:
	if hit_pos == Vector3.ZERO:
		return false
	return (hit_pos - global_position).dot(up_direction) >= head_shot_height

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
	_spawn_death_effect()
	await get_tree().create_timer(respawn_delay).timeout
	_respawn()

const DEATH_EFFECT := preload("res://scripts/world/DeathEffect.gd")

## Comic-book kill marker dropped at the spot we fell.
func _spawn_death_effect() -> void:
	var effect := DEATH_EFFECT.new()
	var root: Node = get_tree().current_scene
	if root == null:
		return
	root.add_child(effect)
	effect.global_position = global_position
	effect.setup(display_name, up_direction)

func _respawn() -> void:
	health = max_health
	is_dead = false
	visible = true
	collision_layer = _default_collision_layer
	collision_mask = _default_collision_mask
	velocity = Vector3.ZERO
	# The Spawner teleports us to the boundary, so whatever planet frame we were
	# riding is stale - dropping it here stops that planet's motion_delta being
	# applied to the new position for a frame.
	_frame_body = null
	_platform_velocity = Vector3.ZERO
	_ladder = null
	_has_aligned_once = false
	_start_spawn_sequence()

func _start_spawn_sequence() -> void:
	if _spawner == null:
		const SpawnerScript = preload("res://scripts/player/Spawner.gd")
		_spawner = SpawnerScript.new()
		add_child(_spawner)
		_spawner.spawn_complete.connect(_on_spawn_complete)
	_spawner.start_spawn(self)

func _on_spawn_complete() -> void:
	pass  # Normal gameplay resumes automatically when Spawner clears _active

## Block normal fire input during the spawn aim window so the fire button
## is exclusively used to lock onto a planet without also triggering weapons.
func _is_spawning() -> bool:
	return _spawner != null and _spawner._active

## The weapon to render in third person. On the authority that's simply whatever
## WeaponManager has selected, and publishing it here is what feeds the
## replicated field; on a remote copy it's whatever that field points at, applied
## here because handle_input() never runs for a peer we don't simulate.
func get_displayed_weapon() -> Weapon:
	if weapon_manager == null:
		return null
	if is_multiplayer_authority():
		current_weapon_index = weapon_manager.get_current_index()
	else:
		weapon_manager.set_current_index(current_weapon_index)
	return weapon_manager.get_active_weapon()

## Spawner hooks. Humans get the full aim window and default to the nearest
## planet; Bot overrides both so 31 of them don't idle at the boundary for ten
## seconds and then all pile onto the same rock.
func get_spawn_aim_window() -> float:
	return 10.0

func pick_spawn_target() -> OrbitalBody:
	return GravityManager.get_nearest_body(global_position)

## True only for the human sitting at this screen. Third-person body attachments
## (see WeaponModel) hide themselves on this, or they'd hang in your own view
## next to the first-person viewmodel.
func is_first_person_view() -> bool:
	return is_multiplayer_authority() and _is_local_view()

## Health pickups. Capped at max_health and refused while dead, so a pack can't
## be burned on a corpse mid-respawn.
func heal(amount: float) -> bool:
	if is_dead or amount <= 0.0 or health >= max_health:
		return false
	health = minf(health + amount, max_health)
	return true

func get_look_direction() -> Vector3:
	return -camera.global_transform.basis.z

## The planet currently acting as our reference frame, or null if we're not
## within `planet_frame_height` of any body's surface. Lets other systems
## (e.g. OrbitalBody's atmosphere glow) know when a player is "on" a planet
## using the same hysteresis-guarded range that drives movement.
func get_frame_body() -> OrbitalBody:
	return _frame_body

func get_muzzle_transform() -> Transform3D:
	return muzzle.global_transform

func grant_weapon(id: String) -> void:
	weapon_manager.grant_weapon(id)

const HUD_SCENE: PackedScene = preload("res://scenes/ui/HUD.tscn")

func _setup_hud() -> void:
	hud = HUD_SCENE.instantiate()
	add_child(hud)
	hud.set_player_id(player_id)

## Sets up what gets replicated to other peers. Position/rotation/velocity
## sync continuously so remote players look reasonably smooth; health and
## death state only sync on change since they're infrequent and reliable.
func _setup_replication() -> void:
	if sync == null:
		return
	var config := SceneReplicationConfig.new()
	# hook_end moves every frame while a cable is out, so it rides the ALWAYS
	# channel alongside transform; hook_active only flips on fire/release.
	var always_props := [".:transform", ".:velocity", ".:hook_end"]
	var on_change_props := [".:health", ".:is_dead", ".:visible", ".:hook_active", ".:current_weapon_index"]
	for p in always_props:
		var path := NodePath(p)
		config.add_property(path)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	for p in on_change_props:
		var path := NodePath(p)
		config.add_property(path)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	sync.replication_config = config
