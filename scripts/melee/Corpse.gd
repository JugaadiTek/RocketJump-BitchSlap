extends RigidBody3D
## Purely cosmetic flying body spawned by Melee.gd. Not networked beyond the
## initial spawn RPC - each peer simulates its own copy locally, which is
## fine since nothing gameplay-critical depends on where it ends up, only
## on whether it smacks into a planet along the way.

@export var despawn_after: float = 6.0
@export var min_impact_speed_to_perturb: float = 4.0

func _ready() -> void:
	gravity_scale = 0.0 # we apply our own gravity from GravityManager below
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(despawn_after).timeout.connect(func(): if is_instance_valid(self): queue_free())

func launch(impulse: Vector3) -> void:
	linear_velocity = impulse
	angular_velocity = Vector3(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0), randf_range(-4.0, 4.0))

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var gravity: Vector3 = GravityManager.get_gravity_at(global_position)
	state.linear_velocity += gravity * state.get_step()

func _on_body_entered(body: Node) -> void:
	var impact_speed: float = linear_velocity.length()
	if impact_speed < min_impact_speed_to_perturb:
		return
	if body is StaticBody3D and body.has_meta("orbital_body"):
		var orbital_body: OrbitalBody = body.get_meta("orbital_body")
		if is_instance_valid(orbital_body):
			orbital_body.perturb_orbit(clamp(impact_speed / 20.0, 0.3, 2.0))
