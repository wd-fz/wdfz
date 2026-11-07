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
	check(app.session != null and app.player.enabled, "real touch tap on menu starts new game")
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
		check(app.session != null, "touch button hit-testing after resize %s" % viewport_size)
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
	check(after_wrong[1]["kind"] == "choice" and String(after_wrong[1]["text"]).contains(RoutesModule.EXPLANATIONS[order[0]]), "and shows the explanation")
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
	await _test_whitelist_route(app)
	await _test_death_flow(app)
	app.return_to_menu()


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
