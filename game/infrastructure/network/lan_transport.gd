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
var _budgets: Dictionary = {}
var _budget_time := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().set_multiplayer(api, get_path())
	api.allow_object_decoding = false
	# This is a host-authoritative star; clients never talk to other clients.
	# Avoid ENet relay notifications racing with disconnected peer channels.
	api.server_relay = false
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
	peer = ENetMultiplayerPeer.new()
	# Allow each guest one replacement handshake while its lost tunnel expires.
	# CooperativeRoom still caps the actual game at four authenticated students.
	var error := peer.create_server(port, 6, LanProtocol.CHANNELS)
	if error != OK:
		peer = null
		return "无法创建房间，端口可能被占用（%d）。" % error
	serving = true
	# Compressed ENet datagrams leave space for EasyTier's tunnel headers.
	# Raw fragmented snapshot RPCs otherwise stall across its UDP forwarding path.
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	api.multiplayer_peer = peer
	return ""


func join(ip: String, port: int) -> String:
	close()
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_client(ip, port, LanProtocol.CHANNELS)
	if error != OK:
		peer = null
		return "无法连接房间（%d）。" % error
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	api.multiplayer_peer = peer
	return ""


func close() -> void:
	if peer != null: peer.close()
	peer = null
	serving = false
	api.multiplayer_peer = OfflineMultiplayerPeer.new()
	_budgets.clear()


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
	if not can_send(id): return
	var packet := LanProtocol.encode(data)
	if packet.size() > LanProtocol.MAX_PACKET: return
	bytes_sent += packet.size()
	_control.rpc_id(id, packet)


func send_input(data: Dictionary) -> void:
	if not can_send(1): return
	var packet := LanProtocol.encode(data)
	bytes_sent += packet.size()
	_receive_input_packet.rpc_id(1, packet)


func send_chunk(id: int, data: Dictionary) -> void:
	if not can_send(id): return
	var packet := LanProtocol.encode(data)
	if packet.size() > LanProtocol.MAX_PACKET: return
	bytes_sent += packet.size()
	_chunk.rpc_id(id, packet)


func send_motion(id: int, data: Dictionary) -> void:
	if not can_send(id): return
	var packet := LanProtocol.encode(data)
	bytes_sent += packet.size()
	_motion.rpc_id(id, packet)


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


@rpc("any_peer", "call_remote", "reliable", 0)
func _control(packet: PackedByteArray) -> void:
	var sender := api.get_remote_sender_id()
	if not serving and sender != 1: return
	if not _allowed(sender, packet.size()): return
	bytes_received += packet.size()
	var data := LanProtocol.decode(packet)
	if not data.is_empty(): control_received.emit(sender, data)


@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _receive_input_packet(packet: PackedByteArray) -> void:
	if not serving: return
	var sender := api.get_remote_sender_id()
	if not _allowed(sender, packet.size(), true): return
	bytes_received += packet.size()
	var data := LanProtocol.decode(packet, 1200)
	if not data.is_empty(): input_received.emit(sender, data)


@rpc("authority", "call_remote", "reliable", 1)
func _chunk(packet: PackedByteArray) -> void:
	if serving or api.get_remote_sender_id() != 1 or packet.size() > LanProtocol.MAX_PACKET: return
	bytes_received += packet.size()
	var data := LanProtocol.decode(packet)
	if not data.is_empty(): chunk_received.emit(1, data)


@rpc("authority", "call_remote", "unreliable_ordered", 3)
func _motion(packet: PackedByteArray) -> void:
	if serving or api.get_remote_sender_id() != 1: return
	bytes_received += packet.size()
	var data := LanProtocol.decode(packet, 8192)
	if not data.is_empty(): motion_received.emit(data)


func _exit_tree() -> void:
	close()
	get_tree().set_multiplayer(null, get_path())
