extends SceneTree
## Touch input reaches the real room controls, including an update between press/release.
class RecordingTransport extends LanTransport:
	var sent: Array = []
	func send_control(id: int, data: Dictionary) -> void:
		sent.append({"peer": id, "data": data.duplicate(true)})

var checks := 0
var failures := 0
var screenshot_dir := ""


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshots="): screenshot_dir = arg.trim_prefix("--screenshots=")
	call_deferred("run")


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ", message)


func frames(count: int = 3) -> void:
	for i in count:
		await physics_frame
		await process_frame


func finger(at: Vector2, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = root.get_final_transform() * at
	event.pressed = down
	Input.parse_input_event(event)
	await frames(2)


func tap(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	await finger(at, true)
	await finger(at, false)


func capture(label: String) -> void:
	if screenshot_dir == "" or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	root.get_texture().get_image().save_png(screenshot_dir.path_join(label + ".png"))


func run() -> void:
	root.size = Vector2i(960, 540)
	root.content_scale_size = Vector2i.ZERO
	await interface_checks()
	await handshake_checks()
	print("LAN ENTRY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func interface_checks() -> void:
	var panel := LanPanel.new()
	panel.theme = UISkin.THEME
	root.add_child(panel)
	var joins := []
	var hosts := []
	var scans := [0]
	var cancels := [0]
	panel.join_requested.connect(func(target: String, nick: String) -> void: joins.append([target, nick]))
	panel.host_requested.connect(func(title: String, nick: String, port: int, restore: bool) -> void: hosts.append([title, nick, port, restore]))
	panel.discover_requested.connect(func() -> void: scans[0] += 1)
	panel.cancel_requested.connect(func() -> void: cancels[0] += 1)
	await frames(6)
	check(panel.find_children("*", "LineEdit", true, false).all(func(edit: LineEdit) -> bool: return not edit.is_visible_in_tree()), "entry page has no exposed input forms")
	check(root.get_visible_rect().encloses(panel._panel.get_global_rect()), "home fits landscape")
	await capture("home")
	await tap(panel.find_child("JoinPage", true, false) as Button)
	check(panel.page == "join" and scans[0] == 1, "one touch opens join and starts discovery automatically")
	var entry := {"room": "a123", "name": "好友的校园", "ip": "192.168.43.1", "port": 24560, "count": 1, "capacity": 4, "phase": "lobby", "content": panel._local_content}
	panel.scanning(true)
	panel.found([entry])
	await frames(4)
	await capture("nearby")
	var button: Button = panel.discovered.get_child(0)
	var at := button.get_global_rect().get_center()
	await finger(at, true)
	for i in 4:
		panel.found([entry])
		await frames(1)
	check(is_instance_valid(button) and panel.discovered.get_child(0) == button, "broadcast updates preserve the pressed room button")
	await finger(at, false)
	check(joins == [["192.168.43.1:24560", "同学"]], "touch release after discovery updates directly submits exactly one join")
	check(panel.busy and panel._progress.is_visible_in_tree() and not panel.host_form.visible, "joining has a progress state and hides duplicate actions")
	panel.request_join("192.168.43.1:24560")
	check(joins.size() == 1, "repeated join cannot replace a pending handshake")
	await tap(panel._back)
	check(cancels[0] == 1, "cancel stays reachable while connecting")
	panel.set_busy(false)
	var incompatible := entry.duplicate()
	incompatible.content = "0".repeat(64)
	panel.found([incompatible])
	check(panel.discovered.get_child(0).disabled, "incompatible rooms are identified before the RPC handshake")
	await tap(panel.discovered.get_child(0))
	check(joins.size() == 1, "incompatible room cannot send a join")
	var list := []
	for i in 12:
		var item := entry.duplicate()
		item.room = str(i)
		item.name = "校园 %d" % i
		list.append(item)
	panel.found(list)
	await frames(4)
	at = panel.discovered.get_child(0).get_global_rect().get_center()
	await finger(at, true)
	for i in 6:
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.position = root.get_final_transform() * (at - Vector2(0, (i + 1) * 18))
		drag.relative = root.get_final_transform().basis_xform(Vector2(0, -18))
		Input.parse_input_event(drag)
		await frames(1)
	await finger(at - Vector2(0, 108), false)
	check(joins.size() == 1 and panel._scroll.scroll_vertical > 50, "swiping a room list scrolls without joining")
	panel._scroll.stop_motion()
	panel.set_remote(true)
	panel.select_page("join")
	await frames(5)
	check(panel.address.is_visible_in_tree() and not panel.nickname.is_visible_in_tree() and not panel.port.is_visible_in_tree(), "remote join only asks for the invitation")
	check(not panel._search.is_visible_in_tree() and not panel._copy_code.is_visible_in_tree(), "remote join has neither LAN discovery nor an empty host invitation")
	await capture("remote-join")
	panel.set_remote(false)
	panel.select_page("create")
	await frames(4)
	check(not panel.nickname.is_visible_in_tree() and not panel.port.is_visible_in_tree(), "quick create uses sensible defaults without a form")
	await capture("create")
	await tap(panel.find_child("CreateRoom", true, false) as Button)
	check(hosts == [["同学的校园", "同学", LanProtocol.PORT, false]], "one touch creates a default room")
	var room := CooperativeRoom.new()
	for i in 4: room.add_member(str(i), "好友%d" % i, i == 0)
	room.ready("0", true, "none")
	panel.show_room(room.public_state(), "0", "192.168.43.1:24560")
	await frames(5)
	check(not panel.busy and panel.members.get_child_count() == 4, "lobby shows four members and ends pending state")
	check(not panel.metrics.is_visible_in_tree() and not panel.address_options.is_visible_in_tree(), "technical information is folded by default")
	for size: Vector2i in [Vector2i(960, 540), Vector2i(720, 360)]:
		root.size = size
		await frames(7)
		check(root.get_visible_rect().encloses(panel._panel.get_global_rect()), "lobby panel fits " + str(size))
		check(root.get_visible_rect().encloses(panel._back.get_global_rect()) and root.get_visible_rect().encloses(panel.start_button.get_global_rect()), "lobby primary actions remain reachable at " + str(size))
		await capture("lobby-%dx%d" % [size.x, size.y])
	panel.show_room({}, "", "")
	panel.connection_info.text = "目标 192.168.43.1:24560\n本机 IPv4：192.168.43.2\nUDP 累计发送 256 B / 5 包 · 接收 0 B / 0 包\n" + "1.0 join started\n".repeat(24)
	for size: Vector2i in [Vector2i(960, 540), Vector2i(720, 360)]:
		root.size = size
		panel.show_connection_error("连接超时，游戏端口没有回包。请保持房主在前台，并复制两端的连接诊断。")
		await frames(8)
		check(root.get_visible_rect().encloses(panel._panel.get_global_rect()) and panel._details.visible, "failure report fits the landscape panel with diagnostics open at " + str(size))
		check(panel.status.get_parent() == panel._scroll.get_child(0) and panel._scroll.get_global_rect().encloses(panel.status.get_global_rect()), "long failure status stays inside the scroll body at " + str(size))
		check(panel._back.get_global_rect().position.y >= panel._scroll.get_global_rect().end.y, "failure scroll content does not overlap fixed actions at " + str(size))
		await capture("failure-%dx%d" % [size.x, size.y])
		var copy := panel.find_child("CopyDiagnostics", true, false) as Button
		panel._scroll.ensure_control_visible(copy)
		await frames(5)
		check(panel._scroll.get_global_rect().encloses(copy.get_global_rect()), "copy diagnostic button remains reachable at " + str(size))
	panel.queue_free()
	await frames()


func handshake_checks() -> void:
	var socket := PacketPeerUDP.new()
	check(socket.bind(0, "127.0.0.1") == OK, "reserve test port")
	var port := socket.get_local_port()
	socket.close()
	var host := LanSession.new()
	host.transport.free()
	host.transport = RecordingTransport.new()
	root.add_child(host)
	check(host.host("test", "host", port).is_empty(), "IPv4 server listens")
	var hello := {"kind": "hello", "protocol": LanProtocol.VERSION, "rules": LanProtocol.RULES, "content": host._fingerprint, "name": "guest", "token": ""}
	host._accept(17, hello)
	var first: Dictionary = host._welcomes[17].duplicate()
	host._accept(17, hello)
	check(host.connections.size() == 2 and host.credentials.size() == 2, "retry hello does not allocate another student or credential")
	check(host.transport.sent[-2].data == first and host.transport.sent[-1].data.kind == "room", "retry hello replays the welcome and room acknowledgement")
	var wrong := hello.duplicate()
	wrong.content = "bad-version"
	host._accept(18, wrong)
	check(host.transport.sent[-1].data.kind == "reject" and not host.connections.has(18), "mismatched version gets an explicit refusal")
	var guest := LanSession.new()
	root.add_child(guest)
	guest._hello_deadline = Time.get_ticks_msec() / 1000.0 + 20.0
	guest._control(1, first)
	check(guest.connection_stage == "joining" and guest._hello_deadline > 0.0, "welcome alone does not finish entering a room")
	guest._receive_room(host.room.public_state())
	check(guest.connection_stage == "joined" and guest._hello_deadline == 0.0 and guest.room != null, "room receipt completes the handshake")
	guest._control(1, first)
	check(guest.connection_stage == "joined", "late welcome replay cannot return a joined player to the joining stage")
	check(not host.connection_details().contains(String(first.token)), "shareable diagnostics never expose reconnect credentials")
	host.queue_free()
	guest.queue_free()
	await frames()


