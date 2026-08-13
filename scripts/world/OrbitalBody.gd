class_name OrbitalBody
extends Node3D

signal shattered(body: OrbitalBody)
signal fragment_spawned(fragment: OrbitalBody)

## The hue-rotating, bump-mapped surface shader every planet's material uses -
## see _apply_bump_pattern(). Needed here (not just in the .tscn) because
## spawned moon fragments build their material from scratch in code.
const PLANET_SURFACE_SHADER: Shader = preload("res://scenes/world/planet_surface.gdshader")

@export_group("Shape")
@export var radius: float = 40.0:
	set(v):
		radius = v
		_apply_visual_scale()

@export_group("Gravity")
@export var surface_gravity: float = 20.0
@export var influence_radius: float = 220.0

@export_group("Orbit")
## A moon fragment gets its pivot/radius assigned after it's already entered
## the tree (see OrbitalBody._spawn_moon_fragments), which used to leave it
## with no orbit ring at all - _add_orbit_ring() only ran once, from _ready(),
## back when both were still unset. These setters make sure the ring gets
## created (or moved/resized) whenever either value changes post-ready.
## Watches whatever it's currently set to for that body's own `shattered`
## signal (only meaningful when the pivot is itself an OrbitalBody, i.e. a
## moon orbiting a planet - not the top-level orbit_center Marker3D, which
## never shatters) - see _on_orbit_pivot_shattered()/go_rogue(). Reconnects
## automatically every time this changes, including the post-ready
## reassignment fragments and recaptured rogue bodies both do.
@export var orbit_pivot: Node3D:
	set(v):
		if orbit_pivot is OrbitalBody and orbit_pivot != v and orbit_pivot.shattered.is_connected(_on_orbit_pivot_shattered):
			orbit_pivot.shattered.disconnect(_on_orbit_pivot_shattered)
		orbit_pivot = v
		if orbit_pivot is OrbitalBody and not orbit_pivot.shattered.is_connected(_on_orbit_pivot_shattered):
			orbit_pivot.shattered.connect(_on_orbit_pivot_shattered)
		_ensure_orbit_ring()
@export var orbit_radius: float = 0.0:
	set(v):
		orbit_radius = v
		_ensure_orbit_ring()
## Semi-minor axis: if 0, orbit is circular. Set to a fraction of orbit_radius
## (e.g. 0.6) for an ellipse. Perturb_orbit can drift this over time.
@export var orbit_eccentricity: float = 0.0
@export var orbit_speed: float = 0.0
@export var orbit_axis: Vector3 = Vector3.UP
@export var orbit_start_angle: float = 0.0

@export_group("Self rotation")
@export var spin_axis: Vector3 = Vector3.UP
@export var spin_speed: float = 0.1

@export_group("Destructible")
@export var can_be_shattered: bool = true
@export var fragment_count_min: int = 2
@export var fragment_count_max: int = 4

@export_group("Rogue")
## Multiplier on GravityManager's normal pull while rogue - real multi-body
## gravity is what has to carry this body now that the analytic orbit formula
## has stopped running for it, so this is tuned close to 1 (a rogue body
## should fall roughly like anything else does), not the exaggerated pull
## Slug.gd uses for its own in-flight arcs.
@export var rogue_gravity_multiplier: float = 1.0
## Seconds of sustained proximity to a candidate host before its pull toward
## a matching stable orbit reaches full strength - see _update_rogue_capture().
@export var rogue_capture_time: float = 4.0

var is_shattered: bool = false
## True from the moment this body's own orbit_pivot is destroyed until it
## either gets recaptured into a new stable orbit or drifts past the arena
## boundary and shatters itself. See go_rogue()/_process_rogue().
var is_rogue: bool = false
var _rogue_velocity: Vector3 = Vector3.ZERO
var _rogue_capture_progress: float = 0.0
## How many inbound Planet Buster shells currently have this body locked
## (see PlanetBusterProjectile.launch/_exit_tree). Counted rather than a
## plain bool so a second overlapping shot can't have the first one's
## resolution turn the siren off while it's still inbound.
var _threat_count: int = 0
var _siren_timer: Timer = null
## Rigid motion of this body between the previous physics frame and the current
## one, expressed as a transform that maps a point's old world position to its
## new one. Planets here orbit at up to ~12 m/s - faster than a player can run -
## and spin on top of that, so anything standing on one has to be carried by
## this delta or the surface simply slides out from under it (Player owns that;
## see Player._update_planet_frame).
var motion_delta: Transform3D = Transform3D.IDENTITY
var _prev_global_transform: Transform3D = Transform3D.IDENTITY
var _motion_delta_time: float = 0.0
var _orbit_angle: float = 0.0
## Height of the tallest structure standing on this body, and a cooldown so a
## single grinding encounter between two planets registers once rather than
## every physics frame. See GravityManager._physics_process.
var structure_reach: float = 0.0
var collision_cooldown: float = 0.0
## Baked surface geometry, populated the first time apply_crater() runs.
## Collider rebuilds are coalesced: several craters landing within this window
## produce one triangle-mesh rebuild instead of one each.
const COLLIDER_REBUILD_INTERVAL: float = 0.6
## Surface tessellation. Coarse enough to read as facets, fine enough that a
## crater still has vertices to displace.
const SURFACE_SEGMENTS: int = 36
const SURFACE_RINGS: int = 18
var _atmosphere: MeshInstance3D = null
var _orbit_ring: MeshInstance3D = null
var _ring_drawn_radius: float = 0.0
var _ring_drawn_axis: Vector3 = Vector3.UP
var _collider_dirty: bool = false
var _collider_rebuild_delay: float = COLLIDER_REBUILD_INTERVAL
var _crater_arrays: Array = []
var _crater_vertices: PackedVector3Array = PackedVector3Array()
## Bodies with eccentricity use semi-major (orbit_radius) and semi-minor
## (_semi_minor) axes to trace an ellipse instead of a circle.
var _semi_minor: float = 0.0
var _orbit_template: PackedScene = null  # set by Arena to allow fragment spawning

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var collision: CollisionShape3D = $StaticBody3D/CollisionShape3D
@onready var static_body: StaticBody3D = $StaticBody3D

func _ready() -> void:
	mesh.mesh = mesh.mesh.duplicate()
	var mat: Material = mesh.get_surface_override_material(0)
	if mat:
		mat = mat.duplicate()
		mesh.set_surface_override_material(0, mat)
		_apply_bump_pattern(mat)
	collision.shape = collision.shape.duplicate()

	add_to_group("orbital_bodies")
	_orbit_angle = orbit_start_angle
	_semi_minor = orbit_radius * (1.0 - clamp(orbit_eccentricity, 0.0, 0.95))
	_apply_visual_scale()
	static_body.set_meta("orbital_body", self)
	GravityManager.register_body(self)
	if orbit_pivot:
		_update_orbit_position()
	# Riders read motion_delta during their own _physics_process, so every body
	# must have finished moving before any player runs. Tree order already puts
	# OrbitalBodies ahead of Players in Arena.tscn, but an explicit priority
	# means that stays true if the scene is ever reordered.
	process_physics_priority = -10
	_prev_global_transform = global_transform
	_add_atmosphere_shell()
	_ensure_orbit_ring()
	_rebuild_faceted_surface()

## Creates the orbit ring if this body now has a valid pivot+radius and
## doesn't already have one, or repositions the existing one otherwise. Called
## both from _ready() and from the orbit_pivot/orbit_radius setters, since a
## spawned moon fragment gets those assigned after it's already in the tree
## (see _spawn_moon_fragments) - a single _ready()-time call would have missed
## it and left the moon with no ring, ever.
func _ensure_orbit_ring() -> void:
	if not is_inside_tree():
		return
	if orbit_pivot == null or orbit_radius <= 0.01:
		return
	if _orbit_ring == null or not is_instance_valid(_orbit_ring):
		_add_orbit_ring()
	else:
		_refresh_orbit_ring()

## Faint ring tracing this body's orbital path, the way the concept art draws
## every world on a visible track. Parented to the PIVOT rather than to us, so a
## moon's ring travels with its parent planet instead of being pinned to the
## arena centre.
func _add_orbit_ring() -> void:
	if orbit_pivot == null or orbit_radius <= 0.01:
		return
	if _orbit_ring and is_instance_valid(_orbit_ring):
		_orbit_ring.queue_free()
	_orbit_ring = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.rings = 96
	ring.ring_segments = 4
	_orbit_ring.mesh = ring
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.55, 0.65, 1.0, 0.16)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.5, 0.68, 1.0)
	ring_mat.emission_energy_multiplier = 0.9
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_orbit_ring.material_override = ring_mat
	_orbit_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	orbit_pivot.add_child(_orbit_ring)
	_refresh_orbit_ring()

## TorusMesh lies in its own XZ plane with +Y as the axis, so aligning the ring
## to the orbit is just a matter of pointing its Y at orbit_axis. Only resizes
## the torus and records the target axis here - the actual transform is set
## every physics frame by _orient_orbit_ring(), since the ring's parent (the
## pivot) can itself be spinning.
func _refresh_orbit_ring() -> void:
	if _orbit_ring == null or not is_instance_valid(_orbit_ring):
		return
	var ring: TorusMesh = _orbit_ring.mesh
	var thickness: float = clampf(orbit_radius * 0.0025, 0.12, 0.6)
	ring.inner_radius = maxf(orbit_radius - thickness, 0.01)
	ring.outer_radius = orbit_radius + thickness
	_ring_drawn_radius = orbit_radius
	_ring_drawn_axis = orbit_axis.normalized()
	_orient_orbit_ring()

## Keeps the ring's WORLD orientation locked to the orbital plane every frame,
## independent of the pivot's own spin. The ring is parented to orbit_pivot so
## its POSITION follows the pivot for free (moons need their ring to travel
## with the parent planet as it circles the binary) - but plain parenting also
## inherits the pivot's ROTATION, and planets spin on their own axis. Without
## this correction a moon's ring would visibly tumble in lockstep with its
## parent's spin instead of staying fixed to the plane the moon actually
## orbits in, drifting out of alignment ("detaching") within a few seconds.
func _orient_orbit_ring() -> void:
	if _orbit_ring == null or not is_instance_valid(_orbit_ring) or orbit_pivot == null:
		return
	var world_basis: Basis = Basis(Quaternion(Vector3.UP, _ring_drawn_axis))
	_orbit_ring.transform = Transform3D(orbit_pivot.global_transform.basis.inverse() * world_basis, Vector3.ZERO)

## Baked once and shared by every planet's material (see Asteroid.gd for why
## sharing a generated resource across near-identical instances matters) -
## only the tiny tile is ever built, however many planets use it.
##
## The tile is NOT square. A true equilateral-triangle lattice (three line
## families 60 degrees apart) only repeats seamlessly over a rectangle of
## height = width * sqrt(3) - the standard fundamental domain for a
## triangular/hex tiling. The previous version used a square tile with a
## u+v diagonal standing in for the 60-degree family, which is only actually
## a 45-degree line in plain (u, v) pixel space - that made the "triangles"
## really right-angled isoceles ones (and squares), not equilateral. Building
## the tile at the correct aspect ratio and using real trigonometry for the
## three line directions fixes the shape instead of approximating it.
const BUMP_TILE_W: int = 128
const BUMP_TILE_H: int = 222  ## round(128 * sqrt(3)) = 221.7
## Triangles across the tile's own width. Must be EVEN - the 60/120 degree
## line families only wrap seamlessly at an even count (each shifts by a
## half-integer number of periods per whole tile width, so two tile-widths
## are needed to close the loop unless the count itself is even). Combined
## with BUMP_TILE_REPEAT this sets how big a triangle reads on a planet's
## surface - both were far too high before (6 * 26 = 156 periods around the
## sphere, fine enough to blur into noise); this is 4 * 4 = 16.
const BUMP_TILES_ACROSS: int = 4
const BUMP_TILE_REPEAT: float = 4.0
static var _bump_texture: ImageTexture = null

## Applies the shared triangular bump pattern to a (per-instance, already
## duplicated) ShaderMaterial (scenes/world/planet_surface.gdshader) - the
## low-poly facets stay the silhouette, this engraves a larger triangular
## plating texture with embossed edges (as a normal map) AND a hue-rotated
## tint right at those same edges (see the shader) on top of them, without
## touching geometry. A plain StandardMaterial3D can't do the hue shift -
## multiplying by a baked tint can't rotate hue relative to a base colour
## that's different on every planet, only real HSV math can, hence the
## custom shader instead of normal_enabled/normal_texture properties.
func _apply_bump_pattern(mat: Material) -> void:
	if not (mat is ShaderMaterial):
		return
	var shader_mat: ShaderMaterial = mat as ShaderMaterial
	shader_mat.set_shader_parameter("normal_texture", _get_bump_texture())
	# V covers half the physical arc-length U does on a sphere (equator vs.
	# pole-to-pole), so repeating it at the same rate as U would stretch the
	# pattern taller than it reads around the equator - halved to compensate.
	shader_mat.set_shader_parameter("uv_scale", Vector2(BUMP_TILE_REPEAT, BUMP_TILE_REPEAT * 0.5))

static func _get_bump_texture() -> ImageTexture:
	if _bump_texture == null:
		_bump_texture = _build_bump_texture()
	return _bump_texture

## Renders a tileable EQUILATERAL triangular lattice, edges embossed and
## faces flat. Per pixel, this finds the distance to the nearest grid line
## among three families whose NORMALS point along 0/60/120 degrees (real
## trigonometry, not a (u, v, u+v) stand-in - see BUMP_TILE_W/H) and raises a
## thin ridge only right at that distance, leaving each triangular cell's
## interior flat - an embossed border rather than a smooth dome.
##
## RGB packs a tangent-space normal, differentiated from the height field via
## central-difference gradients (the same "height field to normal" trick any
## terrain normal map uses). ALPHA packs that same height field directly, 0-1 -
## a plain normal map would leave this channel unused, and the shader reads it
## as the edge mask driving the hue-rotate effect, so the two effects always
## line up exactly without needing a second texture or a second UV sample.
static func _build_bump_texture() -> ImageTexture:
	var w: int = BUMP_TILE_W
	var h: int = BUMP_TILE_H
	var period: float = float(w) / float(BUMP_TILES_ACROSS)
	var strength: float = 3.0
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var h0: float = _bump_height(float(x), float(y), period)
			var dx: float = (_bump_height(float(x) + 1.0, float(y), period) - h0) * strength
			var dy: float = (_bump_height(float(x), float(y) + 1.0, period) - h0) * strength
			var n: Vector3 = Vector3(-dx, -dy, 1.0).normalized()
			img.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5, h0))
	return ImageTexture.create_from_image(img)

## Height is 1 right on a triangle edge and falls to 0 within EDGE_WIDTH
## periods of it, flat (0) the rest of the way to the cell centre - an
## embossed border rather than a smooth dome.
const BUMP_EDGE_WIDTH: float = 0.1
## sqrt(3)/2 - the y-component of the 60/120 degree line normals.
const BUMP_SIN60: float = 0.8660254

static func _bump_height(x: float, y: float, period: float) -> float:
	var s0: float = x / period
	var s1: float = (x * 0.5 + y * BUMP_SIN60) / period
	var s2: float = (-x * 0.5 + y * BUMP_SIN60) / period
	var d: float = minf(_line_dist(s0), minf(_line_dist(s1), _line_dist(s2)))
	return 1.0 - smoothstep(0.0, BUMP_EDGE_WIDTH, d)

## Distance from `x` to the nearest integer (i.e. the nearest grid line in
## this family), as a fraction of one period: 0 exactly on the line, 0.5 at
## the midpoint between two lines.
static func _line_dist(x: float) -> float:
	return absf(fposmod(x + 0.5, 1.0) - 0.5)

## Thin emissive shell just above the surface, rendered inside-out so only the
## limb shows through - the atmospheric rim glow every planet has in the concept
## art. Front faces are culled, so what you see is the shell's FAR side around
## the planet's edge; that band of backfaces is the glow.
func _add_atmosphere_shell() -> void:
	_atmosphere = MeshInstance3D.new()
	_atmosphere.mesh = SphereMesh.new()
	var tint: Color = Color(0.45, 0.62, 1.0)
	var surface_mat := mesh.get_surface_override_material(0)
	if surface_mat is ShaderMaterial:
		var base_color: Variant = (surface_mat as ShaderMaterial).get_shader_parameter("albedo_color")
		if base_color is Color:
			tint = (base_color as Color).lerp(Color(0.5, 0.7, 1.0), 0.55)
	var shell_mat := StandardMaterial3D.new()
	shell_mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.16)
	shell_mat.emission_enabled = true
	shell_mat.emission = tint
	shell_mat.emission_energy_multiplier = 1.4
	shell_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shell_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shell_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	shell_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	_atmosphere.material_override = shell_mat
	_atmosphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_atmosphere)
	_resize_atmosphere()

## Hides the rim glow while the person actually looking at this screen is
## standing on this body. From orbit the shell reads as atmosphere; from the
## surface, with the camera sitting inside/just past it, it's just a bright
## haze in the way. "On the body" reuses Player's own planet-frame check
## (get_frame_body()) rather than a second distance threshold, so the glow
## disappears exactly when the local player's movement frame switches to
## this planet.
##
## Scoped to the LOCAL viewer specifically, not "any player" - this used to
## check every node in the "players" group, so with bots scattered across a
## dozen planets a given world's glow flickered on and off as whichever bots
## happened to be near it wandered in and out of range, with no relation to
## where the person watching actually was. Every OrbitalBody exists
## independently in each client's own scene tree, so there's nothing wrong
## with each client deciding this purely from its own local player - it's a
## rendering nicety, not shared gameplay state.
func _update_atmosphere_visibility() -> void:
	if _atmosphere == null:
		return
	var viewer: Player = _find_local_viewer()
	_atmosphere.visible = not (viewer != null and viewer.get_frame_body() == self)

## The local viewer is the same for every body in a given physics frame, so
## the group scan (GravityManager.find_local_viewer(), the shared
## implementation - ArenaBoundary uses the same one) runs once per frame
## here, cached statically, instead of once per body - with a dozen-plus
## planets all calling this, repeating the scan per body would be the same
## O(bodies x players) cost the atmosphere check used to have, just moved
## rather than fixed.
static var _local_viewer: Player = null
static var _local_viewer_frame: int = -1

static func _find_local_viewer() -> Player:
	var frame: int = Engine.get_physics_frames()
	if frame == _local_viewer_frame:
		return _local_viewer
	_local_viewer_frame = frame
	_local_viewer = GravityManager.find_local_viewer()
	return _local_viewer

func _resize_atmosphere() -> void:
	var shell_mesh: SphereMesh = _atmosphere.mesh
	shell_mesh.radius = radius * 1.05
	shell_mesh.height = radius * 2.1
	shell_mesh.radial_segments = 24
	shell_mesh.rings = 12

func _apply_visual_scale() -> void:
	if not is_inside_tree():
		return
	if collision and collision.shape is SphereShape3D:
		collision.shape.radius = radius
	# Craters edit the surface in place, so regenerating it from a fresh sphere
	# would wipe them. Only rebuild while the surface is still pristine - which
	# is exactly the case that matters, since the only late radius changes come
	# from freshly-spawned shatter fragments.
	if _crater_vertices.is_empty():
		_rebuild_faceted_surface()
	if _atmosphere:
		_resize_atmosphere()

## Rebuilds the surface as flat-shaded facets - the chunky low-poly look the
## concept art uses. Deindexing before generating normals is what does it: with
## no shared vertices every triangle gets its own normal instead of a smoothed
## average. It also leaves an editable ArrayMesh, which is what apply_crater()
## needs anyway.
##
## Tessellation is a balance: coarse enough to read as facets, fine enough that
## a crater has vertices to actually move (at 36x18 the spacing on the largest
## planet is ~7.7m, just under the biggest crater radius).
func _rebuild_faceted_surface() -> void:
	if mesh == null:
		return
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = SURFACE_SEGMENTS
	sphere.rings = SURFACE_RINGS
	var st := SurfaceTool.new()
	st.create_from(sphere, 0)
	st.deindex()
	st.generate_normals()
	mesh.mesh = st.commit()

## Dents the surface where something slammed into it - visibly AND physically.
##
## The mesh starts as a faceted ArrayMesh baked in _ready(), so there are real
## vertices to push. The collider is rebuilt from those same vertices as a
## ConcavePolygonShape3D, which is what lets players actually walk down into a
## crater. That rebuild is the expensive half, so it is deferred and coalesced
## (see _physics_process): a busy respawn wave cratering the same planet several
## times in one second pays for one rebuild, not five.
func apply_crater(world_point: Vector3, crater_radius: float, depth: float) -> void:
	if is_shattered or mesh == null or crater_radius <= 0.01:
		return
	_ensure_deformable_mesh()
	if _crater_vertices.is_empty():
		return

	# Project the impact onto the surface, in the planet's own local space so
	# craters ride along with its orbit and spin.
	var local_hit: Vector3 = (to_local(world_point)).normalized() * radius
	var changed: bool = false
	for i in range(_crater_vertices.size()):
		var v: Vector3 = _crater_vertices[i]
		var dist: float = v.distance_to(local_hit)
		if dist > crater_radius:
			continue
		# Cosine bowl with a raised lip near the rim, so it reads as an impact
		# crater rather than a smooth dimple.
		var t: float = dist / crater_radius
		var bowl: float = cos(t * PI * 0.5)
		var rim: float = -0.28 * sin(t * PI) * t
		var displacement: float = depth * (bowl + rim)
		if absf(displacement) < 0.0005:
			continue
		_crater_vertices[i] = v - v.normalized() * displacement
		changed = true
	if not changed:
		return

	_crater_arrays[Mesh.ARRAY_VERTEX] = _crater_vertices
	_rebuild_cratered_mesh()
	_collider_dirty = true

func _ensure_deformable_mesh() -> void:
	if not _crater_vertices.is_empty():
		return
	var source: Mesh = mesh.mesh
	if source == null or source.get_surface_count() == 0:
		return
	_crater_arrays = source.surface_get_arrays(0)
	_crater_vertices = _crater_arrays[Mesh.ARRAY_VERTEX]

## Normals have to be regenerated from the moved vertices or the crater is
## invisible - the shading, not the silhouette, is what makes it read.
func _rebuild_cratered_mesh() -> void:
	var rebuilt := ArrayMesh.new()
	rebuilt.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _crater_arrays)
	var st := SurfaceTool.new()
	st.create_from(rebuilt, 0)
	st.generate_normals()
	mesh.mesh = st.commit()

## Swaps the perfect SphereShape3D for a triangle mesh built from the cratered
## surface, so craters are walkable terrain rather than paint. Only ever called
## from the coalescing timer in _physics_process - rebuilding a couple of
## thousand triangles is far too expensive to do per impact.
func _rebuild_collider() -> void:
	if mesh == null or mesh.mesh == null:
		return
	if has_meta("no_crater_collider"):
		return  # perf probe: keep the analytic sphere so its cost can be compared
	var faces: PackedVector3Array = mesh.mesh.get_faces()
	if faces.is_empty():
		return
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	collision.shape = shape

func _physics_process(delta: float) -> void:
	if is_shattered:
		motion_delta = Transform3D.IDENTITY
		_motion_delta_time = 0.0
		return
	if is_rogue:
		_process_rogue(delta)
	elif orbit_pivot and orbit_speed != 0.0:
		_orbit_angle += orbit_speed * delta
		_update_orbit_position()
		_check_boundary()
	if spin_speed != 0.0:
		rotate(spin_axis.normalized(), spin_speed * delta)
	if collision_cooldown > 0.0:
		collision_cooldown -= delta
	# Orbits drift on every spawn landing and jump/tilt on a structural
	# collision; refresh the drawn ring's SIZE once either the radius or the
	# plane has moved enough to actually be visible. Axis alone (a tilt with
	# radius unchanged) used to leave a stale ring, since only radius was
	# watched.
	if _orbit_ring and (absf(orbit_radius - _ring_drawn_radius) > maxf(orbit_radius * 0.01, 0.25)
			or orbit_axis.normalized().dot(_ring_drawn_axis) < 0.9999):
		_refresh_orbit_ring()
	# Independent of the above: the ring's ORIENTATION has to be corrected
	# every single frame, not just on a size/axis change, because the pivot
	# it's parented to may be spinning on its own axis right now even when
	# nothing about the orbit itself has changed.
	_orient_orbit_ring()
	if _collider_dirty:
		_collider_rebuild_delay -= delta
		if _collider_rebuild_delay <= 0.0:
			_collider_dirty = false
			_collider_rebuild_delay = COLLIDER_REBUILD_INTERVAL
			_rebuild_collider()
	_update_motion_delta(delta)
	_update_atmosphere_visibility()

## Records a building's height so GravityManager knows how far this body's
## structures stick out when checking whether two planets are grinding together.
func note_structure(height: float) -> void:
	structure_reach = maxf(structure_reach, height)

func is_under_threat() -> bool:
	return _threat_count > 0

## Called once per inbound Planet Buster shell for the whole time it's
## guided at this body (see PlanetBusterProjectile.launch). Drives the
## siren-flash surface shader, a repeating siren wail, and - via Bot._think -
## tells any bot standing here to flee.
func add_threat() -> void:
	_threat_count += 1
	if _threat_count == 1:
		_set_siren_shader(true)
		_start_siren_audio()

## Mirror of add_threat(), called exactly once per shell regardless of how it
## resolved (hit, miss, or expired - see PlanetBusterProjectile._exit_tree).
func remove_threat() -> void:
	_threat_count = maxi(_threat_count - 1, 0)
	if _threat_count == 0:
		_set_siren_shader(false)
		_stop_siren_audio()

func _set_siren_shader(active: bool) -> void:
	var mat: Material = mesh.get_surface_override_material(0)
	if mat is ShaderMaterial:
		(mat as ShaderMaterial).set_shader_parameter("siren_strength", 1.0 if active else 0.0)

## Re-triggers a one-shot "siren_wail" (see Sfx._synthesize) on a fixed
## cadence rather than looping a stream - matches every other sound in this
## project, which is one-shot only (see Sfx.gd's own docstring), so this
## needed no new playback machinery, just a Timer already parented under an
## OrbitalBody that already owns other Sfx.play_3d calls (shatter).
func _start_siren_audio() -> void:
	Sfx.play_3d("siren_wail", global_position, 1.0, -2.0, 0.02)
	if _siren_timer == null:
		_siren_timer = Timer.new()
		_siren_timer.wait_time = 1.55
		_siren_timer.timeout.connect(_on_siren_timer_timeout)
		add_child(_siren_timer)
	_siren_timer.start()

func _on_siren_timer_timeout() -> void:
	if is_under_threat():
		Sfx.play_3d("siren_wail", global_position, 1.0, -2.0, 0.02)

func _stop_siren_audio() -> void:
	if _siren_timer:
		_siren_timer.stop()

func _update_motion_delta(delta: float) -> void:
	motion_delta = global_transform * _prev_global_transform.affine_inverse()
	motion_delta.basis = motion_delta.basis.orthonormalized()
	_prev_global_transform = global_transform
	_motion_delta_time = delta

## World-space velocity of the point on (or above) this body that currently sits
## at `world_point`, combining orbital travel and self-rotation. Used to convert
## player velocity in and out of this body's reference frame.
func get_point_velocity(world_point: Vector3) -> Vector3:
	if _motion_delta_time <= 0.0:
		return Vector3.ZERO
	return ((motion_delta * world_point) - world_point) / _motion_delta_time

func _update_orbit_position() -> void:
	var axis := orbit_axis.normalized()
	var reference := Vector3.RIGHT if abs(axis.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var tangent_a := axis.cross(reference).normalized()
	var tangent_b := axis.cross(tangent_a).normalized()
	## Ellipse: a*cos(θ) along tangent_a, b*sin(θ) along tangent_b
	var a: float = orbit_radius
	var b: float = _semi_minor if _semi_minor > 0.0 else orbit_radius
	var offset := (tangent_a * cos(_orbit_angle) * a + tangent_b * sin(_orbit_angle) * b)
	global_position = orbit_pivot.global_position + offset

## The moon/fragment we were orbiting just shattered - go rogue instead of
## sitting on a now-invalid pivot (_update_orbit_position would otherwise
## start reading a freed/garbage node next frame).
func _on_orbit_pivot_shattered(_pivot: OrbitalBody) -> void:
	if is_shattered or is_rogue:
		return
	go_rogue()

## Leaves the analytic orbit formula behind and starts flying free: keeps
## whatever velocity the orbit was actually carrying at this instant (so the
## body continues in a straight line from where it was, tangent to the old
## orbit, rather than teleporting to a stop), then falls under everyone
## else's real gravity from here on (_process_rogue) until either recaptured
## into a new stable orbit or shattered by drifting past the arena boundary.
func go_rogue() -> void:
	if is_shattered:
		return
	is_rogue = true
	_rogue_capture_progress = 0.0
	_rogue_velocity = get_point_velocity(global_position)
	if _rogue_velocity.length_squared() < 0.0001:
		# No motion_delta history yet (e.g. this body has never had a physics
		# frame tick) - fall back to the orbit formula's own closed-form
		# tangent instead of leaving it dead in space.
		_rogue_velocity = _orbit_tangent_velocity()
	orbit_pivot = null

## d/dt of _update_orbit_position()'s own ellipse parametrization - the exact
## tangential velocity the analytic orbit was producing the instant before
## go_rogue() stops calling it.
func _orbit_tangent_velocity() -> Vector3:
	if orbit_pivot == null:
		return Vector3.ZERO
	var axis := orbit_axis.normalized()
	var reference := Vector3.RIGHT if abs(axis.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var tangent_a := axis.cross(reference).normalized()
	var tangent_b := axis.cross(tangent_a).normalized()
	var a: float = orbit_radius
	var b: float = _semi_minor if _semi_minor > 0.0 else orbit_radius
	return (-tangent_a * sin(_orbit_angle) * a + tangent_b * cos(_orbit_angle) * b) * orbit_speed

## Straight line plus real multi-body gravity - the actual physics this whole
## project otherwise fakes with the analytic orbit formula - until either
## recaptured (_update_rogue_capture) or ejected past the boundary.
func _process_rogue(delta: float) -> void:
	_rogue_velocity += GravityManager.get_gravity_at(global_position) * rogue_gravity_multiplier * delta
	global_position += _rogue_velocity * delta
	_check_boundary()
	if not is_shattered:
		_update_rogue_capture(delta)

## Nearest body a rogue is close enough to plausibly settle around - unlike
## _pick_fragment_host (used for a fresh shatter, which can reach clear
## across the arena for a home), this only ever considers bodies the rogue
## is already inside the influence radius of, and skips anything much
## smaller than itself (a rogue shouldn't end up "orbiting" a pebble).
func _find_capture_host() -> OrbitalBody:
	var best: OrbitalBody = null
	var best_dist: float = INF
	for body in GravityManager.get_bodies():
		if body == self or not is_instance_valid(body) or body.is_shattered:
			continue
		if body.radius < radius * 0.6:
			continue
		var dist: float = body.global_position.distance_to(global_position)
		if dist > body.influence_radius:
			continue
		if dist < best_dist:
			best_dist = dist
			best = body
	return best

## "Excessively trends towards being pulled into a stable orbit around a new
## planet" per design: once a candidate host is in range, ramps up (over
## rogue_capture_time of sustained proximity) how strongly velocity is pulled
## toward the tangential speed a circular orbit at the current distance would
## have, rather than snapping onto one instantly. Reaching full strength
## actually commits to the new orbit via _capture_into_orbit().
func _update_rogue_capture(delta: float) -> void:
	var host: OrbitalBody = _find_capture_host()
	if host == null:
		_rogue_capture_progress = maxf(_rogue_capture_progress - delta / rogue_capture_time, 0.0)
		return
	_rogue_capture_progress = clampf(_rogue_capture_progress + delta / rogue_capture_time, 0.0, 1.0)

	var to_host: Vector3 = host.global_position - global_position
	var dist: float = maxf(to_host.length(), 0.01)
	var axis: Vector3 = orbit_axis.normalized()
	var radial_dir: Vector3 = to_host / dist
	var tangent_dir: Vector3 = axis.cross(radial_dir)
	if tangent_dir.length_squared() < 0.0001:
		tangent_dir = Vector3.RIGHT.cross(radial_dir)
	tangent_dir = tangent_dir.normalized() if tangent_dir.length_squared() > 0.0001 else Vector3.RIGHT
	# Circular-orbit speed at this distance for host's own surface_gravity,
	# same v = sqrt(g_surface * r_surface^2 / r) shape Player.gd's jump uses
	# for "how hard does this body actually pull", scaled down since these
	# orbits are meant to be slow drifts (see ORBIT_DATA's own orbit_speed
	# values), not a literal escape-velocity orbit.
	var ideal_speed: float = sqrt(maxf(host.surface_gravity, 0.1) * host.radius * host.radius / dist) * 0.12
	var ideal_velocity: Vector3 = tangent_dir * ideal_speed + host.get_point_velocity(global_position)

	# Pull strength itself ramps with _rogue_capture_progress - "excessively"
	# trends toward it, not an immediate snap.
	var pull: float = clampf(_rogue_capture_progress * delta * 2.0, 0.0, 1.0)
	_rogue_velocity = _rogue_velocity.lerp(ideal_velocity, pull)

	if _rogue_capture_progress >= 1.0:
		_capture_into_orbit(host, to_host)

## Commits a fully-captured rogue back onto the analytic orbit formula around
## `host`, phased so the body doesn't jump to a different point on the new
## circle the instant orbit_pivot starts driving its position again.
func _capture_into_orbit(host: OrbitalBody, to_host: Vector3) -> void:
	is_rogue = false
	orbit_radius = clampf(to_host.length(), host.radius * 1.8, host.influence_radius * 1.4)
	orbit_speed = (1.0 if orbit_speed >= 0.0 else -1.0) * randf_range(0.08, 0.2)
	orbit_eccentricity = 0.0
	_semi_minor = orbit_radius
	var axis := orbit_axis.normalized()
	var reference := Vector3.RIGHT if abs(axis.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var tangent_a := axis.cross(reference).normalized()
	var tangent_b := axis.cross(tangent_a).normalized()
	_orbit_angle = atan2(-to_host.dot(tangent_b), -to_host.dot(tangent_a))
	orbit_pivot = host

func _check_boundary() -> void:
	if global_position.length() <= GravityManager.ARENA_BOUNDARY_RADIUS:
		return
	if not can_be_shattered:
		return
	_shatter_to_fragments()

func perturb_orbit(impact_strength: float = 1.0) -> void:
	if is_shattered or orbit_pivot == null:
		return
	var strength_mult: float = clamp(impact_strength, 0.0, 3.0)
	var pct: float = randf_range(0.0001, 0.001) * strength_mult
	var sign_r: float = 1.0 if randf() < 0.5 else -1.0
	var sign_s: float = 1.0 if randf() < 0.5 else -1.0
	orbit_radius = max(orbit_radius * (1.0 + sign_r * pct), radius * 1.5)
	orbit_speed *= (1.0 + sign_s * pct)
	# Drift eccentricity slightly over time for emergent ellipses
	orbit_eccentricity = clamp(orbit_eccentricity + randf_range(-0.002, 0.003) * strength_mult, 0.0, 0.7)
	_semi_minor = orbit_radius * (1.0 - orbit_eccentricity)
	if randf() < 0.15:
		orbit_axis = (orbit_axis + Vector3(
			randf_range(-0.01, 0.01), randf_range(-0.01, 0.01), randf_range(-0.01, 0.01)
		)).normalized()

## Two planets have drifted close enough that the buildings on their surfaces
## - or, if they're deep enough into each other, their actual rock - are
## colliding. Unlike perturb_orbit()'s sub-1% drift, this is a real impact:
## the outer body is flung further out and slowed, the inner one is dragged in
## and sped up, scaled by their relative mass so a moon bounces off a planet
## rather than the other way round. Also craters both at the contact point.
##
## GravityManager triggers this once BUILDINGS come into reach (radius +
## structure_reach on both sides), which can be well before the bare spheres
## themselves touch - overlap is usually 0 on the opening hit. The mass-only
## kick used to leave that as the entire response even once the spheres WERE
## genuinely overlapping, and a 3-second cooldown meant a slow, sustained
## approach only got one small nudge and one small crater every three
## seconds while the rock kept sinking into itself in between - which is
## what read as "squishing together and dragging" rather than a resolved
## impact. Two changes: the kick itself now scales up sharply with actual
## rock overlap (structure-only contact still gets the old gentle nudge), and
## the cooldown is much shorter, so a sustained approach gets re-corrected
## every few tenths of a second instead of every three.
func structural_collision(other: OrbitalBody) -> void:
	if is_shattered or other.is_shattered or orbit_pivot == null:
		return
	var separation: float = global_position.distance_to(other.global_position)
	var overlap: float = maxf((radius + other.radius) - separation, 0.0)
	# Fraction of this body's OWN radius currently buried in the other body -
	# 0 when only structures have touched, up to 1 for a serious embedding.
	var overlap_ratio: float = clampf(overlap / maxf(radius, 1.0), 0.0, 1.0)

	# Mass goes as radius cubed, so a big world barely notices a small one.
	var own_mass: float = pow(radius, 3.0)
	var other_mass: float = pow(other.radius, 3.0)
	var share: float = other_mass / maxf(own_mass + other_mass, 0.001)

	var outward: float = 1.0 if orbit_radius >= other.orbit_radius else -1.0
	var kick: float = clampf(share, 0.0, 0.9) * randf_range(0.04, 0.09) * (1.0 + overlap_ratio * 5.0)
	orbit_radius = maxf(orbit_radius * (1.0 + outward * kick), radius * 1.5)
	# Pushed outward means slowing down, dragged inward means speeding up.
	orbit_speed *= (1.0 - outward * kick * 0.5)
	orbit_eccentricity = clampf(orbit_eccentricity + share * randf_range(0.01, 0.05), 0.0, 0.7)
	_semi_minor = orbit_radius * (1.0 - orbit_eccentricity)
	# Tilt the orbital plane a little - a glancing blow shouldn't leave both
	# bodies in exactly the same plane they started in.
	orbit_axis = (orbit_axis + Vector3(
		randf_range(-0.05, 0.05), randf_range(-0.05, 0.05), randf_range(-0.05, 0.05)
	) * share).normalized()

	var contact: Vector3 = global_position + (other.global_position - global_position).normalized() * radius
	# Scaling the dent (and its radius) with how far the spheres actually
	# overlap makes each body carve away enough of its own facing hemisphere
	# that, combined with the other body doing the same on its own call, the
	# two surfaces clear each other - and with the cooldown now short, this
	# reapplies every few tenths of a second for as long as contact holds
	# instead of leaving a sustained graze to just keep sinking in.
	var dent_depth: float = clampf(overlap * 0.6 + radius * 0.04, 0.8, radius * 0.6)
	var dent_radius: float = clampf(radius * 0.3 + overlap * 0.8, 2.0, radius * 0.9)
	apply_crater(contact, dent_radius, dent_depth)
	_demolish_structures_near(contact, other)
	# Short enough that sustained contact keeps getting corrected (was 3.0,
	# which let two bodies grind for seconds between corrections); still long
	# enough that one impact doesn't fire twice in the same instant.
	collision_cooldown = 0.5

## Shears off the buildings actually caught in the encounter - the ones on the
## hemisphere facing the other planet, within reach of its structures. Buildings
## on the far side are untouched.
func _demolish_structures_near(contact: Vector3, other: OrbitalBody) -> void:
	var reach: float = structure_reach + other.structure_reach + other.radius * 0.5
	var tallest_left: float = 0.0
	for child in get_children():
		if not (child is Building):
			continue
		var building: Building = child
		if building.is_demolished():
			continue
		if building.global_position.distance_to(contact) <= reach:
			building.demolish()
		else:
			tallest_left = maxf(tallest_left, building.structure_height())
	# Recompute how far this body's structures now stick out, so a flattened
	# planet stops registering contacts it can no longer physically make.
	structure_reach = tallest_left

## `instigator` credits whoever caused this - the Planet Buster's shooter, so
## kills tied to the planet coming apart go on their scoreboard instead of
## vanishing as an environmental kill. Null for causes with no shooter (e.g.
## an orbit drifting past the arena boundary).
func shatter(blast_radius: float, blast_damage: float, instigator: Node = null, weapon_name: String = "") -> void:
	if is_shattered:
		return
	is_shattered = true
	# The shell that caused this is about to remove_threat() itself on its own
	# _exit_tree(), but the siren/warning has no reason to survive the body it
	# was warning about even a frame longer than that.
	_threat_count = 0
	_stop_siren_audio()
	# Scaled by size: a moon cracks, a 44m world detonates. volume_db trimmed
	# from the original +10 - a boost that hot on top of an already
	# near-full-scale synthesised waveform clipped hard at output; +3 is still
	# the loudest thing in the game without distorting into noise.
	Sfx.play_3d("planet_shatter", global_position, clampf(30.0 / maxf(radius, 1.0), 0.45, 1.6), 3.0, 0.05)
	shattered.emit(self)
	static_body.set_collision_layer_value(1, false)
	static_body.set_collision_mask_value(1, false)
	mesh.visible = false
	_spawn_debris()
	# Counted locally rather than inferred from MatchState.player_fragged
	# afterward - a victim whose authority is this peer dies synchronously
	# inside apply_damage() (Player._die() sets is_dead before returning), so
	# a before/after check here catches it directly. A victim owned by
	# another peer is only ever told over RPC (see the network_apply_damage
	# branch below) and its death isn't observable from here - same
	# per-peer visibility limit MatchState's own frag tracking already has.
	var kill_count: int = 0
	for node in get_tree().get_nodes_in_group("damageable"):
		if not is_instance_valid(node) or node == instigator:
			continue
		var dist: float = node.global_position.distance_to(global_position)
		if dist <= blast_radius:
			var falloff: float = 1.0 - (dist / blast_radius)
			if node.has_method("apply_damage"):
				var dmg: float = blast_damage * falloff
				if node.has_method("network_apply_damage") and not node.is_multiplayer_authority():
					node.rpc_id(node.get_multiplayer_authority(), "network_apply_damage", dmg, instigator.get_path() if instigator else NodePath(), global_position, weapon_name)
				else:
					var was_dead: bool = "is_dead" in node and node.is_dead
					node.apply_damage(dmg, instigator, global_position, weapon_name)
					if "is_dead" in node and node.is_dead and not was_dead:
						kill_count += 1
	if kill_count > 0 and weapon_name == "Planet Buster" and instigator and "player_id" in instigator:
		BountyManager.report_planet_kill(instigator.player_id, kill_count)
	_spawn_moon_fragments()
	await get_tree().create_timer(4.0).timeout
	GravityManager.unregister_body(self)
	queue_free()

## Spawns 2-5 smaller orbiting bodies that become moons of nearby planets.
## Called on Planet Buster destruction AND boundary ejection.
func _spawn_moon_fragments() -> void:
	if _orbit_template == null:
		return
	var count: int = randi_range(fragment_count_min, fragment_count_max)
	var bodies := GravityManager.get_bodies()
	# Pick the nearest non-shattered body to adopt each fragment as a moon
	for i in range(count):
		var frag: OrbitalBody = _orbit_template.instantiate()
		get_tree().current_scene.get_node_or_null("Arena/OrbitalBodies").add_child(frag) if get_tree().current_scene.has_node("Arena/OrbitalBodies") else get_tree().current_scene.add_child(frag)
		# Fragment radius = 20-40% of the parent
		frag.radius = randf_range(radius * 0.2, radius * 0.4)
		frag.surface_gravity = surface_gravity * (frag.radius / radius)
		frag.influence_radius = frag.radius * 3.5
		frag.can_be_shattered = true
		frag._orbit_template = _orbit_template
		# Random color variation of the parent
		var base_color: Color = Color(randf_range(0.2, 0.9), randf_range(0.2, 0.9), randf_range(0.2, 0.9))
		frag.radius = frag.radius  # trigger setter
		var frag_mesh: MeshInstance3D = frag.get_node_or_null("MeshInstance3D")
		if frag_mesh:
			var frag_mat := ShaderMaterial.new()
			frag_mat.shader = PLANET_SURFACE_SHADER
			frag_mat.set_shader_parameter("albedo_color", base_color)
			frag_mesh.set_surface_override_material(0, frag_mat)
			# This replaces the material _ready() already bump-mapped (before
			# radius/color were known), so the fragment needs the pattern
			# applied again on its new one or it'd be the one bare planet.
			# Every OTHER shader parameter (roughness, metallic, hue shift,
			# normal scale) is left unset here, which is fine - an unset
			# ShaderMaterial parameter just falls back to the uniform's own
			# default in planet_surface.gdshader, the same values the .tscn
			# material spells out explicitly.
			frag._apply_bump_pattern(frag_mat)
		# Pick a target parent body to orbit
		var host: OrbitalBody = _pick_fragment_host(bodies, frag.radius)
		if host == null:
			host = bodies[0] if not bodies.is_empty() else null
		if host:
			frag.orbit_pivot = host
			frag.orbit_radius = host.radius * randf_range(1.8, 3.5)
			frag.orbit_speed = randf_range(0.1, 0.3) * (1.0 if randf() < 0.5 else -1.0)
			frag.orbit_axis = Vector3(randf_range(-0.3, 0.3), 1.0, randf_range(-0.3, 0.3)).normalized()
			frag.orbit_start_angle = randf_range(0.0, TAU)
		frag.spin_speed = randf_range(0.03, 0.12) * (1.0 if randf() < 0.5 else -1.0)
		frag.global_position = global_position + Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20))
		fragment_spawned.emit(frag)

func _shatter_to_fragments() -> void:
	## Called when orbit drifts past arena boundary
	shatter(radius * 1.5, 50.0)

func _pick_fragment_host(bodies: Array[OrbitalBody], frag_radius: float) -> OrbitalBody:
	var best: OrbitalBody = null
	var best_score: float = INF
	for body in bodies:
		if body == self or body.is_shattered or not is_instance_valid(body):
			continue
		if body.radius < frag_radius * 2.0:
			continue
		var dist: float = body.global_position.distance_to(global_position)
		if dist < best_score:
			best_score = dist
			best = body
	return best

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
