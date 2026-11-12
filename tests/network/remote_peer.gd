extends SceneTree
## Two real game authorities connected only via official Terracotta + EasyTier.
class LocalRendezvous extends TerracottaGateway:
	var node_port := 0
	func request(path: String) -> void:
		if path.begins_with("/state/scanning?") or path.begins_with("/state/guesting?"):
			path += "&public_nodes=" + ("tcp://127.0.0.1:%d" % node_port).uri_encode()
		super.request(path)

var tunnel := TerracottaSession.new()
var network := LanSession.new()
var host := false
var players := 2
var nickname := "guest-1"
var directory := ""
var port := 24560
var relay := 0
var checks := 0
var failures := 0
var snapshots := 0
var motions := 0
var state: Dictionary = {}
var elapsed := 0.0
var played := 0.0
var step := 0
var seq := 0
var loaded_epoch := ""
var identity := ""
var token := ""
var room_code := ""
var finishing := false
var reconnecting := false
var next_input := 0.0
var next_report := 5.0


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--host": host = true
		if arg.begins_with("--players="): players = int(arg.trim_prefix("--players="))
		if arg.begins_with("--name="): nickname = arg.trim_prefix("--name=")
		if arg.begins_with("--directory="): directory = arg.trim_prefix("--directory=")
		if arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
		if arg.begins_with("--relay="): relay = int(arg.trim_prefix("--relay="))
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", label)


func write(name: String, data: Dictionary) -> void:
	var file := FileAccess.open(directory.path_join(name), FileAccess.WRITE)
	file.store_string(JSON.stringify(data))


func run() -> void:
	tunnel.gateway.free()
	var gateway := LocalRendezvous.new()
	gateway.node_port = relay
	tunnel.gateway = gateway
	root.add_child(tunnel)
	root.add_child(network)
	tunnel.failed.connect(func(reason: String) -> void:
		if not finishing:
			check(false, reason)
			finish())
	tunnel.connected.connect(func(target: String, code: String) -> void:
		if host:
			room_code = code
			write("invitation.json", {"code": code})
			check(tunnel.available, "host port verified against Scaffolding")
		else:
			check(target != "127.0.0.1:%d" % port, "guest uses independently forwarded UDP port")
			check(network.join(target, nickname, token) == "", "ENet joins through Terracotta")
			reconnecting = false)
	network.closed.connect(func(reason: String) -> void:
		if not finishing and not reconnecting:
			check(false, reason)
			finish())
	network.transport.connected.connect(func() -> void: print("ENET CONNECTED"))
	network.notice.connect(func(text: String) -> void: print("NOTICE: ", text))
	network.room_changed.connect(func(_data: Dictionary) -> void:
		if network.room.phase == "lobby" and network.room.members.has(network.local_id) and not network.room.members[network.local_id].ready:
			network.ready(true, "watch")
		if host and network.room.members.size() == players and network.room.can_start():
			check(network.start() == "", "remote players start shared authority"))
	network.snapshot_received.connect(func(data: Dictionary) -> void:
		state = data
		snapshots += 1
		if loaded_epoch != network.room.epoch:
			loaded_epoch = network.room.epoch
			network.loaded())
	network.motion_received.connect(func(_data: Dictionary) -> void: motions += 1)
	if host:
		check(network.host("remote fixture", "host", port) == "", "ENet host created")
		check(tunnel.begin(true, "host", "", port) == "", "real Terracotta host boot")
	else:
		var file := FileAccess.open(directory.path_join("invitation.json"), FileAccess.READ)
		room_code = String(JSON.parse_string(file.get_as_text())["code"])
		check(tunnel.begin(false, nickname, room_code) == "", "real Terracotta guest boot")


func _process(dt: float) -> bool:
	if finishing: return false
	elapsed += dt
	if elapsed >= next_report:
		next_report += 10.0
		print("REMOTE PROGRESS: ", "host" if host else "guest", " tunnel=", tunnel.phase, " game=", network.room.phase if network.room != null else "none", " snapshots=", snapshots, " step=", step)
		var ages: Array = []
		for id: int in network._peer_heard:
			if id != 1: ages.append(snappedf(network._clock - float(network._peer_heard[id]), 0.1))
		print("ENET PROGRESS: connections=", network.connections.size(), " peer_ages=", ages, " transport=", network.transport.peer.get_connection_status() if network.transport.peer != null else -1, " retry=", network._hello_again_at > 0.0)
		if host and network.transport.peer != null:
			var states: Array = []
			for socket: ENetPacketPeer in network.transport.peer.host.get_peers(): states.append(socket.get_state())
			print("ENET SOCKETS: ", states, " pending=", network._peers_waiting.size())
	if elapsed > 180:
		check(false, "real tunnel connection/gameplay timeout")
		finish()
		return false
	if network.room != null and network.room.phase == "playing" and not reconnecting:
		played += dt
		next_input -= dt
		if not state.is_empty() and next_input <= 0:
			next_input = 0.05
			seq += 1
			network.input({"seq": seq, "scene": state.scene, "x": 0.0, "y": 0.0, "yaw": 0.0, "pitch": 0.0, "run": false})
		if not host and step == 0 and played > 4:
			identity = network.local_id
			token = network.reconnect_token
			step = 1
			reconnecting = true
			# Break the tunnel first, so the old ENet disconnect cannot reach the
			# host. This is a real stale-socket reconnect, not a graceful LAN leave.
			tunnel.stop()
			loaded_epoch = ""
			state.clear()
		elif not host and step == 2 and played > 8:
			check(identity == network.local_id, "original role survives a rebuilt tunnel")
			check(snapshots >= 5 and motions >= 10, "reliable snapshots and UDP movement cross the tunnel")
			write(nickname + "-done.json", {"checks": checks, "failures": failures})
			finish()
		elif host and guests_done():
			check(network.room.members.size() == players, "reconnect does not create another student")
			check(snapshots >= 5, "host keeps shared world running")
			finish()
	if reconnecting and step == 1 and tunnel.phase == "idle":
		network.stop()
		step = 2
		check(tunnel.begin(false, nickname, room_code) == "", "rebuild tunnel using invitation rather than stale local port")
	return false


func guests_done() -> bool:
	for i in range(1, players):
		if not FileAccess.file_exists(directory.path_join("guest-%d-done.json" % i)): return false
	return true


func finish() -> void:
	if finishing: return
	finishing = true
	network.stop()
	tunnel.stop()
	var until := Time.get_ticks_msec() + 15000
	while tunnel.phase != "idle" and Time.get_ticks_msec() < until: await process_frame
	check(tunnel.phase == "idle", "remote room cleanly released")
	write("host-summary.json" if host else nickname + "-summary.json", {"checks": checks, "failures": failures, "snapshots": snapshots, "motions": motions})
	print("TERRACOTTA PEER: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
