class_name TerracottaBridge
extends Node
## Only the discovery/health protocol is emulated. Gameplay remains ENet UDP.
signal verified(ok: bool)
var _listener := TCPServer.new()
var _announce := PacketPeerUDP.new()
var _connections: Array[Dictionary] = []
var _port := 0
var _timer := 0.0
var _probe: StreamPeerTCP
var _deadline := 0
var _sent := false
var _response := PackedByteArray()


func start(port: int) -> String:
	stop()
	if _listener.listen(port, "127.0.0.1") != OK:
		return "远程兼容端口被占用，请更换端口后重试。"
	_port = port
	_announce.set_dest_address("127.0.0.1", 4445)
	_timer = 0.0
	return ""


func stop() -> void:
	_listener.stop()
	_announce.close()
	_port = 0
	for entry: Dictionary in _connections: entry.peer.disconnect_from_host()
	_connections.clear()
	if _probe != null: _probe.disconnect_from_host()
	_probe = null


func verify_port(scaffolding_port: int) -> void:
	_probe = StreamPeerTCP.new()
	_sent = false
	_response.clear()
	_deadline = Time.get_ticks_msec() + 5000
	_probe.connect_to_host("127.0.0.1", scaffolding_port)


func _process(dt: float) -> void:
	if _port != 0:
		_timer -= dt
		if _timer <= 0:
			_timer = 0.4
			_announce.put_packet(("[MOTD]WDFZ Terracotta[/MOTD][AD]%d[/AD]" % _port).to_utf8_buffer())
		if _listener.is_connection_available():
			var peer := _listener.take_connection()
			if _connections.size() < 16:
				_connections.append({"peer": peer, "until": Time.get_ticks_msec() + 2000})
			else: peer.disconnect_from_host()
		for i in range(_connections.size() - 1, -1, -1):
			var entry := _connections[i]
			var peer: StreamPeerTCP = entry.peer
			peer.poll()
			if peer.get_available_bytes() > 0:
				if peer.get_u8() == 254:
					# Legacy status string: UTF-16BE, bounded and independent of save state.
					peer.put_data(PackedByteArray([255, 0, 4, 0, 87, 0, 68, 0, 70, 0, 90]))
				entry["until"] = 0
			if Time.get_ticks_msec() >= int(entry["until"]) or peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				peer.disconnect_from_host()
				_connections.remove_at(i)
	if _probe == null: return
	_probe.poll()
	if not _sent and _probe.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		var name_bytes := "c:server_port".to_ascii_buffer()
		var packet := PackedByteArray([name_bytes.size()])
		packet.append_array(name_bytes)
		packet.append_array(PackedByteArray([0, 0, 0, 0]))
		_probe.put_data(packet)
		_sent = true
	if _probe.get_available_bytes() > 0:
		var data := _probe.get_partial_data(mini(8, _probe.get_available_bytes()))
		if data[0] == OK: _response.append_array(data[1])
	var done := _response.size() >= 7
	if done or Time.get_ticks_msec() >= _deadline or _probe.get_status() == StreamPeerTCP.STATUS_ERROR:
		var ok := done and _response.slice(0, 5) == PackedByteArray([0, 0, 0, 0, 2]) and (_response[5] * 256 + _response[6]) == _port
		_probe.disconnect_from_host()
		_probe = null
		verified.emit(ok)


func _exit_tree() -> void:
	stop()
