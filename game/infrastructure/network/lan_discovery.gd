class_name LanDiscovery
extends Node
## Best-effort LAN discovery. Direct address entry never depends on broadcasts.
signal found(rooms: Array)
var socket: PacketPeerUDP
var advertisement: Dictionary = {}
var rooms: Dictionary = {}
var _elapsed := 0.0
var _until := 0.0


func serve(info: Dictionary) -> String:
	close()
	socket = PacketPeerUDP.new()
	if socket.bind(LanProtocol.DISCOVERY_PORT) != OK:
		socket = null
		return "房间发现端口被占用；仍可通过 IP 加入。"
	advertisement = info.duplicate()
	return ""


func discover() -> void:
	close()
	socket = PacketPeerUDP.new()
	if socket.bind(0) != OK:
		socket = null
		return
	socket.set_broadcast_enabled(true)
	_until = Time.get_ticks_msec() / 1000.0 + 8.0
	_elapsed = 2.0


func _process(dt: float) -> void:
	if socket == null: return
	var now := Time.get_ticks_msec() / 1000.0
	if advertisement.is_empty():
		_elapsed += dt
		if now < _until and _elapsed >= 1.0:
			_elapsed = 0.0
			socket.set_dest_address("255.255.255.255", LanProtocol.DISCOVERY_PORT)
			socket.put_packet(LanProtocol.encode({"wdfz": LanProtocol.VERSION}))
		var expired := false
		for key: String in rooms.keys():
			if now - float(rooms[key]["seen"]) > 8.0:
				rooms.erase(key)
				expired = true
		if expired: found.emit(rooms.values())
	var budget := 16
	while socket.get_available_packet_count() > 0 and budget > 0:
		budget -= 1
		var packet := socket.get_packet()
		var sender := socket.get_packet_ip()
		var port := socket.get_packet_port()
		var data := LanProtocol.decode(packet, 1200)
		if data.get("wdfz") != LanProtocol.VERSION: continue
		if not advertisement.is_empty():
			socket.set_dest_address(sender, port)
			var info := advertisement.duplicate()
			info["wdfz"] = LanProtocol.VERSION
			socket.put_packet(LanProtocol.encode(info))
		elif data.get("name") is String and String(data["name"]).length() <= 32 and SaveSchema.is_integer(data.get("port"), 1024, 65535):
			if not SaveSchema.is_integer(data.get("count"), 0, 4) or data.get("phase") not in ["lobby", "loading", "playing", "ended"]: continue
			var key := sender + ":" + str(int(data["port"]))
			if rooms.size() >= 64 and not rooms.has(key): continue
			data["ip"] = sender
			data["seen"] = now
			rooms[key] = data
			found.emit(rooms.values())


func close() -> void:
	if socket != null: socket.close()
	socket = null
	advertisement.clear()
	rooms.clear()
	found.emit([])
	_until = 0.0


func _exit_tree() -> void:
	close()
