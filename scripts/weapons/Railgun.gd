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
## Fraction of hipfire mouse sensitivity kept while scoped - panning is still
## much slower than hipfire (a narrow FOV makes raw sensitivity feel frantic),
## but this is 30% faster than it used to be (0.18 -> 0.234).
@export var scope_sensitivity_multiplier: float = 0.18 * 1.3
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
## Everything in the viewmodel except the scope itself - hidden while scoped.
var _non_scope_parts: Array[MeshInstance3D] = []
## The scope's own glass, a translucent sphere. Looks right sitting on the
## tube from outside (hipfire/third-person), but once scoped the viewmodel
## slides it right onto the camera axis, where a translucent disc this close
## to the lens just fogs the whole view - so it hides for the scoped duration
## same as the rest of the viewmodel, leaving the screen-space scope.gdshader
## overlay as the only "looking through glass" effect.
var _scope_lens: MeshInstance3D = null

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
	# Sliding the WHOLE viewmodel to put the scope on the camera axis also
	# drags the barrel (Body) there, since it was authored only ~5mm off the
	# scope's own X/Y to begin with (they're meant to look roughly coaxial at
	# rest) - close enough that scoping in put a solid box from the barrel
	# directly across the view, same complaint as the scope tube itself used
	# to be. Everything but the scope assembly hides while scoped instead.
	if _view_model:
		for child in _view_model.get_children():
			if child is MeshInstance3D:
				_non_scope_parts.append(child)
	_scope_lens = get_node_or_null("ViewModel/Scope/ScopeLens")
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
		if not _charging and owner_player:
			# Pitch of the whine rises with charge, so the sound tells you how
			# close to a full-power shot you are without looking at the bar.
			Sfx.play_3d("railgun_charge", (owner_player as Node3D).global_position, 1.0, -6.0, 0.04)
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
	# Louder and deeper the harder it was charged. Ceiling trimmed from +2 to
	# +1 - see OrbitalBody.shatter()'s planet_shatter call for why.
	Sfx.play_3d("railgun_fire", muzzle_transform.origin, 1.25 - charge * 0.35,
		-6.0 + charge * 7.0)
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
## blurs and darkens everything outside the lens. Everything in the viewmodel
## except the scope assembly (the barrel, the stock) hides for the duration -
## sliding the model to put the scope on-axis puts the barrel almost exactly
## on that same axis too (see _non_scope_parts), which read as vision being
## blocked just as badly as the old solid scope tube did.
##
## Reads p.is_aiming rather than polling the mouse directly, so bots (which set
## it through _wants_aim()) scope the same way a human does.
func _handle_scope(_fire_held: bool) -> void:
	var p: Player = owner_player as Player
	if p == null or p.camera == null:
		return
	var was_active: bool = _scope_active
	_scope_active = p.is_aiming and visible

	var t: float = clamp(scope_transition_speed * get_process_delta_time(), 0.0, 1.0)
	var target_fov: float = scope_fov if _scope_active else p.hipfire_fov_degrees
	p.camera.fov = lerp(p.camera.fov, target_fov, t)
	p.mouse_sensitivity = _base_sensitivity * (scope_sensitivity_multiplier if _scope_active else 1.0)
	if _view_model:
		_view_model.position = _view_model.position.lerp(
			_scope_ads_offset if _scope_active else Vector3.ZERO, t)
	for part in _non_scope_parts:
		part.visible = not _scope_active
	if _scope_lens:
		_scope_lens.visible = not _scope_active

	if _scope_active != was_active:
		_highlight_other_players(p, _scope_active)

## Makes everyone else easy to pick out against the blurred, darkened
## surround while scoped - a distant low-poly silhouette is otherwise easy to
## lose against a planet's own facets. Gated to the local human specifically:
## bots carry and scope this same weapon (their own AI can hold "aim"), and
## without this check a bot scoping in offline would highlight everyone from
## the one shared screen even though no human asked to look through a scope.
func _highlight_other_players(p: Player, active: bool) -> void:
	if not p.is_first_person_view():
		return
	for node in p.get_tree().get_nodes_in_group("players"):
		if node == p or not is_instance_valid(node) or not node.has_method("set_highlighted"):
			continue
		node.set_highlighted(active)

func is_scoped() -> bool:
	return _scope_active

## Tells Player._apply_aim() to keep its hands off the FOV while the railgun is
## out - otherwise the generic ADS zoom and this scope zoom fight each frame.
func overrides_aim_fov() -> bool:
	return true

## Put the viewmodel and the player's sensitivity back when switching away
## mid-scope, or the next weapon inherits a zoomed-in mouse.
func on_holster() -> void:
	var p: Player = owner_player as Player
	if _scope_active and p:
		_highlight_other_players(p, false)
	_scope_active = false
	if _view_model:
		_view_model.position = Vector3.ZERO
	for part in _non_scope_parts:
		part.visible = true
	if _scope_lens:
		_scope_lens.visible = true
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
