extends MeshInstance3D
## Purely visual - the actual "in/out of bounds" gameplay logic lives in
## GravityManager.is_within_boundary()/arena_half_extent(), which
## Player._apply_arena_bounds() and every Projectile check against.
##
## ONE box for the whole arena, centred on the arena origin, sized to just
## contain whichever planet currently reaches furthest out (plus a margin) -
## see GravityManager.arena_half_extent(). It flexes as orbits drift and
## planets get destroyed, but there is only ever this single shell: it does
## NOT track individual planets, so it never shows up as a wall out in open
## space between two worlds the way a per-planet box would. The shader
## (arena_boundary.gdshader) still only fades it in as the camera actually
## nears a wall, so under normal play - anywhere well inside the box - it
## stays invisible.

func _ready() -> void:
	# Own copy - resized every frame below, so it can't share the resource
	# with anything else that might load this same scene.
	if mesh is BoxMesh:
		mesh = mesh.duplicate()

func _process(_delta: float) -> void:
	if mesh is BoxMesh:
		var half: float = GravityManager.arena_half_extent()
		(mesh as BoxMesh).size = Vector3.ONE * (half * 2.0)
	global_position = Vector3.ZERO
