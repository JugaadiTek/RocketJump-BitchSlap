extends Node3D
## Builds the starter arena: a central binary pair plus four smaller orbs
## sweeping around them at different radii/speeds. Bodies are instanced from
## a single OrbitalBody.tscn template rather than hand-placed, so tuning a
## planet is a one-line data change instead of editing a scene tree.
##
## Sizing note: with Player.max_ground_speed = 9 m/s, a circumference of
## ~135m takes ~15s to run around and ~1080m takes ~120s - that's where
## Luna's and Titan's radii below come from (radius = circumference / 2*PI).

const ORBIT_DATA: Array[Dictionary] = [
	# The central binary - always present, never shatterable.
	{
		"name": "Alpha", "radius": 45.0, "surface_gravity": 22.0,
		"orbit_radius": 70.0, "orbit_speed": 0.05, "start_angle": 0.0,
		"can_be_shattered": false, "color": Color(0.55, 0.48, 0.42),
	},
	{
		"name": "Beta", "radius": 35.0, "surface_gravity": 19.0,
		"orbit_radius": 55.0, "orbit_speed": 0.05, "start_angle": PI,
		"can_be_shattered": false, "color": Color(0.42, 0.46, 0.55),
	},
	# Outer orbs - shatterable by the Planet Buster.
	{
		"name": "Luna", "radius": 21.0, "surface_gravity": 14.0,
		"orbit_radius": 200.0, "orbit_speed": 0.026, "start_angle": 0.6,
		"can_be_shattered": true, "color": Color(0.6, 0.6, 0.62),
	},
	{
		"name": "Ceres", "radius": 60.0, "surface_gravity": 20.0,
		"orbit_radius": 320.0, "orbit_speed": 0.015, "start_angle": 2.4,
		"can_be_shattered": true, "color": Color(0.5, 0.35, 0.25),
	},
	{
		"name": "Vesta", "radius": 90.0, "surface_gravity": 23.0,
		"orbit_radius": 430.0, "orbit_speed": 0.010, "start_angle": 4.1,
		"can_be_shattered": true, "color": Color(0.35, 0.5, 0.4),
	},
	{
		"name": "Titan", "radius": 172.0, "surface_gravity": 26.0,
		"orbit_radius": 620.0, "orbit_speed": 0.006, "start_angle": 1.3,
		"can_be_shattered": true, "color": Color(0.45, 0.4, 0.55),
	},
]

const SPAWNS_PER_BODY: int = 3

@export var orbital_body_scene: PackedScene
@export var player_scene: PackedScene
@export var bot_scene: PackedScene
@export var bot_count: int = 3
@export var planet_buster_pickup_scene: PackedScene
@export var planet_buster_pad_bodies: Array[String] = ["Ceres", "Vesta"]

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
	for data in ORBIT_DATA:
		var body: OrbitalBody = orbital_body_scene.instantiate()
		orbital_bodies_container.add_child(body)
		body.name = data["name"]
		body.radius = data["radius"]
		body.surface_gravity = data["surface_gravity"]
		body.influence_radius = data["radius"] * 3.0
		body.orbit_pivot = orbit_center
		body.orbit_radius = data["orbit_radius"]
		body.orbit_speed = data["orbit_speed"]
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
