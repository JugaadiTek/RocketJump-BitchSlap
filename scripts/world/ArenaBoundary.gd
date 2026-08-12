extends MeshInstance3D
## Purely visual - the actual "in/out of bounds" gameplay logic lives in
## GravityManager.is_within_boundary()/arena_bounds_min()/arena_bounds_max(),
## which Player._apply_arena_bounds() and every Projectile check against.
##
## ONE box for the whole arena, sized (and now also POSITIONED - it is no
## longer always centred on the arena origin) to just contain whichever
## planet reaches furthest out in each of the six cardinal directions
## independently, plus a margin - see GravityManager's bounds functions. It
## flexes as orbits drift and planets get destroyed, and it can be a
## genuinely rectangular box now (a single far-flung planet only pushes out
## the faces it actually reaches toward), but there is still only ever this
## one shell: it does NOT track individual planets, so it never shows up as
## a wall out in open space between two worlds the way a per-planet box
## would. The shader (arena_boundary.gdshader) still only fades it in as the
## camera actually nears a wall, so under normal play - anywhere well inside
## the box - it stays invisible.

func _ready() -> void:
	# Own copy - resized every frame below, so it can't share the resource
	# with anything else that might load this same scene.
	if mesh is BoxMesh:
		mesh = mesh.duplicate()

func _process(_delta: float) -> void:
	var bmin: Vector3 = GravityManager.arena_bounds_min()
	var bmax: Vector3 = GravityManager.arena_bounds_max()
	if mesh is BoxMesh:
		(mesh as BoxMesh).size = bmax - bmin
	global_position = (bmin + bmax) * 0.5
