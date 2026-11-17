class_name CooperativeStories
extends RefCounted
## Personal hidden experiences use domain modules, never single-player scene/pause flows.
var sim: CooperativeSimulation
var game: CooperativeGameplay

func _init(authority: CooperativeSimulation, gameplay: CooperativeGameplay) -> void:
	sim = authority
	game = gameplay

func setup(seed_value: int) -> void:
	for a: CooperativeActor in sim.active_actors():
		(a.feature(&"story.paper_plane") as PaperPlaneModule).roll(seed_value + a.id.hash())
		(a.feature(&"dlc.campus_rules") as RulesDlcModule).start(sim.room.rules_dlc, str(seed_value))

func prepare(a: CooperativeActor, ctx: Dictionary) -> void:
	var paper := a.feature(&"story.paper_plane") as PaperPlaneModule
	var gaze := a.feature(&"story.window_gaze") as WindowGazeModule
	var rules := a.feature(&"dlc.campus_rules") as RulesDlcModule
	var c := ctx.duplicate()
	c.merge({"now": a.session.clock.active_seconds, "eye": 1.65, "time": a.school().tsec, "need": SchoolClock.need_where(a.school().tsec), "playing": not a.fate().over(), "choice": not a.choice.is_empty(), "trusted": not sim.room.debug_run, "now_ms": int(sim.calendar.seconds * 1000), "tt": a.school().tt, "special": (a.feature(&"school.days") as DayModule).today(a.school().day, a.school().tsec), "on_leave": a.school().on_leave(), "seed": (a.feature(&"phone.network") as PhoneModule).run_seed,
		"steer": a.input.get("steer", {"l": 0, "r": 0, "u": 0, "d": 0})}, true)
	rules.set_context(c)
	(a.feature(&"campus.tales") as TalesModule).set_context(c)
	paper.text_override = rules.paper_text
	var pc := c.duplicate()
	pc["busy"] = c["busy"] or a.school().seated or a.watcher().hide["on"] or not gaze.current().is_empty() or not a.activities.game.is_empty()
	paper.set_context(pc)
	c["busy"] = c["busy"] or a.watcher().hide["on"] or paper.calm(c["now"]) or not a.activities.game.is_empty()
	gaze.set_context(c)

func interact(a: CooperativeActor) -> bool:
	var room: Dictionary = CampusData.rooms().get(a.location(), {})
	var at := a.point(CampusData.rooms())
	if a.location() == MazeModule.ROOM:
		var maze := a.feature(&"campus.maze") as MazeModule
		var p: Array = a.pose["position"]
		var feet := Vector3(p[0], p[1], p[2])
		var exit := maze.nearby_exit(feet, not sim.physics.bodies[a.id].is_on_floor())
		if not exit.is_empty():
			var lift := a.feature(&"campus.elevator") as ElevatorModule
			lift.ride = a.special_return.duplicate(true)
			game.apply_result(a, lift.leave_maze(String(exit["id"])))
			maze.leave()
			a.special_return.clear()
		elif maze.near_chalk(feet, false): a.bag().add("chalk")
		return true
	var dream := a.feature(&"story.inception") as InceptionModule
	if a.location() == InceptionModule.ROOM:
		if InceptionModule.near_exit(_dream_cell(a)): dream.exit_door(true)
		flush(a, "inception")
		return true
	if dream.near_top(a.location(), room, at):
		if a.bag().add("top"): dream.top = true
		return true
	var knife := a.feature(&"story.knife") as KnifeModule
	if knife.near(a.location(), room, at):
		if a.bag().add("small_knife"): knife.took = true
		return true
	var rules := a.feature(&"dlc.campus_rules") as RulesDlcModule
	var spot := rules.near(a.location(), at)
	if not spot.is_empty():
		rules.read(spot["item"]["id"])
		flush(a, "rules")
		return true
	if (a.feature(&"story.paper_plane") as PaperPlaneModule).use_here():
		flush(a, "paper")
		return true
	if (a.feature(&"campus.tales") as TalesModule).use_here():
		flush(a, "tales")
		return true
	return false

func item(a: CooperativeActor, id: String, source: String) -> bool:
	if not a.bag().has(id): return false
	if id == "small_knife":
		(a.feature(&"story.knife") as KnifeModule).use(true, source)
		flush(a, "knife")
		return true
	if id == "top":
		(a.feature(&"story.inception") as InceptionModule).spin(a.location() == InceptionModule.ROOM)
		flush(a, "inception")
		return true
	return false

func rest(a: CooperativeActor, key: String) -> bool:
	if key != "sleep": return false
	var at := a.point(CampusData.rooms())
	var from := {"room": a.location(), "x": at.x, "y": at.y, "ang": CampusGeometry.ang_from_yaw(a.pose["yaw"]), "floorY": a.pose["position"][1]}
	var intercepted := (a.feature(&"story.inception") as InceptionModule).rest(a.school().day, a.school().tsec, SchoolClock.need_where(a.school().tsec) == "教室" and not SchoolClock.is_night(a.school().tsec), a.bag().has("top"), from)
	flush(a, "inception")
	return intercepted

func _dream_cell(a: CooperativeActor) -> Vector2i:
	var room: Dictionary = CampusData.rooms()[InceptionModule.ROOM]
	var at := a.point(CampusData.rooms())
	return Vector2i(floori((at.x - room["ox"]) / room["tw"]), floori((at.y - room["oy"]) / room["th"]))

func enter_maze(a: CooperativeActor) -> void:
	var engine := game._lift_for(a)
	a.special_return = engine.ride.duplicate(true)
	var origin := String(engine.ride.get("host", "teach")) + str(int(engine.ride.get("origin", 1)))
	for other: CooperativeActor in sim.active_actors():
		if other.id != a.id and other.location() == "lift_" + String(engine.ride.get("host", "teach")):
			sim.travel(other, origin, sim.spawn(origin))
	engine.ride.clear()
	var host := String(a.special_return.get("host", "teach"))
	engine.lifts[host].merge({"phase": "idle", "floor": int(a.special_return.get("origin", 1)), "remaining": 0.0, "door": 0.0}, true)
	game.lift_owners.erase(host)
	game.lift_riders[host] = []
	sim.travel(a, MazeModule.ROOM, (a.feature(&"campus.maze") as MazeModule).enter())
	a.event("notice", {"text": "门外只剩白色的墙。队友仍在校园里。"})

func tick(a: CooperativeActor, dt: float) -> void:
	(a.feature(&"story.knife") as KnifeModule).tick(dt, a.fate().over())
	flush(a, "knife")
	if a.fate().over(): return
	if a.location() == InceptionModule.ROOM:
		(a.feature(&"story.inception") as InceptionModule).tick(dt, _dream_cell(a))
		flush(a, "inception")
		return
	if a.location() == MazeModule.ROOM:
		var p: Array = a.pose["position"]
		var maze := a.feature(&"campus.maze") as MazeModule
		maze.step(dt, {"feet": Vector3(p[0], p[1], p[2]), "moving": a.moving, "airborne": not sim.physics.bodies[a.id].is_on_floor(), "pitch": a.pose["pitch"], "ang": CampusGeometry.ang_from_yaw(a.pose["yaw"]), "eye": 1.65})
		flush(a, "maze")
		return
	for source: String in ["paper", "gaze", "tales", "rules"]:
		a.feature(CooperativeGameplay.SOURCES[source]).call("tick", dt)
		if source == "rules": (a.feature(&"dlc.campus_rules") as RulesDlcModule).advance_cues(dt)
		flush(a, source)

func flush(a: CooperativeActor, source: String) -> void:
	for e: Dictionary in a.feature(CooperativeGameplay.SOURCES[source]).call("take_events"):
		match String(e["kind"]):
			"enter":
				var room: Dictionary = CampusData.rooms()[InceptionModule.ROOM]
				var p := CampusGeometry.to_scene(room, CampusGeometry.tile_center(room, InceptionModule.START.x, InceptionModule.START.y))
				sim.travel(a, InceptionModule.ROOM, {"position": [p.x, 0, p.y], "yaw": 0.0, "pitch": 0.0})
			"loop":
				var room: Dictionary = CampusData.rooms()[InceptionModule.ROOM]
				var p := CampusGeometry.to_scene(room, CampusGeometry.tile_center(room, InceptionModule.START.x, InceptionModule.START.y))
				a.pose["position"] = [p.x, 0, p.y]
			"wake":
				var from: Dictionary = e["from"]
				var pose := sim.spawn(from["room"])
				if from.get("x") != null:
					var p := CampusGeometry.to_scene(CampusData.rooms()[from["room"]], Vector2(from["x"], from["y"]))
					pose = {"position": [p.x, from.get("floorY", 0), p.y], "yaw": CampusGeometry.yaw_from_ang(from.get("ang", 0)), "pitch": 0.0}
				sim.travel(a, from["room"], pose)
				if e["settle"]:
					a.school().change_san(snappedf(52.0 * float(a.school().pressure()["rest"]), .1))
					a.school().add_violation(15)
					(a.feature(&"campus.facilities") as FacilitiesModule).act_cool["sleep"] = a.school().game_clock() + 200
					a.event("notice", {"text": "我在宿舍醒来。队友没有离开，校园时间仍在继续。"})
			"ending":
				a.hidden_history[String(e["id"])] = true
				if e["id"] == "knife":
					sim.travel(a, "teach1", a.school().start_seated("teach1"))
					a.school().start_seated("teach1")
					a.event("notice", {"text": "《管制刀具》· 小刀被收走。你在自己的座位醒来，队友仍在行动。"})
				else: game._offer_ending(a, e["id"])
			"kill":
				game.kill(a, String(e.get("msg", e.get("text", ""))), e["fx"], e["source"], false)
				if source == "gaze": (a.feature(&"story.window_gaze") as WindowGazeModule).after_kill(a.fate().dead)
			"settle":
				if a.school().san <= 0: game.kill(a, e["text"], e["fx"], e["source"], false)
			"respawn":
				var result := (a.feature(&"campus.maze") as MazeModule).finish_respawn()
				if not a.fate().over() and result.has("pose"):
					a.pose = result["pose"]
					a.event("notice", {"text": result["text"]})
			"give":
				(a.feature(&"story.paper_plane") as PaperPlaneModule).gave(a.bag().add(e["id"]))
				flush(a, "paper")
			"read": game._choice(a, "paper", {"text": e["text"], "labels": ["折好投回", "扔掉"], "timeout": PaperPlaneModule.READ})
			"pull": a.event("gaze_pull", {"yaw": e["yaw"], "pitch": e["pitch"]})
			"san_zero": a.school().san = 0
			"viol": a.school().add_violation(float(e["amount"]))
			"tt": a.school().tt = minf(float(e["cap"]), a.school().tt + float(e["amount"]))
			"hold": a.school().tt_hold_until = float(e["until"])
			"advance":
				# Personal experiences do not jump everybody's clock; the shared calendar keeps running.
				pass
			"breath", "steps", "sound", "invert", "invert_end", "shadow_show", "shadow_hide":
				if e["kind"] == "breath": a.event("sound", {"cue": "threat.breath", "options": {"k": 0.6}})
				else: a.event(String(e["kind"]), e)
			"grant": a.event("notice", {"text": "【合作 · 规则怪谈】记录：" + String(e["id"])})
			"fact":
				var fact: Dictionary = e.get("fact", {"kind": source, "what": e.get("what", "")})
				(a.feature(&"dlc.campus_rules") as RulesDlcModule).fact(fact)
			_: game.apply_event(a, source, e)
