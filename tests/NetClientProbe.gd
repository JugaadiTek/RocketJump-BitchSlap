extends Node
## Headless multiplayer CLIENT probe. Exercises the exact code path
## MainMenu._on_join_pressed() does (NetworkManager.join_game() then load
## Arena.tscn once connected_to_server fires), driven directly instead of via
## button clicks. Pair with NetHostProbe.gd running as a separate OS process.
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

	var connected: bool = false
	var failed: bool = false
	NetworkManager.connected_to_server.connect(func(): connected = true)
	NetworkManager.connection_failed.connect(func(): failed = true)

	# Wall-clock timeout, not a fixed frame count: headless runs uncapped and
	# unpredictably fast (a first pass here counted 600 frames in ~4.5s and
	# gave up before a frame-count budget could reflect real elapsed time).
	# 25s is generous - the host side of this same handshake reliably
	# registers the peer within ~9s (see NetHostProbe.gd) - but this is NOT
	# just about giving a slow connection more time: as of this writing,
	# repeated runs (including a 60s budget) show the client's
	# connected_to_server NEVER fires at all even though the host's side
	# completes and successfully replicates a player for the new peer -
	# see the CHANGELOG entry this probe's addition is documented under.
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
	_log("CLIENT  connected_to_server fired after %dms (unique_id=%d)" % [elapsed_ms, multiplayer.get_unique_id()])

	var monitor := Monitor.new()
	get_tree().root.add_child(monitor)

	get_tree().change_scene_to_file("res://scenes/world/Arena.tscn")
	# `self` may be freed any moment now - nothing after this point in THIS
	# node is safe to run. Monitor.new() already took over.

class Monitor extends Node:
	static func _log(line: String) -> void:
		print(line)
		var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(LOG_PATH) else FileAccess.WRITE)
		if f:
			f.seek_end(); f.store_line(line); f.close()

	func _ready() -> void:
		await get_tree().process_frame
		await get_tree().process_frame

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
