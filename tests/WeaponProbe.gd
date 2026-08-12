extends Node
## Headless probe for the three weapon improvements:
##   HOOK    - the grappling hook shoots a hook head and pays out a visible cable
##   BOARD   - the space board gives unrestricted movement on all six axes
##   BUSTER  - the planet buster refuses to fire unlocked, and its shell starts
##             slow, accelerates linearly, and re-aims once a second
##
## Run: Godot --headless --path . res://tests/WeaponProbe.tscn

const ProbePlayer := preload("res://tests/ProbePlayer.gd")
const ARENA := preload("res://scenes/world/Arena.tscn")
const LOG_PATH := "/tmp/rjbs_weapons.log"

const WEAPON_GRAPPLE := 3
const WEAPON_BOARD := 4

var _arena: Node3D
var _player: Player
var _body: OrbitalBody

func _log(line: String) -> void:
	print(line)
	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(LOG_PATH) else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(line)
		f.close()

func _ready() -> void:
	seed(20260811)
	_arena = ARENA.instantiate()
	_arena.bot_count = 0
	add_child(_arena)
	await get_tree().physics_frame
	await get_tree().physics_frame

	_body = _arena.get_node("OrbitalBodies/Ferrum")
	var scene: PackedScene = load("res://scenes/player/Player.tscn")
	_player = scene.instantiate()
	_player.set_script(ProbePlayer)
	_arena.get_node("Players").add_child(_player)
	_player.player_id = 99
	await get_tree().physics_frame

	await _test_hook()
	await _test_board()
	await _test_buster_lock_gate()
	await _test_buster_shell()
	await _test_third_person_weapon()
	await _test_scope()
	_test_slug_gravity()
	await _test_all_weapons_option()
	get_tree().quit()

func _place_on_surface(altitude: float = 1.2) -> void:
	_player.probe_move = Vector2.ZERO
	_player.probe_fire = false
	_player.probe_jump = false
	_player.probe_descend = false
	_player.disable_spawner()
	var out: Vector3 = Vector3(0.3, 1.0, 0.2).normalized()
	_player.global_position = _body.global_position + out * (_body.radius + altitude)
	_player.velocity = Vector3.ZERO
	_player.reset_frame()
	# Right-handed basis with Y = out and -Z = the chosen tangent. Building it as
	# Basis(out.cross(fwd), out, -fwd) instead mirrors the basis (det -1), which
	# silently reverses which way every local-axis rotation turns.
	var fwd: Vector3 = out.cross(Vector3.RIGHT).normalized()
	var basis_z: Vector3 = -fwd
	var basis_x: Vector3 = out.cross(basis_z).normalized()
	_player.global_transform.basis = Basis(basis_x, out, basis_z).orthonormalized()
	# Level the camera too - a pitch left over from a previous phase would tilt
	# every "horizontal" direction the next phase commands.
	_player.head.rotation.x = 0.0
	for i in range(60):
		await get_tree().physics_frame

func _select(index: int) -> void:
	_player.probe_switch = index
	await get_tree().physics_frame
	await get_tree().physics_frame

## IMPROVEMENT 1 - shoot a hook and pay out a cable.
func _test_hook() -> void:
	# Fired from well above the surface so the cable has real distance to pay
	# out over; a point-blank shot at the ground would attach in one frame.
	await _place_on_surface(90.0)
	await _select(WEAPON_GRAPPLE)
	var hook: GrapplingHook = _player.weapon_manager.get_active_weapon() as GrapplingHook
	if hook == null:
		_log("HOOK    FAIL - active weapon is not the grappling hook")
		return
	var visual: Node3D = _player.get_node("HookVisual")
	var cable: MeshInstance3D = visual.get_node("Cable")
	var head: MeshInstance3D = visual.get_node("HookHead")
	_log("HOOK    idle: cable_visible=%s attached=%s (cable lives on the Player, outside the hidden viewmodel: %s)" % [
		cable.visible, hook.is_attached(), visual.get_path()])

	# Straight down at the planet, ~90m below.
	var out: Vector3 = (_player.global_position - _body.global_position).normalized()
	var target: Vector3 = _body.global_position + out * _body.radius
	_player.aim_at(target)
	_player.probe_fire = true

	var max_extension: float = 0.0
	var frames_cable_visible: int = 0
	var frames_attached: int = 0
	var extension_samples: Array[String] = []
	for i in range(120):
		await get_tree().physics_frame
		if cable.visible:
			frames_cable_visible += 1
		if hook.is_attached():
			frames_attached += 1
		var extension: float = head.global_position.distance_to(_player.get_muzzle_transform().origin)
		max_extension = maxf(max_extension, extension)
		if i < 6:
			extension_samples.append("%.1f" % extension)
	var pulled_distance: float = _player.global_position.distance_to(target)
	_log("HOOK    firing: cable_visible %d/120 frames, attached %d/120, cable paid out to %.1fm" % [
		frames_cable_visible, frames_attached, max_extension])
	_log("HOOK    cable extension over first 6 frames = [%s] (pays out, not instant)" % ", ".join(extension_samples))
	_log("HOOK    player is now %.1fm from the anchor (reeled in)" % pulled_distance)

	# Release: the cable should retract and the hook go idle.
	_player.probe_fire = false
	for i in range(120):
		await get_tree().physics_frame
		if not hook.is_attached() and not cable.visible:
			break
	_log("HOOK    released: cable_visible=%s attached=%s" % [cable.visible, hook.is_attached()])

## IMPROVEMENT 2 - the board allows movement in any direction.
func _test_board() -> void:
	await _place_on_surface()
	await _select(WEAPON_BOARD)
	var board: Weapon = _player.weapon_manager.get_active_weapon()
	_log("BOARD   selected=%s flight_mode=%s" % [board.weapon_name, _player._is_flight_mode()])

	# Six axes, each commanded on its own from a standstill.
	var axes := {
		"up (against gravity)": {"jump": true},
		"down": {"descend": true},
		"forward": {"move": Vector2(0.0, 1.0)},
		"back": {"move": Vector2(0.0, -1.0)},
		"right": {"move": Vector2(1.0, 0.0)},
		"left": {"move": Vector2(-1.0, 0.0)},
	}
	var results: Array[String] = []
	for axis_name in axes:
		var cmd: Dictionary = axes[axis_name]
		# Start clear of the surface so "down" has somewhere to go.
		await _place_on_surface(14.0)
		_player.probe_jump = cmd.get("jump", false)
		_player.probe_descend = cmd.get("descend", false)
		_player.probe_move = cmd.get("move", Vector2.ZERO)
		var start: Vector3 = _player.global_position
		var start_alt: float = start.distance_to(_body.global_position) - _body.radius
		for i in range(90):
			await get_tree().physics_frame
		var end: Vector3 = _player.global_position
		var end_alt: float = end.distance_to(_body.global_position) - _body.radius
		_player.probe_jump = false
		_player.probe_descend = false
		_player.probe_move = Vector2.ZERO
		results.append("%s: moved %.1fm (altitude %+.1fm)" % [axis_name, start.distance_to(end), end_alt - start_alt])
	for r in results:
		_log("BOARD   " + r)

## IMPROVEMENT 3a - the planet buster must not fire without a lock.
func _test_buster_lock_gate() -> void:
	await _place_on_surface()
	_player.grant_weapon("planetbuster")
	await get_tree().physics_frame
	var buster: PlanetBuster = _player.weapon_manager.get_active_weapon() as PlanetBuster
	if buster == null:
		_log("BUSTER  FAIL - planet buster was not granted")
		return

	# Aimed at empty space: holding fire must neither lock nor fire.
	_player.aim_at(_player.global_position + (_player.global_position - _body.global_position).normalized() * 5000.0)
	_player.probe_fire = true
	for i in range(180):
		await get_tree().physics_frame
	var shells_no_lock: int = _count_shells()
	_log("BUSTER  aimed at empty space, fire held 3s: lock=%s can_fire=%s shells_spawned=%d (weapon still held=%s)" % [
		buster.get_lock_target(), buster.can_fire(), shells_no_lock,
		_player.weapon_manager.get_weapon_names().has("Planet Buster")])

	# Aimed at a lockable planet: lock builds, then it fires.
	var target_body: OrbitalBody = _arena.get_node("OrbitalBodies/Verdant")
	_player.aim_at(target_body.global_position)
	var locked_at_frame: int = -1
	var fired_at_frame: int = -1
	for i in range(240):
		await get_tree().physics_frame
		if is_instance_valid(buster) and locked_at_frame < 0:
			if buster.get_lock_target() != null:
				locked_at_frame = i
		if _count_shells() > 0:
			fired_at_frame = i
			break
		_player.aim_at(target_body.global_position)
	_player.probe_fire = false
	_log("BUSTER  aimed at %s: locked after %s, fired after %s" % [
		target_body.name,
		"never" if locked_at_frame < 0 else "%.2fs" % (float(locked_at_frame) / 60.0),
		"never" if fired_at_frame < 0 else "%.2fs" % (float(fired_at_frame) / 60.0)])

func _count_shells() -> int:
	var root: Node = get_tree().current_scene.get_node_or_null("Projectiles")
	if root == null:
		return 0
	var n: int = 0
	for c in root.get_children():
		if c is PlanetBusterProjectile:
			n += 1
	return n

## IMPROVEMENT 3b - shell flight profile: slow start, linear acceleration,
## heading recomputed once a second.
func _test_buster_shell() -> void:
	var target_body: OrbitalBody = _arena.get_node("OrbitalBodies/Umbra")
	var scene: PackedScene = load("res://scenes/weapons/PlanetBusterProjectile.tscn")
	var shell: PlanetBusterProjectile = scene.instantiate()
	get_tree().current_scene.add_child(shell)
	# Launch from well outside the target, deliberately aimed 25 degrees off so
	# the course corrections have something to correct. Kept inside
	# GravityManager.ARENA_BOUNDARY_RADIUS (535) - Umbra orbits at 350, so the
	# old 400-unit offset could push the spawn point past 535 from the arena
	# centre depending on direction, which now gets the shell destroyed as
	# out-of-bounds on its very first frame (see Projectile._physics_process).
	var offset: Vector3 = Vector3(1, 0.3, 0.4).normalized() * 150.0
	shell.global_position = target_body.global_position + offset
	var straight: Vector3 = -offset.normalized()
	var askew: Vector3 = straight.rotated(offset.cross(Vector3.UP).normalized(), deg_to_rad(25.0))
	shell.lock_target = target_body
	shell.launch(askew * 7.0, null)

	var speeds: Array[String] = []
	var heading_change_frames: Array[String] = []
	var prev_dir: Vector3 = shell.velocity.normalized()
	var frame: int = 0
	var hit_frame: int = -1
	while frame < 900:
		await get_tree().physics_frame
		frame += 1
		if not is_instance_valid(shell):
			hit_frame = frame
			break
		var dir: Vector3 = shell.velocity.normalized()
		if dir.angle_to(prev_dir) > deg_to_rad(0.2):
			heading_change_frames.append("%.2fs" % (float(frame) / 60.0))
		prev_dir = dir
		if frame % 60 == 0:
			speeds.append("%.0f" % shell.velocity.length())
	_log("BUSTER  shell speed each second = [%s] m/s (launched at 7)" % ", ".join(speeds))
	_log("BUSTER  heading recomputed at: [%s]" % ", ".join(heading_change_frames))
	if hit_frame > 0:
		_log("BUSTER  shell struck %s after %.2fs; planet shattered=%s" % [
			target_body.name, float(hit_frame) / 60.0, target_body.is_shattered])
	else:
		_log("BUSTER  shell still in flight after 15s (did not reach target)")


## IMPROVEMENT - everyone can see what gun everyone else is holding.
func _test_third_person_weapon() -> void:
	await _place_on_surface()
	var model: MeshInstance3D = _player.get_node("Model/WeaponModel")
	var seen: Array[String] = []
	for index in [0, 1, 2, 3, 4]:
		await _select(index)
		await get_tree().process_frame
		await get_tree().process_frame
		var weapon: Weapon = _player.get_displayed_weapon()
		seen.append("%s%s" % [weapon.weapon_name, "" if model.visible else "(HIDDEN)"])
	# The body model is never hidden for remote views, unlike the viewmodel.
	var viewmodel_hidden_for_others: bool = not _player.weapon_manager.visible
	_log("THIRDPERSON model visible per weapon = [%s]; first-person viewmodel hidden for non-local view = %s" % [
		", ".join(seen), viewmodel_hidden_for_others])

## IMPROVEMENT - railgun ADS looks through the scope.
func _test_scope() -> void:
	await _place_on_surface()
	await _select(1)
	var railgun = _player.weapon_manager.get_active_weapon()
	var view_model: Node3D = railgun.get_node("ViewModel")
	var rest_offset: Vector3 = view_model.position
	var hip_fov: float = _player.camera.fov
	_player.probe_aim = true
	for i in range(120):
		await get_tree().physics_frame
		await get_tree().process_frame
	var scoped_fov: float = _player.camera.fov
	var scoped_offset: Vector3 = view_model.position
	# Where the scope tube ends up relative to the camera axis: near zero on
	# X/Y means you are looking straight down the optic.
	var scope_node: Node3D = railgun.get_node("ViewModel/Scope")
	var in_camera: Vector3 = _player.camera.global_transform.affine_inverse() * scope_node.global_position
	_log("SCOPE   scoped=%s fov %.0f -> %.0f | viewmodel %.2f -> %.2f | lens offset from camera axis = (%.3f, %.3f)" % [
		railgun.is_scoped(), hip_fov, scoped_fov, rest_offset.x, scoped_offset.x, in_camera.x, in_camera.y])
	# The probe player is not a local view, so it never builds a HUD. Check the
	# overlay wiring against a HUD instance directly instead.
	var hud: CanvasLayer = load("res://scenes/ui/HUD.tscn").instantiate()
	add_child(hud)
	await get_tree().process_frame
	var default_visible: bool = hud.scope_overlay.visible
	hud.update_scope(true)
	var on: bool = hud.scope_overlay.visible
	hud.update_scope(false)
	var off: bool = hud.scope_overlay.visible
	var has_shader: bool = hud.scope_overlay.material is ShaderMaterial
	_log("SCOPE   overrides_aim_fov=%s | HUD overlay default=%s -> update_scope(true)=%s -> (false)=%s, blur shader attached=%s" % [
		railgun.overrides_aim_fov(), default_visible, on, off, has_shader])
	hud.queue_free()
	_player.probe_aim = false

## IMPROVEMENT - slugs fired from space fall into gravity wells much harder.
func _test_slug_gravity() -> void:
	# Pick a live body at runtime: the buster phases above deliberately shatter
	# planets, so naming one here would be a race against its own test suite.
	var body: OrbitalBody = null
	for candidate in GravityManager.get_bodies():
		if is_instance_valid(candidate) and not candidate.is_shattered and candidate.radius >= 15.0:
			body = candidate
			break
	if body == null:
		_log("SLUG    no intact planet left to test against")
		return
	var scene: PackedScene = load("res://scenes/weapons/Slug.tscn")
	var slug: Slug = scene.instantiate()
	get_tree().current_scene.add_child(slug)
	slug.global_position = body.global_position + Vector3(0, body.radius + 60.0, 0)
	var ground: float = slug._flight_gravity_multiplier()
	slug.global_position = body.global_position + Vector3(0, body.radius + 3.0, 0)
	var surface: float = slug._flight_gravity_multiplier()
	_log("SLUG    gravity multiplier: near surface %.1fx, out in space %.1fx | aggro range %.0fm, slither %.0f m/s" % [
		surface, ground, slug.tracking_range, slug.slither_speed])
	slug.queue_free()


## MAIN MENU option - starting with the complete arsenal, buster included.
func _test_all_weapons_option() -> void:
	var menu: Control = load("res://scenes/ui/MainMenu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	var has_checkbox: bool = menu.get_node_or_null("CenterContainer/VBoxContainer/AllWeaponsCheck") != null
	menu.queue_free()

	var scene: PackedScene = load("res://scenes/player/Player.tscn")
	MatchState.start_with_all_weapons = false
	var plain: Player = scene.instantiate()
	plain.set_script(ProbePlayer)
	plain.name = "LoadoutProbePlain"
	_arena.get_node("Players").add_child(plain, true)
	await get_tree().physics_frame
	var without: Array[String] = plain.weapon_manager.get_weapon_names()
	plain.queue_free()

	MatchState.start_with_all_weapons = true
	var loaded: Player = scene.instantiate()
	loaded.set_script(ProbePlayer)
	loaded.name = "LoadoutProbeAll"
	_arena.get_node("Players").add_child(loaded, true)
	await get_tree().physics_frame
	var with_all: Array[String] = loaded.weapon_manager.get_weapon_names()
	loaded.queue_free()
	MatchState.start_with_all_weapons = false

	_log("MENU    checkbox present=%s | unchecked loadout=[%s] | checked loadout=[%s]" % [
		has_checkbox, ", ".join(without), ", ".join(with_all)])
