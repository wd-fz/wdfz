class_name LanSession
extends Node
## Room orchestration. Authentication, authority and presentation use separate boundaries.
signal room_changed(data: Dictionary)
signal snapshot_received(data: Dictionary)
signal motion_received(data: Dictionary)
signal notice(text: String)
signal closed(reason: String)
var transport := LanTransport.new()
var discovery := LanDiscovery.new()
var room: CooperativeRoom
var simulation: CooperativeSimulation
var local_id := ""
var reconnect_token := ""
var nickname := "同学"
var address := ""
var room_name := "好友的校园"
var port := LanProtocol.PORT
var connections: Dictionary = {}
var credentials: Dictionary = {}
var store := CooperativeStore.new()
var _chunks := LanChunks.new()
var _clock := 0.0
var _motion_timer := 0.0
var _state_timer := 0.0
var _command_seq := 0
var _snapshot_seq := 0
var _last_snapshot := -1
var _awaiting: Dictionary = {}
var _hello_deadline := 0.0
var _loading_deadline := 0.0
var _last_heard := 0.0
var _heartbeat := 0.0
var _queued_save := false
var _resume: Dictionary = {}
var _fingerprint := ""
var _peers_waiting: Dictionary = {}
var rtt_ms := 0.0
var jitter_ms := 0.0


func _ready() -> void:
	_clock = Time.get_ticks_msec() / 1000.0
	process_mode = Node.PROCESS_MODE_ALWAYS
	store.validator = CooperativeValidation.validate
	transport.name = "Transport"
	add_child(transport)
	add_child(discovery)
	transport.connected.connect(_hello)
	transport.disconnected.connect(_lost)
	transport.peer_left.connect(_peer_left)
	transport.control_received.connect(_control)
	transport.input_received.connect(_receive_input)
	transport.motion_received.connect(func(data: Dictionary) -> void:
		_last_heard = _clock
		if room != null and data.get("epoch") == room.epoch: motion_received.emit(data))
	transport.chunk_received.connect(_chunk)
	transport.api.peer_connected.connect(func(id: int) -> void:
		if transport.serving: _peers_waiting[id] = _clock + 10.0)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/lan_manifest.json"))
	_fingerprint = String(manifest["digest"])


func active() -> bool:
	return room != null or transport.peer != null


func host(name: String, who: String, requested_port: int, resume: bool = false) -> String:
	stop()
	_clock = Time.get_ticks_msec() / 1000.0
	if requested_port < 1024 or requested_port > 65535: return "端口应为 1024–65535。"
	port = requested_port
	nickname = who.strip_edges().left(24)
	room_name = name.strip_edges().left(32)
	var error := transport.host(port)
	if not error.is_empty(): return error
	room = CooperativeRoom.new()
	local_id = "p-" + LanProtocol.token().left(12)
	reconnect_token = LanProtocol.token()
	room.add_member(local_id, nickname, true)
	room.ready(local_id, true, "none")
	credentials = {reconnect_token.sha256_text(): local_id}
	if resume:
		var saved := store.read()
		if saved.has("error"):
			stop()
			return String(saved["error"])
		var why := CooperativeValidation.validate(saved["save"])
		if not why.is_empty():
			stop()
			return why
		_resume = saved["save"]
		var prior: Dictionary = _resume["room"]
		if prior["phase"] == "ended":
			stop()
			return "这个合作存档已经结算，请创建新房间。"
		local_id = String(prior["host"])
		room.host_id = local_id
		room.minimum_loaded = 1
		room.members = prior["members"].duplicate(true)
		room.difficulty = String(prior["difficulty"])
		for id: String in room.members:
			if room.members[id]["state"] == "departed": continue
			room.members[id].merge({"ready": id == local_id, "connected": id == local_id, "state": "lobby"}, true)
		credentials = saved["credentials"].duplicate()
		credentials[reconnect_token.sha256_text()] = local_id
	connections[1] = local_id
	var discovery_error := discovery.serve({"name": room_name, "port": port, "count": room.members.size(), "phase": "lobby"})
	if not discovery_error.is_empty(): notice.emit(discovery_error)
	_publish_room()
	return ""


func join(target: String, who: String, token: String = "") -> String:
	stop()
	_clock = Time.get_ticks_msec() / 1000.0
	var parsed := LanProtocol.address(target)
	if parsed.is_empty(): return "请输入有效 IPv4 地址，可加端口，例如 192.168.1.23:24560。"
	address = target.strip_edges()
	nickname = who.strip_edges().left(24)
	reconnect_token = token
	var error := transport.join(parsed["ip"], int(parsed["port"]))
	if error.is_empty():
		_hello_deadline = _clock + 12.0
		_last_heard = _clock
	return error


func _hello() -> void:
	transport.send_control(1, {"kind": "hello", "protocol": LanProtocol.VERSION, "rules": LanProtocol.RULES, "content": _fingerprint, "name": nickname, "token": reconnect_token})


func ready(value: bool, gift: String) -> void:
	_send({"kind": "ready", "ready": value, "talent": gift})


func start() -> String:
	if not transport.serving or room == null or not room.can_start(): return "请让本局需加入的成员全部连接并准备；新局至少需要两人。"
	if not room.begin(LanProtocol.token()): return "无法开始房间。"
	simulation = CooperativeSimulation.new()
	add_child(simulation)
	simulation.setup(room, int(Time.get_ticks_usec() % 2147483647))
	if not _resume.is_empty():
		simulation.restore(_resume)
		_resume.clear()
	simulation.checkpoint_requested.connect(func() -> void: _queued_save = true)
	_loading_deadline = _clock + 60.0
	_publish_room()
	_send_states(true)
	return ""


func loaded() -> void:
	if room != null: _send({"kind": "loaded", "epoch": room.epoch})


func command(action: String, fields: Dictionary = {}) -> void:
	if room == null: return
	_command_seq += 1
	var data := fields.duplicate()
	data.merge({"kind": "command", "epoch": room.epoch, "seq": _command_seq, "action": action}, true)
	_send(data)


func input(data: Dictionary) -> void:
	if room == null: return
	data["epoch"] = room.epoch
	if transport.serving:
		if simulation != null: simulation.input(local_id, data)
	else: transport.send_input(data)


func pause(value: bool) -> void:
	_send({"kind": "pause", "value": value})


func save() -> void:
	_send({"kind": "save"})


func remove(id: String) -> void:
	if not transport.serving or room == null or id == local_id: return
	room.remove(id)
	room.check_loaded()
	if simulation != null: simulation.departed(id)
	for peer_id: int in connections.keys():
		if connections[peer_id] == id:
			transport.send_control(peer_id, {"kind": "reject", "text": "房主已将你移出本局。"})
			connections.erase(peer_id)
	_publish_room()


func _send(data: Dictionary) -> void:
	if transport.serving: _control(1, data)
	elif transport.peer != null: transport.send_control(1, data)


func _control(peer_id: int, data: Dictionary) -> void:
	if not data.get("kind") is String: return
	if not transport.serving:
		_last_heard = _clock
		match data["kind"]:
			"welcome":
				local_id = String(data.get("id", ""))
				reconnect_token = String(data.get("token", ""))
				_hello_deadline = 0.0
			"room": _receive_room(data.get("room", {}))
			"reject": _lost(String(data.get("text", "连接被拒绝。")))
			"result":
				if not data.get("ok", false): notice.emit(String(data.get("error", "操作失败。")))
			"notice": notice.emit(String(data.get("text", "")))
			"pong":
				if SaveSchema.number_in(data.get("time"), 0, _clock):
					var sample := (_clock - float(data["time"])) * 1000.0
					jitter_ms = lerpf(jitter_ms, absf(sample - rtt_ms), 0.2)
					rtt_ms = sample
		return
	if data["kind"] == "hello":
		_accept(peer_id, data)
		return
	if not connections.has(peer_id) or room == null: return
	var id := String(connections[peer_id])
	match data["kind"]:
		"ready":
			if not data.get("talent") is String or not data.get("ready") is bool: return
			var gift := String(data.get("talent", "none"))
			if gift != "none" and not TalentModule.DEF.has(gift): return
			room.ready(id, bool(data.get("ready", false)), gift)
			_publish_room()
		"loaded":
			if data.get("epoch") != room.epoch: return
			room.loaded(id)
			if simulation != null and room.phase == "playing":
				for key: String in simulation.actors:
					if simulation.actor(key).fate().dead and not simulation.actor(key).fate().wake_pending: room.members[key]["state"] = "dead"
			_publish_room()
		"command":
			if simulation == null or not SaveSchema.is_integer(data.get("seq"), 0, 2147483647): return
			var result := simulation.command(id, data)
			result["kind"] = "result"
			result["seq"] = data["seq"]
			if peer_id == 1:
				if not result["ok"]: notice.emit(String(result.get("error", "操作失败。")))
			else: transport.send_control(peer_id, result)
		"pause":
			if not data.get("value") is bool: return
			if room.pause(id, bool(data.get("value", false))): _publish_room()
		"save":
			if id == room.host_id: _queued_save = true
		"state_ack":
			if _awaiting.has(peer_id) and data.get("snapshot") == _awaiting[peer_id]["snapshot"]: _awaiting.erase(peer_id)
		"ping":
			if peer_id != 1: transport.send_control(peer_id, {"kind": "pong", "time": data.get("time", 0)})


func _accept(peer_id: int, data: Dictionary) -> void:
	if room == null or connections.has(peer_id): return
	var error := ""
	if data.get("protocol") != LanProtocol.VERSION or data.get("rules") != LanProtocol.RULES or data.get("content") != _fingerprint: error = "游戏版本或玩法资源不兼容，请使用相同版本。"
	if not data.get("token", "") is String or not data.get("name", "") is String:
		transport.send_control(peer_id, {"kind": "reject", "text": "成员资料格式无效。"})
		return
	var token := String(data.get("token", "")).left(128)
	var id := String(credentials.get(token.sha256_text(), "")) if token != "" else ""
	if error.is_empty() and not id.is_empty():
		if room.phase == "lobby" and room.members.has(id) and room.members[id]["state"] != "departed" and not room.members[id]["connected"]:
			room.members[id]["connected"] = true
		elif not room.reconnect(id): error = "原角色已离队或已经连接。"
	elif error.is_empty():
		if not _resume.is_empty(): error = "这个存档只接受原成员重连。"
		else:
			id = "p-" + LanProtocol.token().left(12)
			error = room.add_member(id, String(data.get("name", "同学")))
			if error.is_empty():
				token = LanProtocol.token()
				credentials[token.sha256_text()] = id
	if not error.is_empty():
		transport.send_control(peer_id, {"kind": "reject", "text": error})
		return
	_peers_waiting.erase(peer_id)
	connections[peer_id] = id
	transport.send_control(peer_id, {"kind": "welcome", "id": id, "token": token})
	_publish_room()
	if simulation != null: _send_state(peer_id, id)


func _receive_input(peer_id: int, data: Dictionary) -> void:
	if simulation != null and connections.has(peer_id): simulation.input(connections[peer_id], data)


func _publish_room() -> void:
	if room == null: return
	room.revision += 1
	var state := room.public_state()
	for peer_id: int in connections:
		if peer_id != 1: transport.send_control(peer_id, {"kind": "room", "room": state})
	if not discovery.advertisement.is_empty():
		discovery.advertisement["count"] = room.members.size()
		discovery.advertisement["phase"] = room.phase
	# Local listeners can start/load/leave synchronously; publish the current state
	# to the transport first so reentrant notifications cannot send stale lobbies.
	room_changed.emit(state)


func _receive_room(state: Dictionary) -> void:
	if not state.get("members") is Dictionary or not state.get("phase") is String: return
	if room == null: room = CooperativeRoom.new()
	if state.get("epoch") == room.epoch:
		if int(state.get("revision", 0)) < room.revision: return
		if int(state.get("revision", 0)) == room.revision and int(state.get("tick", 0)) < room.tick: return
	room.revision = int(state.get("revision", 0))
	room.tick = int(state.get("tick", 0))
	room.epoch = String(state.get("epoch", ""))
	room.phase = String(state["phase"])
	room.members = state["members"].duplicate(true)
	room.host_id = String(state.get("host", ""))
	room.capacity = int(state.get("capacity", 4))
	room.difficulty = String(state.get("difficulty", "easy"))
	room.paused_left = float(state.get("paused", 0))
	room.ending = String(state.get("ending", ""))
	room.ending_offer = state.get("offer", {}).duplicate(true)
	room.debug_run = bool(state.get("debug", false))
	room_changed.emit(state)


func _send_state(peer_id: int, id: String) -> void:
	if simulation == null: return
	var first_sent := _clock
	if peer_id != 1 and _awaiting.has(peer_id):
		first_sent = float(_awaiting[peer_id]["started"])
		if _clock - first_sent > 60.0:
			transport.peer.disconnect_peer(peer_id)
			return
		if _clock - float(_awaiting[peer_id]["at"]) >= 5.0:
			# Retransmit the same transaction. Replacing its ID while a slow client
			# builds a scene would invalidate its eventual acknowledgement forever.
			_awaiting[peer_id]["at"] = _clock
			for fragment: Dictionary in _awaiting[peer_id]["chunks"]: transport.send_chunk(peer_id, fragment)
		return
	var data := simulation.state_for(id)
	_snapshot_seq += 1
	data["snapshot"] = _snapshot_seq
	if peer_id == 1:
		snapshot_received.emit(data)
		return
	var chunks := LanChunks.split(data, "%s:%d" % [room.epoch, _snapshot_seq])
	if chunks.is_empty():
		transport.send_control(peer_id, {"kind": "reject", "text": "合作状态超过同步限制，请恢复最近检查点。"})
		return
	_awaiting[peer_id] = {"at": _clock, "started": first_sent, "snapshot": _snapshot_seq, "chunks": chunks}
	for chunk: Dictionary in chunks: transport.send_chunk(peer_id, chunk)


func _send_states(force: bool = false) -> void:
	if force: _awaiting.clear()
	for peer_id: int in connections: _send_state(peer_id, connections[peer_id])


func _chunk(_peer_id: int, packet: Dictionary) -> void:
	_last_heard = _clock
	var data := _chunks.accept(packet, _clock)
	if data.is_empty() or not data.get("room") is Dictionary or not data.get("session") is Dictionary: return
	if int(data.get("snapshot", -1)) <= _last_snapshot: return
	if room == null or data["room"].get("epoch") != room.epoch: return
	_last_snapshot = int(data["snapshot"])
	transport.send_control(1, {"kind": "state_ack", "snapshot": _last_snapshot})
	_receive_room(data["room"])
	snapshot_received.emit(data)


func _peer_left(peer_id: int) -> void:
	_peers_waiting.erase(peer_id)
	if not transport.serving or room == null or not connections.has(peer_id): return
	var id := String(connections[peer_id])
	connections.erase(peer_id)
	_awaiting.erase(peer_id)
	room.disconnect_member(id)
	if simulation != null: simulation.disconnect_member(id)
	_publish_room()


func _physics_process(dt: float) -> void:
	if transport.serving and simulation != null: simulation.tick(dt)


func _process(dt: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var wall_dt := maxf(0.0, now - _clock)
	_clock = now
	if transport.peer == null: return
	if not transport.serving:
		var timeout := 60.0 if room != null and room.phase == "loading" else 12.0
		if (_hello_deadline > 0.0 and _clock > _hello_deadline) or (_hello_deadline == 0.0 and _clock - _last_heard > timeout):
			_lost("房主没有响应。检查网络后可重连原角色。")
			return
		_heartbeat += wall_dt
		if _heartbeat >= 2.0:
			_heartbeat = 0.0
			transport.send_control(1, {"kind": "ping", "time": _clock})
		return
	if room == null: return
	for peer_id: int in _peers_waiting.keys():
		if _clock >= float(_peers_waiting[peer_id]):
			transport.peer.disconnect_peer(peer_id)
			_peers_waiting.erase(peer_id)
	var paused := room.paused_left > 0.0
	for id: String in room.elapsed(wall_dt):
		if simulation != null: simulation.departed(id)
		_publish_room()
	if paused and room.paused_left == 0.0: _publish_room()
	if room.phase == "loading" and _clock >= _loading_deadline:
		notice.emit("有成员尚未加载完成。可移除该成员或返回大厅重新开始。")
		_loading_deadline = _clock + 60.0
	if simulation != null:
		_motion_timer += dt
		_state_timer += dt
		if _motion_timer >= 0.05:
			_motion_timer = fmod(_motion_timer, 0.05)
			for peer_id: int in connections:
				var motion := simulation.motion(connections[peer_id])
				if peer_id == 1: motion_received.emit(motion)
				else: transport.send_motion(peer_id, motion)
		if _state_timer >= 0.2:
			_state_timer = 0.0
			_send_states()
		if _queued_save:
			_queued_save = false
			var error := store.write(simulation.capture(), credentials)
			if not error.is_empty(): notice.emit(error)


func _lost(reason: String) -> void:
	transport.close()
	closed.emit(reason)


func stop() -> void:
	if simulation != null and is_instance_valid(simulation):
		if room != null and room.phase in ["playing", "ended"]: store.write(simulation.capture(), credentials)
		simulation.queue_free()
	simulation = null
	transport.close()
	discovery.close()
	room = null
	connections.clear()
	credentials.clear()
	_awaiting.clear()
	_chunks.clear()
	_resume.clear()
	local_id = ""
	_command_seq = 0
	_last_snapshot = -1
	_hello_deadline = 0.0
	_queued_save = false
	_peers_waiting.clear()
	_heartbeat = 0.0


func _exit_tree() -> void:
	stop()
