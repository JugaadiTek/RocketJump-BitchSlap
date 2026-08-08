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

const ORBIT_DATA: Array[Dictionary] = [
	# The central binary - always present, never shatterable.
	{
		"name": "Alpha", "radius": 28.0, "surface_gravity": 20.0,
		"orbit_radius": 48.0, "orbit_speed": 0.045, "start_angle": 0.0,
		"can_be_shattered": false, "color": Color(0.85, 0.65, 0.25),
	},
	{
		"name": "Beta", "radius": 19.0, "surface_gravity": 16.0,
		"orbit_radius": 36.0, "orbit_speed": 0.045, "start_angle": PI,
		"can_be_shattered": false, "color": Color(0.35, 0.55, 0.85),
	},
	# Satellite planets - shatterable, spread far out at different orbital
	# radii and tilted orbital planes so they don't all sweep through the
	# same flat disc.
	{
		"name": "Ferrum", "radius": 15.0, "surface_gravity": 13.0,
		"orbit_radius": 230.0, "orbit_speed": 0.021, "start_angle": 0.4,
		"orbit_axis": Vector3(0.18, 1.0, 0.05), "can_be_shattered": true,
		"color": Color(0.75, 0.3, 0.15),
	},
	{
		"name": "Verdant", "radius": 33.0, "surface_gravity": 21.0,
		"orbit_radius": 360.0, "orbit_speed": 0.014, "start_angle": 2.6,
		"orbit_axis": Vector3(-0.22, 1.0, 0.12), "can_be_shattered": true,
		"color": Color(0.25, 0.7, 0.35),
	},
	{
		"name": "Cobalt", "radius": 9.0, "surface_gravity": 10.0,
		"orbit_radius": 480.0, "orbit_speed": 0.010, "start_angle": 4.4,
		"orbit_axis": Vector3(0.05, 1.0, -0.28), "can_be_shattered": true,
		"color": Color(0.2, 0.55, 0.8),
	},
	{
		"name": "Umbra", "radius": 24.0, "surface_gravity": 18.0,
		"orbit_radius": 610.0, "orbit_speed": 0.007, "start_angle": 1.5,
		"orbit_axis": Vector3(-0.12, 1.0, -0.2), "can_be_shattered": true,
		"color": Color(0.6, 0.3, 0.75),
	},
	# Moons - orbit_pivot resolves to their parent's OrbitalBody at build
	# time, so they travel with it instead of around the arena center.
	{
		"name": "Ferrum_Moon", "radius": 4.0, "surface_gravity": 6.0,
		"orbit_radius": 32.0, "orbit_speed": 0.13, "start_angle": 0.0,
		"orbit_axis": Vector3(0.1, 1.0, 0.3), "can_be_shattered": true,
		"color": Color(0.8, 0.55, 0.4), "parent": "Ferrum",
	},
	{
		"name": "Verdant_Moon", "radius": 6.0, "surface_gravity": 7.0,
		"orbit_radius": 56.0, "orbit_speed": 0.09, "start_angle": 1.8,
		"orbit_axis": Vector3(-0.15, 1.0, 0.05), "can_be_shattered": true,
		"color": Color(0.55, 0.8, 0.6), "parent": "Verdant",
	},
	{
		"name": "Umbra_Moon", "radius": 3.5, "surface_gravity": 5.0,
		"orbit_radius": 42.0, "orbit_speed": 0.15, "start_angle": 3.5,
		"orbit_axis": Vector3(0.2, 1.0, -0.1), "can_be_shattered": true,
		"color": Color(0.75, 0.6, 0.85), "parent": "Umbra",
	},
]

const SPAWNS_PER_BODY: int = 3

@export var orbital_body_scene: PackedScene
@export var player_scene: PackedScene
@export var bot_scene: PackedScene
@export var bot_count: int = 3
@export var planet_buster_pickup_scene: PackedScene
@export var planet_buster_pad_bodies: Array[String] = ["Verdant", "Umbra"]

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
		orbital_bodies_container.add_child(body)
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

func _spawn_bots() -> void:
	if bot_scene == null:
		return
	for i in range(bot_count):
		var bot: Player = bot_scene.instantiate()
		bots_container.add_child(bot)
		bot.name = "Bot_%d" % i
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

func _spawn_player(peer_id: int) -> void:
	if player_scene == null:
		return
	var player: Player = player_scene.instantiate()
	player.name = "Player_%d" % peer_id
	players_container.add_child(player)
	player.set_multiplayer_authority(peer_id)
	var sp: Node3D = MatchState.get_random_spawn_point()
	if sp:
		player.global_position = sp.global_position
		player.global_transform.basis = sp.global_transform.basis
