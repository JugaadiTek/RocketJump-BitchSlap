extends Node
## Headless probe for the three weapon improvements:
##   HOOK    - the grappling hook shoots a hook head and pays out a visible cable
##   BOARD   - the space board gives unrestricted movement on all six axes
##   BUSTER  - the planet buster refuses to fire unlocked, and its shell starts
##             slow, accelerates linearly, and re-aims once a second
##
## Run: Godot --headless --path . res://tests/WeaponProbe.tscn

const ProbePlayer := preload("res://tests/ProbePlayer.gd")
const ProbeLocalPlayer := preload("res://tests/ProbeLocalPlayer.gd")
const ARENA := preload("res://scenes/world/Arena.tscn")
const LOG_PATH := "/tmp/rjbs_weapons.log"

const WEAPON_ROCKET := 0
const WEAPON_RAILGUN := 1
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
	await _test_buster_intercept_moving_target()
	await _test_third_person_weapon()
	await _test_scope()
	await _test_scope_highlight()
	await _test_melee_hand_animation()
	await _test_grapple_auto_melee()
	await _test_slug_vs_tower()
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


## BUGFIX - the shell used to aim with pure pursuit and only re-aim once a
## second, so a small, fast-orbiting body could drift clear of its own radius
## between corrections and the shot would sail past. Fires one shell each at
## four small/fast bodies (three of them moons orbiting an already-orbiting
## parent, so their true world-space speed is well above what their own
## orbit_speed*orbit_radius alone suggests) from an off-axis angle, like a
## human's aim, and checks every one actually connects. A real hit shatters
## its target, so each case gets its own body rather than reusing one.
func _test_buster_intercept_moving_target() -> void:
	var scene: PackedScene = load("res://scenes/weapons/PlanetBusterProjectile.tscn")
	# Ferrum deliberately excluded - it's where _place_on_surface() stands the
	# probe player, and shattering the ground out from under it corrupts every
	# test that runs after this one.
	var cases: Array[Dictionary] = [
		{"path": "OrbitalBodies/Cinder_Moon", "offset": Vector3(1, 0.2, 0.3).normalized() * 35.0, "askew_deg": 30.0},
		{"path": "OrbitalBodies/Verdant_Moon", "offset": Vector3(-1, 0.1, 0.4).normalized() * 45.0, "askew_deg": 30.0},
		{"path": "OrbitalBodies/Cobalt", "offset": Vector3(0.3, -0.2, 1).normalized() * 40.0, "askew_deg": 30.0},
	]
	var hits: int = 0
	var results: Array[String] = []
	for c in cases:
		var target: OrbitalBody = _arena.get_node(c["path"])
		if not is_instance_valid(target) or target.is_shattered:
			results.append("%s: SKIPPED (already gone)" % c["path"])
			continue
		var shell: PlanetBusterProjectile = scene.instantiate()
		get_tree().current_scene.add_child(shell)
		var offset: Vector3 = c["offset"]
		shell.global_position = target.global_position + offset
		var straight: Vector3 = -offset.normalized()
		# Deliberately a little off-axis, like a human's aim would be.
		var askew: Vector3 = straight.rotated(offset.cross(Vector3.UP).normalized(), deg_to_rad(c["askew_deg"]))
		shell.lock_target = target
		shell.launch(askew * 7.0, null)
		for frame in range(600):
			await get_tree().physics_frame
			if not is_instance_valid(shell):
				break
		# Ground truth is whether the target actually shattered, not just
		# whether the shell object went away - it also disappears on a plain
		# expire/out-of-bounds miss, which would otherwise misreport as a hit.
		var hit: bool = is_instance_valid(target) and target.is_shattered
		if hit:
			hits += 1
		results.append("%s: %s" % [target.name, "HIT" if hit else "MISS"])
		if is_instance_valid(shell):
			shell.queue_free()
	_log("BUSTER  intercept-vs-moving-target: %d/%d hit | %s" % [hits, cases.size(), ", ".join(results)])

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
	# BUGFIX - the ScopeLens glass sphere used to stay visible while scoped,
	# sitting right on the camera axis and fogging the whole view with a
	# translucent blue disc. It should hide for the scoped duration, same as
	# the rest of the viewmodel, and come back once un-scoped.
	var lens: MeshInstance3D = railgun.get_node("ViewModel/Scope/ScopeLens")
	var lens_hidden_while_scoped: bool = not lens.visible
	_player.probe_aim = false
	# Wait for the weapon to actually report un-scoped rather than a fixed
	# frame count - is_aiming/tick() ordering can leave one boundary frame
	# where the flag hasn't propagated yet, which a short fixed wait can
	# occasionally land on and misreport as a stuck-hidden lens.
	for i in range(120):
		await get_tree().physics_frame
		if not railgun.is_scoped():
			break
	var lens_visible_after_unscope: bool = lens.visible
	_log("SCOPE   ScopeLens hidden while scoped=%s | visible again after release=%s" % [
		lens_hidden_while_scoped, lens_visible_after_unscope])
	_player.probe_aim = true
	for i in range(60):
		await get_tree().physics_frame
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
	_log("SCOPE   scope_sensitivity_multiplier=%.4f (0.18 base * 1.3 retune = %.4f expected)" % [
		railgun.scope_sensitivity_multiplier, 0.18 * 1.3])
	hud.queue_free()
	_player.probe_aim = false

## NEW - scoping in should highlight every OTHER player bright red, but only
## for the actual local human (Player._is_local_view()), never for a bot's
## own AI-driven scope use sharing the same offline screen. Regular
## ProbePlayer always reports local_view=false (matching Bot.gd), so this
## needs ProbeLocalPlayer specifically to exercise the gated path at all.
func _test_scope_highlight() -> void:
	var scene: PackedScene = load("res://scenes/player/Player.tscn")

	var local: Player = scene.instantiate()
	local.set_script(ProbeLocalPlayer)
	local.name = "HighlightLocal"
	_arena.get_node("Players").add_child(local, true)
	local.player_id = 201
	await get_tree().physics_frame

	var bystander: Player = scene.instantiate()
	bystander.set_script(ProbePlayer)
	bystander.name = "HighlightBystander"
	_arena.get_node("Players").add_child(bystander, true)
	bystander.player_id = 202
	await get_tree().physics_frame

	var remote_scoper: Player = scene.instantiate()
	remote_scoper.set_script(ProbePlayer)
	remote_scoper.name = "HighlightRemoteScoper"
	_arena.get_node("Players").add_child(remote_scoper, true)
	remote_scoper.player_id = 203
	await get_tree().physics_frame

	var base: Vector3 = _body.global_position + Vector3(0, _body.radius + 30.0, 0)
	for p in [local, bystander, remote_scoper]:
		p.disable_spawner()
		p.global_position = base
		p.velocity = Vector3.ZERO
		p.reset_frame()
	for i in range(10):
		await get_tree().physics_frame

	local.probe_switch = WEAPON_RAILGUN
	remote_scoper.probe_switch = WEAPON_RAILGUN
	for i in range(4):
		await get_tree().physics_frame

	# Local scopes in - bystander should light up.
	local.probe_aim = true
	for i in range(30):
		await get_tree().physics_frame
	var highlighted_while_scoped: bool = bystander._highlighted
	local.probe_aim = false
	for i in range(30):
		await get_tree().physics_frame
	var highlighted_after_release: bool = bystander._highlighted

	# Re-scope, then switch weapons mid-scope (the on_holster path, not a
	# plain release) - should also clear the highlight.
	local.probe_aim = true
	for i in range(30):
		await get_tree().physics_frame
	var highlighted_before_holster: bool = bystander._highlighted
	local.probe_switch = WEAPON_ROCKET
	for i in range(4):
		await get_tree().physics_frame
	var highlighted_after_holster: bool = bystander._highlighted
	local.probe_aim = false

	# A non-local scoper (stands in for a bot) should never highlight anyone.
	remote_scoper.probe_aim = true
	for i in range(30):
		await get_tree().physics_frame
	var highlighted_by_remote_scoper: bool = bystander._highlighted
	remote_scoper.probe_aim = false

	_log("HIGHLIGHT scope-in highlights bystander=%s -> release clears it=%s | before mid-scope holster=%s -> after=%s | non-local scoper ever highlights anyone=%s" % [
		highlighted_while_scoped, not highlighted_after_release, highlighted_before_holster, highlighted_after_holster, highlighted_by_remote_scoper])

	local.queue_free()
	bystander.queue_free()
	remote_scoper.queue_free()

## IMPROVEMENT - the bitchslap now swings a real first-person hand model
## through windup/slap/slam, visible only on the attacker's own local view -
## same "viewmodel, not everyone else's screen" rule every weapon already
## follows (see MeleeViewModel nested under WeaponManager in Player.tscn, and
## Player._ready() hiding WeaponManager wholesale for non-local views).
func _test_melee_hand_animation() -> void:
	var scene: PackedScene = load("res://scenes/player/Player.tscn")

	var local_attacker: Player = scene.instantiate()
	local_attacker.set_script(ProbeLocalPlayer)
	local_attacker.name = "MeleeAnimLocal"
	_arena.get_node("Players").add_child(local_attacker, true)
	local_attacker.player_id = 221
	await get_tree().physics_frame

	var remote_attacker: Player = scene.instantiate()
	remote_attacker.set_script(ProbePlayer)
	remote_attacker.name = "MeleeAnimRemote"
	_arena.get_node("Players").add_child(remote_attacker, true)
	remote_attacker.player_id = 222
	await get_tree().physics_frame

	var victim_a: Player = scene.instantiate()
	victim_a.set_script(ProbePlayer)
	victim_a.name = "MeleeAnimVictimA"
	_arena.get_node("Players").add_child(victim_a, true)
	victim_a.player_id = 223
	await get_tree().physics_frame

	var victim_b: Player = scene.instantiate()
	victim_b.set_script(ProbePlayer)
	victim_b.name = "MeleeAnimVictimB"
	_arena.get_node("Players").add_child(victim_b, true)
	victim_b.player_id = 224
	await get_tree().physics_frame

	var base: Vector3 = _body.global_position + Vector3(0, _body.radius + 30.0, 0)
	for p in [local_attacker, remote_attacker, victim_a, victim_b]:
		p.disable_spawner()
		p.global_position = base
		p.velocity = Vector3.ZERO
		p.reset_frame()
	for i in range(10):
		await get_tree().physics_frame

	var hand: Node3D = local_attacker.get_node("Head/Camera3D/WeaponManager/MeleeViewModel")
	var hidden_before: bool = not hand.visible

	local_attacker.melee.try_activate(victim_a)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var visible_during_windup: bool = hand.visible
	var displaced_during_windup: bool = hand.position.length() > 0.05

	var total: float = local_attacker.melee.windup_time + local_attacker.melee.slap_time + local_attacker.melee.slam_time
	var settle_frames: int = int(total * 60.0) + 30
	for i in range(settle_frames):
		await get_tree().physics_frame
	var hidden_after: bool = not hand.visible
	var victim_a_killed: bool = victim_a.is_dead

	# A non-local attacker (stands in for a bot's own slap) must never show
	# its hand to this screen.
	var remote_hand: Node3D = remote_attacker.get_node("Head/Camera3D/WeaponManager/MeleeViewModel")
	remote_attacker.melee.try_activate(victim_b)
	for i in range(settle_frames):
		await get_tree().physics_frame
	var remote_hand_ever_shown: bool = remote_hand.visible

	_log("MELEEANIM local attacker: hidden at rest=%s -> visible+moved during windup=%s (moved=%s) -> hidden again after full sequence=%s | victim killed=%s | remote (non-local) attacker's hand ever visible here=%s" % [
		hidden_before, visible_during_windup, displaced_during_windup, hidden_after, victim_a_killed, remote_hand_ever_shown])

	local_attacker.queue_free()
	remote_attacker.queue_free()
	victim_a.queue_free()
	victim_b.queue_free()

## NEW - reeling a hooked player all the way in (within 3m) should
## auto-trigger the Bitchslap via Melee's own targeting, not just detach.
func _test_grapple_auto_melee() -> void:
	var scene: PackedScene = load("res://scenes/player/Player.tscn")
	var shooter: Player = scene.instantiate()
	shooter.set_script(ProbePlayer)
	shooter.name = "GrappleShooter"
	_arena.get_node("Players").add_child(shooter, true)
	shooter.player_id = 211
	await get_tree().physics_frame

	var target: Player = scene.instantiate()
	target.set_script(ProbePlayer)
	target.name = "GrappleTarget"
	target.display_name = "GrappleVictim"
	_arena.get_node("Players").add_child(target, true)
	target.player_id = 212
	await get_tree().physics_frame

	# Grounded, not floating in open gravity - a free-floating pair drifts
	# apart under real gravity over the several seconds a pull can take,
	# which chases the test's own aim correction all over the sky instead of
	# testing the feature. Standing on a planet, facing each other, is also
	# the realistic case (grapple-then-slap is a close-quarters combo).
	var out: Vector3 = Vector3(0.3, 1.0, 0.2).normalized()
	var fwd: Vector3 = out.cross(Vector3.RIGHT).normalized()
	var tangent: Vector3 = out.cross(-fwd).normalized()
	for p in [shooter, target]:
		p.disable_spawner()
		p.velocity = Vector3.ZERO
	shooter.global_position = _body.global_position + out * (_body.radius + 1.2)
	# A flat tangent offset from a curved surface point lands slightly ABOVE
	# the true surface (chord vs. arc) - small on a large planet, but Ferrum's
	# radius (7m) makes even a modest offset pop up several metres, needing
	# longer than expected to fall back and settle. Kept short (6m, not 10)
	# and given a longer settle window so both players are actually resting
	# on the ground, not still mid-fall, when the hook fires.
	target.global_position = shooter.global_position + tangent * 6.0
	shooter.global_transform.basis = Basis(out.cross(-fwd).normalized(), out, -fwd).orthonormalized()
	target.global_transform.basis = Basis(out.cross(fwd).normalized(), out, fwd).orthonormalized()  # facing shooter
	shooter.reset_frame()
	target.reset_frame()
	for i in range(150):
		await get_tree().physics_frame

	shooter.probe_switch = WEAPON_GRAPPLE
	for i in range(4):
		await get_tree().physics_frame
	var hook: GrapplingHook = shooter.weapon_manager.get_active_weapon() as GrapplingHook
	# fire()'s aim_direction is the camera's exact forward vector, used as-is
	# from the MUZZLE's own origin (Weapon.gd: "independent of muzzle bob/sway") -
	# the two rays are parallel, not converging, so aiming the camera straight
	# at the target (aim_at(target)) actually sends the muzzle ray past it by
	# whatever the muzzle's own offset from the camera is. Aim from the
	# muzzle's position instead so the ray this weapon actually fires goes
	# exactly through the target, the same correction a real player would make
	# by adjusting for a visible offset-iron-sight/hip-fire weapon.
	var muzzle_origin: Vector3 = shooter.get_muzzle_transform().origin
	var to_target: Vector3 = (target.global_position - muzzle_origin).normalized()
	shooter.aim_at(shooter.camera.global_position + to_target * 100.0)
	shooter.probe_fire = true
	var reeled_in: bool = false
	var ever_pulled: bool = false
	var trace: Array[String] = []
	for i in range(360):
		await get_tree().physics_frame
		if not is_instance_valid(target):
			break
		muzzle_origin = shooter.get_muzzle_transform().origin
		to_target = (target.global_position - muzzle_origin).normalized()
		shooter.aim_at(shooter.camera.global_position + to_target * 100.0)
		var dist: float = target.global_position.distance_to(shooter.global_position)
		if dist < 3.5:
			reeled_in = true
		var pulling: bool = is_instance_valid(hook) and hook._hook_state == GrapplingHook.HookState.PULLING_TARGET
		if pulling:
			ever_pulled = true
		if i % 15 == 0:
			trace.append("%.1fm/state%d" % [dist, hook._hook_state if is_instance_valid(hook) else -1])
		if target.is_dead:
			break
		# Stop as soon as the first pull attempt has fully resolved (retracted
		# back to IDLE after having pulled) rather than holding fire for the
		# whole budget and letting it auto-refire and chase a target that may
		# have moved - one full attempt is what the test is measuring.
		if ever_pulled and is_instance_valid(hook) and hook._hook_state == GrapplingHook.HookState.IDLE:
			break
	shooter.probe_fire = false
	# try_activate() only STARTS the windup/slap/slam sequence (Melee.gd,
	# ~0.22s total) - the hook itself has already gone back to IDLE and
	# detached well before _resolve_hit() actually lands the kill, so the
	# loop above breaking out on hook-state alone would check target.is_dead
	# too early. Give the in-flight slap sequence room to finish.
	for i in range(30):
		await get_tree().physics_frame
		if is_instance_valid(target) and target.is_dead:
			break
	var target_died: bool = is_instance_valid(target) and target.is_dead
	var melee_cooldown_after: float = shooter.melee._cooldown_remaining if shooter.melee else -1.0
	_log("AUTOSLAP hook ever entered PULLING_TARGET=%s, reeled within melee range=%s | auto-triggered melee killed target=%s | shooter.melee cooldown after=%.2fs (>0 means try_activate() found and grabbed a target; 0 means every call whiffed Melee's own range/cone re-check)" % [
		ever_pulled, reeled_in, target_died, melee_cooldown_after])
	_log("AUTOSLAP trace (distance/HookState 0=IDLE 1=FLYING 2=PULLING_SELF 3=PULLING_TARGET 4=RETRACTING, every 15 frames) = [%s]" % ", ".join(trace))

	shooter.queue_free()
	if is_instance_valid(target):
		target.queue_free()

## NEW - a slug in FLYING state only recognises a hit as "landed" (StaticBody3D
## tagged with orbital_body meta) or "hit a player" (has_method("apply_damage")).
## A Tower/Bunker/Turret's plain wall geometry matches neither, so a slug that
## hits one is a candidate for silently going inert against the wall instead
## of landing, damaging, or expiring cleanly.
func _test_slug_vs_tower() -> void:
	var tower: Tower = null
	var host: OrbitalBody = null
	for body in GravityManager.get_bodies():
		for child in body.get_children():
			if child is Tower and tower == null:
				tower = child
				host = body
	if tower == null:
		_log("SLUGTOWER no tower found to test")
		return
	var wall_global: Vector3 = tower.to_global(tower._surface_transform(Vector3(tower.tower_width * 0.5, 3.0, 0.0)).origin)
	var outward: Vector3 = (wall_global - host.global_position).normalized()
	var spawn: Vector3 = wall_global + outward * 5.0

	var scene: PackedScene = load("res://scenes/weapons/Slug.tscn")
	var slug: Slug = scene.instantiate()
	get_tree().current_scene.add_child(slug)
	slug.global_position = spawn
	slug.velocity = (wall_global - spawn).normalized() * 20.0
	for i in range(120):
		await get_tree().physics_frame
	var alive: bool = is_instance_valid(slug)
	var state_after: String = "freed" if not alive else ("SLITHERING" if slug._state == Slug.State.SLITHERING else "FLYING")
	var residual_speed: float = slug.velocity.length() if alive else -1.0
	_log("SLUGTOWER slug fired straight at a tower wall: state after 2s = %s, still-alive=%s, residual speed=%.2f (FLYING+alive+near-zero speed means stuck against the wall, not landed/expired)" % [
		state_after, alive, residual_speed])
	if alive:
		slug.queue_free()

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
