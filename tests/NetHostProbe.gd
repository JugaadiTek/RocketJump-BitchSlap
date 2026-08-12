extends Node
## Headless multiplayer HOST probe. Exercises the exact code path
## MainMenu._on_host_pressed() does (NetworkManager.host_game() then load
## Arena.tscn), driven directly instead of via button clicks, so it can run
## headless as its own OS process. Pair with NetClientProbe.gd running as a
## second process to verify a real ENet handshake, peer replication, and
## MultiplayerSpawner player spawning end to end - not just read off the
## source.
##
## change_scene_to_file() makes Arena the actual current_scene, mounted
## directly under /root as /root/Arena/... - that absolute path is what has
## to match between host and client for MultiplayerSpawner's node-path-based
## replication to resolve at all, so this can't just add Arena as an
## ordinary child the way the other probes do. The catch: change_scene_to_file
## FREES whatever was the previous current_scene - if that's this very probe
## node, everything after the call never runs. So the actual monitoring lives
## in a small Monitor node added directly to get_tree().root (a sibling of
## current_scene, not inside it) BEFORE the scene swap, which survives it.
##
## Run: Godot --headless --path . res://tests/NetHostProbe.tscn -- <port>

const LOG_PATH := "/tmp/rjbs_net_host.log"

static func _log(line: String) -> void:
	print(line)
	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(LOG_PATH) else FileAccess.WRITE)
	if f:
		f.seek_end(); f.store_line(line); f.close()

func _ready() -> void:
	# Let the scene tree finish its own initial setup before calling
	# change_scene_to_file() below - doing that synchronously inside the
	# very first _ready() collides with the engine's own in-progress
	# add/remove of the root scene ("Parent node is busy adding/removing
	# children"). MainMenu.gd never hits this in real play because a human
	# clicking Host happens long after the tree has settled; a probe driving
	# the same call from _ready() needs to wait a frame for the same effect.
	await get_tree().process_frame

	var port: int = NetworkManager.DEFAULT_PORT
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		port = args[0].to_int()

	MatchState.start_with_all_weapons = false
	var err: Error = NetworkManager.host_game(port)
	if err != OK:
		_log("HOST    FAILED to host on port %d: error %d" % [port, err])
		get_tree().quit(1)
		return
	_log("HOST    listening on 0.0.0.0:%d (unique_id=%d, is_server=%s)" % [
		port, multiplayer.get_unique_id(), NetworkManager.is_server()])

	NetworkManager.player_joined.connect(func(id): _log("HOST    player_joined signal: peer %d" % id))
	NetworkManager.player_left.connect(func(id): _log("HOST    player_left signal: peer %d" % id))

	var monitor := Monitor.new()
	get_tree().root.add_child(monitor)

	get_tree().change_scene_to_file("res://scenes/world/Arena.tscn")
	# `self` is about to be freed by the scene swap above - nothing after
	# this point in THIS node is safe to run. Monitor.new() already took
	# over.

class Monitor extends Node:
	static func _log(line: String) -> void:
		print(line)
		var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(LOG_PATH) else FileAccess.WRITE)
		if f:
			f.seek_end(); f.store_line(line); f.close()

	func _ready() -> void:
		await get_tree().process_frame
		await get_tree().process_frame
		var arena: Node = get_tree().current_scene
		if arena:
			arena.bot_count = 0  # keep this run about the network handshake, not AI

		# Poll for up to ~20s, logging peer/player state every second so a
		# connecting client's arrival (and any player it spawns) is visible.
		for second in range(30):
			await get_tree().create_timer(1.0).timeout
			var peers: PackedInt32Array = get_tree().get_multiplayer().get_peers()
			var players: Node = get_tree().current_scene.get_node_or_null("Players") if get_tree().current_scene else null
			var player_names: Array = []
			if players:
				for c in players.get_children():
					player_names.append(c.name)
			_log("HOST    t+%ds peers=%s players_in_world=%s" % [second + 1, peers, player_names])
			if peers.size() > 0 and player_names.size() >= 2:
				_log("HOST    a remote peer connected AND replicated a player into this world - handshake+spawn verified")
				break

		_log("HOST    done, shutting down")
		NetworkManager.disconnect_game()
		get_tree().quit()
