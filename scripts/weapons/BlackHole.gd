class_name BlackHole
extends Node3D
## Persistent hazard opened by a BlackHoleProjectile's impact. Pulls every
## player and in-flight projectile within `pull_radius` toward its center
## (inverse-distance falloff, same shape GravityManager.get_gravity_at()
## already uses for planets), and burns anyone caught inside the smaller
## `event_horizon_radius` for damage over time. Lasts `lifetime` seconds then
## dissipates.
##
## A plain Node3D driving its own manual sweep each physics frame, not an
## Area3D - the pull needs continuous per-node falloff by distance, not a
## one-shot enter/exit signal, and it has to reach projectiles (CharacterBody3D,
## no Area3D signals fire for those against a body-only Area) as well as
## players.

@export var pull_radius: float = 24.0
@export var event_horizon_radius: float = 4.5
@export var pull_strength: float = 55.0
@export var damage_per_second: float = 35.0
@export var lifetime: float = 10.0

var owner_player: Node = null
var _age: float = 0.0
var _visual: Node3D = null

func _ready() -> void:
	add_to_group("black_holes")
	_build_visual()

func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		_dissipate()
		return
	_pull_players(delta)
	_pull_projectiles(delta)
	if _visual:
		_visual.rotate_y(delta * 1.4)
		# Shrinks over its final second instead of just vanishing, so it reads
		# as dissipating rather than switching off.
		var t: float = clampf((lifetime - _age) / 1.0, 0.0, 1.0) if _age > lifetime - 1.0 else 1.0
		_visual.scale = Vector3.ONE * t

func _pull_players(delta: float) -> void:
	for node in get_tree().get_nodes_in_group("damageable"):
		if not is_instance_valid(node):
			continue
		var to_center: Vector3 = global_position - node.global_position
		var dist: float = to_center.length()
		if dist > pull_radius or dist < 0.05:
			continue
		var falloff: float = 1.0 - dist / pull_radius
		var accel: Vector3 = to_center.normalized() * pull_strength * falloff * falloff
		if node.has_method("apply_impulse"):
			var impulse: Vector3 = accel * delta
			if node.has_method("network_apply_impulse") and not node.is_multiplayer_authority():
				node.rpc_id(node.get_multiplayer_authority(), "network_apply_impulse", impulse)
			else:
				node.apply_impulse(impulse)
		if dist <= event_horizon_radius and node.has_method("apply_damage"):
			var dmg: float = damage_per_second * delta
			if node.has_method("network_apply_damage") and not node.is_multiplayer_authority():
				node.rpc_id(node.get_multiplayer_authority(), "network_apply_damage", dmg, owner_player.get_path() if owner_player else NodePath(), node.global_position, "Black Hole Gun")
			else:
				node.apply_damage(dmg, owner_player, node.global_position, "Black Hole Gun")

## Projectiles have no apply_impulse/network authority split (each one only
## ever exists on the peer that fired it), so this is a direct velocity nudge
## rather than the RPC-routed path players go through above.
func _pull_projectiles(delta: float) -> void:
	for node in get_tree().get_nodes_in_group("projectiles"):
		if not is_instance_valid(node) or node == self or not ("velocity" in node):
			continue
		var to_center: Vector3 = global_position - node.global_position
		var dist: float = to_center.length()
		if dist > pull_radius or dist < 0.05:
			continue
		var falloff: float = 1.0 - dist / pull_radius
		node.velocity += to_center.normalized() * pull_strength * falloff * falloff * delta

func _dissipate() -> void:
	Sfx.play_3d("collapse", global_position, 1.3, -2.0)
	queue_free()

func _build_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)

	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = event_horizon_radius * 0.55
	sphere.height = event_horizon_radius * 1.1
	core.mesh = sphere
	var core_mat := StandardMaterial3D.new()
	core_mat.albedo_color = Color(0.02, 0.0, 0.05)
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core.material_override = core_mat
	_visual.add_child(core)

	# Accretion ring - a flattened torus tilted at a random angle so every
	# black hole reads a little differently.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = event_horizon_radius * 0.7
	torus.outer_radius = pull_radius * 0.35
	ring.mesh = torus
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.7, 0.35, 1.0, 0.8)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.65, 0.3, 1.0)
	ring_mat.emission_energy_multiplier = 3.0
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = ring_mat
	ring.rotation = Vector3(randf_range(-0.5, 0.5), 0.0, randf_range(-0.5, 0.5))
	ring.scale = Vector3(1.0, 0.18, 1.0)
	_visual.add_child(ring)

	var light := OmniLight3D.new()
	light.light_color = Color(0.6, 0.3, 1.0)
	light.light_energy = 3.0
	light.omni_range = pull_radius * 0.6
	light.shadow_enabled = false
	_visual.add_child(light)
