class_name OrbitalBody
extends Node3D
## A miniature planet. Two things happen here that are deliberately NOT
## realistic physics, per the design brief ("do not perfectly emulate
## physics, focus on fun gameplay"):
##
## 1. Orbits are simple circular/elliptical paths around a fixed pivot point,
##    driven by an angle that advances every frame - not force integration.
##    This keeps the arena's macro-motion predictable and readable even
##    though...
## 2. ...impacts (rockets, corpses, the planet buster) nudge the orbit's
##    radius/speed/inclination by a small random percentage, so the arena
##    layout drifts and gets slightly chaotic over a long match without ever
##    spiraling into something unplayable.
##
## Gravity pull that affects players/projectiles is handled separately by
## GravityManager, which reads `radius`, `surface_gravity` and
## `influence_radius` off of this node.

signal shattered(body: OrbitalBody)

@export_group("Shape")
@export var radius: float = 40.0:
	set(v):
		radius = v
		_apply_visual_scale()

@export_group("Gravity")
## Acceleration (m/s^2) felt by something standing on the surface.
@export var surface_gravity: float = 20.0
## Beyond this distance from the center, this body exerts no pull at all.
@export var influence_radius: float = 220.0

@export_group("Orbit")
## If null, this body is static (used for the arena's outermost anchor, if any).
@export var orbit_pivot: Node3D
@export var orbit_radius: float = 0.0
@export var orbit_speed: float = 0.0 ## radians/sec
@export var orbit_axis: Vector3 = Vector3.UP
@export var orbit_start_angle: float = 0.0

@export_group("Self rotation")
@export var spin_axis: Vector3 = Vector3.UP
@export var spin_speed: float = 0.1 ## radians/sec, purely cosmetic

@export_group("Destructible")
## If true, the planet buster can shatter this body. The two central binary
## bodies are usually left indestructible so there's always at least a couple
## of planets left standing.
@export var can_be_shattered: bool = true

var is_shattered: bool = false
var _orbit_angle: float = 0.0

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var collision: CollisionShape3D = $StaticBody3D/CollisionShape3D
@onready var static_body: StaticBody3D = $StaticBody3D

func _ready() -> void:
	add_to_group("orbital_bodies")
	_orbit_angle = orbit_start_angle
	_apply_visual_scale()
	static_body.set_meta("orbital_body", self)
	GravityManager.register_body(self)
	if orbit_pivot:
		_update_orbit_position()

func _apply_visual_scale() -> void:
	if not is_inside_tree():
		return
	if mesh:
		mesh.mesh.radius = radius
		mesh.mesh.height = radius * 2.0
	if collision and collision.shape is SphereShape3D:
		collision.shape.radius = radius

func _physics_process(delta: float) -> void:
	if is_shattered:
		return
	if orbit_pivot and orbit_speed != 0.0:
		_orbit_angle += orbit_speed * delta
		_update_orbit_position()
	if spin_speed != 0.0:
		rotate(spin_axis.normalized(), spin_speed * delta)

func _update_orbit_position() -> void:
	var axis := orbit_axis.normalized()
	# Build two vectors perpendicular to the orbit axis to sweep the circle.
	var reference := Vector3.RIGHT if abs(axis.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var tangent_a := axis.cross(reference).normalized()
	var tangent_b := axis.cross(tangent_a).normalized()
	var offset := (tangent_a * cos(_orbit_angle) + tangent_b * sin(_orbit_angle)) * orbit_radius
	global_position = orbit_pivot.global_position + offset

## Called by rockets, corpses, and other impacts. `impact_strength` is 0..1
## and scales how big a nudge the orbit gets (a rocket splash is a light
## nudge, a corpse slamming in is a bit more).
func perturb_orbit(impact_strength: float = 1.0) -> void:
	if is_shattered or orbit_pivot == null:
		return
	var strength_mult: float = clamp(impact_strength, 0.0, 3.0)
	var pct: float = randf_range(0.0001, 0.001) * strength_mult
	var sign_r: float = 1.0 if randf() < 0.5 else -1.0
	var sign_s: float = 1.0 if randf() < 0.5 else -1.0
	orbit_radius = max(orbit_radius * (1.0 + sign_r * pct), radius * 1.5)
	orbit_speed *= (1.0 + sign_s * pct)
	# Very occasionally tilt the orbit plane a hair for extra chaos.
	if randf() < 0.15:
		orbit_axis = (orbit_axis + Vector3(
			randf_range(-0.01, 0.01), randf_range(-0.01, 0.01), randf_range(-0.01, 0.01)
		)).normalized()

## Planet Buster hit this body: remove it from play, damage everyone nearby.
func shatter(blast_radius: float, blast_damage: float) -> void:
	if is_shattered:
		return
	is_shattered = true
	shattered.emit(self)
	static_body.set_collision_layer_value(1, false)
	static_body.set_collision_mask_value(1, false)
	mesh.visible = false
	_spawn_debris()
	for node in get_tree().get_nodes_in_group("damageable"):
		if not is_instance_valid(node):
			continue
		var dist: float = node.global_position.distance_to(global_position)
		if dist <= blast_radius:
			var falloff: float = 1.0 - (dist / blast_radius)
			if node.has_method("apply_damage"):
				node.apply_damage(blast_damage * falloff, self, global_position)
	# The planet is gone for the rest of the match; free it after debris FX.
	await get_tree().create_timer(4.0).timeout
	GravityManager.unregister_body(self)
	queue_free()

func _spawn_debris() -> void:
	var particles := GPUParticles3D.new()
	add_child(particles)
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = radius * 0.5
	mat.initial_velocity_max = radius * 1.5
	mat.gravity = Vector3.ZERO
	mat.scale_min = radius * 0.05
	mat.scale_max = radius * 0.15
	particles.process_material = mat
	particles.draw_pass_1 = BoxMesh.new()
	particles.amount = 64
	particles.lifetime = 3.0
	particles.one_shot = true
	particles.emitting = true
	particles.explosiveness = 1.0
