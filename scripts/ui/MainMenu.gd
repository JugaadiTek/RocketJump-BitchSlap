extends Control

const ARENA_SCENE_PATH: String = "res://scenes/world/Arena.tscn"

@onready var ip_field: LineEdit = $CenterContainer/VBoxContainer/JoinRow/IpField
@onready var port_field: LineEdit = $CenterContainer/VBoxContainer/PortRow/PortField
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel
@onready var host_button: Button = $CenterContainer/VBoxContainer/HostButton
@onready var join_button: Button = $CenterContainer/VBoxContainer/JoinRow/JoinButton
@onready var offline_button: Button = $CenterContainer/VBoxContainer/OfflineButton
@onready var all_weapons_check: CheckBox = $CenterContainer/VBoxContainer/AllWeaponsCheck

func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	offline_button.pressed.connect(_on_offline_pressed)
	NetworkManager.connected_to_server.connect(_on_connected_to_server)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	all_weapons_check.button_pressed = MatchState.start_with_all_weapons

## Stashed on MatchState rather than passed along, because every entry point
## below leaves this scene behind - the flag has to outlive it.
func _apply_options() -> void:
	Sfx.play_ui("ui_click")
	MatchState.start_with_all_weapons = all_weapons_check.button_pressed

func _get_port() -> int:
	var value: int = port_field.text.to_int()
	return value if value > 0 else NetworkManager.DEFAULT_PORT

func _on_host_pressed() -> void:
	_apply_options()
	status_label.text = "Starting server..."
	var err: Error = NetworkManager.host_game(_get_port())
	if err != OK:
		status_label.text = "Failed to host (port in use?)"
		return
	get_tree().change_scene_to_file(ARENA_SCENE_PATH)

## The client used to wait right here for NetworkManager.connected_to_server
## before ever loading Arena - which reliably never fired. The real ENet
## handshake takes several seconds, and the moment the low-level connection
## registers, the SERVER starts replicating its already-spawned nodes
## (itself, any bots) to the new peer via absolute paths under
## "Arena/...". A client still sitting on MainMenu has no "Arena" node at
## all yet, so every one of those replication messages resolved to nothing
## ("Node not found: Arena/BotSpawner") - and that appears to be exactly
## what stalled the connection-completion handshake itself, not just spammed
## harmless errors: confirmed via tests/NetHostProbe.gd + NetClientProbe.gd,
## the host's side completed and replicated a player for the peer every
## single time, but connected_to_server never fired on the client, even
## given 60 real seconds.
##
## Fix: load Arena immediately, the same way _on_host_pressed() already
## does, instead of waiting for the connection to finish first - so the
## matching node paths already exist by the time the server's replication
## traffic arrives, whenever that turns out to be. connected_to_server no
## longer needs to do anything (this scene will already be long gone by the
## time it fires); a failed connection is handled by
## NetworkManager._on_connection_failed(), which - since this scene won't be
## around to hear about it either - routes back to MainMenu itself.
func _on_join_pressed() -> void:
	_apply_options()
	var address: String = ip_field.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	var err: Error = NetworkManager.join_game(address, _get_port())
	if err != OK:
		status_label.text = "Invalid address"
		return
	get_tree().change_scene_to_file(ARENA_SCENE_PATH)

func _on_connected_to_server() -> void:
	pass  # already in Arena by now - see _on_join_pressed()

func _on_connection_failed() -> void:
	status_label.text = "Connection failed."

func _on_offline_pressed() -> void:
	_apply_options()
	get_tree().change_scene_to_file(ARENA_SCENE_PATH)
