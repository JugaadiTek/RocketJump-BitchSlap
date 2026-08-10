class_name SpaceBoard
extends Weapon
## Held like a boogie board in front of the player. Only switchable and
## usable when off a planet surface. Firing (holding fire) applies a boost
## in the camera's look direction; gives strong 3D steering during orbital
## arcs. No cooldown while held — it's a continuous thrust.

@export var thrust_force: float = 28.0
@export var max_boost_speed: float = 55.0

func _init() -> void:
	weapon_name = "Space Board"
	fire_cooldown = 0.0
	weapon_color = Color(0.9, 0.75, 0.2)

func can_fire() -> bool:
	if owner_player == null:
		return false
	var p: Player = owner_player as Player
	if p == null:
		return false
	# Only usable when not touching a planet
	return not p.is_on_floor() and _cooldown_remaining <= 0.0

func _do_fire(muzzle_transform: Transform3D, aim_direction: Vector3) -> void:
	if owner_player == null:
		return
	var p: Player = owner_player as Player
	if p == null:
		return
	var current_speed: float = p.velocity.length()
	if current_speed < max_boost_speed:
		var boost: Vector3 = aim_direction * thrust_force * get_physics_process_delta_time()
		p.apply_impulse(boost)
	_cooldown_remaining = 0.05  ## tiny cooldown so fire() can be called continuously
