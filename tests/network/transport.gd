extends SceneTree
## Real UDP/ENet regressions; delayed replies must reach the original client socket.
var checks := 0
var failures := 0


class DropFirstSnapshotAck extends LanTransport:
	var dropped := false

	func send_control(id: int, data: Dictionary) -> void:
		if data.get("kind") == "state_ack" and not dropped:
			dropped = true
			return
		super.send_control(id, data)


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ", message)


func free_port() -> int:
	var socket := PacketPeerUDP.new()
	if socket.bind(0, "127.0.0.1") != OK: return 0
	var port := socket.get_local_port()
	socket.close()
	return port


func run() -> void:
	await delayed_join()
	await delayed_join(true)
	await reconnect_during_loading()
	await reload_in_playing_room()
	await input_bandwidth()
	await failed_join_diagnostics()
	print("LAN TRANSPORT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func delayed_join(reconnect: bool = false) -> void:
	var host := LanSession.new()
	var guest := LanSession.new()
	root.add_child(host)
	root.add_child(guest)
	var port := free_port()
	check(port > 0 and host.host("test", "host", port).is_empty(), "delayed-reply host listens")
	var token := ""
	if reconnect:
		token = "private-delayed-reconnect-token"
		host.room.add_member("returning", "guest", false)
		host.room.members["returning"]["connected"] = false
		host.credentials[token.sha256_text()] = "returning"
	var proxy := PacketPeerUDP.new()
	check(proxy.bind(0, "127.0.0.1") == OK, "UDP proxy listens")
	check(guest.join("127.0.0.1:%d" % proxy.get_local_port(), "guest", token).is_empty(), "start delayed join")
	var attempts := {}
	var queue: Array = []
	var client_port := 0
	var until := Time.get_ticks_msec() + 23000
	while guest.room == null and guest.connection_stage != "failed" and Time.get_ticks_msec() < until:
		while proxy.get_available_packet_count() > 0:
			var packet := proxy.get_packet()
			var sender := proxy.get_packet_port()
			var now := Time.get_ticks_msec()
			if sender != port:
				client_port = sender
				if not attempts.has(sender): attempts[sender] = now + 5100
				proxy.set_dest_address("127.0.0.1", port)
				proxy.put_packet(packet)
			elif client_port > 0:
				queue.append({"at": attempts[client_port], "port": client_port, "packet": packet})
		for i in range(queue.size() - 1, -1, -1):
			if Time.get_ticks_msec() >= int(queue[i].at):
				proxy.set_dest_address("127.0.0.1", int(queue[i].port))
				proxy.put_packet(queue[i].packet)
				queue.remove_at(i)
		await process_frame
	check(guest.room != null and guest.connection_stage == "joined", "join completes after the first host replies are delayed 5.1 seconds")
	check(attempts.size() == 1 and guest._attempts == 1, "connecting ENet keeps the same UDP socket and its retransmissions")
	if reconnect: check(guest.local_id == "returning", "delayed reconnect preserves the member and does not immediately replace the new connection")
	print("Delayed join: ", guest.connection_details())
	proxy.close()
	host.queue_free()
	guest.queue_free()
	await process_frame


func reconnect_during_loading() -> void:
	var host := LanSession.new()
	var original := LanSession.new()
	var replacement := LanSession.new()
	for session: LanSession in [host, original, replacement]: root.add_child(session)
	var port := free_port()
	var target := "127.0.0.1:%d" % port
	check(host.host("test", "host", port).is_empty() and original.join(target, "guest").is_empty(), "open the original ENet connection")
	var deadline := Time.get_ticks_msec() + 5000
	while original.room == null and Time.get_ticks_msec() < deadline: await process_frame
	check(original.room != null, "original guest owns a room seat")
	if original.room != null:
		host.room.phase = "loading"
		var member := original.local_id
		var old_peer := original.transport.api.get_unique_id()
		check(replacement.join(target, "guest", original.reconnect_token).is_empty(), "start restoring the same seat")
		deadline = Time.get_ticks_msec() + 5000
		while replacement.connection_stage != "reconnect_wait" and Time.get_ticks_msec() < deadline: await process_frame
		check(replacement.connection_stage == "reconnect_wait" and host.connections.has(old_peer), "a second connection waits without displacing the original player")
		if replacement.connection_stage == "reconnect_wait":
			var new_peer := replacement.transport.api.get_unique_id()
			var client_limit := replacement._hello_deadline
			var host_limit := float(host._peers_waiting[new_peer].until)
			check(client_limit - replacement._join_started >= LanSession.LOADING_HEARTBEAT_TIMEOUT and host_limit - float(host._peers_waiting[new_peer].start) >= LanSession.LOADING_HEARTBEAT_TIMEOUT, "both ends allow the old loading heartbeat to expire")
			await create_timer(1.3).timeout
			check(replacement._hello_deadline == client_limit and host._peers_waiting[new_peer].until == host_limit, "repeated wait messages cannot extend either deadline")
			host._peer_heard[old_peer] = Time.get_ticks_msec() / 1000.0 - LanSession.LOADING_HEARTBEAT_TIMEOUT - 1.0
			host._process(0)
			deadline = Time.get_ticks_msec() + 5000
			while replacement.room == null and Time.get_ticks_msec() < deadline: await process_frame
			check(replacement.room != null and replacement.local_id == member and replacement._hello_deadline == 0.0, "the waiting socket receives the original seat and finishes joining")
			check(host.connections.get(new_peer) == member and not host.connections.has(old_peer) and not host._peers_waiting.has(new_peer), "only the replacement owns the admitted member")
	for session: LanSession in [replacement, original, host]: session.queue_free()
	await process_frame


func reload_in_playing_room() -> void:
	var host := LanSession.new()
	var original := LanSession.new()
	var replacement := LanSession.new()
	host.store.path = "user://lan-transport-tests/%s/room.json" % Time.get_ticks_usec()
	var transport := DropFirstSnapshotAck.new()
	replacement.transport.free()
	replacement.transport = transport
	for session: LanSession in [host, original, replacement]: root.add_child(session)
	var received: Array[int] = []
	replacement.snapshot_received.connect(func(data: Dictionary) -> void: received.append(int(data["snapshot"])))

	var port := free_port()
	var target := "127.0.0.1:%d" % port
	check(host.host("test", "host", port).is_empty() and original.join(target, "guest").is_empty(), "open a room for the load-and-reconnect fixture")
	var deadline := Time.get_ticks_msec() + 5000
	while original.room == null and Time.get_ticks_msec() < deadline: await process_frame
	check(original.room != null, "the guest joins before campus loading")
	if original.room != null:
		var member := original.local_id
		var token := original.reconnect_token
		var old_peer := original.transport.api.get_unique_id()
		host.room.ready(member, true, "none")
		host.snapshot_received.connect(func(_data: Dictionary) -> void:
			if host.room.phase == "loading": host.loaded())
		original.snapshot_received.connect(func(_data: Dictionary) -> void:
			if original.room.phase == "loading": original.loaded())
		check(host.start().is_empty(), "start the room before reconnecting")
		deadline = Time.get_ticks_msec() + 9000
		while host.room.phase != "playing" and Time.get_ticks_msec() < deadline: await process_frame
		check(host.room.phase == "playing", "two initial players finish the loading barrier")
		original.stop()
		deadline = Time.get_ticks_msec() + 5000
		while host.connections.has(old_peer) and Time.get_ticks_msec() < deadline: await process_frame
		check(replacement.join(target, "guest", token).is_empty(), "original member rejoins the running room")
		deadline = Time.get_ticks_msec() + 5000
		while received.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
		check(not received.is_empty() and replacement.local_id == member, "reconnecting client gets its first campus snapshot")
		if not received.is_empty():
			var peer_id := replacement.transport.api.get_unique_id()
			var snapshot := received[0]
			check(transport.dropped and host._awaiting.get(peer_id, {}).get("snapshot") == snapshot, "host awaits the first snapshot confirmation")
			var now := Time.get_ticks_msec() / 1000.0
			var stale := now - LanSession.PLAYING_HEARTBEAT_TIMEOUT - 1.0
			host._peer_heard[peer_id] = stale
			replacement._last_heard = stale
			host._process(0.0)
			replacement._process(0.0)
			check(host.connections.has(peer_id) and replacement.transport.peer != null, "a reconnect still loading survives a silence longer than the gameplay interval")
			if host._awaiting.has(peer_id) and replacement.transport.peer != null:
				replacement.loaded()
				host._awaiting[peer_id]["at"] = now - 6.0
				host._send_state(peer_id, member)
				deadline = Time.get_ticks_msec() + 5000
				while host._awaiting.get(peer_id, {}).get("snapshot") == snapshot and Time.get_ticks_msec() < deadline: await process_frame
				check(host._awaiting.get(peer_id, {}).get("snapshot") != snapshot and received.count(snapshot) == 1, "a repeated snapshot confirms the lost acknowledgement without replaying state")
				check(not host._loading_peers.has(peer_id) and host._heartbeat_timeout(peer_id) == LanSession.PLAYING_HEARTBEAT_TIMEOUT and replacement._heartbeat_timeout() == LanSession.PLAYING_HEARTBEAT_TIMEOUT,
					"the ready acknowledgement restores the regular heartbeat on both sides")
	var path := host.store.path
	for session: LanSession in [replacement, original, host]:
		session.stop()
		session.queue_free()
	await process_frame
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	DirAccess.remove_absolute(path.get_base_dir())


func failed_join_diagnostics() -> void:
	# A real UDP listener that never replies: ENet emits packets, while the
	# application counters correctly stay zero. This is the screenshot's blind spot.
	var sink := PacketPeerUDP.new()
	check(sink.bind(0, "127.0.0.1") == OK, "silent endpoint listens")
	var target := "127.0.0.1:%d" % sink.get_local_port()
	var guest := LanSession.new()
	root.add_child(guest)
	check(guest.join(target, "guest", "private-reconnect-credential").is_empty(), "start silent join")
	await create_timer(0.8).timeout
	guest.transport.sample_network()
	var sent := guest.transport.wire_sent
	check(sent > 0 and guest.transport.packets_sent > 0 and guest.transport.bytes_sent == 0, "diagnostics distinguish UDP handshake traffic from game data")
	check(guest.transport.packets_received == 0 and guest._join_timeout_reason().contains("没有回包"), "silent endpoint reports missing game-port replies")
	guest._transport_closed("fixture transport failure")
	check(guest.transport.wire_sent == sent and guest.transport.peer == null, "closing a failed attempt preserves its traffic")
	guest._transport_retry_at = Time.get_ticks_msec() / 1000.0
	guest._process(0)
	check(guest._attempts == 2 and guest.transport.peer != null and guest.transport.wire_sent >= sent, "an actual transport failure retries without clearing cumulative traffic")
	await create_timer(0.2).timeout
	guest._hello_deadline = Time.get_ticks_msec() / 1000.0 - 0.01
	guest._process(0)
	var details := guest.connection_details()
	check(guest.connection_stage == "failed" and guest.transport.peer == null, "the total deadline still stops a silent join")
	check(details.contains(target) and details.contains("UDP 累计发送") and details.contains("本机 IPv4") and details.contains("版本"), "failed-join copy retains the endpoint, version and transport counters")
	check(guest.transport.wire_sent >= sent and not details.contains("private-reconnect-credential"), "final diagnostics retain every attempt without disclosing credentials")
	guest.stop()
	check(guest.transport.wire_sent == 0 and guest.transport.endpoint.is_empty(), "a separate session starts with fresh diagnostics")
	sink.close()
	guest.queue_free()
	await process_frame


func input_bandwidth() -> void:
	var host := LanTransport.new()
	var guest := LanTransport.new()
	root.add_child(host)
	root.add_child(guest)
	var port := free_port()
	check(host.host(port).is_empty() and guest.join("127.0.0.1", port).is_empty(), "bandwidth peers start")
	var until := Time.get_ticks_msec() + 3000
	while not guest.can_send(1) and Time.get_ticks_msec() < until: await process_frame
	check(guest.can_send(1), "bandwidth peers connect")
	if guest.can_send(1):
		var received := [0]
		host.input_received.connect(func(_id: int, _data: Dictionary) -> void: received[0] += 1)
		for i in 150:
			guest.send_input({"seq": i, "padding": "x".repeat(200)})
			await create_timer(0.02).timeout
		var limit := guest.peer.get_peer(1).get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE_LIMIT)
		print("Input delivery: %d/150, ENet throttle limit %d/32" % [received[0], limit])
		check(limit == 32 and received[0] >= 145, "ordinary input traffic is not throttled by an accidental 7-byte bandwidth limit")
	host.queue_free()
	guest.queue_free()
	await process_frame
