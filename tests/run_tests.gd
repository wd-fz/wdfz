extends SceneTree
## Real engine tests without an addon. All test saves use an isolated directory.

const APP := preload("res://scenes/app.tscn")
var _checks := 0
var _failures: PackedStringArray = []
var _test_path := "user://framework-tests/run-%s/slot.json" % Time.get_ticks_usec()


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		print("FAIL: ", message)


func same_json(a: Variant, b: Variant) -> bool:
	# JSON has one numeric type; Godot's nested Dictionary equality is type-strict.
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		return absf(float(a) - float(b)) < 0.000001
	if typeof(a) != typeof(b):
		return false
	if a is Dictionary:
		if a.size() != b.size():
			return false
		for key: Variant in a:
			if not b.has(key) or not same_json(a[key], b[key]):
				return false
		return true
	if a is Array:
		if a.size() != b.size():
			return false
		for index in a.size():
			if not same_json(a[index], b[index]):
				return false
		return true
	return a == b


func _session() -> GameSession:
	var result := GameSession.new()
	check(result.modules.register(DemoModule.new()).is_empty(), "register demo module")
	check(result.modules.register(CampusData.make_module()).is_empty(), "register campus module")
	result.start("migration_lab")
	return result


func _pose() -> Dictionary:
	return {"position": [0.0, 0.1, 3.0], "yaw": 0.0, "pitch": 0.0}


func _run() -> void:
	_test_clock()
	_test_modules_and_schema()
	_test_storage()
	await _test_app()
	_test_campus_rules()
	_test_elevator_rules()
	_test_school_rules()
	_test_inventory_rules()
	_test_story_rules()
	_test_patrol_rules()
	_test_anomaly_rules()
	_test_routes_rules()
	_test_achievements()
	_test_garage_rules()
	_test_facility_rules()
	_test_broadcast_rules()
	_test_phone_rules()
	_test_talent_rules()
	_test_fake_normal_rules()
	_test_body_rules()
	_test_exchange_rules()
	_test_day_rules()
	_test_tales_rules()
	_test_checkup_rules()
	_test_speedrun_rules()
	_test_gaze_rules()
	_test_paper_rules()
	_test_marks_rules()
	_test_classmates_rules()
	_test_sensory_rules()
	_test_caption_rules()
	_test_dread_rules()
	_test_atmos_rules()
	_test_mono_rules()
	_test_scene_rules()
	_test_settings_rules()
	_test_investigation_rules()
	_test_exploration_rules()
	_test_drop_rules()
	_test_plane_rules()
	_test_camera_rules()
	_test_snake_rules()
	await _test_campus_app()
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(_test_path + suffix):
			DirAccess.remove_absolute(_test_path + suffix)
	var death_log := _test_path.get_base_dir().path_join("death_log.json")
	if FileAccess.file_exists(death_log):
		DirAccess.remove_absolute(death_log)
	DirAccess.remove_absolute(_test_path.get_base_dir())
	CampusData.clear_caches()
	print("FRAMEWORK TESTS: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


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


func _frames(count: int = 3) -> void:
	for _i in count:
		await physics_frame
		await process_frame


func _tap(control: Control) -> void:
	await _frames(2)
	var position := root.get_final_transform() * control.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.pressed = pressed
		event.position = position
		Input.parse_input_event(event)
		await _frames(2)


func _test_app() -> void:
	var app: GameApp = APP.instantiate()
	app.initial_world = "migration_lab" # Framework regression keeps the sandbox room.
	app.saves = SaveStore.new(_test_path)
	root.size = Vector2i(1280, 720)
	root.add_child(app)
	await _frames()
	check(app.ui.menu.visible and app.session == null, "app boots to menu")
	await _tap(app.ui.get_node("%NewGame"))
	await _frames()
	check(app.session == null and app.ui.choice_open(), "real touch tap on menu opens the talent pick")
	await _tap(app.ui._choice_box.get_child(0))
	await _frames()
	check(app.session != null and app.talent().id == "tech" and app.items().has("phone"), "tapping the first talent starts the run with it (科技党 starts with a phone)")
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
		var content: Control = app.ui.menu.get_node("Margin/Center/Content")
		check(root.get_visible_rect().encloses(content.get_global_rect()), "menu fits viewport %s" % viewport_size)
		await _tap(app.ui.get_node("%NewGame"))
		check(app.ui.choice_open(), "the talent pick opens after resize %s" % viewport_size)
		check(root.get_visible_rect().encloses(app.ui.choice_panel.get_global_rect()), "the talent pick fits viewport %s" % viewport_size)
		var random_card: Control = app.ui._choice_box.get_child(TalentModule.KEYS.size())
		app.ui._choice_scroll.ensure_control_visible(random_card)
		await _frames(2)
		await _tap(random_card)
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


func _campus_pose(room: Variant, w: Vector2, ang: float) -> Dictionary:
	var p := CampusGeometry.to_scene(room, w)
	return {"position": [p.x, 0.05, p.y], "yaw": CampusGeometry.yaw_from_ang(ang), "pitch": 0.0}


func _test_campus_rules() -> void:
	var rooms := CampusData.rooms()
	check(rooms.size() == 42 and not CampusData.layout("out").is_empty(), "all 42 Web interiors and the outside are exported")
	var campus := CampusData.make_module()
	campus.reset()
	check(campus.start_world() == "teach1", "run starts in teach1 like the Web version")
	var t1: Dictionary = rooms["teach1"]
	check(t1["grid"].size() == 22 and String(t1["grid"][0]).length() == 63, "teach1 keeps the 63 x 22 tile grid")
	# Door 10:15 is the front door of the first classroom; stand in the corridor facing north.
	var door := CampusGeometry.tile_center(t1, 10, 15)
	var pose := _campus_pose(t1, door + Vector2(0, 14), -PI * 0.5)
	check(campus.hint("teach1", pose) == "开门", "closed classroom door offers to open")
	var opened := campus.interact_at("teach1", pose)
	check(opened.get("door", {}).get("open") == true and campus.is_open("teach1:10:15"), "E opens the facing door")
	check(campus.capture()["open_doors"] == ["teach1:10:15"], "open doors are saved by key")
	var blocked := campus.interact_at("teach1", _campus_pose(t1, door + Vector2(0, 5), -PI * 0.5))
	check(blocked["notice"] == "我：先让开门口。" and campus.is_open("teach1:10:15"), "cannot close a door while standing in it")
	campus.interact_at("teach1", pose)
	check(not campus.is_open("teach1:10:15"), "E closes it again from the corridor")
	check(not campus.validate({"open_doors": ["teach1:99:99"]}).is_empty(), "unknown door keys rejected")
	check(not campus.validate({"open_doors": "x"}).is_empty(), "malformed door state rejected")
	var l3: Dictionary = rooms["lab3"]
	var locked := campus.interact_at("lab3", _campus_pose(l3, CampusGeometry.tile_center(l3, 41, 15) + Vector2(0, 14), -PI * 0.5))
	check(String(locked.get("toast", "")).contains("机房钥匙") and not campus.is_open("lab3:41:15"), "locked door keeps the Web lock and key name")
	# Seamless teach1 south door (campus-link: column 31, 3 cells wide).
	var cfg: Dictionary = CampusData.campus()["campus_doors"]
	var spec: Dictionary = cfg["doors"][0]
	var port := CampusGeometry.door_port(t1, spec)
	var inside := campus.crossing("teach1", _campus_pose(t1, port["p"] - Vector2(0, 2), PI * 0.5))
	check(inside.is_empty(), "no switch before the threshold line")
	var out := campus.crossing("teach1", _campus_pose(t1, port["p"] + Vector2(0, 0.5), PI * 0.5))
	check(out.get("world") == "out", "crossing the threshold leaves to the campus")
	var back := campus.crossing("out", out["pose"])
	check(back.is_empty(), "standing outside the gap does not bounce back")
	var shift := CampusGeometry.shift_of(t1)
	var entering := campus.crossing("out", _campus_pose(null, port["p"] + shift - Vector2(0, 1), -PI * 0.5))
	check(entering.get("world") == "teach1", "walking into the doorway enters teach1")
	var p_in: Array = entering["pose"]["position"]
	var expect := CampusGeometry.to_scene(t1, port["p"] - Vector2(0, 1))
	check(absf(p_in[0] - expect.x) < 0.001 and absf(p_in[2] - expect.y) < 0.001, "threshold keeps position through the room/campus translation")
	var garage := campus.interact_at("out", _campus_pose(null, Vector2(956, 326), PI * 0.5))
	check(garage.get("travel", {}).get("world") == "garage1", "E at the garage entrance enters garage1")
	var at_teach := campus.interact_at("out", _campus_pose(null, Vector2(1077.5, 1975), -PI * 0.5))
	check(at_teach["notice"] == "我：门开着，直接走进去就行。", "seamless buildings answer like the Web version")
	var exit_room: Dictionary = rooms["trash1"]
	check(exit_room["exit_world"] != null, "rooms know where their host door is outside")
	# Stairwell threshold (stairwell.js): teach1 west stair cell (6..7, 21) opens to stair_teach_w.
	var stair_port := CampusPortals.stair_port(CampusPortals.stair_config(CampusData.campus()["stair_layout"], "stair_teach_w"), 0, rooms, CampusData.layout("out"))
	var before_stair := campus.crossing("teach1", _campus_pose(t1, stair_port["p"] - Vector2(0, 2), PI * 0.5))
	check(before_stair.is_empty(), "approaching the stair doorway does not switch yet")
	var into_stair := campus.crossing("teach1", _campus_pose(t1, stair_port["p"] + Vector2(0, 0.3), PI * 0.5))
	check(into_stair.get("world") == "stair_teach_w" and absf(float(into_stair["pose"]["position"][1]) - 0.05) < 0.001, "walking past the stair doorway enters the shaft at ground level")
	var level_two := campus.crossing("stair_teach_w", {"position": [0.0, 3.2, -2.9], "yaw": 0.0, "pitch": 0.0})
	check(level_two.get("world") == "teach2", "leaving the shaft on the 3.2 m landing reaches teach2")
	var mid_air := campus.crossing("stair_teach_w", {"position": [0.0, 1.6, -2.9], "yaw": 0.0, "pitch": 0.0})
	check(mid_air.is_empty(), "no exit between landings")
	var surfaces := CampusPortals.stair_surfaces(6, 3.2)
	check(surfaces.size() == 6 * 2 + 5 * 3, "stair surfaces match StairGeometry for six levels")
	check(is_equal_approx(CampusPortals.surface_at(surfaces, -1.25, 3.2, 0.8)["h"], 0.8), "half way up the first flight is 0.8 m")
	# Corridor bridge teach2 -> link2 (campus-link/link.js, a pure translation).
	var t2: Dictionary = rooms["teach2"]
	var link_cfg: Dictionary = CampusData.campus()["campus_link"]
	var tp := CampusPortals.link_port(rooms, link_cfg["pairs"][3][0], 3)
	var bridged := campus.crossing("teach2", _campus_pose(t2, (tp["p"] as Vector2) + Vector2(0, -0.5), -PI * 0.5))
	check(bridged.get("world") == "link2", "walking out of teach2's north opening enters the bridge")
	var back_t2 := campus.crossing("link2", bridged["pose"])
	check(back_t2.is_empty(), "arriving on the bridge does not bounce back")
	var canteen_stair := campus.interact_at("canteen1", _campus_pose(rooms["canteen1"], CampusGeometry.tile_center(rooms["canteen1"], 4, 25), PI * 0.5))
	check(canteen_stair.get("travel", {}).get("world") == "out", "canteen stair without a shaft leads outside like stairGo")


func _run_lift(lift: ElevatorModule, seconds: float, room: String, pose: Dictionary) -> Dictionary:
	var last := {}
	var t := 0.0
	while t < seconds:
		var r := lift.step(1.0 / 60.0, room, pose)
		if not r.is_empty():
			last = r
			if r.has("travel"):
				return r
		t += 1.0 / 60.0
	return last


func _test_elevator_rules() -> void:
	var rooms := CampusData.rooms()
	var lift := ElevatorModule.new(rooms)
	lift.reset()
	lift.set_seed(7)
	var t1: Dictionary = rooms["teach1"]
	var f := lift.frame("teach1")
	check(not f.is_empty() and (f["out"] as Vector2) == Vector2(0, -1), "teach1 elevator J cell faces the corridor")
	var hall := (f["j"] as Vector2) + Vector2(0, -12)
	var pose_hall := _campus_pose(t1, hall, -PI * 0.5)
	# The car starts at floor 1: the call button opens the doors directly.
	var called := lift.use_at("teach1", hall)
	check(called["notice"] == "我：按下呼梯键。门开了。", "hall call at the car's floor opens the doors")
	_run_lift(lift, 1.0, "teach1", pose_hall)
	check(is_equal_approx(lift.door_amount("teach", 1), 1.0), "doors open fully in 0.9 s")
	_run_lift(lift, 4.2, "teach1", pose_hall)
	check(lift.door_amount("teach", 1) < 1.0, "doors start closing after the 4 s hold")
	# Step into the cabin (behind the landing door) and choose floor 3.
	lift.use_at("teach1", hall)
	_run_lift(lift, 1.0, "teach1", pose_hall)
	var inside := lift.world("teach1", -1.2, 0.0)
	var pose_in := _campus_pose(t1, inside, PI * 0.5)
	_run_lift(lift, 0.1, "teach1", pose_in)
	check(lift.ride.get("phase") == "cabin" and lift.ride.get("origin") == 1, "stepping over the landing door boards the cabin")
	var panel := lift.use_at("teach1", inside)
	check(panel.has("choice") and (panel["choice"]["values"] as Array).size() in [2, 5], "cabin panel offers floors")
	if lift.ride.get("rare", false):
		lift.ride["rare"] = false # This seed's roll is irrelevant here; the rare path is tested below.
	lift.press(3, "teach1", pose_in)
	var departed := _run_lift(lift, 2.0, "teach1", pose_in)
	check(departed.get("travel", {}).get("world") == "lift_teach", "doors close, then the ride moves to the cabin scene")
	var car_pose: Dictionary = departed["travel"]["pose"]
	check(lift.door_amount("teach", 1) == 0.0 and lift.lifts["teach"]["phase"] == "occupied", "car is occupied while travelling")
	var arrived := _run_lift(lift, 5.0, "lift_teach", car_pose)
	check(arrived.get("travel", {}).get("world") == "teach3", "after 2 + 2 × 0.7 s the ride arrives at teach3")
	var p3: Array = arrived["travel"]["pose"]["position"]
	var exp3 := CampusGeometry.to_scene(rooms["teach3"], lift.world("teach3", -1.2, 0.0))
	check(absf(p3[0] - exp3.x) < 0.01 and absf(p3[2] - exp3.y) < 0.01, "arrival keeps the spot inside the cabin")
	_run_lift(lift, 1.0, "teach3", arrived["travel"]["pose"])
	check(is_equal_approx(lift.door_amount("teach", 3), 1.0), "doors open at the arrival floor")
	var saved := lift.capture()
	var copy := ElevatorModule.new(rooms)
	copy.reset()
	check(copy.validate(JSON.parse_string(JSON.stringify(saved))).is_empty(), "elevator state survives JSON")
	copy.restore(JSON.parse_string(JSON.stringify(saved)))
	check(copy.capture()["lifts"]["teach"]["floor"] == 3 and copy.ride.get("phase") == "cabin", "restored elevator is at floor 3 with the ride")
	# Calling from another floor makes the car travel there.
	var lab := ElevatorModule.new(rooms)
	lab.reset()
	var l4: Dictionary = rooms["lab4"]
	var lab_hall := lab.world("lab4", 1.2, 0.0)
	var waiting := lab.use_at("lab4", lab_hall)
	check(waiting["notice"] == "我：按下呼梯键。楼层指示灯缓慢亮了起来。" and lab.lifts["lab"]["phase"] == "waiting", "calling from lab4 summons the car")
	_run_lift(lab, 3.0 + 3 * 0.7 + 1.2, "lab4", _campus_pose(l4, lab_hall, 0.0))
	check(lab.lifts["lab"]["floor"] == 4 and lab.door_amount("lab", 4) > 0.9, "car arrives at lab4 and opens")
	# Rare ride: the 67/89 buttons and the old built-in white room.
	lab.ride = {"host": "lab", "origin": 4, "target": 4, "phase": "cabin", "rare": true, "remaining": 0.0, "pending": null}
	var rare_panel := lab.controls("lab4", lab.world("lab4", -1.2, 0.0))
	check(rare_panel["choice"]["values"] == ["67", "89"], "the rare cabin only offers 67 and 89")
	var fresh := ElevatorModule.new(rooms)
	fresh.reset()
	var rare_rolls := 0
	for _i in 200:
		fresh.ride = {}
		fresh._enter_cabin("teach", 1)
		rare_rolls += 1 if fresh.ride["rare"] else 0
	check(rare_rolls == 0, "no wrong-elevator roll before the void maze is ported")


func _test_school_rules() -> void:
	check(SchoolClock.fmt_clock(700) == "11:40" and SchoolClock.period_at(700)[2] == "第 4 节", "a run starts at 11:40 in period 4")
	check(SchoolClock.need_where(1340) == "宿舍" and SchoolClock.need_where(600) == "操场" and SchoolClock.need_where(530) == "自由", "need_where follows the schedule")
	# A whole natural day is 1200 simulation seconds (four phases 360/360/360/120).
	var total := 0.0
	var t := 440.0
	while t < 1500.0 - 1e-9:
		var end := SchoolClock.clock_boundary(t)
		total += (end - t) * 60.0 / SchoolClock.rate_at(t)
		t = end
	check(absf(total - 1200.0) < 0.01, "one natural day costs 1200 simulation seconds (%.3f)" % total)
	var school := SchoolModule.new(CampusData.rooms(), CampusData.layout("out"), CampusData.campus())
	school.reset()
	var seat := school.start_seated("teach1")
	var own := CampusGeometry.to_world(CampusData.layout("teach1"), float(seat["position"][0]), float(seat["position"][2]))
	var ctx := {"world_id": "teach1", "w": own, "moving": false, "running": false, "calendar": true}
	school.san = 50.0
	school.step(10.0, ctx)
	# 700 -> 705 takes 5.3 s at the first phase's rate; the internal window after 11:45 runs at 2 game min / min.
	check(absf(school.tsec - 705.16) < 0.02, "ten seconds from 11:40 reach 11:45 and enter the slow window (%.3f)" % school.tsec)
	check(absf(school.san - (50.0 + 0.42 * 10.0)) < 0.01, "seated at the own seat in class restores 0.42 SAN per second")
	check(absf(school.tt - 0.26 * 10.0) < 0.01, "sitting through class raises assimilation 0.26 per second")
	school.stand_up()
	ctx["world_id"] = "out"
	ctx["w"] = Vector2(1000, 1000)
	school.tsec = 1345.0
	school.viol = 0.0
	school.step(2.0, ctx)
	check(absf(school.viol - 2.0 * 0.85 * 0.5) < 0.01, "after lights-out outside, violation grows at the halved night rate")
	school.tsec = 900.0
	school.viol = 10.0
	school.step(1.0, ctx)
	check(absf(school.viol - (10.0 - 3.2)) < 0.01, "outside the rules violation decays 3.2 per second")
	school.stam = 40.0
	school.step(1.0, {"world_id": "out", "w": Vector2(1000, 1000), "moving": true, "running": true, "calendar": false})
	check(absf(school.stam - 32.0) < 0.01, "running costs 8 stamina per second")
	school.stam = 5.0
	school.step(0.1, {"world_id": "out", "w": Vector2(1000, 1000), "moving": true, "running": true, "calendar": false})
	check(school.tired and not school.can_run(), "below 6 stamina the player is out of breath")
	school.stam = 29.0
	school.step(0.01, {"world_id": "out", "w": Vector2(1000, 1000), "moving": false, "running": false, "calendar": false})
	check(school.tired, "still out of breath until stamina is back at 30")
	school.stam = 31.0
	school.step(0.01, {"world_id": "out", "w": Vector2(1000, 1000), "moving": false, "running": false, "calendar": false})
	check(not school.tired, "stamina 30 lets the player run again")
	check(is_equal_approx(SchoolModule.stamina_max_for(50.0), 70.0), "stamina maximum is 40 + 0.6 × SAN")
	var later := SchoolModule.new(CampusData.rooms(), CampusData.layout("out"), CampusData.campus())
	later.reset()
	later.tsec = 1340.0
	later.advance_game_time(20.0)
	check(later.day == 2 and is_equal_approx(later.tsec, 1360.0), "day two starts at 22:30")
	later.advance_game_time(140.0)
	check(is_equal_approx(later.tsec, 440.0), "01:00 jumps to 07:20")
	check(int(later.pressure()["stage"]) >= 2, "campus pressure climbs after the first night")
	var data: Dictionary = JSON.parse_string(JSON.stringify(later.capture()))
	check(school.validate(data).is_empty(), "school state survives JSON")
	# Inspection (inspection.js): warning 60 s before 12:50, eight seconds of checking, settlement.
	var ins := SchoolModule.new(CampusData.rooms(), CampusData.layout("out"), CampusData.campus())
	ins.reset()
	var seat_pose := ins.start_seated("teach1")
	var at_seat := CampusGeometry.to_world(CampusData.layout("teach1"), float(seat_pose["position"][0]), float(seat_pose["position"][2]))
	var sit_ctx := {"world_id": "teach1", "w": at_seat, "moving": false, "running": false, "calendar": true, "ang": PI, "pitch": 1.2}
	ins.tsec = SchoolClock.clock_time_before(770.0, 61.0)
	ins.step(2.0, sit_ctx)
	check(ins.inspection_upcoming() and ins.period_text(false) == "集合将至 · 请坐回自己的座位", "the broadcast warns a minute before 12:50")
	var heard := ins.take_notices()
	check(heard.size() > 0 and heard[heard.size() - 1].contains("十二点五十"), "broadcast text names 12:50")
	var waited := 0.0
	while not ins.inspection_active() and waited < 90.0:
		ins.step(0.5, sit_ctx)
		waited += 0.5
	check(ins.inspection_active() and absf(waited - 59.0) < 1.5, "the check starts at 12:50 (%.1f s later)" % waited)
	ins.san = 80.0
	ins.viol = 20.0
	ins.tt = 10.0
	var checking := 0.0
	while ins.inspection_active() and checking < 20.0:
		ins.step(0.05, sit_ctx)
		checking += 0.05
	check(absf(checking - 8.0) < 0.1, "the check lasts eight seconds (%.2f)" % checking)
	check(absf(ins.san - 77.0) < 0.1 and absf(ins.viol - 12.0) < 0.2 and absf(ins.tt - 13.0) < 0.05, "sitting still: -3 SAN, -8 violation, +3 assimilation (san %.2f viol %.2f tt %.2f)" % [ins.san, ins.viol, ins.tt])
	check(ins.inspection["settled"].get("1:0") == "present", "the own seat counts as present")
	var absent := SchoolModule.new(CampusData.rooms(), CampusData.layout("out"), CampusData.campus())
	absent.reset()
	absent.tsec = 1069.9
	absent.san = 80.0
	absent.viol = 20.0
	var away := {"world_id": "out", "w": Vector2(1000, 1000), "moving": true, "running": false, "calendar": true, "ang": 0.0, "pitch": 1.2}
	var started := false
	for _i in 400:
		absent.step(0.05, away)
		if absent.inspection_active():
			started = true
		elif started:
			break
	check(absent.inspection["settled"].get("1:1") == "absent", "away from the seat at 17:50 counts as absent")
	check(absent.viol > 20.0 + 16.0 + 10.0 - 1.0, "moving during the check adds 2 violation per second on top of the absence (%.2f)" % absent.viol)


func _test_inventory_rules() -> void:
	var rooms := CampusData.rooms()
	var inv := InventoryModule.new(rooms, CampusData.campus())
	inv.reset()
	inv.set_seed(3)
	check(inv.capacity() == 8, "the bag holds eight things")
	check(inv.add("torch") and not inv.add("torch"), "an item is held once")
	for id: String in ["chalk", "pen", "coin", "battery", "card", "notebook", "watch"]:
		inv.add(id)
	check(inv.bag.size() == 8 and not inv.add("pill") and inv.take_notices().has("我：装不下了。"), "a full bag refuses more")
	check(inv.set_hot(0, "torch") and not inv.set_hot(1, "pill"), "hot slots only take held items")
	inv.use_hot(0, 700.0)
	check(inv.torch_on, "the torch toggles from its hot slot")
	inv.remove("torch")
	check(inv.hot[0] == null and not inv.torch_on, "dropping the torch clears its slot and light")
	check(inv.has_clock() and inv.use("watch", 700.0)["notice"] == "我：现在是 11:40。", "the watch tells the time")
	inv.remove("coin")
	inv.add("pill")
	inv.use("pill", 700.0)
	var gained := 0.0
	for _i in 40:
		gained += inv.step(1.0)
	check(absf(gained - 60.0) < 0.01 and not inv.has("pill"), "a pill restores 2 SAN per second for 30 s")
	inv.add("snack")
	inv.use("snack", 700.0)
	check(inv.snack_active(), "the snack starts its 30 s")
	# Searching: hold still 0.8 s; walking away cancels; the same drawer is only searched once.
	var fresh := InventoryModule.new(rooms, CampusData.campus())
	fresh.reset()
	fresh.set_seed(11)
	var t1: Dictionary = rooms["teach1"]
	var desk := CampusGeometry.tile_center(t1, 47, 7)
	fresh.start_search("teach1", 47, 7, desk)
	fresh.search_tick(0.5, "teach1", desk + Vector2(9, 0))
	check(not fresh.searching() and fresh.take_notices().has("我：手一松，没翻完。"), "moving away interrupts the search")
	fresh.start_search("teach1", 47, 7, desk)
	fresh.search_tick(0.5, "teach1", desk)
	check(fresh.searching(), "still searching after 0.5 s")
	fresh.search_tick(0.4, "teach1", desk)
	check(not fresh.searching() and fresh.hw_taken and fresh.has("hw"), "the first teach1 drawer holds the homework")
	fresh.start_search("teach1", 47, 7, desk)
	check(fresh.take_notices().has("我：翻过了。"), "a searched drawer stays searched")
	# The principal's office keeps its 45 % key chance with the pity on the fourth miss.
	var keys := InventoryModule.new(rooms, CampusData.campus())
	keys.reset()
	var found := false
	for i in 4:
		keys.desk_used.clear()
		keys.do_search("admin5", 10 + i, 3)
		found = found or keys.has("key") or keys.has("roomkey")
	check(found, "four principal drawers always give a key (pity)")
	var campus := CampusData.make_module()
	campus.reset()
	var l3: Dictionary = rooms["lab3"]
	var lab_pose := _campus_pose(l3, CampusGeometry.tile_center(l3, 41, 15) + Vector2(0, 14), -PI * 0.5)
	check(campus.hint("lab3", lab_pose) == "开门（锁着）", "the lab3 machine room door shows as locked")
	var bag := InventoryModule.new(rooms, CampusData.campus())
	bag.reset()
	campus.has_item = bag.has
	bag.add("roomkey")
	var opened := campus.interact_at("lab3", lab_pose)
	check(opened.get("door", {}).get("open") == true, "the machine room key opens it")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(bag.capture()))
	check(bag.validate(saved).is_empty(), "bag state survives JSON")
	saved["bag"] = ["nonsense"]
	check(not bag.validate(saved).is_empty(), "unknown items are rejected")


func _test_story_rules() -> void:
	var fate := StoryModule.new()
	fate.reset()
	var first := fate.kill("你一直撑着的那根弦，断了。", "vignette", "san", {"day": 1, "has_elixir": false})
	check(first.get("dead", false) and first["wake"] and is_equal_approx(first["hold"], 2.0), "day-one death on 预知梦 wakes and the scene lasts 2 s")
	check(fate.kill("x", "grip", "patrol", {"day": 1, "has_elixir": false}).is_empty(), "a second kill while dead is ignored")
	check(fate.epitaph() == "有人替你应了一声\"到\"。" and fate.cause().begins_with("你的理智已经耗尽"), "epitaph and cause come from the old tables")
	check(fate.finish_wake() == 2 and not fate.dead, "the first wake leaves two")
	fate.kill("x", "names", "assimilation", {"day": 1, "has_elixir": false})
	fate.finish_wake()
	fate.kill("x", "names", "assimilation", {"day": 1, "has_elixir": false})
	check(fate.finish_wake() == 0, "three wakes at most")
	var fourth := fate.kill("x", "names", "assimilation", {"day": 1, "has_elixir": false})
	check(fourth["wake"] == false, "after three wakes the next death is final")
	fate.reset()
	check(fate.kill("x", "grip", "patrol", {"day": 2, "has_elixir": false})["wake"] == false, "no wake after day one")
	fate.reset()
	fate.diff = "hard"
	check(fate.kill("x", "grip", "patrol", {"day": 1, "has_elixir": false})["wake"] == false, "梦魇 never wakes")
	fate.reset()
	var saved := fate.kill("x", "grip", "patrol", {"day": 1, "has_elixir": true})
	check(saved.get("protected") == "elixir" and not fate.dead, "the unknown pill takes the death instead")
	check(is_equal_approx(StoryModule.duration("liftdoor"), 4.4) and is_equal_approx(StoryModule.duration("nonsense"), 2.0), "death scene durations follow DeathTimeline")
	var record := {}
	fate.reset()
	fate.kill("x", "vignette", "san", {"day": 1, "has_elixir": false})
	record = fate.log_death(record, 1, "teach1")
	check(StoryModule.hints(record).is_empty(), "one death gives no hint yet")
	fate.finish_wake()
	fate.kill("x", "vignette", "san", {"day": 1, "has_elixir": false})
	record = fate.log_death(record, 1, "out")
	var clues := StoryModule.hints(record)
	check(clues.size() == 1 and clues[0].begins_with("留意呼吸和画面变化"), "the same death twice gives its clue (deathHints)")
	check(fate.validate(JSON.parse_string(JSON.stringify(fate.capture()))).is_empty(), "story state survives JSON")
	var school := SchoolModule.new(CampusData.rooms(), CampusData.layout("out"), CampusData.campus())
	school.reset()
	school.san = 0.0
	school.step(0.1, {"world_id": "out", "w": Vector2(1000, 1000), "moving": false, "running": false, "calendar": true})
	var asked := school.take_deaths()
	check(asked.size() == 1 and asked[0]["source"] == "san" and asked[0]["fx"] == "vignette", "SAN 0 asks for the vignette death")
	school.san = 50.0
	school.tt = 100.0
	school.step(0.1, {"world_id": "out", "w": Vector2(1000, 1000), "moving": false, "running": false, "calendar": true})
	asked = school.take_deaths()
	check(asked.size() == 1 and asked[0]["source"] == "assimilation" and asked[0]["fx"] == "names", "assimilation 100 asks for the names death")
	school.san = 0.0
	school.tt = 100.0
	school.survive("assimilation")
	check(school.san >= 45.0 and is_equal_approx(school.tt, 86.0), "a protected assimilation death falls back to 86")
	school.dream_wake_reset()
	check(is_equal_approx(school.tsec, 700.0) and is_equal_approx(school.san, 78.0) and school.viol == 0.0 and school.tt == 0.0, "the dream wake returns to 11:40 with SAN 78")


func _pctx(scene: String, w: Vector2, extra: Dictionary = {}) -> Dictionary:
	var c := {"scene": scene, "x": w.x, "y": w.y, "fy": 0.0, "seated": false, "at_seat": false, "excused": false, "on_leave": false,
		"night": false, "need_where": "教室", "dead": false, "playing": true, "inspection_room": "", "calm": 0.0, "calm_room": "",
		"has_seal": false, "active_seconds": 0.0, "car_chase": false}
	c.merge(extra, true)
	return c


func _patrol_run(pm: PatrolModule, ctx: Dictionary, seconds: float, stop_on: String = "") -> Array:
	var got: Array = []
	var t := 0.0
	while t < seconds:
		pm.set_context(ctx)
		pm.tick(0.05)
		for e: Dictionary in pm.take_events():
			got.append(e)
			if e["kind"] == stop_on:
				return got
		t += 0.05
	return got


func _test_patrol_rules() -> void:
	var nav := CampusData.patrol_nav()
	var data := CampusData.patrol_data()
	check(not nav.grid("teach1").is_empty() and nav.nodes.size() == 121 and nav.edges.size() == 128, "patrol grids and the 121-node connection graph are exported")
	check(data["route"]["nodes"].size() == 128 and data["zones"].size() == 9, "route of 128 nodes and nine report zones")
	var a: Dictionary = nav.nodes["teach1:stairs"]
	var b: Dictionary = nav.nodes["teach1:east"]
	var way := nav.path(a, b)
	check(way.size() > 10 and nav.length(way) > 400.0, "A* connects the west stairs and the east end of teach1 (%d cells, %.0f units)" % [way.size(), nav.length(way)])
	var blocked := PatrolNav.point("teach1", 1000.0, 1760.0)
	var wall_edge := CampusGeometry.tile_center(CampusData.layout("teach1"), 31, 15)
	check(not nav.snap("teach1", PatrolNav.point("teach1", wall_edge.x, wall_edge.y)).is_empty(), "snap finds a free cell next to a wall point")
	check(nav.segment(a, way[2]) and not nav.segment(a, PatrolNav.point("teach1", 1000.0, 1760.0)), "a segment is clear along the corridor and blocked through walls")
	var hop := nav.shortest("admin1:stairs", "admin2:stairs")
	check(not hop.is_empty() and hop["nodes"].size() >= 2 and float(hop["weight"]) > 0.0, "RouteGraph finds admin1 -> admin2 through the stairs")
	# A patrol with nobody around walks the route and changes scenes.
	var pm := CampusData.make_patrol()
	pm.reset()
	pm.elevator = ElevatorModule.new(CampusData.rooms())
	check(pm.pat["room"] == "admin1" and pm.pat["state"] == "walk", "the patroller starts at the admin1 stairs")
	var far := _pctx("dorm1", CampusGeometry.tile_center(CampusData.layout("dorm1"), 10, 5), {"need_where": "自由"})
	_patrol_run(pm, far, 120.0)
	check(int(pm.pat["routeIndex"]) > 1 or pm.pat["room"] != "admin1", "after two minutes the patroller has walked on (node %d in %s)" % [pm.pat["routeIndex"], pm.pat["room"]])
	var moved := {}
	for _i in 6:
		_patrol_run(pm, far, 60.0)
		moved[pm.pat["room"]] = true
	check(moved.size() >= 2, "it crosses between scenes (%s)" % ", ".join(PackedStringArray(moved.keys())))
	# Chase: out of place in a classroom building during class.
	var t1: Dictionary = CampusData.layout("teach1")
	var me := CampusGeometry.tile_center(t1, 30, 17)
	var chaser := CampusData.make_patrol()
	chaser.reset()
	chaser.pat["room"] = "teach1"
	chaser.pat["x"] = me.x + 80.0
	chaser.pat["y"] = me.y
	chaser.pat["behavior"] = "patrol"
	chaser.pat["routeIndex"] = _route_towards("teach1:east", "teach1:stairs", chaser)
	chaser.pat["safety"] = 0.0
	chaser.elevator = pm.elevator
	var ctx := _pctx("teach1", me)
	check(chaser.eligible() == false or true, "context-free eligibility does not crash")
	chaser.set_context(ctx)
	check(chaser.eligible() and not chaser.exempt() and chaser.hunting(), "out of the seat in class inside a teaching building makes the player a target")
	var events := _patrol_run(chaser, ctx, 20.0, "kill")
	var kinds := events.map(func(e: Dictionary) -> String: return e["kind"])
	check(kinds.has("violation") and kinds.has("kill"), "it locks on (+8 violation once), chases and catches")
	check(events.size() > 0 and events[events.size() - 1].get("source") == "patrol" and events[events.size() - 1].get("fx") == "grip", "the catch is the patrol grip death")
	check(kinds.count("violation") == 1, "the citation is issued once")
	# Seated at the own seat: exempt.
	var calm := CampusData.make_patrol()
	calm.reset()
	calm.pat["room"] = "teach1"
	calm.pat["x"] = me.x + 80.0
	calm.pat["y"] = me.y
	calm.pat["safety"] = 0.0
	calm.pat["behavior"] = "patrol"
	calm.pat["routeIndex"] = _route_towards("teach1:east", "teach1:stairs", calm)
	calm.elevator = pm.elevator
	var seated_ctx := _pctx("teach1", me, {"seated": true, "at_seat": true})
	var quiet := _patrol_run(calm, seated_ctx, 15.0)
	check(quiet.is_empty() and not bool(calm.pat["locked"]), "sitting at the own seat in class is never hunted")
	# A seal burns instead of the lock.
	var sealed := CampusData.make_patrol()
	sealed.reset()
	sealed.pat["room"] = "teach1"
	sealed.pat["x"] = me.x + 80.0
	sealed.pat["y"] = me.y
	sealed.pat["safety"] = 0.0
	sealed.pat["behavior"] = "patrol"
	sealed.pat["routeIndex"] = _route_towards("teach1:east", "teach1:stairs", sealed)
	sealed.elevator = pm.elevator
	var sealed_events := _patrol_run(sealed, _pctx("teach1", me, {"has_seal": true}), 12.0, "remove_item")
	check(sealed_events.size() > 0 and sealed_events[sealed_events.size() - 1]["kind"] == "remove_item" and sealed.pat["state"] == "idle" and is_equal_approx(float(sealed.pat["respawn"]), 30.0),
		"the talisman burns at the lock and the patroller is banished for 30 s")
	# Night outside: hunted on the campus, left alone indoors.
	check(not _night_hunt("dorm1"), "at night inside a dorm the player is not eligible")
	check(_night_hunt("out"), "at night outside the player is eligible")
	# Hiding.
	var hider := CampusData.make_patrol()
	hider.reset()
	hider.elevator = pm.elevator
	hider.pat["room"] = "teach1"
	hider.pat["safety"] = 0.0
	var locker: Vector2i = Vector2i(12, 16)
	check(String(t1["grid"][16]).substr(12, 1) == "H", "teach1 has the exported locker cell (12, 16)")
	var near_locker := CampusGeometry.tile_center(t1, 12, 17)
	hider.pat["x"] = near_locker.x + 200.0
	hider.pat["y"] = near_locker.y
	hider.set_context(_pctx("teach1", near_locker))
	var spot := hider.hide_in(locker.x, locker.y)
	check(hider.hide["on"] and not hider.hide["seen"] and absf(spot["ang"] - PI * 0.5) < 0.001, "hiding in a locker unseen")
	var hide_events := _patrol_run(hider, _pctx("teach1", Vector2(spot["x"], spot["y"])), 10.0)
	check(not bool(hider.pat["locked"]), "an unseen locker is not searched")
	var out_spot := hider.hide_out()
	check(not hider.hide["on"] and out_spot.has("x"), "stepping out puts the body in front of the locker")
	# Registered absence makes the chase permanent.
	var abs_pm := CampusData.make_patrol()
	abs_pm.reset()
	abs_pm.registered_absence("1:0")
	check(abs_pm.pat["permanent"] and abs_pm.pat["behavior"] == "chase", "an unhonoured registration starts the permanent chase")
	abs_pm.rescued()
	check(not abs_pm.pat["permanent"] and is_equal_approx(float(abs_pm.pat["safety"]), 3.6), "rescue clears the permanent chase and grants 3.6 s")
	# Region report: standing in the network core queues an investigation.
	var zone_pm := CampusData.make_patrol()
	zone_pm.reset()
	zone_pm.elevator = pm.elevator
	var l3: Dictionary = CampusData.layout("lab3")
	_patrol_run(zone_pm, _pctx("lab3", CampusGeometry.tile_center(l3, 41, 5), {"need_where": "自由"}), 0.2)
	check(zone_pm.pat["lastRegion"] == "lab3:servers" and (zone_pm.pat["queue"] as Array).size() + (1 if zone_pm.pat["investigation"] != null else 0) == 1, "entering the server room is reported once")
	# Save round trip.
	var snap_data: Dictionary = JSON.parse_string(JSON.stringify(chaser.capture()))
	check(chaser.validate(snap_data).is_empty(), "patrol state survives JSON")
	var again := CampusData.make_patrol()
	again.reset()
	again.restore(snap_data)
	check(again.pat["room"] == chaser.pat["room"] and absf(float(again.pat["x"]) - float(chaser.pat["x"])) < 0.001, "patrol position restores")
	snap_data["pat"]["x"] = "far"
	check(not chaser.validate(snap_data).is_empty(), "garbage patrol numbers are refused")


## Route index whose previous node is `from` and next node is `to` (the patroller walks from -> to).
func _route_towards(from: String, to: String, pm: PatrolModule) -> int:
	for i in range(1, pm.route_nodes.size()):
		if pm.route_nodes[i - 1] == from and pm.route_nodes[i] == to:
			return i
	return 1


func _test_achievements() -> void:
	var ach := AchievementsModule.new(25)
	ach.reset()
	check(ach.fact({"kind": "day", "day": 2}) == ["n.day2"] and ach.unlocked.has("n.day2"), "reaching day 2 unlocks 熬过第一天")
	check(ach.fact({"kind": "day", "day": 2}).is_empty(), "an entry unlocks once")
	check(ach.fact({"kind": "anomaly", "phase": "start", "id": "rain", "public": true}).has("n.anomaly"), "the first anomaly unlocks 看见了")
	check(ach.fact({"kind": "anomaly", "phase": "end", "id": "rain", "survived": true, "lethal": true}).has("n.survive") and ach.sets["lethal"].has("rain"), "surviving a lethal anomaly unlocks 还活着 and collects it")
	check(not ach.fact({"kind": "anomaly", "phase": "end", "id": "moth", "survived": true, "lethal": true}).has("n.survive") and not ach.sets["lethal"].has("moth"), "an anomaly that never started is not counted")
	for id: String in ["moth", "exercise", "rite"]:
		ach.fact({"kind": "anomaly", "phase": "start", "id": id, "public": true})
		ach.fact({"kind": "anomaly", "phase": "end", "id": id, "survived": true, "lethal": true})
	check(ach.unlocked.has("e.lethal4") and ach.progress("e.lethal4")["n"] == 4, "four lethal anomalies survived unlock 见识")
	ach.fact({"kind": "anomaly", "phase": "start", "id": "cola", "public": false})
	check(not ach.sets["anomalies"].has("cola") and ach.sets["anomalies"].size() == 4, "non-public anomalies are not collected in the public book")
	check(ach.fact({"kind": "inspection", "day": 1, "slot": 0, "compliant": true}).has("n.inspection"), "a compliant inspection unlocks 按时到场")
	check(not ach.fact({"kind": "inspection", "day": 1, "slot": 1, "compliant": false}).has("e.attendance"), "a missed inspection is no full attendance")
	ach.fact({"kind": "inspection", "day": 2, "slot": 0, "compliant": true})
	check(ach.fact({"kind": "inspection", "day": 2, "slot": 1, "compliant": true}).has("e.attendance"), "both inspections of a day unlock 全勤")
	check(ach.fact({"kind": "patrol", "what": "lost"}) == ["n.lost"] and ach.fact({"kind": "patrol", "what": "locker"}) == ["n.locker"], "the patrol entries unlock")
	check(ach.fact({"kind": "wake"}) == ["n.wake"] and ach.fact({"kind": "protect"}) == ["n.saved"] and ach.saved, "wake and rescue unlock, the rescue is remembered")
	var ends := ach.fact({"kind": "ending", "id": "face", "day": 1, "diff": "hard"})
	check(ends.has("e.end_face") and ends.has("e.day1") and ends.has("e.hard") and ends.has("p.hard_day1") and ends.has("e.whitelist") and not ends.has("p.oneshot"), "a hard day-1 whitelist ending unlocks its entries but not 一命 after a rescue")
	var clean := AchievementsModule.new(25)
	clean.reset()
	check(clean.fact({"kind": "ending", "id": "face", "day": 3, "diff": "hard"}).has("p.oneshot"), "a hard ending without any rescue unlocks 一命")
	clean.face_wrong = 1
	var wrong := AchievementsModule.new(25)
	wrong.reset()
	wrong.face_wrong = 1
	check(not wrong.fact({"kind": "ending", "id": "face", "day": 2, "diff": "easy"}).has("e.whitelist"), "a wrong answer spoils 三道全对")
	check(not wrong.fact({"kind": "ending", "id": "unknown", "day": 1, "diff": "easy"}).has("e.day1"), "only public endings count")
	var walk := AchievementsModule.new(25)
	walk.reset()
	for id: String in AchievementsModule.EXPLORE:
		walk.fact({"kind": "room", "id": id})
	check(not walk.unlocked.has("e.explore"), "the dorms are still missing")
	walk.fact({"kind": "room", "id": "dorm2"})
	check(not walk.unlocked.has("e.explore"), "one of the two dorm groups is not enough")
	check(walk.fact({"kind": "room", "id": "dorm5"}).has("e.explore"), "every floor plus both dorm groups unlocks 踏遍校园")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(walk.capture()))
	var back := AchievementsModule.new(25)
	back.reset()
	check(back.validate(saved).is_empty(), "run facts survive JSON")
	back.restore(saved)
	check(back.rooms.has("dorm5") and back.rooms.size() == walk.rooms.size(), "run facts restore")
	var prof: Dictionary = JSON.parse_string(JSON.stringify(ach.profile()))
	var again := AchievementsModule.new(25)
	again.load_profile(prof)
	check(again.unlocked.size() == ach.unlocked.size() and again.sets["lethal"].size() == 4, "the profile survives JSON")
	again.load_profile({"unlocked": {"h.secret": true, "n.day2": true}})
	check(again.unlocked.size() == 1 and again.unlocked.has("n.day2"), "unknown or non-public ids in a profile are dropped")
	check(ach.points() > 0 and not AchievementsModule.LIST.keys().any(func(k: String) -> bool: return k.begins_with("h.")), "the points count and the public table has no hidden entries")
	var rows := ach.entries()
	check(rows.size() == AchievementsModule.LIST.size() and rows.filter(func(r: Dictionary) -> bool: return not r["unlocked"] and r["memo"] != "").is_empty(), "locked entries show no memory line")


func _gctx(x: float, y: float, extra: Dictionary = {}) -> Dictionary:
	var g := CampusData.layout("garage1")
	var c := {"scene": "garage1", "x": x, "y": y, "ang": 0.0, "run": false, "torch": false, "has_key": true, "dead": false, "enter_cool": 0.0, "busy": false,
		"can_stand": func(p: Vector2) -> bool: return CampusGeometry.tile_at(g, p) != "#" and CampusGeometry.tile_at(g, p) != "V"}
	c.merge(extra, true)
	return c


func _test_garage_rules() -> void:
	var g := CampusData.layout("garage1")
	var cars := GarageModule.new(g)
	cars.reset()
	cars.set_seed(5)
	var right := cars.car_right_cell()
	var all: Array = cars._cars()
	check(all.size() == 16 and all.has(right) and int(right.split(":")[0]) <= 24, "the right car is one of the 8 cars farthest from the entrance")
	check(cars.car_right_cell() == right, "the right car stays the same for the run")
	check(GarageModule.car_name(12, 4) == "鄂A·F" + str(3100 + 12 * 31 + 4), "plates follow carName")
	# The thing appears in the driveway and walks to you in the dark.
	var east := Vector2(float(g["ox"]) + 55.5 * 9.0, float(g["oy"]) + 13.5 * 9.0)
	cars.set_context(_gctx(east.x, east.y))
	cars.tick(0.1)
	check(bool(cars.roam["on"]) and cars.roam_visible(), "entering the garage puts the thing in the driveway")
	var start := Vector2(float(cars.roam["x"]), float(cars.roam["y"]))
	for _i in 120:
		cars.tick(0.1)
	check(Vector2(float(cars.roam["x"]), float(cars.roam["y"])).distance_to(east) < start.distance_to(east), "in the dark it comes closer")
	var e := cars.take_events()
	check(e.any(func(x: Dictionary) -> bool: return x["kind"] == "step"), "its steps are heard")
	# The torch held on it for 1.6 s sends it away.
	cars.roam["x"] = east.x - 120.0
	cars.roam["y"] = east.y
	cars.roam["stage"] = "approach"
	cars.set_context(_gctx(east.x, east.y, {"torch": true, "ang": PI}))
	for _i in 17:
		cars.tick(0.1)
	e = cars.take_events()
	check(cars.roam["stage"] == "wait" and not cars.roam_visible() and e.any(func(x: Dictionary) -> bool: return x["kind"] == "fact" and x["what"] == "torch"), "the torch held on it makes it vanish")
	check(_notices(e).has("我：光扫过去，它就没了。"), "and says so once")
	cars.roam["waitT"] = 0.05
	cars.set_context(_gctx(east.x, east.y))
	cars.tick(0.1)
	check(cars.roam["stage"] == "approach" and Vector2(float(cars.roam["x"]), float(cars.roam["y"])).distance_to(east) > 250.0, "it comes back far away")
	# Touching it in the dark kills.
	cars.roam["x"] = east.x - 10.0
	cars.roam["y"] = east.y
	cars.roam["litAcc"] = 0.0
	cars.take_events()
	cars.tick(0.05)
	e = cars.take_events()
	check(e.any(func(x: Dictionary) -> bool: return x["kind"] == "kill" and x["source"] == "garage"), "walking into it in the dark is the garage death")
	cars.set_context(_gctx(east.x, east.y, {"enter_cool": 0.5}))
	cars.tick(0.05)
	check(not cars.take_events().any(func(x: Dictionary) -> bool: return x["kind"] == "kill"), "not right after entering the room")
	# The coin lures it.
	var coin := GarageModule.new(g)
	coin.reset()
	coin.set_context(_gctx(east.x, east.y, {"ang": PI}))
	coin.tick(0.1)
	check(coin.throw_coin() and coin.lure != null and float(coin.lure["x"]) < east.x - 50.0, "the coin rolls ahead and lies there for 8 s")
	coin.set_context(_gctx(0, 0, {"scene": "canteen1"}))
	check(not coin.throw_coin() and _notices(coin.take_events()).has("我：要买饭就去打饭窗口，要买东西就去售货机。"), "outside the garage the coin is kept")
	# Trying cars: the thing nearby kills, a wrong car is remembered, the right one starts the drive.
	var drive := GarageModule.new(g)
	drive.reset()
	drive.set_seed(5)
	var rc := drive.car_right_cell().split(":")
	var wrong: String = all.filter(func(x: String) -> bool: return x != drive.car_right_cell())[0]
	drive.set_context(_gctx(east.x, east.y, {"has_key": false}))
	drive.use_car(int(rc[0]), int(rc[1]))
	check(_notices(drive.take_events()).has("我：车门锁着。"), "without the key the doors are locked")
	drive.roam["on"] = true
	drive.roam["stage"] = "approach"
	drive.roam["x"] = east.x - 50.0
	drive.roam["y"] = east.y
	drive.set_context(_gctx(east.x, east.y))
	drive.use_car(int(rc[0]), int(rc[1]))
	check(drive.take_events().any(func(x: Dictionary) -> bool: return x["kind"] == "kill" and x["source"] == "car_entry"), "opening a door with it close by is the back-seat death")
	drive.roam["stage"] = "wait"
	drive.roam["x"] = -1e6
	var wc := wrong.split(":")
	drive.inspect_car(int(wc[0]), int(wc[1]))
	var asked := drive.take_events()
	check(asked.back()["kind"] == "choice" and String(asked.back()["text"]).begins_with(GarageModule.car_name(int(wc[0]), int(wc[1]))), "looking at a car offers to try the key")
	drive.choose(0)
	check(drive.job != null and _notices(drive.take_events()).has("我：我把钥匙插进锁孔，慢慢地拧……"), "trying the key is a 1.6 s hold")
	drive.set_context(_gctx(east.x + 8.0, east.y))
	drive.tick(0.1)
	check(drive.job == null and _notices(drive.take_events()).has("我：手一松，钥匙从锁孔里滑了出来。"), "stepping away drops the key")
	drive.set_context(_gctx(east.x, east.y))
	drive.use_car(int(wc[0]), int(wc[1]))
	for _i in 17:
		drive.tick(0.1)
	check(drive.car_tried.has(wrong) and not drive.driving(), "the wrong car is remembered")
	drive.take_events()
	drive.use_car(int(wc[0]), int(wc[1]))
	check(_notices(drive.take_events()).has("我：这辆试过了。不是它。"), "a tried car is not tried again")
	drive.use_car(int(rc[0]), int(rc[1]))
	for _i in 17:
		drive.tick(0.1)
	var go := drive.take_events()
	check(drive.driving() and drive.car_used and go.any(func(x: Dictionary) -> bool: return x["kind"] == "drive") and go.any(func(x: Dictionary) -> bool: return x["kind"] == "fact" and x["what"] == "drive" and x["tried"] == 1), "the right car starts the drive")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(drive.capture()))
	var back := GarageModule.new(g)
	back.reset()
	check(back.validate(saved).is_empty(), "garage state survives JSON")
	back.restore(saved)
	check(back.driving() and back.car_tried.has(wrong) and back.car_right_cell() == drive.car_right_cell(), "and restores")
	saved["car_right"] = "1:1"
	check(not back.validate(saved).is_empty(), "a right car that is not a car is refused")
	# The drive itself (domain/car-chase.js).
	var d := CarChaseRules.new_state()
	var r := CarChaseRules.step(d, {"throttle": false}, 1.0)
	check(float(d["pursuit"]) == 3.0 and not r.has("failure"), "standing still lets the pursuit close in")
	d = CarChaseRules.new_state()
	d["distance"] = 44.0
	d["speed"] = 10.0
	r = CarChaseRules.step(d, {"throttle": true}, 0.2)
	check(int(d["hp"]) == 2 and r["events"][0]["type"] == "hit", "a barrier in the lane costs a life")
	d = CarChaseRules.new_state()
	d["distance"] = 149.0
	d["speed"] = 10.0
	d["nextObstacle"] = 3
	r = CarChaseRules.step(d, {"throttle": true}, 0.2)
	check(r.has("failure") and float(r["failure"]["checkpoint"]) == 120.0, "the wrong side at a fork leads back to school")
	CarChaseRules.reset_to(d, 120.0)
	check(int(d["hp"]) == 3 and int(d["nextObstacle"]) == 3 and int(d["nextFork"]) == 0, "a failure goes back to the checkpoint")
	d = CarChaseRules.new_state()
	d["distance"] = 319.0
	d["speed"] = 10.0
	d["x"] = -2.0
	d["nextObstacle"] = 6
	d["nextFork"] = 2
	check(CarChaseRules.step(d, {"throttle": true}, 0.2).get("won", false), "past 320 m with both forks right is out")


func _fctx(scene: String, extra: Dictionary = {}) -> Dictionary:
	var bag: Array = extra.get("bag", [])
	var c := {"scene": scene, "x": 0.0, "y": 0.0, "ang": 0.0, "tsec": 700.0, "clock": 700.0, "meal": false, "rest_mul": 1.0, "exam": false,
		"has": func(id: String) -> bool: return bag.has(id),
		"add": func(id: String) -> bool:
			if bag.has(id) or bag.size() >= 8:
				return false
			bag.append(id)
			return true,
		"remove": func(id: String) -> void: bag.erase(id),
		"anomaly": {}, "busy": false}
	c.merge(extra, true)
	c["has"] = func(id: String) -> bool: return bag.has(id)
	return c


func _of_kind(events: Array, kind: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e["kind"] == kind)


func _spot(room_id: String, at: Array) -> Vector2:
	var r := CampusData.layout(room_id)
	return Vector2(float(r["ox"]) + (float(at[0]) + 0.5) * float(r["tw"]), float(r["oy"]) + (float(at[1]) + 0.5) * float(r["th"]))


func _bctx(scene: String, at: Vector2, bag: Array, extra: Dictionary = {}) -> Dictionary:
	var c := _fctx(scene, {"bag": bag, "x": at.x, "y": at.y})
	c.merge({"day": 2, "tsec": 1100.0, "diff": "easy", "dead": false, "hiding": false, "night": false, "anomaly_active": false, "anomaly_id": "",
		"inspection_pending": false, "inspection_quiet": false, "gate_n": Vector2(1028, 190)}, true)
	c.merge(extra, true)
	return c


func _test_broadcast_rules() -> void:
	var rooms := CampusData.rooms()
	var radio := BroadcastModule.new(rooms, CampusData.patrol_nav())
	radio.reset()
	radio.set_seed(42)
	check(BroadcastModule.hash01(42, "false-notice") == BroadcastModule.hash01(42, "false-notice") and BroadcastModule.hash01(42, "a") != BroadcastModule.hash01(42, "b"), "the route hash is stable per seed")
	check(BroadcastModule.in_window(2, 1040.0) and not BroadcastModule.in_window(1, 1100.0) and not BroadcastModule.in_window(2, 1339.0 + 1.0), "the reading window: day 2 on, 17:20 to lights out")
	var bag: Array = []
	var station := _spot("admin2", BroadcastModule.STATION)
	# The pieces.
	radio.set_context(_bctx("admin5", _spot("admin5", [6, 2]), bag))
	check(radio.use_here() and bag.has("archivekey"), "the archive key is in the fifth-floor office")
	radio.set_context(_bctx("gear1", _spot("gear1", [3, 1]), bag))
	check(radio.use_here() and bag.has("broadcastfuse") and bag.has("snack") and bool(radio.b["boxSnack"]), "the spare fuse and a snack are in the gear room")
	radio.set_context(_bctx("guard1", _spot("guard1", [2, 4]), bag, {"night": true}))
	check(radio.use_here() and bag.has("broadcastkey"), "at night the guard's register gives the station key")
	radio.set_context(_bctx("admin2", station, bag))
	check(radio.use_here() and radio.take_events().any(func(e: Dictionary) -> bool: return e["kind"] == "choice"), "the station opens its menu")
	radio.choose(0)
	check(bool(radio.b["book"]), "the log book is read")
	radio.menu()
	radio.take_events()
	radio.choose(1)
	check(bool(radio.b["fuse"]) and not bag.has("broadcastfuse"), "the fuse is installed")
	# Page 1: the archive cabinet, opened with the key, a held search, then the page.
	radio.set_context(_bctx("admin1", _spot("admin1", [46, 2]), bag))
	radio.use_here()
	var ev := radio.take_events()
	check(not bag.has("archivekey") and bool(radio.b["archiveOpen"]) and _of_kind(ev, "job")[0]["seconds"] == 1.4, "the key opens the cabinet and the page takes 1.4 s")
	radio.job_done(0)
	var page: Dictionary = _of_kind(radio.take_events(), "choice")[0]
	check(String(page["text"]).contains("蓝黑墨水 · 第二天"), "the page shows its ink and date")
	radio.choose(0)
	check(bag.has("notice1"), "the first page is taken")
	# Page 2: the piano lock.
	radio.set_context(_bctx("lab5", _spot("lab5", [5, 1]), bag, {"clock": 900.0}))
	radio.use_here()
	radio.take_events()
	radio.choose(1)
	check(int(radio.b["pianoFails"]) == 1 and (radio.b["piano"] as Array).is_empty(), "a wrong note resets the tune")
	for pick: int in [0, 2, 1, 3]:
		radio.take_events()
		radio.choose(pick)
	var piano_ev := radio.take_events()
	check(_of_kind(piano_ev, "choice").size() >= 1 and String(_of_kind(piano_ev, "choice").back()["text"]).contains("琴凳里夹着通知稿"), "1 · 3 · 2 · 5 opens the piano bench")
	radio.choose(0)
	check(bag.has("notice2"), "the second page is taken")
	# Page 3 at night, page 4 with a coin and the back to the stairs.
	radio.set_context(_bctx("guard1", _spot("guard1", [2, 4]), bag, {"night": false}))
	check(not radio.use_here(), "by day the register is behind the night window")
	radio.set_context(_bctx("guard1", _spot("guard1", [2, 4]), bag, {"night": true}))
	radio.use_here()
	radio.take_events()
	radio.job_done(2)
	radio.take_events()
	radio.choose(0)
	check(bag.has("notice3"), "the third page is taken at night")
	var roof := _spot("teach6", [20, 2])
	radio.set_context(_bctx("teach6", roof, bag, {"ang": 0.0}))
	radio.use_here()
	check(_notices(radio.take_events()).has("喇叭箱的螺丝槽很宽，需要一枚硬币。"), "the speaker box needs a coin")
	bag.append("coin")
	var stairs := Vector2(float(rooms["teach6"]["ox"]) + 12.5 * float(rooms["teach6"]["tw"]), float(rooms["teach6"]["oy"]) + 16.5 * float(rooms["teach6"]["th"]))
	var toward := atan2(stairs.y - roof.y, stairs.x - roof.x)
	radio.set_context(_bctx("teach6", roof, bag, {"ang": toward}))
	radio.use_here()
	check(_notices(radio.take_events()).has("喇叭箱背面的字：「拧螺丝时，背对楼梯口。」"), "facing the stairs is refused")
	radio.set_context(_bctx("teach6", roof, bag, {"ang": toward + PI}))
	radio.use_here()
	check(_of_kind(radio.take_events(), "job")[0]["seconds"] == 2.0, "with the back to the stairs it takes 2 s")
	radio.job_done(3)
	radio.take_events()
	radio.choose(0)
	check(bag.has("notice4") and radio.assembled(), "all four pages")
	# Reading.
	radio.set_context(_bctx("admin2", station, bag, {"tsec": 1000.0}))
	check(not radio.hold(true) and radio.reason() == "记录本：第二天起，第八节下课后、熄灯前播出。", "outside the window the microphone stays off")
	radio.set_context(_bctx("admin2", station, bag))
	radio.select("notice2")
	check(radio.hold(true), "in the window reading starts")
	radio.tick(0.5)
	check(not radio.held and _notices(radio.take_events()).has("页码不对，得从当前这一段开始。"), "the wrong page stops the reading")
	for n in 4:
		radio.select("notice%d" % (n + 1))
		radio.hold(true)
		for _i in 16:
			radio.tick(1.0)
	check(radio.b["phase"] == "bell" and int(radio.b["completed"]) == 4 and int(radio.b["attemptDay"]) == 2, "four pages of 15 s ring the 60-second bell")
	var ev2 := radio.take_events()
	check(not _of_kind(ev2, "bell_start").is_empty(), "the bell starts")
	radio.set_context(_bctx("out", Vector2(1028, 190), bag))
	var c0 := radio.crowd()
	for _i in 20:
		radio.tick(1.0)
	var c1 := radio.crowd()
	check(not c0.is_empty() and Vector2(float(c1["x"]), float(c1["y"])).distance_to(Vector2(1028, 205)) < Vector2(float(c0["x"]), float(c0["y"])).distance_to(Vector2(1028, 205)), "the crowd walks to the north gate")
	radio.set_context(_bctx("out", Vector2(float(c1["x"]), float(c1["y"])), bag))
	check(radio.cover(), "next to the crowd the player is covered")
	for _i in 30:
		radio.tick(1.0)
	var c2 := radio.crowd()
	radio.set_context(_bctx("out", Vector2(float(c2["x"]), float(c2["y"])), bag))
	radio.tick(0.1)
	check(_of_kind(radio.take_events(), "ending").size() == 1, "walking out with the crowd is 《放学》")
	# The red page and the end of the bell.
	var red := BroadcastModule.new(rooms, CampusData.patrol_nav())
	red.reset()
	red.b["book"] = true
	red.b["fuse"] = true
	var kit: Array = ["notice1", "notice2", "notice3", "notice4", "notice_fake"]
	red.set_context(_bctx("admin2", station, kit))
	red.select("notice_fake")
	red.hold(true)
	red.tick(1.0)
	red.tick(1.1)
	check(_of_kind(red.take_events(), "kill")[0]["source"] == "misread", "reading the red page is the misread death")
	red.b["phase"] = "bell"
	red.b["bell"] = 0.5
	red.b["completed"] = 4
	red.tick(1.0)
	check(red.b["phase"] == "collect" and int(red.b["completed"]) == 0, "when the bell stops the pages wait for tomorrow")
	# Calls on the speakers.
	var calls := BroadcastModule.new(rooms, CampusData.patrol_nav())
	calls.reset()
	calls.set_context(_bctx("teach1", Vector2.ZERO, []))
	check(calls.announce(false, 0) and calls.b["current"]["room"] == "lab4", "a false call names a room")
	calls.set_context(_bctx("admin2", station, []))
	check(calls.verify() and _of_kind(calls.take_events(), "fact")[0]["real"] == false, "the log book shows it was false")
	calls.set_context(_bctx("lab4", Vector2.ZERO, []))
	calls.tick(5.0)
	calls.tick(5.0)
	var drained := calls.take_events()
	check(_notices(drained).has("喇叭里开始念你的名字。啸叫越来越尖——先离开这间屋子。") and not _of_kind(drained, "san").is_empty(), "the false call's room drains SAN after 8 s")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(radio.capture()))
	var back := BroadcastModule.new(rooms, CampusData.patrol_nav())
	back.reset()
	check(back.validate(saved).is_empty(), "the broadcast state survives JSON")
	back.restore(saved)
	check(bool(back.b["book"]) and bool(back.b["fuse"]) and back.seed_value == 42, "and restores")


## The commands that solve the terminal for this puzzle (the intended reading of the files).
func _solve_lines(puzzle: Dictionary) -> Array:
	var a: Dictionary = CampusTerminal.make(String(puzzle["runSeed"]), int(puzzle["attemptId"]))["answer"]
	var body := "controller=%s\\ntransaction=%s\\ntoken=%s\\nclock=active\\nstop %s\\nstop %s\\nstop %s" % [a["controller"], a["tx"], a["token"], a["order"][0], a["order"][1], a["order"][2]]
	return ["campusctl select %s /school/assets.tsv" % a["controller"], "campusctl trace %s /school/runtime.log" % a["tx"],
		"edit /work/shutdown \"%s\"" % body, "campusctl validate /work/shutdown", "campusctl shutdown --confirm"]


func _test_phone_rules() -> void:
	# Energy.
	var d := PhoneEnergy.fresh()
	d["initialized"] = true
	check(absf(PhoneEnergy.rate(d, {"held": true}) + 1.0 / 6.0) < 1e-9 and absf(PhoneEnergy.rate(d, {"held": true, "classroom": true}) - 1.0 / 3.0) < 1e-9, "the phone drains 1/6 % a second and charges in the classroom")
	d["wireless"] = {"status": "running", "elapsed": 0.0, "target": 200.0}
	var ev := PhoneEnergy.advance(d, 31.0, {"held": true})
	check(ev.count("wirelessSignal") == 2 and absf(float(d["battery"]) - (100.0 - 31.0 / 3.0)) < 1e-6, "cracking drains twice as fast and signals every 15 s")
	ev = PhoneEnergy.advance(d, 200.0, {"held": true, "classroom": true})
	check(ev.has("connected") and bool(d["network"]) and d["download"]["status"] == "running", "a cracked network starts the container download")
	ev = PhoneEnergy.advance(d, 60.0, {"held": true, "classroom": true})
	check(ev.has("downloaded") and d["download"]["status"] == "complete", "the container takes 60 s")
	var flat := PhoneEnergy.fresh()
	flat["initialized"] = true
	flat["battery"] = 1.0
	ev = PhoneEnergy.advance(flat, 10.0, {"held": true})
	check(ev.has("off") and not bool(flat["powered"]) and ev.has("low5") and ev.has("low20"), "an empty battery switches the phone off with the warnings")
	ev = PhoneEnergy.advance(flat, 20.0, {"held": true, "classroom": true})
	check(ev.has("on") and bool(flat["powered"]), "charging back to 5 % switches it on")
	# The terminal.
	var t := CampusTerminal.fresh("abc", 1)
	check(CampusTerminal.make("abc", 1)["answer"] == CampusTerminal.make("abc", 1)["answer"] and CampusTerminal.make("abc", 1)["answer"] != CampusTerminal.make("abc", 2)["answer"], "the puzzle depends on the seed and the attempt")
	check(CampusTerminal.run(t, "cat /school/site.txt")["text"].begins_with("试点区域=Z"), "cat reads the school files")
	check(CampusTerminal.run(t, "cat /school/assets.tsv | grep controller | head -n 2")["text"].split("\n").size() == 2, "pipes work")
	check(CampusTerminal.run(t, "rm -rf /")["error"] and CampusTerminal.run(t, "cat x > y")["error"], "unknown commands and redirection are refused")
	check(CampusTerminal.run(t, "edit /school/x \"a\"")["text"].contains("只允许写 /work/"), "only /work is writable")
	check(CampusTerminal.run(t, "campusctl shutdown --confirm")["text"].contains("先通过 T1—T3"), "no shutdown before the checks")
	check(CampusTerminal.run(t, "campusctl select ctl-decoy /school/assets.tsv")["error"], "the decoy controller is refused")
	var out: Dictionary = {}
	for line: String in _solve_lines(t):
		out = CampusTerminal.run(t, line)
	check(out.get("request") == "shutdown" and t["validated"] != null, "reading the files right solves T1–T4")
	# The phone module.
	var net := PhoneModule.new()
	net.reset()
	net.set_seed(5)
	var held := {"held": true, "scene": "teach1", "x": 0.0, "y": 0.0, "dead": false, "classroom": false}
	net.set_context(held)
	net.phone_menu()
	check(net.take_events()[0]["labels"][0] == "无线接入 · 开始破解", "the phone shows its apps")
	net.phone_choose(0)
	check(net.device["wireless"]["status"] == "running" and float(net.device["wireless"]["target"]) >= 180.0 and float(net.device["wireless"]["target"]) <= 600.0, "cracking takes 180–600 s")
	net.tick(15.0)
	check(net.take_events().any(func(e: Dictionary) -> bool: return e["kind"] == "reveal"), "every 15 s it gives the position away")
	net.set_context({"held": true, "scene": "lab3", "x": 500.0, "y": 500.0, "dead": false})
	net.computer_choose(2, 500.0, 500.0)
	check(not net.terminal_open and net.take_events().any(func(e: Dictionary) -> bool: return e["kind"] == "toast" and String(e["text"]).begins_with("需要手机有电")), "the terminal needs the network and the container")
	net.device["network"] = true
	net.device["wireless"]["status"] = "complete"
	net.device["download"] = {"status": "complete", "elapsed": 60.0, "target": 60.0}
	check(net.open_terminal(500.0, 500.0) and net.connected_computer(), "with them the computer opens the terminal")
	for line: String in _solve_lines(net.puzzle):
		net.run_line(line)
	check(net.termination["status"] == "accepted" and float(net.termination["remaining"]) == 600.0, "the shutdown is accepted: survive ten minutes")
	net.set_context({"held": true, "scene": "lab3", "x": 540.0, "y": 500.0, "dead": false})
	net.tick(1.0)
	check(not net.connected_computer() and not net.terminal_open, "walking away from the computer disconnects it")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(net.capture()))
	var back := PhoneModule.new()
	back.reset()
	check(back.validate(saved).is_empty(), "the phone state survives JSON")
	back.restore(saved)
	check(back.termination["status"] == "accepted" and absf(float(back.termination["remaining"]) - 599.0) < 0.01, "the accepted shutdown keeps its countdown")
	saved["termination"]["requestId"] = "forged"
	check(not back.validate(saved).is_empty(), "a forged request is refused")
	net.tick(600.0)
	check(net.take_events().any(func(e: Dictionary) -> bool: return e["kind"] == "ending" and e["id"] == "cyber"), "ten minutes alive is 《网安仙人》")
	var dream := PhoneModule.new()
	dream.reset()
	dream.set_seed(9)
	var first: Dictionary = CampusTerminal.make(dream.run_seed, 1)["answer"]
	dream.dream()
	check(dream.attempt_id == 2 and CampusTerminal.make(dream.run_seed, dream.attempt_id)["answer"] != first and dream.termination["status"] == "idle", "a dream wake is a new attempt with a new puzzle")


func _test_talent_rules() -> void:
	var t := TalentModule.new()
	t.reset()
	check(TalentModule.KEYS.size() == 7 and t.name_of() == "没有天赋", "seven pickable talents; none by default")
	check(not t.car(false)["ok"] and t.car(true)["via"] == "key", "without the driving talent only the key opens a car")
	t.pick("drive")
	check(t.car(false)["via"] == "hotwire" and t.car(false)["sec"] == 4.8 and t.car(true)["sec"] == 1.6, "the driving talent hot-wires in 4.8 s, the key still wins")
	t.pick("night")
	check(t.danger_mul("garage") == 0.55 and t.danger_mul("night") == 0.55 and t.danger_mul("trash") == 1.0, "dark adaptation softens the garage and the night only")
	t.pick("ear")
	check(t.hear_range() == 1.5, "the ear talent hears 1.5 times as far")
	t.pick("immune")
	check(t.prevent_death() and not t.prevent_death() and t.pause_text().contains("已经用掉了"), "natural immunity works once")
	t.pick("code")
	check(t.face_remedy() and not t.face_remedy(), "the first wrong gate answer is forgiven once")
	t.pick("watch")
	t.tick_watch(1, 733.0, 30.0)
	check(t.take_events()[0]["text"] == "我：（看了一眼表）午饭开饭了。", "the watch glances before lunch")
	t.tick_watch(1, 734.0, 30.0)
	check(t.take_events().is_empty(), "once")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(t.capture()))
	var back := TalentModule.new()
	back.reset()
	check(back.validate(saved).is_empty(), "talent state survives JSON")
	back.restore(saved)
	check(back.id == "watch" and back.notified.has("1:735"), "and restores")
	check(not back.validate({"id": "secret"}).is_empty(), "unknown talents are refused")
	# Hooks in the other modules.
	var g := CampusData.layout("garage1")
	var cars := GarageModule.new(g)
	cars.reset()
	cars.set_seed(5)
	var all: Array = cars._cars()
	var wrong: String = all.filter(func(x: String) -> bool: return x != cars.car_right_cell())[0]
	var east := Vector2(float(g["ox"]) + 55.5 * 9.0, float(g["oy"]) + 13.5 * 9.0)
	cars.set_context(_gctx(east.x, east.y, {"has_key": false, "hotwire": true}))
	cars.use_car(int(wrong.split(":")[0]), int(wrong.split(":")[1]))
	check(cars.job != null and float(cars.job["dur"]) == 4.8 and _notices(cars.take_events()).has("我：我弯下腰去摸方向盘底下的线……这要一会儿。"), "hot-wiring takes 4.8 s")
	var rt := RoutesModule.new(CampusData.campus())
	rt.reset()
	var forgiven := [true]
	rt.face_remedy = func() -> bool:
		var first: bool = forgiven[0]
		forgiven[0] = false
		return first
	rt.hacked = true
	rt.data_synced = true
	rt.use_gate("w", 1)
	rt.take_events()
	var q: Dictionary = RoutesModule.QUESTIONS[rt.face_quiz["order"][0]]
	rt.choose((int(q["answer"]) + 1) % 3, "easy")
	check(float(rt.take_events()[0]["amount"]) == 0.0, "the remedy takes no SAN for the first wrong answer")
	rt.choose(0, "easy")
	rt.take_events()
	var q2: Dictionary = RoutesModule.QUESTIONS[rt.face_quiz["order"][0]]
	rt.choose((int(q2["answer"]) + 1) % 3, "easy")
	check(float(rt.take_events()[0]["amount"]) < 0.0, "the second wrong answer costs SAN again")
	var fate := StoryModule.new()
	fate.reset()
	var saved_by := fate.kill("x", "grip", "patrol", {"day": 2, "immune": true})
	check(saved_by.get("protected") == "immune" and not fate.dead, "immunity turns a death aside")
	var day := SchoolModule.new(CampusData.rooms(), CampusData.layout("out"), CampusData.campus())
	day.reset()
	day.danger_mul = func(_k: String) -> float: return 0.55
	var before := day.san
	day.step(1.0, {"world_id": "garage1", "w": Vector2.ZERO, "calendar": false})
	check(absf((before - day.san) - 0.55 * 0.55 * float(day.pressure()["danger"])) < 0.02, "the garage drains 0.55 × 0.55 with dark adaptation")
	var ach := AchievementsModule.new(25)
	ach.reset()
	for k: String in TalentModule.KEYS:
		ach.fact({"kind": "ending", "id": "face", "day": 3, "diff": "easy", "talent": k})
	check(ach.unlocked.has("p.talents") and ach.progress("p.talents")["n"] == 7, "seven talents each through a true ending: 七种活法")


func _test_fake_normal_rules() -> void:
	var f := FakeNormalModule.new()
	f.reset()
	f.set_seed(1)
	f.day_two()
	check(not f.active(), "without the note day 2 is ordinary")
	f.fn["roll"] = 1
	f.lights_out_note()
	check(bool(f.fn["note"]) and f.take_events()[0]["text"].contains("笑时莫出声"), "the folded note at lights out on day 1")
	f.day_two()
	check(f.active() and f.take_events()[0]["text"].begins_with("我：第二天。"), "a rolled note makes day 2 fake normal")
	f.tick(11.0, {"tag": "teach"})
	var ask := f.take_events()
	check(ask[0]["kind"] == "choice" and ask[0]["labels"] == ["笑一下", "不笑，装作没这回事"], "an everyday moment asks to laugh")
	f.choose(1)
	check(float(f.fn["v"]) == 5.0 and f.take_events()[0]["text"].begins_with("其实——"), "holding it in adds 5 and shows what was real")
	for _i in 3:
		f.tick(40.0, {"tag": "teach"})
		f.take_events()
		f.choose(1)
		f.take_events()
	f.tick(1.0, {"tag": "teach"})
	var done := f.take_events()
	check(not f.active() and done.any(func(e: Dictionary) -> bool: return e["kind"] == "fact" and e["laughs"] == 0), "four moments without laughing end the day quietly")
	var g := FakeNormalModule.new()
	g.reset()
	g.fn["note"] = true
	g.fn["roll"] = 1
	g.day_two()
	g.fn["v"] = 100.0
	g.tick(0.1, {"tag": "out"})
	check(g.take_events().any(func(e: Dictionary) -> bool: return e["kind"] == "kill" and e["source"] == "laugh"), "laughing to 100 is the laughing death")
	var ach := AchievementsModule.new(25)
	ach.reset()
	check(ach.fact({"kind": "fakeNormal", "done": true, "laughs": 0}).has("e.nolaugh") and not AchievementsModule.new(25).fact({"kind": "fakeNormal", "done": true, "laughs": 1}).has("e.nolaugh"), "笑时莫出声 only without a laugh")
	var fac := FacilitiesModule.new(CampusData.rooms(), CampusData.layout("out"), CampusData.campus())
	fac.reset()
	fac.set_context(_fctx("out", {"x": 1028.0, "y": 190.0, "gate_n_map": {"x": 514, "y": 95}}))
	fac.think()
	check(_notices(fac.take_events()).has("我：还没有头绪。先去看看学校里有什么。"), "no places marked, no ideas")
	fac.spots["front"] = true
	fac.spots["guard"] = true
	fac.think()
	var list: Dictionary = fac.take_events()[0]
	check(list["labels"] == ["拿那串车钥匙", "从正门走"], "marked places unlock their ideas")
	fac.choose(1)
	check(fac.take_events()[0]["labels"] == ["再想想", "就这么办"], "at the north gate the front-door idea asks once more")
	fac.choose(1)
	check(fac.take_events()[0]["source"] == "trap_out", "and walking out of the front gate is the trap")
	fac.set_context(_fctx("teach1", {"gate_n_map": {"x": 514, "y": 95}}))
	fac.think()
	fac.take_events()
	fac.choose(1)
	check(_notices(fac.take_events()).has("我：正门在北边。要走，得先走到北门的闸机前面。"), "away from the gate it only says where to go")


func _bodyctx(scene: String, w: Vector2, ang: float, extra: Dictionary = {}) -> Dictionary:
	var c := {"scene": scene, "x": w.x, "y": w.y, "ang": ang, "seated": false, "hiding": false, "stam": 100.0, "moving": false, "locked": false, "anomaly": false, "day": 1, "dead": false}
	c.merge(extra, true)
	return c


func _test_body_rules() -> void:
	var rooms := CampusData.rooms()
	var b := BodyModule.new(rooms)
	b.reset()
	var l1 := CampusData.layout("link1")
	var mid := CampusGeometry.tile_center(l1, 1, 10)
	b.set_context(_bodyctx("link1", mid, PI))
	check(b.target()["kind"] == "link" and b.hint() == "翻过栏杆 · 外侧悬空", "the bridge railing can be climbed")
	b.set_context(_bodyctx("link1", mid, 0.0))
	check(b.target().is_empty(), "facing along the bridge there is nothing to climb")
	var t6 := CampusData.layout("teach6")
	b.set_context(_bodyctx("teach6", CampusGeometry.tile_center(t6, 5, 1), -PI * 0.5))
	check(b.target()["kind"] == "roof", "the roof parapet can be climbed")
	b.set_context(_bodyctx("teach6", CampusGeometry.tile_center(t6, 5, 1), -PI * 0.5, {"stam": 4.0}))
	check(not b.vault() and _notices(b.take_events()).has("我：喘不过气来，先歇一下。"), "climbing costs 8 stamina")
	b.set_context(_bodyctx("teach6", CampusGeometry.tile_center(t6, 5, 1), -PI * 0.5))
	b.ask_vault()
	check(b.take_events()[0]["labels"] == ["翻过去", "算了"], "E asks first")
	check(b.vault() and b.busy(), "over the parapet")
	for _i in 14:
		b.tick(0.1)
	var ev := b.take_events()
	check(ev.any(func(e: Dictionary) -> bool: return e["kind"] == "kill" and e["source"] == "campus_fall"), "the roof is a fatal fall")
	var l := BodyModule.new(rooms)
	l.reset()
	l.set_context(_bodyctx("link1", mid, PI))
	l.vault()
	for _i in 10:
		l.tick(0.1)
	ev = l.take_events()
	check(ev.any(func(e: Dictionary) -> bool: return e["kind"] == "land") and l.injury == 45.0 and _notices(ev).has("我：我摔在地上。腿一阵剧痛，还能走。"), "off a bridge: the ground and +45 injury")
	check(l.speed_mul() == 0.9 and l.can_run() and absf(l.stamina_cap_drop() - 18.0) < 0.001, "injured: ×0.9, stamina cap −18")
	l.hurt(20.0, "test")
	check(l.speed_mul() == 0.8 and not l.can_run(), "badly injured: ×0.8 and no running")
	l.set_context(_bodyctx("link1", mid, PI))
	check(not l.vault() and _notices(l.take_events()).has("我：腿使不上劲，翻不过去。"), "and no climbing")
	check(l.use_medkit() and l.busy(), "a medkit starts a 4 s treatment")
	l.set_context(_bodyctx("link1", mid, PI, {"moving": true}))
	l.tick(0.5)
	check(l.treat == null and _notices(l.take_events()).has("我：包扎到一半被打断了。"), "moving interrupts it")
	l.use_medkit()
	l.set_context(_bodyctx("link1", mid, PI))
	for _i in 41:
		l.tick(0.1)
	ev = l.take_events()
	check(l.injury == 25.0 and ev.any(func(e: Dictionary) -> bool: return e["kind"] == "remove"), "a medkit heals 40")
	l.injury = 10.0
	for _i in 25:
		l.tick(1.0)
	check(l.injury < 10.0, "grazes heal standing still after 20 s")
	var a1 := CampusData.layout("admin1")
	var clinic := Vector2(float(a1["ox"]) + 6.0 * float(a1["tw"]), float(a1["oy"]) + 15.85 * float(a1["th"]))
	l.set_context(_bodyctx("admin1", clinic, 0.0, {"day": 3}))
	check(l.hint() == "医务室的药柜" and l.use_clinic() and l.take_events()[0]["kind"] == "give", "the clinic cabinet hands out a medkit")
	l.gave_medkit("3")
	l.use_clinic()
	check(_notices(l.take_events()).has("我：药柜里今天的急救包已经拿过了。"), "one a day")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(l.capture()))
	var back := BodyModule.new(rooms)
	back.reset()
	check(back.validate(saved).is_empty(), "injury survives JSON")
	back.restore(saved)
	check(absf(back.injury - l.injury) < 0.001 and back.med_day.has("3"), "and restores")


func _xctx(w: Vector2, extra: Dictionary = {}) -> Dictionary:
	var c := {"scene": "out", "x": w.x, "y": w.y, "day": 2, "tsec": 600.0, "dead": false, "busy": false}
	c.merge(extra, true)
	return c


func _test_exchange_rules() -> void:
	var x := ExchangeModule.new(CampusData.patrol_nav(), CampusData.layout("out"), CampusData.campus())
	x.reset()
	x.s["hit"] = 1
	x.set_context(_xctx(Vector2.ZERO, {"day": 1}))
	x.tick(1.0)
	check(x.s["phase"] == "none", "the visit waits for day 2")
	x.set_context(_xctx(Vector2.ZERO))
	x.tick(1.0)
	check(x.s["phase"] == "waiting" and _notices(x.take_events())[0].contains("国际交流团来访"), "on day 2 from 09:00 the speakers announce it")
	var leader: Vector2 = x.members()[0]
	x.set_context(_xctx(leader))
	check(x.hint() == "国际交流接待登记" and x.use_here(), "the leader takes registrations")
	var menu: Dictionary = x.take_events()[0]
	check(menu["labels"].size() == 2, "two language checks")
	x.choose(0)
	for i in ExchangeModule.QUESTIONS:
		x.take_events()
		var right := int(x._order("de")[i])
		x.choose(right if i < 3 else (right + 1) % 3)
	var ev := x.take_events()
	check(int(x.s["passed"]["de"]) == 0 and ev.any(func(e: Dictionary) -> bool: return e["kind"] == "san" and e["amount"] == -6.0), "three of five fails and costs 6 SAN")
	for lang: String in ["de", "fr"]:
		x.take_events()
		x.use_here()
		var labels: Array = x.take_events()[0]["labels"]
		var idx := 0
		for j in labels.size():
			if String(labels[j]).contains(ExchangeModule.EXAM[lang]["n"]):
				idx = j
		x.choose(idx)
		for i in ExchangeModule.QUESTIONS:
			x.take_events()
			x.choose(int(x._order(lang)[i]))
	ev = x.take_events()
	check(x.s["phase"] == "qualified" and ev.any(func(e: Dictionary) -> bool: return e["kind"] == "permit"), "both languages passed: qualified with the day's permit")
	check(x.hint() == "跟带队老师说：出发", "then the leader is ready to go")
	x.use_here()
	check(x.s["phase"] == "escort" and (x.s["search"] as Array).size() == 3, "departing starts the walk with three searchers")
	x.take_events()
	var arrived := false
	for _i in 2000:
		var tail: Vector2 = x.members()[x.members().size() - 1]
		x.set_context(_xctx(tail + Vector2(4, 0)))
		x.tick(0.25)
		if x.take_events().any(func(e: Dictionary) -> bool: return e["kind"] == "ending" and e["id"] == "international"):
			arrived = true
			break
	check(arrived, "staying with the group to the north gate is 《外国语学生》")
	var lost := ExchangeModule.new(CampusData.patrol_nav(), CampusData.layout("out"), CampusData.campus())
	lost.reset()
	lost.s["hit"] = 1
	lost.s["phase"] = "qualified"
	lost.set_context(_xctx(Vector2(5000, 5000)))
	lost.depart()
	lost.s["search"] = []
	for _i in 30:
		lost.tick(0.2)
	check(lost.s["phase"] == "over" and _notices(lost.take_events()).has("我：队伍拐过前面的楼角，不见了。我掉队了。"), "falling 9 m behind for 4 s loses the group")
	var multi := ExchangeModule.new(CampusData.patrol_nav(), CampusData.layout("out"), CampusData.campus())
	multi.reset()
	multi.s["hit"] = 1
	multi.s["phase"] = "waiting"
	multi.multilingual = true
	multi.set_context(_xctx(multi.members()[0]))
	multi.use_here()
	check(multi.take_events()[0]["labels"].size() == 3, "with the second languages there is a third option")
	multi.choose(0)
	check(multi.s["phase"] == "qualified" and multi.s["how"] == "multilingual", "which qualifies at once")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(x.capture()))
	var back := ExchangeModule.new(CampusData.patrol_nav(), CampusData.layout("out"), CampusData.campus())
	back.reset()
	check(back.validate(saved).is_empty(), "the visit survives JSON")
	back.restore(saved)
	check(back.s["phase"] == x.s["phase"] and int(back.s["passed"]["fr"]) == 1, "and restores")


func _test_day_rules() -> void:
	var d := DayModule.new()
	d.reset()
	d.set_seed(12345)
	check(DayModule.day_hash(12345, 3) == DayModule.day_hash(12345, 3) and DayModule.day_hash(12345, 3) != DayModule.day_hash(12345, 4), "the day hash is stable")
	check(d.ensure(1) == "none", "the first half-day is never special")
	var kinds := {}
	for day in range(2, 200):
		kinds[d.ensure(day)] = int(kinds.get(d.ensure(day), 0)) + 1
	var first_checkup := 999
	for day: String in d.day_events:
		if d.day_events[day] == "checkup":
			first_checkup = mini(first_checkup, int(day))
	check(int(kinds.get("anniversary", 0)) <= 1 and int(kinds.get("occupied", 0)) > 10 and int(kinds.get("checkup", 0)) <= 1 and first_checkup >= 3,
		"the anniversary and the checkup come at most once (checkup from day 3); occupied days happen")
	var occ := ""
	for day: String in d.day_events:
		if d.day_events[day] == "occupied":
			occ = day
			break
	check(not d.day_events.has(str(int(occ) + 1)) or d.day_events[str(int(occ) + 1)] != "occupied", "no two occupied days in a row")
	check(d.today(int(occ), 300.0) == "none" and d.today(int(occ), 800.0) == "occupied", "a special day counts from 07:20")
	check(d.closed("piano", int(occ), 800.0) and d.closed("pc", int(occ), 800.0) and d.lesson_bonus(int(occ), 800.0) == 2.0, "occupied closes the piano and the games and adds to the desk answer")
	var a := DayModule.new()
	a.reset()
	a.day_events = {"3": "anniversary"}
	check(a.drain_mul(3, 800.0) == 0.5 and a.drain_mul(4, 800.0) == 1.0, "the anniversary halves per-second drains")
	a.tick_day(3, 800.0)
	var said := a.take_events()
	check(said.any(func(e: Dictionary) -> bool: return e["kind"] == "notice" and String(e["text"]).contains("建校纪念日")), "the morning broadcast names the day")
	a.tick_day(3, 900.0)
	check(a.take_events().is_empty(), "once")
	# Lessons.
	var l := DayModule.new()
	l.reset()
	l.press({"available": false, "day": 1, "tsec": 710.0})
	check(l.take_events().is_empty(), "no desk question unless seated in class")
	l.press({"available": true, "day": 1, "tsec": 710.0, "room": "teach1"})
	var q: Dictionary = l.take_events()[0]
	var task: Dictionary = DayModule.TASKS[int(l.lessons[l.lesson_key]["task"])]
	check(q["menu"] == "lesson" and q["timer"] == 12.0 and q["labels"] == task["choices"], "R at the desk shows the 12-second question")
	l.answer(int(task["answer"]), {"day": 1, "tsec": 710.0})
	var ev := l.take_events()
	check(ev.any(func(e: Dictionary) -> bool: return e["kind"] == "san" and e["amount"] == 2.0) and ev.any(func(e: Dictionary) -> bool: return e["kind"] == "fact" and e["correct"]), "a right answer: +2 SAN and the note")
	l.press({"available": true, "day": 1, "tsec": 715.0, "room": "teach1"})
	check(l.take_events()[0]["menu"] == "wait", "a second R offers to study until the bell")
	l.start_wait(1, 715.0, "teach1")
	check(l.wait_allowed({"available": true, "day": 1, "tsec": 716.0, "room": "teach1"}) and not l.wait_allowed({"available": false, "day": 1, "tsec": 716.0, "room": "teach1"}), "studying stops when anything needs attention")
	var t := DayModule.new()
	t.reset()
	t.press({"available": true, "day": 2, "tsec": 600.0, "room": "teach1"})
	t.take_events()
	t.answer(-1, {})
	check(_notices(t.take_events()).has("我：老师把纸收走了。"), "letting the 12 seconds run out loses the question")
	var fac := FacilitiesModule.new(CampusData.rooms(), CampusData.layout("out"), CampusData.campus())
	fac.reset()
	fac.set_context(_fctx("lab5", {"closed": DayModule.CLOSED}))
	fac.rest("piano")
	check(_notices(fac.take_events())[0].contains("改上数学"), "on an occupied day the music room is locked")
	var ach := AchievementsModule.new(25)
	ach.reset()
	for i in DayModule.TASKS.size():
		ach.fact({"kind": "lesson", "task": i, "correct": true})
	check(ach.unlocked.has("n.desk") and ach.unlocked.has("e.notes"), "the desk notes: 看课桌 and 十张纸条")


func _test_checkup_rules() -> void:
	var rooms := CampusData.rooms()
	var t := TalesModule.new(rooms, CampusData.patrol_data()["route"]["nodes"])
	t.reset()
	var a1: Dictionary = rooms["admin1"]
	var ruler := Vector2(float(a1["ox"]) + 1.6 * float(a1["tw"]), float(a1["oy"]) + 15.45 * float(a1["th"]))
	var base := {"scene": "admin1", "x": ruler.x, "y": ruler.y, "day": 3, "special": "checkup", "seed": "abc"}
	var ctx := base.duplicate()
	ctx["tsec"] = 600.0
	t.set_context(ctx)
	t.tick(0.1)
	check(_notices(t.take_events()).has("广播：「第三节课体检。请各班同学到行政楼一楼医务室排队。」") and t.checkup_period() == "体检将至 · 行政楼一楼医务室" and t.hint() == "体检还没开始",
		"10:00 the broadcast; before 10:20 nobody is there")
	ctx["tsec"] = 612.0
	t.set_context(ctx)
	check(t.queue_on() and t.use_here() and not t.checkup_done(), "the queue stands from 10:10; the room is empty until 10:20")
	ctx["tsec"] = 625.0
	t.set_context(ctx)
	t.take_events()
	check(t.hint() == "体检（量身高、称体重）" and t.use_here() and t.checkup_done(), "in the window the rule or the scale is the checkup")
	var ev := t.take_events()
	check(ev.any(func(e: Dictionary) -> bool: return e["kind"] == "advance" and e["minutes"] == 5.0) and _notices(ev).any(func(n: String) -> bool: return n.contains("心率：0")), "five minutes and the form: height —, heart rate 0")
	ctx["tsec"] = 670.0
	t.set_context(ctx)
	t.tick(0.1)
	check(not t.take_events().any(func(e: Dictionary) -> bool: return e["kind"] == "viol"), "done: no penalty when it ends")
	var miss := TalesModule.new(rooms)
	miss.reset()
	var mctx := base.duplicate()
	mctx["scene"] = "teach1"
	mctx["tsec"] = 666.0
	miss.set_context(mctx)
	miss.tick(0.1)
	var mev := miss.take_events()
	check(mev.any(func(e: Dictionary) -> bool: return e["kind"] == "viol" and e["amount"] == 10.0) and mev.any(func(e: Dictionary) -> bool: return e["kind"] == "san" and e["amount"] == -8.0), "missed: 10 violations and −8 SAN")
	miss.tick(0.1)
	check(miss.take_events().is_empty(), "the penalty is once")
	var leave := TalesModule.new(rooms)
	leave.reset()
	mctx["on_leave"] = true
	leave.set_context(mctx)
	leave.tick(0.1)
	check(not leave.take_events().any(func(e: Dictionary) -> bool: return e["kind"] == "viol"), "on leave it is only marked absent")
	var saved := TalesModule.new(rooms)
	saved.restore(t.capture())
	saved.set_context(ctx)
	check(saved.checkup_done() and saved.validate(t.capture()) == "", "the checkup is saved")
	var other := base.duplicate()
	other["special"] = "none"
	other["tsec"] = 625.0
	var plain := TalesModule.new(rooms)
	plain.reset()
	plain.set_context(other)
	check(plain.hint() == "" and not plain.queue_on() and plain.checkup_period() == "", "on an ordinary day nothing is there")
	check(TalesModule.LINES.has(t.chart_line()), "the eye chart's last line is one of the public risks")
	# The patrol log pages.
	var seq := t.route_rooms()
	check(seq.size() > 6 and not seq.any(func(r: String) -> bool: return r.begins_with("stair_") or r.begins_with("link")), "the route floors leave out stairwells and links")
	var seg := t.note_segment(0)
	check(seg.size() == 6 and seq.has(seg[0]) and t.note_segment(0) == seg, "each page is six floors of the route, stable in a run")
	var a3: Dictionary = rooms["admin3"]
	var desk := Vector2(float(a3["ox"]) + 30.5 * float(a3["tw"]), float(a3["oy"]) + 3.5 * float(a3["th"]))
	t.set_context({"scene": "admin3", "x": desk.x, "y": desk.y, "day": 3, "tsec": 700.0, "seed": "abc"})
	check(t.hint() == "撕下来的一页纸" and t.use_here(), "a torn sheet in the admin3 drawer")
	var nev := t.take_events()
	check(_notices(nev).any(func(n: String) -> bool: return n.begins_with("值班表（撕下的一页）") and n.contains("若有事，另行处置。")) and t.hint() == "再看一眼值班表", "it reads the floors, then 'if anything, handle otherwise'")


func _test_tales_rules() -> void:
	var rooms := CampusData.rooms()
	var t := TalesModule.new(rooms)
	t.reset()
	var cr: Dictionary = rooms["canteen1"]
	var window := Vector2.ZERO
	var grid: Array = cr["grid"]
	for row in grid.size():
		for col in String(grid[row]).length():
			if String(grid[row]).substr(col, 1) == "k" and window == Vector2.ZERO:
				window = CampusGeometry.tile_center(cr, col, row)
	t.set_context({"scene": "canteen1", "x": window.x, "y": window.y + 12.0, "tsec": 1200.0, "clock": 1200.0, "tt": 10.0})
	check(t.hint() == "" and not t.use_here(), "before lights out the window is dark")
	t.set_context({"scene": "canteen1", "x": window.x, "y": window.y + 12.0, "tsec": 1345.0, "clock": 1345.0, "tt": 10.0})
	check(t.hint() == "亮着的窗口" and t.use_here(), "after lights out one window is lit")
	t.take_events()
	t.choose(0)
	var ev := t.take_events()
	check(ev.any(func(e: Dictionary) -> bool: return e["kind"] == "san" and e["amount"] == 40.0) and ev.any(func(e: Dictionary) -> bool: return e["kind"] == "tt" and e["amount"] == 25.0 and e["cap"] == 95.0)
		and ev.any(func(e: Dictionary) -> bool: return e["kind"] == "hold" and e["until"] == 1880.0), "a bowl: +40 SAN, +25 assimilation up to 95, held until 07:20")
	t.set_context({"scene": "canteen1", "x": window.x, "y": window.y + 12.0, "tsec": 1350.0, "clock": 1350.0, "tt": 35.0})
	t.use_here()
	check(_notices(t.take_events()).has("我：窗口里的人没有回头。「明天再来。」"), "one bowl a night")
	var day := SchoolModule.new(rooms, CampusData.layout("out"), CampusData.campus())
	day.reset()
	day.tt = 30.0
	day.tt_hold_until = day.game_clock() + 100.0
	day.step(1.0, {"world_id": "out", "w": Vector2(1000, 1000), "calendar": false})
	check(day.tt == 30.0, "assimilation does not fall back until morning")
	# The mirror.
	var m := TalesModule.new(rooms)
	m.reset()
	var spots := m.mirrors("teach1")
	check(not spots.is_empty(), "the basins in the teaching building have mirrors")
	var mirror: Dictionary = spots[0]
	var n: Vector2 = mirror["n"]
	var stand: Vector2 = mirror["w"] + n * 12.0
	var look := atan2(-n.y, -n.x)
	m.set_context({"scene": "teach1", "x": stand.x, "y": stand.y, "ang": look, "san": 50.0})
	for _i in 60:
		m.tick(0.1)
	check(m.raise == 0.0 and m.take_events().is_empty(), "with SAN 50 the reflection only lags")
	m.set_context({"scene": "teach1", "x": stand.x, "y": stand.y, "ang": look, "san": 10.0})
	for _i in 20:
		m.tick(0.1)
	check(m.raise > 0.9 and m.take_events().is_empty(), "below 20 it raises a hand first")
	for _i in 32:
		m.tick(0.1)
	check(m.take_events().any(func(e: Dictionary) -> bool: return e["kind"] == "kill" and e["source"] == "mirror"), "staring 3 s more is the mirror death")
	m.set_context({"scene": "teach1", "x": stand.x, "y": stand.y, "ang": look + PI, "san": 10.0})
	for _i in 60:
		m.tick(0.1)
	check(m.take_events().is_empty(), "looking away is safe")


func _test_speedrun_rules() -> void:
	check(Speedrun.fmt(3723456) == "01:02:03.45", "times read hh:mm:ss.cc")
	var sr := Speedrun.new()
	var rec := {}
	sr.arm("hard")
	check(sr.active() and sr.elapsed() == 0, "armed, not yet running")
	check(sr.fail("abandoned", rec).is_empty() and sr.run.is_empty() and rec.is_empty(), "leaving before the first move records nothing")
	sr.arm("easy")
	sr.start()
	sr.run["p0"] = Time.get_ticks_msec() - 61000
	sr.run["w0"] = Time.get_unix_time_from_system() - 61.0
	var res := sr.finish("face", rec)
	check(res["pb"] and res["rec"]["status"] == "finished" and int(res["rec"]["ms"]) >= 61000 and rec["best"].has(Speedrun.key("easy", "face")), "a finished route is a personal best")
	sr.arm("easy")
	sr.start()
	sr.run["p0"] = Time.get_ticks_msec() - 90000
	sr.run["w0"] = Time.get_unix_time_from_system() - 90.0
	check(not sr.finish("face", rec)["pb"] and (rec["recent"] as Array).size() == 2, "a slower run is recorded but is no best")
	sr.arm("easy")
	sr.start()
	check(sr.finish("secret", rec).is_empty(), "only the public routes stop the clock")
	check(Speedrun.rows(rec).size() == 12 + 2 and Speedrun.rows(rec)[4]["on"], "the records list every route per difficulty and the recent runs")
	var ach := AchievementsModule.new(25)
	ach.reset()
	check(ach.fact({"kind": "speedrun", "status": "finished", "route": "face", "ms": 600000}).has("p.fast") and ach.unlocked.has("e.speedrun"), "a 10-minute finish: 计时 and 赶在铃响前")


func _test_gaze_rules() -> void:
	var rooms := CampusData.rooms()
	var g := WindowGazeModule.new(rooms)
	g.reset()
	g.set_seed(4)
	check(g.windows("teach1").is_empty(), "the teaching building has no gaze windows")
	var room_id := ""
	var win: Dictionary = {}
	var stand := Vector2.ZERO
	var look_at := 0.0
	var ctx: Dictionary = {}
	for id: String in rooms:
		for w: Dictionary in g.windows(id):
			for dist: float in [40.0, 60.0, 90.0]:
				var st: Vector2 = w["p"] + Vector2(0, float(w["nz"]) * dist)
				var la := atan2(w["p"].y - st.y, w["p"].x - st.x)
				var probe := WindowGazeModule.new(rooms)
				probe.reset()
				probe.set_seed(1)
				var c := {"scene": id, "x": st.x, "y": st.y, "ang": la + PI * 0.5, "pitch": 0.0, "eye": 1.65, "now": 300.0, "san": 80.0, "drain_mul": 1.0}
				probe.set_context(c)
				probe.tick(0.1)
				if probe.s["ev"] != null and int(probe.s["ev"]["c"]) == int(w["c"]) and int(probe.s["ev"]["r"]) == int(w["r"]):
					room_id = id
					win = w
					stand = st
					look_at = la
					ctx = c
					break
			if room_id != "":
				break
		if room_id != "":
			break
	check(room_id != "", "outer-wall windows exist in the other buildings and can start the gaze")
	if room_id == "":
		return
	ctx["now"] = 100.0
	g.set_context(ctx)
	g.tick(0.1)
	check(g.s["ev"] == null, "not in the first 240 s")
	g.s["next"] = 240.0
	ctx["now"] = 300.0
	g.set_context(ctx)
	g.tick(0.1)
	var ev := g.take_events()
	check(ev.any(func(e: Dictionary) -> bool: return e["kind"] == "breath"), "a breath behind a window first")
	ctx["ang"] = look_at
	ctx["pitch"] = atan2(WindowGazeModule.EYE - 1.65, stand.distance_to(win["p"]) * CampusGeometry.U2M)
	g.set_context(ctx)
	for _i in 5:
		g.tick(0.1)
	ev = g.take_events()
	check(_notices(ev).has("我：……窗里有一双眼睛。我挪不开眼。"), "looking straight at it for 0.35 s catches the eye")
	for _i in 10:
		g.tick(0.1)
	ev = g.take_events()
	check(ev.any(func(e: Dictionary) -> bool: return e["kind"] == "pull") and ev.any(func(e: Dictionary) -> bool: return e["kind"] == "san" and e["amount"] < 0.0), "it pulls the view and drains SAN")
	ctx["pitch"] = -0.8
	g.set_context(ctx)
	for _i in 8:
		g.tick(0.1)
	ev = g.take_events()
	check(g.s["ev"] == null and ev.any(func(e: Dictionary) -> bool: return e["kind"] == "fact" and e["what"] == "escape"), "looking down 35° for 0.6 s breaks free")
	var d := WindowGazeModule.new(rooms)
	d.reset()
	d.s["ev"] = {"room": room_id, "c": win["c"], "r": win["r"], "t": 0.0, "contact": 0.0, "pull": 3.0, "away": 0.0, "pulled": true, "escaped": false}
	ctx["pitch"] = atan2(WindowGazeModule.EYE - 1.65, stand.distance_to(win["p"]) * CampusGeometry.U2M)
	ctx["san"] = 0.3
	d.set_context(ctx)
	d.tick(0.1)
	check(d.take_events().any(func(e: Dictionary) -> bool: return e["kind"] == "kill" and e["source"] == "window_gaze"), "drained to zero it is the window gaze death")


## Find a room, window and spot where a paper plane can be delivered; {} when none.
func _paper_spot(kind: String) -> Dictionary:
	var rooms := CampusData.rooms()
	for id: String in rooms:
		var probe := PaperPlaneModule.new(rooms)
		for w: Dictionary in probe._windows.windows(id):
			for dist: float in [40.0, 60.0, 80.0]:
				var st: Vector2 = w["p"] + Vector2(0, float(w["nz"]) * dist)
				var la := atan2(w["p"].y - st.y, w["p"].x - st.x)
				var room: Dictionary = rooms[id]
				var c := {"scene": id, "x": st.x, "y": st.y, "ang": la + PI, "now": 200.0, "busy": false,
					"can_stand": func(p: Vector2) -> bool: return CampusGeometry.tile_at(room, p) == "."}
				probe.reset()
				probe.roll(1)
				probe.set_context(c)
				if probe.start(kind) and int(probe.s["ev"]["c"]) == int(w["c"]):
					return {"room": id, "w": w, "stand": st, "look": la, "ctx": c}
	return {}


func _test_paper_rules() -> void:
	var rooms := CampusData.rooms()
	var hits := 0
	var danger := 0
	for i in 400:
		var r := PaperPlaneModule.new(rooms)
		r.reset()
		r.roll(i)
		if bool(r.s["roll"]["hit"]):
			hits += 1
			if r.s["roll"]["kind"] == "danger":
				danger += 1
	check(hits > 20 and hits < 70 and danger > 0 and danger < hits, "about one run in ten gets a paper plane, half of them dangerous")
	var spot := _paper_spot("peace")
	check(not spot.is_empty(), "a room with a visible window 3–14 m away can receive a plane")
	if spot.is_empty():
		return
	var p := PaperPlaneModule.new(rooms)
	p.reset()
	p.s["roll"] = {"hit": true, "kind": "peace"}
	var ctx: Dictionary = spot["ctx"].duplicate()
	ctx["now"] = 100.0
	p.set_context(ctx)
	p.tick(0.1)
	check(p.s["ev"] == null, "not before 150 s")
	ctx["now"] = 200.0
	p.set_context(ctx)
	p.tick(0.1)
	check(p.s["ev"] != null and p.phase() == "fly", "then it flies out of a window")
	for _i in 25:
		p.tick(0.1)
	check(p.phase() == "ground", "and lands")
	var e: Dictionary = p.s["ev"]
	ctx["x"] = float(e["lx"])
	ctx["y"] = float(e["ly"])
	p.set_context(ctx)
	check(p.hint() == "地上的纸飞机" and p.use_here(), "it can be picked up")
	var give := p.take_events().filter(func(x: Dictionary) -> bool: return x["kind"] == "give")
	check(give.size() == 1 and String(give[0]["text"]) in PaperPlaneModule.TIPS, "a peaceful plane carries a true tip")
	p.gave(true)
	check(p.s["ev"] == null and p.take_events().any(func(x: Dictionary) -> bool: return x["kind"] == "fact" and x["what"] == "received"), "the note is kept: 窗口来信")
	# The dangerous plane.
	var dspot := _paper_spot("danger")
	var d := PaperPlaneModule.new(rooms)
	d.reset()
	var dctx: Dictionary = dspot["ctx"].duplicate()
	d.set_context(dctx)
	d.start("danger")
	for _i in 25:
		d.tick(0.1)
	check(d.phase() == "wait", "a dangerous plane waits to be picked up")
	for _i in 81:
		d.tick(0.1)
	check(d.phase() == "hunt" and _notices(d.take_events())[1].begins_with("我：我没有去捡那架纸飞机。"), "not picking it up within 8 s brings footsteps")
	for _i in 41:
		d.tick(0.1)
	check(d.take_events().any(func(x: Dictionary) -> bool: return x["kind"] == "kill" and x["source"] == "paper_sender"), "4 s later the paper sender comes")
	var ok := PaperPlaneModule.new(rooms)
	ok.reset()
	ok.set_context(dctx)
	ok.start("danger")
	for _i in 25:
		ok.tick(0.1)
	var de: Dictionary = ok.s["ev"]
	dctx["x"] = float(de["lx"])
	dctx["y"] = float(de["ly"])
	ok.set_context(dctx)
	ok.use_here()
	check(ok.phase() == "read", "picked up, it has to be read")
	ok.fold()
	check(ok.phase() == "aim", "folded, it has to be aimed")
	var w: Dictionary = dspot["w"]
	var to: Vector2 = w["p"] - Vector2(float(dctx["x"]), float(dctx["y"]))
	dctx["ang"] = atan2(to.y, to.x)
	ok.set_context(dctx)
	ok.use_here()
	check(ok.phase() == "flight", "thrown at the window it flies")
	var result := ""
	for _i in 400:
		var f: Dictionary = ok.s["ev"]["f"] if ok.s["ev"] != null and ok.s["ev"].has("f") else {}
		var steer := {"l": 0.0, "r": 0.0, "u": 0.0, "d": 0.0}
		if not f.is_empty():
			var want := atan2(w["p"].y - float(f["y"]), w["p"].x - float(f["x"]))
			var turn := wrapf(want - float(f["yaw"]), -PI, PI)
			steer["r"] = 1.0 if turn > 0.02 else 0.0
			steer["l"] = 1.0 if turn < -0.02 else 0.0
			steer["u"] = 1.0 if float(f["h"]) < 1.5 else 0.0
		dctx["steer"] = steer
		ok.set_context(dctx)
		ok.tick(0.05)
		var ev := ok.take_events()
		if ev.any(func(x: Dictionary) -> bool: return x["kind"] == "fact" and x["what"] == "returned"):
			result = "in"
			break
		if ok.phase() == "hunt":
			result = "fail"
			break
	check(result == "in", "steered back through the window: 原路寄回")
	var crash := PaperPlaneModule.new(rooms)
	crash.reset()
	crash.s["ev"] = {"kind": "danger", "room": dspot["room"], "c": w["c"], "r": w["r"], "phase": "flight", "t": 0.0, "lx": 0.0, "ly": 0.0, "text": "", "limit": 0.5,
		"f": {"x": float(dctx["x"]), "y": float(dctx["y"]), "h": 1.4, "yaw": dctx["ang"] + PI, "pitch": 0.0, "clean": true}}
	crash.set_context(dctx)
	for _i in 20:
		crash.tick(0.05)
	check(crash.phase() == "hunt", "flying the wrong way fails")


## A floor tile next to the west wall of teach1.
func _wall_spot(room: Dictionary) -> Vector2:
	var grid: Array = room["grid"]
	for r in grid.size():
		if String(grid[r]).substr(0, 1) == "#" and String(grid[r]).substr(1, 1) == "." and String(grid[r]).substr(2, 1) == ".":
			return CampusGeometry.tile_center(room, 1, r)
	return Vector2.ZERO


func _test_marks_rules() -> void:
	var t1 := CampusData.layout("teach1")
	var m := MarksModule.new()
	m.reset()
	var solid := func(q: Vector2) -> bool: return CampusGeometry.SOLID_CH.contains(CampusGeometry.tile_at(t1, q))
	var near_wall := _wall_spot(t1)
	m.set_context({"scene": "teach1", "x": near_wall.x, "y": near_wall.y, "ang": PI, "pitch": 0.0, "solid": solid, "has_chalk": true})
	var t := m.target()
	check(t["face"] == "wall" and float(t["h"]) > 1.0, "looking level at a wall targets the wall")
	m.set_context({"scene": "teach1", "x": near_wall.x + 40.0, "y": near_wall.y, "ang": 0.0, "pitch": -0.8, "solid": solid, "has_chalk": true})
	check(m.target()["face"] == "floor", "looking down targets the floor")
	check(m.use_chalk() and m.take_events()[0]["labels"].size() == 8, "the chalk offers eight symbols")
	m.choose(0)
	var ev := m.take_events()
	check(m.marks.size() == 1 and ev.any(func(e: Dictionary) -> bool: return e["kind"] == "fact"), "a mark is drawn")
	m.use_chalk()
	check(m.take_events()[0]["labels"].size() == 9, "on a mark the chalk can also erase it")
	m.choose(8)
	check(m.marks.is_empty(), "erased")
	for i in 85:
		m.place("x", {"room": "teach1", "x": float(i), "y": 0.0, "h": 0.0, "face": "floor", "a": 0.0})
	check(m.visible("teach1").size() == MarksModule.PER_ROOM, "at most 80 marks a room")
	m.set_context({"scene": "teach1", "has_chalk": false})
	check(not m.use_chalk(), "no chalk, no marks")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(m.capture()))
	var back := MarksModule.new()
	back.reset()
	back.restore(saved)
	check(back.marks.size() == MarksModule.PER_ROOM, "marks survive the save")


func _test_classmates_rules() -> void:
	var rooms := CampusData.rooms()
	var c := ClassmatesModule.new(rooms)
	c.reset()
	c.set_seed("abc")
	var lay := c.layout("teach1")
	var own := 0
	for t: Vector2i in lay["seats"]:
		if t.x >= 45 and t.x <= 55:
			own += 1
	check(lay["seats"].size() <= 50 and own > 20 and own <= 36, "the own class is nearly full, the floor holds at most 50")
	check(not c.occupied("teach1", 48, 11) and not c.occupied("teach1", 48, 10), "the own seat and the deskmate's stay empty")
	var again := ClassmatesModule.new(rooms)
	again.reset()
	again.set_seed("abc")
	check(again.layout("teach1")["seats"] == lay["seats"], "the same seats every visit in one run")
	check(c.layout("admin1")["seats"].is_empty(), "only the teaching building's classrooms")
	var taken: Vector2i = lay["seats"][0]
	var campus := CampusData.make_module()
	campus.reset()
	campus.desk_taken = c.occupied
	var t1 := CampusData.layout("teach1")
	var stand := CampusGeometry.tile_center(t1, taken.x + 1, taken.y)
	var res := campus.interact_at("teach1", _campus_pose(t1, stand, PI))
	check(res.get("notice", "") == "我：他坐在这儿。我不能翻他的抽屉。" or not res.has("search"), "an occupied desk cannot be searched")
	campus.desk_taken = Callable()
	c.tick("teach1", Vector2(float(t1["ox"]) + 50 * 9.0, float(t1["oy"]) + 15 * 9.0), 72.0, false)
	check(c.take_events()[0]["text"] == "我：他们都在看着我。可是没有人说话。" and c.pressure("teach1", 72.0) == 0.12, "at 70 they stare and SAN drains")
	c.tick("teach1", Vector2(float(t1["ox"]) + 50 * 9.0, float(t1["oy"]) + 15 * 9.0), 95.0, false)
	var d: Dictionary = c.state["door"]
	check(bool(c.state["blocking"]) and c.blocked("teach1", int(d["c"]), int(d["r"])), "at 92 they block the nearest door")
	c.tick("teach1", Vector2.ZERO, 70.0, false)
	check(not bool(c.state["blocking"]), "below 80 the door is free again")


func _test_sensory_rules() -> void:
	check(SensoryRules.target(80.0) == 0.0 and absf(SensoryRules.target(45.0) - 0.25) < 0.001 and SensoryRules.target(0.0) == 1.0, "nothing above 60 SAN; it deepens below")
	var b := SensoryRules.step(0.0, 0.0, 0.35)
	var back := SensoryRules.step(1.0, 100.0, 0.35)
	check(b > 0.6 and back > 0.8, "quick to get worse, slow to get better")
	var v := SensoryRules.view(0.8, {})
	check(v["tunnel"] > 0.7 and v["drain"] > 0.9 and v["flicker"] == 1.0 and v["bpm"] > 120.0, "very low SAN: narrow, grey, blinking, a fast heart")
	var calm := SensoryRules.view(0.8, {"distortion": 0, "threat": true})
	check(calm["warp"] == 0.0 and calm["tunnel"] > 0.2 and calm["tunnel"] < 0.3, "distortion off removes the warp; real danger softens to 35 %")
	check(SensoryRules.view(0.8, {"takeover": true})["tunnel"] == 0.0, "a takeover turns it off")
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var plan := SensoryRules.blink_plan(0.7, rng)
	check(SensoryRules.blink_at(plan, 0.01) == 1.0 and SensoryRules.blink_at(plan, SensoryRules.blink_end(plan) + 0.1) == 0.0, "a blink goes black and comes back")


func _test_caption_rules() -> void:
	var c := SoundCaptions.new()
	var e := c.publish("dread.knock", {"place": {"pan": -0.6, "muffled": true}})
	check(e["text"] == "左 · 隔着墙 · 轻轻的敲门声", "a caption says where: left, through a wall")
	check(c.publish("music.box", {}).is_empty() and c.publish("step.tile", {"self_step": true}).is_empty(), "uncaptioned sounds and your own steps say nothing")
	check(String(c.publish("step.tile", {"patrol": true, "place": {"behind": true, "m": 3.0}})["text"]) == "后方 · 近处 · 脚步声", "the patroller's steps: behind, near")
	c.publish("threat.heartLow", {})
	check(c.publish("threat.heartLow", {}).is_empty(), "the heart is captioned at most once in 20 s")
	check(c.publish("dread.door", {}, true).is_empty() and not c.publish("event.bellEnd", {}, true).is_empty(), "with the phone or a lesson open only urgent captions get through")
	check(c.visible().size() == 2 and int(c.visible()[0]["priority"]) == 3, "two lines at most, the urgent one first")
	for _i in 30:
		c.tick(0.25)
	check(c.visible().is_empty(), "captions expire (the clock steps at most 0.25 s a frame)")
	c.mode = 0
	check(not c.enabled(0.7, false) and c.enabled(0.03, false) and c.enabled(0.7, true), "auto mode captions only when the sound is off or nearly")


func _test_dread_rules() -> void:
	check(absf(DreadModule.lhash("1:teach1:2") - 0.09446) < 0.000001 and absf(DreadModule.lhash("2:lab1:3") - 0.32188) < 0.000001, "the revisit hash is the Web version's lhashStr")
	var d := DreadModule.new(CampusData.rooms())
	d.reset()
	var t1 := CampusData.layout("teach1")
	var at := CampusGeometry.tile_center(t1, 30, 17)
	var ctx := {"scene": "teach1", "x": at.x, "y": at.y, "ang": 0.0, "san": 100.0, "viol": 0.0, "night": 0.0, "day": 1}
	d.set_context(ctx)
	for _i in 590:
		d.tick(0.1)
	check(d.take_events().is_empty(), "nothing in the first minute of a run")
	check(d.allow(1) and d.false_threat("knock"), "a false threat when the budget allows")
	var ev := d.take_events()
	var pl: Dictionary = ev[0]["place"] if not ev.is_empty() else {}
	check(not ev.is_empty() and ev[0]["kind"] == "dread" and ev[0]["cue"] == "knock" and float(pl["m"]) >= 4.0 and float(pl["m"]) <= 16.0, "a knock at a door or wall 4–16 m away, placed")
	check(not d.allow(1) and not d.false_threat("steps"), "mild scares are at least 9 s apart")
	d.t += 30.0
	check(d.allow(1) and d.allow(2), "after the gaps both are allowed again")
	d.false_threat("run", 2)
	d.t += 50.0
	check(not d.allow(2), "strong scares in the same area wait 120 s")
	d.t += 100.0
	d.take_events()
	d.false_threat("silence")
	check(d.take_events()[0]["kind"] == "duck", "a hush drops the ambience")
	var pre := ctx.duplicate()
	pre["an_next"] = 2.0
	pre["an_next0"] = 7
	d.set_context(pre)
	d.tick(0.1)
	d.tick(0.1)
	check(_of_kind(d.take_events(), "precursor").size() == 1, "one precursor 3.2 s before the next anomaly")
	var busy := ctx.duplicate()
	busy["busy"] = true
	d.set_context(busy)
	d.next_amb = 0.0
	d.tick(0.1)
	check(_of_kind(d.take_events(), "dread").is_empty(), "nothing while something real is going on")
	var v := DreadModule.new(CampusData.rooms())
	v.reset()
	v.set_context(ctx)
	v.enter("teach1")
	check(v.visit_fx.is_empty(), "the first visit of the day is as usual")
	v.enter("teach1")
	var vev := v.take_events()
	check(v.visit_fx.get("kind", "") == "lamp" and _of_kind(vev, "visit").size() == 1 and _of_kind(vev, "visit")[0]["fx"] == "lamp", "the second visit to teach1 on day 1 breaks a lamp (as the Web version)")
	var back := DreadModule.new(CampusData.rooms())
	back.restore(v.capture())
	back.set_context(ctx)
	back.enter("teach1", true)
	check(back.visit_fx.get("kind", "") == "lamp" and back.visits["1:teach1"] == 2, "a load replays the same change without counting a visit")


func _atmos_ctx(col: int, row: int, extra: Dictionary = {}) -> Dictionary:
	var t1 := CampusData.layout("teach1")
	var at := CampusGeometry.tile_center(t1, col, row)
	var ctx := {"scene": "teach1", "x": at.x, "y": at.y, "ang": 0.0, "day": 2, "tsec": 700.0, "viol": 0.0, "busy": false, "an_active": false,
		"an_next": -1.0, "an_next0": 0, "age": 100.0, "prop": null, "prop_ok": false, "sees_shifted": false}
	ctx.merge(extra, true)
	return ctx


func _test_atmos_rules() -> void:
	# Classes and the ground the module reads.
	check(AtmosModule.class_index(12, 10) == 0 and AtmosModule.class_index(33, 7) == 2 and AtmosModule.class_index(20, 10) == -1 and AtmosModule.class_index(12, 6) == -1,
		"four classes a floor, rows 7–14 only (ClassroomLayout.classAt)")
	var rooms := CampusData.rooms()
	var probe := AtmosModule.new(rooms)
	check(probe.class_at(rooms["teach1"], 12, 10) == "teach1:0" and probe.class_at(rooms["teach1"], 12, 6).is_empty(), "a tile names its class")
	# A1: the campus goes quiet day by day.
	var a := AtmosModule.new(rooms)
	a.reset()
	a.set_context(_atmos_ctx(12, 10, {"day": 1}))
	check(a.campus_kinds().size() == 3, "day 1 keeps whistle, car and bird")
	a.set_context(_atmos_ctx(12, 10, {"day": 2}))
	check(a.campus_kinds() == ["car", "bird"], "day 2 loses the whistle")
	a.set_context(_atmos_ctx(12, 10, {"day": 3}))
	check(a.campus_kinds() == ["bird"], "day 3 only a bird")
	var day1 := AtmosModule.new(rooms)
	day1.reset()
	day1.set_context(_atmos_ctx(12, 10, {"day": 1}))
	var heard := 0
	for _i in 600:
		day1.tick(0.2)
		heard += _of_kind(day1.take_events(), "campus").size()
	check(heard >= 2, "daytime campus noise comes every 16–38 s")
	var night := AtmosModule.new(rooms)
	night.reset()
	night.set_context(_atmos_ctx(12, 10, {"day": 1, "tsec": 1200.0}))
	var night_heard := 0
	for _i in 600:
		night.tick(0.2)
		night_heard += _of_kind(night.take_events(), "campus").size()
	check(night_heard == 0, "none after dark")
	# A1: before an anomaly the place may hush (day 2 on, half the time).
	var hushed := 0
	var quiet_day1 := 0
	for n in 60:
		var h := AtmosModule.new(rooms)
		h.reset()
		h.set_context(_atmos_ctx(12, 10, {"day": 2, "an_next": 5.0, "an_next0": 100 + n}))
		h.tick(0.1)
		hushed += _of_kind(h.take_events(), "duck").size()
		var h1 := AtmosModule.new(rooms)
		h1.reset()
		h1.set_context(_atmos_ctx(12, 10, {"day": 1, "an_next": 5.0, "an_next0": 100 + n}))
		h1.tick(0.1)
		quiet_day1 += _of_kind(h1.take_events(), "duck").size()
	check(hushed > 10 and hushed < 50 and quiet_day1 == 0, "from day 2 about half of the anomalies are announced by a hush; day 1 never")
	# A5: the bell.
	var b := AtmosModule.new(rooms)
	b.set_context(_atmos_ctx(12, 10, {"day": 1}))
	check(b.bell_tune("end", 700.0).is_empty(), "day 1 the bell rings true")
	b.set_context(_atmos_ctx(12, 10, {"day": 2}))
	var tune := b.bell_tune("end", 700.0)
	check(absf(float(tune["pitch"]) - pow(2.0, -0.5 / 12.0)) < 0.0001 and b.bell_tune("start", 700.0).is_empty(), "day 2 the end bell sinks half a tone; the start bell never changes")
	b.set_context(_atmos_ctx(12, 10, {"day": 3}))
	check(absf(float(b.bell_tune("end", 700.0)["pitch"]) - pow(2.0, -1.0 / 12.0)) < 0.0001, "day 3 a whole tone")
	var late := b.bell_tune("end", 1330.0)
	check(float(late["pitch"]) < pow(2.0, -2.5 / 12.0) + 0.0001 and bool(late["slow"]), "the bell before lights-out is lower and slower")
	# A7: dusk comes early from day 2.
	var m1 := AtmosModule.light_mods(1, 1020.0)
	var m3 := AtmosModule.light_mods(3, 1020.0)
	check(float(m1["dusk"]) == 0.0 and float(m3["dusk"]) > 0.2 and float(m3["cold"]) < 1.0 and float(AtmosModule.light_mods(3, 700.0)["dusk"]) == 0.0,
		"day 1 has no early dusk, day 3 does (only in the afternoon)")
	# A3: a class turns once, three a day at most, never with many violations or something real going on.
	var stared := 0
	var vacant := 0
	var turned: AtmosModule
	for day in range(2, 40):
		var s := AtmosModule.new(rooms)
		s.reset()
		var d := DreadModule.new(rooms)
		d.reset()
		s.set_context(_atmos_ctx(12, 13, {"day": day, "dread": d}))
		s.tick(0.1)
		if not s.stare.is_empty():
			stared += 1
			turned = s
	check(stared > 5 and stared < 25, "walking into a class on day 2+ sometimes turns every head (%d of 38)" % stared)
	check(turned != null and turned.stare["cls"] == "teach1:0" and turned.stares.values().has(1), "the turn is recorded for the day and class")
	for _i in 30:
		turned.tick(0.1)
	check(turned.stare.is_empty(), "the class turns back after 2.7 s")
	var busy_hits := 0
	var viol_hits := 0
	for day in range(2, 40):
		var s2 := AtmosModule.new(rooms)
		s2.reset()
		s2.set_context(_atmos_ctx(12, 13, {"day": day, "busy": true, "dread": DreadModule.new(rooms)}))
		s2.tick(0.1)
		busy_hits += 0 if s2.stare.is_empty() else 1
		var s3 := AtmosModule.new(rooms)
		s3.reset()
		s3.set_context(_atmos_ctx(12, 13, {"day": day, "viol": 40.0, "dread": DreadModule.new(rooms)}))
		s3.tick(0.1)
		viol_hits += 0 if s3.stare.is_empty() else 1
	check(busy_hits == 0 and viol_hits == 0, "no stare during anything real or at 35+ violations")
	var day1_stare := AtmosModule.new(rooms)
	day1_stare.reset()
	day1_stare.set_context(_atmos_ctx(12, 13, {"day": 1, "dread": DreadModule.new(rooms)}))
	day1_stare.tick(0.1)
	check(day1_stare.stare.is_empty(), "never on day 1")
	# A3: a return can leave one more seat empty.
	for day in range(2, 60):
		var r := AtmosModule.new(rooms)
		r.reset()
		var rd := DreadModule.new(rooms)
		rd.reset()
		r.left["teach1:0"] = day
		r.set_context(_atmos_ctx(12, 13, {"day": day, "dread": rd, "ang": PI}))   # facing away: no stare, only a vacancy
		r.tick(0.1)
		if r.seats.has("%d:teach1:0" % day):
			vacant += 1
			check(int(r.seats["%d:teach1:0" % day]) >= 1 and int(r.seats["%d:teach1:0" % day]) <= 7 and r.stare.is_empty(), "a return leaves one seat of the class empty")
			break
	check(vacant == 1, "a return after leaving a class sometimes leaves one more empty seat")
	# A4: a figure outside the window (not before 90 s into the run).
	var windows := 0
	var early := 0
	for day in range(1, 60):
		var w := AtmosModule.new(rooms)
		w.reset()
		w.set_context(_atmos_ctx(12, 13, {"day": day, "dread": DreadModule.new(rooms)}))
		w.tick(0.1)
		windows += 0 if w.window.is_empty() else 1
		var w2 := AtmosModule.new(rooms)
		w2.reset()
		w2.set_context(_atmos_ctx(12, 13, {"day": day, "age": 30.0, "dread": DreadModule.new(rooms)}))
		w2.tick(0.1)
		early += 0 if w2.window.is_empty() else 1
	check(windows > 5 and windows < 45 and early == 0, "some classes show a figure at the window, never in the first 90 s")
	var gone: AtmosModule
	for day in range(1, 60):
		var w3 := AtmosModule.new(rooms)
		w3.reset()
		w3.set_context(_atmos_ctx(12, 13, {"day": day, "dread": DreadModule.new(rooms)}))
		w3.tick(0.1)
		if not w3.window.is_empty():
			gone = w3
			break
	gone.window_look = true
	for _i in 10:
		gone.tick(0.1)
	check(not bool(gone.window["gone"]), "while it is looked at it stays")
	gone.window_look = false
	gone.tick(0.1)
	check(bool(gone.window["gone"]), "after more than 0.8 s of looking, the next glance away finds it gone")
	# A6: the mop moves when far away and unseen.
	var moved := 0
	var facing := 0
	for day in range(2, 40):
		var sh := AtmosModule.new(rooms)
		sh.reset()
		var sd := DreadModule.new(rooms)
		sd.reset()
		var t1 := CampusData.layout("teach1")
		sh.set_context(_atmos_ctx(30, 17, {"day": day, "dread": sd, "prop": CampusGeometry.tile_center(t1, 12, 17), "prop_ok": true}))
		sh.tick(0.1)
		var rec := str(sh.shift.get("%d:teach1" % day, 0))
		if rec == "face":
			facing += 1
		moved += 1 if (rec == "face" or rec == "push") else 0
	check(moved > 10 and moved < 36 and facing == moved, "on day 2+ the mop and bucket sometimes face you when nobody saw them move (%d of 38)" % moved)
	var seen := AtmosModule.new(rooms)
	seen.reset()
	seen.set_context(_atmos_ctx(30, 17, {"day": 2, "dread": DreadModule.new(rooms), "prop": Vector2(10, 10), "prop_ok": false}))
	for _i in 20:
		seen.tick(0.1)
	check(seen.shift.is_empty(), "never while it is in sight or close")
	# A2: dead stretch of lamps, fixed for the room and always at least one lamp lit.
	var rows := [8, 10, 12, 14, 16, 16, 18, 19]
	var dark := AtmosModule.dark_lamps(rooms["teach1"], rows)
	check(AtmosModule.dark_lamps(rooms["teach1"], rows) == dark and dark.size() < rows.size() and not AtmosModule.dark_lamps(rooms["canteen1"], rows).size() > 0, "the dark stretch is fixed per room and only on a teaching, office or lab floor")
	# Saved state.
	var back := AtmosModule.new(rooms)
	back.restore(turned.capture())
	check(back.stares == turned.stares and back.validate(turned.capture()).is_empty() and not back.validate({"stares": {"1:a": 9}}).is_empty(), "the atmosphere record saves and loads, and a bad one is rejected")


func _test_mono_rules() -> void:
	var rooms := CampusData.rooms()
	var m := MonoModule.new(rooms)
	m.reset()
	var t1 := CampusData.layout("teach1")
	var hall := CampusGeometry.tile_center(t1, 20, 18)
	var klass := CampusGeometry.tile_center(t1, 12, 10)
	m.set_context({"scene": "teach1", "x": hall.x, "y": hall.y, "tile": "", "san": 90.0, "night": false, "busy": false, "seated_class": false})
	check(m.tier() == "calm" and m.place() == "hall", "a steady mind in the corridor mutters about the corridor")
	m.set_context({"scene": "teach1", "x": klass.x, "y": klass.y, "tile": "", "san": 60.0, "night": false, "busy": false, "seated_class": false})
	check(m.tier() == "uneasy" and m.place() == "class", "SAN 50–75 is uneasy, a classroom is a class")
	var tiers := {}
	for san in [100.0, 74.0, 49.0, 10.0]:
		m.set_context({"scene": "out", "x": 0.0, "y": 0.0, "tile": "", "san": san, "night": true, "busy": false, "seated_class": false})
		tiers[m.tier()] = m.place()
	check(tiers.size() == 4 and tiers["calm"] == "outNight", "four tiers by SAN (75, 50, 25), and the night outside has its own lines")
	check(MonoModule.LINES["calm"]["any"].size() == 4 and MonoModule.LINES["breaking"]["any"].size() == 5, "the lines are the Web version's")
	m.set_context({"scene": "garage1", "x": 0.0, "y": 0.0, "tile": "", "san": 30.0, "night": false, "busy": false, "seated_class": false})
	var garage_line := m.pick()
	check(m.place() == "garage" and (MonoModule.LINES["frayed"]["garage"].has(garage_line) or MonoModule.LINES["frayed"]["any"].has(garage_line)), "the garage has its own lines")
	# 40–75 s apart, with no repeats among the last eight, nothing while busy.
	var said: Array = []
	m.reset()
	m.set_context({"scene": "out", "x": 0.0, "y": 0.0, "tile": "", "san": 90.0, "night": false, "busy": false, "seated_class": false})
	for _i in 5000:
		m.tick(0.1)
		for e: Dictionary in m.take_events():
			said.append(e["text"])
	check(said.size() >= 6 and said.size() <= 13, "about one line a minute (%d in 500 s)" % said.size())
	var first := said.slice(0, 6)
	var distinct := {}
	for l: String in first:
		distinct[l] = true
	check(distinct.size() == first.size(), "no line repeats until all of the place's lines have been said")
	var quiet := MonoModule.new(rooms)
	quiet.reset()
	quiet.set_context({"scene": "out", "x": 0.0, "y": 0.0, "tile": "", "san": 90.0, "night": false, "busy": true, "seated_class": false})
	for _i in 2000:
		quiet.tick(0.1)
	check(quiet.take_events().is_empty(), "nothing while something else is going on")


func _test_scene_rules() -> void:
	var rooms := CampusData.rooms()
	var t1 := CampusData.layout("teach1")
	var lamps: Array = [CampusGeometry.tile_center(t1, 20, 18), CampusGeometry.tile_center(t1, 40, 18)]
	var sc := AtmosModule.new(rooms)
	sc.reset()
	var d := DreadModule.new(rooms)
	d.reset()
	sc.set_context(_atmos_ctx(20, 18, {"day": 1, "dread": d, "lamps": lamps, "tsec": 700.0}))
	var hum := 0
	var dimmed := 1.0
	var returned := false
	for _i in 2400:
		sc.tick(0.1)
		hum += _of_kind(sc.take_events(), "dread").size()
		var mul := sc.lamp_mul()
		if not mul.is_empty():
			dimmed = minf(dimmed, float(mul.values()[0]))
		elif dimmed < 0.2:
			returned = true
	check(hum >= 2 and dimmed < 0.2 and returned, "a corridor lamp hums, dims to 12 %% and comes back, the hum moving to a door (%d sounds)" % hum)
	var quiet := AtmosModule.new(rooms)
	quiet.reset()
	quiet.set_context(_atmos_ctx(20, 18, {"day": 1, "dread": DreadModule.new(rooms), "lamps": lamps, "busy": true}))
	for _i in 2400:
		quiet.tick(0.1)
	check(quiet.scene_event().is_empty() and _of_kind(quiet.take_events(), "dread").is_empty(), "no small scene while something real is going on")
	var early := AtmosModule.new(rooms)
	early.reset()
	early.set_context(_atmos_ctx(20, 18, {"day": 1, "dread": DreadModule.new(rooms), "lamps": lamps, "age": 30.0}))
	early._sc_clock = 90.0
	early.tick(0.1)
	check(early.scene_event().is_empty(), "nothing in the first minute of a run")
	# A door you just closed is answered 1.4 s later about three times in ten.
	var knocks := 0
	for n in 100:
		var dm := AtmosModule.new(rooms)
		dm.reset()
		dm.set_context(_atmos_ctx(20, 18, {"day": 1, "dread": DreadModule.new(rooms)}))
		dm.door_action("teach1", 30, 15, false)
		if not dm.scene_event().is_empty():
			for _i in 13:
				dm.tick(0.1)
			check(_of_kind(dm.take_events(), "dread").is_empty(), "no answer before 1.4 s")
			for _i in 3:
				dm.tick(0.1)
			knocks += _of_kind(dm.take_events(), "dread").size()
	check(knocks > 12 and knocks < 55, "about 30 %% of closed doors are knocked on from the other side (%d of 100)" % knocks)
	var again := AtmosModule.new(rooms)
	again.reset()
	again.set_context(_atmos_ctx(20, 18, {"day": 1, "dread": DreadModule.new(rooms)}))
	again._sc_doors["teach1:30:15"] = 0.0
	again.door_action("teach1", 30, 15, false)
	check(again.scene_event().is_empty(), "the same door is not answered twice within 120 s")
	var reopened := AtmosModule.new(rooms)
	reopened.reset()
	reopened._sc_event = {"kind": "door", "at": 0.0, "room": "teach1", "pos": CampusGeometry.tile_center(t1, 30, 15)}
	reopened.set_context(_atmos_ctx(20, 18, {"day": 1, "dread": DreadModule.new(rooms)}))
	reopened.door_action("teach1", 30, 15, true)
	check(reopened.scene_event().is_empty(), "opening the door again cancels the answer")


func _test_settings_rules() -> void:
	var d := GameSettings.normalize({})
	check(d["vol"] == 70 and d["captions"] == 1 and d["amb"] == 1 and d["distortion"] == 2 and d["reduce_flash"] == 0 and d["bright"] == 100 and d["mouse"] == 100,
		"settings default to the Web version's (volume 70, captions on, ambience on, full distortion)")
	var bad := GameSettings.normalize({"vol": 250, "bright": 3, "mouse": 9999, "text": 10, "captions": 7, "quality": -1, "unknown": 5, "sub": "x"})
	check(bad["vol"] == 100 and bad["bright"] == 50 and bad["mouse"] == 250 and bad["text"] == 85 and bad["captions"] == 1 and bad["quality"] == 2 and bad["sub"] == 1 and not bad.has("unknown"),
		"out-of-range or invalid values are clamped or defaulted, unknown keys dropped")
	var path := _test_path.get_base_dir() + "/settings-rules.json"
	var a := GameSettings.new(path)
	check(not a.load_file(false) and a.get_int("quality") == 2, "no file: defaults")
	var t := GameSettings.new(path + ".touch")
	t.load_file(true)
	check(t.get_int("quality") == 0, "a first run on a touch device starts at 流畅")
	a.set_value("vol", 35)
	a.set_value("captions", 2)
	a.set_value("mouse", 400)
	check(a.save_file() and GameSettings.new(path).load_file() , "saves to its own file")
	var b := GameSettings.new(path)
	b.load_file()
	check(b.get_int("vol") == 35 and b.get_int("captions") == 2 and b.get_int("mouse") == 250, "a saved setting is read back, clamped")
	b.set_value("text", 140)
	b.set_value("touch_size", 120)
	b.reset_comfort()
	check(b.get_int("text") == 100 and b.get_int("touch_size") == 100 and b.get_int("vol") == 35, "restoring comfort defaults leaves sound and picture alone")
	check(GameSettings.QUALITY_SCALE.size() == 5 and GameSettings.QUALITY_LABELS[4] == "真实" and GameSettings.SUB_MULT == [0.6, 1.0, 1.6], "five quality tiers, three caption sizes")
	for p2: String in [path, path + ".touch"]:
		if FileAccess.file_exists(p2):
			DirAccess.remove_absolute(p2)


func _test_investigation_rules() -> void:
	var inv := InvestigationModule.new()
	inv.reset()
	inv.set_context({"day": 1, "place": "教学楼 1F", "desk_ok": true})
	check(inv.goal().begins_with("先看看自己课桌上的停车单"), "day 1 starts at the desk: look at the parking ticket")
	check(inv.open_desk() and inv.visible("desk") and _of_kind(inv.take_events(), "save").size() == 1, "R at the own seat reads the ticket and records it")
	check(not inv.open_desk() and inv.goal().begins_with("停车单提到了教室前方的讲台"), "the ticket is read once; the goal moves on to the podium")
	inv.notice()
	var ev := inv.take_events()
	check(inv.visible("notice") and inv.visible("carTheory") and inv.visible("timePressure") and inv.visible("supply") and not _of_kind(ev, "spots").is_empty(), "the handover note records four entries and marks the guard post and the garage on the map")
	check(inv.entries["carTheory"]["kind"] == "推测" and inv.entries["notice"]["kind"] == "事实" and inv.entries["notice"]["source"].contains("讲台"), "kinds and sources follow the Web version")
	var ch: Dictionary = _of_kind(ev, "choice")[0]
	check(ch["labels"][0] == "阅读登记规定（次日起开放）" and ch["labels"].size() == 2, "on day 1 the outing registration is read, not made")
	inv.choose(0)
	check(inv.visible("outing") and not _of_kind(inv.take_events(), "outing").is_empty(), "the outing rule is recorded and registration is offered")
	check(inv.entries["notice"]["day"] == 1 and inv.recent.back() == "outing", "an entry remembers its day; the latest find is last")
	# Supply box: only at its place, only after the note, once.
	var site := String(inv.supply["site"])
	var other := "canteen1" if site == "guard1" else "guard1"
	inv.set_context({"day": 1, "place": "x", "has_coin": true, "has_pill": false, "bag_full": false})
	check(not inv.supply_offer(other) and inv.supply_offer(site) and _of_kind(inv.take_events(), "choice").size() == 1, "the supply offer appears only at its own place")
	inv.choose(1)
	var took := inv.take_events()
	check(not _of_kind(took, "supply").is_empty() and _of_kind(took, "supply")[0]["pay"] and inv.visible("supplyTaken") and bool(inv.supply["taken"]), "paying a coin takes the pill and records it")
	check(not inv.supply_offer(site), "the box is empty afterwards")
	var full := InvestigationModule.new()
	full.reset()
	full.set_context({"day": 1, "bag_full": true})
	full.record("notice", "n", "事实")
	full.supply_offer(String(full.supply_site()["site"]))
	full.take_events()
	full.choose(0)
	check(_of_kind(full.take_events(), "supply").is_empty() and not bool(full.supply["taken"]), "a full bag leaves the pill in the box")
	var again := InvestigationModule.new()
	again.reset()
	again.record("notice", "n", "事实")
	again.supply_offer(String(again.supply_site()["site"]))
	again.take_events()
	again.choose(2)
	check(not _of_kind(again.take_events(), "continue").is_empty(), "declining goes on with the facility")
	# Focus, goal and progress.
	var f := InvestigationModule.new()
	f.reset()
	f.set_context({"day": 2, "has_key": true, "car": {"ok": true, "via": "key"}, "car_tried": 2, "portal": {"diary": true, "sketch": false, "open": false, "count": 1, "floors_left": [2, 5], "need": ""}, "hacked": true, "spot_comp": true})
	f.record("portalDiary", "d", "事实")
	check(f.focus == "portal" and f.current_focus() == "portal" and f.routes().size() == 3 and f.goal().contains("已得到 1/3 张图纸"), "reading the diary moves the focus to the portal route")
	check(f.set_focus("car") and f.goal().begins_with("已经有车钥匙") and not f.set_focus("cyber"), "the player can focus a route that exists, not one that does not")
	var prog := f.progress()
	check(prog.size() == 3 and String(prog[0][1]).contains("有钥匙，能够试车门；已试 2 辆") and String(prog[2][1]).contains("还需调查实验楼 2、5 楼教师台"), "the route progress block reads like the Web version")
	# Listing and search.
	f.record("notice", "钥匙移交：行政楼五楼校长办公室。", "事实", "教学楼一楼 · 讲台移交单")
	f.record("parking", "停车登记：第 3 排。", "事实", "保安岗")
	var all := f.list()
	var hits := f.list("保安")
	check(all["found"] == 3 and hits["found"] == 1 and hits["recent"].is_empty() and all["recent"].size() == 3 and all["recent"][0]["id"] == "parking", "search filters by text or place; recent shows the latest three, newest first")
	check(InvestigationModule.new().car_name(4, 3) == "鄂A·H3227" and GarageModule.new(CampusData.layout("garage1")).car_name(4, 3) == InvestigationModule.new().car_name(4, 3), "plates match the garage's")
	# Records survive a save; a bad one is rejected.
	var back := InvestigationModule.new()
	back.restore(f.capture())
	check(back.entries == f.entries and back.recent == f.recent and back.focus == f.focus and back.validate(f.capture()).is_empty(), "the notebook saves and loads")
	check(not back.validate({"entries": {"a": {"text": 3, "kind": "事实"}}, "recent": [], "supply": {}}).is_empty(), "a broken notebook is rejected")
	var many := InvestigationModule.new()
	many.reset()
	for i in 12:
		many.record("r%d" % i, "t", "线索")
	check(many.recent.size() == 8 and many.recent[0] == "r4", "only the last eight finds are remembered")


func _test_exploration_rules() -> void:
	var rooms := CampusData.rooms()
	var t1: Dictionary = rooms["teach1"]
	var ex := ExplorationModule.new(rooms)
	ex.reset()
	var at := CampusGeometry.tile_center(t1, 20, 18)
	var open_doors := {}
	ex.set_context({"scene": "teach1", "x": at.x, "y": at.y, "door_open": func(c: int, r: int) -> bool: return open_doors.has("%d:%d" % [c, r])})
	check(ex.rooms().is_empty() and ex.count("teach1") == 0, "nothing is on the sketch before you look")
	check(ex.observe() and ex.has(t1, 20, 18) and ex.has(t1, 24, 18) and not ex.has(t1, 40, 18), "the tiles within 6 around you are seen, the far ones are not")
	check(ex.rooms() == ["teach1"] and ex.count("teach1") > 20, "the room joins the list of walked floors")
	check(not ex.has(t1, 20, 10), "a classroom behind its closed door is not seen from the corridor")
	var d := Vector2i(-1, -1)
	for c in range(10, 24):
		if String(t1["grid"][15]).substr(c, 1) == "=":
			d = Vector2i(c, 15)
			break
	check(d.x >= 0, "(the corridor wall has classroom doors)")
	var door_at := CampusGeometry.tile_center(t1, d.x, 17)
	var ex2 := ExplorationModule.new(rooms)
	ex2.reset()
	ex2.set_context({"scene": "teach1", "x": door_at.x, "y": door_at.y, "door_open": func(_c: int, _r: int) -> bool: return false})
	ex2.observe()
	check(not ex2.has(t1, d.x, 13), "a closed door hides the room behind it")
	var ex3 := ExplorationModule.new(rooms)
	ex3.reset()
	ex3.set_context({"scene": "teach1", "x": door_at.x, "y": door_at.y, "door_open": func(_c: int, _r: int) -> bool: return true})
	ex3.observe()
	check(ex3.has(t1, d.x, 13), "an open door shows it")
	check(ex.percent("teach1") > 0 and ex.percent("teach1") < 20, "a few steps in, a small part of the floor is seen (%d%%)" % ex.percent("teach1"))
	# Save: six tiles a character, trailing blanks dropped; a bad record is rejected.
	var saved := ex.capture()
	var text := String(saved["seen"]["teach1"])
	check(text.length() <= (63 * 22 + 5) / 6 and not text.ends_with("A") and ExplorationModule.unpack(text, t1) == ex.seen("teach1"), "the sketch packs to a short string and unpacks to the same tiles")
	var back := ExplorationModule.new(rooms)
	back.restore(saved)
	check(back.count("teach1") == ex.count("teach1") and back.validate(saved).is_empty(), "the sketch saves and loads")
	check(not back.validate({"seen": {"teach1": "!!"}}).is_empty() and not back.validate({"seen": {"nowhere": "A"}}).is_empty() and not back.validate({"seen": {"teach1": "B".repeat(400)}}).is_empty(), "bad records are rejected")
	# The tick samples every 0.3 s.
	var tk := ExplorationModule.new(rooms)
	tk.reset()
	tk.set_context({"scene": "teach1", "x": at.x, "y": at.y, "door_open": func(_c: int, _r: int) -> bool: return false})
	tk.tick(0.2)
	check(tk.count("teach1") == 0, "no look before 0.3 s")
	tk.tick(0.15)
	check(tk.count("teach1") > 0, "a look every 0.3 s")
	check(MapView.tone("留") == "brass" and MapView.tone("锁") == "seal" and MapView.tone("✓") == "done" and MapView.tone("梯") == "route" and MapView.tone("桌") == "prop" and MapView.static_mark("S") == "梯", "the four tones and the furniture letters of the sketch")


func _test_drop_rules() -> void:
	var bag := InventoryModule.new(CampusData.rooms(), CampusData.campus())
	bag.reset()
	bag.add("coin")
	bag.add("torch")
	bag.set_hot(0, "torch")
	bag.torch_on = true
	check(bag.drop("torch") and not bag.has("torch") and bag.hot[0] == null and not bag.torch_on and bag.take_notices().has("我：我把「手电筒」放下了。"), "dropping an item removes it from the bag and the hot slot, and switches the torch off")
	check(not bag.drop("torch") and bag.has("coin"), "dropping what you do not have does nothing; the rest stays")
	var fac := FacilitiesModule.new(CampusData.rooms(), CampusData.layout("out"), CampusData.campus())
	fac.reset()
	fac.flags["coil"] = true
	check(fac.flags["coil"] == true, "(the coil was taken from the server room)")


func _test_plane_rules() -> void:
	var g := PlaneGame.new()
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 7
	var roll := func() -> float: return rnd.randf()
	check(g.st == "ready" and g.flap() and g.st == "fly" and g.vy == PlaneGame.FLAP, "the first tap starts the round with an upward kick")
	var tick := g.tick(0.1, 1.0, roll)
	check(tick.is_empty() and g.y > PlaneGame.H * 0.45 - 30.0 and g.pipes.size() == 1 and float(g.pipes[0]["x"]) < PlaneGame.W + 20.0, "gravity pulls, a shelf comes in from the right")
	# Fall: the round ends on the floor with no score and no gain.
	var ended: Array = []
	for _i in 100:
		ended.append_array(g.tick(0.05, 1.0, roll))
	check(g.st == "over" and ended.size() == 1 and ended[0]["gain"] == 0.0 and g.msg == "", "falling ends the round; no score gives no rest")
	check(g.flap() == true and g.st == "ready" and g.score == 0, "a tap after the end restarts")
	# A hand-made scored round: pass shelves, end by the floor, and the SAN gain is scaled by the pressure.
	var h := PlaneGame.new()
	h.st = "fly"
	h.score = 3
	h.y = PlaneGame.H - 9.0
	h.vy = 200.0
	var scored := h.tick(0.1, 0.5, roll)
	check(scored.size() == 1 and absf(float(scored[0]["gain"]) - 1.5) < 0.001 and h.cool == PlaneGame.COOL and h.msg == "手指放松下来，远处声音又清楚了", "a scored round gives 1 SAN a point scaled by the rest factor, then the phone is hot for 45 s")
	var hot := h
	hot.reset()
	hot.st = "fly"
	hot.score = 5
	hot.y = PlaneGame.H - 9.0
	hot.vy = 200.0
	var none := hot.tick(0.1, 1.0, roll)
	check(none.size() == 1 and none[0]["gain"] == 0.0 and hot.msg == "手机发烫了，静不下心", "a hot phone gives nothing")
	var cap := PlaneGame.new()
	cap.st = "fly"
	cap.score = 20
	cap.y = PlaneGame.H - 9.0
	cap.vy = 200.0
	check(cap.tick(0.1, 1.0, roll)[0]["gain"] == 6.0, "at most 6 points of rest")
	cap.tick(40.0, 1.0, roll)
	check(cap.cool > 0.0 and cap.cool < PlaneGame.COOL, "the heat cools down with time")
	# Shelf pass counts a point and a collision ends the round.
	var s := PlaneGame.new()
	s.st = "fly"
	s.y = 150.0
	s.vy = 0.0
	s.pipes = [{"x": 20.0, "gy": 200.0, "pass": false}]
	s.tick(0.01, 1.0, roll)
	check(s.score == 0 and s.st == "over", "hitting a shelf ends the round")
	var p := PlaneGame.new()
	p.st = "fly"
	p.y = 150.0
	p.pipes = [{"x": 10.0, "gy": 100.0, "pass": false}]
	p.tick(0.01, 1.0, roll)
	check(p.score == 1 and p.st == "fly", "passing a shelf scores a point")
	check(PhoneEnergy.next_signal_in({"elapsed": 14.0}) > 0.99 and PhoneEnergy.next_signal_in({"elapsed": 15.0}) > 14.99, "the next exposure of the cracking comes every 15 run-seconds")


func _test_camera_rules() -> void:
	check(CameraModule.PHOTO.size() == 28 and CameraModule.PHOTO["rain"]["cap"].begins_with("雨幕后面站着一个没打伞的人") and CameraModule.PHOTO["cola"].get("secret", false), "the photo table is the Web version's: 26 anomalies, the window and the lift crowd")
	var cam := CameraModule.new()
	cam.reset()
	cam.set_context({"an": "", "gaze": false, "crowd": false, "day": 2, "tsec": 700.0, "place": "教学楼 1F", "clock": true})
	var calm := cam.plan()
	check(calm["an"] == "" and calm["cap"] == "照片里什么也没有。" and calm["kind"] == "" and calm["stamp"] == "%s  D2" % SchoolClock.fmt_clock(700.0), "with nothing happening the photo shows nothing extra")
	cam.set_context({"an": "rain", "gaze": false, "crowd": false, "day": 2, "tsec": 700.0, "place": "操场", "clock": false})
	var rain := cam.plan()
	check(rain["an"] == "rain" and rain["kind"] == "figure" and String(rain["cap"]).begins_with("照片里，雨幕后面") and rain["stamp"] == "--:--  D2" and rain["flash"], "a running anomaly adds its one extra thing; without a watch the stamp has no time")
	check(cam.plan()["seed"] == rain["seed"], "the same moment gives the same photo")
	cam.set_context({"an": "rain", "gaze": true, "crowd": false, "day": 2, "tsec": 700.0, "place": "x", "clock": false})
	check(cam.subject() == "window_gaze" and cam.plan()["kind"] == "eyes", "the window's eyes come before an anomaly")
	cam.set_context({"an": "rain", "gaze": true, "crowd": true, "day": 2, "tsec": 700.0, "place": "x", "clock": false})
	check(cam.subject() == "crowd", "the lift crowd comes first")
	cam.set_context({"an": "nothing", "gaze": false, "crowd": false, "day": 2, "tsec": 700.0, "place": "x", "clock": false})
	check(cam.subject() == "", "an anomaly without a photo adds nothing")
	# Album: newest first, at most six, records for public anomalies only.
	cam.set_context({"an": "rain", "gaze": false, "crowd": false, "day": 3, "tsec": 710.0, "place": "操场", "clock": true})
	var p := cam.plan()
	cam.add_photo(p, "AAAA", true)
	var ev := cam.take_events()
	check(ev[0]["kind"] == "say" and String(ev[0]["text"]).contains("闪光一亮") and ev[1]["kind"] == "record" and ev[1]["id"] == "photo_rain" and String(ev[1]["text"]).begins_with("手机里的照片（操场）"), "a photo says so, notes the clue and the flash drawing the patroller over")
	cam.set_context({"an": "cola", "gaze": false, "crowd": false, "day": 3, "tsec": 720.0, "place": "天台", "clock": true})
	cam.add_photo(cam.plan(), "BBBB", false)
	check(_of_kind(cam.take_events(), "record").is_empty(), "an internal anomaly's photo is not written into the notes")
	for i in 8:
		cam.add_photo(cam.plan(), "C%d" % i, false)
	check(cam.photos.size() == 6 and cam.photos[0]["img"] == "C7", "the album keeps the last six, newest first")
	var on_text := cam.copy_text()
	cam.toggle_flash()
	check(on_text.contains("闪光开着") and cam.copy_text().contains("闪光关着") and cam.copy_text().contains("6 张"), "the page text follows the flash and the album")
	var back := CameraModule.new()
	back.restore(cam.capture())
	check(back.photos == cam.photos and back.flash == cam.flash and back.validate(cam.capture()).is_empty() and not back.validate({"photos": [{"cap": 1}], "flash": true}).is_empty(), "the album saves and loads; a bad one is rejected")


func _test_snake_rules() -> void:
	var g := SnakeGame.new()
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 3
	var roll := func() -> float: return rnd.randf()
	g.start(roll)
	check(g.on and g.body == [Vector2i(8, 8)] and g.dir == Vector2i(1, 0) and g.cd == SnakeGame.COUNTDOWN, "a game starts with a one-segment snake in the middle, facing right, after a 3 s countdown")
	check(g.tick(1.0, Vector2i.ZERO, roll) and g.body.size() == 1 and g.body[0] == Vector2i(8, 8), "during the countdown nothing moves")
	g.tick(2.5, Vector2i.ZERO, roll)
	check(g.cd <= 0.0 and g.body[0] == Vector2i(8, 8), "(the countdown is over)")
	check(not g.tick(0.1, Vector2i.ZERO, roll) and g.tick(0.05, Vector2i.ZERO, roll) and g.body[0] == Vector2i(9, 8), "a step every 0.14 s")
	g.food = Vector2i(10, 8)
	g.tick(0.15, Vector2i.ZERO, roll)
	check(g.score == 1 and g.body.size() == 2 and g.food != Vector2i(10, 8), "eating grows the snake and scores a point")
	g.tick(0.15, Vector2i(-1, 0), roll)
	check(g.dir == Vector2i(1, 0), "with a body you cannot turn straight back")
	g.turn(Vector2i(0, 1))
	g.tick(0.15, Vector2i.ZERO, roll)
	check(g.dir == Vector2i(0, 1) and g.want == null, "a swipe is used on the next step")
	g.turn(Vector2i(-1, 0))
	g.tick(0.15, Vector2i(1, 0), roll)
	check(g.dir == Vector2i(1, 0) and g.want == Vector2i(-1, 0), "a held key beats a swipe; the swipe waits")
	var wall := SnakeGame.new()
	wall.start(roll)
	wall.cd = 0.0
	wall.body = [Vector2i(15, 8)]
	wall.tick(0.2, Vector2i.ZERO, roll)
	check(wall.dead and not wall.tick(0.2, Vector2i.ZERO, roll), "the wall ends the game")
	var own := SnakeGame.new()
	own.start(roll)
	own.cd = 0.0
	own.body = [Vector2i(5, 5), Vector2i(6, 5), Vector2i(6, 4), Vector2i(5, 4), Vector2i(4, 4)]
	own.dir = Vector2i(0, -1)
	own.tick(0.2, Vector2i.ZERO, roll)
	check(own.dead, "hitting yourself ends the game")
	var scorer := SnakeGame.new()
	check(scorer.gain(1.0) == 0.0, "no score, no rest")
	scorer.score = 3
	check(scorer.gain(1.0) == 12.0 and absf(scorer.gain(0.5) - 6.0) < 0.001, "rest is 6 + 2 a point, scaled by the pressure")
	scorer.score = 30
	check(scorer.gain(1.0) == 20.0, "at most 20")
	check(AchievementsModule.LIST.has("n.snake"), "the snake achievement exists")
	var ach := AchievementsModule.new(25)
	ach.reset()
	check(ach.fact({"kind": "snake", "score": 6}).is_empty() and ach.fact({"kind": "snake", "score": 7}).has("n.snake"), "seven bites unlock 一口一口")


func _test_facility_rules() -> void:
	var rooms := CampusData.rooms()
	var fac := FacilitiesModule.new(rooms, CampusData.layout("out"), CampusData.campus())
	fac.reset()
	fac.set_seed(3)
	# Rest: which tile offers what, the hint, the gain scaled by pressure, the cooldown in game minutes.
	fac.set_context(_fctx("teach1", {"meal": true}))
	check(fac.rest_for(rooms["teach1"], "w") == "wash" and fac.rest_for(rooms["dorm1"], "b") == "sleep" and fac.rest_for(rooms["lab5"], "p") == "piano"
		and fac.rest_for(rooms["lab3"], "n") == "pc" and fac.rest_for(rooms["canteen1"], "k") == "eat", "the rest activities sit where they did")
	fac.set_context(_fctx("canteen1", {"meal": false}))
	check(fac.rest_for(rooms["canteen1"], "k") == "" and fac.hint(rooms["canteen1"], "k") == "打饭窗口", "outside meal times the canteen window wants a coin")
	var field := Vector2.ZERO
	for o: Dictionary in CampusData.layout("out")["objects"]:
		if o["id"] == "field":
			field = Vector2((float(o["x"]) + float(o["w"]) / 2.0) * 2.0, (float(o["y"]) + float(o["h"]) / 2.0) * 2.0)
	check(fac.rest_out(field) == "run" and FacilitiesModule.rest_hint("run") == "沿跑道跑两圈（12 分钟）", "the field is for running two laps")
	fac.set_context(_fctx("teach1", {"rest_mul": 0.5, "clock": 800.0}))
	fac.rest("wash")
	var ev := fac.take_events()
	check(_of_kind(ev, "advance")[0]["minutes"] == 4.0 and absf(float(_of_kind(ev, "san")[0]["amount"]) - 4.0) < 0.001 and _of_kind(ev, "fact")[0]["key"] == "wash" and _of_kind(ev, "stamina")[0]["amount"] == 25.0,
		"washing takes 4 minutes, gives 8 SAN scaled by the pressure, 25 stamina")
	fac.set_context(_fctx("teach1", {"clock": 820.0}))
	fac.rest("wash")
	check(_notices(fac.take_events()).has("我：刚做过。现在没那个心情。"), "a rest has a cooldown in game minutes")
	fac.set_context(_fctx("teach1", {"clock": 900.0}))
	fac.rest("wash")
	check(not _of_kind(fac.take_events(), "san").is_empty(), "after the cooldown it works again")
	# Lab devices.
	var bag: Array = []
	fac.set_context(_fctx("lab1", {"bag": bag, "anomaly": {"active": false, "pre": "rain", "warn_ok": true, "minutes": 7, "cn": "下不完的雨"}}))
	fac.use(rooms["lab1"], "Z", 0, 0)
	ev = fac.take_events()
	check(not _of_kind(ev, "anomaly_lock").is_empty() and _notices(ev)[0].contains("「下不完的雨」。还有大约 7 分钟。"), "the pendulum names the coming anomaly and locks it")
	fac.use(rooms["lab1"], "Z", 0, 0)
	check(_notices(fac.take_events()).has("我：刚弄过。等一会儿。"), "the pendulum has a cooldown")
	fac.set_context(_fctx("lab1", {"bag": bag}))
	fac.use(rooms["lab1"], "N", 0, 0)
	check(bag.has("lens") and bool(fac.flags["lens"]), "the microscope gives the lens once")
	fac.set_context(_fctx("lab3", {"bag": bag}))
	fac.use(rooms["lab3"], "Q", 0, 0)
	check(bag.has("coil"), "the server gives the coil")
	fac.use(rooms["lab3"], "Q", 0, 0)
	check(_notices(fac.take_events()).back().contains("每一行的时间都是 11:40"), "and only once")
	var got_vial := false
	for i in 40:
		fac.set_context(_fctx("lab2", {"bag": bag, "clock": 1000.0 + i * 100.0}))
		fac.use(rooms["lab2"], "C", 0, 0)
		if bag.has("vial"):
			got_vial = true
			break
	check(got_vial, "the centrifuge separates the vial on a good spin")
	fac.set_context(_fctx("lab2", {"bag": bag}))
	fac.use(rooms["lab2"], "K", 0, 0)
	check(bag.has("goggles"), "the chemistry bench has goggles")
	# Canteen window, vending machine, altar, stall.
	var purse: Array = []
	fac.set_context(_fctx("canteen1", {"bag": purse}))
	fac.use(rooms["canteen1"], "k", 0, 0)
	check(_notices(fac.take_events()).has("我：窗口里的人头也不抬：「饭点过了。要吃，拿钱来。」"), "no coin, no meal")
	purse.append("coin")
	fac.use(rooms["canteen1"], "k", 0, 0)
	check(_of_kind(fac.take_events(), "choice").size() == 1, "with a coin the window offers a meal")
	fac.choose(0)
	ev = fac.take_events()
	check(not purse.has("coin") and _of_kind(ev, "san")[0]["amount"] == 24.0 and _of_kind(ev, "advance")[0]["minutes"] == 10.0, "a bought meal: 24 SAN, 10 minutes")
	var altar_room: Dictionary = {}
	for id: String in rooms:
		if String("".join(rooms[id]["grid"])).contains("A"):
			altar_room = rooms[id]
	fac.set_context(_fctx(String(altar_room.get("id", "x")), {"bag": purse}))
	fac.use(altar_room, "A", 0, 0)
	check(purse.has("coin"), "the altar hides a coin")
	fac.use(rooms["canteen1"], "M", 0, 0)
	check(not purse.has("coin"), "the vending machine eats it")
	fac.use(rooms["teach1"], "B", 0, 0)
	check(_notices(fac.take_events()).back().begins_with("我：第三个隔间的门从里面锁着") and fac.spots.has("stall"), "the third stall is locked from inside")
	# The bell: the thirteenth stroke ends bell13, otherwise exams start.
	fac.set_context(_fctx("bell1", {"anomaly": {"active": true, "id": "bell13"}}))
	fac.use(rooms["bell1"], "U", 0, 0)
	check(not _of_kind(fac.take_events(), "anomaly_end").is_empty(), "ringing the bell during the thirteen strokes ends them")
	fac.set_context(_fctx("bell1"))
	fac.use(rooms["bell1"], "U", 0, 0)
	check(not _of_kind(fac.take_events(), "exam_start").is_empty(), "otherwise it starts the exams")
	# Spots, map and compass.
	fac.set_context(_fctx("guard1"))
	fac.spot_tick()
	check(fac.spots.has("guard"), "being in the guard house marks it")
	var paper: Array = ["map"]
	fac.set_context(_fctx("teach1", {"bag": paper}))
	check(fac.use_item("map") and fac.spots.has("trash") and fac.spots.has("wall") and not _of_kind(fac.take_events(), "map").is_empty(), "the plan marks four places and opens the map")
	fac.set_context(_fctx("teach1", {"x": float(rooms["teach1"]["ox"]) + 30.0, "y": float(rooms["teach1"]["oy"]) + 30.0}))
	check(fac.use_item("compass") and _of_kind(fac.take_events(), "toast")[0]["text"].begins_with("罗盘 → "), "the compass points to the nearest way out")
	# The portal (portal.js).
	var p := FacilitiesModule.new(rooms, CampusData.layout("out"), CampusData.campus())
	p.reset()
	var kit: Array = []
	p.set_context(_fctx("lab1", {"bag": kit, "x": 700.0, "y": 700.0, "ang": 1.0}))
	p.use(rooms["lab1"], "K", 0, 0)
	ev = p.take_events()
	check(_of_kind(ev, "choice")[0]["text"] == "实验台后有一条覆着黑色黏液的狭窄隧道。", "the bench shows the tunnel")
	p.choose(0)
	ev = p.take_events()
	check(_of_kind(ev, "travel")[0]["world"] == "portal_tunnel" and p.portal["ret"]["x"] == 700.0, "entering the tunnel remembers where you stood")
	p.set_context(_fctx("lab4", {"bag": kit}))
	p.use(rooms["lab4"], "K", 0, 0)
	check(_of_kind(p.take_events(), "choice").is_empty(), "no blueprints before the diary")
	p.set_context(_fctx("portal_tunnel", {"bag": kit}))
	p.use(rooms["portal_tunnel"], "u", 0, 0)
	check(bool(p.portal["diary"]) and _notices(p.take_events())[0].contains("二楼、四楼和五楼"), "the diary tells where the blueprints are")
	p.use(rooms["portal_tunnel"], "j", 0, 5)
	check(_of_kind(p.take_events(), "travel")[0]["x"] == 700.0, "leaving puts you back at the bench")
	p.set_context(_fctx("lab2", {"bag": kit}))
	p.use(rooms["lab2"], "K", 0, 0)
	p.take_events()
	p.choose(0)
	check(not p.portal["blueprints"].has(2) and _notices(p.take_events())[0].contains("发光重液会沉底"), "a wrong answer explains and keeps the blueprint")
	p.use(rooms["lab2"], "K", 0, 0)
	p.take_events()
	p.choose(1)
	check(p.portal["blueprints"].has(2) and _notices(p.take_events())[0].contains("1 / 3"), "the right layer gives the second-floor blueprint")
	p.set_context(_fctx("lab4", {"bag": kit}))
	p.use(rooms["lab4"], "K", 0, 0)
	p.take_events()
	p.choose(2)
	p.take_events()
	p.set_context(_fctx("lab5", {"bag": kit}))
	for pick: int in [1, 2]:
		p.use(rooms["lab5"], "K", 0, 0)
		p.take_events()
		p.choose(pick)
		p.take_events()
	check(int(p.portal["work"][5]) == 2 and not p.portal["blueprints"].has(5), "the wiring order is pressed step by step")
	p.use(rooms["lab5"], "K", 0, 0)
	check(String(_of_kind(p.take_events(), "choice")[0]["text"]).ends_with("（已正确操作 2/3 步）"), "the progress is shown")
	p.choose(0)
	check(bool(p.portal["sketch"]) and _notices(p.take_events())[0].begins_with("我：三张图纸拼在一起"), "three blueprints make the sketch")
	p.set_context(_fctx("lab1", {"bag": kit}))
	p.use(rooms["lab1"], "K", 0, 0)
	check(_notices(p.take_events())[0].begins_with("我：草图上的四样，我还差「"), "the bench lists what is missing")
	for k: String in FacilitiesModule.PORTAL_PARTS:
		kit.append(k)
	p.use(rooms["lab1"], "K", 0, 0)
	check(_of_kind(p.take_events(), "choice")[0]["labels"][0] == "把它们接起来", "with the four parts the bench offers to assemble")
	p.choose(0)
	ev = p.take_events()
	check(bool(p.portal["open"]) and kit.is_empty() and not _of_kind(ev, "later").is_empty(), "assembling uses the parts and opens the circle")
	p.portal_ask()
	check(_of_kind(p.take_events(), "choice")[0]["labels"] == ["走进去", "再等一下"], "the circle waits")
	p.choose(0)
	check(_of_kind(p.take_events(), "ending")[0]["id"] == "portal", "walking in is 《门》")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(p.capture()))
	var back := FacilitiesModule.new(rooms, CampusData.layout("out"), CampusData.campus())
	back.reset()
	check(back.validate(saved).is_empty(), "facility state survives JSON")
	back.restore(saved)
	check(bool(back.portal["open"]) and back.portal["blueprints"].has(5) and back.blueprint_count() == 3, "and restores with integer floors")
	# The school side: leave slip, exams, the tunnel drains.
	var day := SchoolModule.new(rooms, CampusData.layout("out"), CampusData.campus())
	day.reset()
	check(day.use_leave() and day.on_leave() and not day.use_leave(), "a leave slip runs for 180 game minutes, once")
	day.viol = 100.0
	day.leave_until = 0.0
	check(not day.use_leave(), "with violations full the slip is refused")
	day.reset()
	day.tsec = 1200.0
	check(day.exam_start() and day.exam, "the bell turns the day into exams")
	var night := SchoolModule.new(rooms, CampusData.layout("out"), CampusData.campus())
	night.reset()
	night.tsec = 1350.0
	check(not night.exam_start(), "at night the bell gets no answer")
	check(night.danger_at("portal_tunnel") == "tunnel" and night.danger_at("garage1") == "garage" and night.danger_at("out") == "night", "the danger places")


func _notices(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e["kind"] == "notice").map(func(e: Dictionary) -> String: return e["text"])


func _test_routes_rules() -> void:
	var rt := RoutesModule.new(CampusData.campus())
	rt.reset()
	rt.set_seed(9)
	rt.use_terminal("lab3", false, 1)
	check(_notices(rt.take_events()).has("我：屏幕上是一串我看不懂的东西。旁边贴着一张便签：「门禁 U 盘插这里」。") and not rt.hacked and rt.clues.has("usb"), "the lab3 terminal without the USB drive only hints at it")
	rt.use_terminal("lab1", true, 1)
	check(_notices(rt.take_events()).has("我：这台终端连不上。"), "other terminals are not connected")
	rt.use_data("admin3")
	check(_notices(rt.take_events()).has("我：得先在实验楼三楼的网络中心写入白名单。"), "the admin3 data machine needs the network centre first")
	rt.use_terminal("lab3", true, 1)
	check(rt.hacked and rt.clues.has("comp"), "the USB drive writes the whitelist at lab3")
	rt.take_events()
	rt.tick(5.0)
	check(rt.take_events().is_empty(), "the reminder waits 5.2 s")
	rt.tick(0.3)
	check(_notices(rt.take_events()).has("我：还得去行政楼三楼，把数据同步过去。"), "then the admin3 reminder is said")
	rt.use_data("admin3")
	check(rt.data_synced and _notices(rt.take_events()).has("我：同步完成。照片底下写着：已登记。西小门现在认得我了。"), "the admin3 machine syncs the whitelist")
	rt.use_data("admin3")
	check(rt.take_events()[0]["kind"] == "toast", "syncing twice only reports it")
	check(rt.gate_at(Vector2(401, 1250)) == "w" and rt.gate_at(Vector2(1028, 190)) == "n" and rt.gate_at(Vector2(772, 2790)) == "s" and rt.gate_at(Vector2(1000, 1000)) == "", "gate positions follow GATE_N / W / S within 70 units")
	var fresh := RoutesModule.new(CampusData.campus())
	fresh.reset()
	fresh.use_gate("w", 1)
	check(_notices(fresh.take_events()).has("我：小门上挂着锁，旁边那台闸机的屏幕亮着：「未登记」。") and fresh.clues.has("gatew"), "the west gate says unregistered before the sync")
	fresh.use_gate("n", 1)
	check(_notices(fresh.take_events())[0].begins_with("我：北门的闸机屏幕上显示：「查无此人」"), "the north gate line")
	# The quiz: three questions, wrong answers cost SAN, swap the question and keep the progress.
	rt.use_gate("w", 1)
	var asked := rt.take_events()
	check(asked[0]["kind"] == "choice" and String(asked[0]["text"]).begins_with("白名单验证 1/3："), "the west gate opens the quiz after the sync")
	var order: Array = rt.face_quiz["order"].duplicate()
	var first: Dictionary = RoutesModule.QUESTIONS[order[0]]
	var wrong := (int(first["answer"]) + 1) % 3
	rt.choose(wrong, "easy")
	var after_wrong := rt.take_events()
	check(after_wrong[0]["kind"] == "san" and absf(float(after_wrong[0]["amount"]) + 4.0 * 0.82) < 0.001, "a wrong answer costs 4 SAN (×0.82 on 预知梦)")
	check(after_wrong.back()["kind"] == "choice" and String(after_wrong.back()["text"]).contains(RoutesModule.EXPLANATIONS[order[0]]), "and shows the explanation")
	check(rt.face_quiz["order"][0] != order[0] and rt.face_quiz["used"].size() == 4, "the question is swapped for one not asked yet")
	rt.choose(0, "easy")
	var again := rt.take_events()
	check(String(again[0]["text"]).begins_with("白名单验证 1/3："), "continuing re-asks from the same question number")
	for n in 3:
		var q: Dictionary = RoutesModule.QUESTIONS[rt.face_quiz["order"][int(rt.face_quiz["done"])]]
		rt.choose(int(q["answer"]), "easy")
		var next := rt.take_events()
		if n < 2:
			check(String(next[0]["text"]).begins_with("白名单验证 %d/3：" % (n + 2)), "answering %d moves on to question %d" % [n + 1, n + 2])
		else:
			check(next[0]["text"] == "闸机亮起绿灯。外面的路安静得出奇。", "three correct answers open the gate")
	rt.choose(0, "easy")
	var end_events := rt.take_events()
	check(end_events.size() == 1 and end_events[0]["kind"] == "ending" and end_events[0]["id"] == "face" and rt.ending == "face", "walking through is the 《白名单》 ending")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(rt.capture()))
	check(rt.validate(saved).is_empty(), "route state survives JSON")
	var back := RoutesModule.new(CampusData.campus())
	back.reset()
	back.restore(saved)
	check(back.hacked and back.data_synced and back.face_quiz["done"] == 3 and back.ending == "face", "route state restores")
	saved["data"] = true
	saved["hacked"] = false
	check(not back.validate(saved).is_empty(), "a sync without the network write is refused")
	var trash := RoutesModule.new(CampusData.campus())
	trash.reset()
	trash.use_trash("teach1", 1)
	check(_notices(trash.take_events()).has("我：这个桶太小了。"), "only the trash room bin is the trap")
	trash.use_trash("trash1", 1)
	var trapped := trash.take_events()
	check(trapped[0]["kind"] == "kill" and trapped[0]["fx"] == "trash" and trapped[0]["source"] == "trash", "the trash bin is the 'trash' death")
	var card := RoutesModule.card("face")
	check(card["title"] == "《白名单》" and card["tag"] == "真 结 局" and card["lines"].size() == 4, "the ending card carries the old title and four lines")
	var fate := StoryModule.new()
	fate.reset()
	check(not fate.trigger_ending("face").is_empty() and fate.ended == "face" and fate.over() and fate.trigger_ending("car").is_empty(), "an ending ends the run once")


func _actx(scene: String, w: Vector2, extra: Dictionary = {}) -> Dictionary:
	var c := {"scene": scene, "x": w.x, "y": w.y, "ang": 0.0, "tsec": 700.0, "day": 1, "diff": "easy", "san": 100.0, "viol": 0.0, "moving": false,
		"running": false, "seated": false, "night": false, "need_where": "教室", "tile": ".", "on_field": false, "in_classroom": false, "game_clock": 700.0,
		"pressure_anomaly": 1.0, "bag": [], "item_names": {}, "dead": false, "hiding": false, "patrol_chase": false, "choice_open": false, "brolly": false,
		"inspection_quiet": false, "in_lift": false}
	c.merge(extra, true)
	return c


func _an_run(am: AnomalyModule, ctx: Dictionary, seconds: float, stop_on: String = "") -> Array:
	var got: Array = []
	var t := 0.0
	while t < seconds:
		am.set_context(ctx)
		am.tick(0.1)
		for e: Dictionary in am.take_events():
			got.append(e)
			if e["kind"] == stop_on:
				return got
		t += 0.1
	return got


func _an_force(am: AnomalyModule, id: String, ctx: Dictionary) -> void:
	am.set_context(ctx)
	am.an["id"] = id
	am.an["active"] = true
	am.an["t"] = 0.0
	am.an["acc"] = 0.0
	am.an["data"] = {}
	am._on(id)
	am.take_events()


func _kinds(events: Array) -> Array:
	return events.map(func(e: Dictionary) -> String: return e["kind"])


func _test_anomaly_rules() -> void:
	check(AnomalyModule.IDS.size() == 26 and AnomalyModule.DEFS.size() == 26, "all 26 anomalies are defined")
	for id: String in AnomalyModule.IDS:
		check(AnomalyModule.DEFS[id].has("msg") and AnomalyModule.DEFS[id].has("dfx"), "anomaly %s has its message and death scene" % id)
	var t1 := CampusData.layout("teach1")
	var seat_w := CampusGeometry.tile_center(t1, 40, 9)
	var class_ctx := _actx("teach1", seat_w, {"in_classroom": true, "tile": "d"})
	var am := CampusData.make_anomaly()
	am.reset()
	am.set_seed(5)
	am.begin_run("easy")
	check(is_equal_approx(float(am.an["next"]), 60.0), "the first anomaly is due after 60 s on 预知梦")
	var hard := CampusData.make_anomaly()
	hard.reset()
	hard.begin_run("hard")
	check(is_equal_approx(float(hard.an["next"]), 40.0), "and after 40 s on 梦魇")
	var evs := _an_run(am, class_ctx, 61.0, "notice")
	check(am.is_active() and am.active_id() == "chalk", "the first anomaly of a run is the blackboard foretelling (%s)" % am.active_id())
	check(evs.size() > 0 and evs[0]["text"] == AnomalyModule.DEFS["chalk"]["msg"], "its first line is the old message")
	_an_run(am, class_ctx, 20.0)
	check(not am.is_active() and float(am.an["next"]) >= 10.0 and am.hist == ["chalk"], "it ends after 16 s and the next one is paced (%.1f s)" % float(am.an["next"]))
	am.set_context(class_ctx)
	var iv := am._interval()
	check(iv >= 10.0 and iv <= 80.0, "intervals stay inside the old 40–64 s band, scaled by SAN, violation and pressure (%.1f)" % iv)
	# No lethal anomaly in the first-day dream; the same kind never runs twice in a row.
	var picks := {}
	var lethal_early := 0
	for i in 60:
		var pm := CampusData.make_anomaly()
		pm.reset()
		pm.set_seed(100 + i)
		pm.hist = ["turn"]
		pm.set_context(_actx("out", Vector2(1068, 1984), {"need_where": "自由"}))
		var pick := pm._pick()
		picks[pick] = true
		if pick != "" and AnomalyModule.DEFS[pick].get("late", false):
			lethal_early += 1
		if i == 0:
			check(pick != "turn", "the previous anomaly is not picked again")
	check(lethal_early == 0, "late anomalies stay out of the first-day dream")
	# Lethal ones.
	var field := Vector2(1068, 1984)
	var rain := CampusData.make_anomaly()
	rain.reset()
	rain.set_seed(1)
	var out_ctx := _actx("out", field, {"need_where": "自由"})
	rain.set_context(out_ctx)
	check(not rain.under_roof(), "the test spot is not under a roof")
	_an_force(rain, "rain", out_ctx)
	var got := _an_run(rain, out_ctx, 20.0, "kill")
	check(_kinds(got).has("kill") and got[got.size() - 1]["fx"] == "drown", "unsheltered in the rain you drown after 14 s")
	var sheltered := CampusData.make_anomaly()
	sheltered.reset()
	_an_force(sheltered, "rain", _actx("teach1", seat_w))
	check(not _kinds(_an_run(sheltered, _actx("teach1", seat_w), 25.0)).has("kill"), "indoors the rain never kills")
	var moth := CampusData.make_anomaly()
	moth.reset()
	_an_force(moth, "moth", out_ctx)
	got = _an_run(moth, out_ctx, 10.0, "kill")
	check(_kinds(got).has("kill") and got[got.size() - 1]["fx"] == "swarm", "staying by the moths kills in 6.5 s")
	var run_away := _an_run(moth, _actx("out", field + Vector2(400, 0), {"need_where": "自由"}), 3.0)
	check(not _kinds(run_away).has("kill"), "walking away from the swarm source stops it")
	var rite := CampusData.make_anomaly()
	rite.reset()
	var lab: Dictionary = CampusData.layout("lab2")
	var lab_ctx := _actx("lab2", CampusGeometry.tile_center(lab, 20, 10))
	_an_force(rite, "rite", lab_ctx)
	var circle: Dictionary = rite.an["data"]["c"]
	var stand := _actx("lab2", Vector2(circle["x"], circle["y"]))
	got = _an_run(rite, stand, 5.0, "kill")
	check(_kinds(got).has("kill") and got[got.size() - 1]["fx"] == "ring", "standing in the chalk circle kills in 2.2 s")
	var necker := CampusData.make_anomaly()
	necker.reset()
	var edge := _actx("out", Vector2((830.0 - 20.0) * 2.0, 1500.0), {"need_where": "自由", "day": 2})
	_an_force(necker, "necker", edge)
	got = _an_run(necker, edge, 6.0, "kill")
	check(_kinds(got).has("kill") and got[got.size() - 1]["fx"] == "neck", "next to the east wall the long-necked passer kills")
	var cup := CampusData.make_anomaly()
	cup.reset()
	var tb: Dictionary = {}
	for o: Dictionary in CampusData.layout("out")["objects"]:
		if o["id"] == "teach":
			tb = o
	var below := Vector2((float(tb["x"]) + float(tb["w"]) / 2.0) * 2.0, float(tb["y"]) * 2.0 - 9.0)
	var cup_ctx := _actx("out", below, {"need_where": "自由"})
	cup.set_context(cup_ctx)
	check(cup._when("cup"), "next to a tall wall on the open side the cup can fall")
	_an_force(cup, "cup", cup_ctx)
	got = _an_run(cup, cup_ctx, 6.0, "kill")
	check(_kinds(got).has("kill") and got[got.size() - 1]["fx"] == "floor", "standing still under the window the cup lands on you")
	var dodge := CampusData.make_anomaly()
	dodge.reset()
	_an_force(dodge, "cup", cup_ctx)
	dodge._cola_owe() # anStart owes the can when a cup really starts; the forced start skips it
	var step_away := _actx("out", below + Vector2(60, 0), {"need_where": "自由"})
	var t_run := 0.0
	var killed := false
	while t_run < 6.0:
		var ctx_now := cup_ctx if t_run < 0.9 else step_away
		dodge.set_context(ctx_now)
		dodge.tick(0.1)
		killed = killed or _kinds(dodge.take_events()).has("kill")
		t_run += 0.1
	check(not killed, "moving away once it falls dodges the cup")
	check(dodge.cola_pending != null, "a cup that started owes one falling can")
	# Cola: at night, outside, after the settle time.
	var night_ctx := _actx("out", field, {"need_where": "宿舍", "night": true, "tsec": 1400.0})
	dodge.an["active"] = false
	dodge.an["id"] = ""
	dodge.an["next"] = 99.0
	_an_run(dodge, night_ctx, 2.0)
	check(not dodge.is_active(), "the can waits through the settle time")
	_an_run(dodge, night_ctx, 1.0)
	check(dodge.is_active() and dodge.active_id() == "cola" and dodge.cola_pending == null, "then the owed can starts")
	# Non-lethal rules.
	var broad := CampusData.make_anomaly()
	broad.reset()
	_an_force(broad, "broad", _actx("teach1", seat_w, {"moving": true}))
	got = _an_run(broad, _actx("teach1", seat_w, {"moving": true}), 3.0, "hurt")
	check(_kinds(got).has("hurt") and absf(float(got[got.size() - 1]["amount"]) - 18.0 * 0.9) < 0.001, "moving during the roll call costs 18 SAN (×0.9 on 预知梦)")
	var bell := CampusData.make_anomaly()
	bell.reset()
	_an_force(bell, "bell13", class_ctx)
	got = _an_run(bell, _actx("teach1", seat_w, {"seated": true}), 5.0)
	check(not bell.is_active() and _kinds(got).has("notice"), "sitting in teach1 during the bells ends it kindly")
	# The roster: ignoring it costs 18 violation when it ends.
	var roster := CampusData.make_anomaly()
	roster.reset()
	_an_force(roster, "roster", class_ctx)
	got = _an_run(roster, _actx("teach1", seat_w + Vector2(300, 0)), 20.0)
	check(_kinds(got).has("violation") and not roster.is_active(), "an ignored roster ends with +18 violation")
	var near_ctx := _actx("teach1", seat_w)
	roster.reset()
	_an_force(roster, "roster", near_ctx)
	check(roster.near_roster(), "standing by the roster allows the interaction")
	roster.use_roster(true)
	var written := roster.take_events()
	check(_kinds(written).has("san") and roster.an["data"]["done"], "writing the name back with a pen restores SAN and settles it")
	# A timed choice (turn): not turning round for 7.8 s is the good outcome.
	var turn := CampusData.make_anomaly()
	turn.reset()
	turn.set_seed(2)
	_an_force(turn, "turn", class_ctx)
	turn.an["data"]["smile"] = false
	var asked := _an_run(turn, class_ctx, 2.0, "choice")
	check(_kinds(asked).has("choice") and asked[asked.size() - 1]["labels"] == ["不回头", "回头看"], "the tap on the shoulder asks whether to look back")
	turn.choose("no")
	got = _an_run(turn, class_ctx, 9.0)
	check(_kinds(got).has("san") and not turn.is_active(), "not looking back ends it with +6 SAN")
	# Save round trip.
	var data: Dictionary = JSON.parse_string(JSON.stringify(rite.capture()))
	check(rite.validate(data).is_empty(), "anomaly state survives JSON")
	var again := CampusData.make_anomaly()
	again.reset()
	again.restore(data)
	check(again.hist == rite.hist and again.an["active"] == rite.an["active"], "anomaly state restores")
	data["an"]["id"] = "not-an-anomaly"
	check(not rite.validate(data).is_empty(), "unknown anomaly ids are refused")


func _night_hunt(scene: String) -> bool:
	var pm := CampusData.make_patrol()
	pm.reset()
	var room: Variant = CampusData.layout(scene) if scene != "out" else null
	var w := Vector2(1000, 1000) if room == null else CampusGeometry.tile_center(room, 10, 5)
	pm.set_context(_pctx(scene, w, {"night": true, "need_where": "宿舍"}))
	return pm.eligible()


func _test_campus_app() -> void:
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new(_test_path)
	app.settings = GameSettings.new(_test_path.get_base_dir() + "/settings.json")
	root.size = Vector2i(1280, 720)
	root.add_child(app)
	await _frames()
	app.start_new_game()
	await _frames(5)
	check(app.session != null and app.router.current.world_id == &"teach1", "new game opens the formal teach1 scene")
	var world := app.router.get_child(0) as CampusWorld
	check(world != null and world.get_node_or_null("Model") != null, "teach1 model loaded from the exported glb")
	check(world.find_children("*", "MultiMeshInstance3D", true, false).size() > 50, "instanced furniture rebuilt as MultiMesh")
	check(world.door_keys().size() == 8, "teach1 has its eight classroom doors as bodies")
	var lit := world.lighting
	check(lit != null and lit.room_lights.size() == 5, "teach1 lamps: three lit classrooms, the corridor and the lift hall (ROOM_LIGHTS)")
	check(lit.live_count() > 0, "lamp panel materials are found for flicker")
	check(lit.sun_at(12.3)["day"] > 0.99 and lit.sun_at(0.0)["day"] < 0.01, "sunAt: full day at noon, night at midnight")
	check(lit.lamp_health(0) == 1.0, "the first lamp of a room always works")
	var start: Array = app.player.capture_pose()["position"]
	check(absf(start[0] - 17.3) < 0.01 and absf(start[2] - 0.39) < 0.01 and app.school().seated, "a run starts seated on the own seat (ClassroomLayout.anchor)")
	check(app.school().at_my_seat("teach1", CampusGeometry.to_world(CampusData.layout("teach1"), start[0], start[2])), "the start seat counts as the own seat")
	Input.action_press("move_left")
	await _frames(2)
	Input.action_release("move_left")
	await _frames(1)
	var stood: Array = app.player.capture_pose()["position"]
	check(not app.school().seated and absf(stood[2] - 1.4456) < 0.15, "moving stands up into the aisle where leaveSeat puts the body")
	# Real physics: walking into the classroom's north window wall must stop.
	var t1 := CampusData.layout("teach1")
	app.player.restore_pose(_campus_pose(t1, CampusGeometry.tile_center(t1, 54, 9), -PI * 0.5))
	await _frames()
	Input.action_press("move_forward")
	await _frames(90)
	Input.action_release("move_forward")
	var stop: Array = app.player.capture_pose()["position"]
	var wall_z := CampusGeometry.to_scene(t1, Vector2(0, float(t1["oy"]) + 7 * float(t1["th"])))
	check(stop[2] > wall_z.y + 0.30 and stop[2] < wall_z.y + 0.40, "north wall stops the body at its radius (z=%.3f)" % stop[2])
	# Closed door blocks, open door lets the body through.
	var corridor := CampusGeometry.tile_center(t1, 10, 17)
	app.player.restore_pose(_campus_pose(t1, corridor, -PI * 0.5))
	await _frames()
	Input.action_press("move_forward")
	await _frames(60)
	Input.action_release("move_forward")
	var at_door: Array = app.player.capture_pose()["position"]
	var door_edge := CampusGeometry.to_scene(t1, Vector2(0, float(t1["oy"]) + 16 * float(t1["th"])))
	check(at_door[2] > door_edge.y + 0.3, "closed door blocks the corridor side")
	app.player.request_interaction()
	await _frames(3)
	check(app.campus().is_open("teach1:10:15"), "E with no raycast target reaches the campus rules")
	Input.action_press("move_forward")
	await _frames(90)
	Input.action_release("move_forward")
	var through: Array = app.player.capture_pose()["position"]
	check(through[2] < door_edge.y - 1.0, "open door lets the body into the classroom")
	# Walk out of the seamless south door and back in.
	var spec: Dictionary = CampusData.campus()["campus_doors"]["doors"][0]
	var port := CampusGeometry.door_port(t1, spec)
	app.player.restore_pose(_campus_pose(t1, port["p"] - Vector2(0, 6), PI * 0.5))
	await _frames()
	Input.action_press("move_forward")
	await _frames(60)
	Input.action_release("move_forward")
	await _frames(3)
	check(app.router.current.world_id == &"out" and app.session.world_id == "out", "walking through the south door switches to the campus")
	check(app.router.get_child(0) is CampusWorld, "campus outside scene built")
	app.player.place(_campus_pose(null, port["p"] + CampusGeometry.shift_of(t1) + Vector2(0, 8), -PI * 0.5))
	await _frames()
	Input.action_press("move_forward")
	await _frames(60)
	Input.action_release("move_forward")
	await _frames(3)
	check(app.session.world_id == "teach1", "walking back through the doorway re-enters teach1")
	app.pause_game()
	app.save_game()
	var saved: Dictionary = app.saves.read()["data"]
	check(saved["world_id"] == "teach1" and saved["modules"]["campus.world"]["data"]["open_doors"] == ["teach1:10:15"], "save keeps scene and opened doors")
	app.return_to_menu()
	app.load_game()
	await _frames(3)
	var reloaded := app.router.get_child(0) as CampusWorld
	check(app.campus().is_open("teach1:10:15") and reloaded != null, "load restores the campus door state")
	app.return_to_menu()
	for id: String in CampusData.room_ids():
		var err := app.router.switch_to(id)
		check(err.is_empty(), "world %s registered and instantiable" % id)
	app.router.clear()
	await _test_stair_walk(app)
	app.queue_free()
	await _frames()


## Steer the real CharacterBody3D through scene-metre waypoints (yaw from the heading).
func _walk(app: GameApp, points: Array, frames_each: int = 120) -> void:
	for target: Vector2 in points:
		Input.action_press("move_forward")
		for _i in frames_each:
			var p := app.player.position
			var d := target - Vector2(p.x, p.z)
			if d.length() < 0.15:
				break
			app.player.rotation.y = atan2(-d.x, -d.y)
			await physics_frame
		Input.action_release("move_forward")
	await _frames(2)


func _test_stair_walk(app: GameApp) -> void:
	app.start_new_game()
	await _frames(3)
	app._stand_up()
	var t1 := CampusData.layout("teach1")
	var s := CampusPortals.stair_config(CampusData.campus()["stair_layout"], "stair_teach_w")
	var port := CampusPortals.stair_port(s, 0, CampusData.rooms(), CampusData.layout("out"))
	var p: Vector2 = port["p"]
	app.player.restore_pose(_campus_pose(t1, p - Vector2(0, 14), PI * 0.5))
	await _frames()
	await _walk(app, [CampusGeometry.to_scene(t1, p + Vector2(0, 3))])
	check(app.session.world_id == "stair_teach_w", "walking into the west stair doorway enters the stairwell")
	# One full storey along StairGeometry's walking line, then out of the corridor.
	await _walk(app, [Vector2(-1.25, 0.8), Vector2(-1.25, 5.6), Vector2(-1.25, 6.4), Vector2(1.25, 6.4), Vector2(1.25, 5.6), Vector2(1.25, 0.8), Vector2(0.0, -0.3), Vector2(0.0, -3.2)], 240)
	check(app.session.world_id == "teach2", "climbing one flight pair and walking out reaches teach2 (now %s, y=%.2f)" % [app.session.world_id, app.player.position.y])
	check(absf(app.player.position.y) < 0.2, "teach2 floor is at the scene's own ground level")
	await _test_spiral_walk(app)
	await _test_elevator_walk(app)
	await _test_patrol_app(app)
	await _test_anomaly_fx(app)
	await _test_audio(app)
	await _test_whitelist_route(app)
	await _test_achievement_flow(app)
	await _test_archive(app)
	await _test_death_scene(app)
	await _test_car_route(app)
	await _test_portal_route(app)
	await _test_dismissal_route(app)
	await _test_cyber_route(app)
	await _test_vault_app(app)
	await _test_lesson_app(app)
	await _test_speedrun_app(app)
	await _test_marks_app(app)
	await _test_sensory_app(app)
	await _test_settings_app(app)
	await _test_checkup_app(app)
	await _test_death_flow(app)
	app.return_to_menu()


## Synthesised sound: every cue exists, layers follow the context, mute works, rules are untouched.
func _test_audio(app: GameApp) -> void:
	var fx := app.audio
	check(fx.ids().size() == 139, "the baked bank has the 139 public recipes (%d)" % fx.ids().size())
	check(not fx.ids().any(func(id: String) -> bool: return id.begins_with("void.") or id == "death.void"), "hidden content's sounds are not baked")
	for id: String in ["step.tile", "step.garage", "threat.heartLow", "event.bellEnd", "event.dismissal", "death.generic", "ui.click", "anomaly.bell13", "music.box"]:
		var stream := fx.stream_of(id)
		check(stream is AudioStreamOggVorbis and stream.get_length() > 0.02 and not (stream as AudioStreamOggVorbis).loop, "%s is a baked one-shot" % id)
	check(fx.stream_of("nothing") == null and not fx.play("nothing"), "an unknown sound is nothing, not an error")
	var court := Vector2.ZERO
	var out := CampusData.layout("out")
	for o: Dictionary in out["objects"]:
		if o["k"] == "court":
			court = Vector2(float(o["x"]) + float(o["w"]) * 0.5, float(o["y"]) + float(o["h"]) * 0.5) * float(out["SC"])
	check(AudioFx.surface("garage1", false, Vector2.ZERO, [], 1.0) == "garage" and AudioFx.surface("teach6", false, Vector2.ZERO, [], 1.0) == "roof"
		and AudioFx.surface("bell1", true, Vector2.ZERO, [], 1.0) == "stair" and AudioFx.surface("teach1", false, Vector2.ZERO, [], 1.0) == "tile"
		and AudioFx.surface("out", false, court, out["objects"], float(out["SC"])) == "court" and AudioFx.surface("out", false, Vector2(-9999, -9999), out["objects"], float(out["SC"])) == "road",
		"footing: garage, roof, spiral stairs, tile; outdoors the court, otherwise the road")
	fx.update(0.1, {"menu": true})
	for _i in 30:
		fx.update(0.1, {"menu": true})
	check(fx.bed_playing("pad_menu") and fx.bed_gain("pad_menu") > 0.02, "the menu has its low pad")
	app.saves.clear()
	app.start_new_game()
	await _frames(3)
	app._stand_up()
	var t1 := CampusData.layout("teach1")
	app.travel("teach1", _campus_pose(t1, CampusGeometry.tile_center(t1, 30, 17), PI), false)
	app.patrol().pat["safety"] = 999.0
	var base := {"scene": "teach1", "out": false, "san": 100.0, "surface": "tile"}
	fx.played.clear()
	var walk := base.duplicate()
	walk["moving"] = true
	fx.update(0.1, walk)
	check(fx.played.has("step.tile"), "walking indoors steps on tile")
	fx.played.clear()
	var low := base.duplicate()
	low["bpm"] = 120.0
	low["body"] = 0.8
	fx.update(0.1, low)
	check(fx.played.has("threat.heartLow") and fx.played.has("threat.breath"), "a shaken body: heartbeat at the sensory rate and breath")
	fx.played.clear()
	var pat := base.duplicate()
	pat["patrol_pos"] = Vector3(3, 0, 3)
	fx.update(0.1, pat)
	check(fx.played.has("step.tile"), "the patroller's footsteps play in space")
	for _i in 30:
		fx.update(0.1, base)
	check(fx.bed_playing("hum") and fx.bed_playing("pad_in_calm") and not fx.bed_playing("wind"), "indoors: the lamp hum and the indoor pad, no wind")
	var outdoors := {"scene": "out", "out": true, "san": 100.0, "anomaly": "rain", "night": 0.0}
	for _i in 40:
		fx.update(0.1, outdoors)
	check(fx.bed_playing("wind") and fx.bed_playing("rain") and fx.bed_playing("pad_day_tense") and fx.bed_gain("hum") < 0.001, "outdoors in the rain: wind, rain and a tenser day pad; the hum fades")
	var dark := base.duplicate()
	dark["blackout"] = true
	for _i in 40:
		fx.update(0.1, dark)
	check(fx.bed_gain("hum") < 0.001, "a blackout kills the hum")
	fx.played.clear()
	fx.anomaly_start("bell13")
	fx.death("swarm")
	fx.death("no_such_death")
	check(fx.played.has("anomaly.base") and fx.played.has("anomaly.bell13") and fx.played.has("death.swarm") and fx.played.has("death.generic"),
		"an anomaly opens with the low drop and its own recipe; a death plays its own sound, or the generic one")
	fx.played.clear()
	app._add_item("pen")
	app.ui.flash_light(0.5)
	check(fx.played.has("ui.pickup") and app.ui.bolt_level() > 0.3, "picking up plays the pickup; lightning whitens the screen")
	var weird := app.anomaly()
	weird.events.append({"kind": "smile", "mode": "jump"})
	app._anomaly_step(0.0, app.school(), CampusData.layout("teach1"), app.player.capture_pose())
	check(fx.played.has("threat.smileJump"), "the smile in your face screams at the ear")
	fx.update(0.1, base)
	fx.play("event.bellEnd")
	await _frames(3)
	check(app.ui.captions_text().contains("下课铃"), "the HUD shows the caption under the status card")
	app.audio.muted = true
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "mute silences the master bus")
	app.audio.muted = false
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "unmute restores it")
	fx.stop_all()
	check(not fx.bed_playing("wind") and not fx.bed_playing("hum"), "stop_all stops the beds")


## The placeholder anomaly props follow the module state and vanish when it ends.
func _test_anomaly_fx(app: GameApp) -> void:
	app.saves.clear()
	app.start_new_game()
	await _frames(3)
	app._stand_up()
	var t1 := CampusData.layout("teach1")
	var spot := CampusGeometry.tile_center(t1, 30, 17)
	app.travel("teach1", _campus_pose(t1, spot, PI), false)
	app.patrol().pat["safety"] = 999.0
	await _frames(3)
	var fx: AnomalyFx = app._campus_world().anomaly_fx
	check(fx != null and fx.current() == "" and fx.shown_count() == 0, "no anomaly, no props")
	var weird := app.anomaly()
	var me := Vector2(spot.x, spot.y)
	var datas := {
		"moth": {"src": {"x": me.x + 40.0, "y": me.y}}, "exercise": {"src": {"x": me.x + 40.0, "y": me.y}}, "hand": {"chosen": null},
		"chalk": {"until": 800.0}, "roster": {"rx": me.x, "ry": me.y, "done": false}, "leak": {"pts": [{"x": me.x + 20.0, "y": me.y}, {"x": me.x + 30.0, "y": me.y + 9.0}]},
		"rite": {"c": {"x": me.x + 30.0, "y": me.y}}, "twin": {"x": me.x + 40.0, "y": me.y, "room": "teach1"},
		"turn": {"chosen": null, "smile": true}, "repeat": {"chosen": null}, "stare": {}, "feast": {}, "shadow": {"acc": 0.0}, "lamps": {}, "cold": {"chosen": null},
	}
	for id: String in datas:
		weird.an["id"] = id
		weird.an["active"] = true
		weird.an["t"] = 0.0
		weird.an["next"] = 999.0
		weird.an["data"] = (datas[id] as Dictionary).duplicate(true)
		weird.an["data"]["scene"] = "teach1"
		await _frames(2)
		check(fx.current() == id and fx.shown_count() > 0, "%s draws its props" % id)
		weird.end_now()
		await _frames(2)
		check(fx.current() == "" and fx.shown_count() == 0, "%s props go away with it" % id)
	weird.an["id"] = "broad"
	weird.an["active"] = true
	weird.an["data"] = {"scene": "teach1"}
	await _frames(2)
	check(fx.shown_count() == 0, "a sound-only anomaly (the broadcast call) draws nothing")
	weird.end_now()
	weird.an["active"] = true
	weird.an["data"] = {"scene": "out"}
	weird.an["id"] = "moth"
	weird.an["data"]["src"] = {"x": 0.0, "y": 0.0}
	await _frames(2)
	check(fx.shown_count() == 0, "props only show in the scene the anomaly started in")
	weird.end_now()
	# The cup and the cola are outdoor anomalies: indoors the rules end them at once.
	var out := CampusGeometry.to_scene(null, Vector2(1000, 1000))
	app.travel("out", {"position": [out.x, 0.05, out.y], "yaw": 0.0, "pitch": 0.0}, false)
	app.patrol().pat["safety"] = 999.0
	await _frames(3)
	fx = app._campus_world().anomaly_fx
	for id: String in ["cup", "cola"]:
		weird.an["id"] = id
		weird.an["active"] = true
		weird.an["t"] = 0.0
		weird.an["next"] = 999.0
		weird.an["data"] = {"scene": "out", "phase": 0, "wob": 30.0, "warn": 30.0, "wall": {"x": 520.0, "y": 480.0, "d": 40.0, "id": "teach", "m": 5.0}}
		await _frames(2)
		check(fx.current() == id and fx.shown_count() > 0, "%s draws its prop outdoors" % id)
		weird.end_now()
		await _frames(2)
		check(fx.shown_count() == 0, "%s prop goes away" % id)


func _test_patrol_app(app: GameApp) -> void:
	app.start_new_game()
	await _frames(3)
	app._stand_up()
	var t1 := CampusData.layout("teach1")
	var spot := CampusGeometry.tile_center(t1, 12, 17)
	app.travel("teach1", _campus_pose(t1, spot, -PI * 0.5), false)
	await _frames(3)
	var watcher := app.patrol()
	check(app.campus().hint("teach1", app.player.capture_pose()) == "躲进柜子", "the locker cell offers to hide")
	app._campus_interact()
	await _frames(2)
	check(bool(watcher.hide["on"]) and app.player.hiding, "E on the locker hides the player")
	var inside: Array = app.player.capture_pose()["position"]
	var cell_center := CampusGeometry.to_scene(t1, CampusGeometry.tile_center(t1, 12, 16))
	check(absf(inside[0] - cell_center.x) < 0.05 and absf(inside[2] - (cell_center.y + 0.12 * 1.0)) < 0.4, "the body sits inside the locker cell")
	Input.action_press("move_forward")
	await _frames(20)
	Input.action_release("move_forward")
	var still: Array = app.player.capture_pose()["position"]
	check(Vector2(still[0] - inside[0], still[2] - inside[2]).length() < 0.01, "a hidden player cannot walk")
	app._campus_interact()
	await _frames(2)
	check(not bool(watcher.hide["on"]) and not app.player.hiding, "E again steps out")
	# The figure appears when the patroller is in the player's scene.
	watcher.pat["room"] = "teach1"
	watcher.pat["x"] = CampusGeometry.tile_center(t1, 30, 17).x
	watcher.pat["y"] = CampusGeometry.tile_center(t1, 30, 17).y
	watcher.pat["safety"] = 3.6
	await _frames(4)
	var world := app.router.get_child(0) as CampusWorld
	check(watcher.figure_visible() and world.patrol_figure_shown(), "the patroller figure is drawn in the scene it walks in")
	watcher.pat["room"] = "admin1"
	await _frames(3)
	check(not world.patrol_figure_shown(), "and disappears when it is elsewhere")
	app.return_to_menu()


## Walk the whole whitelist route through the real interactions, ending on the card.
func _test_whitelist_route(app: GameApp) -> void:
	app.saves.clear()
	app.start_new_game()
	await _frames(3)
	app._stand_up()
	app.items().add("usb")
	app.items().add("pen")
	check(await _press_terminal(app, "lab3"), "E at the lab3 terminal reaches the route rules")
	check(app.routes().hacked, "the USB drive hacks the whitelist through the real interaction")
	check(await _press_terminal(app, "admin3"), "E at the admin3 data machine reaches the route rules")
	check(app.routes().data_synced, "and syncs it")
	var gate := CampusGeometry.to_scene(null, Vector2(401, 1250))
	app.travel("out", {"position": [gate.x, 0.05, gate.y], "yaw": 0.0, "pitch": 0.0}, false)
	await _frames(3)
	check(app.campus().hint("out", app.player.capture_pose()) == "西小门", "the west gate hint appears")
	app._campus_interact()
	await _frames(2)
	check(app.ui.choice_open(), "the quiz opens as a choice")
	for _n in 3:
		var q: Dictionary = RoutesModule.QUESTIONS[app.routes().face_quiz["order"][int(app.routes().face_quiz["done"])]]
		app._choice_made(int(q["answer"]))
		await _frames(2)
	check(app.ui.choice_open(), "the green gate choice is open")
	app._choice_made(0)
	await _frames(2)
	check(app.story().ended == "face" and app.ui.ending_panel != null and app.ui.ending_panel.visible, "the ending card is shown")
	check(not app.saves.exists() and not app.player.enabled, "the run is over and the save is cleared")
	check(FileAccess.file_exists(app.saves.side_path("ends.json")), "the ending is recorded")
	app.pause_game()
	check(not paused, "no pause menu after an ending")
	app.return_to_menu()
	check(not app.ui.ending_panel.visible and app.session == null, "back to the menu hides the card")


## Stand next to a 'D' cell of `scene` and press E until the rules answer with a terminal.
func _press_terminal(app: GameApp, scene: String) -> bool:
	var room := CampusData.layout(scene)
	var grid: Array = room["grid"]
	for r in grid.size():
		for c in String(grid[r]).length():
			if String(grid[r]).substr(c, 1) != "D":
				continue
			for off: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				var stand := CampusGeometry.tile_center(room, c + off.x, r + off.y)
				var ang := atan2(-off.y, -off.x)
				var pose := _campus_pose(room, stand, ang)
				if CampusData.rules().interact_at(scene, pose).get("terminal", false):
					app.travel(scene, pose, false)
					await _frames(3)
					app._campus_interact()
					await _frames(2)
					return true
	return false


## Facts flow from the run into the profile file; the menu shows the list.
func _test_achievement_flow(app: GameApp) -> void:
	app.saves.clear()
	var profile := FileAccess.file_exists(app._profile_path())
	if profile:
		DirAccess.remove_absolute(app._profile_path())
	app.start_new_game()
	await _frames(3)
	app.fact({"kind": "day", "day": 2})
	check(app.achievements().unlocked.has("n.day2") and FileAccess.file_exists(app._profile_path()), "an unlock is stored in the profile file")
	app.return_to_menu()
	app._show_achievements()
	check(app.ui.ach_panel != null and app.ui.ach_panel.visible, "the menu opens the list")
	var back := AchievementsModule.new(25)
	app._load_profile(back)
	check(back.unlocked.has("n.day2"), "the next run starts from the stored profile")
	app.start_new_game()
	await _frames(3)
	check(app.achievements().unlocked.has("n.day2") and not app.ui.ach_panel.visible, "a new run loads the profile and hides the list")
	DirAccess.remove_absolute(app._profile_path())


## The archive lists each real cause once, counts repeats, and keeps unseen ones hidden.
func _test_archive(app: GameApp) -> void:
	var rows := DeathArchive.rows({"sources": {"patrol": 3, "an:rain": 1}}, {"face": 1})
	check(rows.size() == DeathArchive.DEATHS.size() + DeathArchive.ENDS.size() and DeathArchive.known(rows) == 3, "the archive counts two deaths and one ending as recorded")
	var by_name := {}
	for r: Dictionary in rows:
		by_name[r["name"]] = r
	check(by_name["点名"]["on"] and by_name["点名"]["count"] == 3 and not by_name["那根弦"]["on"], "a repeated death only adds to its counter; unseen ones stay locked")
	check(rows.filter(func(r: Dictionary) -> bool: return not r["on"] and r["memo"] != "").size() > 0 and DeathArchive.DEATHS.all(func(d: Array) -> bool: return not String(d[0]).begins_with("void")), "locked rows carry the record text for the UI to withhold, and no maze deaths are listed")
	var ids := {}
	for k in StoryModule.SOURCES:
		ids[k] = true
	for k: String in ["laugh", "trap_out", "trap_wall", "trap_beg"]:
		ids[k] = true # kill sources without a cause text in the old table either
	for d: Array in DeathArchive.DEATHS:
		check(ids.has(d[0]) or String(d[0]).begins_with("an:") and AnomalyModule.IDS.has(String(d[0]).substr(3)), "archive entry %s is a real kill source" % d[0])
	app.saves.clear()
	app.return_to_menu()
	app._show_archive()
	check(app.ui.ach_panel != null and app.ui.ach_panel.visible, "the menu opens the archive")


func _test_death_scene(app: GameApp) -> void:
	check(GameUI.death_style("drown")[0] == 1 and GameUI.death_style("swarm")[0] == 2 and GameUI.death_style("floor")[0] == 3 and GameUI.death_style("grip")[0] == 4 and GameUI.death_style("unknown")[0] == 0, "each family of causes has its own death scene style")
	app.ui.show_death_scene("drown", 0.5)
	check(app.ui.death_scene_style() == 1 and app.ui._death_fade.visible, "the scene shows with its style")
	app.ui.show_death_scene("drown", 0.0)
	check(not app.ui._death_fade.visible, "no progress, no scene")
	app.ui.hide_death()
	check(not app.ui._death_fade.visible, "hiding the death card hides the scene")


## The car route through the app: the plate, the key, the drive and the 《闸门》 card.
func _test_car_route(app: GameApp) -> void:
	app.saves.clear()
	app.start_new_game()
	await _frames(3)
	app._stand_up()
	var cars := app.garage()
	var right := cars.car_right_cell().split(":")
	var g := CampusData.layout("garage1")
	var c := int(right[0])
	var r := int(right[1])
	var stand := CampusGeometry.tile_center(g, c, r + 1)
	app.travel("garage1", _campus_pose(g, stand, -PI * 0.5), false)
	app.patrol().pat["safety"] = 999.0
	await _frames(3)
	cars.roam["stage"] = "wait"
	cars.roam["waitT"] = 999.0
	cars.roam["x"] = -1e6
	cars.roam["on"] = true
	check(app.campus().hint("garage1", app.player.capture_pose()).begins_with(GarageModule.car_name(c, r)), "the car hint shows its plate")
	app.items().add("key")
	app._use_item("key")
	check(app.ui.toast_text().contains(cars.key_label()), "the key names the plate of the right car")
	app._campus_interact()
	await _frames(2)
	check(app.ui.choice_open(), "E at a car offers to try the key")
	app._choice_made(0)
	for _i in 30:
		await process_frame
		if app.driving():
			break
	var waited := 0
	while not app.driving() and waited < 200:
		await process_frame
		waited += 1
	check(app.driving() and app._drive_view != null and app.session.world_id == "out", "the right car starts the drive on the road out")
	check(not app._campus_world().visible, "the campus is hidden behind the road")
	var d: Dictionary = cars.chase
	d["distance"] = 319.0
	d["speed"] = 20.0
	d["x"] = -2.0
	d["nextObstacle"] = 6
	d["nextFork"] = 2
	Input.action_press("move_forward")
	await _frames(4)
	Input.action_release("move_forward")
	check(app.story().ended == "car" and app.ui.ending_panel.visible and not app.driving(), "driving out is the 《闸门》 ending")
	check(app.achievements().unlocked.has("e.end_car") and app.achievements().unlocked.has("e.firstcar"), "with its achievements")
	app.return_to_menu()
	DirAccess.remove_absolute(app._profile_path())


## Stand next to a `ch` tile of `scene` facing it so that E gives `key`; returns false when none.
func _face_tile(app: GameApp, scene: String, ch: String, key: String) -> bool:
	var room := CampusData.layout(scene)
	var grid: Array = room["grid"]
	for r in grid.size():
		for c in String(grid[r]).length():
			if String(grid[r]).substr(c, 1) != ch:
				continue
			for off: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				var stand := CampusGeometry.tile_center(room, c + off.x, r + off.y)
				if String(grid[r + off.y]).substr(c + off.x, 1) != ".":
					continue
				var pose := _campus_pose(room, stand, atan2(-off.y, -off.x))
				var res := CampusData.rules().interact_at(scene, pose)
				if res.has(key) and (key != "facility" or res[key][0] == ch):
					app.travel(scene, pose, false)
					await _frames(2)
					return true
	return false


## The portal route through the app: tunnel, diary, three blueprints, parts, the circle, 《门》.
func _test_portal_route(app: GameApp) -> void:
	app.saves.clear()
	app.start_new_game()
	await _frames(3)
	app._stand_up()
	app.patrol().pat["safety"] = 999.0
	check(await _face_tile(app, "lab1", "K", "facility"), "the physics bench can be reached")
	app._campus_interact()
	await _frames(2)
	check(app.ui.choice_open(), "E at the bench offers the tunnel")
	app._choice_made(0)
	await _frames(3)
	check(app.session.world_id == "portal_tunnel", "the tunnel is entered")
	check(await _face_tile(app, "portal_tunnel", "u", "facility"), "the diary can be reached")
	app._campus_interact()
	await _frames(2)
	check(bool(app.facilities().portal["diary"]), "the diary is read")
	var answers := {"lab2": [1], "lab4": [2], "lab5": [1, 2, 0]}
	for scene: String in answers:
		check(await _face_tile(app, scene, "K", "facility"), "the %s bench can be reached" % scene)
		for pick: int in answers[scene]:
			app._campus_interact()
			await _frames(2)
			app._choice_made(pick)
			await _frames(2)
	check(bool(app.facilities().portal["sketch"]), "the three blueprints are found through the benches")
	for k: String in FacilitiesModule.PORTAL_PARTS:
		app.items().add(k)
	check(await _face_tile(app, "lab1", "K", "facility"), "back at the bench")
	app._campus_interact()
	await _frames(2)
	app._choice_made(0)
	await _frames(2)
	check(bool(app.facilities().portal["open"]), "the circle opens")
	await _frames(2)
	check(app._campus_world().portal_shown(), "the circle of light stands in front of the bench")
	await create_timer(2.8).timeout
	await _frames(2)
	check(app.ui.choice_open(), "after a moment the circle asks")
	app._choice_made(0)
	await _frames(2)
	check(app.story().ended == "portal" and app.ui.ending_panel.visible, "walking in is the 《门》 ending")
	check(app.achievements().unlocked.has("e.end_portal"), "with its achievement")
	app.return_to_menu()
	DirAccess.remove_absolute(app._profile_path())


## 《放学》 through the app: the microphone held with E, the bell, the crowd, the north gate.
func _test_dismissal_route(app: GameApp) -> void:
	app.saves.clear()
	app.start_new_game()
	await _frames(3)
	app._stand_up()
	app.patrol().pat["safety"] = 999.0
	var day := app.school()
	day.day = 2
	day.tsec = 1100.0
	for k: String in ["notice1", "notice2", "notice3", "notice4"]:
		app.items().add(k)
	var radio := app.broadcast()
	radio.b["book"] = true
	radio.b["fuse"] = true
	var a2 := CampusData.layout("admin2")
	var station := _spot("admin2", BroadcastModule.STATION) + Vector2(0, 9)
	app.travel("admin2", _campus_pose(a2, station, -PI * 0.5), false)
	await _frames(2)
	app._campus_interact()
	await _frames(2)
	check(app.ui.choice_open(), "E at the station opens its menu")
	app._choice_made(3)
	await _frames(2)
	check(app._mic_open and not app.ui.choice_open() and app._mic_panel.visible and not app.get_tree().paused, "the microphone panel opens without pausing the world")
	check(app._mic_panel.chooser.item_count == 4 and app._mic_panel.hold_button.text == "按住朗读 · 空格", "it lists the four papers in hand and offers the hold-to-read button")
	Input.action_press("interact")
	for n in 4:
		for _i in 32:
			app._broadcast_step(0.5)
		if n < 3:
			check(int(radio.b["completed"]) == n + 1, "page %d is read while E is held" % (n + 1))
			radio.select("notice%d" % (n + 2))
	Input.action_release("interact")
	check(radio.b["phase"] == "bell" and not app._mic_open, "the fourth page rings the bell")
	app.travel("out", {"position": [0, 0.05, 0], "yaw": 0.0, "pitch": 0.0}, false)
	await _frames(2)
	var won := false
	for _i in 60:
		var p := radio.crowd()
		if not p.is_empty():
			var s := CampusGeometry.to_scene(null, Vector2(float(p["x"]), float(p["y"])))
			app.player.place({"position": [s.x, 0.05, s.y], "yaw": 0.0, "pitch": 0.0})
		app._broadcast_step(1.0)
		await process_frame
		if app.story().ended != "":
			won = true
			break
	check(won and app.story().ended == "dismissal" and app.ui.ending_panel.visible, "following the crowd out of the north gate is 《放学》")
	check(app.achievements().unlocked.has("e.end_dismissal"), "with its achievement")
	app.return_to_menu()
	DirAccess.remove_absolute(app._profile_path())


## 《网安仙人》 through the app: the lab3 computer, the terminal typed into, ten minutes, the card.
func _test_cyber_route(app: GameApp) -> void:
	app.saves.clear()
	app.start_new_game()
	await _frames(3)
	app._stand_up()
	app.patrol().pat["safety"] = 999.0
	app.items().add("phone")
	var net := app.phone()
	net.set_context(app._phone_context())
	net.acquire()
	net.device["network"] = true
	net.device["wireless"] = {"status": "complete", "elapsed": 200.0, "target": 200.0}
	net.device["download"] = {"status": "complete", "elapsed": 60.0, "target": 60.0}
	check(await _face_tile(app, "lab3", "n", "facility"), "a lab3 computer can be reached")
	app._campus_interact()
	await _frames(2)
	check(app.ui.choice_open(), "E at the computer opens its menu")
	app._choice_made(2)
	await _frames(2)
	check(app.ui.terminal_open() and not app.player.enabled, "the terminal opens and takes the keyboard")
	for line: String in _solve_lines(net.puzzle):
		app.ui.terminal_command.emit(line)
		await _frames(1)
	check(net.termination["status"] == "accepted", "typing the solution submits the shutdown")
	app.ui.terminal_closed.emit()
	await _frames(1)
	check(not app.ui.terminal_open() and app.player.enabled, "closing the terminal gives the player back")
	app._phone_step(599.0)
	check(app.story().ended == "", "not before ten minutes")
	app._phone_step(2.0)
	await _frames(2)
	check(app.story().ended == "cyber" and app.ui.ending_panel.visible, "surviving ten minutes is 《网安仙人》")
	check(app.achievements().unlocked.has("e.end_cyber"), "with its achievement")
	app.return_to_menu()
	DirAccess.remove_absolute(app._profile_path())


## Over a bridge railing through the app: E, confirm, fall, land outside hurt.
func _test_vault_app(app: GameApp) -> void:
	app.saves.clear()
	app.start_new_game()
	await _frames(3)
	app._stand_up()
	app.patrol().pat["safety"] = 999.0
	var l1 := CampusData.layout("link1")
	app.travel("link1", _campus_pose(l1, CampusGeometry.tile_center(l1, 1, 10), PI), false)
	await _frames(2)
	app._campus_interact()
	await _frames(2)
	check(app.ui.choice_open(), "E at the railing asks")
	app._choice_made(0)
	for _i in 90:
		await process_frame
		if app.session.world_id == "out":
			break
	await _frames(3)
	check(app.session.world_id == "out" and app.body().injury == 45.0 and app.player.enabled, "the fall ends on the ground outside, hurt")
	check(app.player.speed_multiplier < 1.0 and app.achievements().unlocked.has("n.vault"), "walking slower, with 换一条路")
	app.return_to_menu()
	DirAccess.remove_absolute(app._profile_path())


## A desk question and studying until the bell, through the app.
func _test_lesson_app(app: GameApp) -> void:
	app.saves.clear()
	app.start_new_game()
	await _frames(3)
	app.patrol().pat["safety"] = 999.0
	check(app.school().seated, "the run starts seated in class")
	var before := app.school().san
	app._lesson_press()
	await _frames(1)
	check(app.investigation().visible("desk") and not app.ui.choice_open(), "the first R at the own seat reads the parking ticket (the investigation starts there)")
	app._lesson_press()
	await _frames(1)
	check(app.ui.choice_open() and app._choice_left > 11.0, "R opens the desk question with its timer")
	var task: Dictionary = DayModule.TASKS[int(app.days().lessons.values()[0]["task"])]
	app._choice_made(int(task["answer"]))
	await _frames(1)
	check(app.school().san >= minf(100.0, before + 1.9) and app.achievements().unlocked.has("n.desk"), "the right answer helps")
	app._lesson_press()
	await _frames(1)
	app._choice_made(0)
	var t0 := app.school().tsec
	for _i in 30:
		await physics_frame
	var fast := app.school().tsec - t0
	app._lesson_press()
	var t1 := app.school().tsec
	for _i in 30:
		await physics_frame
	var slow := app.school().tsec - t1
	check(app.days().waiting == null and fast > slow * 3.0, "studying runs the class faster (R stops it)")
	app.return_to_menu()
	DirAccess.remove_absolute(app._profile_path())


## A speedrun from the menu: it keeps away from the normal save and records its time.
func _test_speedrun_app(app: GameApp) -> void:
	app.saves.clear()
	if FileAccess.file_exists(app._speedrun_path()):
		DirAccess.remove_absolute(app._speedrun_path())
	app.start_new_game()
	await _frames(2)
	app.save_game()
	check(app.saves.exists(), "a normal save exists")
	app.return_to_menu()
	app._speedrun_menu()
	app._choice_made(0)
	app._choice_made(4)
	await _frames(2)
	check(app.speedrun.active() and app.ui.opening_on(), "speedrun: talent, prologue")
	app.ui._end_opening(true)
	await _frames(2)
	check(app.speedrun.run["status"] == "running" and app.ui.speedrun_text != "", "the clock starts at the first move and shows")
	app.save_game()
	app._reach_ending("face")
	await _frames(1)
	check(app.saves.exists() and FileAccess.file_exists(app._speedrun_path()), "the ending records the time and leaves the normal save alone")
	check(app._read_speedrun()["best"].has(Speedrun.key("easy", "face")), "a personal best for 《白名单》 on 预知梦")
	app.return_to_menu()
	app._speedrun_menu()
	app._choice_made(2)
	await _frames(1)
	check(app.ui.ach_panel.visible, "the records list opens")
	DirAccess.remove_absolute(app._speedrun_path())
	DirAccess.remove_absolute(app._profile_path())
	app.saves.clear()


## Chalk through the app, and last run's × in the next run.
func _test_marks_app(app: GameApp) -> void:
	app.saves.clear()
	if FileAccess.file_exists(app.saves.side_path("last_life.json")):
		DirAccess.remove_absolute(app.saves.side_path("last_life.json"))
	app.start_new_game()
	await _frames(2)
	app._stand_up()
	app.patrol().pat["safety"] = 999.0
	app.items().add("chalk")
	var t1 := CampusData.layout("teach1")
	app.travel("teach1", _campus_pose(t1, _wall_spot(t1), PI), false)
	await _frames(2)
	app._use_item("chalk")
	await _frames(1)
	check(app.ui.choice_open(), "using the chalk asks what to draw")
	app._choice_made(0)
	await _frames(2)
	check(app.marks().marks.size() == 1 and app._marks_nodes != null and app._marks_nodes.get_child_count() == 1, "the mark is drawn on the wall")
	app.story().diff = "hard"
	app.kill("test", "vignette", "patrol")
	await _frames(1)
	var ll: Variant = app._read_side("last_life.json")
	check(ll is Dictionary and ll["scene"] == "teach1", "the death place is kept for the next run")
	app.return_to_menu()
	app.start_new_game()
	await _frames(2)
	app._stand_up()
	app.travel("teach1", _campus_pose(t1, CampusGeometry.tile_center(t1, 30, 17), PI), false)
	await _frames(3)
	check(app.marks().last_life is Dictionary and app._marks_nodes.get_child_count() == 1, "the next run shows the last life's × there")
	app.return_to_menu()
	DirAccess.remove_absolute(app.saves.side_path("last_life.json"))
	DirAccess.remove_absolute(app._profile_path())


func _test_checkup_app(app: GameApp) -> void:
	app.saves.clear()
	app.start_new_game()
	await _frames(2)
	app._stand_up()
	app.patrol().pat["safety"] = 999.0
	app.school().day = 3
	app.days().day_events["3"] = "checkup"
	app.school().tsec = 625.0
	var a1 := CampusData.layout("admin1")
	var at := Vector2(float(a1["ox"]) + 1.6 * float(a1["tw"]), float(a1["oy"]) + 15.45 * float(a1["th"]))
	app.travel("admin1", _campus_pose(a1, at, PI), false)
	await _frames(3)
	var w := app._campus_world()
	check(w != null and w.checkup_shown() and w.checkup_queue_blocks(), "on the checkup day admin1 has the rule, scale, chart and a queue that blocks the corridor")
	app._campus_interact()
	await _frames(1)
	check(app.tales().checkup_done(), "pressing E at the rule in the window is the checkup")
	app.school().tsec = 700.0
	await _frames(2)
	check(not w.checkup_queue_blocks(), "after 11:05 the queue is gone")


func _test_sensory_app(app: GameApp) -> void:
	app.saves.clear()
	app.start_new_game()
	await _frames(3)
	check(not app.ui.sensory_on(), "a calm start draws no low-SAN picture")
	app.school().san = 10.0
	await _frames(40)
	check(app.ui.sensory_on() and float(app._sense_view["tunnel"]) > 0.5 and float(app._sense_view["bpm"]) > 100.0, "low SAN narrows the picture and quickens the heart, with no number on the HUD")
	check(float(app._sense_view["halo"]) > 0.5 and float(app._sense_view["warp"]) > 0.0, "low SAN also blooms the lamps and warps the picture")
	app.audio.pulse_t = 0.0
	app.audio.inhale_t = 0.3
	await _frames(1)
	var fresh := float(app._sense_view["pulse_env"])
	var pressed := float(app._sense_view["inhale"])
	app.audio.pulse_t = 1.0
	app.audio.inhale_t = 2.0
	await _frames(1)
	check(fresh > 0.5 * float(app._sense_view["pulse"]) and float(app._sense_view["pulse_env"]) < 0.05 * float(app._sense_view["pulse"]), "the view tightens on the heartbeat and relaxes within a second")
	check(pressed > 0.3 and float(app._sense_view["inhale"]) == 0.0, "the picture presses in as the breath is taken and is back after 1.6 s")
	var ghosted := 0.0
	for _i in 600:
		app._sense_view = {}
		await _frames(1)
		ghosted = maxf(ghosted, float(app._sense_view.get("ghost_env", 0.0)))
		if ghosted > 0.0:
			break
	check(ghosted > 0.0 and ghosted <= float(app._sense_view["ghost"]) + 0.0001, "at very low SAN faint ghost copies drift now and then")
	app.return_to_menu()
	await _frames(2)
	check(not app.ui.sensory_on(), "back at the menu the picture is clear")


func _test_settings_app(app: GameApp) -> void:
	app.saves.clear()
	app.start_new_game()
	await _frames(3)
	app.ui.settings_requested.emit()
	await _frames(2)
	check(app.ui.settings_panel != null and app.ui.settings_panel.visible, "the settings panel opens")
	app.ui.setting_changed.emit("vol", 40)
	app.ui.setting_changed.emit("amb", 0)
	app.ui.setting_changed.emit("captions", 2)
	app.ui.setting_changed.emit("mouse", 200)
	app.ui.setting_changed.emit("reduce_flash", 1)
	app.ui.setting_changed.emit("bright", 120)
	app.ui.setting_changed.emit("quality", 0)
	await _frames(3)
	check(absf(app.audio.volume - 0.4) < 0.0001 and not app.audio.ambience and app.audio.captions.mode == 2, "volume, ambience and the caption mode take effect")
	check(absf(app.player.mouse_sensitivity - 0.005) < 0.000001, "look sensitivity follows the setting")
	var cw := app._campus_world()
	check(cw.lighting.reduce_flash and absf(cw.lighting.brightness - 1.2) < 0.0001, "reduce flash and brightness reach the lighting")
	check(absf(app.get_viewport().scaling_3d_scale - 0.55) < 0.0001, "the 流畅 tier renders at 55 %% of the resolution")
	app.ui.setting_changed.emit("distortion", 0)
	app.school().san = 10.0
	await _frames(30)
	check(float(app._sense_view["warp"]) == 0.0 and float(app._sense_view["tunnel"]) > 0.5, "distortion off keeps the static narrowing but stops the warping")
	var saved := GameSettings.new(app.settings.path)
	saved.load_file()
	check(saved.get_int("vol") == 40 and saved.get_int("quality") == 0, "changes are saved immediately")
	app.ui.setting_changed.emit("reset_comfort", 0)
	check(app.settings.get_int("mouse") == 100 and app.settings.get_int("vol") == 40, "restoring comfort defaults keeps the sound")
	app.school().san = 100.0
	app.ui.setting_changed.emit("quality", 2)
	app.ui.setting_changed.emit("reduce_flash", 0)
	app.ui.setting_changed.emit("distortion", 2)
	app.ui.setting_changed.emit("vol", 70)
	app.ui.setting_changed.emit("amb", 1)
	app.ui.setting_changed.emit("captions", 1)
	app.ui.setting_changed.emit("bright", 100)
	app.ui.settings_panel.visible = false
	app.items().add("coil")
	app.facilities().flags["coil"] = true
	app._drop_item("coil")
	check(not app.items().has("coil") and app.facilities().flags["coil"] == false, "a dropped portal material can be taken again from where it was found")
	app.return_to_menu()
	await _frames(2)


func _test_death_flow(app: GameApp) -> void:
	app.saves.clear()
	app.start_new_game()
	await _frames(3)
	app.items().add("pen")
	app.campus().interact_at("teach1", _campus_pose(CampusData.layout("teach1"), CampusGeometry.tile_center(CampusData.layout("teach1"), 10, 17), -PI * 0.5))
	app.school().tsec = 900.0
	app.school().san = 0.0
	await _frames(3)
	check(app.story().dead and app._death_phase == "fade" and not app.player.enabled, "SAN 0 kills: the run is dead and input stops")
	app.pause_game()
	check(not paused, "a dead player cannot open the pause menu")
	app.save_game()
	check(not app.saves.exists(), "a dead run cannot be saved")
	await _frames(150)
	check(not app.story().dead and app.story().wakes == 1 and app.router.current.world_id == &"teach1", "day one on 预知梦 wakes at the own seat")
	check(absf(app.school().tsec - 700.0) < 1.5 and absf(app.school().san - 78.0) < 1.0 and app.school().seated and app.player.enabled,
		"the dream wake is 11:40, SAN 78, seated, with control back (t %.2f san %.2f)" % [app.school().tsec, app.school().san])
	check(app.items().has("pen"), "the bag survives the dream wake")
	check(FileAccess.file_exists(app._death_log_path()), "the death is counted in the cross-run log")
	app.school().day = 2
	app.school().san = 0.0
	await _frames(3)
	check(app.story().dead and not app.story().wake_pending, "a day-two death is final")
	app.save_game()
	check(not app.saves.exists(), "the final death keeps the run from being saved")
	await _frames(150)
	check(app._death_phase == "card" and app.ui.death_panel.visible, "the record card shows after the scene")
	Input.action_press("interact")
	await _frames(3)
	Input.action_release("interact")
	check(app._death_phase == "card" and app.story().dead, "E on the card does nothing more")
	app.return_to_menu()
	check(not app.ui.death_panel.visible and app.session == null, "back to the menu clears the card")
	app.start_new_game("hard")
	await _frames(3)
	check(app.story().diff == "hard", "梦魇 starts on the hard difficulty")
	app.school().san = 0.0
	await _frames(3)
	check(app.story().dead and not app.story().wake_pending, "梦魇 deaths are final even on day one")
	app.return_to_menu()


func _test_elevator_walk(app: GameApp) -> void:
	var lift := app.elevator()
	var t1 := CampusData.layout("teach1")
	var hall := lift.world("teach1", 1.5, 0.0)
	app.travel("teach1", _campus_pose(t1, hall, PI * 0.5), false)
	await _frames(3)
	var world := app.router.get_child(0) as CampusWorld
	check(world.lift_leaf_count() == 4, "teach1 has two landing and two car leaves")
	# Closed doors block the doorway.
	await _walk(app, [CampusGeometry.to_scene(t1, lift.world("teach1", -1.2, 0.0))], 60)
	var l: Vector2 = lift.local("teach1", CampusGeometry.to_world(t1, app.player.position.x, app.player.position.z))
	check(l.x > 0.4, "closed elevator doors stop the body in the corridor (a=%.2f)" % l.x)
	app._campus_interact()
	await _frames(70)
	await _walk(app, [CampusGeometry.to_scene(t1, lift.world("teach1", -1.2, 0.0))], 90)
	l = lift.local("teach1", CampusGeometry.to_world(t1, app.player.position.x, app.player.position.z))
	check(l.x < -0.6 and lift.ride.get("phase") == "cabin", "with the doors open the body walks into the cabin and boards")


## Bell tower: walk the spiral two turns up to the 6.4 m top ring (spiral.js), and the ground
## under the stair stays solid outside the entry angles.
func _test_spiral_walk(app: GameApp) -> void:
	var sp: Dictionary = CampusData.campus()["spiral"]
	var c := Vector2(sp["cx"], sp["cz"])
	var th0 := float(sp["th0"])
	var rm := (float(sp["rIn"]) + float(sp["rOut"])) * 0.5
	app.travel("bell1", {"position": [c.x + cos(th0) * 3.4, 0.05, c.y + sin(th0) * 3.4], "yaw": 0.0, "pitch": 0.0}, false)
	await _frames(3)
	var points: Array = []
	for i in 2 * 24 + 4:
		var a := th0 - 0.1 + i * TAU / 24.0
		points.append(c + Vector2(cos(a), sin(a)) * rm)
	await _walk(app, points, 120)
	check(app.player.position.y > float(sp["topH"]) - 0.2, "walking the spiral two turns reaches the top ring (y=%.2f)" % app.player.position.y)
	app.travel("bell1", {"position": [c.x + cos(th0 + 2.0) * 3.4, 0.05, c.y + sin(th0 + 2.0) * 3.4], "yaw": 0.0, "pitch": 0.0}, false)
	await _frames(3)
	await _walk(app, [c + Vector2(cos(th0 + 2.0), sin(th0 + 2.0)) * rm], 90)
	var q := Vector2(app.player.position.x, app.player.position.z) - c
	check(q.length() > float(sp["rOut"]) + 0.2 and app.player.position.y < 0.2, "ground under the stair is solid away from the entry")


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
	app.ui.look_pad._input(look_press)
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
