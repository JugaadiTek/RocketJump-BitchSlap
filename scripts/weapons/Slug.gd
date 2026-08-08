class_name Slug
extends Projectile
## The "alien slug" - a slow projectile that actively steers toward the
## nearest enemy player within its tracking cone once launched, rather than
## flying in a straight line. Still affected by planet gravity, so it can
## curve in unexpected ways when a planet's pull fights its homing turn.

@export var damage: float = 40.0
@export var turn_rate_degrees: float = 90.0 ## max turn per second
@export var tracking_range: float = 60.0
@export var tracking_cone_degrees: float = 100.0
@export var speed: float = 10.0

var _target: Node3D = null

func _ready() -> void:
	super._ready()
	speed = velocity.length() if velocity.length() > 0.1 else speed

func _steer(delta: float) -> void:
	if _target != null and is_instance_valid(_target) and "is_dead" in _target and _target.is_dead:
		_target = null
	if _target == null or not is_instance_valid(_target):
		_target = _find_target()
	if _target == null:
		return

	var to_target: Vector3 = _target.global_position - global_position
	var dist: float = to_target.length()
	if dist > tracking_range:
		_target = null
		return

	var current_dir: Vector3 = velocity.normalized() if velocity.length() > 0.01 else -global_transform.basis.z
	var desired_dir: Vector3 = to_target.normalized()
	var max_turn: float = deg_to_rad(turn_rate_degrees) * delta
	var angle: float = current_dir.angle_to(desired_dir)
	var new_dir: Vector3
	if angle <= max_turn or angle < 0.0001:
		new_dir = desired_dir
	else:
		new_dir = current_dir.slerp(desired_dir, max_turn / angle)
	var current_speed: float = max(velocity.length(), speed)
	velocity = new_dir * current_speed
	if new_dir.length_squared() > 0.0001:
		look_at(global_position + new_dir, Vector3.UP if abs(new_dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT)

func _find_target() -> Node3D:
	var best: Node3D = null
	var best_dist: float = tracking_range
	var forward: Vector3 = velocity.normalized() if velocity.length() > 0.01 else -global_transform.basis.z
	for node in get_tree().get_nodes_in_group("damageable"):
		if node == owner_player or not is_instance_valid(node):
			continue
		if "is_dead" in node and node.is_dead:
			continue
		var to_node: Vector3 = node.global_position - global_position
		var dist: float = to_node.length()
		if dist > tracking_range or dist < 0.01:
			continue
		var angle_deg: float = rad_to_deg(forward.angle_to(to_node.normalized()))
		if angle_deg > tracking_cone_degrees * 0.5:
			continue
		if dist < best_dist:
			best_dist = dist
			best = node
	return best

func _on_hit(collider: Object, hit_position: Vector3, _hit_normal: Vector3) -> void:
	if collider == owner_player:
		return
	if collider and collider.has_method("apply_damage"):
		if collider.has_method("network_apply_damage") and not collider.is_multiplayer_authority():
			collider.rpc_id(collider.get_multiplayer_authority(), "network_apply_damage", damage, owner_player.get_path() if owner_player else NodePath(), hit_position, "Slug Launcher")
		else:
			collider.apply_damage(damage, owner_player, hit_position, "Slug Launcher")
	queue_free()
