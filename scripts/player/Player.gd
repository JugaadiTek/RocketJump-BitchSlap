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
@export var jump_speed: float = 6.5
@export var align_to_gravity_speed: float = 10.0 ## rad/sec, how fast the body re-levels on a new planet

@export_group("Look")
@export var mouse_sensitivity: float = 0.0025
@export var pitch_limit_degrees: float = 89.0

@export_group("Health")
@export var max_health: float = 100.0
@export var respawn_delay: float = 3.0

## ---- Runtime state -----------------------------------------------------
var health: float = 100.0
var is_dead: bool = false
var current_gravity: Vector3 = Vector3.ZERO
var last_damage_instigator_path: NodePath

var _mouse_delta := Vector2.ZERO
var _has_aligned_once := false
var _default_collision_layer: int
var _default_collision_mask: int

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var muzzle: Marker3D = $Head/Camera3D/Muzzle
@onready var weapon_manager: Node = $WeaponManager
@onready var melee: Node = $Melee
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var model: Node3D = $Model
@onready var sync: MultiplayerSynchronizer = $MultiplayerSynchronizer

func _ready() -> void:
	health = max_health
	_default_collision_layer = collision_layer
	_default_collision_mask = collision_mask
	add_to_group("players")
	add_to_group("damageable")
	_setup_replication()
	if is_multiplayer_authority():
		if camera:
			camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		if camera:
			camera.current = false

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if not _uses_mouse_look():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_delta += event.relative
	if event.is_action_pressed("ui_cancel"):
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

	_apply_look(delta)
	_apply_movement(new_up, delta)

	if _wants_melee():
		melee.try_activate()
	weapon_manager.handle_input(delta, _wants_fire(), _get_weapon_switch())

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
	rotate_object_local(Vector3.UP, -look.x * mouse_sensitivity)
	var pitch_limit: float = deg_to_rad(pitch_limit_degrees)
	head.rotation.x = clamp(head.rotation.x - look.y * mouse_sensitivity, -pitch_limit, pitch_limit)

func _apply_movement(up: Vector3, delta: float) -> void:
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
			vel_up = jump_speed
	else:
		vel_horizontal = _q3_air_accelerate(wish_dir, max_ground_speed, air_accel, air_speed_cap, vel_horizontal, delta)

	# Gravity always applies; current_gravity already points toward the pull,
	# so its component along `up` is naturally negative (or zero in deep space).
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

## ---- Input hooks (override in Bot.gd) -----------------------------------
func _get_move_axis() -> Vector2:
	return Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	)

func _get_look_delta() -> Vector2:
	var d := _mouse_delta
	_mouse_delta = Vector2.ZERO
	return d

func _wants_jump() -> bool:
	return Input.is_action_pressed("jump")

func _wants_fire() -> bool:
	return Input.is_action_pressed("fire")

func _wants_melee() -> bool:
	return Input.is_action_just_pressed("melee")

func _get_weapon_switch() -> int:
	if Input.is_action_just_pressed("weapon_rocket"):
		return 0
	if Input.is_action_just_pressed("weapon_railgun"):
		return 1
	if Input.is_action_just_pressed("weapon_slug"):
		return 2
	if Input.is_action_just_pressed("weapon_planetbuster"):
		return 3
	return -1

## ---- Combat --------------------------------------------------------------

## Direct velocity change - used for rocket-jump splash and bitchslap launches.
## Works identically whether the player is grounded or drifting in zero-g.
func apply_impulse(force: Vector3) -> void:
	if is_dead:
		return
	velocity += force

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
	if instigator and instigator.has_method("get_multiplayer_authority"):
		killer_id = instigator.get_multiplayer_authority()
	MatchState.report_frag(get_multiplayer_authority(), killer_id, weapon_name)
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
