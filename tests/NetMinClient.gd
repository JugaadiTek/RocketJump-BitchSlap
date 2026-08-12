extends Node
## Minimal, Arena-free client - pairs with NetMinHost.gd.
const LOG_PATH := "/tmp/rjbs_net_min_client.log"

static func _log(line: String) -> void:
	print(line)
	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(LOG_PATH) else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(line)
		f.close()

func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var address: String = args[0] if args.size() > 0 else "127.0.0.1"
	var port: int = args[1].to_int() if args.size() > 1 else 17700
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(address, port)
	_log("MINCLIENT create_client err=%d" % err)
	multiplayer.multiplayer_peer = peer
	var connected: bool = false
	var failed: bool = false
	multiplayer.connected_to_server.connect(func(): connected = true)
	multiplayer.connection_failed.connect(func(): failed = true)
	multiplayer.server_disconnected.connect(func(): _log("MINCLIENT server_disconnected"))

	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 25000:
		await get_tree().process_frame
		if connected or failed:
			break
		if int(Time.get_ticks_msec() - t0) % 1000 < 20:
			_log("MINCLIENT t+%dms status: peer=%s get_connection_status=%s" % [
				Time.get_ticks_msec() - t0, peer, peer.get_connection_status()])

	if connected:
		_log("MINCLIENT connected_to_server fired after %dms, unique_id=%d" % [Time.get_ticks_msec() - t0, multiplayer.get_unique_id()])
	elif failed:
		_log("MINCLIENT connection_failed after %dms" % [Time.get_ticks_msec() - t0])
	else:
		_log("MINCLIENT TIMED OUT after %dms, final peer.get_connection_status()=%s" % [Time.get_ticks_msec() - t0, peer.get_connection_status()])
	get_tree().quit()
