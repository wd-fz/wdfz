extends "res://tests/support/test_suite.gd"


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


func _test_body_rules() -> void:
	var rooms := CampusData.rooms()
	var b := BodyModule.new(rooms)
	b.reset()
	var l1 := CampusData.layout("link1")
	var mid := CampusGeometry.tile_center(l1, 1, 10)
	b.set_context(_bodyctx("link1", mid, PI))
	check(b.target()["kind"] == "link" and b.hint() == "翻过栏杆 · 外侧悬空（按住空格）", "the bridge railing can be climbed")
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
