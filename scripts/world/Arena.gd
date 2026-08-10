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
## (665). Bodies are spaced so that no two adjacent orbits can bring their
## surfaces - or a moon at full extension - into contact even when their phases
## line up: check `gap between orbit radii > sum of the two radii` before moving
## anything, and remember a moon adds (its orbit_radius + its radius) to how far
## its parent reaches.
##
## Sizes deliberately span a wide range, from 5m pebbles you can run around in
## seconds up to a 44m world, so fights on different planets feel different.
const ORBIT_DATA: Array[Dictionary] = [
	# The central binary - always present, never shatterable. Same orbit_speed
	# and opposite start angles keep them locked on opposite sides forever.
	{
		"name": "Alpha", "radius": 28.0, "surface_gravity": 19.0,
		"orbit_radius": 34.0, "orbit_speed": 0.1125, "start_angle": 0.0,
		"can_be_shattered": false, "color": Color(0.85, 0.65, 0.25),
	},
	{
		"name": "Beta", "radius": 13.0, "surface_gravity": 11.0,
		"orbit_radius": 25.0, "orbit_speed": 0.1125, "start_angle": PI,
		"can_be_shattered": false, "color": Color(0.35, 0.55, 0.85),
	},
	# Satellite planets - shatterable, spread out at different orbital radii and
	# tilted orbital planes so they don't all sweep through the same flat disc.
	{
		"name": "Ferrum", "radius": 7.0, "surface_gravity": 8.0,
		"orbit_radius": 115.0, "orbit_speed": 0.0525, "start_angle": 0.4,
		"orbit_axis": Vector3(0.18, 1.0, 0.05), "can_be_shattered": true,
		"color": Color(0.75, 0.3, 0.15),
	},
	{
		"name": "Cinder", "radius": 18.0, "surface_gravity": 14.0,
		"orbit_radius": 185.0, "orbit_speed": 0.042, "start_angle": 5.5,
		"orbit_axis": Vector3(0.24, 1.0, -0.14), "can_be_shattered": true,
		"color": Color(0.8, 0.45, 0.2),
	},
	{
		"name": "Verdant", "radius": 44.0, "surface_gravity": 26.0,
		"orbit_radius": 275.0, "orbit_speed": 0.035, "start_angle": 2.6,
		"orbit_axis": Vector3(-0.22, 1.0, 0.12), "can_be_shattered": true,
		"color": Color(0.25, 0.7, 0.35),
	},
	{
		"name": "Cobalt", "radius": 5.0, "surface_gravity": 6.0,
		"orbit_radius": 375.0, "orbit_speed": 0.025, "start_angle": 4.4,
		"orbit_axis": Vector3(0.05, 1.0, -0.28), "can_be_shattered": true,
		"color": Color(0.2, 0.55, 0.8),
	},
	{
		"name": "Umbra", "radius": 27.0, "surface_gravity": 18.0,
		"orbit_radius": 460.0, "orbit_speed": 0.0175, "start_angle": 1.5,
		"orbit_axis": Vector3(-0.12, 1.0, -0.2), "can_be_shattered": true,
		"color": Color(0.6, 0.3, 0.75),
	},
	{
		"name": "Halcyon", "radius": 36.0, "surface_gravity": 22.0,
		"orbit_radius": 570.0, "orbit_speed": 0.014, "start_angle": 3.7,
		"orbit_axis": Vector3(0.15, 1.0, 0.22), "can_be_shattered": true,
		"color": Color(0.85, 0.8, 0.55),
	},
	# Moons - orbit_pivot resolves to their parent's OrbitalBody at build
	# time, so they travel with it instead of around the arena center.
	{
		"name": "Cinder_Moon", "radius": 3.0, "surface_gravity": 4.0,
		"orbit_radius": 40.0, "orbit_speed": 0.325, "start_angle": 0.0,
		"orbit_axis": Vector3(0.1, 1.0, 0.3), "can_be_shattered": true,
		"color": Color(0.8, 0.55, 0.4), "parent": "Cinder",
	},
	{
		"name": "Verdant_Moon", "radius": 6.0, "surface_gravity": 7.0,
		"orbit_radius": 80.0, "orbit_speed": 0.225, "start_angle": 1.8,
		"orbit_axis": Vector3(-0.15, 1.0, 0.05), "can_be_shattered": true,
		"color": Color(0.55, 0.8, 0.6), "parent": "Verdant",
	},
	{
		"name": "Umbra_Moon", "radius": 4.0, "surface_gravity": 5.0,
		"orbit_radius": 54.0, "orbit_speed": 0.375, "start_angle": 3.5,
		"orbit_axis": Vector3(0.2, 1.0, -0.1), "can_be_shattered": true,
		"color": Color(0.75, 0.6, 0.85), "parent": "Umbra",
	},
]

const SPAWNS_PER_BODY: int = 4

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

## Scatters a mix of structures over every body big enough to hold them, so
## each planet has cover to fight around and interiors to fight through.
## Towers go on anything sizeable; small worlds get bunkers instead, where a
## radius-tall tower would be a stub not worth entering.
func _build_buildings() -> void:
	for body_name in _bodies_by_name:
		var body: OrbitalBody = _bodies_by_name[body_name]
		if body.radius < 5.0:
			continue  # moons and pebbles stay bare
		var count: int = randi_range(1, 3) if body.radius >= 15.0 else 1
		for i in range(count):
			var prefer_tower: bool = body.radius >= 12.0 and (i == 0 or randf() < 0.6)
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
				building.tower_height = body.radius
				building.floor_count = maxi(2, int(body.radius / 9.0))
				building.tower_width = clampf(body.radius * 0.28, 6.0, 11.0)
			body.add_child(building)
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
		var sp: Node3D = MatchState.get_random_spawn_point()
		if sp:
			bot.global_position = sp.global_position
			bot.global_transform.basis = sp.global_transform.basis

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
