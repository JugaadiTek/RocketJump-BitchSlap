extends Node3D
## Builds the starter arena: a central binary pair, four satellite planets
## swept out around them at varied radii/speeds/orbital-plane tilts, and a
## moon orbiting three of those satellites (their `orbit_pivot` points at the
## parent planet's OrbitalBody instead of the shared center, so a moon's
## position naturally follows its parent as the parent itself circles the
## binary - see `_build_orbital_bodies()`).
##
## Bodies are instanced from a single OrbitalBody.tscn template rather than
## hand-placed, so tuning a planet is a one-line data change instead of
## editing a scene tree.

## Every orbit radius here is sized against GravityManager.ARENA_BOUNDARY_RADIUS
## (535). Bodies are spaced so that no two adjacent orbits can bring their
## surfaces - or a moon at full extension - into contact even when their phases
## line up: check `gap between orbit radii > sum of the two radii` before moving
## anything, and remember a moon adds (its orbit_radius + its radius) to how far
## its parent reaches.
##
## Sizes deliberately span a wide range, from 5m pebbles you can run around in
## seconds up to a 44m world, so fights on different planets feel different.
##
## One more constraint: orbit_radius must stay above radius * 1.5, because
## OrbitalBody.perturb_orbit() floors it there on every spawn landing - drop
## below and the first impact will snap the body outward. That floor is why the
## central binary sits wider than a straight scale-down would put it.
const ORBIT_DATA: Array[Dictionary] = [
	# The central binary - always present, never shatterable. Same orbit_speed
	# and opposite start angles keep them locked on opposite sides forever.
	{
		"name": "Alpha", "radius": 28.0, "surface_gravity": 19.0,
		"orbit_radius": 44.0, "orbit_speed": 0.1125, "start_angle": 0.0,
		"can_be_shattered": false, "color": Color(0.85, 0.65, 0.25),
	},
	{
		"name": "Beta", "radius": 13.0, "surface_gravity": 11.0,
		"orbit_radius": 30.0, "orbit_speed": 0.1125, "start_angle": PI,
		"can_be_shattered": false, "color": Color(0.35, 0.55, 0.85),
	},
	# Satellite planets - shatterable, spread out at different orbital radii and
	# tilted orbital planes so they don't all sweep through the same flat disc.
	{
		"name": "Ferrum", "radius": 7.0, "surface_gravity": 8.0,
		"orbit_radius": 85.0, "orbit_speed": 0.0525, "start_angle": 0.4,
		"orbit_axis": Vector3(0.18, 1.0, 0.05), "can_be_shattered": true,
		"color": Color(0.75, 0.3, 0.15),
	},
	{
		"name": "Cinder", "radius": 18.0, "surface_gravity": 14.0,
		"orbit_radius": 130.0, "orbit_speed": 0.042, "start_angle": 5.5,
		"orbit_axis": Vector3(0.24, 1.0, -0.14), "can_be_shattered": true,
		"color": Color(0.8, 0.45, 0.2),
	},
	{
		"name": "Verdant", "radius": 44.0, "surface_gravity": 26.0,
		"orbit_radius": 210.0, "orbit_speed": 0.035, "start_angle": 2.6,
		"orbit_axis": Vector3(-0.22, 1.0, 0.12), "can_be_shattered": true,
		"color": Color(0.25, 0.7, 0.35),
	},
	{
		"name": "Cobalt", "radius": 5.0, "surface_gravity": 6.0,
		"orbit_radius": 290.0, "orbit_speed": 0.025, "start_angle": 4.4,
		"orbit_axis": Vector3(0.05, 1.0, -0.28), "can_be_shattered": true,
		"color": Color(0.2, 0.55, 0.8),
	},
	{
		"name": "Umbra", "radius": 27.0, "surface_gravity": 18.0,
		"orbit_radius": 350.0, "orbit_speed": 0.0175, "start_angle": 1.5,
		"orbit_axis": Vector3(-0.12, 1.0, -0.2), "can_be_shattered": true,
		"color": Color(0.6, 0.3, 0.75),
	},
	{
		"name": "Halcyon", "radius": 36.0, "surface_gravity": 22.0,
		"orbit_radius": 440.0, "orbit_speed": 0.014, "start_angle": 3.7,
		"orbit_axis": Vector3(0.15, 1.0, 0.22), "can_be_shattered": true,
		"color": Color(0.85, 0.8, 0.55),
	},
	# Moons - orbit_pivot resolves to their parent's OrbitalBody at build
	# time, so they travel with it instead of around the arena center.
	{
		"name": "Cinder_Moon", "radius": 3.0, "surface_gravity": 4.0,
		"orbit_radius": 32.0, "orbit_speed": 0.325, "start_angle": 0.0,
		"orbit_axis": Vector3(0.1, 1.0, 0.3), "can_be_shattered": true,
		"color": Color(0.8, 0.55, 0.4), "parent": "Cinder",
	},
	{
		"name": "Verdant_Moon", "radius": 6.0, "surface_gravity": 7.0,
		"orbit_radius": 66.0, "orbit_speed": 0.225, "start_angle": 1.8,
		"orbit_axis": Vector3(-0.15, 1.0, 0.05), "can_be_shattered": true,
		"color": Color(0.55, 0.8, 0.6), "parent": "Verdant",
	},
	{
		"name": "Umbra_Moon", "radius": 4.0, "surface_gravity": 5.0,
		"orbit_radius": 48.0, "orbit_speed": 0.375, "start_angle": 3.5,
		"orbit_axis": Vector3(0.2, 1.0, -0.1), "can_be_shattered": true,
		"color": Color(0.75, 0.6, 0.85), "parent": "Umbra",
	},
]

const SPAWNS_PER_BODY: int = 4
## Below this radius a body stays bare - a building would be bigger than the rock.
const MIN_BUILDING_RADIUS: float = 5.0
## Slack left in the structure-height solve. structure_reach also counts roof
## and floor slabs on top of tower_height, so budgeting right up to the surface
## gap would still leave the two just touching.
const STRUCTURE_CLEARANCE_MARGIN: float = 2.0

@export var orbital_body_scene: PackedScene
@export var player_scene: PackedScene
@export var bot_scene: PackedScene
## Always 31 bots so total player count (1 human + 31) == 32.
## In multiplayer, bots fill slots not taken by human peers.
@export var bot_count: int = 31
@export var planet_buster_pickup_scene: PackedScene
@export var planet_buster_pad_bodies: Array[String] = ["Verdant", "Umbra"]
@export var jump_pad_scene: PackedScene
@export var jump_pad_bodies: Array[String] = ["Alpha", "Beta", "Ferrum", "Cobalt"]
@export var tower_scene: PackedScene
@export var bunker_scene: PackedScene
@export var health_pack_scene: PackedScene

@onready var orbit_center: Node3D = $OrbitCenter
@onready var orbital_bodies_container: Node3D = $OrbitalBodies
@onready var spawn_points_container: Node3D = $SpawnPoints
@onready var players_container: Node3D = $Players
@onready var bots_container: Node3D = $Bots

var _bodies_by_name: Dictionary = {}

func _ready() -> void:
	_build_orbital_bodies()
	_build_spawn_points()
	_build_planet_buster_pads()
	_build_jump_pads()
	_build_buildings()
	_build_health_packs()
	_build_debris_field()

	if NetworkManager.is_online:
		NetworkManager.player_joined.connect(_on_player_joined)
		NetworkManager.player_left.connect(_on_player_left)
		if NetworkManager.is_server():
			_spawn_bots()
			# The host is also peer 1 - spawn ourselves too.
			_spawn_player(multiplayer.get_unique_id())
	else:
		_spawn_player(1)
		_spawn_bots()


func _build_orbital_bodies() -> void:
	# ORBIT_DATA lists every moon after its parent planet, so by the time we
	# reach a "parent" entry, _bodies_by_name already has that planet's node.
	for data in ORBIT_DATA:
		var body: OrbitalBody = orbital_body_scene.instantiate()
		body.name = data["name"]
		body.radius = data["radius"]
		body.surface_gravity = data["surface_gravity"]
		body.influence_radius = data["radius"] * 3.5
		var parent_name: String = data.get("parent", "")
		body.orbit_pivot = _bodies_by_name[parent_name] if parent_name != "" else orbit_center
		body.orbit_radius = data["orbit_radius"]
		body.orbit_speed = data["orbit_speed"]
		body.orbit_axis = (data.get("orbit_axis", Vector3.UP) as Vector3).normalized()
		body.orbit_start_angle = data["start_angle"]
		body.can_be_shattered = data["can_be_shattered"]
		body.spin_speed = randf_range(0.02, 0.08) * (1.0 if randf() < 0.5 else -1.0)
		# Random tumble axis, not just polar spin, so no two planets present the
		# same face the same way and surfaces stay interesting to fight across.
		body.spin_axis = Vector3(
			randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)
		).normalized()
		body._orbit_template = orbital_body_scene
		# Every export above MUST be set before add_child() - add_child()
		# triggers _ready() synchronously, and _ready() copies
		# orbit_start_angle into its internal _orbit_angle. Setting
		# orbit_start_angle any later would silently be ignored, and every
		# body would start at angle 0 regardless of its intended phase
		# (which is exactly what caused Alpha/Beta, meant to start on
		# opposite sides, to instead start on top of each other).
		orbital_bodies_container.add_child(body)
		var mesh: MeshInstance3D = body.get_node("MeshInstance3D")
		var mat: StandardMaterial3D = mesh.get_surface_override_material(0)
		if mat:
			mat.albedo_color = data["color"]
		_bodies_by_name[data["name"]] = body

func _build_spawn_points() -> void:
	# Scatter spawn points around every body's surface so respawns aren't
	# clustered on just the two central planets.
	for body_name in _bodies_by_name:
		var body: OrbitalBody = _bodies_by_name[body_name]
		for i in range(SPAWNS_PER_BODY):
			var dir := Vector3(
				randf_range(-1.0, 1.0), randf_range(0.2, 1.0), randf_range(-1.0, 1.0)
			).normalized()
			var point := Marker3D.new()
			spawn_points_container.add_child(point)
			point.name = "%s_Spawn%d" % [body_name, i]
			# Parented directly under the body so spawn points travel with
			# their planet's orbit instead of staying fixed in world space.
			point.reparent(body, false)
			point.position = dir * (body.radius + 1.2)
			MatchState.register_spawn_point(point)

func _build_planet_buster_pads() -> void:
	if planet_buster_pickup_scene == null:
		return
	for body_name in planet_buster_pad_bodies:
		var body: OrbitalBody = _bodies_by_name.get(body_name)
		if body == null:
			continue
		var pad := planet_buster_pickup_scene.instantiate()
		body.add_child(pad)
		var dir := Vector3(randf_range(-1, 1), randf_range(0.3, 1), randf_range(-1, 1)).normalized()
		pad.position = dir * (body.radius + 0.5)
		pad.look_at(pad.global_position + dir, Vector3.UP if abs(dir.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT)

func _build_jump_pads() -> void:
	if jump_pad_scene == null:
		return
	for body_name in jump_pad_bodies:
		var body: OrbitalBody = _bodies_by_name.get(body_name)
		if body == null:
			continue
		var pad := jump_pad_scene.instantiate()
		body.add_child(pad)
		var dir := Vector3(randf_range(-1, 1), randf_range(0.3, 1), randf_range(-1, 1)).normalized()
		# Build a basis with Y = dir (radially outward from the planet) - the
		# pad's script reads its own local up as the launch direction, so a
		# flat pad on the surface launches straight "up" relative to it.
		var reference: Vector3 = Vector3.RIGHT if abs(dir.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
		var basis_x: Vector3 = dir.cross(reference).normalized()
		var basis_z: Vector3 = basis_x.cross(dir).normalized()
		pad.transform = Transform3D(Basis(basis_x, dir, basis_z), dir * (body.radius + 0.1))

## Works out how tall each body's buildings may be.
##
## Towers want to be as tall as their planet's radius, which doubles that
## planet's effective footprint. Two bodies whose structures sweep through each
## other is fine - that IS the cross-planet collision feature, and GravityManager
## kicks both orbits when it happens. What is NOT fine is a pair that overlaps
## PERMANENTLY, because the encounter never ends and never stops re-triggering.
##
## That only happens for pairs whose separation is fixed: the phase-locked
## central binary (same pivot, same orbit speed, so they hold station forever)
## and a moon against its own parent. Those pairs get the constraint
## `heightA + heightB <= surface gap`, relaxed proportionally until it holds.
## Every other pair is left alone to collide transiently as designed.
func _solve_structure_heights() -> Dictionary:
	var names: Array = _bodies_by_name.keys()
	var heights: Dictionary = {}
	for n in names:
		# Bodies too small to carry a building claim no height, so they don't
		# eat into a neighbour's budget for structures they'll never have.
		var body: OrbitalBody = _bodies_by_name[n]
		heights[n] = float(body.radius) if body.radius >= MIN_BUILDING_RADIUS else 0.0

	for _pass in range(12):
		var adjusted: bool = false
		for i in range(names.size()):
			for j in range(i + 1, names.size()):
				var a: OrbitalBody = _bodies_by_name[names[i]]
				var b: OrbitalBody = _bodies_by_name[names[j]]
				var clearance: float = _fixed_separation_clearance(a, b)
				if clearance == INF:
					continue  # separation varies; transient contact is allowed
				var excess: float = heights[names[i]] + heights[names[j]] - clearance
				if excess <= 0.01:
					continue
				# Trim both in proportion to their current height, so a big
				# tower gives up more than a small one.
				var total: float = maxf(heights[names[i]] + heights[names[j]], 0.001)
				heights[names[i]] = maxf(heights[names[i]] - excess * (heights[names[i]] / total), 0.0)
				heights[names[j]] = maxf(heights[names[j]] - excess * (heights[names[j]] / total), 0.0)
				adjusted = true
		if not adjusted:
			break
	return heights

## Surface gap between two bodies whose separation never changes, or INF if it
## does change (in which case any contact is a passing event, not a standing
## overlap, and buildings are free to be as tall as they like).
func _fixed_separation_clearance(a: OrbitalBody, b: OrbitalBody) -> float:
	var centre_distance: float
	if a.orbit_pivot == b:
		centre_distance = a.orbit_radius       # a is b's moon: fixed radius
	elif b.orbit_pivot == a:
		centre_distance = b.orbit_radius
	elif a.orbit_pivot == b.orbit_pivot and is_equal_approx(a.orbit_speed, b.orbit_speed):
		# Phase-locked (the central binary) - they hold station forever, so the
		# current distance is the permanent one.
		centre_distance = a.global_position.distance_to(b.global_position)
	else:
		return INF
	return centre_distance - a.radius - b.radius - STRUCTURE_CLEARANCE_MARGIN

## Scatters a mix of structures over every body big enough to hold them, so
## each planet has cover to fight around and interiors to fight through.
## Towers go on anything sizeable; small worlds get bunkers instead, where a
## radius-tall tower would be a stub not worth entering.
func _build_buildings() -> void:
	var allowed_height: Dictionary = _solve_structure_heights()
	for body_name in _bodies_by_name:
		var body: OrbitalBody = _bodies_by_name[body_name]
		if body.radius < MIN_BUILDING_RADIUS:
			continue  # moons and pebbles stay bare
		var height_budget: float = allowed_height.get(body_name, body.radius)
		if height_budget < 3.0:
			continue  # no room here without grinding into a neighbour
		var count: int = randi_range(1, 3) if body.radius >= 15.0 else 1
		for i in range(count):
			var prefer_tower: bool = body.radius >= 12.0 and height_budget >= 9.0 and (i == 0 or randf() < 0.6)
			var scene: PackedScene = tower_scene if prefer_tower else bunker_scene
			if scene == null:
				scene = tower_scene if tower_scene else bunker_scene
			if scene == null:
				return
			var building: Node3D = scene.instantiate()
			# Every export MUST be set before add_child(): add_child() runs
			# _ready() synchronously and Building._ready() builds the geometry
			# there and then, so anything assigned afterwards is ignored. That
			# is exactly why towers used to come out a fixed 30m tall instead
			# of matching their planet.
			if building is Tower:
				# Target is the planet's own radius; the solver above only trims
				# it where a neighbour would otherwise be clipped.
				building.tower_height = minf(body.radius, height_budget)
				building.floor_count = maxi(2, int(building.tower_height / 9.0))
				building.tower_width = clampf(body.radius * 0.28, 6.0, 11.0)
			elif building is Bunker:
				building.bunker_height = clampf(height_budget * 0.8, 3.0, 4.5)
				# Footprint capped against the planet: an 11m bunker on a 5m
				# pebble would wrap most of the way round it.
				building.bunker_width = clampf(body.radius * 0.8, 5.0, 11.0)
				building.bunker_depth = building.bunker_width * 0.72
			# Lets the building work out how far the surface curves away beneath
			# its flat base, so its foundation can fill that gap instead of
			# leaving the outer corners hanging in the air.
			building.host_radius = body.radius
			body.add_child(building)
			body.note_structure(building.structure_height())
			# Orient so the building's local +Y points radially outward from the
			# planet surface (the planet's local "up" at that spot).
			var rand_angle: float = randf_range(0.0, TAU)
			var polar: float = randf_range(0.2, 0.85) # avoid exact poles
			var surface_dir := Vector3(
				sin(polar) * cos(rand_angle),
				cos(polar),
				sin(polar) * sin(rand_angle)
			).normalized()
			var ref: Vector3 = Vector3.RIGHT if abs(surface_dir.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
			var bx: Vector3 = surface_dir.cross(ref).normalized()
			var bz: Vector3 = bx.cross(surface_dir).normalized()
			building.transform = Transform3D(Basis(bx, surface_dir, bz), surface_dir * body.radius)

## Health packs on every planet, count scaled to surface area so a 44m world
## isn't as sparsely stocked as a 5m pebble.
func _build_health_packs() -> void:
	if health_pack_scene == null:
		return
	for body_name in _bodies_by_name:
		var body: OrbitalBody = _bodies_by_name[body_name]
		var count: int = clampi(1 + int(body.radius / 9.0), 1, 6)
		for i in range(count):
			var pack: Node3D = health_pack_scene.instantiate()
			body.add_child(pack)
			var dir := Vector3(
				randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)
			).normalized()
			# +Y points radially outward, matching how buildings and pads sit.
			var ref: Vector3 = Vector3.RIGHT if absf(dir.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
			var bx: Vector3 = dir.cross(ref).normalized()
			var bz: Vector3 = bx.cross(dir).normalized()
			pack.transform = Transform3D(Basis(bx, dir, bz), dir * (body.radius + 0.1))

## Asteroid rubble filling the space between the planets. Built after the bodies
## exist so it can steer clear of their orbital tracks.
func _build_debris_field() -> void:
	var field := DebrisField.new()
	field.name = "DebrisField"
	field.inner_radius = 70.0
	field.outer_radius = GravityManager.ARENA_BOUNDARY_RADIUS * 0.92
	add_child(field)

func _spawn_bots() -> void:
	if bot_scene == null:
		return
	for i in range(bot_count):
		var bot: Player = bot_scene.instantiate()
		bots_container.add_child(bot)
		bot.name = "Bot_%d" % i
		# Negative ids can never collide with a real ENet peer id (always
		# >= 1), so bots stay distinct from real players and each other in
		# the scoreboard/kill-counter regardless of multiplayer_authority
		# (which defaults to the same id 1 as the real local player offline).
		bot.player_id = -(i + 1)
		# Bot.gd._ready() already picked a random name from BOT_NAMES; just
		# re-register it with MatchState now that player_id is also set.
		MatchState.register_player(bot.player_id, bot.display_name)
		# Position and facing are deliberately NOT set here: bots run the same
		# Spawner flow humans do (boundary -> choose a planet -> fly in on a red
		# trail -> crater the surface on landing), so overriding their transform
		# now would just teleport them straight out of that sequence.

func _on_player_joined(peer_id: int) -> void:
	if not NetworkManager.is_server():
		return
	if peer_id == multiplayer.get_unique_id():
		return # host already spawned itself in _ready()
	_spawn_player(peer_id)

func _on_player_left(peer_id: int) -> void:
	if not NetworkManager.is_server():
		return
	var node := players_container.get_node_or_null("Player_%d" % peer_id)
	if node:
		node.queue_free()
	MatchState.unregister_player(peer_id)

func _spawn_player(peer_id: int) -> void:
	if player_scene == null:
		return
	var player: Player = player_scene.instantiate()
	player.name = "Player_%d" % peer_id
	players_container.add_child(player)
	player.set_multiplayer_authority(peer_id)
	player.player_id = peer_id
	player.display_name = "Player %d" % peer_id
	MatchState.register_player(player.player_id, player.display_name)
	# Position and facing are handled by the Spawner (Player._start_spawn_sequence)
	# which places the player on the boundary sphere, facing inward.
