class_name LanTransport
extends Node
## A dedicated MultiplayerAPI subtree keeps the single-player tree off the wire.
signal control_received(peer: int, data: Dictionary)
signal input_received(peer: int, data: Dictionary)
signal motion_received(data: Dictionary)
signal chunk_received(peer: int, data: Dictionary)
signal connected
signal disconnected(reason: String)
signal peer_left(peer: int)
var api := SceneMultiplayer.new()
var peer: ENetMultiplayerPeer
var serving := false
var bytes_sent := 0
var bytes_received := 0
var wire_sent := 0
var wire_received := 0
var packets_sent := 0
var packets_received := 0
var endpoint := ""
var role := ""
var local_port := 0
var last_state := "idle"
var last_error := ""
var _stats_time := 0.0
var _budgets: Dictionary = {}
var _budget_time := 0.0
enum Packet { CONTROL, INPUT, CHUNK, MOTION }


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().set_multiplayer(api, get_path())
	api.allow_object_decoding = false
	# This is a host-authoritative star; clients never talk to other clients.
	# Avoid ENet relay notifications racing with disconnected peer channels.
	api.server_relay = false
	api.peer_packet.connect(_receive_packet)
	api.connected_to_server.connect(func() -> void: connected.emit())
	api.connection_failed.connect(func() -> void: disconnected.emit("连接失败：检查地址、同一局域网和防火墙。"))
	api.server_disconnected.connect(func() -> void: disconnected.emit("房主连接中断。可重连原房间或返回菜单。"))
	api.peer_disconnected.connect(func(id: int) -> void: peer_left.emit(id))
	api.peer_connected.connect(func(id: int) -> void:
		var remote := peer.get_peer(id) if peer != null and (serving or id == 1) else null
		# Scene generation can block polling during the loading barrier. ENet must
		# allow that 60-second budget; application heartbeats detect gameplay loss.
		if remote != null: remote.set_timeout(32, 60000, 60000))


func host(port: int) -> String:
	close()
	reset_diagnostics()
	role = "host"
	endpoint = "0.0.0.0:%d" % port
	peer = ENetMultiplayerPeer.new()
	# Discovery and direct join both use IPv4. Do not rely on an Android
	# dual-stack wildcard accepting IPv4 on every Wi-Fi / tethering interface.
	peer.set_bind_ip("0.0.0.0")
	# Allow each guest one replacement handshake while its lost tunnel expires.
	# CooperativeRoom still caps the actual game at four authenticated students.
	var error := peer.create_server(port, 6, LanProtocol.CHANNELS)
	if error != OK:
		peer = null
		last_error = "无法创建房间，端口可能被占用（%d）。" % error
		return last_error
	serving = true
	# Godot 4.6.3 create_server passes max_channels + SYSCH_MAX as incoming
	# bandwidth (7 B/s here). Restore unlimited bandwidth before the first poll;
	# otherwise healthy clients lose most of their unreliable input packets.
	peer.host.bandwidth_limit(0, 0)
	# Compressed ENet datagrams leave space for EasyTier's tunnel headers.
	# Uncompressed fragmented snapshots otherwise stall across its UDP forwarding path.
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	api.multiplayer_peer = peer
	sample_network()
	return ""


func join(ip: String, port: int, reset_stats: bool = true) -> String:
	close()
	if reset_stats: reset_diagnostics()
	role = "client"
	endpoint = "%s:%d" % [ip, port]
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_client(ip, port, LanProtocol.CHANNELS)
	if error != OK:
		peer = null
		last_error = "无法连接房间（%d）。" % error
		return last_error
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	api.multiplayer_peer = peer
	sample_network()
	return ""


func close() -> void:
	sample_network()
	if peer != null: peer.close()
	peer = null
	serving = false
	api.multiplayer_peer = OfflineMultiplayerPeer.new()
	_budgets.clear()


func reset_diagnostics() -> void:
	bytes_sent = 0
	bytes_received = 0
	wire_sent = 0
	wire_received = 0
	packets_sent = 0
	packets_received = 0
	endpoint = ""
	role = ""
	local_port = 0
	last_state = "idle"
	last_error = ""
	_stats_time = 0.0


func sample_network() -> void:
	if peer == null: return
	var state := peer.get_connection_status()
	# A failed poll can already have destroyed the host before its signal runs.
	if state == MultiplayerPeer.CONNECTION_DISCONNECTED: return
	var socket := peer.host
	wire_sent += int(socket.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA))
	wire_received += int(socket.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA))
	packets_sent += int(socket.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS))
	packets_received += int(socket.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_PACKETS))
	local_port = socket.get_local_port()
	last_state = "listening" if serving else "connected" if state == MultiplayerPeer.CONNECTION_CONNECTED else "connecting"
	if not serving:
		var remotes := socket.get_peers()
		if not remotes.is_empty(): last_state += " / peer=%d" % remotes[0].get_state()


func _process(dt: float) -> void:
	_stats_time += dt
	if _stats_time >= 0.25:
		_stats_time = 0.0
		sample_network()


func expire_peer(id: int) -> void:
	if not serving or peer == null or not api.get_peers().has(id): return
	var socket := peer.get_peer(id)
	# SceneMultiplayer, ENetMultiplayerPeer and ENet each keep peer state.
	# disconnect_peer(force=true) only removes the Godot map; it still waits
	# for a network ACK. Expired tunnels cannot ACK, so reset the socket too.
	api.disconnect_peer(id)
	peer.disconnect_peer(id, true)
	if socket != null: socket.peer_disconnect_now()


func send_control(id: int, data: Dictionary) -> void:
	_send(id, Packet.CONTROL, data, LanProtocol.MAX_PACKET, MultiplayerPeer.TRANSFER_MODE_RELIABLE, 0)


func send_input(data: Dictionary) -> void:
	if not serving: _send(1, Packet.INPUT, data, 1200, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, 2)


func send_chunk(id: int, data: Dictionary) -> void:
	if serving: _send(id, Packet.CHUNK, data, LanProtocol.MAX_PACKET, MultiplayerPeer.TRANSFER_MODE_RELIABLE, 1)


func send_motion(id: int, data: Dictionary) -> void:
	if serving: _send(id, Packet.MOTION, data, 8192, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, 3)


func _send(id: int, kind: Packet, data: Dictionary, limit: int, mode: MultiplayerPeer.TransferMode, channel: int) -> void:
	if not can_send(id): return
	var packet := LanProtocol.encode(data)
	if packet.size() > limit: return
	# Messages contain JSON, not scene nodes. Raw SceneMultiplayer packets avoid
	# RPC path-cache IDs arriving ahead of their reliable registration after a
	# reconnect. Preserve independent ENet delivery/order for all four streams.
	packet.insert(0, kind)
	if api.send_bytes(packet, id, mode, channel) == OK: bytes_sent += packet.size()


func can_send(id: int) -> bool:
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED or not api.get_peers().has(id) or (not serving and id != 1): return false
	var remote := peer.get_peer(id)
	return remote != null and remote.get_state() == ENetPacketPeer.STATE_CONNECTED and remote.get_channels() >= LanProtocol.CHANNELS


func _allowed(id: int, size: int, input: bool = false) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _budget_time >= 1.0:
		_budgets.clear()
		_budget_time = now
	var key := "%d:%s" % [id, input]
	_budgets[key] = int(_budgets.get(key, 0)) + 1
	return size <= (1200 if input else LanProtocol.MAX_PACKET) and int(_budgets[key]) <= (90 if input else 80)


func _receive_packet(sender: int, packet: PackedByteArray) -> void:
	if sender < 1 or (not serving and sender != 1) or packet.size() < 2: return
	var kind := int(packet[0])
	var limit := LanProtocol.MAX_PACKET
	match kind:
		Packet.CONTROL:
			if not _allowed(sender, packet.size() - 1): return
		Packet.INPUT:
			if not serving or not _allowed(sender, packet.size() - 1, true): return
			limit = 1200
		Packet.CHUNK:
			if serving: return
		Packet.MOTION:
			if serving: return
			limit = 8192
		_: return
	if packet.size() > limit + 1: return
	var data := LanProtocol.decode(packet.slice(1), limit)
	if data.is_empty(): return
	bytes_received += packet.size()
	match kind:
		Packet.CONTROL: control_received.emit(sender, data)
		Packet.INPUT: input_received.emit(sender, data)
		Packet.CHUNK: chunk_received.emit(sender, data)
		Packet.MOTION: motion_received.emit(data)


func _exit_tree() -> void:
	close()
	get_tree().set_multiplayer(null, get_path())
