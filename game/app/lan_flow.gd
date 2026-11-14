class_name LanFlow
extends Node
## Local presentation and device input only. All gameplay commands go to LanSession.
var app: GameApp
var network := LanSession.new()
var panel: LanPanel
var avatars: RemoteStudents
var current: Dictionary = {}
var _epoch := ""
var _scene := -1
var _input_seq := 0
var _input_timer := 0.0
var _seen_event := 0
var _shown_choice := -1
var _last_motion := -1
var _special_choice := ""
var _paused := false
var _lost := false
var _installed := false
var _death_t := 0.0
var _death_seen := false
var _ended_seen := false
var _last_connection: Dictionary = {}
var _team: Button
var _watch: Button
var _spectating := false
var _observing := ""
var _view_scene := -1
var prediction := LanPrediction.new()
var _mic: MicPanel
var _manual := false
var _time_prompt := ""
var _ending_prompt := ""
var _board_prompt := ""
var _recorded := false
var _pointer_inside := false
var remote := TerracottaSession.new()
var _remote_mode := false
var _remote_token := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().mouse_entered.connect(func() -> void: _pointer_inside = true)
	get_window().mouse_exited.connect(func() -> void: _pointer_inside = false)
	network.name = "Network"
	add_child(network)
	remote.name = "Terracotta"
	add_child(remote)
	panel = LanPanel.new()
	panel.name = "LanPanel"
	panel.visible = false
	panel.theme = GameUI.BASE_THEME
	app.ui.get_node("Root").add_child(panel)
	panel.host_requested.connect(_host)
	panel.join_requested.connect(_join)
	panel.ready_requested.connect(network.ready)
	panel.start_requested.connect(func() -> void:
		if _remote_mode and not remote.available: return
		var error := network.start()
		if error != "": panel.status.text = error)
	panel.close_requested.connect(func() -> void:
		if _lost: app.return_to_menu()
		elif playing(): resume()
		else: stop())
	panel.leave_requested.connect(func() -> void: app.return_to_menu())
	panel.discover_requested.connect(network.discovery.discover)
	panel.reconnect_requested.connect(reconnect)
	panel.pause_requested.connect(network.pause)
	panel.remove_requested.connect(network.remove)
	panel.configure_requested.connect(func(capacity: int, difficulty: String) -> void:
		if network.transport.serving and network.room != null and network.room.phase == "lobby":
			network.room.capacity = capacity
			network.room.difficulty = difficulty
			network._publish_room())
	panel.save_requested.connect(network.save)
	panel.ending_requested.connect(func() -> void:
		panel.hide()
		resume()
		send("ending_request"))
	panel.debug_requested.connect(func(action: String, fields: Dictionary) -> void: send(action, fields))
	panel.give_requested.connect(func(target: String, item: String) -> void: send("give", {"to": target, "item": item}))
	network.discovery.found.connect(panel.found)
	network.discovery.scanning_changed.connect(panel.scanning)
	network.room_changed.connect(_room_changed)
	network.snapshot_received.connect(_snapshot)
	network.motion_received.connect(_motion)
	network.notice.connect(func(text: String) -> void:
		app.ui.show_notice(text)
		if panel.visible: panel.status.text = text)
	network.closed.connect(func(reason: String) -> void:
		if _remote_mode: remote.stop()
		_lost = true
		app.player.enabled = false
		app.player.clear_input()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		panel.show_room({}, "", "")
		panel.show()
		panel.status.text = reason)
	var new_game := app.ui.find_child("NewGame", true, false) as Button
	if new_game != null:
		var button := Button.new()
		button.name = "LanCoop"
		button.text = "局域网合作 · 2–4 人"
		button.custom_minimum_size.y = 48
		button.pressed.connect(func() -> void: _open_mode(false))
		new_game.get_parent().add_child(button)
		var remote_button := Button.new()
		remote_button.name = "RemoteCoop"
		remote_button.text = "远程合作 · Terracotta"
		remote_button.custom_minimum_size.y = 48
		remote_button.pressed.connect(func() -> void: _open_mode(true))
		new_game.get_parent().add_child(remote_button)
	remote.status_changed.connect(func(text: String) -> void:
		panel.remote_status(text, remote.code if remote.available else "", remote.available))
	remote.connected.connect(func(target: String, code: String) -> void:
		panel.remote_status("远程通道已连接。", code, true)
		if target != "":
			var error := network.join(target, panel.nickname.text, _remote_token)
			if error != "":
				remote.stop()
				panel.status.text = error)
	remote.stopped.connect(func() -> void: panel.set_busy(false))
	remote.failed.connect(func(reason: String) -> void:
		if network.active(): network._lost(reason)
		else:
			panel.show_room({}, "", "")
			panel.status.text = reason)
	_team = Button.new()
	_team.text = "队伍"
	_team.position = Vector2(16, 64)
	_team.custom_minimum_size = Vector2(90, 44)
	_team.visible = false
	_team.pressed.connect(open)
	app.ui.hud.add_child(_team)
	_watch = Button.new()
	_watch.text = "观战存活队友"
	_watch.custom_minimum_size = Vector2(190, 52)
	_watch.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_watch.position = Vector2(-210, 20)
	_watch.visible = false
	_watch.pressed.connect(func() -> void:
		_spectating = true
		app.ui.hide_death()
		app._stop_death_cg()
		var ids := network.room.alive_ids()
		if not ids.is_empty(): send("spectate", {"target": ids[(ids.find(_observing) + 1) % ids.size()]})
		_watch.text = "切换观战队友")
	app.ui.get_node("Root").add_child(_watch)
	var file := FileAccess.open("user://cooperative/connection.json", FileAccess.READ)
	if file != null and file.get_length() < 2048:
		var data: Variant = JSON.parse_string(file.get_as_text())
		if data is Dictionary:
			_last_connection = data
			if data.get("mode", "lan") == "lan": panel.address.text = String(data.get("address", ""))
			panel.nickname.text = String(data.get("name", "同学"))


func active() -> bool:
	return network.active() or _installed or remote.phase != "idle"


func _open_mode(value: bool) -> void:
	if active() and value != _remote_mode:
		panel.status.text = "请先离开当前房间。"
		open()
		return
	_remote_mode = value
	panel.set_remote(value)
	if _last_connection.get("mode", "lan") == ("remote" if value else "lan"):
		panel.address.text = String(_last_connection.get("code" if value else "address", ""))
	open()


func _host(room_name: String, nick: String, port: int, restore: bool) -> void:
	if remote.phase != "idle":
		panel.status.text = "请等待远程连接关闭。"
		return
	var error := network.host(room_name, nick, port, restore)
	if error == "" and _remote_mode:
		panel.set_busy(true)
		error = remote.begin(true, nick, "", port)
		if error != "": network.stop()
	if error != "":
		panel.set_busy(false)
		panel.show_room({}, "", "")
		panel.status.text = error


func _join(target: String, nick: String) -> void:
	if _remote_mode:
		_remote_token = String(_last_connection.get("token", "")) if _last_connection.get("mode") == "remote" else ""
		panel.set_busy(true)
		var error := remote.begin(false, nick, target)
		if error != "":
			panel.set_busy(false)
			panel.status.text = error
	else:
		var error := network.join(target, nick)
		panel.status.text = error if error != "" else "正在连接，可随时离开取消。"


func playing() -> bool:
	return _installed and network.room != null


func open() -> void:
	if playing(): pause()
	panel.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	panel.refit.call_deferred()


func reconnect() -> void:
	if _last_connection.is_empty():
		panel.status.text = "没有原成员重连信息。请先加入一个房间。"
		return
	_epoch = ""
	_installed = false
	_lost = false
	if _last_connection.get("mode") == "remote":
		_remote_mode = true
		panel.set_remote(true)
		panel.nickname.text = String(_last_connection["name"])
		panel.address.text = String(_last_connection["code"])
		_join(String(_last_connection["code"]), String(_last_connection["name"]))
		return
	_remote_mode = false
	panel.set_remote(false)
	var error := network.join(String(_last_connection["address"]), String(_last_connection["name"]), String(_last_connection["token"]))
	panel.status.text = error if error != "" else "正在恢复原角色……"


func _addresses() -> String:
	var list: Array = []
	for address: String in IP.get_local_addresses():
		if address.contains(":") or address.begins_with("127.") or address.begins_with("169.254."): continue
		list.append("%s:%d" % [address, network.port])
	return " / ".join(list)


func _room_changed(state: Dictionary) -> void:
	panel.show_room(state, network.local_id, _addresses() if network.transport.serving else network.address)
	if not network.transport.serving and network.reconnect_token != "" and network.address != "":
		_last_connection = {"address": network.address, "name": network.nickname, "token": network.reconnect_token}
		if _remote_mode:
			_last_connection["mode"] = "remote"
			_last_connection["code"] = remote.code
			_last_connection.erase("address")
		DirAccess.make_dir_recursive_absolute("user://cooperative")
		var file := FileAccess.open("user://cooperative/connection.json", FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify(_last_connection))
	if state.get("phase") == "playing" and _installed and not _paused and not _lost:
		panel.hide()
		_sync_input()


func send(action: String, fields: Dictionary = {}) -> void:
	if not playing() or _lost: return
	fields["scene"] = _scene
	network.command(action, fields)


func choice(index: int) -> void:
	if _manual:
		_manual = false
		app.ui.hide_choice()
		match index:
			0: app._open_bag()
			1: app._show_notes("")
			2: app._show_map("")
			3: send("lesson")
			4: send("think")
		return
	if _special_choice != "":
		send(_special_choice, {"accept": index == 0})
		_special_choice = ""
	else: send("choice", {"index": index})
	app.ui.hide_choice()
	resume()


func pause() -> void:
	_paused = true
	app.player.enabled = false
	app.player.clear_input()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	app.ui.set_mode("pause")
	app.ui.pause_screen.description.text = ("远程合作" if _remote_mode else "局域网合作") + " · 世界继续运行\n个人菜单不会暂停队友；需要停下时，在「队伍」中发起全队暂停。"


func resume() -> void:
	_paused = false
	if not playing() or _lost: return
	panel.hide()
	app.ui.set_mode("play")
	_sync_input()
	app.player.clear_input()
	var capture := not app.ui.touch_enabled() and app.player.enabled
	# Wayland locks a pointer only after it has entered a focused surface.
	# Loading/reconnect can resume a background window; leave the cursor visible
	# until its next real click, which PlayerController already handles.
	if DisplayServer.get_name().to_lower() == "wayland":
		capture = capture and get_window().has_focus() and _pointer_inside
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE


func stop() -> void:
	remote.stop()
	network.stop()
	if is_instance_valid(avatars): avatars.queue_free()
	avatars = null
	_installed = false
	_epoch = ""
	_scene = -1
	_lost = false
	_paused = false
	current.clear()
	_seen_event = 0
	_shown_choice = -1
	_death_seen = false
	_ended_seen = false
	_last_motion = -1
	_view_scene = -1
	_spectating = false
	_observing = ""
	prediction.clear()
	_time_prompt = ""
	_ending_prompt = ""
	_board_prompt = ""
	_recorded = false
	if is_instance_valid(_mic): _mic.hide()
	if is_instance_valid(_watch): _watch.hide()
	if is_instance_valid(panel):
		panel.hide()
		panel.show_room({}, "", "")
	if is_instance_valid(_team): _team.hide()


func _snapshot(data: Dictionary) -> void:
	if not data.get("session") is Dictionary or network.room == null: return
	var view: Dictionary = data.get("observed", data) if _spectating else data
	_observing = String(view.get("id", "")) if _spectating else ""
	var source: Dictionary = view["session"]
	var first := _epoch != network.room.epoch or not _installed
	if first:
		var candidate := SessionFactory.create()
		(candidate.modules.get_module(&"school.day") as SchoolModule).assign_own_seat(String(view["seat"]))
		var why := candidate.validate(source, app.router.known_ids())
		if why != "":
			network._lost("房间状态无效：" + why)
			return
		candidate.restore(source)
		why = app.router.switch_to(String(source["world_id"]))
		if why != "":
			network._lost(why)
			return
		_installed = true
		_epoch = network.room.epoch
		_lost = false
		app._install_session(candidate, source["player"])
		if is_instance_valid(avatars): avatars.queue_free()
		avatars = RemoteStudents.new()
		avatars.name = "RemoteStudents"
		app.get_node("World").add_child(avatars)
		avatars.stepped.connect(_remote_step)
		_team.show()
		_seen_event = int(data.get("event_seq", 0))
		_shown_choice = -1
		_death_seen = false
		_ended_seen = false
		_last_motion = -1
		_input_seq = int(data.get("input_seq", 0)) + 1
		network._command_seq = int(data.get("command_seq", 0)) + 1
		loaded.call_deferred()
	else:
		app.session.modules.restore(source["modules"])
		app.session.clock.restore(source["clock"])
	current = data
	if network.room.phase == "ended" and not _recorded:
		_recorded = true
		var error := network.store.result(network.room.public_state(), network.local_id, data["life"])
		if not error.is_empty(): app.ui.show_notice(error)
	for key: String in view.get("runtime", {}):
		if not CooperativeActor.RUNTIME_FIELDS.has(key): continue
		var module := app.session.modules.get_module(StringName(key))
		for property: String in view["runtime"][key]:
			if property in CooperativeActor.RUNTIME_FIELDS[key]: module.set(property, view["runtime"][key][property])
	app.school().assign_own_seat(String(view["seat"]))
	app.campus().desk_taken = func(world: String, c: int, r: int) -> bool:
		var seat := "%s:%d:%d" % [world, c, r]
		for member: Dictionary in network.room.members.values():
			if member.get("seat") == seat: return false
		return app.classmates().occupied(world, c, r)
	var life: Dictionary = data["life"]
	app.story().dead = bool(life["dead"])
	app.story().ended = String(life["ended"])
	app.story().death_fx = String(life["fx"])
	app.story().death_msg = String(life["msg"])
	app.story().death_source = String(life["source"])
	app.story().wake_pending = bool(life["wake"])
	var phone := app.phone()
	phone.terminal_open = bool(data["terminal"])
	app.player.seated = app.school().seated
	app.player.hiding = bool(app.patrol().hide["on"])
	app.player.can_sprint = app.school().can_run(app.items().snack_active()) and app.body().can_run()
	app.player.speed_multiplier = (1.5 if app.items().snack_active() else 1.0) * app.body().speed_mul()
	_scene = int(data["scene"])
	var next_scene := int(view["scene"])
	if first or next_scene != _view_scene or app.session.world_id != source["world_id"]:
		_view_scene = next_scene
		prediction.clear()
		if app.session.world_id != source["world_id"]:
			app.router.switch_to(String(source["world_id"]))
			app.session.world_id = String(source["world_id"])
		app.player.restore_pose(source["player"])
		app._sync_world()
	if app.story().dead and not _death_seen:
		_death_seen = true
		_death_t = 0.0
		app.player.enabled = false
		app.player.clear_input()
		app.ui.hide_choice()
		app.ui.hide_bag()
		app.audio.death(app.story().death_fx)
		app._start_death_cg(DeathCG.resolve(app.story().death_source, app.story().death_fx))
	elif not app.story().dead and _death_seen:
		_death_seen = false
		app._stop_death_cg()
		app.ui.hide_death()
		resume()
	if app.story().ended != "" and not _ended_seen:
		_ended_seen = true
		app.player.enabled = false
		_watch.hide()
		app.ui.hide_death()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var card := RoutesModule.card(app.story().ended)
		app.ui.show_ending(String(card.get("title", card.get("t", "合作通关"))), "合作通关", card.get("lines", card.get("l", [])), "本局为局域网合作，个人记录与单人分开。", PackedStringArray(), "", app.story().ended)
	for event: Dictionary in data.get("events", []):
		if int(event["seq"]) <= _seen_event: continue
		_seen_event = int(event["seq"])
		_event(event)
	var choice_data: Dictionary = data.get("choice", {})
	if choice_data.is_empty() and _shown_choice >= 0:
		_shown_choice = -1
		if _special_choice.is_empty() and not _manual: app.ui.hide_choice()
	if not choice_data.is_empty() and int(choice_data.get("id", -1)) != _shown_choice:
		_shown_choice = int(choice_data["id"])
		app.ui.show_choice(String(choice_data.get("text", "请选择")), choice_data.get("labels", []), true)
		app.player.enabled = false
		app.player.clear_input()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if bool(data.get("terminal", false)):
		app.ui.show_terminal("\n".join(PackedStringArray(app.phone().puzzle["history"])), app.phone().status_text())
		app.player.enabled = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_update_offers()
	app._sync_world()
	if app.ui.bag_open(): app.ui.show_bag(app._bag_entries(), app.items().capacity())
	panel.inventory(app._bag_entries())
	_sync_input()
	if app.phone_open(): app._phone_paint()


func loaded() -> void:
	var epoch := _epoch
	# The first Vulkan frame can compile pipelines. Keep the shared loading
	# barrier until that local work has completed instead of starting the game.
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	if not _installed or network.room == null or network.room.epoch != epoch: return
	network.loaded()
	if network.room != null and network.room.phase == "playing": resume()


func _event(e: Dictionary) -> void:
	match e["kind"]:
		"notice", "wake": app.ui.show_notice(String(e.get("text", "")))
		"phone": app._open_phone()
		"mic": open_mic()


func _update_offers() -> void:
	if app.story().over(): return
	var offers: Array = [
		["ending_confirm", network.room.ending_offer, "队友已完成逃离条件。确认后一起离开校园？", ["确认逃离", "暂时留下"]],
		["time_confirm", current.get("time_offer", {}), "全队一起等待 %d 个游戏分钟？全员同意后才结算奖励与时间。" % int(current.get("time_offer", {}).get("minutes", 0)), ["同意等待", "继续探索"]],
		["board_confirm", current.get("boarding", {}), "确认上车后，一人驾驶，全队共同面对追逐。", ["确认上车", "暂不上车"]]]
	var live := false
	for offer: Array in offers:
		var info: Dictionary = offer[1]
		if offer[0] == _special_choice and not info.is_empty(): live = true
	if not _special_choice.is_empty() and not live:
		_special_choice = ""
		app.ui.hide_choice()
	if _manual or not current.get("choice", {}).is_empty() or app.ui.choice_open() or app.ui.terminal_open(): return
	for offer: Array in offers:
		var info: Dictionary = offer[1]
		if info.is_empty() or network.local_id in info.get("confirmed", []): continue
		var key := String(info.get("id", str(info.get("expires", ""))))
		var shown := _ending_prompt if offer[0] == "ending_confirm" else (_time_prompt if offer[0] == "time_confirm" else _board_prompt)
		if shown == key: continue
		if offer[0] == "ending_confirm": _ending_prompt = key
		elif offer[0] == "time_confirm": _time_prompt = key
		else: _board_prompt = key
		_special_choice = offer[0]
		app.ui.hide_bag()
		app._close_phone()
		app.ui.show_choice(offer[2], offer[3], false)
		app.player.enabled = false
		app.player.clear_input()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return


func _motion(data: Dictionary) -> void:
	if not playing() or data.get("epoch") != _epoch or int(data.get("tick", -1)) <= _last_motion: return
	_last_motion = int(data["tick"])
	if avatars != null: avatars.receive(data, _observing if _spectating else network.local_id, app.session.world_id, network.room.members)
	var own: Dictionary = data.get("players", {}).get(_observing if _spectating else network.local_id, {})
	if own.is_empty() or own["world"] != app.session.world_id or int(own["scene"]) != _view_scene or bool(current.get("vehicle", false)): return
	if _spectating:
		app.player.restore_pose(own["pose"])
		return
	var p: Array = own["pose"]["position"]
	var position := Vector3(p[0], p[1], p[2])
	prediction.reconcile(app.player, position, int(own["ack"]), app.player.enabled and not app.player.seated and not app.player.hiding)


func _remote_step(at: Vector3, running: bool) -> void:
	if not playing() or _lost or app.story().over() or network.room.paused_left > 0.0: return
	if at.distance_to(app.player.global_position) > 12.0: return
	var world := app.session.world_id
	var location := CampusGeometry.to_world(CampusData.rooms().get(world), at.x, at.z)
	var outdoor := CampusData.layout("out")
	var surface := AudioFx.surface(world, world == "bell1" and at.y > 0.4, location, outdoor.get("objects", []), float(outdoor.get("SC", 1.0)))
	# Player footsteps must not produce the patrol's threat captions.
	app.audio.step_on(surface, 0.8 if running else 0.55, {"pos": at, "self_step": true})


func _physics_process(dt: float) -> void:
	if not playing() or _lost: return
	_sync_input()
	var sampled_axis := Vector2.ZERO
	if app.player.enabled and not app.player.editing_text(): sampled_axis = (Input.get_vector("move_left", "move_right", "move_forward", "move_back") + app.ui.movement_touch()).limit_length()
	if not _spectating: prediction.record(_input_seq, sampled_axis, app.player.rotation.y, app.player.sprinting, app.player.speed_multiplier, dt)
	_input_timer += dt
	if _input_timer >= 1.0 / 30.0:
		_input_timer = fmod(_input_timer, 1.0 / 30.0)
		_input_seq += 1
		var axis := Vector2.ZERO
		var run := false
		if (app.player.enabled or bool(current.get("vehicle", false))) and not app.player.editing_text() and not _paused:
			axis = (Input.get_vector("move_left", "move_right", "move_forward", "move_back") + app.ui.movement_touch()).limit_length()
			run = Input.is_action_pressed("sprint") or app.player._touch_sprint
		network.input({"seq": _input_seq, "scene": _scene, "x": axis.x, "y": axis.y, "yaw": wrapf(app.player.rotation.y, -PI, PI), "pitch": app.player._look_pitch, "run": run})
	if app.player.enabled and not app.player.editing_text():
		if Input.is_action_just_pressed("bag"): app._open_bag()
		if Input.is_action_just_pressed("torch"): send("item", {"item": "torch"})
		for i in 2:
			if Input.is_action_just_pressed("hot_%d" % (i + 1)) and app.items().hot[i] != null: send("item", {"item": app.items().hot[i]})
		if Input.is_action_just_pressed("lift_close"): send("lift_close")
	_present(dt)
	if is_instance_valid(_mic) and _mic.visible:
		var radio := app.broadcast()
		radio.set_context(app._broadcast_context())
		var names: Array = []
		for id: String in radio.papers(): names.append([id, app.items().item_name(id)])
		_mic.paint(names, String(radio.b["selected"]), radio.paper_text(String(radio.b["selected"])) if radio.papers().has(String(radio.b["selected"])) else "请选择通知稿", "按住朗读，松开暂停", float(current.get("radio_live", {}).get("progress", 0)), radio.reading_seconds(), bool(current.get("radio_live", {}).get("held", false)), not radio.papers().is_empty())
	if bool(current.get("vehicle", false)) and app.garage().chase != null and not _spectating:
		if app._drive_view == null:
			app._drive_view = CarChaseView.new()
			app._drive_view.position = Vector3(0, 400, 0)
			app.add_child(app._drive_view)
			app._campus_world().hide()
		var chase: Dictionary = app.garage().chase
		app._drive_view.update(chase)
		var eye := app._drive_view.position + CarChaseView.eye(chase)
		app.player.position = eye - Vector3(0, app.player.camera.position.y, 0)
		app.player.rotation.y = 0.0
		app.player.set_pitch(-0.04)
		app.ui.show_status("校外道路 · " + ("驾驶" if current.get("driver") == network.local_id else "乘客"), "速度 %d · 车况 %d/3 · %d%%" % [roundi(float(chase["speed"]) * 3.6), int(chase["hp"]), roundi(float(chase["distance"]) / CarChaseRules.DISTANCE * 100.0)], "", "")
	elif app._drive_view != null: app._leave_drive()


func _present(dt: float) -> void:
	var school := app.school()
	var world := app._campus_world()
	var pose := app.player.capture_pose()
	var room: Variant = app.campus().room(app.session.world_id)
	app.patrol().set_context(app._patrol_context(room, pose))
	app.anomaly().set_context(app._anomaly_context(room, pose))
	app.ui.show_status(school.place_name(app.session.world_id, float(pose["position"][1])), school.period_text(false), school.period_class(false), school.clock_text(app.items().has_clock() or app.talent().has("watch")))
	app.ui.show_stamina(school.stam, school.stamina_max(), school.tired)
	app.ui.show_sprint_available(app.player.can_sprint)
	app.ui.show_runtime(app.session.clock.active_seconds)
	app.ui.show_search(float(current.get("search", {}).get("t", 0)) / InventoryModule.SEARCH_SECONDS)
	app.ui.show_hiding(app.player.hiding)
	app.player.camera.get_node("Torch").visible = app.items().torch_on
	var hot_names := [app.items().item_name(String(app.items().hot[0])) if app.items().hot[0] != null else "空", app.items().item_name(String(app.items().hot[1])) if app.items().hot[1] != null else "空"]
	app.ui.show_hot("1 · %s    2 · %s" % hot_names, app.items().hot, hot_names)
	app._refresh_interaction_prompt()
	app._show_classmates(app.classmates(), room, CampusGeometry.to_world(room, float(pose["position"][0]), float(pose["position"][2])), dt)
	app.broadcast().set_context(app._broadcast_context())
	app._show_crowd(app.broadcast())
	app._show_visit(app.exchange())
	app._show_marks()
	app._ground_step(app.items())
	app.ui.set_lift_close(app.elevator().show_close_button(app.session.world_id, pose))
	app._sensory_step(dt)
	app._audio_step(dt, app.patrol(), school, room, pose["position"])
	if world != null:
		world.set_player_scene(app.player.position)
		app.garage().set_context(app._garage_context())
		var shadow := app.session.world_id == GarageModule.ROOM and app.garage().roam_visible()
		var shadow_at := CampusGeometry.to_scene(room, Vector2(float(app.garage().roam["x"]), float(app.garage().roam["y"]))) if shadow else Vector2.ZERO
		world.show_garage_shadow(shadow, shadow_at, float(pose["position"][1]))
		world.show_silhouettes(school.inspection_points(), room, float(pose["position"][1]))
		world.update_lighting(dt, school.tsec, app.player.camera, app.patrol().flick, app.patrol().red, app.anomaly().blackout_now(), app.anomaly().overcast_target())
		if app.patrol().figure_visible():
			var pos := CampusGeometry.to_scene(room, Vector2(float(app.patrol().pat["x"]), float(app.patrol().pat["y"])))
			var look := app.patrol().look_point()
			var at := CampusGeometry.to_scene(room, Vector2(float(look["x"]), float(look["y"])))
			world.show_patrol(true, pos, float(app.patrol().pat["fy"]), Vector3(at.x, float(app.patrol().pat["fy"]), at.y))
		else: world.show_patrol(false, Vector2.ZERO, 0, Vector3.ZERO)
		world.show_portal(bool(app.facilities().portal["open"]), bool(app.facilities().portal["sketch"]))
		if world.anomaly_fx != null:
			var cam := app.player.camera.global_position
			var fwd := -app.player.camera.global_basis.z
			world.anomaly_fx.update(dt, app.anomaly().an, room, app.session.world_id, app.player.position, Vector2(fwd.x, fwd.z), cam, app.story().diff == "hard")
	if _death_seen and not _spectating and not _ended_seen:
		_death_t += dt
		if is_instance_valid(app._death_cg): app._death_cg.tick(dt)
		if _death_t >= StoryModule.duration(app.story().death_fx) and not app.story().wake_pending:
			app._stop_death_cg()
			app.ui.show_death_card(app.story().death_msg, app.story().epitaph(), app.story().cause(), PackedStringArray(), PackedStringArray(), "队友仍在继续；可从队伍窗口查看状态。", app.story().death_source)
			_watch.visible = not network.room.alive_ids().is_empty()
	if panel.visible:
		panel.metrics.text = "%s · RTT %.0f ms · 抖动 %.0f ms · 输入 %d · 确认帧 %d\n已发送 %.1f KiB / 接收 %.1f KiB · 校正误差 %.2f m" % ["房主" if network.transport.serving else "客机", network.rtt_ms, network.jitter_ms, _input_seq, _last_motion, network.transport.bytes_sent / 1024.0, network.transport.bytes_received / 1024.0, prediction.error_metres]
		if network.simulation != null: panel.metrics.text += "\n活动区域 %d · 巡察目标 %s · 待确认快照 %d" % [network.simulation.physics.zones.size(), network.simulation.patrol.target, network._awaiting.size()]
	_team.text = "队伍 %d/%d%s" % [network.room.members.size(), network.room.capacity, " · 全队暂停" if network.room.paused_left > 0 else ""]
	if _spectating: _team.text = "观战 · " + String(network.room.members.get(_observing, {}).get("name", "队友"))


func _sync_input() -> void:
	if not playing(): return
	var blocked: bool = _paused or _lost or _spectating or network.room.phase != "playing" or network.room.paused_left > 0 or app.story().over() or app.ui._mode != "play"
	blocked = blocked or app.ui.bag_open() or app.ui.choice_open() or app.ui.terminal_open() or app.phone_open() or not current.get("choice", {}).is_empty() or bool(current.get("terminal", false)) or bool(current.get("vehicle", false)) or app.body().fall != null
	for view: Control in [app.ui.map_panel, app.ui.notes_panel, _mic]:
		if is_instance_valid(view) and view.visible: blocked = true
	if blocked and app.player.enabled:
		app.player.clear_input()
		app.ui.clear_touch()
	app.player.enabled = not blocked


func manual() -> void:
	if not playing() or app.story().over(): return
	_manual = true
	app.player.clear_input()
	app.player.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	app.ui.show_choice("合作手册 · 世界继续运行", ["背包", "笔记", "地图", "课堂互动", "逃生思路"], false)


func open_mic() -> void:
	if not is_instance_valid(_mic):
		_mic = MicPanel.new()
		app.ui.get_node("Root").add_child(_mic)
		_mic.paper_selected.connect(func(id: String) -> void: send("mic", {"paper": id, "held": false}))
		_mic.hold_changed.connect(func(on: bool) -> void: send("mic", {"held": on}))
		_mic.closed.connect(func() -> void:
			send("mic", {"held": false})
			_mic.hide()
			resume())
	_mic.show()
	app.player.clear_input()
	app.player.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
