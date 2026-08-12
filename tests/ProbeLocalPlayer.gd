extends "res://tests/ProbePlayer.gd"
## ProbePlayer variant that reports as the local human view
## (`is_first_person_view()` == true). Several features are deliberately
## gated to the actual local viewer specifically (the atmosphere glow, the
## arena boundary shell, and now the railgun scope's enemy-highlight) so a
## bot's own AI-driven scope use never triggers them - plain ProbePlayer
## always reports `_is_local_view() == false` (matching Bot.gd), which makes
## it impossible to exercise that gated path at all. Use this one whenever a
## probe specifically needs to be "the" local viewer; use plain ProbePlayer
## for everyone else in the scene, same as a real match has exactly one.

func _is_local_view() -> bool: return true
