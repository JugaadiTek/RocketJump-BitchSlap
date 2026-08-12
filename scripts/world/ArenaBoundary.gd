extends MeshInstance3D
## Purely visual - the actual "in/out of bounds" gameplay logic lives in
## GravityManager.is_within_boundary(), which Player._apply_arena_bounds()
## and every Projectile check against.
##
## Used to be one giant sphere fixed at the arena centre. The boundary itself
## is no longer a single fixed shape - it's a box around whichever planet is
## nearest, sized BOUNDARY_MARGIN past that planet's own extents (see
## GravityManager) - so this shell now follows the LOCAL VIEWER specifically:
## every frame it resizes and repositions to wrap the box around whichever
## planet that one player is currently closest to, rather than representing
## an arena-wide edge that doesn't correspond to any single check anymore.
## The shader (arena_boundary.gdshader) still only fades it in as the camera
## actually nears a wall, so under normal play - anywhere comfortably inside
## the box - it stays invisible.

func _ready() -> void:
	# Own copy - resized every frame below, so it can't share the resource
	# with anything else that might load this same scene.
	if mesh is BoxMesh:
		mesh = mesh.duplicate()

func _process(_delta: float) -> void:
	var viewer: Player = GravityManager.find_local_viewer()
	if viewer == null:
		visible = false
		return
	var box: Dictionary = GravityManager.nearest_boundary_box(viewer.global_position)
	if box.is_empty():
		visible = false
		return
	visible = true
	var half: float = box["half_extent"]
	if mesh is BoxMesh:
		(mesh as BoxMesh).size = Vector3.ONE * (half * 2.0)
	global_position = (box["body"] as OrbitalBody).global_position
