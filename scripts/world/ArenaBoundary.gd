extends MeshInstance3D
## Purely visual - the actual "push back toward nearest planet" gameplay
## logic lives in Player._apply_arena_bounds(), keyed off the same
## GravityManager.ARENA_BOUNDARY_RADIUS this shell sizes itself to. Kept as
## a single big sphere at the arena center; the shader (arena_boundary.
## gdshader) handles fading it in only when the camera is actually close.

func _ready() -> void:
	var radius: float = GravityManager.ARENA_BOUNDARY_RADIUS
	if mesh is SphereMesh:
		mesh = mesh.duplicate()
		mesh.radius = radius
		mesh.height = radius * 2.0
