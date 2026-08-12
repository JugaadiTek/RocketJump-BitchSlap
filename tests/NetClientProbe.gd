extends Node
## Headless multiplayer CLIENT probe. Exercises the exact code path
## MainMenu._on_join_pressed() does - NetworkManager.join_game() immediately
## followed by loading Arena.tscn, NOT waiting for connected_to_server first
## (see the fix in MainMenu.gd/NetworkManager.gd and the CHANGELOG entry it's
## documented under) - driven directly instead of via button clicks. Pair
## with NetHostProbe.gd running as a separate OS process.
##
## See NetHostProbe.gd's header for why the actual monitoring lives in a
## Monitor node added to get_tree().root rather than in this node - the
## change_scene_to_file() call below frees whatever the current_scene was,
## which would be this node otherwise.
##
## Run: Godot --headless --path . res://tests/NetClientProbe.tscn -- <address> <port>

const LOG_PATH := "/tmp/rjbs_net_client.log"

static func _log(line: String) -> void:
	print(line)
	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(LOG_PATH) else FileAccess.WRITE)
	if f:
		f.seek_end(); f.store_line(line); f.close()

func _ready() -> void:
	# See NetHostProbe.gd - same reasoning for waiting a frame before driving
	# any scene-tree-affecting calls from the very first _ready().
	await get_tree().process_frame

	var address: String = "127.0.0.1"
	var port: int = NetworkManager.DEFAULT_PORT
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		address = args[0]
	if args.size() > 1:
		port = args[1].to_int()

	var t0: int = Time.get_ticks_msec()
	var err: Error = NetworkManager.join_game(address, port)
	if err != OK:
		_log("CLIENT  FAILED to start connection to %s:%d: error %d" % [address, port, err])
		get_tree().quit(1)
		return
	_log("CLIENT  connecting to %s:%d ..." % [address, port])

	var monitor := Monitor.new()
	monitor.t0 = t0
	get_tree().root.add_child(monitor)

	# Fixed flow: load Arena immediately, the same way the host already does,
	# instead of waiting for connected_to_server first - see MainMenu.gd.
	get_tree().change_scene_to_file("res://scenes/world/Arena.tscn")
	# `self` may be freed any moment now - nothing after this point in THIS
	# node is safe to run. Monitor.new() already took over.

class Monitor extends Node:
	var t0: int = 0

	static func _log(line: String) -> void:
		print(line)
		var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(LOG_PATH) else FileAccess.WRITE)
		if f:
			f.seek_end(); f.store_line(line); f.close()

	func _ready() -> void:
		var connected: bool = false
		var failed: bool = false
		NetworkManager.connected_to_server.connect(func(): connected = true)
		NetworkManager.connection_failed.connect(func(): failed = true)

		# Wall-clock timeout, not a fixed frame count: headless runs uncapped
		# and unpredictably fast, so a frame budget doesn't reflect real
		# elapsed time. 25s is generous - the host side of this handshake
		# reliably registers the peer within ~9s (see NetHostProbe.gd).
		while Time.get_ticks_msec() - t0 < 25000:
			await get_tree().process_frame
			if connected or failed:
				break
		var elapsed_ms: int = Time.get_ticks_msec() - t0

		if failed:
			_log("CLIENT  connection_failed after %dms" % elapsed_ms)
			get_tree().quit(1)
			return
		if not connected:
			_log("CLIENT  TIMED OUT after %dms waiting for connected_to_server (host unreachable, wrong port, or firewalled)" % elapsed_ms)
			get_tree().quit(1)
			return
		_log("CLIENT  connected_to_server fired after %dms (unique_id=%d)" % [elapsed_ms, get_tree().get_multiplayer().get_unique_id()])

		# Wait for the server to replicate: our own spawned Player (via
		# MultiplayerSpawner, server-authoritative) and the host's own player.
		var saw_players: Array = []
		for second in range(10):
			await get_tree().create_timer(1.0).timeout
			var players: Node = get_tree().current_scene.get_node_or_null("Players") if get_tree().current_scene else null
			saw_players = []
			if players:
				for c in players.get_children():
					saw_players.append(c.name)
			_log("CLIENT  t+%ds players_in_world=%s (own unique_id=%d)" % [second + 1, saw_players, get_tree().get_multiplayer().get_unique_id()])
			if saw_players.size() >= 2:
				_log("CLIENT  replication verified - can see both the host's player and my own spawned player")
				break

		_log("CLIENT  done, disconnecting")
		NetworkManager.disconnect_game()
		get_tree().quit()
