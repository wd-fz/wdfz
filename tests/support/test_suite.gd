extends RefCounted
## Shared assertion and scene-tree utilities. Suites own no persistent game state.

const APP := preload("res://game/app/app.tscn")
var _runner: SceneTree
var root: Window:
	get: return _runner.root
var paused: bool:
	get: return _runner.paused
	set(value): _runner.paused = value
var physics_frame: Signal:
	get: return _runner.physics_frame
var process_frame: Signal:
	get: return _runner.process_frame
var _test_path: String:
	get: return _runner._test_path


func _init(runner: SceneTree) -> void:
	_runner = runner


func check(condition: bool, message: String) -> void:
	_runner.check(condition, message)


func same_json(a: Variant, b: Variant) -> bool:
	return _runner.same_json(a, b)


func create_timer(seconds: float) -> SceneTreeTimer:
	return _runner.create_timer(seconds)


func _session() -> GameSession:
	var result := GameSession.new()
	check(result.modules.register(DemoModule.new()).is_empty(), "register demo module")
	check(result.modules.register(CampusData.make_module()).is_empty(), "register campus module")
	result.start("migration_lab")
	return result


func _pose() -> Dictionary:
	return {"position": [0.0, 0.1, 3.0], "yaw": 0.0, "pitch": 0.0}


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


func _campus_pose(room: Variant, w: Vector2, ang: float) -> Dictionary:
	var p := CampusGeometry.to_scene(room, w)
	return {"position": [p.x, 0.05, p.y], "yaw": CampusGeometry.yaw_from_ang(ang), "pitch": 0.0}


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


func _route_towards(from: String, to: String, pm: PatrolModule) -> int:
	for i in range(1, pm.route_nodes.size()):
		if pm.route_nodes[i - 1] == from and pm.route_nodes[i] == to:
			return i
	return 1


func _gctx(x: float, y: float, extra: Dictionary = {}) -> Dictionary:
	var g := CampusData.layout("garage1")
	var c := {"scene": "garage1", "x": x, "y": y, "ang": 0.0, "run": false, "torch": false, "has_key": true, "dead": false, "enter_cool": 0.0, "busy": false,
		"can_stand": func(p: Vector2) -> bool: return CampusGeometry.tile_at(g, p) != "#" and CampusGeometry.tile_at(g, p) != "V"}
	c.merge(extra, true)
	return c


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


func _solve_lines(puzzle: Dictionary) -> Array:
	var a: Dictionary = CampusTerminal.make(String(puzzle["runSeed"]), int(puzzle["attemptId"]))["answer"]
	var body := "controller=%s\\ntransaction=%s\\ntoken=%s\\nclock=active\\nstop %s\\nstop %s\\nstop %s" % [a["controller"], a["tx"], a["token"], a["order"][0], a["order"][1], a["order"][2]]
	return ["campusctl select %s /school/assets.tsv" % a["controller"], "campusctl trace %s /school/runtime.log" % a["tx"],
		"edit /work/shutdown \"%s\"" % body, "campusctl validate /work/shutdown", "campusctl shutdown --confirm"]


func _bodyctx(scene: String, w: Vector2, ang: float, extra: Dictionary = {}) -> Dictionary:
	var c := {"scene": scene, "x": w.x, "y": w.y, "ang": ang, "seated": false, "hiding": false, "stam": 100.0, "moving": false, "locked": false, "anomaly": false, "day": 1, "dead": false}
	c.merge(extra, true)
	return c


func _xctx(w: Vector2, extra: Dictionary = {}) -> Dictionary:
	var c := {"scene": "out", "x": w.x, "y": w.y, "day": 2, "tsec": 600.0, "dead": false, "busy": false}
	c.merge(extra, true)
	return c


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


func _wall_spot(room: Dictionary) -> Vector2:
	var grid: Array = room["grid"]
	for r in grid.size():
		if String(grid[r]).substr(0, 1) == "#" and String(grid[r]).substr(1, 1) == "." and String(grid[r]).substr(2, 1) == ".":
			return CampusGeometry.tile_center(room, 1, r)
	return Vector2.ZERO


func _atmos_ctx(col: int, row: int, extra: Dictionary = {}) -> Dictionary:
	var t1 := CampusData.layout("teach1")
	var at := CampusGeometry.tile_center(t1, col, row)
	var ctx := {"scene": "teach1", "x": at.x, "y": at.y, "ang": 0.0, "day": 2, "tsec": 700.0, "viol": 0.0, "busy": false, "an_active": false,
		"an_next": -1.0, "an_next0": 0, "age": 100.0, "prop": null, "prop_ok": false, "sees_shifted": false}
	ctx.merge(extra, true)
	return ctx


func _rec(route: String, diff: String, grade: String, gscore: int, used: float, at: int, extra: Dictionary = {}) -> Dictionary:
	var r := {"at": at, "mode": "normal", "diff": diff, "talent": "none", "route": route, "routeName": route, "day": 1, "clock": 700.0,
		"time": {"active": used, "rta": null, "par": 1200.0, "used": used}, "score": {"rules": 1, "total": gscore - 400, "sum": gscore - 400, "mult": 1.0, "items": []},
		"grade": grade, "gradeName": "x", "band": "mid", "memo": "m", "gradeScore": gscore, "timeScore": 400, "gate": false, "capped": false,
		"explore": {"pct": 10, "place": 10, "sketch": 10, "clue": 10}, "san": {"final": 50, "min": 20}, "ach": {"run": [], "newly": []}, "source": "play", "version": "t"}
	r.merge(extra, true)
	return r


func _notices(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e["kind"] == "notice").map(func(e: Dictionary) -> String: return e["text"])


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


func _night_hunt(scene: String) -> bool:
	var pm := CampusData.make_patrol()
	pm.reset()
	var room: Variant = CampusData.layout(scene) if scene != "out" else null
	var w := Vector2(1000, 1000) if room == null else CampusGeometry.tile_center(room, 10, 5)
	pm.set_context(_pctx(scene, w, {"night": true, "need_where": "宿舍"}))
	return pm.eligible()


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
