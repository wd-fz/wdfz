extends "res://tests/support/test_suite.gd"


func _point(c: int, r: int = 17) -> Dictionary:
	var p := CampusGeometry.tile_center(CampusData.layout("teach1"), c, r)
	return PatrolNav.point("teach1", p.x, p.y)


func _watcher(point: Dictionary, violation: float = 0.0) -> PatrolModule:
	var pm := CampusData.make_patrol()
	pm.reset()
	pm.elevator = ElevatorModule.new(CampusData.rooms())
	pm._put(point)
	pm.pat["safety"] = 0.0
	pm.pat["afterBlink"] = 0.0
	pm.pat["near"] = true
	pm.set_context(_pctx("teach1", Vector2(point["x"] + 80.0, point["y"]), {"viol": violation}))
	return pm


func test_scaling() -> void:
	var pm := _watcher(_point(28))
	for spec: Array in [[-1, 0, 135, 1.0], [0, 0, 135, 1.0], [24.999, 0, 135, 1.0], [25, 1, 153, 1.03],
			[49.999, 1, 153, 1.03], [50, 2, 171, 1.05], [74.999, 2, 171, 1.05], [75, 3, 189, 1.08], [100, 3, 189, 1.08], [1000, 3, 189, 1.08]]:
		pm.set_context(_pctx("teach1", Vector2.ZERO, {"viol": spec[0]}))
		check(pm.alert_level() == spec[1] and pm.sight_range() == spec[2] and is_equal_approx(pm.chase_speed(), 31.0 * spec[3]),
			"violation %s chooses the bounded sight and speed tier" % str(spec[0]))
	check(pm.chase_speed() < 36.4, "even the fastest pursuit is slower than an uninjured normal sprint")
	for invalid: float in [INF, NAN]:
		pm.set_context(_pctx("teach1", Vector2.ZERO, {"viol": invalid}))
		check(pm.alert_level() == 0, "non-finite debug input does not poison patrol arithmetic")
	for level in 4:
		var p := _point(28)
		var at_range := Vector2(p["x"] + [135.0, 153.0, 171.0, 189.0][level], p["y"])
		pm.set_context(_pctx("teach1", at_range, {"viol": level * 25}))
		check(pm.sees(), "tier %d can see through a clear corridor at its range boundary" % level)
		pm.set_context(_pctx("teach1", at_range + Vector2(0.1, 0), {"viol": level * 25}))
		check(not pm.sees(), "tier %d cannot see beyond its range boundary" % level)
		var acquirer := _watcher(p, level * 25)
		acquirer.tick(0.1)
		check(is_equal_approx(acquirer.pat["lock"], 0.11 / [1.0, 0.9, 0.8, 0.75][level]), "tier %d shortens actual acquisition time" % level)
		var chaser := _watcher(pm.nav.snap("teach1", _point(28)), level * 25)
		chaser.pat["locked"] = true
		chaser.pat["lastSeen"] = PatrolNav.point("teach1", chaser.pat["x"] + 80.0, chaser.pat["y"])
		var before := chaser.position()
		chaser.tick(0.1)
		check(absf(chaser._dist3(before, chaser.position()) - 3.1 * [1.0, 1.03, 1.05, 1.08][level]) < 0.01, "tier %d changes real pursuit movement" % level)
	var wall_pm := _watcher(_point(13), 100)
	var behind := _point(13, 14)
	wall_pm.set_context(_pctx("teach1", Vector2(behind["x"], behind["y"]), {"viol": 100}))
	check(not wall_pm.sees(), "maximum violation still cannot see through the classroom wall")
	var warned := _watcher(_point(28), 100)
	warned.pat["near"] = false
	warned.tick(0.1)
	check(warned.pat["warning"] > 3.4 and warned.pat["lock"] == 0.0 and not warned.pat["locked"], "high violation preserves the initial warning")
	pm.set_context(_pctx("teach1", Vector2.ZERO, {"viol": 0}))
	check(pm.sight_range() == 135.0 and pm.chase_speed() == 31.0, "current violation falling restores baseline sight and speed")


func test_pursuit_lifecycle() -> void:
	var pm := _watcher(_point(28), 75)
	pm.pat["locked"] = true
	pm.pat["cited"] = true
	pm.tick(0.1)
	var last_seen: Dictionary = pm.pat["lastSeen"].duplicate()
	var hidden := _point(40, 10)
	var ctx := _pctx("teach1", Vector2(hidden["x"], hidden["y"]), {"viol": 75})
	pm.set_context(ctx)
	check(not pm.sees(), "the player broke sight by moving behind a classroom wall")
	_patrol_run(pm, ctx, 2.3)
	check(pm.pat["locked"] and pm.pat["search"] == 0.0 and same_json(pm.pat["lastSeen"], last_seen), "briefly lost sight retains only the actual last observation")
	_patrol_run(pm, ctx, 0.4)
	check(not pm.pat["locked"] and pm.pat["search"] > 14.0 and not pm.pat["searchPlan"].is_empty(), "sustained loss of sight starts the higher-tier active search")
	var hidden_look := pm.look_point()
	pm.set_context(_pctx("teach1", Vector2(hidden["x"] - 10, hidden["y"]), {"viol": 75}))
	check(same_json(pm.look_point(), hidden_look), "even the rendered facing ignores changes to an unseen player")
	var visible := Vector2(pm.pat["x"] + 60, pm.pat["y"])
	var events := _patrol_run(pm, _pctx("teach1", visible, {"viol": 75}), 0.8)
	check(pm.pat["locked"] and pm.pat["search"] == 0.0 and pm.pat["searchPlan"].is_empty(), "seeing the player again cancels the old search and resumes pursuit")
	check(not events.any(func(e: Dictionary) -> bool: return e["kind"] == "violation"), "reacquisition within the same encounter does not issue repeated citations")
	pm.rescued()
	pm.tick(0.1)
	check(not pm.pat["locked"] and pm.pat["safety"] > 3.4, "survival protection still wins over maximum alert")
	# A genuinely new flash is evidence; it does not grant a wall-penetrating camera detector.
	var flash := _watcher(_point(28), 75)
	check(flash.camera_flash(1.6, 0.85) and flash.pat["search"] == 15.0 and flash.pat["lock"] == 0.85, "a visible camera flash starts a search while preserving partial acquisition")
	flash.set_context(ctx)
	check(not flash.camera_flash(1.6, 0.85), "camera flashes behind walls stay undetected")


func test_search() -> void:
	var origin := _point(36)
	for level in 4:
		var pm := _watcher(origin, level * 25)
		pm.pat["lastSeen"] = origin.duplicate()
		pm.pat["heading"] = [1.0, 0.0]
		pm.pat["stuck"] = 2
		pm._begin_search()
		check(pm.pat["stuck"] == 0, "a new observation clears the previous route failure")
		check(pm.pat["search"] == [3.0, 6.0, 10.0, 15.0][level], "tier %d chooses the search budget" % level)
		var points: Array = pm.pat["searchPlan"]["points"]
		check(points.size() <= level + 1 and (points.size() > 1 if level > 0 else points.size() == 1), "tier %d has bounded reachable search stops" % level)
		if level > 0:
			check(float(points[1]["x"]) > float(origin["x"]), "search first checks the witnessed direction of travel")
		var prev := origin
		for point: Dictionary in points:
			check(point["scene"] == "teach1" and is_finite(pm.nav.length(pm.nav.path(prev, point))), "each search leg is a real same-scene route")
			prev = point
	# Hidden players in different positions must yield identical search decisions and movement.
	var a := _watcher(origin, 75)
	a.pat["lastSeen"] = origin.duplicate()
	a.pat["heading"] = [1.0, 0.0]
	a._begin_search()
	a.hide["on"] = true
	var b := _watcher(origin, 75)
	b.restore(JSON.parse_string(JSON.stringify(a.capture())))
	var a_ctx := _pctx("teach1", Vector2(origin["x"] - 60, origin["y"] - 40), {"viol": 0})
	var b_ctx := _pctx("teach1", Vector2(origin["x"] + 80, origin["y"] - 40), {"viol": 0})
	var same_decisions := true
	var collision_safe := true
	var travelled := 0.0
	for _i in 120:
		var previous := a.position()
		a.set_context(a_ctx)
		b.set_context(b_ctx)
		a.tick(0.1)
		b.tick(0.1)
		same_decisions = same_decisions and same_json(a.position(), b.position()) and same_json(a.pat["searchPlan"], b.pat["searchPlan"])
		var distance := a._dist3(previous, a.position())
		travelled += distance
		collision_safe = collision_safe and distance <= 1.601 and (distance < 0.001 or a.nav.segment(previous, a.position()))
	check(same_decisions, "different unseen locations cannot redirect the search or leak live player coordinates")
	check(collision_safe and travelled > 24.0, "search walks around the corridor without teleporting or crossing walls")
	check(a.pat["search"] > 2.9 and a.pat["searchPlan"]["tier"] == 3 and a.alert_level() == 0, "an active search keeps its original budget while current threat stats decline")
	_patrol_run(a, a_ctx, 3.2)
	check(a.pat["search"] == 0.0 and a.pat["lastSeen"] == null and a.pat["searchPlan"].is_empty(), "an exhausted search forgets the sighting and returns to patrol")
	# Being unable to reach the observation must not trap the resident forever.
	var blocked := _watcher(origin, 75)
	blocked.hide["on"] = true
	blocked.pat["lastSeen"] = PatrolNav.point("teach1", -100000, -100000)
	blocked._begin_search()
	blocked.tick(0.1)
	check(blocked.pat["search"] == 0.0 and blocked.pat["lastSeen"] == null, "an unreachable origin is abandoned")
	# Crossing a floor needs its proper navigation, never planar guesses at an arbitrary height.
	for special: Dictionary in [a.nav.nodes["stair_teach_w:0"], a.nav.maze.point(0, 0)]:
		var plan := PatrolSearch.make(a.nav, special, [1.0, 0.0], {}, 3, 15.0)
		check(plan["points"].size() == 1 and plan["points"][0].get("fy", 0.0) == special.get("fy", 0.0), "special spaces retain height-aware last-sighting search")
	var deadline := _watcher(origin, 75)
	deadline.pat["lastSeen"] = _point(45)
	deadline.hide["on"] = true
	deadline._begin_search()
	deadline.pat["searchPlan"]["ttl"] = 0.05
	deadline.tick(0.1)
	check(deadline.pat["searchPlan"].is_empty() and deadline.pat["lastSeen"] == null, "the travel deadline also bounds searches that never reach their origin")
	var looking := _watcher(origin, 75)
	looking.pat["lastSeen"] = origin.duplicate()
	looking._begin_search()
	looking.hide["on"] = true
	looking.tick(0.2)
	var glance := looking.look_point()
	looking.tick(0.3)
	check(not same_json(glance, looking.look_point()), "at a search stop the figure actually turns to look around")


func test_elevator() -> void:
	var arrival_times: Array = []
	for violation: float in [0.0, 75.0]:
		var pm := _watcher(_point(30, 19), violation)
		pm.elevator.reset()
		pm.elevator.lifts["teach"]["door"] = 1.0
		var cabin := pm.elevator.world("teach1", -1.0, 0.0)
		pm.set_context(_pctx("teach1", cabin, {"viol": violation}))
		pm.pat["locked"] = true
		pm.pat["lastSeen"] = pm._lift_front("teach1")
		pm._lift_door()
		check(pm.pat["doorRush"] != null, "the patroller sees boarding through an open elevator door")
		if pm.pat["doorRush"] == null:
			continue
		arrival_times.append(float(pm.pat["doorRush"]["eta"]))
		pm.elevator.lifts["teach"]["door"] = 0.0
		check(pm.elevator_closed("teach", 1) and not pm.pat["locked"] and pm.pat["search"] == (15.0 if violation > 0 else 3.0), "closing the elevator wins over pursuit and starts a tiered search at its landing")
		var events := _patrol_run(pm, _pctx("lift_teach", Vector2.ZERO, {"viol": violation}), 40.0)
		check(pm.pat["search"] == 0.0 and not events.any(func(e: Dictionary) -> bool: return e["kind"] == "kill"), "the search never follows an unseen elevator destination")
	check(arrival_times.size() == 2 and is_equal_approx(arrival_times[0] / arrival_times[1], 1.08), "elevator arrival estimates use the same boosted speed as physical pursuit")


func test_lockers_and_shelter() -> void:
	var origin := _point(31)
	var pm := _watcher(origin, 75)
	pm.pat["lastSeen"] = origin.duplicate()
	pm.pat["lockerMemory"]["teach1"] = {"c": 28, "r": 16, "cycle": -1}
	pm._begin_search()
	check(pm.pat["searchPlan"]["points"].any(func(p: Dictionary) -> bool: return p.get("kind") == "locker" and p["c"] == 28), "a previously witnessed locker is a search candidate")
	pm.hide = {"on": true, "seen": false, "near": false, "c": 28, "r": 16, "t": 0.0}
	var hidden := _point(28, 16)
	var ctx := _pctx("teach1", Vector2(hidden["x"], hidden["y"]), {"viol": 75})
	pm.set_context(ctx)
	pm.tick(0.1)
	check(not pm.pat["locked"] and not pm.hide["seen"], "remembering a locker does not reveal its current occupant from a distance")
	var events := _patrol_run(pm, ctx, 12.0, "kill")
	check(events.any(func(e: Dictionary) -> bool: return e["kind"] == "kill") and pm.hide["seen"], "physically checking the remembered locker can find its occupant")
	check(events.filter(func(e: Dictionary) -> bool: return e["kind"] == "violation").size() == 1, "the rediscovery issues only one citation")
	var unknown := _watcher(origin, 75)
	unknown.pat["lastSeen"] = origin.duplicate()
	unknown._begin_search()
	unknown.hide = {"on": true, "seen": false, "near": false, "c": 28, "r": 16, "t": 0.0}
	events = _patrol_run(unknown, ctx, 17.0)
	check(not events.any(func(e: Dictionary) -> bool: return e["kind"] == "kill") and not unknown.hide["seen"], "an unknown locker remains an effective hiding place at maximum alert")
	var at_locker := _watcher(_point(28), 75)
	at_locker.pat["lastSeen"] = _point(28)
	at_locker.pat["lockerMemory"]["teach1"] = {"c": 28, "r": 16, "cycle": -1}
	at_locker._begin_search()
	check(at_locker.pat["searchPlan"]["points"].any(func(p: Dictionary) -> bool: return p.get("kind") == "locker"), "a remembered locker at the sighting itself is still checked")
	var outside: Dictionary = CampusData.patrol_nav().nodes["out:dormN"]
	var dorm := _watcher(outside, 75)
	dorm.set_context(_pctx("out", Vector2(outside["x"], outside["y"]), {"viol": 75, "night": true, "need_where": "宿舍"}))
	dorm.pat["locked"] = true
	dorm.pat["lastSeen"] = outside.duplicate()
	dorm.left_scene("out", "dorm1")
	check(dorm.pat["lastSeen"]["scene"] == "out", "seeing the player enter a night dorm records the outside of the entrance")
	var sheltered := _pctx("dorm1", Vector2(0, 0), {"viol": 75, "night": true, "need_where": "宿舍"})
	dorm.set_context(sheltered)
	dorm.tick(0.1)
	check(not dorm.pat["locked"] and dorm.pat["search"] > 0.0 and dorm.pat["searchPlan"]["points"].all(func(p: Dictionary) -> bool: return p["scene"] == "out"), "ordinary night pursuit ends while a bounded search remains outside")
	events = _patrol_run(dorm, sheltered, 16.0)
	check(dorm.pat["search"] == 0.0 and not events.any(func(e: Dictionary) -> bool: return e["kind"] == "kill"), "the dorm search expires without entering to capture the sheltered player")
	dorm.registered_absence("2:0")
	check(dorm.hunting() and dorm._target()["scene"] == "dorm1", "independent permanent absence punishment keeps its existing scope")
	# Reported coordinates remain a snapshot even at the highest tier.
	var wireless := _watcher(origin, 100)
	wireless.reveal_wireless()
	var report: Dictionary = wireless.pat["wirelessSignal"]["point"].duplicate()
	wireless.set_context(_pctx("teach1", Vector2(origin["x"] - 100, origin["y"]), {"viol": 100}))
	check(same_json(wireless._target(), wireless.nav.snap("teach1", report)), "high alert does not turn a wireless snapshot into live tracking")


func test_save() -> void:
	var origin := _point(36)
	var pm := _watcher(origin, 75)
	pm.pat["lastSeen"] = origin.duplicate()
	pm.pat["heading"] = [1.0, 0.0]
	pm._begin_search()
	pm.hide["on"] = true
	var ctx := _pctx("teach1", Vector2(origin["x"] - 80, origin["y"] - 40), {"viol": 75})
	_patrol_run(pm, ctx, 2.0)
	var save: Dictionary = JSON.parse_string(JSON.stringify(pm.capture()))
	var untouched := save.duplicate(true)
	var loaded := _watcher(origin, 75)
	check(loaded.validate(save).is_empty(), "search plans validate through the native save schema")
	loaded.restore(save)
	check(same_json(loaded.capture(), pm.capture()), "save/load retains waypoints, direction, waypoint index and both timers")
	_patrol_run(pm, ctx, 0.5)
	_patrol_run(loaded, ctx, 0.5)
	check(pm._dist3(pm.position(), loaded.position()) < 0.5 and is_equal_approx(pm.pat["search"], loaded.pat["search"]), "a resumed search advances instead of restarting its timer")
	check(same_json(save, untouched), "advancing a restored search never mutates the input snapshot")
	var old := save.duplicate(true)
	old["pat"].erase("searchPlan")
	old["pat"].erase("heading")
	old["pat"]["search"] = 2.0
	check(loaded.validate(old).is_empty(), "existing saves without new fields remain compatible")
	loaded.restore(old)
	loaded.set_context(ctx)
	loaded.tick(0.1)
	check(loaded.pat["search"] <= 2.0 and not loaded.pat["searchPlan"].is_empty(), "legacy search keeps its remaining budget")
	for change: Dictionary in [{"searchPlan": []}, {"heading": [NAN, 0]}, {"heading": [2, 0]}, {"lastSeen": {"scene": "teach1", "x": NAN, "y": 0}}]:
		var bad := save.duplicate(true)
		bad["pat"].merge(change, true)
		check(not loaded.validate(bad).is_empty(), "malformed search metadata is rejected without crashing")
	for field: String in ["index", "ttl", "wait"]:
		var bad := save.duplicate(true)
		bad["pat"]["searchPlan"][field] = 1000
		check(not loaded.validate(bad).is_empty(), "out-of-bounds search %s is rejected" % field)
	var bad_scene := save.duplicate(true)
	bad_scene["pat"]["searchPlan"]["points"][1]["scene"] = "dorm1"
	check(not loaded.validate(bad_scene).is_empty(), "a saved search cannot introduce an unobserved cross-scene leg")
	loaded.rescued()
	check(loaded.pat["searchPlan"].is_empty() and loaded.pat["search"] == 0.0, "rescue clears the full search state")
	loaded.restore(save)
	loaded._banish()
	check(loaded.pat["searchPlan"].is_empty() and loaded.pat["search"] == 0.0, "banishing also clears the full search state")


func test_app() -> void:
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new(_test_path.get_base_dir() + "/patrol-awareness/slot.json")
	app.settings = GameSettings.new(_test_path.get_base_dir() + "/patrol-awareness/settings.json")
	root.add_child(app)
	await _frames(2)
	app.start_new_game("hard", "none")
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app.school().viol = 75.0
	var context := app._patrol_context(CampusData.layout("teach1"), app.player.capture_pose())
	app.patrol().set_context(context)
	check(context["viol"] == 75.0 and app.patrol().alert_level() == 3, "the real application feeds violation into the patroller")
	check(not app.patrol().hunting(), "high violation alone does not revoke the own-seat exemption")
	app.school().viol = 0.0
	app.patrol().set_context(app._patrol_context(CampusData.layout("teach1"), app.player.capture_pose()))
	check(app.patrol().alert_level() == 0, "the real application also lowers the threat tier when violation falls")
	app.return_to_menu()
	app.queue_free()
	await _frames(2)
	CampusData.clear_caches()
