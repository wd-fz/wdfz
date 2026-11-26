class_name LanSession
extends Node
## Room orchestration. Authentication, authority and presentation use separate boundaries.
signal room_changed(data: Dictionary)
signal snapshot_received(data: Dictionary)
signal motion_received(data: Dictionary)
signal notice(text: String)
signal closed(reason: String)
signal connection_changed(text: String)

const JOIN_TIMEOUT := 20.0
const PLAYING_HEARTBEAT_TIMEOUT := 12.0
const LOADING_HEARTBEAT_TIMEOUT := 60.0

var transport := LanTransport.new()
var discovery := LanDiscovery.new()
var route := LanNetworkRoute.new()
var direct_lan := true
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
var _loaded_epoch := ""
var _loading_peers: Dictionary = {}
var _join_started := 0.0
var _hello_deadline := 0.0
var _loading_deadline := 0.0
var _last_heard := 0.0
var _heartbeat := 0.0
var _queued_save := false
var _manual_save := false
var _resume: Dictionary = {}
var _fingerprint := ""
var _peers_waiting: Dictionary = {}
var _peer_heard: Dictionary = {}
var _hello_again_at := 0.0
var _transport_retry_at := 0.0
var rtt_ms := 0.0
var jitter_ms := 0.0
var connection_stage := "idle"
var _welcomes: Dictionary = {}
var _trace: PackedStringArray = []
var _attempts := 0


func _ready() -> void:
	_clock = Time.get_ticks_msec() / 1000.0
	process_mode = Node.PROCESS_MODE_ALWAYS
	store.validator = CooperativeValidation.validate
	transport.name = "Transport"
	add_child(transport)
	add_child(discovery)
	add_child(route)
	route.unavailable.connect(func(reason: String) -> void:
		discovery.close()
		if active(): _lost(reason)
		else:
			route.release()
			notice.emit(reason))
	transport.connected.connect(_hello)
	transport.disconnected.connect(_transport_closed)
	transport.peer_left.connect(_peer_left)
	transport.control_received.connect(_control)
	transport.input_received.connect(_receive_input)
	transport.motion_received.connect(func(data: Dictionary) -> void:
		_last_heard = Time.get_ticks_msec() / 1000.0
		if room != null and data.get("epoch") == room.epoch: motion_received.emit(data))
	transport.chunk_received.connect(_chunk)
	transport.api.peer_connected.connect(func(id: int) -> void:
		_trace_event("ENet peer connected")
		if transport.serving:
			var now := Time.get_ticks_msec() / 1000.0
			_peers_waiting[id] = {"start": now, "until": now + JOIN_TIMEOUT})
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/lan_manifest.json"))
	_fingerprint = String(manifest["digest"])


func active() -> bool:
	return room != null or transport.peer != null


func host(name: String, who: String, requested_port: int, resume: bool = false) -> String:
	var stop_error := stop()
	if not stop_error.is_empty(): return stop_error
	_clock = Time.get_ticks_msec() / 1000.0
	if requested_port < 1024 or requested_port > 65535: return "端口应为 1024–65535。"
	port = requested_port
	nickname = who.strip_edges().left(24)
	room_name = name.strip_edges().left(32)
	var error := _prepare_route()
	if not error.is_empty(): return error
	error = transport.host(port)
	if not error.is_empty(): route.release()
	if not error.is_empty(): return error
	room = CooperativeRoom.new()
	room.title = room_name if not room_name.is_empty() else "好友的校园"
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
		room.rules_dlc = bool(prior.get("rules_dlc", false))
		room.capacity = int(prior["capacity"])
		room.title = String(prior.get("title", room.title))
		for id: String in room.members:
			if room.members[id]["talent"] == "watch": room.members[id]["talent"] = "none"
			if room.members[id]["state"] == "departed": continue
			room.members[id].merge({"ready": id == local_id, "connected": id == local_id, "state": "lobby"}, true)
		credentials = saved["credentials"].duplicate()
		credentials[reconnect_token.sha256_text()] = local_id
	connections[1] = local_id
	connection_stage = "hosting"
	_trace_event("IPv4 host listening")
	var discovery_error := discovery.serve({"name": room.title, "port": port, "count": room.members.size(), "capacity": room.capacity, "phase": "lobby", "content": _fingerprint})
	if not discovery_error.is_empty(): notice.emit(discovery_error)
	_publish_room()
	return ""


func join(target: String, who: String, token: String = "") -> String:
	var stop_error := stop()
	if not stop_error.is_empty(): return stop_error
	_clock = Time.get_ticks_msec() / 1000.0
	var parsed := LanProtocol.address(target)
	if parsed.is_empty(): return "请输入有效 IPv4 地址，可加端口，例如 192.168.1.23:24560。"
	address = target.strip_edges()
	nickname = who.strip_edges().left(24)
	reconnect_token = token
	var error := _prepare_route(String(parsed["ip"]))
	if not error.is_empty(): return error
	error = transport.join(parsed["ip"], int(parsed["port"]))
	if not error.is_empty(): route.release()
	if error.is_empty():
		_attempts = 1
		connection_stage = "connecting"
		_trace_event("join started")
		connection_changed.emit("正在连接房主……")
		_join_started = _clock
		_hello_deadline = _join_started + JOIN_TIMEOUT
		_transport_retry_at = _clock + 4.0
		_last_heard = _clock
	return error


func _prepare_route(target: String = "") -> String:
	if not direct_lan: return route.release()
	var error := route.acquire(target)
	discovery.targets = route.broadcasts.duplicate()
	return error


func discover(preserve: bool = false) -> void:
	if not direct_lan or active(): return
	if preserve and discovery.socket != null and discovery.advertisement.is_empty():
		discovery.discover(true)
		return
	discovery.close()
	var error := route.release()
	if error.is_empty(): error = _prepare_route()
	if error.is_empty(): discovery.discover()
	else:
		discovery.scanning_changed.emit(false)
		notice.emit(error)


func _transport_closed(reason: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if not transport.serving and _hello_deadline > now:
		_trace_event("transport retry scheduled: " + reason)
		transport.close()
		_transport_retry_at = now + 1.0
		return
	_lost(reason)


func _hello() -> void:
	if transport.can_send(1) and connection_stage == "connecting":
		# A slow ENet connect has just proved the link alive. Give the room
		# handshake its own silence interval; repeated hellos cannot extend it.
		_last_heard = Time.get_ticks_msec() / 1000.0
		connection_stage = "handshake"
		_trace_event("sending room handshake")
		connection_changed.emit("已连接到房主，正在校验版本……")
	transport.send_control(1, {"kind": "hello", "protocol": LanProtocol.VERSION, "rules": LanProtocol.RULES, "content": _fingerprint, "name": nickname, "token": reconnect_token})
	if _hello_deadline > 0.0: _hello_again_at = Time.get_ticks_msec() / 1000.0 + 1.0


func ready(value: bool, gift: String) -> void:
	_send({"kind": "ready", "ready": value, "talent": gift})


func select_character(character: String) -> void:
	_send({"kind": "character", "character": character})


func start() -> String:
	if not transport.serving or room == null or not room.can_start(): return "请让本局需加入的成员全部连接并准备；新局至少需要两人。"
	if not room.begin(LanProtocol.token()): return "无法开始房间。"
	# Send the loading phase before the authority builds the school's collision.
	# That work can block polling longer than a lobby heartbeat allows.
	var starting_room := room
	_trace_event("room loading started")
	_publish_room()
	if room != starting_room or not transport.serving: return "房间已关闭。"
	transport.flush()
	simulation = CooperativeSimulation.new()
	add_child(simulation)
	simulation.setup(room, int(Time.get_ticks_usec() % 2147483647))
	if not _resume.is_empty():
		simulation.restore(_resume)
		_resume.clear()
	else:
		for student: CooperativeActor in simulation.active_actors(): student.entrance_exam().prepare()
	simulation.checkpoint_requested.connect(func() -> void: _queued_save = true)
	_loading_deadline = Time.get_ticks_msec() / 1000.0 + LOADING_HEARTBEAT_TIMEOUT
	_publish_room()
	_send_states(true)
	return ""


func loaded() -> void:
	if room == null or room.epoch.is_empty() or transport.peer == null: return
	if _loaded_epoch != room.epoch:
		_loaded_epoch = room.epoch
		# The local scene and its first frame can block polling. Start the
		# shorter in-game heartbeat interval after that work has finished.
		if not transport.serving: _last_heard = Time.get_ticks_msec() / 1000.0
		_trace_event("local campus ready")
	_send({"kind": "loaded", "epoch": room.epoch})


func is_ready() -> bool:
	return room != null and not room.epoch.is_empty() and _loaded_epoch == room.epoch


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
			_awaiting.erase(peer_id)
			_loading_peers.erase(peer_id)
			_welcomes.erase(peer_id)
	_publish_room()


func _send(data: Dictionary) -> void:
	if transport.serving: _control(1, data)
	elif transport.peer != null: transport.send_control(1, data)


func _control(peer_id: int, data: Dictionary) -> void:
	if not data.get("kind") is String: return
	if not transport.serving:
		# Multiplayer polls before _process. A world build or Vulkan pipeline
		# compilation may have blocked that frame; the cached clock is stale.
		_last_heard = Time.get_ticks_msec() / 1000.0
		match data["kind"]:
			"welcome":
				# A retry already in flight can arrive after the room. It must not
				# move an established player back to the joining UI/state.
				if _hello_deadline == 0.0 and room != null: return
				local_id = String(data.get("id", ""))
				reconnect_token = String(data.get("token", ""))
				connection_stage = "joining"
				_trace_event("welcome received")
				connection_changed.emit("版本校验通过，正在进入房间……")
			"reconnect_wait":
				if _hello_deadline > 0.0 and reconnect_token != "":
					# The first connection may still own the seat. Replays use the original
					# start time so a responsive occupied seat cannot keep us here forever.
					var old_link_timeout := LOADING_HEARTBEAT_TIMEOUT if is_same(data.get("loading"), true) else PLAYING_HEARTBEAT_TIMEOUT
					_hello_deadline = maxf(_hello_deadline, _join_started + JOIN_TIMEOUT + old_link_timeout)
					_hello_again_at = _last_heard + 1.0
					if connection_stage != "reconnect_wait":
						connection_stage = "reconnect_wait"
						notice.emit("正在等待原连接释放，随后恢复角色……")
			"room": _receive_room(data.get("room", {}))
			"reject": _lost(String(data.get("text", "连接被拒绝。")))
			"result":
				if not data.get("ok", false): notice.emit(String(data.get("error", "操作失败。")))
			"notice": notice.emit(String(data.get("text", "")))
			"pong":
				if SaveSchema.number_in(data.get("time"), 0, _last_heard):
					var sample := (_last_heard - float(data["time"])) * 1000.0
					jitter_ms = lerpf(jitter_ms, absf(sample - rtt_ms), 0.2) if rtt_ms > 0 else 0.0
					rtt_ms = sample
		return
	if data["kind"] == "hello":
		_accept(peer_id, data)
		return
	if not connections.has(peer_id) or room == null: return
	_peer_heard[peer_id] = Time.get_ticks_msec() / 1000.0
	var id := String(connections[peer_id])
	match data["kind"]:
		"ready":
			if not data.get("talent") is String or not data.get("ready") is bool: return
			var gift := String(data.get("talent", "none"))
			if gift != "none" and not TalentModule.DEF.has(gift): return
			room.ready(id, bool(data.get("ready", false)), gift)
			_publish_room()
		"character":
			if not data.get("character") is String: return
			var reason := room.select_character(id, data["character"])
			if reason.is_empty(): _publish_room()
			elif peer_id == 1: notice.emit(reason)
			else: transport.send_control(peer_id, {"kind": "notice", "text": reason})
		"loaded":
			if room.epoch.is_empty() or data.get("epoch") != room.epoch: return
			_loading_peers.erase(peer_id)
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
			if room.pause(id, bool(data.get("value", false))):
				if room.paused_left > 0.0 and simulation != null:
					for actor: CooperativeActor in simulation.actors.values(): actor.clear_input()
				_publish_room()
		"save":
			if id == room.host_id:
				_queued_save = true
				_manual_save = true
		"state_ack":
			if _awaiting.has(peer_id) and data.get("snapshot") == _awaiting[peer_id]["snapshot"]: _awaiting.erase(peer_id)
		"ping":
			if peer_id != 1: transport.send_control(peer_id, {"kind": "pong", "time": data.get("time", 0)})


func _accept(peer_id: int, data: Dictionary) -> void:
	if room == null: return
	if connections.has(peer_id):
		# A retried hello must replay the acknowledgement, not leave the guest
		# waiting forever if the first welcome/room was not queued successfully.
		if _welcomes.has(peer_id):
			transport.send_control(peer_id, _welcomes[peer_id])
			transport.send_control(peer_id, {"kind": "room", "room": room.public_state()})
		return
	_trace_event("room handshake received")
	var error := ""
	if data.get("protocol") != LanProtocol.VERSION or data.get("rules") != LanProtocol.RULES or data.get("content") != _fingerprint: error = "游戏版本或玩法资源不兼容，请使用相同版本。"
	if not data.get("token", "") is String or not data.get("name", "") is String:
		transport.send_control(peer_id, {"kind": "reject", "text": "成员资料格式无效。"})
		return
	var token := String(data.get("token", "")).left(128)
	var id := String(credentials.get(token.sha256_text(), "")) if token != "" else ""
	if error.is_empty() and not id.is_empty():
		if room.members.has(id) and room.members[id]["connected"] and room.members[id]["state"] != "departed":
			# A tunnel can disappear before ENet's disconnect packet arrives. A
			# credential holder waits for heartbeat expiry; it cannot evict a live player.
			var old_peer: Variant = connections.find_key(id)
			var heartbeat_timeout := _heartbeat_timeout(int(old_peer) if old_peer != null else 0)
			var loading := heartbeat_timeout == LOADING_HEARTBEAT_TIMEOUT
			if _peers_waiting.has(peer_id):
				var pending: Dictionary = _peers_waiting[peer_id]
				var until := float(pending.start) + JOIN_TIMEOUT + heartbeat_timeout
				pending.until = maxf(float(pending.until), until)
			transport.send_control(peer_id, {"kind": "reconnect_wait", "loading": loading})
			return
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
		_trace_event("room handshake rejected: " + error)
		transport.send_control(peer_id, {"kind": "reject", "text": error})
		return
	_peers_waiting.erase(peer_id)
	connections[peer_id] = id
	_peer_heard[peer_id] = Time.get_ticks_msec() / 1000.0
	if simulation != null: _loading_peers[peer_id] = true
	_welcomes[peer_id] = {"kind": "welcome", "id": id, "token": token}
	transport.send_control(peer_id, _welcomes[peer_id])
	_trace_event("member admitted")
	_publish_room()
	if simulation != null: _send_state(peer_id, id)


func _receive_input(peer_id: int, data: Dictionary) -> void:
	if simulation != null and connections.has(peer_id):
		_peer_heard[peer_id] = Time.get_ticks_msec() / 1000.0
		simulation.input(connections[peer_id], data)


func _publish_room() -> void:
	if simulation != null: simulation.normalize_members()
	if room == null: return
	room.revision += 1
	var state := room.public_state()
	for peer_id: int in connections:
		if peer_id != 1: transport.send_control(peer_id, {"kind": "room", "room": state})
	if not discovery.advertisement.is_empty():
		discovery.advertisement["count"] = room.members.size()
		discovery.advertisement["phase"] = room.phase
		discovery.advertisement["capacity"] = room.capacity
	# Local listeners can start/load/leave synchronously; publish the current state
	# to the transport first so reentrant notifications cannot send stale lobbies.
	room_changed.emit(state)


func _receive_room(state: Dictionary) -> void:
	if not state.get("members") is Dictionary or not state.get("phase") is String: return
	if local_id == "" or not state["members"].has(local_id): return
	if _hello_deadline > 0.0:
		_hello_deadline = 0.0
		_hello_again_at = 0.0
		_transport_retry_at = 0.0
		connection_stage = "joined"
		_trace_event("room entered")
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
	room.title = String(state.get("title", "好友的校园"))
	room.minimum_loaded = int(state.get("minimum_loaded", 2))
	room.difficulty = String(state.get("difficulty", "easy"))
	room.rules_dlc = bool(state.get("rules_dlc", false))
	room.paused_left = float(state.get("paused", 0))
	room.ending = String(state.get("ending", ""))
	room.ending_offer = state.get("offer", {}).duplicate(true)
	room.debug_run = bool(state.get("debug", false))
	room_changed.emit(state)


func _send_state(peer_id: int, id: String) -> void:
	if simulation == null: return
	var now := Time.get_ticks_msec() / 1000.0
	if peer_id != 1 and _awaiting.has(peer_id):
		var pending: Dictionary = _awaiting[peer_id]
		if now - float(pending["started"]) > LOADING_HEARTBEAT_TIMEOUT:
			_trace_event("snapshot acknowledgement timed out")
			transport.peer.disconnect_peer(peer_id)
			return
		if now - float(pending["at"]) >= 5.0:
			# Retransmit the same transaction. Replacing its ID while a slow client
			# builds a scene would invalidate its eventual acknowledgement forever.
			pending["at"] = now
			for fragment: Dictionary in pending["chunks"]: transport.send_chunk(peer_id, fragment)
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
	now = Time.get_ticks_msec() / 1000.0
	_awaiting[peer_id] = {"at": now, "started": now, "snapshot": _snapshot_seq, "chunks": chunks}
	for chunk: Dictionary in chunks: transport.send_chunk(peer_id, chunk)


func _send_states(force: bool = false) -> void:
	if force: _awaiting.clear()
	for peer_id: int in connections: _send_state(peer_id, connections[peer_id])


func _chunk(_peer_id: int, packet: Dictionary) -> void:
	_last_heard = Time.get_ticks_msec() / 1000.0
	var data := _chunks.accept(packet, _last_heard)
	if data.is_empty() or not data.get("room") is Dictionary or not data.get("session") is Dictionary: return
	if room == null or data["room"].get("epoch") != room.epoch: return
	var snapshot := int(data.get("snapshot", -1))
	if snapshot < 0 or snapshot < _last_snapshot: return
	# A repeat can be the host retrying a lost acknowledgement. Acknowledge
	# it again without replaying the snapshot or its events.
	transport.send_control(1, {"kind": "state_ack", "snapshot": snapshot})
	if snapshot == _last_snapshot: return
	_last_snapshot = snapshot
	_receive_room(data["room"])
	snapshot_received.emit(data)
	# Synchronous scene installation is local work, not a silent host.
	_last_heard = Time.get_ticks_msec() / 1000.0


func _peer_left(peer_id: int) -> void:
	_welcomes.erase(peer_id)
	_peers_waiting.erase(peer_id)
	_peer_heard.erase(peer_id)
	_loading_peers.erase(peer_id)
	if not transport.serving or room == null or not connections.has(peer_id): return
	var id := String(connections[peer_id])
	connections.erase(peer_id)
	_awaiting.erase(peer_id)
	if room.phase == "lobby" and not _resume.is_empty() and room.members.has(id):
		# A restored room must keep the saved student available for its owner.
		room.members[id]["connected"] = false
		room.members[id]["ready"] = false
	else:
		room.disconnect_member(id)
		if room.phase == "lobby":
			# Fresh lobbies release the seat. Its obsolete token must not point
			# at a removed student and reject a later invitation-based join.
			for credential: String in credentials.keys():
				if credentials[credential] == id: credentials.erase(credential)
	if simulation != null: simulation.disconnect_member(id)
	_publish_room()


func _physics_process(dt: float) -> void:
	if transport.serving and simulation != null: simulation.tick(dt)


func _heartbeat_timeout(peer_id: int = 0) -> float:
	if room != null:
		var local_loading := not transport.serving and not room.epoch.is_empty() and _loaded_epoch != room.epoch
		if room.phase == "loading" or local_loading or _loading_peers.has(peer_id):
			return LOADING_HEARTBEAT_TIMEOUT
	return PLAYING_HEARTBEAT_TIMEOUT


func _process(dt: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var wall_dt := maxf(0.0, now - _clock)
	_clock = now
	if not transport.serving and _hello_deadline > 0.0:
		if _clock > _hello_deadline:
			_lost(_join_timeout_reason())
			return
		# ENet retransmits CONNECT itself. Replacing a still-connecting socket
		# every four seconds discards delayed replies and can fill the host with
		# unfinished handshakes. Retry only a failed transport, or a *connected*
		# but silent old tunnel while restoring a member. Keep the total deadline.
		var state := transport.peer.get_connection_status() if transport.peer != null else MultiplayerPeer.CONNECTION_DISCONNECTED
		var retry := state == MultiplayerPeer.CONNECTION_DISCONNECTED or (state == MultiplayerPeer.CONNECTION_CONNECTED and reconnect_token != "" and _clock - _last_heard > 4.0)
		if _transport_retry_at > 0.0 and _clock >= _transport_retry_at and retry:
			_transport_retry_at = _clock + 4.0
			_attempts += 1
			_trace_event("retry transport")
			var target := LanProtocol.address(address)
			connection_stage = "connecting"
			var error := transport.join(String(target["ip"]), int(target["port"]), false)
			if not error.is_empty(): _trace_event(error)
	if transport.peer == null: return
	if not transport.serving:
		if (_hello_deadline > 0.0 and _clock > _hello_deadline) or (_hello_deadline == 0.0 and _clock - _last_heard > _heartbeat_timeout()):
			_lost("房主没有响应。检查网络后可重连原角色。")
			return
		if _hello_again_at > 0.0 and _clock >= _hello_again_at:
			_hello_again_at = 0.0
			_hello()
		_heartbeat += wall_dt
		if _heartbeat >= 2.0:
			_heartbeat = 0.0
			transport.send_control(1, {"kind": "ping", "time": _clock})
			if room != null and room.phase == "loading" and is_ready() and room.members.get(local_id, {}).get("state") == "loading":
				_send({"kind": "loaded", "epoch": room.epoch})
		return
	if room == null: return
	for peer_id: int in _peer_heard.keys():
		if peer_id == 1: continue
		var timeout := _heartbeat_timeout(peer_id)
		if _clock - float(_peer_heard[peer_id]) > timeout:
			_trace_event("peer heartbeat timed out (%s)" % ("loading" if timeout == LOADING_HEARTBEAT_TIMEOUT else "playing"))
			transport.expire_peer(peer_id)
			_peer_left(peer_id)
	for peer_id: int in _peers_waiting.keys():
		if _clock >= float(_peers_waiting[peer_id].until):
			transport.expire_peer(peer_id)
			_peers_waiting.erase(peer_id)
	var paused := room.paused_left > 0.0
	for id: String in room.elapsed(wall_dt):
		if simulation != null: simulation.departed(id)
		_publish_room()
	if paused and room.paused_left == 0.0: _publish_room()
	if room.phase == "loading" and _clock >= _loading_deadline:
		notice.emit("有成员尚未加载完成。可移除该成员或返回大厅重新开始。")
		_loading_deadline = _clock + LOADING_HEARTBEAT_TIMEOUT
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
			elif _manual_save: notice.emit("合作进度已保存。房主可从「继续上次合作」恢复，好友使用原角色重连。")
			_manual_save = false


func _lost(reason: String) -> void:
	connection_stage = "failed"
	_trace_event(reason)
	_hello_deadline = 0.0
	_hello_again_at = 0.0
	_transport_retry_at = 0.0
	transport.close()
	discovery.close()
	var release_error := route.release()
	if not release_error.is_empty(): _trace_event(release_error)
	closed.emit(reason)


func _join_timeout_reason() -> String:
	if connection_stage == "reconnect_wait":
		return "原角色的连接仍未释放，请稍后重试恢复。"
	if connection_stage in ["handshake", "joining"]:
		return "已连接到设备，但房间未确认加入。请确认双方版本一致，并让房主重建房间。"
	transport.sample_network()
	if transport.packets_sent == 0:
		return "连接超时，尚未记录到游戏连接数据包发出。请复制两端的连接诊断。"
	if transport.packets_received == 0:
		return "连接超时，游戏端口没有回包。请保持房主在前台，并复制两端的连接诊断。"
	return "已收到游戏端口回包，但连接握手未完成。请复制两端的连接诊断。"


func _trace_event(text: String) -> void:
	_trace.append("%.1f %s" % [Time.get_ticks_msec() / 1000.0, text])
	if _trace.size() > 24: _trace.remove_at(0)


func connection_details() -> String:
	# No invitation or member credential is included in shareable diagnostics.
	transport.sample_network()
	var addresses: PackedStringArray = []
	for ip: String in IP.get_local_addresses():
		if not ip.contains(":") and not ip.begins_with("127.") and not ip.begins_with("169.254."): addresses.append(ip)
	var lines: PackedStringArray = [
		"版本 %s · %s · Godot %s" % [ProjectSettings.get_setting("application/config/version", "?"), OS.get_name(), Engine.get_version_info().string],
		"协议 %d · 规则 %s · 内容 %s" % [LanProtocol.VERSION, LanProtocol.RULES, _fingerprint.left(12)],
		"阶段 %s · 尝试 %d · 已连接设备 %d · 待验证 %d" % [connection_stage, _attempts, transport.api.get_peers().size(), _peers_waiting.size()],
		"%s %s · 本地端口 %d" % ["监听" if transport.role == "host" else "目标", transport.endpoint, transport.local_port],
		"本机 IPv4：%s" % ", ".join(addresses),
		"ENet %s%s · 自动轮询 %s" % [transport.last_state, "（已关闭，保留最后状态）" if transport.peer == null else "", str(get_tree().multiplayer_poll)],
		"UDP 累计发送 %d B / %d 包 · 接收 %d B / %d 包（含握手）" % [transport.wire_sent, transport.packets_sent, transport.wire_received, transport.packets_received],
		"游戏数据累计发送 %d B / 接收 %d B" % [transport.bytes_sent, transport.bytes_received]]
	lines.append(route.details if direct_lan else "远程模式：使用系统／Terracotta 网络，不绑定本地 Wi-Fi")
	if room != null:
		lines.append("房间状态 %s · 本地校园 %s" % [room.phase, "就绪" if not room.epoch.is_empty() and _loaded_epoch == room.epoch else "未就绪"])
	if not transport.last_error.is_empty(): lines.append(transport.last_error)
	lines.append_array(_trace)
	return "\n".join(lines)


func stop() -> String:
	if simulation != null and is_instance_valid(simulation):
		if room != null and room.phase in ["playing", "ended"]: store.write(simulation.capture(), credentials)
		simulation.queue_free()
	simulation = null
	transport.close()
	transport.reset_diagnostics()
	discovery.close()
	var route_error := route.release()
	room = null
	connections.clear()
	_welcomes.clear()
	_trace.clear()
	_attempts = 0
	connection_stage = "idle"
	credentials.clear()
	_awaiting.clear()
	_loaded_epoch = ""
	_loading_peers.clear()
	_chunks.clear()
	_resume.clear()
	local_id = ""
	_command_seq = 0
	_last_snapshot = -1
	_join_started = 0.0
	_hello_deadline = 0.0
	_queued_save = false
	_manual_save = false
	rtt_ms = 0.0
	jitter_ms = 0.0
	_motion_timer = 0.0
	_state_timer = 0.0
	_peers_waiting.clear()
	_peer_heard.clear()
	_hello_again_at = 0.0
	_transport_retry_at = 0.0
	_heartbeat = 0.0
	return route_error


func _exit_tree() -> void:
	stop()
