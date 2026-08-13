extends Node
## Owns Artillery Gunship spawn timing: one enters 2 minutes after the match
## starts, and another 2 minutes after the last one leaves (destroyed, or -
## see Gunship.is_abandoned()/_check_left_arena - abandoned by its crew and
## pathfinds its own way back out past the boundary) - never more than one in
## the arena at a time. Server-authoritative, same as bot/player spawning in
## Arena.gd - offline play (no NetworkManager session) always counts as "the
## server" for this, exactly like Arena._ready() already treats it for its
## own initial spawns.

@export var gunship_scene: PackedScene
@export var spawn_delay: float = 120.0
## Kept inside the live arena boundary box by this much, same reasoning (and
## the same GravityManager.arena_bounds_min/max, not the single-sphere
## arena_half_extent() - the arena is far wider in X/Z than it is tall, so a
## sphere sized to the tightest face would spawn every ship absurdly close
## to the centre) as Spawner.SPAWN_BOUNDARY_MARGIN.
@export var spawn_inset: float = 60.0

@onready var _spawner: MultiplayerSpawner = $GunshipSpawner
@onready var _container: Node3D = $"../Gunships"

var _timer: float = 0.0
var _current: Gunship = null

func _ready() -> void:
	_timer = spawn_delay

func _is_authority() -> bool:
	return not NetworkManager.is_online or NetworkManager.is_server()

func _physics_process(delta: float) -> void:
	if not _is_authority():
		return
	if _current != null and not is_instance_valid(_current):
		_current = null
	if _current != null:
		return
	_timer -= delta
	if _timer <= 0.0:
		_spawn_gunship()

func _spawn_gunship() -> void:
	if gunship_scene == null or _container == null:
		return
	var ship: Gunship = gunship_scene.instantiate()
	ship.name = "Gunship_%d" % Time.get_ticks_msec()
	# global_position/look_at both need the node to already be inside the
	# tree (look_at outright refuses otherwise - "Use look_at_from_position()
	# instead" - and global_position silently no-ops), so add it as a child
	# first and only place it afterward.
	_container.add_child(ship, true)
	ship.set_multiplayer_authority(1) # host is always peer 1, see Arena.gd
	var spawn_pos: Vector3 = _boundary_entry_point()
	ship.global_position = spawn_pos
	# Face roughly toward the arena centre so it visibly enters rather than
	# spawning already flying away from everything.
	var inward: Vector3 = -spawn_pos.normalized() if spawn_pos.length() > 0.01 else Vector3.FORWARD
	ship.look_at(spawn_pos + inward, Vector3.UP if absf(inward.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT)
	_current = ship
	# Single source of truth for "it's gone", whatever the reason (destroyed,
	# or drifted past the boundary and despawned itself - see
	# Gunship._check_left_arena): the node actually leaving the tree, not the
	# `destroyed` signal alone, which only covers the health-reaching-zero
	# case and would leave this cooldown never restarting for the other one.
	ship.tree_exiting.connect(_on_gunship_gone, CONNECT_ONE_SHOT)

func _on_gunship_gone() -> void:
	_current = null
	_timer = spawn_delay

## Same technique as Spawner._random_boundary_point() (not shared code since
## Spawner has no class_name to call it through) and for the same reason: the
## arena's box is far wider in X/Z than it is tall, so pin one axis to a real
## face (GravityManager.arena_bounds_min/max) and randomize the other two,
## rather than a single sphere radius that would end up squashed down to
## whatever the THINNEST face allows.
func _boundary_entry_point() -> Vector3:
	var inset := Vector3.ONE * spawn_inset
	var bmin: Vector3 = GravityManager.arena_bounds_min() + inset
	var bmax: Vector3 = GravityManager.arena_bounds_max() - inset
	var p := Vector3(
		randf_range(minf(bmin.x, bmax.x), maxf(bmin.x, bmax.x)),
		randf_range(minf(bmin.y, bmax.y), maxf(bmin.y, bmax.y)),
		randf_range(minf(bmin.z, bmax.z), maxf(bmin.z, bmax.z)))
	match randi() % 3:
		0: p.x = bmax.x if randf() < 0.5 else bmin.x
		1: p.y = bmax.y if randf() < 0.5 else bmin.y
		_: p.z = bmax.z if randf() < 0.5 else bmin.z
	return p
