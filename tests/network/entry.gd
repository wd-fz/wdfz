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
	print("CASE: LAN room discovery and touch controls")
	await interface_checks()
	print("CASE: LAN setup before readiness")
	await setup_checks()
	print("CASE: LAN team controls")
	await team_experience_checks()
	print("CASE: LAN handshake")
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
		# Fallback font metrics can center the panel on a half pixel, while
		# ScrollContainer offsets are integers. Allow one raster pixel, not a
		# partially hidden button; include both rectangles if this fails again.
		var viewport := panel._scroll.get_global_rect()
		var button_rect := copy.get_global_rect()
		check(viewport.grow(1.0).encloses(button_rect), "copy diagnostic button remains reachable at %s: viewport=%s button=%s" % [size, viewport, button_rect])
	panel.queue_free()
	await frames()


func cast_picker_checks(panel: LanPanel, room: CooperativeRoom) -> void:
	root.size = Vector2i(720,360)
	panel.character_requested.connect(func(id: String) -> void:
		room.select_character("a",id)
		panel.show_room(room.public_state(),"a",""))
	await frames(3)
	panel._scroll.ensure_control_visible(panel._choose_cast)
	await frames(3)
	await tap(panel._choose_cast)
	var picker := panel.cast_picker
	check(picker.is_visible_in_tree(), "a touch opens the actual lobby character picker")
	if not picker.visible: return
	for card: Button in picker.cards.values():
		check(root.get_visible_rect().encloses(card.get_global_rect()), "touch role card fits 720x360")
	check(root.get_visible_rect().encloses(picker.confirm.get_global_rect()), "confirm is always visible on a small landscape phone")
	await tap(picker.cards.qiao)
	await tap(picker._pose)
	check(picker.selected=="qiao" and picker.studio.action=="walk" and room.members.a.ready, "previewing a walking model preserves the reservation and readiness")
	var stage := picker.studio
	var start := stage.get_global_rect().get_center()
	var angle := stage._angle
	await finger(start,true)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = root.get_final_transform() * (start + Vector2(46,0))
	drag.relative = root.get_final_transform().basis_xform(Vector2(46,0))
	Input.parse_input_event(drag)
	await frames(2)
	await finger(start + Vector2(46,0),false)
	check(absf(stage._angle-angle)>.22, "dragging the live student turns the 3D model")
	await tap(picker._back)
	check(not picker.visible and picker.studio==null and room.members.a.character=="" and room.members.a.ready, "cancel releases the renderer without committing a choice")
	await tap(panel._choose_cast)
	await tap(picker.cards.shen)
	room.select_character("b","shen")
	panel.show_room(room.public_state(),"a","")
	check(picker.confirm.disabled and picker.selected=="shen", "a teammate reserving the previewed role live disables confirmation")
	await tap(picker.cards.xu)
	await tap(picker.confirm)
	check(room.members.a.character=="xu" and not room.members.a.ready and panel._member_labels.a.text.contains("许棠"), "confirm reserves a specific student, updates the roster and releases readiness")
	room.ready("a",true,"none")
	room.ready("b",true,"none")
	root.size = Vector2i(960,540)
	panel.show_room(room.public_state(),"a","")
	await frames(3)


func setup_checks() -> void:
	root.size = Vector2i(720, 360)
	var panel := LanPanel.new()
	panel.theme = UISkin.THEME
	root.add_child(panel)
	var room := CooperativeRoom.new()
	room.add_member("a", "房主", true)
	room.add_member("b", "队友")
	var requests: Array = []
	panel.ready_requested.connect(func(value: bool, gift: String) -> void: requests.append([value, gift]))
	panel.character_requested.connect(func(id: String) -> void:
		room.select_character("a", id)
		panel.show_room(room.public_state(), "a", ""))
	panel.show_room(room.public_state(), "a", "")
	await frames(6)
	await tap(panel.ready_button)
	check(panel.cast_picker.visible and requests.is_empty(), "ready prompts for a character without notifying the host")
	await tap(panel.cast_picker.cards.qiao)
	await tap(panel.cast_picker.confirm)
	await tap(panel.ready_button)
	check(not room.members.a.character.is_empty() and not panel.ready_button.button_pressed and requests.is_empty(), "a reserved character still requires an explicit talent choice")
	panel.talent.select(2)
	panel.talent.item_selected.emit(2)
	panel.show_room(room.public_state(), "a", "")
	await tap(panel.ready_button)
	var gift: String = TalentModule.KEYS[0]
	check(requests == [[false, gift], [true, gift]], "a room update arriving before the talent acknowledgment preserves the selected talent")
	panel.talent.select(1)
	panel.talent.item_selected.emit(1)
	await tap(panel.ready_button)
	check(requests.slice(2) == [[false, "none"], [true, "none"]], "an explicit no-talent choice also permits readiness")
	panel.queue_free()
	await frames()


func team_experience_checks() -> void:
	root.size = Vector2i(960, 540)
	var panel := LanPanel.new()
	panel.theme = UISkin.THEME
	root.add_child(panel)
	var room := CooperativeRoom.new()
	room.title = "好友校园"
	room.add_member("a", "房主", true)
	panel.show_connection_error("上次连接失败")
	panel.show_room(room.public_state(), "a", "192.168.1.2:24560")
	check(not panel._details.visible and not panel._retry.visible, "successful room entry folds old failure diagnostics and retry actions")
	check(panel.start_button.disabled and panel.start_button.text.contains("至少 2 人"), "one-member start explains how to proceed")
	room.add_member("b", "队友")
	room.ready("a", true, "none")
	panel.show_room(room.public_state(), "a", "")
	check(panel.start_button.disabled and panel.start_button.text.contains("1/2"), "missing readiness is visible before tapping start")
	room.ready("b", true, "none")
	panel.show_room(room.public_state(), "a", "")
	check(not panel.start_button.disabled and panel._heading.text.contains("好友校园"), "all-ready room shows its name and enables start")
	await cast_picker_checks(panel, room)
	var rows := panel.members.get_children()
	panel.feedback("合作进度已保存。")
	for i in 10: panel.show_room(room.public_state(), "a", "")
	check(panel.status.text == "合作进度已保存。" and panel.members.get_children() == rows, "baseline refresh preserves action feedback and row focus")
	panel.talent.select(2)
	panel.talent.item_selected.emit(2)
	check(not panel._talent_text.text.is_empty() and panel._talent_image.texture != null, "talent choice includes its picture, effect and tradeoff")
	room.begin("ui-experience")
	room.loaded("a")
	panel.show_room(room.public_state(), "a", "")
	check(panel.status.text.contains("1/2") and panel._member_labels.b.text.contains("正在准备"), "loading shows which teammate still needs to finish")
	room.loaded("b")
	panel.show_room(room.public_state(), "a", "")
	panel.inventory([{ "id": "key", "name": "钥匙" }, { "id": "pill", "name": "药片" }])
	panel.transfer.select(1)
	panel.inventory([{ "id": "coin", "name": "硬币" }, { "id": "key", "name": "钥匙" }, { "id": "pill", "name": "药片" }])
	check(panel.transfer.get_item_metadata(panel.transfer.selected) == "pill", "inventory update preserves the selected item instead of changing the gift")
	panel.show_team({"b": {"place": "教学楼一楼", "distance": 1.2, "can_give": false}})
	check(panel._gift_buttons.b.disabled and panel._gift_buttons.b.text.contains("开门"), "team menu explains obstructed handoff")
	panel.show_team({"b": {"place": "教学楼一楼", "distance": 1.2, "can_give": true}})
	check(not panel._gift_buttons.b.disabled and panel._member_labels.b.text.contains("教学楼一楼"), "nearby teammate displays place and enabled handoff")
	panel.inventory([])
	check(panel.transfer.disabled and panel._gift_buttons.b.disabled, "empty bag cannot submit a null or stale gift")
	room.pause("a", true)
	panel.show_room(room.public_state(), "a", "")
	check(panel._team_actions.get_node("PauseRow/PauseTeam").disabled and not panel._team_actions.get_node("PauseRow/ResumeTeam").disabled, "pause controls reflect the team pause state")
	var leave := [0]
	var removed: Array = []
	panel.leave_requested.connect(func() -> void: leave[0] += 1)
	panel.remove_requested.connect(func(id: String) -> void: removed.append(id))
	await frames(5)
	await tap(panel._leave)
	check(leave[0] == 0 and panel._confirm_box.visible and panel._confirm_text.text.contains("所有队友"), "one accidental touch cannot close the host room")
	for size: Vector2i in [Vector2i(960, 540), Vector2i(720, 360)]:
		root.size = size
		await frames(6)
		check(root.get_visible_rect().encloses(panel._confirm_button.get_global_rect()) and panel._confirm_button.get_global_rect().position.y >= panel._scroll.get_global_rect().end.y, "confirmation stays fixed below scrolling content at " + str(size))
		await capture("team-confirm-%dx%d" % [size.x, size.y])
	await tap(panel._back)
	check(leave[0] == 0 and not panel._confirm_box.visible, "confirmation cancel returns safely to the team")
	panel._ask_remove("b")
	await frames(4)
	await tap(panel._confirm_button)
	check(removed == ["b"] and leave[0] == 0, "confirmation removes only the named teammate")
	room.phase = "ended"
	panel.show_room(room.public_state(), "a", "")
	check(not panel.transfer.visible and not panel._team_actions.get_node("PauseRow").visible, "ended room has no active gameplay controls")
	check(panel._gift_buttons.is_empty() and panel._member_labels.a.text.contains("已结束"), "ended roster no longer offers item transfer or claims exploration")
	panel.set_remote(false)
	panel.show_room({}, "", "")
	panel.set_history(true, false, "192.168.1.2:24560")
	panel.select_page("join")
	var entry := {"room": "recent", "name": "好友校园", "ip": "192.168.1.2", "port": 24560, "count": 4, "capacity": 4, "phase": "playing", "content": panel._local_content}
	panel.found([entry])
	check(not panel.discovered.get_child(0).disabled and panel.discovered.get_child(0).text.contains("恢复原角色"), "remembered member can rejoin its full playing room from the list")
	entry.ip = "192.168.1.3"
	panel.found([entry])
	check(panel.discovered.get_child(0).disabled, "reconnect identity does not unlock somebody else's full room")
	panel.show_connection_error("连接中断")
	check(panel._retry.visible, "connection failure provides a direct original-character retry")
	panel.set_remote(true)
	check(not panel._details.visible and not panel._retry.visible, "switching connection mode folds the previous failure report")
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
	host._awaiting[17] = {"fixture": true}
	host.remove(String(first.id))
	check(not host.connections.has(17) and not host._awaiting.has(17) and not host._welcomes.has(17), "removed peer loses pending baseline retries and handshake replay")
	host.queue_free()
	guest.queue_free()
	await frames()


