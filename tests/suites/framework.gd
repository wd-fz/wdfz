extends "res://tests/support/test_suite.gd"


func _test_clock() -> void:
	var clock := RunClock.new()
	check(clock.day_index() == 1 and clock.calendar_minute() == 440.0, "sandbox starts at 07:20")
	clock.advance(360)
	check(is_equal_approx(clock.calendar_minute(), 770.0), "first phase ends at 12:50 after six minutes")
	clock.advance(360)
	check(is_equal_approx(clock.calendar_minute(), 1070.0), "second phase ends at 17:50")
	clock.advance(360)
	check(is_equal_approx(clock.calendar_minute(), 1340.0), "third phase ends at 22:20")
	clock.advance(120)
	check(clock.day_index() == 2 and clock.calendar_minute() == 440.0, "twenty-minute natural day wraps")
	clock.advance(15, false)
	check(clock.active_seconds == 1215.0 and clock.calendar_seconds == 1200.0, "calendar freeze does not freeze active play time")
	clock.advance(-1)
	clock.advance(NAN)
	check(clock.active_seconds == 1215.0, "invalid deltas ignored")
	var restored := RunClock.new()
	restored.restore(clock.capture())
	check(restored.capture() == clock.capture(), "clock round trip")
	var session := _session()
	session.stop()
	session.advance(10)
	check(session.clock.active_seconds == 0, "stopped sessions do not advance")


func _test_modules_and_schema() -> void:
	var session := _session()
	check(not session.modules.register(DemoModule.new()).is_empty(), "duplicate module rejected")
	session.interact(&"demo.read_board")
	var data := session.capture(_pose())
	check(data["modules"]["demo.notice_board"]["data"]["read_count"] == 1, "interaction reaches rule owner")
	data["modules"]["demo.notice_board"]["data"]["read_count"] = 99
	check(session.capture(_pose())["modules"]["demo.notice_board"]["data"]["read_count"] == 1, "snapshot has no live state references")
	var worlds := PackedStringArray(["migration_lab"])
	data = session.capture(_pose())
	check(session.validate(data, worlds).is_empty(), "valid snapshot accepted")
	var reloaded := _session()
	reloaded.restore(data)
	check(reloaded.capture(_pose()) == data, "restoration does not replay interactions")
	var optional := {"version": 7, "data": {"timer": 1.25, "items": ["unknown"]}}
	data["modules"]["optional.future_module"] = optional
	check(reloaded.validate(data, worlds).is_empty(), "inactive module state accepted")
	reloaded.restore(data)
	check(reloaded.capture(_pose())["modules"]["optional.future_module"] == optional, "inactive module state survives saving")
	reloaded.start("migration_lab")
	check(not reloaded.capture(_pose())["modules"].has("optional.future_module"), "new run clears previous optional module data")
	check(reloaded.capture(_pose())["modules"]["demo.notice_board"]["data"]["read_count"] == 0, "new run resets known modules")
	data = session.capture(_pose())
	data["version"] = 999
	check(not session.validate(data, worlds).is_empty(), "future save version rejected")
	check(not session.validate({"v": 1}, worlds).is_empty(), "Web save is not silently converted")
	data = session.capture(_pose())
	data["world_id"] = "res://unexpected.tscn"
	check(not session.validate(data, worlds).is_empty(), "unregistered world paths rejected")
	data = session.capture(_pose())
	data["player"]["position"][0] = INF
	check(not session.validate(data, worlds).is_empty(), "non-finite position rejected")
	data = session.capture(_pose())
	data["player"]["pitch"] = 100
	check(not session.validate(data, worlds).is_empty(), "invalid camera pitch rejected")
	data = session.capture(_pose())
	data["clock"]["calendar_seconds"] = 10
	check(not session.validate(data, worlds).is_empty(), "calendar cannot exceed active play time")
	data = session.capture(_pose())
	data["modules"]["demo.notice_board"]["version"] = 2
	check(not session.validate(data, worlds).is_empty(), "module version is checked separately")
	data = session.capture(_pose())
	data["modules"]["demo.notice_board"]["data"]["read_count"] = "one"
	check(not session.validate(data, worlds).is_empty(), "module validates its own payload")
	data["modules"]["demo.notice_board"] = []
	check(not session.validate(data, worlds).is_empty(), "malformed module envelope rejected")
	data = session.capture(_pose())
	data["modules"].erase("demo.notice_board")
	check(session.validate(data, worlds).is_empty(), "missing newly added module is allowed")
	reloaded.restore(data)
	check(reloaded.capture(_pose())["modules"]["demo.notice_board"]["data"]["read_count"] == 0, "missing module gets fresh state")
	session.stop()
	reloaded.stop()


func _test_storage() -> void:
	var store := SaveStore.new(_test_path)
	check(store.read().has("error"), "missing save reports an error")
	var session := _session()
	var first := session.capture(_pose())
	check(store.write(first).is_empty(), "first save writes successfully")
	check(same_json(store.read().get("data"), first), "JSON save round trip")
	session.interact(&"demo.read_board")
	var second := session.capture(_pose())
	check(store.write(second).is_empty(), "save replaces existing file")
	check(same_json(store.read().get("data"), second), "latest save read")
	check(same_json(SaveStore.new(_test_path + ".bak").read().get("data"), first), "previous save kept as backup")
	check(not FileAccess.file_exists(_test_path + ".tmp"), "temporary file consumed by rename")
	var oversized := {"large": "a".repeat(SaveStore.MAX_BYTES + 1)}
	check(not store.write(oversized).is_empty(), "oversized write refused")
	check(same_json(store.read().get("data"), second), "failed write preserves previous save")
	check(not store.write({"temporary_object": Vector3.ZERO}).is_empty(), "transient engine values cannot silently turn into strings")
	check(same_json(store.read().get("data"), second), "non-JSON write also preserves previous save")
	var file := FileAccess.open(_test_path, FileAccess.WRITE)
	file.store_string("{incomplete json")
	file.close()
	check(store.read().has("error"), "truncated JSON reported")
	check(same_json(SaveStore.new(_test_path + ".bak").read().get("data"), first), "failed read leaves backup alone")
	session.stop()


func _test_app() -> void:
	var app: GameApp = APP.instantiate()
	app.initial_world = "migration_lab" # Framework regression keeps the sandbox room.
	app.saves = SaveStore.new(_test_path)
	root.size = Vector2i(1280, 720)
	root.add_child(app)
	await _frames()
	check(app.ui.menu.visible and app.session == null, "app boots to menu")
	check(app.ui.menu_screen.state in ["opening", "open"] and app.ui.menu_screen.find_child("MenuTag", true, false) == null, "the side menu opens by itself, without a tag to click")
	app.ui.menu_screen.reveal(app.ui.get_node("%NewGame"))
	await _frames(3)
	await _tap(app.ui.get_node("%NewGame"))
	await _frames()
	check(app.session == null and app.ui.choice_open(), "real touch tap on menu opens the talent pick")
	await _tap(app.ui.selection_panel.cards[0])
	check(app.session == null, "browsing a talent does not start the run")
	await _tap(app.ui.selection_panel.confirm_button)
	await _until_started(app)
	await _frames()
	check(app.session != null and app.talent().id == "tech" and app.items().has("phone"), "confirming the first talent starts the run with it (科技党 starts with a phone)")
	check(app.ui.opening_on() and paused and not app.player.enabled, "the prologue plays first, with the game waiting")
	var t0 := app.school().tsec
	for _i in TalentModule.KEYS.size() + 6:
		app.ui._next_opening()
	await _frames()
	check(not app.ui.opening_on(), "the pages run out")
	app.ui.show_opening()
	app.ui._end_opening(true)
	await _frames()
	check(not paused and app.player.enabled and app.school().tsec == t0 and app.achievements().unlocked.has("n.opening"), "after the prologue the run begins where it stood: 第四节")
	if app.session == null:
		app.queue_free()
		return
	check(app.router.current.world_id == &"migration_lab", "registered room loaded")
	await _tap(app.ui.get_node("%PauseButton"))
	check(paused and app.ui.pause_panel.visible, "real touch tap opens pause")
	await _tap(app.ui.get_node("%Resume"))
	check(not paused and app.player.enabled, "real touch tap resumes simulation")
	var initial_z := app.player.position.z
	Input.action_press("move_forward")
	await _frames(30)
	Input.action_release("move_forward")
	check(app.player.position.z < initial_z - 1.0, "actual physics movement moves player")
	app.pause_game()
	var elapsed := app.session.clock.active_seconds
	var position := app.player.position
	Input.action_press("move_forward")
	await _frames(10)
	Input.action_release("move_forward")
	check(app.session.clock.active_seconds == elapsed, "pause freezes simulation")
	check(app.player.position == position, "pause freezes player")
	app.resume_game()
	app.player.restore_pose({"position": [0.0, 0.05, -3.4], "yaw": 0.0, "pitch": 0.0})
	await _frames()
	app.player.request_interaction()
	check(app.session.capture(_pose())["modules"]["demo.notice_board"]["data"]["read_count"] == 1, "raycast interaction reaches module")
	app.player.restore_pose({"position": [0.0, 0.05, -7.0], "yaw": PI, "pitch": 0.0})
	app.player.request_interaction()
	check(app.session.capture(_pose())["modules"]["demo.notice_board"]["data"]["read_count"] == 1, "wall occludes interaction behind it")
	app.player.restore_pose({"position": [0.0, 0.05, -3.4], "yaw": 0.2, "pitch": 0.25})
	app.pause_game()
	app.save_game()
	var saved: Dictionary = app.saves.read()["data"]
	var old_session := app.session
	app.resume_game()
	app.session.interact(&"demo.read_board")
	app.player.apply_look(Vector2(0.5, 0.5))
	app.load_game()
	app.pause_game()
	check(app.session != old_session and not old_session.running, "load replaces and stops the previous session")
	check(same_json(app.session.capture(app.player.capture_pose()), saved), "load restores pose, camera, clock and module state")
	var live_session := app.session
	var world := app.router.get_child(0)
	var invalid := saved.duplicate(true)
	invalid["version"] = 99
	check(app.saves.write(invalid).is_empty(), "invalid fixture written")
	app.load_game()
	check(app.session == live_session and app.router.get_child(0) == world, "invalid load does not tear down live session or world")
	check(paused, "failed load keeps pause state")
	app.resume_game()
	app.ui.set_touch_enabled(true)
	await _frames()
	await _test_touch(app)
	app.return_to_menu()
	check(app.session == null and app.router.get_child_count() == 0, "return to menu releases the world and session")
	check(not paused and not app.player.enabled, "menu leaves no paused-tree or active-player residue")
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(390, 844), Vector2i(844, 390)]:
		root.size = viewport_size
		await _frames()
		app.ui.menu_screen.reveal(app.ui.get_node("%NewGame"))
		await _frames(3)
		var content: ScrollContainer = app.ui.menu_screen.scroll
		check(root.get_visible_rect().encloses(content.get_global_rect()), "scrollable menu fits viewport %s" % viewport_size)
		await _tap(app.ui.get_node("%NewGame"))
		check(app.ui.choice_open(), "the talent pick opens after resize %s" % viewport_size)
		check(root.get_visible_rect().encloses(app.ui.selection_panel.shell.get_global_rect()), "the talent pick fits viewport %s" % viewport_size)
		var random_card: Control = app.ui.selection_panel.cards[TalentModule.KEYS.size()]
		app.ui.selection_panel.list_scroll.ensure_control_visible(random_card)
		await _frames(2)
		await _tap(random_card)
		check(app.session == null, "random selection also waits for confirmation")
		await _tap(app.ui.selection_panel.confirm_button)
		await _until_started(app)
		check(app.session != null and TalentModule.KEYS.has(app.talent().id), "touch button hit-testing after resize %s (random talent)" % viewport_size)
		app.ui._end_opening(true)
		app.return_to_menu()
	for _i in 3:
		app.start_new_game()
		await _frames()
		check(app.session.capture(_pose())["modules"]["demo.notice_board"]["data"]["read_count"] == 0, "repeated new runs start with fresh module state")
		app.return_to_menu()
	app.queue_free()
	await _frames()


func _test_touch(app: GameApp) -> void:
	var press := InputEventScreenTouch.new()
	press.index = 2
	press.pressed = true
	press.position = app.ui.stick.size * 0.5 + Vector2(50, 0)
	app.ui.stick._gui_input(press)
	check(app.player.get("_touch_move").x > 0.5, "touch stick drives movement")
	var look_press := InputEventScreenTouch.new()
	look_press.index = 3
	look_press.pressed = true
	look_press.position = app.ui.look_pad.get_global_rect().get_center()
	app.ui.look_pad._unhandled_input(look_press)
	var yaw := app.player.rotation.y
	var drag := InputEventScreenDrag.new()
	drag.index = 4
	drag.relative = Vector2(20, 0)
	app.ui.look_pad._input(drag)
	check(app.player.rotation.y == yaw, "unowned finger cannot rotate camera")
	drag.index = 3
	app.ui.look_pad._input(drag)
	check(not is_equal_approx(app.player.rotation.y, yaw), "owned touch drag rotates camera without pointer lock")
	yaw = app.player.rotation.y
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(40, 0)
	app.ui.look_pad._input(mouse)
	check(app.player.rotation.y == yaw, "mouse motion never enters touch camera path")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	mouse.device = -1
	mouse.screen_relative = Vector2(30, 0)
	app.player._unhandled_input(mouse)
	check(app.player.rotation.y == yaw, "emulated touch mouse motion cannot rotate desktop camera")
	mouse.device = 0
	app.player._unhandled_input(mouse)
	if DisplayServer.get_name() == "headless":
		check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and app.player.rotation.y == yaw, "headless display does not claim mouse capture")
	else:
		check(not is_equal_approx(app.player.rotation.y, yaw), "real captured mouse still rotates with touch controls visible")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var click := InputEventMouseButton.new()
	click.device = -1
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	app.player._unhandled_input(click)
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "touch-generated mouse click does not capture cursor")
	app.pause_game()
	check(app.player.get("_touch_move") == Vector2.ZERO and app.ui.look_pad.get("_finger") == -1, "pause releases all touch ownership and movement")
	app.resume_game()
	check(app.player.get("_touch_move") == Vector2.ZERO, "resume does not resurrect a held touch")
