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
var _host_ack := -1
var _input_window: Array = []
var _seen_event := 0
var _shown_choice := -1
var _last_motion := -1
var _special_choice := ""
var _game_id := ""
var _maze_fx: MazeFx
var _snake_direction := Vector2i.ZERO
var _special_id := ""
var _paused := false
var _lost := false
var _installed := false
var _preparing_epoch := ""
var _loading_snapshot: Dictionary = {}
var _death_t := 0.0
var _death_seen := false
var _ended_seen := false
var _last_connection: Dictionary = {}
var _team: Button
var _watch: Button
var _spectating := false
var _observing := ""
var _view_scene := -1
var _view_member := ""
var _watch_pose := {}
var _anchored: Variant = null
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
var _diagnostic_timer := 0.0
var history := CooperativeConnectionHistory.new()
var _room_phase := ""
var _display_addresses := ""
var _network_hint: Label
var _rescan_timer := 0.0
var _presented_frame := -1
var _presentation_elapsed := 0.0
var _frame_telemetry := DebugTelemetry.new()
var _last_play_frame_us := 0
var _longest_physics_ms := 0.0
var _longest_snapshot_us := 0
var _longest_gpu_ms := 0.0
var _measure_render_time := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().mouse_entered.connect(func() -> void: _pointer_inside = true)
	get_window().mouse_exited.connect(func() -> void: _pointer_inside = false)
	network.name = "Network"
	add_child(network)
	remote.name = "Terracotta"
	add_child(remote)
	panel = LanPanel.new()
	panel.refresh_diagnostics = _refresh_diagnostics
	panel.name = "LanPanel"
	panel.visible = false
	app.ui.get_node("Root").add_child(panel)
	panel.host_requested.connect(_host)
	panel.join_requested.connect(_join)
	panel.ready_requested.connect(network.ready)
	panel.character_requested.connect(network.select_character)
	panel.start_requested.connect(func() -> void:
		if _remote_mode and not remote.available: return
		var error := network.start()
		if error != "": panel.feedback(error))
	panel.close_requested.connect(func() -> void:
		if _lost: app.return_to_menu()
		elif playing(): resume()
		else: stop())
	panel.leave_requested.connect(func() -> void: app.return_to_menu())
	panel.discover_requested.connect(network.discover)
	panel.mode_requested.connect(_open_mode)
	panel.cancel_requested.connect(_cancel_connection)
	panel.reconnect_requested.connect(reconnect)
	panel.pause_requested.connect(network.pause)
	panel.remove_requested.connect(network.remove)
	panel.rules_requested.connect(func(enabled: bool) -> void:
		if network.room != null and network.transport.serving and network.room.phase == "lobby":
			network.room.rules_dlc = enabled
			network._publish_room())
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
	network.connection_changed.connect(func(text: String) -> void: panel.feedback(text, 0))
	network.snapshot_received.connect(_snapshot)
	network.motion_received.connect(_motion)
	network.notice.connect(func(text: String) -> void:
		app.ui.show_notice(text)
		if panel.visible: panel.feedback(text))
	network.closed.connect(func(reason: String) -> void:
		_cancel_preparation()
		if _remote_mode: remote.stop()
		_lost = true
		_reset_local_modals()
		app.player.enabled = false
		app.player.clear_input()
		app.ui.clear_touch()
		_watch.hide()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		panel.show_room({}, "", "")
		panel.set_busy(false)
		_refresh_history()
		panel.connection_info.text = network.connection_details()
		panel.show()
		panel.show_connection_error(reason))
	app.ui.menu_screen.add_coop_action(func() -> void: _open_mode(false))
	remote.status_changed.connect(func(text: String) -> void:
		panel.remote_status(text, remote.code if remote.available else "", remote.available))
	remote.connected.connect(func(target: String, code: String) -> void:
		panel.remote_status("远程通道已连接。", code, true)
		if target != "":
			var error := network.join(target, panel.nickname.text, _remote_token)
			if error != "":
				remote.stop()
				panel.feedback(error))
	remote.stopped.connect(func() -> void: panel.set_busy(false))
	remote.failed.connect(func(reason: String) -> void:
		if network.active(): network._lost(reason)
		else:
			panel.show_room({}, "", "")
			panel.show_connection_error(reason))
	_team = Button.new()
	_team.text = "队伍"
	_team.custom_minimum_size = Vector2(90, 48)
	_team.visible = false
	_team.pressed.connect(open)
	app.ui.add_hud_action(_team)
	_network_hint = Label.new()
	_network_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_network_hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_network_hint.offset_left = -20
	_network_hint.offset_right = -20
	_network_hint.offset_top = 72
	_network_hint.offset_bottom = 72
	_network_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_network_hint.theme_type_variation = "HudPill"
	_network_hint.add_theme_font_size_override("font_size", 14)
	_network_hint.add_theme_color_override("font_color", UISkin.MUTED)
	_network_hint.hide()
	app.ui.hud.add_child(_network_hint)
	_watch = Button.new()
	_watch.text = "观战存活队友"
	_watch.custom_minimum_size = Vector2(230, 52)
	_watch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_watch.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_watch.position = Vector2(-246, 80)
	_watch.visible = false
	_watch.pressed.connect(func() -> void:
		_spectating = true
		app.ui.hide_death()
		app._stop_death_cg()
		var ids := network.room.alive_ids()
		if not ids.is_empty(): send("spectate", {"target": ids[(ids.find(_observing) + 1) % ids.size()]})
		_watch.text = "切换观战队友")
	app.ui.get_node("Root").add_child(_watch)
	history.load_file()
	_last_connection = history.get_entry("lan")
	panel.address.text = String(_last_connection.get("address", ""))
	panel.nickname.text = String(_last_connection.get("name", "同学"))
	_refresh_history()


func active() -> bool:
	return network.active() or _installed or remote.phase != "idle"


func _open_mode(value: bool) -> void:
	if active() and not _lost:
		if value != _remote_mode: panel.feedback("请先离开当前房间。")
		open()
		return
	var route_error := network.stop()
	if not route_error.is_empty():
		panel.show_connection_error(route_error)
		open()
		return
	_remote_mode = value
	_display_addresses = ""
	_last_connection = history.get_entry("remote" if value else "lan")
	network.direct_lan = not value
	panel.set_remote(value)
	if _last_connection.get("mode", "lan") == ("remote" if value else "lan"):
		panel.address.text = String(_last_connection.get("code" if value else "address", ""))
		panel.nickname.text = String(_last_connection.get("name", panel.nickname.text))
	open()


func _host(room_name: String, nick: String, port: int, restore: bool) -> void:
	if remote.phase != "idle":
		panel.set_busy(false)
		panel.feedback("请等待远程连接关闭。")
		return
	_display_addresses = ""
	network.direct_lan = not _remote_mode
	var error := network.host(room_name, nick, port, restore)
	if error == "" and _remote_mode:
		panel.set_busy(true)
		error = remote.begin(true, nick, "", port)
		if error != "": network.stop()
	if error != "":
		panel.set_busy(false)
		panel.show_room({}, "", "")
		panel.show_connection_error(error)


func _join(target: String, nick: String) -> void:
	# A finger double tap or keyboard submit must not replace a live handshake.
	if _lost:
		network.stop()
		_installed = false
		_epoch = ""
	if network.active() or remote.phase != "idle": return
	_lost = false
	_display_addresses = ""
	panel.set_busy(true)
	network.direct_lan = not _remote_mode
	if _remote_mode:
		var route_error := network.route.release()
		if not route_error.is_empty():
			panel.set_busy(false)
			panel.show_connection_error(route_error)
			return
		_remote_token = String(_last_connection.get("token", "")) if _last_connection.get("mode") == "remote" and _last_connection.get("code") == target.strip_edges() else ""
		panel.set_busy(true)
		var error := remote.begin(false, nick, target)
		if error != "":
			panel.set_busy(false)
			panel.show_connection_error(error)
	else:
		var error := network.join(target, nick)
		if error != "":
			panel.set_busy(false)
			panel.show_connection_error(error)


func _cancel_connection() -> void:
	network.stop()
	remote.stop()
	_lost = false
	_display_addresses = ""
	panel.show_room({}, "", "")
	panel.set_busy(remote.phase != "idle")
	panel.feedback("已取消连接。" if remote.phase == "idle" else "正在关闭远程连接……")
	_refresh_history()


func _refresh_history() -> void:
	panel.set_history(not _last_connection.is_empty(), FileAccess.file_exists(network.store.path) or FileAccess.file_exists(network.store.path + ".bak"), String(_last_connection.get("address", "")))


func playing() -> bool:
	return _installed and network.room != null


func open() -> void:
	if playing(): pause()
	if network.room != null:
		panel.show_room(network.room.public_state(), network.local_id, _room_addresses())
	if playing():
		panel.inventory(app._bag_entries())
		panel.show_team(current.get("team", {}))
	panel.show()
	_refresh_history()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	panel.refit.call_deferred()


func reconnect() -> void:
	if _last_connection.is_empty():
		panel.feedback("没有原成员重连信息。请先加入一个房间。")
		return
	_epoch = ""
	_installed = false
	_cancel_preparation()
	_reset_local_modals()
	prediction.clear()
	_input_window.clear()
	_watch_pose.clear()
	_view_member = ""
	_view_scene = -1
	_display_addresses = ""
	_lost = false
	network.stop()
	if remote.phase != "idle":
		panel.feedback("远程连接正在关闭，请稍后再试。")
		return
	panel.show_room({}, "", "")
	if _last_connection.get("mode") == "remote":
		_remote_mode = true
		panel.set_remote(true)
		panel.nickname.text = String(_last_connection["name"])
		panel.address.text = String(_last_connection["code"])
		_join(String(_last_connection["code"]), String(_last_connection["name"]))
		return
	_remote_mode = false
	network.direct_lan = true
	panel.set_remote(false)
	panel.set_busy(true)
	var error := network.join(String(_last_connection["address"]), String(_last_connection["name"]), String(_last_connection["token"]))
	if error != "":
		panel.set_busy(false)
		panel.show_connection_error(error)
	else: panel.feedback("正在恢复原角色……", 0)


func _addresses() -> String:
	var list: Array = []
	var addresses := network.route.addresses if network.direct_lan and not network.route.addresses.is_empty() else IP.get_local_addresses()
	for address: String in addresses:
		if address.contains(":") or address.begins_with("127.") or address.begins_with("169.254."): continue
		list.append("%s:%d" % [address, network.port])
	return " / ".join(list)


func _room_addresses() -> String:
	if _display_addresses.is_empty(): _display_addresses = _addresses() if network.transport.serving else network.address
	return _display_addresses


func _room_changed(state: Dictionary) -> void:
	var phase := String(state.get("phase", ""))
	if panel.visible or phase != _room_phase or phase != "playing": panel.show_room(state, network.local_id, _room_addresses())
	_room_phase = phase
	if not network.transport.serving and network.reconnect_token != "" and network.address != "":
		_last_connection = {"address": network.address, "name": network.nickname, "token": network.reconnect_token}
		if _remote_mode:
			_last_connection["mode"] = "remote"
			_last_connection["code"] = remote.code
			_last_connection.erase("address")
		var error := history.remember("remote" if _remote_mode else "lan", _last_connection)
		if not error.is_empty(): app.ui.show_notice(error)
	if state.get("phase") == "playing" and _installed and not _paused and not _lost:
		panel.hide()
		_sync_input()


func send(action: String, fields: Dictionary = {}) -> void:
	if not playing() or _lost: return
	fields["scene"] = _scene
	if action in ["cancel", "terminal", "mic"] and not fields.has("operation_id"): fields["operation_id"] = current.get("operation_id", "")
	if action in ["choice", "cancel"] and not fields.has("choice_id"): fields["choice_id"] = _shown_choice
	if action in ["board_confirm", "time_confirm", "ending_confirm"] and not fields.has("offer_id"): fields["offer_id"] = _special_id
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
			5: send("seat_card")
		return
	if _special_choice != "":
		send(_special_choice, {"accept": index == 0})
		_special_choice = ""
		_special_id = ""
	else: send("choice", {"index": index})
	app.ui.hide_choice()
	resume()


func pause() -> void:
	_paused = true
	app.player.enabled = false
	app.player.clear_input()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	app.ui.set_mode("pause")
	var mode := "远程合作" if _remote_mode else "局域网合作"
	app.ui.pause_screen.set_context(app.investigation_brief() + "\n" + mode + " · 队友仍在游戏中，可在「队伍」里发起全队暂停。", true)


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
	app.player.network_driven = false
	_clear_maze_fx()
	_cancel_preparation()
	_reset_local_modals()
	remote.stop()
	network.stop()
	if is_instance_valid(avatars): avatars.queue_free()
	avatars = null
	_installed = false
	_epoch = ""
	_scene = -1
	_lost = false
	_paused = false
	_presented_frame = -1
	_presentation_elapsed = 0.0
	_reset_frame_timings()
	current.clear()
	_seen_event = 0
	_shown_choice = -1
	_death_seen = false
	_ended_seen = false
	_last_motion = -1
	_watch_pose.clear()
	_view_member = ""
	_view_scene = -1
	_spectating = false
	_observing = ""
	prediction.clear()
	_input_window.clear()
	_time_prompt = ""
	_ending_prompt = ""
	_board_prompt = ""
	_recorded = false
	_input_seq = 0
	_remote_token = ""
	_room_phase = ""
	_display_addresses = ""
	if is_instance_valid(_mic): _mic.hide()
	if is_instance_valid(_watch): _watch.hide()
	if is_instance_valid(panel):
		panel.hide()
		panel.show_room({}, "", "")
		panel.set_busy(false)
	if is_instance_valid(_team): _team.hide()
	if is_instance_valid(_network_hint): _network_hint.hide()


func _reset_local_modals() -> void:
	_manual = false
	_special_choice = ""
	_special_id = ""
	_shown_choice = -1
	_time_prompt = ""
	_ending_prompt = ""
	_board_prompt = ""
	if not is_instance_valid(app.ui) or not app.ui.is_inside_tree(): return
	app.ui.hide_choice()
	app.ui.hide_bag()
	app.ui.hide_terminal()
	app._close_phone()
	for view: Control in [app.ui.map_panel, app.ui.notes_panel, _mic]:
		if is_instance_valid(view): view.hide()


func _snapshot(data: Dictionary) -> void:
	if not data.get("session") is Dictionary or network.room == null: return
	var started_at := Time.get_ticks_usec()
	var view: Dictionary = data.get("observed", data) if _spectating else data
	_observing = String(view.get("id", "")) if _spectating else ""
	var source: Dictionary = view["session"]
	var first := _epoch != network.room.epoch or not _installed
	# A small motion datagram may already have moved this player to a newer region.
	if not first and not _spectating and _view_member == network.local_id and int(view["scene"]) < _view_scene: return
	if first and (not _preparing_epoch.is_empty() or (app.router.continuous_campus and not app.router.school_ready())):
		_loading_snapshot = data.duplicate(true)
		if _preparing_epoch != network.room.epoch:
			if not _preparing_epoch.is_empty(): app.cancel_loading()
			_preparing_epoch = network.room.epoch
			# Yield between regions so ENet keeps polling throughout initial load.
			app._load_then(String(source["world_id"]), _finish_preparation.bind(_preparing_epoch), source.get("player"))
		return
	if first:
		var candidate := SessionFactory.create()
		for c in range(49, 52): (candidate.modules.get_module(&"school.day") as SchoolModule).assign_own_seat("teach1:%d:11" % c)
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
		app.player.network_driven = true
		_epoch = network.room.epoch
		_lost = false
		_presented_frame = -1
		_presentation_elapsed = 0.0
		_reset_frame_timings()
		app._install_session(candidate, source["player"])
		_load_album()
		if is_instance_valid(avatars): avatars.queue_free()
		avatars = RemoteStudents.new()
		avatars.name = "RemoteStudents"
		if is_instance_valid(app.router.resident): avatars.space = app.router.resident.space
		app.get_node("World").add_child(avatars)
		avatars.stepped.connect(_remote_step)
		_team.show()
		_seen_event = int(data.get("event_seq", 0))
		_shown_choice = -1
		_death_seen = false
		_ended_seen = false
		_last_motion = -1
		_host_ack = int(data.get("input_seq", -1))
		_input_seq = maxi(0, _host_ack)
		network._command_seq = int(data.get("command_seq", 0)) + 1
		loaded.call_deferred()
	else:
		var album := app.camera().capture()
		var phone_page := app.phone().page
		var same_phone: bool = data.get("phone_uid", "") == current.get("phone_uid", "")
		app.session.modules.restore(source["modules"])
		app.camera().restore(album)
		app.phone().page = phone_page if same_phone else "home"
		app.session.clock.restore(source["clock"])
		app.session.character_id = StudentCast.resolve(source.get("character"))
	current = data
	if is_instance_valid(app._mates_nodes) and not app._mates_nodes._echoes.is_empty():
		for person: Dictionary in data.get("team", {}).values():
			if person.get("seated", false): app._mates_nodes.clear_seat_witness(person.get("seat_id", ""))
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
	app.campus().seat_query = func(world: String, c: int, r: int) -> Dictionary:
		var key := "%s:%d:%d" % [world, c, r]
		for member: Dictionary in network.room.members.values():
			if member.get("seat") != key: continue
			var occupied := false
			for id: String in current.get("team", {}):
				var person: Dictionary = current["team"][id]
				occupied = occupied or (id != network.local_id and person.get("seated", false) and person.get("seat_id") == key)
			return {"own": app.school()._campus["own_seat"]["seatId"] == key, "occupied": occupied}
		return {}
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
	if _view_scene != int(view["scene"]) or _last_motion <= int(data["room"]["tick"]) or _spectating:
		app.player.seated = app.school().seated
		app.player.hiding = bool(app.patrol().hide["on"])
	app.player.can_sprint = app.school().can_run(app.items().snack_active()) and app.body().can_run()
	app.player.speed_multiplier = (1.5 if app.items().snack_active() else 1.0) * app.body().speed_mul()
	_scene = int(data["scene"])
	var next_scene := int(view["scene"])
	var member := _observing if _spectating else network.local_id
	var view_changed: bool = first or member != _view_member or next_scene != _view_scene or app.session.world_id != source["world_id"]
	if view_changed:
		_place_view(member, next_scene, String(source["world_id"]), source["player"], not first and not _spectating and view.get("seamless", false))
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
		var gate := "paper" if data.get("qualified", {}).get("paper", false) else "electronic"
		var card := RoutesModule.card(app.story().ended, app.school().seat_card, gate)
		app.ui.show_ending(String(card.get("title", card.get("t", "合作通关"))), "合作通关", card.get("lines", card.get("l", [])), "本局为局域网合作，个人记录与单人分开。", PackedStringArray(), "", card.get("memory", app.story().ended))
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
	# Network snapshots update world state. Local view culling runs through prefetch,
	# so packets cannot alternate between eye-height and body-height region lists.
	if not view_changed: app._sync_world(false)
	if app.ui.bag_open(): app.ui.show_bag(app._bag_entries(), app.items().capacity())
	if panel.visible:
		panel.inventory(app._bag_entries())
		panel.show_team(data.get("team", {}))
	_sync_input()
	var activity: Dictionary = data.get("activities", {})
	if not activity.is_empty():
		var id := String(activity["id"])
		if activity["game"] == "snake" and id != _game_id: app._start_snake()
		elif activity["game"] != "snake" and app.snake_open(): app._stop_snake(true)
		_game_id = id
		CooperativeActivities.display(activity, app.phone().plane, app._snake)
		if app._snake_panel != null: app._snake_panel.board.queue_redraw()
	if app.phone_open(): app._phone_paint()
	if not first and network.room.phase == "playing":
		_longest_snapshot_us = maxi(_longest_snapshot_us, Time.get_ticks_usec() - started_at)


func _place_view(member: String, scene: int, destination: String, pose: Dictionary, seam: bool) -> void:
	var continuous := seam and scene == _view_scene + 1 and app.router.same_space(app.session.world_id, destination)
	_watch_pose.clear()
	_anchored = null
	if is_instance_valid(avatars): avatars.remove_from_view(member)
	_view_member = member
	_view_scene = scene
	if continuous:
		var space := app.router.resident.space
		var frame := space.frame(destination).affine_inverse() * space.frame(app.session.world_id)
		pose = space.local_pose(destination, space.global_pose(app.session.world_id, app.player.capture_pose()))
		prediction.rebase(frame)
		for sample: Array in _input_window:
			sample[2] = wrapf(float(sample[2]) + frame.basis.get_euler().y, -PI, PI)
	else:
		prediction.clear()
		_input_window.clear()
	if app.session.world_id != destination:
		app.router.switch_to(destination, app.router.same_space(app.session.world_id, destination))
		app.session.world_id = destination
	if continuous: app.player.place(pose)
	else: app.player.restore_pose(pose)
	app.inception_flow.changed_world()
	app._sync_world()


func _finish_preparation(epoch: String) -> void:
	if _preparing_epoch != epoch or network.room == null or network.room.epoch != epoch: return
	_preparing_epoch = ""
	var data := _loading_snapshot
	_loading_snapshot = {}
	_snapshot(data)


func _cancel_preparation() -> void:
	if not _preparing_epoch.is_empty(): app.cancel_loading()
	_preparing_epoch = ""
	_loading_snapshot.clear()


func loaded() -> void:
	var epoch := _epoch
	# The first Vulkan frame can compile pipelines. Keep the shared loading
	# barrier until that local work has completed instead of starting the game.
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	if not _installed or network.room == null or network.room.epoch != epoch: return
	_measure_render_time = OS.is_debug_build() and DisplayServer.get_name() != "headless"
	if _measure_render_time:
		RenderingServer.viewport_set_measure_render_time(app.get_viewport().get_viewport_rid(), true)
	network.loaded()
	if network.room != null and network.room.phase == "playing": resume()


func _event(e: Dictionary) -> void:
	match e["kind"]:
		"seat_witness":
			if app.session.world_id != "teach1" or app.story().over(): return
			var left := minf(6.0, float(e["expires"]) - app.school().active_seconds)
			if left <= 0: return
			var room: Dictionary = CampusData.rooms()["teach1"]
			app._show_classmates(app.classmates(), room, CampusGeometry.to_world(room, app.player.position.x, app.player.position.z), 0)
			if is_instance_valid(app._mates_nodes):
				app._mates_nodes.show_seat_witness(e["seat"], e["person"], Vector2(e["x"], e["y"]), left)
				app.audio.play("dread.call", {"k": .5, "caption": "%s的座位上传来一声「到」" % StudentCast.PEOPLE[e["person"]]["name"]})
		"invert", "invert_end", "shadow_show", "shadow_hide":
			_sync_maze_fx()
			if is_instance_valid(_maze_fx): _maze_fx.event(e)
		"notice", "wake":
			app.ui.show_notice(String(e.get("text", "")))
			if panel.visible: panel.feedback(String(e.get("text", "")))
		"sound": app.audio.play(String(e.get("cue", "dread.steps")), e.get("options", {}))
		"steps": app.audio.play("dread.steps", {"k": 1.0})
		"garage_step":
			if app.session.world_id == GarageModule.ROOM:
				var p := CampusGeometry.to_scene(CampusData.rooms()[GarageModule.ROOM], Vector2(e["x"], e["y"]))
				app.audio.step_on("garage", 1.1, {"pos": Vector3(p.x, app.player.position.y + .2, p.y)})
		"gaze_pull":
			app.player.rotation.y = wrapf(app.player.rotation.y - float(e["yaw"]), -PI, PI)
			app.player._look_pitch = clampf(app.player._look_pitch + float(e["pitch"]), -1.4, 1.4)
		"smile":
			var world := app._campus_world()
			if world != null and world.phantoms != null:
				world.phantoms.reduce_flash = app.settings.get_int("reduce_flash") == 1
				world.phantoms.show_smile(String(e["mode"]), app.player.scene_camera_transform().origin, CampusGeometry.ang_from_yaw(app.player.rotation.y))
				if e["mode"] == "jump": app.ui.flash_hurt(.6)
			app.audio.play("threat.smileJump" if e["mode"] == "jump" else "threat.smileBack")
		"locker":
			match e["beat"]:
				"knock":
					app.audio.play("dread.knock", {"k": 0.7, "caption": "铁皮从柜子里面被敲了两下"})
					app.ui.show_notice("我：……不是外面，是柜子里面。")
				"breath":
					app.audio.play("threat.breath", {"k": 0.7, "caption": "柜子里还有别人的呼吸"})
					app.ui.show_notice("我：耳朵后面有呼吸声。")
				"push": app.ui.show_notice("我撞开柜门跌了出来——柜子里什么也没有。")
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
		if offer[0] == _special_choice and info.get("id") == _special_id: live = true
	if not _special_choice.is_empty() and not live:
		_special_choice = ""
		_special_id = ""
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
		_special_id = String(info.get("id", ""))
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
	var member := _observing if _spectating else network.local_id
	var own: Dictionary = data.get("players", {}).get(member, {})
	if not own.is_empty() and not _spectating:
		_host_ack = maxi(_host_ack, int(own["ack"]))
		# All ordinary campus geometry is resident. A congested reliable baseline
		# must not hold up a doorway, or cause the next input to use the old frame.
		if int(own["scene"]) > _view_scene and app.router.same_space(app.session.world_id, own["world"]):
			_scene = int(own["scene"])
			_place_view(member, _scene, own["world"], own["pose"], own.get("seam", false))
	if avatars != null: avatars.receive(data, member, app.session.world_id, network.room.members)
	if own.is_empty() or own["world"] != app.session.world_id or int(own["scene"]) != _view_scene or bool(current.get("vehicle", false)): return
	if _spectating:
		_watch_pose = own["pose"]
		return
	var p: Array = own["pose"]["position"]
	var position := Vector3(p[0], p[1], p[2])
	app.player.seated = bool(own["seated"])
	app.player.hiding = bool(own["hiding"])
	var fixed_pose: bool = app.player.seated or app.player.hiding or bool(own["dead"]) or own.get("act", "") in ["vault","fall","drive","ride"]
	var transition: bool = _anchored != null and fixed_pose != _anchored
	_anchored = fixed_pose
	if transition: app.player.velocity = Vector3.ZERO
	prediction.reconcile(app.player, position, int(own["ack"]), not fixed_pose and not transition)


func _follow_observed(dt: float) -> void:
	if _watch_pose.is_empty() or network.room.paused_left > 0: return
	var p: Array = _watch_pose["position"]
	var target := Vector3(p[0], p[1], p[2])
	var player := app.player
	var blend := 1.0 if target.distance_squared_to(player.position) > 2.25 else 1.0 - exp(-18.0 * dt)
	player.position = player.position.lerp(target, blend)
	player.rotation.y = lerp_angle(player.rotation.y, float(_watch_pose["yaw"]), blend)
	player.set_pitch(lerpf(player._look_pitch, float(_watch_pose["pitch"]), blend))


func _remote_step(at: Vector3, running: bool, world: String) -> void:
	if not playing() or _lost or app.story().over() or network.room.paused_left > 0.0: return
	if at.distance_to(app.player.global_position) > 12.0: return
	var frame := avatars.space.frame(world) if avatars != null and avatars.space != null else app.router.coordinate_frame.global_transform
	var local := frame.affine_inverse() * at
	var location := CampusGeometry.to_world(CampusData.rooms().get(world), local.x, local.z)
	var outdoor := CampusData.layout("out")
	var surface := AudioFx.surface(world, world == "bell1" and local.y > 0.4, location, outdoor.get("objects", []), float(outdoor.get("SC", 1.0)))
	# Player footsteps must not produce the patrol's threat captions.
	app.audio.step_on(surface, 0.8 if running else 0.55, {"pos": at, "world_pos": true, "self_step": true})


func _process(dt: float) -> void:
	_sample_play_frame()
	if is_instance_valid(panel) and panel.is_visible_in_tree() and panel.page == "join" and not panel.busy and not _remote_mode and not active():
		if network.discovery.scanning: _rescan_timer = 0.0
		else:
			_rescan_timer += dt
			if _rescan_timer >= 5.0:
				_rescan_timer = 0.0
				network.discover(true)
	else: _rescan_timer = 0.0
	_diagnostic_timer += dt
	if _diagnostic_timer >= 0.5:
		_diagnostic_timer = 0.0
		if is_instance_valid(panel) and panel.is_visible_in_tree() and panel._details.is_visible_in_tree():
			_refresh_diagnostics()
		if playing():
			var silence := Time.get_ticks_msec() / 1000.0 - network._last_heard
			_network_hint.text = "连接不稳定 · 等待房主回应" if not network.transport.serving and silence > 3.0 else "网络延迟较高" if network.rtt_ms > 350 else ""
			if network.room.paused_left > 0: _network_hint.text = "全队暂停 · %d 秒后继续" % ceili(network.room.paused_left)
			_network_hint.visible = not _network_hint.text.is_empty() and not _lost


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_RESUMED:
		_last_play_frame_us = 0


func _reset_frame_timings() -> void:
	if _measure_render_time:
		RenderingServer.viewport_set_measure_render_time(app.get_viewport().get_viewport_rid(), false)
		_measure_render_time = false
	_frame_telemetry.reset()
	_last_play_frame_us = 0
	_longest_physics_ms = 0.0
	_longest_snapshot_us = 0
	_longest_gpu_ms = 0.0


func _sample_play_frame() -> void:
	if not playing() or _lost or _paused or network.room.phase != "playing" or network.room.paused_left > 0.0:
		_last_play_frame_us = 0
		return
	var now := Time.get_ticks_usec()
	if _last_play_frame_us > 0:
		_frame_telemetry.sample((now - _last_play_frame_us) / 1000000.0)
		_longest_physics_ms = maxf(_longest_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		if _measure_render_time:
			_longest_gpu_ms = maxf(_longest_gpu_ms, RenderingServer.viewport_get_measured_render_time_gpu(app.get_viewport().get_viewport_rid()))
	_last_play_frame_us = now


func _refresh_diagnostics() -> void:
	panel.connection_info.text = network.connection_details()
	var text := "%s · 延迟 %.0f ms · 抖动 %.0f ms\n发送 %.1f KiB / 接收 %.1f KiB · 校正误差 %.2f m" % ["房主" if network.transport.serving else "客户端", network.rtt_ms, network.jitter_ms, network.transport.bytes_sent / 1024.0, network.transport.bytes_received / 1024.0, prediction.error_metres]
	if not _frame_telemetry.intervals.is_empty():
		var sample := _frame_telemetry.capture()
		var resolution := app.get_window().size
		text += "\n%s · %s · %s · %d×%d（3D %.0f%%）" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name(), GameSettings.QUALITY_LABELS[app.settings.get_int("quality")], resolution.x, resolution.y, app.get_viewport().scaling_3d_scale * 100.0]
		text += "\n游玩 %.1f FPS · 最近 %d 帧 P95 %.1f ms · 本次最长 %.1f ms · ≥1 秒 %d 帧" % [1000.0 / maxf(0.01, sample.average_ms), sample.samples, sample.p95_ms, sample.longest_ms, sample.one_second_frames]
		text += "\n物理峰值 %.1f ms · 应用联机快照峰值 %.1f ms" % [_longest_physics_ms, _longest_snapshot_us / 1000.0]
		if _longest_gpu_ms > 0.0: text += " · GPU 峰值 %.1f ms" % _longest_gpu_ms
	panel.metrics.text = text


func _step_input(dt: float) -> void:
	var player := app.player
	# If the host stalls, continue resending the recent ticks until it catches up.
	# Capping prediction also bounds the amount of stale movement on release.
	if not network.transport.serving and _input_seq - _host_ack >= CooperativeActor.MAX_INPUT_LEAD and not _input_window.is_empty():
		if Engine.get_physics_frames() % 2 == 0:
			network.input({"seq": _input_seq, "scene": _scene, "frames": _input_window, "phone": app.phone_open()})
		player.moving = false
		player.sprinting = false
		return
	var vehicle := bool(current.get("vehicle", false))
	var active := (player.enabled or vehicle) and not _paused and not player.debug_frozen
	var axis := player.movement_axis() if active else Vector2.ZERO
	var run := active and player.run_requested() and not player.editing_text()
	var vault := player.enabled and not player.editing_text() and Input.is_physical_key_pressed(KEY_SPACE)
	var steer := app._paper_steer() if app._paper_owns_input() and not _paused else {}
	_input_seq += 1
	if not vehicle and not player.debug_frozen and not app.story().over() and app.body().fall == null:
		var before := player.position
		if active or not (player.seated or player.hiding):
			player.step_movement(axis, run, dt)
		prediction.advance(player, dt, player.position - before)
	prediction.record(_input_seq, player.position)
	_input_window.append([axis.x, axis.y, wrapf(player.rotation.y, -PI, PI), player._look_pitch, run, vault, steer])
	if _input_window.size() > LanProtocol.INPUT_WINDOW: _input_window.pop_front()
	# Two physics ticks per datagram, including enough prior ticks to repair loss.
	if _input_seq % 2 == 0 or network.transport.serving:
		var frames := [_input_window.back()] if network.transport.serving else _input_window
		network.input({"seq": _input_seq, "scene": _scene, "frames": frames, "phone": app.phone_open()})


func _physics_process(dt: float) -> void:
	if not playing() or _lost: return
	_sync_input()
	if _spectating: _follow_observed(dt)
	if network.room.phase == "playing" and network.room.paused_left <= 0 and not _spectating:
		_step_input(dt)
	else:
		_input_window.clear()
		prediction.clear()
	if (app.player.enabled or app.knife_flow.captured()) and not app.player.editing_text():
		if Input.is_action_just_pressed("bag"): app._open_bag()
		if Input.is_action_just_pressed("torch"): send("item", {"item": "torch"})
		for i in 2:
			if Input.is_action_just_pressed("hot_%d" % (i + 1)) and app.items().hot[i] != null: send("item", {"item": app.items().hot[i], "source": "hot"})
		if Input.is_action_just_pressed("lift_close"): send("lift_close")
	# Several physics steps can precede one rendered frame. Keep physics queries
	# here, and update the view once using the elapsed simulation time.
	_presentation_elapsed += dt
	var frame := Engine.get_process_frames()
	if _presented_frame == frame: return
	_presented_frame = frame
	var elapsed := _presentation_elapsed
	_presentation_elapsed = 0.0
	_present(elapsed)
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
		app.player.global_position = eye - Vector3(0, app.player.camera.position.y, 0)
		app.player.rotation.y = 0.0
		app.player.set_pitch(-0.04)
		app.ui.show_status("校外道路 · " + ("驾驶" if current.get("driver") == network.local_id else "乘客"), "速度 %d · 车况 %d/3 · %d%%" % [roundi(float(chase["speed"]) * 3.6), int(chase["hp"]), roundi(float(chase["distance"]) / CarChaseRules.DISTANCE * 100.0)], "", "")
	elif app._drive_view != null: app._leave_drive()


func _clear_maze_fx() -> void:
	if is_instance_valid(_maze_fx):
		_maze_fx.clear_effects()
		_maze_fx.queue_free()
	_maze_fx = null


func _sync_maze_fx() -> void:
	if app.session == null or app.session.world_id != MazeModule.ROOM or app.story().over():
		_clear_maze_fx()
		return
	if not is_instance_valid(_maze_fx):
		_maze_fx = MazeFx.new()
		add_child(_maze_fx)
		_maze_fx.setup(app.player, app.audio)


func _present(dt: float) -> void:
	_sync_maze_fx()
	if is_instance_valid(_maze_fx): _maze_fx.advance(dt, app.settings.get_int("shake") == 0 or app.settings.get_int("reduce_flash") != 0)
	if is_instance_valid(avatars): avatars.frozen = network.room.paused_left > 0 or network.room.phase != "playing"
	var school := app.school()
	var world := app._campus_world()
	var pose := app.player.capture_pose()
	var room: Variant = app.campus().room(app.session.world_id)
	app.phone().set_context(app._phone_context())
	app.patrol().set_context(app._patrol_context(room, pose))
	app.anomaly().set_context(app._anomaly_context(room, pose))
	app.ui.show_status(school.place_name(app.session.world_id, float(pose["position"][1])), app.first_lunch_lead(school, school.period_text(false)), school.period_class(false), school.clock_text(app.items().has_clock() or app.talent().has("watch")))
	app.ui.show_stamina(school.stam, school.stamina_max(), school.tired)
	app.ui.show_sprint_available(app.player.can_sprint)
	app.ui.show_runtime(app.session.clock.active_seconds)
	var work: Dictionary = current.get("car_job", {})
	app.ui.show_search(float(work.get("t", 0)) / maxf(.001, float(work.get("dur", 1))) if not work.is_empty() else float(current.get("search", {}).get("t", 0)) / InventoryModule.SEARCH_SECONDS)
	app.ui.show_hiding(app.player.hiding)
	app.player.camera.get_node("Torch").visible = app.items().torch_on
	var hot_names := [app.items().item_name(String(app.items().hot[0])) if app.items().hot[0] != null else "空", app.items().item_name(String(app.items().hot[1])) if app.items().hot[1] != null else "空"]
	app.ui.show_hot("1 · %s    2 · %s" % hot_names, app.items().hot, hot_names)
	if app.phone_open() and (not app.phone().available() or school.inspection_active() or app.story().over() or app.ui.terminal_open() or app.ui.choice_open() or app._phone_danger()): app._close_phone()
	if app._chalk_step(dt, app.anomaly(), school, room, pose) and app.anomaly().warning_visible() and not app.anomaly().pre_told: send("warning_seen")
	app._phantom_step(dt, school, room, pose, app.anomaly())
	app._show_plane(app.paper())
	app._show_gaze(app.gaze())
	if world != null: world.show_checkup(app.tales().checkup_today() and app.session.world_id == TalesModule.CHECKUP["room"], app.tales().queue_on(), app.tales().chart_line())
	CampusWorld.pending_traces = app.anomaly().traces
	if world != null: world.sync_traces(app.anomaly().traces)
	app._refresh_interaction_prompt()
	app._show_classmates(app.classmates(), room, CampusGeometry.to_world(room, float(pose["position"][0]), float(pose["position"][2])), dt)
	app.broadcast().set_context(app._broadcast_context())
	app._show_crowd(app.broadcast())
	app._show_visit(app.exchange())
	app._show_marks()
	app._ground_step(app.items())
	app.ui.set_lift_close(app.elevator().show_close_button(app.session.world_id, pose))
	if app.snake_open(): app._snake_step(dt)
	app._sensory_step(dt)
	app._audio_step(dt, app.patrol(), school, room, pose["position"])
	if world != null:
		world.set_player_scene(app.player.position)
		app.garage().set_context(app._garage_context())
		var shadow := app.session.world_id == GarageModule.ROOM and app.garage().roam_visible()
		var shadow_at := CampusGeometry.to_scene(room, Vector2(float(app.garage().roam["x"]), float(app.garage().roam["y"]))) if shadow else Vector2.ZERO
		world.show_garage_shadow(shadow, shadow_at, float(pose["position"][1]))
		world.show_silhouettes(school.inspection_points(), room, float(pose["position"][1]))
		app._update_campus_lighting(world, dt)
		var patrol_view := visible_patrol()
		if not patrol_view.is_empty():
			var at: Vector3 = patrol_view["position"]
			world.show_patrol(true, Vector2(at.x, at.z), at.y, patrol_view["look"], String(app.patrol().pat.behavior), dt)
		else: world.show_patrol(false, Vector2.ZERO, 0, Vector3.ZERO)
		world.show_portal(bool(app.facilities().portal["open"]), bool(app.facilities().portal["sketch"]))
		if world.anomaly_fx != null:
			var cam := app.player.scene_camera_transform().origin
			var fwd := -app.player.scene_camera_transform().basis.z
			world.anomaly_fx.update(dt, app.anomaly().an, room, app.session.world_id, app.player.position, Vector2(fwd.x, fwd.z), cam, app.story().diff == "hard", app.session.character_id)
	if _death_seen and not _spectating and not _ended_seen:
		_death_t += dt
		if is_instance_valid(app._death_cg): app._death_cg.tick(dt)
		if _death_t >= StoryModule.duration(app.story().death_fx) and not app.story().wake_pending:
			app._stop_death_cg()
			app.ui.show_death_card(app.story().death_msg, app.story().epitaph(), app.story().cause(), PackedStringArray(), PackedStringArray(), "队友仍在继续；可从队伍窗口查看状态。", app.story().death_source)
			_watch.visible = not network.room.alive_ids().is_empty()
	var online := network.room.members.values().filter(func(m: Dictionary) -> bool: return m["connected"] and m["state"] != "departed").size()
	_team.text = "队伍 %d/%d%s" % [online, network.room.capacity, " · 全队暂停" if network.room.paused_left > 0 else ""]
	if _spectating: _team.text = "观战 · " + String(network.room.members.get(_observing, {}).get("name", "队友"))
	if _spectating: _watch.text = "正在观战 %s\n切换队友" % String(network.room.members.get(_observing, {}).get("name", "队友")).left(12)


func _sync_input() -> void:
	if not playing(): return
	var blocked: bool = _paused or _lost or _spectating or network.room.phase != "playing" or network.room.paused_left > 0 or app.story().over() or app.ui._mode != "play"
	blocked = blocked or app.ui.bag_open() or app.ui.choice_open() or app.ui.terminal_open() or app.phone_open() or app.snake_open() or app.knife_flow.captured() or app._paper_owns_input() or not current.get("choice", {}).is_empty() or bool(current.get("terminal", false)) or bool(current.get("vehicle", false)) or app.body().fall != null
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
	var pages := ["背包", "笔记", "地图", "课堂互动", "逃生思路"]
	if app.school().at_card_seat(): pages.append("我桌上的名牌")
	app.ui.show_choice("合作手册 · 世界继续运行", pages, false)


func open_mic() -> void:
	if not is_instance_valid(_mic):
		_mic = MicPanel.new()
		app.ui.get_node("Root").add_child(_mic)
		_mic.paper_selected.connect(func(id: String) -> void: send("mic", {"paper": id, "held": false}))
		_mic.hold_changed.connect(func(on: bool) -> void: send("mic", {"held": on}))
		_mic.closed.connect(func() -> void:
			send("mic", {"held": false})
			send("cancel")
			_mic.hide()
			resume())
	_mic.show()
	app.player.clear_input()
	app.player.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func ground_entries() -> Array:
	var space: CampusSpace = app.router.resident.space if is_instance_valid(app.router.resident) else null
	return CooperativeGround.local_entries(app.items().ground, app.session.world_id, space)

func ground_target() -> int:
	var eye := app.player.scene_camera_transform()
	return CooperativeGround.target(ground_entries(), app.player.position, eye.origin, -eye.basis.z)


func visible_patrol() -> Dictionary:
	var watcher := app.patrol()
	if watcher.pat["state"] != "walk" or watcher.pat["transition"] != null: return {}
	var source := String(watcher.pat["room"])
	var viewer := app.session.world_id
	var frame := Transform3D.IDENTITY
	if source != viewer:
		if not app.router.same_space(source, viewer): return {}
		var space: CampusSpace = app.router.resident.space
		frame = space.frame(viewer).affine_inverse() * space.frame(source)
	var room: Variant = CampusData.rooms().get(source)
	var p := CampusGeometry.to_scene(room, Vector2(float(watcher.pat["x"]), float(watcher.pat["y"])))
	var at := frame * Vector3(p.x, float(watcher.pat["fy"]), p.y)
	var look := watcher.look_point()
	var q := CampusGeometry.to_scene(room, Vector2(float(look["x"]), float(look["y"])))
	var eye := app.player.camera.global_position
	var world := app._campus_world()
	if world == null or at.distance_to(app.player.position) > 70: return {}
	var query := PhysicsRayQueryParameters3D.create(eye, world.to_global(at + Vector3.UP * 1.4), 3)
	if not app.player.get_world_3d().direct_space_state.intersect_ray(query).is_empty(): return {}
	return {"position": at, "look": frame * Vector3(q.x, float(watcher.pat["fy"]), q.y)}


func game_input(operation: String, data: Dictionary = {}) -> void:
	if _game_id.is_empty(): return
	data["game_id"] = _game_id
	data["operation"] = operation
	send("game_input", data)

func close_game() -> void:
	if not _game_id.is_empty(): send("game_close", {"game_id": _game_id})

func snake_turn(direction: Vector2i) -> void:
	if direction == Vector2i.ZERO: return
	game_input("turn", {"x": direction.x, "y": direction.y})

func _load_album() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://cooperative-album.json")) if FileAccess.file_exists("user://cooperative-album.json") else null
	if parsed is Dictionary and app.camera().validate(parsed).is_empty(): app.camera().restore(parsed)

func save_album() -> void:
	var file := FileAccess.open("user://cooperative-album.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(app.camera().capture()))
