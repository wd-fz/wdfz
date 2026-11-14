class_name LanDiscovery
extends Node
## Best-effort LAN discovery. Direct address entry never depends on broadcasts.
##
## Probes go to the limited broadcast address, to each local IPv4 interface's /24 directed broadcast and to
## loopback. The limited address alone leaves through a single adapter on Windows (often a VPN or virtual
## NIC), so a host on the real Wi-Fi never heard it; loopback finds a room hosted on the same machine. Both
## sockets enable broadcast: on Android that also takes the Wi-Fi multicast lock, without which the system
## drops incoming broadcasts and a phone host never answered. One room seen through several addresses is
## listed once, by its room id, preferring a non-loopback address.
signal found(rooms: Array)
signal scanning_changed(active: bool)
const SCAN_TIME := 10.0
const PROBE_EVERY := 1.0
const ROOM_TTL := 8.0
## Replies per sender per second, and distinct senders answered per second (no amplification).
const REPLY_BUDGET := 4
const SENDER_BUDGET := 32
var socket: PacketPeerUDP
var advertisement: Dictionary = {}
var rooms: Dictionary = {}
var scanning := false
var _elapsed := 0.0
var _until := 0.0
var _replies: Dictionary = {}
var _reply_window := 0.0


func serve(info: Dictionary) -> String:
	close()
	socket = PacketPeerUDP.new()
	# IPv4 wildcard: broadcasts are IPv4 only, and some stacks do not deliver them to dual-stack sockets.
	if socket.bind(LanProtocol.DISCOVERY_PORT, "0.0.0.0") != OK:
		socket = null
		return "房间发现端口被占用；仍可通过 IP 加入。"
	socket.set_broadcast_enabled(true)
	advertisement = info.duplicate()
	if not advertisement.has("room"):
		advertisement["room"] = "%08x%08x" % [randi(), randi()]
	return ""


func discover() -> void:
	close()
	socket = PacketPeerUDP.new()
	if socket.bind(0, "0.0.0.0") != OK:
		socket = null
		scanning_changed.emit(false)
		return
	socket.set_broadcast_enabled(true)
	_until = Time.get_ticks_msec() / 1000.0 + SCAN_TIME
	_elapsed = PROBE_EVERY
	scanning = true
	scanning_changed.emit(true)


## Where one probe is sent: limited broadcast, each interface's /24 broadcast, then loopback.
static func probe_targets(interfaces: Array = IP.get_local_interfaces()) -> PackedStringArray:
	var out := PackedStringArray(["255.255.255.255"])
	for entry: Dictionary in interfaces:
		for address: String in entry.get("addresses", []):
			var parts := address.split(".")
			if parts.size() != 4 or not address.is_valid_ip_address() or parts[0] == "127": continue
			var directed := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
			if directed not in out: out.append(directed)
	out.append("127.0.0.1")
	return out


func _process(dt: float) -> void:
	if socket == null: return
	var now := Time.get_ticks_msec() / 1000.0
	if advertisement.is_empty() and scanning:
		_elapsed += dt
		if now < _until and _elapsed >= PROBE_EVERY:
			_elapsed = 0.0
			var probe := LanProtocol.encode({"wdfz": LanProtocol.VERSION})
			for target: String in probe_targets():
				socket.set_dest_address(target, LanProtocol.DISCOVERY_PORT)
				socket.put_packet(probe)
		# Rooms only expire while probing; once the scan ends the last list stays for the player to pick.
		var expired := false
		for key: String in rooms.keys():
			if now - float(rooms[key]["seen"]) > ROOM_TTL:
				rooms.erase(key)
				expired = true
		if expired: found.emit(rooms.values())
		if now >= _until:
			scanning = false
			scanning_changed.emit(false)
	var budget := 16
	while socket.get_available_packet_count() > 0 and budget > 0:
		budget -= 1
		var packet := socket.get_packet()
		var sender := socket.get_packet_ip()
		var port := socket.get_packet_port()
		var data := LanProtocol.decode(packet, 1200)
		if data.get("wdfz") != LanProtocol.VERSION: continue
		if not advertisement.is_empty():
			if not _may_reply(sender, now): continue
			socket.set_dest_address(sender, port)
			var info := advertisement.duplicate()
			info["wdfz"] = LanProtocol.VERSION
			socket.put_packet(LanProtocol.encode(info))
		else:
			_remember(data, sender, now)


func _may_reply(sender: String, now: float) -> bool:
	if now - _reply_window >= 1.0:
		_replies.clear()
		_reply_window = now
	if not _replies.has(sender) and _replies.size() >= SENDER_BUDGET: return false
	_replies[sender] = int(_replies.get(sender, 0)) + 1
	return int(_replies[sender]) <= REPLY_BUDGET


func _remember(data: Dictionary, sender: String, now: float) -> void:
	if not data.get("name") is String or String(data["name"]).length() > 32 or not SaveSchema.is_integer(data.get("port"), 1024, 65535): return
	if not SaveSchema.is_integer(data.get("count"), 0, 4) or data.get("phase") not in ["lobby", "loading", "playing", "ended"]: return
	var room_id: Variant = data.get("room")
	var valid_id := room_id is String and String(room_id).length() <= 32 and String(room_id).is_valid_hex_number()
	var key := "room:" + String(room_id) if valid_id else sender + ":" + str(int(data["port"]))
	if rooms.size() >= 64 and not rooms.has(key): return
	# The same room heard on loopback and on the LAN: keep the address other players can also use.
	if rooms.has(key) and sender.begins_with("127.") and not String(rooms[key]["ip"]).begins_with("127."):
		rooms[key]["seen"] = now
		return
	data["ip"] = sender
	data["seen"] = now
	rooms[key] = data
	found.emit(rooms.values())


func close() -> void:
	if socket != null: socket.close()
	socket = null
	advertisement.clear()
	rooms.clear()
	_replies.clear()
	found.emit([])
	_until = 0.0
	if scanning:
		scanning = false
		scanning_changed.emit(false)


func _exit_tree() -> void:
	close()
