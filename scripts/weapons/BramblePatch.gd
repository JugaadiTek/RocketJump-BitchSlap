class_name BramblePatch
extends Area3D
## Hazard left behind by a BramblesGrenade. Grows from nothing to max_radius
## over `grow_time` as a handful of randomly offset/sized clumps (not a single
## uniform circle - see _build_visual - so it reads as a chaotic, asymmetrical
## thicket rather than a neat ring), then sits there dealing damage over time
## and slowing/obscuring the vision of anyone standing in it until `lifetime`
## runs out.

@export var max_radius: float = 7.0
@export var grow_time: float = 3.0
@export var lifetime: float = 60.0
@export var damage_per_second: float = 12.0
## Set by whoever spawns this (BramblesGrenade) to the impact surface normal,
## so the patch's collision/visual sit flush with a curved planet surface
## instead of always facing world-up.
var up_direction: Vector3 = Vector3.UP

var owner_player: Node = null
var _age: float = 0.0
var _visual: Node3D = null
var _collider_shape: CollisionShape3D = null
## Players currently standing inside - tracked directly (not just via
## get_overlapping_bodies() each tick) so enter/exit hooks (speed debuff,
## vision overlay) fire exactly once each, not every physics frame.
var _inside: Dictionary = {}

func _ready() -> void:
	add_to_group("bramble_patches")
	collision_layer = 0
	collision_mask = 2 # players only
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_build_collision()
	_build_visual()
	scale = Vector3.ONE * 0.05 # starts as basically nothing, grows in _physics_process

func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		_dissipate()
		return
	var grow_t: float = clampf(_age / grow_time, 0.05, 1.0)
	scale = Vector3.ONE * grow_t
	_apply_dot(delta)

func _apply_dot(delta: float) -> void:
	for node in _inside.keys():
		if not is_instance_valid(node):
			continue
		if "is_dead" in node and node.is_dead:
			continue
		if not node.has_method("apply_damage"):
			continue
		var dmg: float = damage_per_second * delta
		if node.has_method("network_apply_damage") and not node.is_multiplayer_authority():
			node.rpc_id(node.get_multiplayer_authority(), "network_apply_damage", dmg, owner_player.get_path() if owner_player else NodePath(), node.global_position, "Brambles Launcher")
		else:
			node.apply_damage(dmg, owner_player, node.global_position, "Brambles Launcher")

func _on_body_entered(body: Node3D) -> void:
	if not body.has_method("apply_damage"):
		return
	_inside[body] = true
	if body.has_method("enter_brambles"):
		body.enter_brambles()
	if body.has_method("show_bramble_vision"):
		body.show_bramble_vision(true)

func _on_body_exited(body: Node3D) -> void:
	if not _inside.has(body):
		return
	_inside.erase(body)
	if is_instance_valid(body):
		if body.has_method("exit_brambles"):
			body.exit_brambles()
		if body.has_method("show_bramble_vision"):
			body.show_bramble_vision(false)

func _dissipate() -> void:
	# Anyone still standing in it when it expires needs their debuffs cleared
	# explicitly - they'll never get a body_exited signal for a patch that's
	# simply gone.
	for node in _inside.keys():
		if is_instance_valid(node):
			if node.has_method("exit_brambles"):
				node.exit_brambles()
			if node.has_method("show_bramble_vision"):
				node.show_bramble_vision(false)
	Sfx.play_3d("collapse", global_position, 0.9, -6.0)
	queue_free()

func _build_collision() -> void:
	_collider_shape = CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = max_radius
	shape.height = 2.5
	_collider_shape.shape = shape
	_collider_shape.transform = _oriented_transform(Vector3.ZERO)
	add_child(_collider_shape)

## `up_direction` may not be world-up (a patch planted on a curved planet
## surface), so both collision and every visual clump are built in a basis
## whose own +Y matches it, then simply placed there.
func _oriented_transform(pos: Vector3) -> Transform3D:
	var up: Vector3 = up_direction.normalized() if up_direction.length() > 0.1 else Vector3.UP
	var ref: Vector3 = Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var bx: Vector3 = up.cross(ref).normalized()
	var bz: Vector3 = bx.cross(up).normalized()
	return Transform3D(Basis(bx, up, bz), pos + up * 0.02)

## A handful of randomly placed/sized thorny clumps rather than one neat
## shape - each is its own small flattened, spiky mesh cluster offset from
## center by a random angle/radius, so the overall silhouette reads as a
## chaotic, asymmetrical patch instead of a uniform circle.
func _build_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	var clump_count: int = randi_range(7, 11)
	for i in range(clump_count):
		var angle: float = randf_range(0.0, TAU)
		var radius: float = sqrt(randf()) * max_radius * randf_range(0.5, 1.0)
		var local_pos: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * radius
		var clump := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = randf_range(0.7, 1.6)
		mesh.height = mesh.radius * randf_range(1.2, 2.2)
		clump.mesh = mesh
		var mat := StandardMaterial3D.new()
		var shade: float = randf_range(0.55, 0.85)
		mat.albedo_color = Color(0.25 * shade, 0.4 * shade, 0.1 * shade)
		mat.roughness = 0.9
		clump.material_override = mat
		clump.transform = _oriented_transform(local_pos)
		clump.rotate_y(randf_range(0.0, TAU))
		_visual.add_child(clump)
	var light := OmniLight3D.new()
	light.light_color = Color(0.4, 0.6, 0.15)
	light.light_energy = 1.2
	light.omni_range = max_radius * 1.3
	light.shadow_enabled = false
	light.position = up_direction.normalized() * 1.0 if up_direction.length() > 0.1 else Vector3.UP
	_visual.add_child(light)
