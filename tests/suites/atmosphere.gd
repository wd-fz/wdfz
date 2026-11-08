extends "res://tests/support/test_suite.gd"


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
	var scaled := DreadModule.new({}, 2.0)
	scaled.set_context({"scene": "out", "x": 450.0, "y": -10.0})
	check(scaled.area() == "out:1,-1", "outdoor atmosphere uses injected layout scale without loading content")
	var invalid_scale := DreadModule.new({}, 0.0)
	invalid_scale.set_context({"scene": "out", "x": 450.0, "y": -10.0})
	check(invalid_scale.area() == "out:3,-1", "invalid outdoor scale falls back to one without dividing by zero")
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


func _test_atmos_rules() -> void:
	var previous_seed := AtmosModule.seed
	AtmosModule.seed = "ci-atmosphere-v1"
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


	AtmosModule.seed = previous_seed


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
