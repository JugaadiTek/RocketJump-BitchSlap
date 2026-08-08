extends Node
## NetworkManager (autoload)
##
## Bare-bones IP connect/host using Godot's high-level ENet multiplayer API.
## Player spawning is handled by a MultiplayerSpawner in Arena.tscn - this
## singleton just owns the peer connection and tells the Arena who joined.
##
## Trust model note: this is a prototype-scope netcode. Combat RPCs (see
## Weapon/Rocket/Melee scripts) let any peer tell another peer's player "you
## took damage" and trust it, and projectiles are simulated independently on
## every peer rather than replicated from a single source of truth. That's
## fine for a starter kit / LAN party, but a shippable game would want
## server-authoritative hit registration.

signal server_started
signal connected_to_server
signal connection_failed
signal player_joined(peer_id: int)
signal player_left(peer_id: int)

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 16

var is_online: bool = false

func host_game(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_error("Failed to host on port %d: %s" % [port, err])
		return err
	multiplayer.multiplayer_peer = peer
	is_online = true
	_connect_signals()
	server_started.emit()
	player_joined.emit(multiplayer.get_unique_id())
	return OK

func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(address, port)
	if err != OK:
		push_error("Failed to connect to %s:%d - %s" % [address, port, err])
		return err
	multiplayer.multiplayer_peer = peer
	is_online = true
	_connect_signals()
	return OK

func disconnect_game() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	is_online = false

func is_server() -> bool:
	return is_online and multiplayer.is_server()

func _connect_signals() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)

func _on_peer_connected(id: int) -> void:
	player_joined.emit(id)

func _on_peer_disconnected(id: int) -> void:
	player_left.emit(id)

func _on_connected_to_server() -> void:
	connected_to_server.emit()
	player_joined.emit(multiplayer.get_unique_id())

func _on_connection_failed() -> void:
	is_online = false
	connection_failed.emit()

func _on_server_disconnected() -> void:
	is_online = false
