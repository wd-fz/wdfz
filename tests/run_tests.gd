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
	check(asked[0]["kind"] == "choice" and String(asked[0]["text"]).begins_with(GarageModule.car_name(int(wc[0]), int(wc[1]))), "looking at a car offers to try the key")
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
	await _test_anomaly_fx(app)
	await _test_audio(app)
	await _test_whitelist_route(app)
	await _test_achievement_flow(app)
	await _test_archive(app)
	await _test_death_scene(app)
	await _test_car_route(app)
	await _test_portal_route(app)
	await _test_death_flow(app)
	app.return_to_menu()


## Synthesised sound: every cue exists, layers follow the context, mute works, rules are untouched.
func _test_audio(app: GameApp) -> void:
	var fx := app.audio
	for id in ["step", "step_heavy", "heart", "thud", "bell", "ding", "drip", "creak", "static", "sting", "scare", "chime", "hum", "wind", "rain"]:
		var stream := fx.stream_of(id)
		check(stream != null and stream.data.size() > 400, "the %s cue is synthesised" % id)
	check(fx.stream_of("hum").loop_mode == AudioStreamWAV.LOOP_FORWARD and fx.stream_of("step").loop_mode == AudioStreamWAV.LOOP_DISABLED, "ambient cues loop, one-shots do not")
	check(fx.stream_of("nothing") == null, "an unknown cue is empty, not an error")
	app.saves.clear()
	app.start_new_game()
	await _frames(3)
	app._stand_up()
	var t1 := CampusData.layout("teach1")
	app.travel("teach1", _campus_pose(t1, CampusGeometry.tile_center(t1, 30, 17), PI), false)
	app.patrol().pat["safety"] = 999.0
	fx.played.clear()
	fx.update(0.1, {"moving": true, "running": false, "indoors": true, "san": 100.0})
	check(fx.played.has("step"), "walking plays a footstep")
	fx.played.clear()
	fx.update(0.1, {"moving": false, "indoors": true, "san": 10.0})
	check(fx.played.has("heart"), "low SAN plays the heartbeat")
	fx.played.clear()
	fx.update(0.1, {"moving": false, "indoors": true, "san": 100.0, "patrol_pos": Vector3(3, 0, 3)})
	check(fx.played.has("step_heavy"), "the patroller's footsteps play in space")
	await _frames(2)
	check(fx.looping("hum") and not fx.looping("wind"), "indoors the room tone plays, not the wind")
	fx.update(0.1, {"indoors": false, "san": 100.0, "rain": true})
	check(fx.looping("wind") and fx.looping("rain") and not fx.looping("hum"), "outdoors the wind and the rain play")
	fx.update(0.1, {"indoors": true, "san": 100.0, "blackout": true})
	check(not fx.looping("hum"), "a blackout kills the hum")
	app.audio.muted = true
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "mute silences the master bus")
	app.audio.muted = false
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "unmute restores it")
	fx.stop_all()
	check(not fx.looping("wind"), "stop_all stops the loops")


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
	weird.an["id"] = "turn"
	weird.an["active"] = true
	weird.an["data"] = {"scene": "teach1", "chosen": null, "smile": false}
	await _frames(2)
	check(fx.shown_count() == 0, "an anomaly without a place in the world draws nothing")
	weird.an["data"]["scene"] = "out"
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
	check(rows[0]["on"] and rows[0]["count"] == 3 and not rows[1]["on"], "a repeated death only adds to its counter; unseen ones stay locked")
	check(rows.filter(func(r: Dictionary) -> bool: return not r["on"] and r["memo"] != "").size() > 0 and DeathArchive.DEATHS.all(func(d: Array) -> bool: return not String(d[0]).begins_with("void")), "locked rows carry the record text for the UI to withhold, and no maze deaths are listed")
	var ids := {}
	for k in StoryModule.SOURCES:
		ids[k] = true
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
