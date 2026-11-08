extends "res://tests/support/test_suite.gd"


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


func _test_fake_people() -> void:
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new(_test_path)
	app.settings = GameSettings.new(_test_path.get_base_dir() + "/settings.json")
	root.add_child(app)
	await _frames()
	app.start_new_game()
	await _frames(3)
	app.patrol().pat["safety"] = 999.0
	var fnm := app.fake_normal()
	fnm.fn["on"] = true
	fnm.fn["v"] = 10.0
	app.school().day = 2
	await _frames(4)
	check(is_instance_valid(app._fake_people) and app._fake_people.get_child_count() >= 1 and app._fake_people.get_child_count() <= 4, "on the fake-normal day a few dull people stand in the room (%d)" % (app._fake_people.get_child_count() if is_instance_valid(app._fake_people) else -1))
	fnm.fn["v"] = 80.0
	await _frames(3)
	check(app._fake_people == null, "past 72 laughs they are gone")
	fnm.fn["v"] = 10.0
	fnm.fn["on"] = false
	await _frames(3)
	check(app._fake_people == null, "and when the fake-normal day ends")
	app.queue_free()
	await _frames(2)


func _test_call_budget() -> void:
	var rooms := CampusData.rooms()
	var radio := BroadcastModule.new(rooms, CampusData.patrol_nav())
	radio.reset()
	radio.set_seed(42)
	var spot := _spot("teach1", [12, 18])
	radio.b["nextCall"] = 0.0
	radio.set_context(_bctx("teach1", spot, [], {"dread_ok": false}))
	radio.tick(1.0)
	check(radio.b["current"] == null and radio.b["nextCall"] == 0.0 and _of_kind(radio.take_events(), "dread_note").is_empty(), "no roll call while the scare budget says wait: it keeps waiting")
	radio.set_context(_bctx("teach1", spot, [], {"dread_ok": true}))
	radio.tick(1.0)
	var ev := radio.take_events()
	check(radio.b["current"] != null and float(radio.b["nextCall"]) > 180.0 and _of_kind(ev, "dread_note").size() == 1 and _of_kind(ev, "dread_note")[0]["what"] == "broadcast-call", "when it is quiet the call is made, the next one 180–260 s later, and the budget is spent")


func _test_inspection_scatter() -> void:
	var rooms := CampusData.rooms()
	var cw := CampusWorld.new()
	check(not cw.scattering(), "no scatter before a check")
	cw.free()


func _test_broadcast_props() -> void:
	check(BroadcastProps.tags_for("admin2").is_empty() and BroadcastProps.tags_for("gear1").size() == 1 and BroadcastProps.tags_for("teach6").size() == 1, "the tags sit in the rooms of the sources, the key and the fuse")
	var bp := BroadcastProps.new()
	root.add_child(bp)
	bp.build(CampusData.rooms()["admin2"])
	var n0 := bp.count()
	check(n0 == 13, "the station has its door signs, amplifier, microphone and book (%d)" % n0)
	bp.set_fuse(true)
	check(bp.count() == n0, "mending the fuse only changes the sign")
	bp.build(CampusData.rooms()["teach2"])
	check(bp.count() == 0, "other rooms have no station props")
	bp.queue_free()


func _test_link_view() -> void:
	var cw := CampusWorld.new()
	cw.scene_id = "link1"
	check(CampusPortals.link_ports(CampusData.campus()["campus_link"], CampusData.rooms(), "link1").size() == 2, "the first bridge has a port at each end")
	check(CampusPortals.link_ports(CampusData.campus()["campus_link"], CampusData.rooms(), "teach3").is_empty(), "a room off the bridges has no neighbour to show")
	cw.free()


func _test_legacy_import() -> void:
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new(_test_path.get_base_dir() + "/legacy-import/save.json")
	root.size = Vector2i(1280, 720)
	root.add_child(app)
	await _frames()
	var save := {"v": 1, "clockVersion": 2, "mode": "in", "room": "teach1", "x": 500.0, "y": 300.0, "ang": 1.0, "pitch": 0.1, "tsec": 800, "day": 3, "diff": "hard", "san": 61.5, "viol": 12,
		"stam": 40, "tt": 25, "bag": ["torch", "pill"], "hot": ["torch", null], "talent": "watch"}
	var why := app.import_legacy_save("not json")
	check(not why.is_empty() and app.session == null, "a file that is not JSON is refused and nothing starts")
	why = app.import_legacy_save(JSON.stringify(save))
	await _frames(3)
	check(why.is_empty() and app.session != null and app.school().day == 3 and absf(app.school().tsec - 800.0) < 1.0, "an old save starts a run on its day and time")
	check(absf(app.school().san - 61.5) < 12.0 and absf(app.school().viol - 12.0) < 12.0 and app.items().bag == ["torch", "pill"] and app.talent().id == "watch" and app.story().diff == "hard", "SAN, violation, bag, talent and difficulty come over")
	check(app.session.world_id == "teach1" and app.runscore().legacy == 1 and app.player.enabled and not app.player.seated, "it puts you where you stood and marks the run as from an old save")
	app.queue_free()
	await _frames()


func _test_legacy_save() -> void:
	var rooms := CampusData.rooms()
	var items: Dictionary = CampusData.campus().get("items", {})
	var keys: Array = TalentModule.KEYS
	var good := {"v": 1, "clockVersion": 2, "mode": "in", "room": "teach1", "x": 500.0, "y": 300.0, "ang": 1.0, "pitch": 0.1, "tsec": 800, "day": 3, "diff": "hard", "san": 61.5, "viol": 12,
		"stam": 40, "tt": 25, "bag": ["torch", "pill", "ghost_item"], "hot": ["torch", "pill"], "talent": "watch"}
	var p := LegacySave.plan(good, rooms, items, keys)
	check(String(p["error"]).is_empty() and p["world"] == "teach1" and p["day"] == 3 and p["diff"] == "hard" and p["talent"] == "watch" and is_equal_approx(float(p["san"]), 61.5), "a good old save is planned")
	check(p["bag"] == ["torch", "pill"] and p["dropped"] == ["ghost_item"] and p["hot"] == ["torch", "pill"], "items this version does not have are dropped, the hotbar keeps what is in the bag")
	check(not String(LegacySave.plan("nope", rooms, items, keys)["error"]).is_empty(), "something that is not an object is refused")
	check(not String(LegacySave.plan({"x": 1, "y": 2, "tsec": 2000}, rooms, items, keys)["error"]).is_empty(), "a time out of range is refused")
	var bad_room := good.duplicate()
	bad_room["room"] = "nowhere"
	check(not String(LegacySave.plan(bad_room, rooms, items, keys)["error"]).is_empty(), "an unknown room is refused")
	var out := {"mode": "out", "x": 10, "y": 20, "tsec": 700, "day": 1, "san": 500, "talent": "bogus"}
	var po := LegacySave.plan(out, rooms, items, keys)
	check(String(po["error"]).is_empty() and po["world"] == "out" and float(po["san"]) == 100.0 and po["talent"] == "none", "numbers are clamped and an unknown talent becomes none")
	var bad_clock := good.duplicate()
	bad_clock["clockVersion"] = 9
	check(not String(LegacySave.plan(bad_clock, rooms, items, keys)["error"]).is_empty(), "an unknown clock version is refused")


func _test_mirror_view() -> void:
	check(MirrorView.tier_of(90.0) == 0 and MirrorView.tier_of(55.0) == 1 and MirrorView.tier_of(30.0) == 2 and MirrorView.tier_of(10.0) == 3, "the four tiers of the mirror by SAN")
	check(is_equal_approx(MirrorView.facing(0.0, Vector2(-1, 0)), 1.0) and is_equal_approx(MirrorView.facing(PI, Vector2(-1, 0)), -1.0), "facing is 1 when squarely at the mirror")
	check(is_equal_approx(MirrorView.lateral(Vector2(10, 20), Vector2(0, 0), Vector2(-1, 0)), -20.0 * CampusGeometry.U2M) or is_equal_approx(MirrorView.lateral(Vector2(10, 20), Vector2(0, 0), Vector2(-1, 0)), 20.0 * CampusGeometry.U2M), "the sideways offset is measured along the mirror")
	var buf: Array = [[0.0, 0.1, 1.0], [0.4, 0.2, 1.0], [0.8, 0.3, 1.0], [1.2, 0.4, 1.0]]
	check(MirrorView.lagged(buf, 1.2, 0.5)[1] == 0.2 and MirrorView.lagged(buf, 1.2, 0.0)[1] == 0.4 and MirrorView.lagged(buf, 0.1, 0.5)[1] == 0.1, "a beat behind replays the position from half a second ago")
	var mv := MirrorView.new()
	root.add_child(mv)
	mv.build(CampusData.rooms()["teach1"], [{"w": Vector2(1392.0, 1917.5), "n": Vector2(-1, 0)}])
	check(mv.count() == 1, "a mirror hangs over the basin")
	mv.update(0.1, Vector2(1380, 1917.5), 0.0, 10.0, 1.0, true)
	check(((mv._mirrors[0]["arm"]) as Node3D).visible, "at the lowest tier with the raise on, the arm shows")
	mv.queue_free()


func _test_canteen_view() -> void:
	var room: Dictionary = CampusData.rooms()["canteen1"]
	var ly := CanteenView.layout(room)
	check(not ly.is_empty() and (ly["lamp"] as Vector2).x > (ly["server"] as Vector2).x, "the lamp is over the counter, the server at its west head")
	check(CanteenView.layout(CampusData.rooms()["teach1"]).is_empty(), "a room without a counter has no layout")
	var cv := CanteenView.new()
	root.add_child(cv)
	cv.build(room)
	check(cv.built(), "the lamp, bowl and server are built")
	cv.update(true, Vector2(0, 0), false)
	check(cv.visible and cv._bowl.visible, "lit after lights out, with the bowl")
	cv.update(true, Vector2(0, 0), true)
	check(not cv._bowl.visible, "the bowl is gone once eaten tonight")
	cv.update(false, Vector2(0, 0), false)
	check(not cv.visible, "dark before lights out")
	cv.queue_free()


func _test_chase_dash() -> void:
	check(not CarChaseView.shade_state(0.0, 0, 0.0)["visible"] and CarChaseView.shade_state(0.1, 0, 0.0)["visible"] and not CarChaseView.shade_state(0.1, 1, 0.0)["visible"] and CarChaseView.shade_state(0.9, 4, 0.0)["visible"], "the shadows in the mirror come one by one as the pursuit closes")
	check(CarChaseView.shade_state(1.0, 0, 0.0)["scale"].x > CarChaseView.shade_state(0.1, 0, 0.0)["scale"].x, "and grow")


func _test_anomaly_traces() -> void:
	var an := AnomalyModule.new(CampusData.rooms(), {})
	var me := Vector2(100, 200)
	check(an.trace_for("rain", {}, me, "teach1", 0.0) == {"k": "puddle", "x": 100.0, "y": 200.0, "room": "teach1"} and an.trace_for("rain", {}, me, "out", 0.0)["room"] == "", "the rain leaves a puddle where you stood, outdoors it is room-less")
	check(an.trace_for("moth", {"src": {"x": 5.0, "y": 6.0}}, me, "teach1", 0.0)["k"] == "moths" and an.trace_for("moth", {}, me, "teach1", 0.0).is_empty(), "moths leave the dead ones at their source, none without a source")
	check(an.trace_for("cup", {"phase": 2, "lx": 1.0, "ly": 2.0}, me, "teach1", 0.0)["room"] == "" and an.trace_for("cup", {"phase": 1}, me, "out", 0.0).is_empty(), "the cup lands outdoors and only after it fell")
	check(an.trace_for("necker", {}, me, "out", 300.0)["x"] == 300.0 and an.trace_for("blackout", {}, me, "out", 0.0).is_empty(), "the necker leaves marks on the fence, a blackout leaves none")
	for i in 45:
		an.traces.append({"k": "dust", "x": 0.0, "y": 0.0, "room": ""})
		while an.traces.size() > AnomalyModule.TRACE_MAX:
			an.traces.pop_front()
	check(an.traces.size() == 40, "at most 40 are kept")
	check(Traces.dynamic_for([{"k": "dust", "room": "teach1"}, {"k": "dust", "room": ""}], "teach1").size() == 1 and Traces.dynamic_for([{"k": "dust", "room": ""}], "out").size() == 1, "each scene shows its own leftovers")


func _test_model_tiers() -> void:
	var was := CampusData.tier
	CampusData.tier = CampusData.DEFAULT_TIER
	check(CampusData.scene_path("teach1") == CampusData.SCENE_DIR + "teach1.glb" and CampusData.tiers_available().has(CampusData.DEFAULT_TIER), "the default tier loads from the usual folder")
	CampusData.tier = 0
	check(CampusData.scene_path("teach1") == "res://assets/campus_q0/scenes/teach1.glb" and CampusData.tiers_available() == [0, 1, 2, 3, 4], "all five tiers are exported and tier 0 loads its own model")
	CampusData.tier = 3
	check(CampusData.scene_path("lab2") == "res://assets/campus_q3/scenes/lab2.glb" and ResourceLoader.exists(CampusData.scene_path("stair_garage")), "every scene exists in every tier, stairwells included")
	for t in [0, 1, 3, 4]:
		CampusData.tier = t
		var n := 0
		for id: String in CampusData.rooms():
			if ResourceLoader.exists(CampusData.scene_path(id)) and CampusData.scene_path(id).contains("campus_q%d" % t):
				n += 1
		check(n == CampusData.rooms().size(), "tier %d has a model for every room (%d)" % [t, n])
	CampusData.tier = was


func _test_weather_fx() -> void:
	check(WeatherFx.wetness(0.0) == 0.0 and WeatherFx.wetness(5.0) == 0.5 and WeatherFx.wetness(30.0) == 1.0, "the puddles fill in ten seconds")
	check(WeatherFx.threat(0.0, false) == 0.0 and WeatherFx.threat(6.5, false) == 1.0 and WeatherFx.threat(4.5, true) == 1.0 and WeatherFx.threat(3.0, true) > WeatherFx.threat(3.0, false), "the swarm closes in faster on nightmare")
	var rain := WeatherFx.new()
	root.add_child(rain)
	rain.setup_rain(Vector3.ZERO)
	for i in 30:
		rain.update_rain(0.05, Vector3.ZERO, 0.0)
	check(rain._seeds.size() == WeatherFx.RAIN_COUNT and rain._puddles.size() == 9, "the rain has its drops and puddles")
	var seen := 0
	for m in rain._rings:
		seen += 1 if m.visible else 0
	check(seen > 0, "drops that land spread rings (%d)" % seen)
	rain.queue_free()
	var swarm := WeatherFx.new()
	root.add_child(swarm)
	swarm.setup_moths(Vector3(2, 0, 3))
	for i in 40:
		swarm.update_moths(0.05, Vector3(0, 1.7, 0), 6.5, false)
	var nearest := 99.0
	for m: Dictionary in swarm._moths:
		nearest = minf(nearest, (m["p"] as Vector3).distance_to(Vector3(0, 1.7, 0)))
	check(nearest >= 0.34 and swarm.distance < 3.0, "the swarm is drawn onto you but never onto your face (nearest %.2f m, mean %.2f)" % [nearest, swarm.distance])
	swarm.queue_free()


func _test_traces() -> void:
	check(Traces.for_scene("garage1").size() == 1 and Traces.for_scene("out").size() == 1 and Traces.for_scene("teach2").is_empty(), "each fixed trace belongs to one scene")
	var tr := Traces.new()
	root.add_child(tr)
	tr.build("garage1", CampusData.rooms()["garage1"])
	check(tr.count() == 52, "the drag marks are 26 pairs of shoe prints (%d)" % tr.count())
	tr.build("teach1", CampusData.rooms()["teach1"])
	check(tr.count() == 5, "five scratches by the toilet door")
	tr.queue_free()


func _test_phantoms() -> void:
	var ph := Phantoms.new()
	root.add_child(ph)
	var room: Dictionary = CampusData.rooms()["teach1"]
	var cam := Vector3(17.3, 1.7, 1.4)
	var stand := func(_w: Vector2) -> bool: return true
	ph.hallucinate(1.0, true, 80.0, cam, 0.0, room, 0.0, stand)
	check(not ph.hallu_visible(), "no hallucination while SAN is above 32")
	var seen := false
	for i in 120:
		ph.hallucinate(1.0, true, 10.0, cam, 0.0, room, 0.0, stand)
		seen = seen or ph.hallu_visible()
	check(seen, "a low SAN brings the figure at the edge of the view")
	# Turning to it takes it away at once.
	ph._hallu.visible = true
	var a_to := atan2(ph._hallu.position.z - cam.z, ph._hallu.position.x - cam.x)
	ph.hallucinate(0.01, true, 10.0, cam, a_to, room, 0.0, stand)
	check(not ph.hallu_visible(), "looking at it makes it gone")
	ph.apparition(1.0, false, true, false, 50.0, cam, 0.0, room, 0.0, stand, func(_a: Vector2, _b: Vector2) -> bool: return true)
	check(not ph.appar_visible(), "no apparition when something else is going on")
	var shown := false
	for i in 200:
		ph.apparition(1.0, true, true, false, 50.0, cam, 0.0, room, 0.0, stand, func(_a: Vector2, _b: Vector2) -> bool: return true)
		shown = shown or ph.appar_visible()
	check(shown, "the far figure appears in the dark")
	ph.apparition(0.1, true, true, true, 50.0, cam, atan2(ph._appar.position.z - cam.z, ph._appar.position.x - cam.x), room, 0.0, stand, func(_a: Vector2, _b: Vector2) -> bool: return true)
	check(not ph.appar_visible() or ph._appar_life > 0.0, "the torch on it can send it away")
	ph.show_smile("behind", cam, 0.0)
	check(ph.smile_mode() == "behind" and absf(ph._smile.position.x - (cam.x + 1.7)) < 0.001, "the smile stands 1.7 m behind")
	ph.tick_smile(3.0, cam)
	check(ph.smile_mode() == "", "and fades after 2 s")
	ph.show_smile("jump", cam, 0.0)
	ph.tick_smile(0.2, cam)
	check(ph._smile.scale.x > 0.9 and ph._smile.scale.x < 0.93, "the jump smile fills the view within 0.18 s")
	ph.queue_free()


func _test_chalk_texture() -> void:
	for sym: String in ChalkTexture.SYMBOLS:
		var img := ChalkTexture.image(sym)
		var inked := 0
		for y in range(0, ChalkTexture.SIZE, 2):
			for x in range(0, ChalkTexture.SIZE, 2):
				if img.get_pixel(x, y).a > 0.3:
					inked += 1
		check(img.get_width() == 128 and inked > 150 and inked < 2500, "the chalk picture of %s is drawn (%d inked samples)" % [sym, inked])
	check(ChalkTexture.image("x").get_pixel(64, 64).a > 0.0 and ChalkTexture.image("x").get_pixel(2, 64).a == 0.0, "the picture is transparent away from the strokes")
	check(MarksModule.SYMS.size() == ChalkTexture.SYMBOLS.size(), "every mark symbol has a chalk picture")


func _test_chalk_notes() -> void:
	var room: Dictionary = CampusData.rooms()["teach1"]
	var w := Vector2(float(room["ox"]) + 48.5 * float(room["tw"]), float(room["oy"]) + 11.5 * float(room["th"]))
	var west := ChalkNotes.spot(room, w, Vector2(-1, 0))
	check(String(west["kind"]) == "wall" and int(west["nx"]) == -1 and int(west["d"]) <= 6, "the forecast finds the wall ahead (the front wall with the board)")
	check(String(ChalkNotes.spot(room, w, Vector2(0, 1))["kind"]) == "wall" and String(ChalkNotes.spot({}, w, Vector2(1, 0))["kind"]) == "floor", "a wall within six tiles, else the floor")
	check(is_equal_approx(ChalkNotes.skip_interval(12.0), 5.024) and ChalkNotes.skip_interval(100.0) == 1.0, "truancy writing comes faster with violation, at most once a second")
	check(ChalkNotes.skip_active(true, 12.0, false) and not ChalkNotes.skip_active(true, 10.0, false) and ChalkNotes.skip_active(true, 10.0, true) and not ChalkNotes.skip_active(true, 7.0, true) and not ChalkNotes.skip_active(false, 50.0, true), "truancy writing starts at 12, stays above 8, needs a wrong place")
	var cn := ChalkNotes.new()
	root.add_child(cn)
	check(cn.update_forecast(true, "10:15", room, w, Vector2(-1, 0), Vector3.ZERO, 0.1) and cn.forecast_text() == "10:15", "the forecast is written")
	cn.update_forecast(false, "", room, w, Vector2(-1, 0), Vector3.ZERO, 0.1)
	check(not cn.has_forecast(), "and wiped when no anomaly is coming")
	for i in 40:
		cn.update_skip(10.0, true, 60.0, room, Vector3(0, 0, 0))
	check(cn.skip_count() > 0 and cn.skip_count() <= ChalkNotes.MAX_SKIP, "the truancy writing is capped at 28")
	cn.update_skip(0.1, false, 0.0, room, Vector3.ZERO)
	check(cn.skip_count() == 0, "and wiped when the violation falls")
	cn.queue_free()


func _test_day_banner() -> void:
	var at := DayBanner.spot(CampusData.layout("out"))
	check(at != Vector3.ZERO and is_equal_approx(at.y, 5.55) and is_equal_approx(at.x, (397.0 + 283.5 / 2.0) * 2.0 / 9.0) and is_equal_approx(at.z, (875.5 + 99.0) * 2.0 / 9.0 + 0.82), "the banner hangs on the front of the teaching building, second floor")
	check(DayBanner.spot({}) == Vector3.ZERO, "no building, no banner")


func _test_death_cg() -> void:
	for c: String in DeathCG.CAUSES:
		check((StoryModule.DURATIONS.has(c) or DeathCG.LENGTH.has(c)) and DeathCG.has(c), "death scene %s has a duration and a scene" % c)
	check(DeathCG.duration("misread", 2.0) == 4.1 and DeathCG.duration("trash", 3.6) == 3.6 and DeathCG.has("window_gaze") and DeathCG.has("paper_sender") and DeathCG.has("campus_fall"), "scenes of the cause's own length (window gaze 7 s, paper sender 8 s, misread 4.1 s, fall 6 s)")
	check(not DeathCG.has("vignette") and DeathCG.seg(0.5, 0.0, 1.0) == 0.5 and DeathCG.seg(-1.0, 0.0, 1.0) == 0.0 and DeathCG.ss(0.5, 0.0, 1.0) == 0.5 and DeathCG.ss(2.0, 0.0, 1.0) == 1.0, "the easing helpers clamp")


func _test_scene_beats() -> void:
	# The beat sounds of the death, ending and opening scenes (old SFX.door / sting / vanish / smile / bigBell / crackle / engine / hum / blink / wake).
	var cg := DeathCG.new()
	var fired := [0]
	cg.snd("foley.door")  # silent without audio: no error
	cg.cue("x", 1.0, 1.5, func() -> void: fired[0] += 1)
	cg.cue("x", 2.0, 1.5, func() -> void: fired[0] += 1)
	check(fired[0] == 1, "a beat fires once, when its time comes")
	var bank: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(AudioFx.INDEX)) as Dictionary)["sfx"]
	var ids: Array = bank.keys()
	for sound_id: String in ["foley.door", "threat.sting", "foley.vanish", "threat.smileBack", "threat.smileJump", "event.bigBell", "world.crackle", "scene.engine", "scene.hum", "scene.cyberEnd", "ui.click", "ui.blink", "foley.wake"]:
		check(ids.has(sound_id), "beat sound %s is in the bank" % sound_id)
	var src := FileAccess.get_file_as_string("res://game/presentation/cinematics/death_cg.gd")
	for pair: String in ["trash:k1", "grip:grab", "twin:in", "gaze:giggle", "bell:hit", "loop:man", "laugh:big", "lamps:last"]:
		var parts := pair.split(":")
		check(src.contains('cue("%s"' % parts[1]) and src.contains("func _update_%s(" % parts[0]), "death scene %s has its beat %s" % [parts[0], parts[1]])
	cg.free()


func _test_portal_device() -> void:
	# The portal rig (model/portal.js): states base -> ready -> charge -> open -> enter.
	var dev := PortalDevice.new()
	dev.build(16)
	check(is_equal_approx(dev.ring_y, 0.935 + 0.05 + 0.06 + 0.62), "the ring centre stands above the bench top (%.3f)" % dev.ring_y)
	check(not dev._inner.visible and not (dev._parts["coil"] as Node3D).visible and (dev._sockets["coil"] as Node3D).visible, "base: sockets only, nothing inside the ring")
	dev.set_state("ready")
	check(((dev._leds["lens"] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color == Color("#ffb347") and not (dev._parts["lens"] as Node3D).visible, "ready: the socket lamps are on")
	dev.set_state("charge", 0.4)
	var closed := 0
	for r: MeshInstance3D in dev._rails:
		closed += 1 if r.visible else 0
	check((dev._parts["coil"] as Node3D).visible and not (dev._sockets["coil"] as Node3D).visible and closed == 2 and not dev._inner.visible, "charge 0.4: parts fitted, two of three rails closed, door still shut")
	dev.set_state("charge", 0.8)
	check(dev._inner.visible and dev._inner.scale.x > 0.2 and dev._inner.scale.x < 1.0, "charge 0.8: the door starts to open")
	dev.set_state("open")
	check(dev._inner.visible and is_equal_approx(dev._inner.scale.x, 1.0), "open: the whole door")
	dev.tick(0.1)
	check(dev._coil_mat.emission.r > 0.0, "the coil pulses once powered")
	dev.set_state("enter", 1.0)
	var top: StandardMaterial3D = dev._layers[2].material_override
	check(top.albedo_color.a > 0.35, "enter: the inside brightens (%.2f)" % top.albedo_color.a)
	var tb := PortalDevice.bench_spot(CampusData.layout("lab1"))
	check(tb != Vector2.ZERO, "the rig stands on the lab's first bench tile")
	dev.free()
	for prop_name: String in ["server_rack", "server_console", "speaker_box", "locker_bank_4", "window_in_150", "desk_computer", "chair_office"]:
		check(ResourceLoader.exists("res://assets/campus/props/%s.glb" % prop_name), "the cyber ending's prop %s is exported" % prop_name)
	check(ResourceLoader.exists("res://assets/campus/patrol/patrol_figure.glb"), "the patroller's own model is there for the corridor")


func _test_ending_cut() -> void:
	check(EndingCut.has("face") and EndingCut.has("international") and EndingCut.has("dismissal") and EndingCut.has("portal") and EndingCut.has("cyber") and EndingCut.has("car"), "only the ported endings have a live scene")
	check(EndingCut.needs_outdoor("face") and not EndingCut.needs_outdoor("international"), "the gate scene needs the outdoors, the stage scene does not")
	check(EndingCut.intl_stage(3.9) == 0 and EndingCut.intl_stage(4.0) == 1 and EndingCut.intl_stage(9.0) == 2 and EndingCut.intl_stage(15.0) == 3 and EndingCut.intl_edge(4.0) == 1.0 and EndingCut.intl_edge(6.0) == 0.0 and is_equal_approx(EndingCut.intl_edge(19.6), 0.5), "the four stages and the fades between them")
	check(EndingCut.intl_caption(0, "multilingual").begins_with("「Alle da?」") and EndingCut.intl_caption(0, "exam").begins_with("队尾的人回头") and EndingCut.intl_caption(3, "exam").contains("学校名字"), "the captions differ only in the first line by qualification")
	check(EndingCut.face_lamp(0.1) == Color("#d23a2e") and EndingCut.face_lamp(0.2) == Color("#e8e4d2"), "the gate's lamp is red, then white")
	check(EndingCut.face_fade(0.1) == 0.0 and EndingCut.face_fade(0.3) == 1.0 and is_equal_approx(EndingCut.face_fade(0.33), 0.5) and EndingCut.face_fade(0.6) == 0.0 and is_equal_approx(EndingCut.face_fade(0.95), 0.5), "black after the beep, clear outside, black at the end")
	check(EndingCut.dis_stage(3.1) == 0 and EndingCut.dis_stage(7.8) == 2 and EndingCut.dis_stage(12.0) == 3 and EndingCut.dis_edge(3.2) == 1.0 and EndingCut.dis_edge(10.0) == 0.0 and EndingCut.dis_caption(14.0).begins_with("登记簿") and EndingCut.dis_caption(17.0).begins_with("你回过头"), "the four stages of the dismissal, fades and captions")
	check(EndingCut.portal_state(0.2)["charge"] < 1.0 and not EndingCut.portal_state(0.2)["open"] and EndingCut.portal_state(0.5)["open"] and EndingCut.portal_state(0.5)["enter"] == 0.0 and EndingCut.portal_state(1.0)["enter"] == 1.0, "the device charges, opens, then is entered")
	var pc := EndingCut.portal_camera(0.55, Vector3.ZERO, 1.6)
	var pe := EndingCut.portal_camera(1.0, Vector3.ZERO, 1.6)
	check(pc["from"].z > EndingCut.portal_camera(0.5, Vector3.ZERO, 1.6)["from"].z - 0.001 and pe["from"].z < 0.2 and is_equal_approx(pe["from"].y, 1.6), "the camera steps back half a pace, then pushes through the ring")
	check(EndingCut.cy_stage(3.1) == 0 and EndingCut.cy_stage(3.2) == 1 and EndingCut.cy_stage(7.2) == 2 and EndingCut.cy_stage(11.2) == 3 and EndingCut.cy_log_lines(0.2) == 0 and EndingCut.cy_log_lines(2.8) == 6, "the four stages and the console log lines")
	check(EndingCut.cy_flicker_on(3.25) and not EndingCut.cy_flicker_on(3.2 + 0.11) and EndingCut.cy_flicker_on(EndingCut.cy_flicker_end() + 1.0) and is_equal_approx(EndingCut.cy_flicker_end(), 3.2 + 1.97), "the tube lights flicker two short one long, then settle")
	check(EndingCut.cy_archive_steps(7.0) == 0 and EndingCut.cy_archive_steps(7.4) == 1 and EndingCut.cy_archive_steps(10.3) == 9 and EndingCut.cy_fade(3.2) == 1.0 and EndingCut.cy_fade(5.0) == 0.0 and EndingCut.cy_fade(16.0) == 1.0, "the archive fills line by line, fades between stages")
	check(EndingCut.car_lights(0.03) == 0.0 and EndingCut.car_lights(0.5) == 1.0 and not EndingCut.car_thing_visible(0.03) and not EndingCut.car_thing_visible(0.3) and EndingCut.car_fade(0.1) == 0.0 and EndingCut.car_fade(0.33) > 0.4 and EndingCut.car_fade(0.5) == 0.0 and is_equal_approx(EndingCut.car_fade(0.95), 0.5), "the garage lights flicker, something shows in the flicker only, black between garage and gate")
	var g := EndingCut.gate_scene(CampusData.campus(), "w")
	check(is_equal_approx(g.x, 200.0 * 2.0 / 9.0) and is_equal_approx(g.z, 624.0 * 2.0 / 9.0), "the gate is placed from the campus plan")


func _test_opening() -> void:
	check(OpeningCut.duration(false) == 26.0 and OpeningCut.duration(true) == 11.0 and OpeningCut.story_time(0.0, true) == OpeningCut.SHORT_FROM and OpeningCut.story_time(1.0, true) == 1.0 and OpeningCut.story_time(0.5, false) == 0.5,
		"the opening is 26 s, the short version 11 s starting at the fourth part")
	check(OpeningCut.line_at(0.1).begins_with("你是这学期转来的") and OpeningCut.line_at(0.22) == "" and OpeningCut.line_at(0.95).begins_with("下课铃没有响"), "the captions follow the storyboard")
	check(OpeningCut.mate_pose("still", 0.0, 0.5, 0.0, 0.2) == Vector2.ZERO and OpeningCut.mate_pose("write", 0.08, 0.5, 0.0, 0.8) == Vector2.ZERO and OpeningCut.mate_pose("write", 0.08, 0.5, 0.0, 0.2).x > 0.0 and is_equal_approx(OpeningCut.mate_pose("turn", 0.08, 0.5, 1.0, 0.2).x, 0.02), "mates write, turn a page or stay, and sit up straight again after 70%")
	check(OpeningCut.ease_k(-1.0) == 0.0 and OpeningCut.ease_k(2.0) == 1.0 and is_equal_approx(OpeningCut.ease_k(0.5), 0.5), "the easing is clamped")


func _test_hands() -> void:
	check(HandsView.uses(true, true, true, true) == {"L": "brolly", "R": "torch"} and HandsView.uses(false, false, true, true) == {"L": "phone", "R": ""}
		and HandsView.uses(false, true, true, true) == {"L": "brolly", "R": "phone"} and HandsView.uses(true, true, true, false) == {"L": "", "R": ""},
		"the umbrella takes the left, the torch the right, the phone the free hand; nothing when hidden")
	var hv := HandsView.new()
	root.add_child(hv)
	hv.update(0.1, true, false, true, true, false, false)
	check(hv.held("R") == "torch" and hv.held("L") == "phone" and hv.get_child_count() == 2, "the hands are built from the exported models")
	hv.update(0.1, false, false, false, true, false, false)
	check(hv.held("R") == "" and hv.held("L") == "", "putting things away empties the hands")
	hv.update(0.1, true, false, false, true, false, false)
	hv.light(2.0, Color("#ffd9a0"), true)
	check(hv._fill != null and hv._fill.light_cull_mask == CampusLighting.HAND_LAYER and is_equal_approx(hv._fill.light_energy, HandsView.fill_energy(2.0, true)) and hv._fill.light_energy > HandsView.fill_energy(2.0, false), "the hands have their own near light, with the torch lit it is stronger")
	check(CampusLighting.WORLD_LIGHT_MASK & CampusLighting.HAND_LAYER == 0 and hv._lens.size() == 2 and hv._lens[0].albedo_color == Color("#fff2c8"), "the world's lights skip the hand layer; the torch lens shines warm")
	hv.light(2.0, Color.WHITE, false)
	check(hv._lens[0].albedo_color == Color("#30343a") and hv._lens[1].albedo_color == Color("#3a3e44"), "an unlit torch has a dark lens and bulb")
	hv.queue_free()


func _test_dev_tools() -> void:
	var pt := Playtest.new(_test_path.get_base_dir() + "/playtest-test.json")
	pt.event("无效", "没开始不记")
	check(pt.export().is_empty(), "nothing is recorded before it starts")
	pt.start({"vol": 70}, Vector2i(1280, 720))
	pt.frame(0.016, "play")
	pt.frame(0.2, "play")
	pt.frame(1.0, "menu")
	pt.event("事实", "lesson", {"day": 2})
	check(pt.note("  回头看了一眼  ", {}) and not pt.note("   ", {}), "an observer's note is kept, a blank one is not")
	var ex := pt.export()
	check(is_equal_approx(float(ex["seconds"]["play"]), 0.216) and is_equal_approx(float(ex["seconds"]["menu"]), 1.0) and ex["frameIntervals"]["under25ms"] == 1 and ex["frameIntervals"]["over100ms"] == 1,
		"seconds by mode and the frame bins (play only)")
	for i in 520:
		pt.event("x", str(i))
	check((pt.data["events"] as Array).size() == Playtest.MAX_EVENTS and int(pt.data["discardedEvents"]) > 0, "at most 500 events, the oldest dropped")
	pt.stop()
	check(FileAccess.file_exists(pt.path) and not pt.recording, "stopping writes the log")
	var idx: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/index.json"))
	var dp := DebugPanel.new(idx as Dictionary)
	var total := 0
	for c: Variant in dp._cats:
		total += dp.ids_of(String(c)).size()
	check(total == dp.sfx().size() and total > 100, "the sound audition lists the whole bank by category (%d)" % total)
	dp.free()
