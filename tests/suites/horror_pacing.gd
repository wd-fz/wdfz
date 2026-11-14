extends "res://tests/support/test_suite.gd"
## The 2026-11-14 horror plan (docs/plan/中式与西式恐怖及吓人手法.md), items 1–5, 7 and 8: the scare-overlap
## rule, the patroller heard in three tiers, the chalk revisit, the corridor notice, the director's pressure,
## the locker that is not safe forever and the playtest fear statistics.


func _of_kind(events: Array, kind: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e["kind"] == kind)


func _ctx(scene: String = "teach1", c: int = 30, r: int = 17) -> Dictionary:
	var at := CampusGeometry.tile_center(CampusData.layout(scene), c, r)
	return {"scene": scene, "x": at.x, "y": at.y, "ang": 0.0, "san": 100.0, "viol": 0.0, "night": 0.0, "day": 2, "tsec": 530.0, "free": true}


func test_rules() -> void:
	_test_overlap_rule()
	_test_precursor()
	_test_director()
	_test_board_and_notice()
	_test_locker()
	_test_stats()


## Item 1: a new anomaly does not start during a chase; a foretold one keeps its time.
func _test_overlap_rule() -> void:
	var an := AnomalyModule.new(CampusData.rooms(), {})
	an.reset()
	var at := CampusGeometry.tile_center(CampusData.layout("teach1"), 30, 17)
	var ctx := {"scene": "teach1", "x": at.x, "y": at.y, "tsec": 700.0, "day": 2, "diff": "normal", "san": 100.0, "viol": 0.0, "patrol_chase": true}
	an.set_context(ctx)
	an.an["next"] = 0.5
	an.tick(3.0)
	check(not an.is_active() and float(an.an["next"]) >= AnomalyModule.CHASE_GRACE - 0.001, "during a chase the next anomaly waits (held at %.1f s)" % float(an.an["next"]))
	ctx["patrol_chase"] = false
	an.set_context(ctx)
	an.tick(AnomalyModule.CHASE_GRACE - 1.0)
	check(not an.is_active() and float(an.an["next"]) > 0.0, "and still waits a few seconds after the chase ends")
	an.an["locked"] = true
	an.an["next"] = 0.5
	ctx["patrol_chase"] = true
	an.set_context(ctx)
	an.tick(1.0)
	check(float(an.an["next"]) < AnomalyModule.CHASE_GRACE, "a foretold anomaly keeps its told time even in a chase")


## Item 2: three tiers by walking distance; escalation plays at once; nothing when unheard.
func _test_precursor() -> void:
	check(PatrolPrecursor.tier_of(30.0) == 0 and PatrolPrecursor.tier_of(20.0) == 1 and PatrolPrecursor.tier_of(10.0) == 2 and PatrolPrecursor.tier_of(4.0) == 3 and PatrolPrecursor.tier_of(INF) == 0, "far 14–24 m, mid 6–14 m, near under 6 m")
	var p := PatrolPrecursor.new(7)
	var first := p.step(0.1, 20.0, true)
	check(first.get("tier", "") == "far" and first["id"] in ["dread.door", "dread.steps"] and float(first["k"]) < 0.3, "far: a quiet door or steps at once")
	check(p.step(0.1, 20.0, true).is_empty(), "then a long pause (7–11 s)")
	var mid := p.step(0.1, 10.0, true)
	check(mid.get("tier", "") == "mid" and mid["id"] == "dread.steps", "closer: steps at once")
	var n := 0
	for i in 24:
		if not p.step(0.1, 10.0, true).is_empty():
			n += 1
	check(n == 2, "mid steps about every 1.1 s (%d in 2.4 s)" % n)
	var near := p.step(0.1, 4.0, true)
	check(near.get("tier", "") == "near" and float(near["k"]) > float(mid["k"]), "near: louder")
	check(p.step(0.1, 4.0, false).is_empty() and p.tier == 0, "drawn in the scene (or not walking): the precursor stops")


## Item 5: pressure held by real events, a breather after, a nudge after long calm.
func _test_director() -> void:
	var d := DreadModule.new(CampusData.rooms())
	d.reset()
	var ctx := _ctx()
	ctx["an_active"] = true
	ctx["busy"] = true
	d.set_context(ctx)
	d.tick(1.0)
	check(d.pressure >= 0.79 and d.pace() < 0.5, "an anomaly holds the pressure up and slows the false threats")
	ctx["an_active"] = false
	ctx["busy"] = false
	d.set_context(ctx)
	for i in 60:
		d.tick(1.0)
	check(absf(d.pressure - 0.4) < 0.02 and d.pace() > 0.6 and d.pace() < 1.0, "half of it is gone a minute later (%.2f)" % d.pressure)
	for i in 400:
		d.tick(1.0)
	check(d.pressure < 0.05 and d.calm > 150.0 and is_equal_approx(d.pace(), DreadModule.PACE["quiet_boost"]), "after a long calm the ambience comes a little more often")
	ctx["chase"] = true
	d.set_context(ctx)
	d.tick(0.1)
	check(d.calm == 0.0 and d.pressure >= 0.79, "a chase counts as real too")
	ctx["chase"] = false
	ctx["inspect"] = true
	d.pressure = 0.0
	d.set_context(ctx)
	d.tick(0.1)
	check(d.pressure >= 0.39 and d.pressure < 0.79, "an inspection raises it less")


## Items 3 and 4: the chalk revisit and the corridor notice.
func _test_board_and_notice() -> void:
	var day := 1
	var board_seen := false
	while day < 400 and not board_seen:
		var key := "%d:teach1" % day
		board_seen = floori(DreadModule.lhash("%s:%d" % [key, 2]) * DreadModule.VISIT_KINDS.size()) == DreadModule.VISIT_KINDS.find("board")
		if not board_seen:
			day += 1
	check(board_seen, "some day the second visit writes chalk (day %d)" % day)
	var v := DreadModule.new(CampusData.rooms())
	v.reset()
	var ctx := _ctx()
	ctx["day"] = day
	v.set_context(ctx)
	v.enter("teach1")
	v.enter("teach1")
	var boards := _of_kind(v.take_events(), "visit").filter(func(e: Dictionary) -> bool: return e["fx"] == "board")
	check(boards.size() == 1 and String(boards[0]["text"]) in DreadModule.BOARD_LINES and boards[0].has("x"), "the chalk line is one of the lines and is placed on a wall")
	# The notice: two lines true to the timetable, one false in red.
	for d in range(2, 12):
		var n := DreadModule.notice_lines(d, 530.0)
		var lines: Array = n["lines"]
		var fakes := lines.filter(func(l: Dictionary) -> bool: return bool(l["fake"]))
		check(lines.size() == 3 and fakes.size() == 1 and lines[int(n["fake"])]["fake"], "day %d: three lines, exactly one false" % d)
		if d == 2:
			var texts := " ".join(lines.map(func(l: Dictionary) -> String: return String(l["text"])))
			check(texts.contains("第 2 节") or texts.contains("操场"), "the true class line names the next lesson in the timetable (第 2 节 after 08:50)")
	check(DreadModule.notice_lines(5, 530.0) == DreadModule.notice_lines(5, 530.0), "the same day gives the same notice (a load does not reroll it)")
	var nd := DreadModule.new(CampusData.rooms())
	nd.reset()
	var nctx := _ctx()
	nctx["day"] = 1
	nd.set_context(nctx)
	for i in 900:
		nd.tick(1.0)
	check(_of_kind(nd.take_events(), "notice").is_empty(), "never on the first day")
	nctx["day"] = 2
	nctx["free"] = false
	nd.set_context(nctx)
	for i in 900:
		nd.tick(1.0)
	check(_of_kind(nd.take_events(), "notice").is_empty(), "never during a lesson")
	nctx["free"] = true
	nd.set_context(nctx)
	var shown: Array = []
	for i in 2000:
		nd.tick(1.0)
		shown.append_array(_of_kind(nd.take_events(), "notice"))
	check(shown.size() == 1 and nd.visits.has("notice:2") and (shown[0]["lines"] as Array).size() == 3, "once in a free period on day 2, and only once that day")
	nctx["scene"] = "out"
	nctx["day"] = 3
	nd.set_context(nctx)
	for i in 2000:
		nd.tick(1.0)
	check(_of_kind(nd.take_events(), "notice").is_empty(), "never outdoors")
	var back := DreadModule.new(CampusData.rooms())
	back.restore(nd.capture())
	check(back.visits.has("notice:2"), "the day's notice is remembered in the save")


## Item 7: knock, breath, push; paused under threat; reset on leaving.
func _test_locker() -> void:
	var l := LockerOverstay.new()
	var beats: Array = []
	for i in 700:
		var b := l.tick(0.1, true, false)
		if b != "":
			beats.append([b, snappedf(l.t, 0.1)])
	check(beats.size() == 3 and beats[0][0] == "knock" and beats[1][0] == "breath" and beats[2][0] == "push", "knock, breath, then out (%s)" % [beats])
	check(absf(float(beats[0][1]) - 45.0) < 0.2 and absf(float(beats[2][1]) - 65.0) < 0.2, "at 45 s and 65 s")
	l.reset()
	var any := ""
	for i in 1000:
		any += l.tick(0.1, true, true)
	check(any == "" and l.t == 0.0, "never while there is a threat: the clock does not run")
	for i in 400:
		l.tick(0.1, true, false)
	l.tick(0.1, false, false)
	check(l.t == 0.0 and l.stage == 0, "leaving resets it")


## Item 8 (and the overlap record of item 1).
func _test_stats() -> void:
	var s := HorrorStats.new()
	var st := {"yaw": 0.0}
	for i in 100:
		s.tick(0.1, st)
	st["chase"] = true
	for i in 30:
		s.tick(0.1, st)
	st["anomaly"] = true
	st["lethal"] = true
	for i in 20:
		s.tick(0.1, st)
	st["chase"] = false
	for i in 10:
		s.tick(0.1, st)
	var r := s.report()
	check(int(r["starts"].get("chase", 0)) == 1 and int(r["starts"].get("anomaly", 0)) == 1 and int(r["gap"]["count"]) == 1, "encounter starts and the gap between them")
	check(int(r["overlap"]["episodes"].get("anomaly+chase", 0)) == 1 and absf(float(r["overlap"]["seconds"]["anomaly+chase"]) - 2.0) < 0.15, "a lethal anomaly during a chase is recorded as an overlap (2 s)")
	check(int(r["chase"]["escaped"]) == 1, "a chase that ends alive is an escape")
	st = {"yaw": 0.0}
	s.tick(0.1, st)
	st["yaw"] = PI * 0.9
	s.tick(0.2, st)
	check(int(s.report()["lookBacks"]) == 1, "a quick turn of more than 120° is a look-back")
	st["hiding"] = true
	for i in 50:
		s.tick(0.1, st)
	st["hiding"] = false
	s.tick(0.1, st)
	check(int(s.report()["hide"]["count"]) == 1 and absf(float(s.report()["hide"]["longest"]) - 5.0) < 0.15, "hides and how long")
	s.death("patrol")
	s.death("patrol")
	s.skip()
	s.pause()
	r = s.report()
	check(int(r["deaths"]["patrol"]) == 2 and int(r["repeatDeaths"]) == 1 and int(r["skips"]) == 1 and int(r["pauses"]) == 1, "deaths by cause, repeats, skips and pauses")
	var pt := Playtest.new(_test_path.get_base_dir() + "/horror-playtest.json")
	pt.horror_frame(1.0, {"chase": true})
	check(pt.horror.seconds == 0.0, "nothing is measured unless the observer records")
	pt.start({}, Vector2i(1280, 720))
	pt.frame(0.1, "play")
	pt.horror_frame(0.5, {"chase": true})
	check(pt.export().has("horror") and float(pt.export()["horror"]["seconds"]) > 0.0, "the playtest export carries the fear statistics")
	pt.recording = false


## In the app: the corridor notice is drawn on a wall and goes into the notebook once read; the locker
## pushes the player out after its warnings.
func test_app() -> void:
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new(_test_path.get_base_dir() + "/horror/slot.json")
	app.settings = GameSettings.new(_test_path.get_base_dir() + "/horror/settings.json")
	root.add_child(app)
	await _frames(3)
	app.start_new_game()
	await _until_started(app)
	await _frames(3)
	var cw := app._campus_world()
	var d := app.dread()
	check(cw != null and d != null, "a run with the campus")
	if cw == null or d == null:
		app.queue_free()
		return
	d.set_context(app._dread_context())
	var pose: Dictionary = app.player.capture_pose()
	var room: Variant = app.campus().room(app.session.world_id)
	var p: Array = pose["position"]
	var yaw := float(pose["yaw"])
	var ahead := CampusGeometry.to_world(room, float(p[0]) - sin(yaw) * 1.6, float(p[2]) - cos(yaw) * 1.6)
	var content := DreadModule.notice_lines(2, 530.0)
	d.notice = {"day": 2, "lines": content["lines"], "fake": content["fake"], "x": ahead.x, "y": ahead.y}
	d.events.append({"kind": "notice", "day": 2, "lines": content["lines"], "fake": content["fake"], "x": ahead.x, "y": ahead.y})
	app._apply_dread_events()
	await _frames(2)
	check(cw.wall_text_kind() == "notice" and (cw.wall_text_lines() as Array).size() == 3, "the notice sheet is on the wall")
	var face: Dictionary = app._wall_face(ahead)
	app.player.camera.look_at(face["pos"])
	app._read_wall_notice()
	var entry: Dictionary = app.investigation().entries.get("notice:2", {})
	check(not entry.is_empty() and String(entry["text"]).contains("红字") and entry["kind"] == "规则", "reading it writes the three lines into the notebook, the red one marked")
	d.events.append({"kind": "clear"})
	app._apply_dread_events()
	await _frames(1)
	check(cw.wall_text_kind() == "", "leaving the room takes it down")
	# The locker.
	var watcher := app.patrol()
	watcher.hide["on"] = true
	app.player.hiding = true
	var san0: float = app.school().san
	app.locker_overstay.reset()
	app.locker_overstay.t = LockerOverstay.PUSH - 0.05
	app.locker_overstay.stage = 2
	app._locker_overstay_step(0.1, watcher, app.school())
	await _frames(1)
	check(not bool(watcher.hide["on"]) and not app.player.hiding and absf(app.school().san - (san0 - LockerOverstay.SAN_COST)) < 0.01, "after the warnings the locker pushes the player out, SAN −4")
	app.queue_free()
	await _frames(2)
