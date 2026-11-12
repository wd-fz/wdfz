extends SceneTree
var network: LanSession
var role := "guest"
var port := 24560
var count := 2
var elapsed := 0.0
var startup := 0.0
var input_timer := 0.0
var seq := 0
var snapshots := 0
var motions := 0
var loaded_epoch := ""
var state: Dictionary = {}
var began := false
var checks := 0
var failures := 0
var stage := 0
var before_pause := 0.0
var duration := 18.0
var ui_mode := false
var app: GameApp
var disconnected_at := -1.0
var saved_identity := ""
var token := ""
var reconnecting := false
var tick_samples: Array = []
var last_tick := -1
var initial_position: Array = []
var slow_load := false
var load_stalled := false
var peers_verified := false
var restore_test := false
var old_epoch := ""
var saved_key := ""
var saved_guest := ""
var saved_calendar := 0.0
var screenshot_dir := ""
var ending_test := false
var ending_wait := 0.0
var last_choice := -1
var route_timer := 0.0
var soak := false
var soak_period := -1
var peak_nodes := 0
var peak_memory := 0
var baseline_memory := 0
var peak_regions := 0
var soak_checked := false


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--role="): role = argument.trim_prefix("--role=")
		if argument.begins_with("--port="): port = int(argument.trim_prefix("--port="))
		if argument.begins_with("--players="): count = int(argument.trim_prefix("--players="))
		if argument.begins_with("--seconds="): duration = float(argument.trim_prefix("--seconds="))
		if argument == "--ui": ui_mode = true
		if argument == "--soak": soak = true
		if argument == "--ending": ending_test = true
		if argument == "--slow-load": slow_load = true
		if argument == "--restore": restore_test = true
		if argument.begins_with("--screenshots="): screenshot_dir = argument.trim_prefix("--screenshots=")
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)


func run() -> void:
	if ui_mode:
		# This is an interface/transport check on software Vulkan, not a GPU
		# benchmark. Use the real lowest preset in this process's isolated data.
		var settings := GameSettings.new()
		settings.set_value("quality", 0)
		settings.set_value("fps_limit", 60)
		settings.set_value("vsync", 0)
		settings.save_file()
		app = preload("res://game/app/app.tscn").instantiate()
		root.add_child(app)
		await process_frame
		network = app.lan.network
		if role != "host": app.ui.set_touch_enabled(true)
		check(app.ui.find_child("LanCoop", true, false) != null, "real main menu contains cooperation entry")
		app.lan.open()
		check(app.lan.panel.visible, "cooperation panel can be opened from menu")
		app.lan.panel.hide()
		if role == "host":
			check(network.host("cancel", "host", port - 1 if port == 65535 else port + 1).is_empty(), "temporary lobby opens")
			app.lan.panel.close_requested.emit()
			check(not app.lan.active() and not paused and app.ui.menu.visible and not app.lan.panel.visible, "returning from lobby cancels networking and keeps single-player menu usable")
		if DisplayServer.get_name() != "headless":
			check(RenderingServer.get_current_rendering_driver_name() == "vulkan" and RenderingServer.get_rendering_device() != null, "real Vulkan device available")
			print("RENDERER VERIFIED: vulkan / ", RenderingServer.get_current_rendering_method())
			print("DISPLAY VERIFIED: ", DisplayServer.get_name().to_lower())
	else:
		var parent := Node.new()
		parent.name = "LanTest"
		root.add_child(parent)
		network = LanSession.new()
		network.name = "Network"
		parent.add_child(network)
	network.notice.connect(func(text: String) -> void: print("NOTICE: ", text))
	network.closed.connect(func(reason: String) -> void:
		if restore_test and elapsed >= 7.0 and not reconnecting:
			saved_identity = network.local_id
			token = network.reconnect_token
			old_epoch = network.room.epoch
			disconnected_at = startup
			reconnecting = true
			network.stop()
			return
		if elapsed < 7.0:
			check(false, reason)
			finish())
	network.room_changed.connect(func(_data: Dictionary) -> void:
		if network.room.phase == "lobby" and network.local_id != "" and network.room.members.has(network.local_id) and not network.room.members[network.local_id]["ready"]: network.ready(true, "watch")
		if role == "host" and not began and network.room.members.size() == count and network.room.can_start():
			began = true
			check(network.start().is_empty(), "host starts ready room"))
	network.snapshot_received.connect(func(data: Dictionary) -> void:
		if slow_load and role != "host" and not load_stalled:
			load_stalled = true
			# Reproduce a slow first world build that blocks ENet polling.
			OS.delay_msec(12000)
		state = data
		snapshots += 1
		if loaded_epoch != network.room.epoch:
			loaded_epoch = network.room.epoch
			print("BASELINE READY: ", role, " at ", Time.get_ticks_msec() / 1000.0)
			# The actual UI owns its load/render barrier.
			if not ui_mode: network.loaded())
	network.motion_received.connect(func(_data: Dictionary) -> void: motions += 1)
	var error := network.host("test", "host", port) if role == "host" else network.join("127.0.0.1:%d" % port, role)
	check(error.is_empty(), "socket setup: " + error)
	if error != "": finish()


func _process(dt: float) -> bool:
	startup += dt
	if startup > duration * 2 + (160 if ui_mode else 35):
		check(false, "connection/loading timeout")
		finish()
	if network == null: return false
	if reconnecting and startup - disconnected_at > (3.0 if restore_test else 1.5):
		reconnecting = false
		check(network.join("127.0.0.1:%d" % port, role, token).is_empty(), "reconnect socket")
	if role == "guest-1" and not restore_test and elapsed > 7.5 and disconnected_at < 0:
		saved_identity = network.local_id
		token = network.reconnect_token
		disconnected_at = startup
		reconnecting = true
		network.stop()
		if ui_mode:
			app.lan._installed = false
			app.lan._lost = true
		return false

	if restore_test and role == "host" and stage == 2 and startup - disconnected_at > 2.0:
		began = false
		check(network.host("restored", "host", port, true).is_empty(), "host reopens the saved room with original credentials")
		stage = 3
	if network.room != null and network.room.phase == "playing": elapsed += dt
	if network.room != null and network.room.phase == "playing" and not state.is_empty():
		if role != "host" and elapsed > 1.0 and not peers_verified:
			peers_verified = true
			check(network.transport.api.get_peers() == PackedInt32Array([1]), "clients only see the authority, never ENet relay peers: " + str(network.transport.api.get_peers()))
		input_timer += dt
		if input_timer > 0.033 and not ui_mode:
			input_timer = 0.0
			seq += 1
			network.input({"seq": seq, "scene": state["scene"], "x": 0.0, "y": -1.0 if elapsed < 5.0 and not ending_test and not restore_test else 0.0, "yaw": state["session"]["player"]["yaw"] if ending_test else 0.0, "pitch": 0.0, "run": true})
		if role == "host":
			if soak: _soak_scenario()
			elif restore_test: _restore_host()
			elif ending_test: _ending_host()
			else: _host_scenario()
		if ui_mode and role != "host": _touch_panel()
		if ending_test: _ending_member(dt)
	if ending_test and network.room != null and network.room.phase == "ended":
		ending_wait += dt
		if ending_wait >= (3.0 if role == "host" else 1.0):
			check(network.room.ending == "face" and state.get("life", {}).get("ended") == "face", "real ENet client receives shared whitelist ending")
			if role == "guest-1": check(network.local_id == saved_identity, "route survives original-member reconnect")
			finish()
	if elapsed > duration + (2.0 if role == "host" else 0.0):
		check(snapshots > 10, "received repeated baselines")
		check(motions > 40, "received motion over unreliable ENet")
		check(not ending_test and network.room != null and network.room.phase == "playing", "room stays running / ending completes before timeout")
		if role == "guest-1":
			check(network.local_id == saved_identity, "reconnect keeps stable identity")
			if restore_test: check(network.room.epoch != old_epoch and state["session"]["world_id"] == "lab3", "restored guest loads the new epoch in its saved world")
		finish()
	return false


func _host_scenario() -> void:
	var sim := network.simulation
	if sim.room.tick != last_tick:
		last_tick = sim.room.tick
		var cost := 0
		for us: int in sim.timings.values(): cost += us
		tick_samples.append(cost / 1000.0)
		if tick_samples.size() > 5000: tick_samples.pop_front()
	if stage == 0 and elapsed > 3.0:
		check(sim.actors.size() == count, "one authoritative actor per process")
		var id := String(sim.actors.keys()[1])
		sim.travel(sim.actor(id), "lab3", sim.spawn("lab3"))
		check(sim.actor(network.local_id).location() == "teach1", "guest travel does not switch host room")
		stage = 1
	elif stage == 1 and elapsed > 4.0:
		check(sim.physics.zones.size() >= 2, "separate physical spaces stay active")
		network.pause(true)
		before_pause = sim.calendar.tsec
		stage = 2
	elif stage == 2 and elapsed > 4.6:
		check(sim.calendar.tsec == before_pause, "global pause keeps heartbeats but freezes game")
		network.pause(false)
		stage = 3
	elif stage == 3 and elapsed > 6.0:
		var saved := sim.capture()
		var error := CooperativeValidation.validate(saved)
		check(error.is_empty(), "running world validates: " + error)
		check(sim.actor(network.local_id).school().tsec == sim.actor(String(sim.actors.keys()[1])).school().tsec, "calendar not multiplied by player count")
		stage = 4
	elif stage == 4 and elapsed > 11.0:
		check(network.connections.size() == count, "original peer restored after transport disconnect")
		if ui_mode:
			app.lan.open()
			stage = 5
			await _capture("team")
			check(not paused and not app.player.enabled, "host menu freezes only local controls")
			var panel := app.lan.panel
			var rows := panel.members.get_children()
			panel.show_room(network.room.public_state(), network.local_id, "127.0.0.1:%d" % port)
			check(panel.members.get_children() == rows, "snapshot refresh keeps touch buttons and keyboard focus alive")
			app.lan.resume()
			if DisplayServer.get_name().to_lower() == "wayland" and (not app.get_window().has_focus() or not app.lan._pointer_inside):
				check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Wayland background resume defers capture until pointer focus")
			var before_command := sim.actor(network.local_id).command_sequence
			var think := InputEventKey.new()
			think.physical_keycode = KEY_H
			think.pressed = true
			app._unhandled_key_input(think)
			check(sim.actor(network.local_id).command_sequence > before_command, "keyboard escape hint goes through host authority")
		stage = 5
	elif stage == 5 and elapsed > 13.0:
		sim.actor(network.local_id).fate().wakes = StoryModule.MAX_WAKES
		sim.gameplay.kill(sim.actor(network.local_id), "联机回归中的死亡场景", "vignette", "san")
		check(sim.room.phase == "playing" and sim.actor(network.local_id).fate().dead, "host death leaves shared simulation running")
		stage = 6
	elif stage == 6 and elapsed > 14.0:
		check(sim.state_for(network.local_id).has("observed"), "dead host receives authorized spectator view")
		stage = 7


func _touch_panel() -> void:
	if stage != 0 or elapsed < 2.0: return
	stage = 1
	app.lan.open()
	await _capture("touch-team")
	var panel_rect := app.lan.panel._panel.get_global_rect()
	var view := root.get_visible_rect()
	check(view.encloses(panel_rect), "landscape touch room panel stays within the viewport")
	check(not app.player.enabled and not paused, "touch room panel blocks only its own controls")
	app.lan.resume()


func _restore_host() -> void:
	var sim := network.simulation
	# JSON sorts dictionary keys; an original member is never an array slot.
	if saved_guest.is_empty():
		for id: String in sim.actors:
			if id != network.local_id: saved_guest = id; break
	var guest := sim.actor(saved_guest)
	if stage == 0 and elapsed > 3.0:
		guest.bag().add("key")
		sim.inventory.reconcile(guest)
		saved_key = sim.inventory.owners[guest.id]["key"]
		(sim.shared[&"story.routes"] as RoutesModule).hacked = true
		sim.travel(guest, "lab3", sim.spawn("lab3"))
		stage = 1
	elif stage == 1 and elapsed > 8.0:
		old_epoch = network.room.epoch
		saved_calendar = sim.calendar.seconds
		disconnected_at = startup
		network.stop()
		check(not network.store.read().has("error"), "host shutdown writes a validated checkpoint")
		stage = 2
	elif stage == 3 and elapsed > 11.0:
		check(network.room.epoch != old_epoch, "restored room discards the old session epoch")
		check(guest.location() == "lab3" and sim.inventory.owners[guest.id].get("key") == saved_key, "saved world and unique item ownership survive host restart: %s / %s" % [guest.location(), sim.inventory.owners[guest.id].get("key")])
		check((sim.shared[&"story.routes"] as RoutesModule).hacked and sim.calendar.seconds >= saved_calendar, "restored room keeps shared progress and time")
		check(network.connections.size() == count, "all original members authenticate after host restart")
		stage = 4


func _terminal_pose(world: String) -> Dictionary:
	var room := CampusData.rooms()[world] as Dictionary
	var grid: Array = room["grid"]
	for row in grid.size():
		for col in String(grid[row]).length():
			if String(grid[row]).substr(col, 1) != "D": continue
			for off: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				var p := CampusGeometry.to_scene(room, CampusGeometry.tile_center(room, col + off.x, row + off.y))
				var pose := {"position": [p.x, 0.05, p.y], "yaw": CampusGeometry.yaw_from_ang(atan2(-off.y, -off.x)), "pitch": 0.0}
				if network.simulation.campus().interact_at(world, pose).get("terminal", false): return pose
	return {}


func _ending_host() -> void:
	var sim := network.simulation
	var a := sim.actor(network.local_id)
	var route := sim.shared[&"story.routes"] as RoutesModule
	var guest := sim.actor(String(sim.actors.keys()[1]))
	if stage == 0 and elapsed > 2:
		a.bag().add("usb")
		sim.inventory.reconcile(a)
		sim.travel(a, "lab3", _terminal_pose("lab3"))
		network.command("interact", {"scene": a.scene_version})
		stage = 1
	elif stage == 1 and route.hacked and elapsed > 4:
		check(route.hacked, "network command writes whitelist from actual terminal")
		sim.travel(guest, "admin3", _terminal_pose("admin3"))
		stage = 2
	elif stage == 2 and route.data_synced and elapsed > 12:
		check(route.data_synced and network.connections.size() == count, "teammate syncs route and reconnects before gate")
		var gate := CampusGeometry.to_scene(null, Vector2(401, 1250))
		for actor: CooperativeActor in sim.actors.values(): sim.travel(actor, "out", {"position": [gate.x, 0.05, gate.y], "yaw": 0.0, "pitch": 0.0})
		network.command("interact", {"scene": a.scene_version})
		stage = 3


func _ending_member(dt: float) -> void:
	route_timer += dt
	if route_timer < 0.35: return
	route_timer = 0.0
	if role != "host" and state["session"]["world_id"] == "admin3":
		var route: Dictionary = state["session"]["modules"]["story.routes"]["data"]
		if not route["data"]: network.command("interact", {"scene": state["scene"]})
	var choice: Dictionary = state.get("choice", {})
	if role == "host" and not choice.is_empty() and choice.get("source") == "routes" and int(choice["id"]) != last_choice:
		last_choice = int(choice["id"])
		var route: Dictionary = state["session"]["modules"]["story.routes"]["data"]
		var quiz: Dictionary = route["face_quiz"]
		var answer := 0 if int(quiz["done"]) == 3 else int(RoutesModule.QUESTIONS[quiz["order"][int(quiz["done"])]] ["answer"])
		network.command("choice", {"scene": state["scene"], "index": answer})
	if not network.room.ending_offer.is_empty() and network.local_id not in network.room.ending_offer["confirmed"]:
		network.command("ending_confirm", {"scene": state["scene"], "accept": true})


func _soak_scenario() -> void:
	# Explicit diagnostic fixture, not a natural playthrough: protect stats so damage
	# does not end the network/region lifecycle workload before 30 real minutes.
	var sim := network.simulation
	sim.room.debug_run = true
	var regions := ["teach1", "lab3", "admin3", "dorm1", "out"]
	var period := int(elapsed / 20.0)
	for i in sim.actors.size():
		var a := sim.actor(String(sim.actors.keys()[i]))
		a.school().san = 100
		a.school().tt = 0
		a.school().viol = 0
		a.fate().wakes = 0
		if period != soak_period:
			sim.travel(a, regions[(i + period) % regions.size()], sim.spawn(regions[(i + period) % regions.size()]))
	soak_period = period
	var memory := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	peak_memory = maxi(peak_memory, memory)
	peak_nodes = maxi(peak_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	peak_regions = maxi(peak_regions, sim.physics.zones.size())
	if elapsed > 60 and baseline_memory == 0: baseline_memory = memory
	if sim.room.tick != last_tick:
		last_tick = sim.room.tick
		var cost := 0
		for us: int in sim.timings.values(): cost += us
		tick_samples.append(cost / 1000.0)
		if tick_samples.size() > 5000: tick_samples.pop_front()
	if elapsed > duration - 0.05 and not soak_checked:
		soak_checked = true
		check(sim.physics.zones.size() <= 10, "active physical regions remain bounded")
		check(network._awaiting.size() <= count - 1, "snapshot backlog remains bounded")
		check(sim.inventory.ground.size() <= InventoryModule.GROUND_MAX, "shared ground bound")
		check(memory < baseline_memory * 1.6 + 16 * 1024 * 1024, "static memory bounded after warmup")


func _capture(label: String) -> void:
	if screenshot_dir.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	var image := root.get_texture().get_image()
	check(image != null and not image.is_empty(), "rendered cooperative window has pixels")
	if image != null: image.save_png(screenshot_dir.path_join(role + "-" + label + ".png"))


func finish() -> void:
	tick_samples.sort()
	print("LAN RESULT: ", JSON.stringify({"elapsed_seconds": elapsed, "soak": soak, "memory_baseline": baseline_memory, "memory_peak": peak_memory, "memory_end": int(Performance.get_monitor(Performance.MEMORY_STATIC)), "nodes_peak": peak_nodes, "regions_peak": peak_regions, "tick_p95_ms": tick_samples[int(tick_samples.size() * .95)] if not tick_samples.is_empty() else 0, "bytes_sent": network.transport.bytes_sent, "bytes_received": network.transport.bytes_received,"role": role, "checks": checks, "failures": failures, "snapshots": snapshots, "motions": motions}))
	if network != null:
		network.stop()
		if is_instance_valid(app): app.queue_free()
		else: network.queue_free()
	quit(1 if failures > 0 else 0)
