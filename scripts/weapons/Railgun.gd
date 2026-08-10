class_name Railgun
extends Weapon
## Charge-up hitscan weapon with damage that scales with hold duration.
## Separate scope zoom distinct from the ADS system.
##
## Fire flow:
##   HOLD    → charge accumulates for up to charge_max_time seconds.
##   RELEASE → fires immediately once min_charge_time is met; if released
##             before min_charge_time, weapon "fizzles" (cooldown still
##             applies, damage is partial, cosmetic-only dim beam fires).
##   SCOPE   → right-click toggles scope independent of ADS (overrides the
##             normal ADS FOV while railgun is active and scope is held; see
##             _handle_scope below).

@export var max_range: float = 500.0

@export_group("Charge")
@export var min_damage: float = 20.0          ## damage when fired at min charge
@export var max_damage: float = 200.0         ## damage at full charge
@export var min_charge_time: float = 0.3      ## seconds before shot is "valid" at all
@export var charge_max_time: float = 1.8      ## seconds to reach max_damage
@export var charge_falloff: float = 0.6       ## charge drains this fast per second after release without firing

@export_group("Scope")
@export var scope_fov: float = 18.0
@export var scope_sensitivity_multiplier: float = 0.18
@export var scope_transition_speed: float = 14.0
## How far in front of the eye the lens sits once scoped. The viewmodel slides
## so the scope tube lands on the camera axis, which is what makes it read as
## looking THROUGH the optic rather than past it.
@export var scope_eye_relief: float = 0.42

var charge: float = 0.0        ## 0.0 → 1.0
var _charging: bool = false
var _scope_active: bool = false
var _prev_fire_held: bool = false
var _view_model: Node3D = null
## Where the viewmodel has to sit for the scope to line up with the camera axis.
var _scope_ads_offset: Vector3 = Vector3.ZERO
var _base_sensitivity: float = 0.0025

func _ready() -> void:
	super._ready()
	_view_model = get_node_or_null("ViewModel")
	var scope: Node3D = get_node_or_null("ViewModel/Scope")
	var holder := get_parent() as Node3D   # WeaponManager, offset to one side of the camera
	if _view_model and scope and holder:
		# Scope position in camera space with the viewmodel at rest. Negating
		# X/Y is exactly the shift that puts the lens on the camera's own axis.
		var rest: Vector3 = holder.position + position + _view_model.position + scope.position
		_scope_ads_offset = Vector3(-rest.x, -rest.y, scope_eye_relief)
	var p: Player = owner_player as Player
	if p:
		_base_sensitivity = p.mouse_sensitivity

func _init() -> void:
	weapon_name = "Railgun"
	fire_cooldown = 0.8          ## delay between successive shots, shorter than before since charge now limits rate
	damage = max_damage          ## base Weapon.damage not used directly; actual damage computed from charge
	weapon_color = Color(0.4, 0.9, 1.0)

## Called by WeaponManager every frame.
func tick(delta: float, fire_held: bool) -> void:
	var just_pressed: bool  = fire_held and not _prev_fire_held
	var just_released: bool = not fire_held and _prev_fire_held
	_prev_fire_held = fire_held

	if _cooldown_remaining > 0.0:
		charge = 0.0
		_charging = false
		return

	if fire_held:
		_charging = true
		charge = min(charge + delta / charge_max_time, 1.0)
	elif _charging and just_released:
		# Fire on release - WeaponManager checks `wants_fire` which is
		# `fire_held`, so a release-based shot needs to be triggered here
		# directly rather than waiting for the manager.
		if owner_player:
			var p: Player = owner_player as Player
			if p:
				_release_fire(p.get_muzzle_transform(), p.get_look_direction())
		_charging = false
	else:
		# Drain charge when not held and not actively charging
		charge = max(charge - delta * charge_falloff, 0.0)

	_handle_scope(fire_held)

func _release_fire(muzzle_transform: Transform3D, aim_direction: Vector3) -> void:
	if _cooldown_remaining > 0.0:
		return
	var shot_damage: float = lerp(min_damage, max_damage, charge)
	var valid: bool = charge >= (min_charge_time / charge_max_time)
	_cooldown_remaining = fire_cooldown
	charge = 0.0
	_do_fire_with_damage(muzzle_transform, aim_direction, shot_damage, valid)
	fired.emit()

## Railgun fires on release (handled in tick()), so WeaponManager's fire()
## call (which fires on hold/press) is suppressed here.
func can_fire() -> bool:
	return false

func _do_fire(_muzzle_transform: Transform3D, _aim_direction: Vector3) -> void:
	pass # not used; railgun fires via _release_fire in tick()

func _do_fire_with_damage(muzzle_transform: Transform3D, aim_direction: Vector3, shot_damage: float, valid: bool) -> void:
	var space_state := get_world_3d().direct_space_state
	var from: Vector3 = muzzle_transform.origin
	var to: Vector3 = from + aim_direction * max_range
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1 | 2 | 8
	if owner_player:
		query.exclude = [owner_player]
	var result: Dictionary = space_state.intersect_ray(query)
	var end_point: Vector3 = to
	if not result.is_empty():
		end_point = result.position
		if valid:
			var collider: Object = result.collider
			if collider and collider.has_method("apply_damage"):
				if collider.has_method("network_apply_damage") and not collider.is_multiplayer_authority():
					collider.rpc_id(collider.get_multiplayer_authority(), "network_apply_damage", shot_damage, owner_player.get_path() if owner_player else NodePath(), end_point, weapon_name)
				else:
					collider.apply_damage(shot_damage, owner_player, end_point, weapon_name)
	_spawn_beam(from, end_point, valid)

## Aiming down the sights on the railgun means going through the optic: the
## viewmodel slides until the scope tube is centred on the camera axis, the FOV
## drops to scope_fov, sensitivity scales to match, and the HUD's scope overlay
## blurs and darkens everything outside the lens.
##
## Reads p.is_aiming rather than polling the mouse directly, so bots (which set
## it through _wants_aim()) scope the same way a human does.
func _handle_scope(_fire_held: bool) -> void:
	var p: Player = owner_player as Player
	if p == null or p.camera == null:
		return
	_scope_active = p.is_aiming and visible

	var t: float = clamp(scope_transition_speed * get_process_delta_time(), 0.0, 1.0)
	var target_fov: float = scope_fov if _scope_active else p.hipfire_fov_degrees
	p.camera.fov = lerp(p.camera.fov, target_fov, t)
	p.mouse_sensitivity = _base_sensitivity * (scope_sensitivity_multiplier if _scope_active else 1.0)
	if _view_model:
		_view_model.position = _view_model.position.lerp(
			_scope_ads_offset if _scope_active else Vector3.ZERO, t)

func is_scoped() -> bool:
	return _scope_active

## Tells Player._apply_aim() to keep its hands off the FOV while the railgun is
## out - otherwise the generic ADS zoom and this scope zoom fight each frame.
func overrides_aim_fov() -> bool:
	return true

## Put the viewmodel and the player's sensitivity back when switching away
## mid-scope, or the next weapon inherits a zoomed-in mouse.
func on_holster() -> void:
	_scope_active = false
	if _view_model:
		_view_model.position = Vector3.ZERO
	var p: Player = owner_player as Player
	if p:
		p.mouse_sensitivity = _base_sensitivity

## Public getter so HUD/WeaponManager can show charge state.
func get_charge() -> float:
	return charge

func _spawn_beam(from: Vector3, to: Vector3, bright: bool) -> void:
	var beam := MeshInstance3D.new()
	_get_projectile_root().add_child(beam)
	var length: float = from.distance_to(to)
	var box := BoxMesh.new()
	var thickness: float = 0.04 + 0.07 * charge
	box.size = Vector3(thickness, thickness, length)
	beam.mesh = box
	var mat := StandardMaterial3D.new()
	var col: Color = weapon_color
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 5.0 if bright else 1.0
	beam.material_override = mat
	beam.global_position = from.lerp(to, 0.5)
	if length > 0.01:
		beam.look_at(to, Vector3.UP if abs((to - from).normalized().dot(Vector3.UP)) < 0.99 else Vector3.RIGHT)
	var lifetime: float = 0.08 + charge * 0.12
	var timer := get_tree().create_timer(lifetime)
	timer.timeout.connect(func(): if is_instance_valid(beam): beam.queue_free())
