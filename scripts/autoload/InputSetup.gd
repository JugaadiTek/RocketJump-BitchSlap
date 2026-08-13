extends Node
## InputSetup (autoload)
##
## Defines this project's custom input actions in code instead of relying
## solely on the hand-authored [input] section in project.godot. Those
## Object(InputEventKey, ...) / Object(InputEventMouseButton, ...) resource
## literals are sensitive to the exact property set a given Godot build
## expects; if project.godot's copy fails to parse cleanly on a different
## engine point-version, an action can silently end up missing or with no
## events, which then spams "InputMap action doesn't exist" errors from
## every Input.is_action_*() call.
##
## This runs before any gameplay scene (all autoloads initialize before the
## main scene loads) and fills in any action that's missing or has no
## events. It never touches an action that's already correctly configured,
## so if project.godot's definitions did load fine, this is a no-op.

const KEY_ACTIONS: Dictionary = {
	"move_forward": KEY_W,
	"move_back": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"jump": KEY_SPACE,
	"crouch": KEY_CTRL,
	"melee": KEY_V,  ## matches Player._wants_melee()'s hardcoded key; was KEY_F, which nothing else ever agreed with
	"interact": KEY_E,  ## mount/dismount the Gunship's driver seat - see Player._wants_interact()
	"weapon_rocket": KEY_1,
	"weapon_railgun": KEY_2,
	"weapon_slug": KEY_3,
	"weapon_planetbuster": KEY_4,
	"ui_cancel": KEY_ESCAPE,
}

const MOUSE_BUTTON_ACTIONS: Dictionary = {
	"fire": MOUSE_BUTTON_LEFT,
	"aim": MOUSE_BUTTON_RIGHT,
	"weapon_next": MOUSE_BUTTON_WHEEL_DOWN,
	"weapon_prev": MOUSE_BUTTON_WHEEL_UP,
}

func _ready() -> void:
	for action_name in KEY_ACTIONS:
		_ensure_key_action(action_name, KEY_ACTIONS[action_name])
	for action_name in MOUSE_BUTTON_ACTIONS:
		_ensure_mouse_action(action_name, MOUSE_BUTTON_ACTIONS[action_name])

func _ensure_key_action(action_name: String, keycode: Key) -> void:
	if _already_bound(action_name):
		return
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action_name, event)

func _ensure_mouse_action(action_name: String, button_index: MouseButton) -> void:
	if _already_bound(action_name):
		return
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	InputMap.action_add_event(action_name, event)

func _already_bound(action_name: String) -> bool:
	return InputMap.has_action(action_name) and not InputMap.action_get_events(action_name).is_empty()
