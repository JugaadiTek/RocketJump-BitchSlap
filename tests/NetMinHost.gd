extends Node
## Minimal, Arena-free host - isolates whether connected_to_server ever
## fires on a bare connection with nothing else going on: no scene changes,
## no MultiplayerSpawners, no replication traffic at all.
const LOG_PATH := "/tmp/rjbs_net_min_host.log"

static func _log(line: String) -> void:
	print(line)
	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(LOG_PATH) else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(line)
		f.close()

func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var port: int = args[0].to_int() if args.size() > 0 else 17700
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, 32)
	_log("MINHOST create_server err=%d" % err)
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(func(id): _log("MINHOST peer_connected: %d" % id))
	multiplayer.peer_disconnected.connect(func(id): _log("MINHOST peer_disconnected: %d" % id))
	for i in range(30):
		await get_tree().create_timer(1.0).timeout
		_log("MINHOST t+%ds peers=%s" % [i + 1, multiplayer.get_peers()])
		if multiplayer.get_peers().size() > 0:
			break
	_log("MINHOST done")
	get_tree().quit()
