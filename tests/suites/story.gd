extends "res://tests/support/test_suite.gd"


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
	check(_of_kind(after_wrong, "choice").size() == 1 and String(_of_kind(after_wrong, "choice")[0]["text"]).contains(RoutesModule.EXPLANATIONS[order[0]]) and _of_kind(after_wrong, "fact_face")[0]["correct"] == false, "and shows the explanation, and the wrong answer is a fact for the ledger")
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
