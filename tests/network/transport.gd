extends SceneTree
## Real UDP/ENet regressions; delayed replies must reach the original client socket.
var checks := 0
var failures := 0


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
