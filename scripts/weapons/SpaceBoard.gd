class_name SpaceBoard
extends Weapon
## Held like a boogie board in front of the player. Selecting it puts the player
## into free flight: while it's out, Player swaps its tangent-plane ground
## movement for full 6-axis thrust (WASD along the camera's own axes, jump/crouch
## along the current up) with gravity all but cancelled — see
## Player._apply_flight_movement. Holding fire adds an afterburner along the look
## direction on top of that. No cooldown; it's continuous thrust.

@export var thrust_force: float = 46.0
@export var max_boost_speed: float = 60.0

func _init() -> void:
	weapon_name = "Space Board"
	fire_cooldown = 0.0
	weapon_color = Color(0.9, 0.75, 0.2)

## Player polls this every physics frame to decide which movement model to run.
## `visible` is exactly "this is the weapon currently in hand" — WeaponManager
## maintains it, and it stays correct on remote peers whose whole WeaponManager
## node is hidden (that hides the subtree without touching this local flag).
func is_flight_active() -> bool:
	return visible

func can_fire() -> bool:
	return owner_player != null and _cooldown_remaining <= 0.0

func _do_fire(_muzzle_transform: Transform3D, aim_direction: Vector3) -> void:
	var p: Player = owner_player as Player
	if p == null:
		return
	# Written straight onto velocity rather than via apply_impulse(): flight
	# mode already bypasses ground-stick, so the impulse grace that
	# apply_impulse() grants would only linger after switching back off the
	# board and let the player skim off into orbit.
	if p.velocity.length() < max_boost_speed:
		p.velocity += aim_direction * thrust_force * get_physics_process_delta_time()
