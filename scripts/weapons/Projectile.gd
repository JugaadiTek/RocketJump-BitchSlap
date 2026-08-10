class_name Projectile
extends CharacterBody3D
## Shared movement for slow projectiles. Uses CharacterBody3D purely for its
## swept move_and_collide() - these aren't "characters", but it gives us
## robust collision detection against the planets' curved surfaces without
## tunneling through them at low speeds, which a plain Area3D + per-frame
## position write would risk.
##
## Affected by GravityManager just like players, which is what produces the
## slingshot arcs around planets the design calls for.

@export var affected_by_gravity: bool = true
@export var lifetime: float = 12.0
@export var gravity_multiplier: float = 1.0

var owner_player: Node = null
var _life_remaining: float

func _ready() -> void:
	_life_remaining = lifetime
	# Projectiles ignore the layer their own owner is on for the first few
	# frames is handled by the weapon (it starts them clear of the player's
	# collider); here we just make sure we don't collide with other
	# projectiles or with NPC hitboxes we don't care about.
	collision_mask = 0
	collision_mask |= 1 # world / planets
	collision_mask |= 2 # players
	collision_mask |= 8 # npcs

func launch(initial_velocity: Vector3, shooter: Node) -> void:
	# Add the shooter's current velocity so the projectile doesn't appear to
	# shoot backwards when the player is moving fast (e.g. rocket fired while
	# sprinting should travel forward, not arc behind the player).
	var shooter_vel: Vector3 = Vector3.ZERO
	if shooter and "velocity" in shooter:
		shooter_vel = shooter.velocity
	velocity = initial_velocity + shooter_vel
	owner_player = shooter
	var dir: Vector3 = velocity.normalized() if velocity.length() > 0.01 else initial_velocity.normalized()
	if dir.length_squared() > 0.0001:
		look_at(global_position + dir, Vector3.UP if abs(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT)

func _physics_process(delta: float) -> void:
	_life_remaining -= delta
	if _life_remaining <= 0.0:
		_expire()
		return

	if affected_by_gravity:
		velocity += GravityManager.get_gravity_at(global_position) * gravity_multiplier * delta

	_steer(delta)

	var motion: Vector3 = velocity * delta
	var collision: KinematicCollision3D = move_and_collide(motion)
	if collision:
		_on_hit(collision.get_collider(), collision.get_position(), collision.get_normal())

## Override for homing behaviour (Slug).
func _steer(_delta: float) -> void:
	pass

func _on_hit(collider: Object, hit_position: Vector3, hit_normal: Vector3) -> void:
	pass # override

func _expire() -> void:
	queue_free()
