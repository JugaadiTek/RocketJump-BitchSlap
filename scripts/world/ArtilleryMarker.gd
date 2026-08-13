class_name ArtilleryMarker
extends Node3D
## One of the 3 painted spots from Gunship._network_request_fire_artillery -
## a real scene node (replicated the same way jump pads/health packs are:
## parented under the target OrbitalBody so it travels with its orbit and
## spin), visible to everyone, not just the driver who painted it. Pulses to
## read as "something is about to land here" and frees itself once the
## matching ArtilleryShell has already detonated (see Gunship._launch_burst,
## which reads this node's path right before the shell consumes it).

## Fallback only - ArtilleryShell frees its own marker directly the instant
## it detonates (see ArtilleryShell._on_hit), which is almost always what
## actually removes this node. This is just the backstop for the case a
## shell never resolves against it at all (expired mid-flight some other way).
const MAX_LIFETIME: float = 8.0

@onready var _pip: MeshInstance3D = $Pip
var _t: float = 0.0

func _ready() -> void:
	var timer: SceneTreeTimer = get_tree().create_timer(MAX_LIFETIME)
	timer.timeout.connect(func(): if is_instance_valid(self): queue_free())

func _process(delta: float) -> void:
	_t += delta
	if _pip:
		var pulse: float = 0.6 + 0.4 * sin(_t * 8.0)
		_pip.scale = Vector3.ONE * (0.85 + 0.25 * pulse)
