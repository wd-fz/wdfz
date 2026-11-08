extends "res://tests/support/test_suite.gd"


func _test_broadcast_rules() -> void:
	var rooms := CampusData.rooms()
	var radio := BroadcastModule.new(rooms, CampusData.patrol_nav())
	radio.reset()
	radio.set_seed(42)
	check(BroadcastModule.hash01(42, "false-notice") == BroadcastModule.hash01(42, "false-notice") and BroadcastModule.hash01(42, "a") != BroadcastModule.hash01(42, "b"), "the route hash is stable per seed")
	check(BroadcastModule.in_window(2, 1040.0) and not BroadcastModule.in_window(1, 1100.0) and not BroadcastModule.in_window(2, 1339.0 + 1.0), "the reading window: day 2 on, 17:20 to lights out")
	var bag: Array = []
	var station := _spot("admin2", BroadcastModule.STATION)
	# The pieces.
	radio.set_context(_bctx("admin5", _spot("admin5", [6, 2]), bag))
	check(radio.use_here() and bag.has("archivekey"), "the archive key is in the fifth-floor office")
	radio.set_context(_bctx("gear1", _spot("gear1", [3, 1]), bag))
	check(radio.use_here() and bag.has("broadcastfuse") and bag.has("snack") and bool(radio.b["boxSnack"]), "the spare fuse and a snack are in the gear room")
	radio.set_context(_bctx("guard1", _spot("guard1", [2, 4]), bag, {"night": true}))
	check(radio.use_here() and bag.has("broadcastkey"), "at night the guard's register gives the station key")
	radio.set_context(_bctx("admin2", station, bag))
	check(radio.use_here() and radio.take_events().any(func(e: Dictionary) -> bool: return e["kind"] == "choice"), "the station opens its menu")
	radio.choose(0)
	check(bool(radio.b["book"]), "the log book is read")
	radio.menu()
	radio.take_events()
	radio.choose(1)
	check(bool(radio.b["fuse"]) and not bag.has("broadcastfuse"), "the fuse is installed")
	# Page 1: the archive cabinet, opened with the key, a held search, then the page.
	radio.set_context(_bctx("admin1", _spot("admin1", [46, 2]), bag))
	radio.use_here()
	var ev := radio.take_events()
	check(not bag.has("archivekey") and bool(radio.b["archiveOpen"]) and _of_kind(ev, "job")[0]["seconds"] == 1.4, "the key opens the cabinet and the page takes 1.4 s")
	radio.job_done(0)
	var page: Dictionary = _of_kind(radio.take_events(), "choice")[0]
	check(String(page["text"]).contains("蓝黑墨水 · 第二天"), "the page shows its ink and date")
	radio.choose(0)
	check(bag.has("notice1"), "the first page is taken")
	# Page 2: the piano lock.
	radio.set_context(_bctx("lab5", _spot("lab5", [5, 1]), bag, {"clock": 900.0}))
	radio.use_here()
	radio.take_events()
	radio.choose(1)
	check(int(radio.b["pianoFails"]) == 1 and (radio.b["piano"] as Array).is_empty(), "a wrong note resets the tune")
	for pick: int in [0, 2, 1, 3]:
		radio.take_events()
		radio.choose(pick)
	var piano_ev := radio.take_events()
	check(_of_kind(piano_ev, "choice").size() >= 1 and String(_of_kind(piano_ev, "choice").back()["text"]).contains("琴凳里夹着通知稿"), "1 · 3 · 2 · 5 opens the piano bench")
	radio.choose(0)
	check(bag.has("notice2"), "the second page is taken")
	# Page 3 at night, page 4 with a coin and the back to the stairs.
	radio.set_context(_bctx("guard1", _spot("guard1", [2, 4]), bag, {"night": false}))
	check(not radio.use_here(), "by day the register is behind the night window")
	radio.set_context(_bctx("guard1", _spot("guard1", [2, 4]), bag, {"night": true}))
	radio.use_here()
	radio.take_events()
	radio.job_done(2)
	radio.take_events()
	radio.choose(0)
	check(bag.has("notice3"), "the third page is taken at night")
	var roof := _spot("teach6", [20, 2])
	radio.set_context(_bctx("teach6", roof, bag, {"ang": 0.0}))
	radio.use_here()
	check(_notices(radio.take_events()).has("喇叭箱的螺丝槽很宽，需要一枚硬币。"), "the speaker box needs a coin")
	bag.append("coin")
	var stairs := Vector2(float(rooms["teach6"]["ox"]) + 12.5 * float(rooms["teach6"]["tw"]), float(rooms["teach6"]["oy"]) + 16.5 * float(rooms["teach6"]["th"]))
	var toward := atan2(stairs.y - roof.y, stairs.x - roof.x)
	radio.set_context(_bctx("teach6", roof, bag, {"ang": toward}))
	radio.use_here()
	check(_notices(radio.take_events()).has("喇叭箱背面的字：「拧螺丝时，背对楼梯口。」"), "facing the stairs is refused")
	radio.set_context(_bctx("teach6", roof, bag, {"ang": toward + PI}))
	radio.use_here()
	check(_of_kind(radio.take_events(), "job")[0]["seconds"] == 2.0, "with the back to the stairs it takes 2 s")
	radio.job_done(3)
	radio.take_events()
	radio.choose(0)
	check(bag.has("notice4") and radio.assembled(), "all four pages")
	# Reading.
	radio.set_context(_bctx("admin2", station, bag, {"tsec": 1000.0}))
	check(not radio.hold(true) and radio.reason() == "记录本：第二天起，第八节下课后、熄灯前播出。", "outside the window the microphone stays off")
	radio.set_context(_bctx("admin2", station, bag))
	radio.select("notice2")
	check(radio.hold(true), "in the window reading starts")
	radio.tick(0.5)
	check(not radio.held and _notices(radio.take_events()).has("页码不对，得从当前这一段开始。"), "the wrong page stops the reading")
	for n in 4:
		radio.select("notice%d" % (n + 1))
		radio.hold(true)
		for _i in 16:
			radio.tick(1.0)
	check(radio.b["phase"] == "bell" and int(radio.b["completed"]) == 4 and int(radio.b["attemptDay"]) == 2, "four pages of 15 s ring the 60-second bell")
	var ev2 := radio.take_events()
	check(not _of_kind(ev2, "bell_start").is_empty(), "the bell starts")
	radio.set_context(_bctx("out", Vector2(1028, 190), bag))
	var c0 := radio.crowd()
	for _i in 20:
		radio.tick(1.0)
	var c1 := radio.crowd()
	check(not c0.is_empty() and Vector2(float(c1["x"]), float(c1["y"])).distance_to(Vector2(1028, 205)) < Vector2(float(c0["x"]), float(c0["y"])).distance_to(Vector2(1028, 205)), "the crowd walks to the north gate")
	radio.set_context(_bctx("out", Vector2(float(c1["x"]), float(c1["y"])), bag))
	check(radio.cover(), "next to the crowd the player is covered")
	for _i in 30:
		radio.tick(1.0)
	var c2 := radio.crowd()
	radio.set_context(_bctx("out", Vector2(float(c2["x"]), float(c2["y"])), bag))
	radio.tick(0.1)
	check(_of_kind(radio.take_events(), "ending").size() == 1, "walking out with the crowd is 《放学》")
	# The red page and the end of the bell.
	var red := BroadcastModule.new(rooms, CampusData.patrol_nav())
	red.reset()
	red.b["book"] = true
	red.b["fuse"] = true
	var kit: Array = ["notice1", "notice2", "notice3", "notice4", "notice_fake"]
	red.set_context(_bctx("admin2", station, kit))
	red.select("notice_fake")
	red.hold(true)
	red.tick(1.0)
	red.tick(1.1)
	check(_of_kind(red.take_events(), "kill")[0]["source"] == "misread", "reading the red page is the misread death")
	red.b["phase"] = "bell"
	red.b["bell"] = 0.5
	red.b["completed"] = 4
	red.tick(1.0)
	check(red.b["phase"] == "collect" and int(red.b["completed"]) == 0, "when the bell stops the pages wait for tomorrow")
	# Calls on the speakers.
	var calls := BroadcastModule.new(rooms, CampusData.patrol_nav())
	calls.reset()
	calls.set_context(_bctx("teach1", Vector2.ZERO, []))
	check(calls.announce(false, 0) and calls.b["current"]["room"] == "lab4", "a false call names a room")
	calls.set_context(_bctx("admin2", station, []))
	check(calls.verify() and _of_kind(calls.take_events(), "fact")[0]["real"] == false, "the log book shows it was false")
	calls.set_context(_bctx("lab4", Vector2.ZERO, []))
	calls.tick(5.0)
	calls.tick(5.0)
	var drained := calls.take_events()
	check(_notices(drained).has("喇叭里开始念你的名字。啸叫越来越尖——先离开这间屋子。") and not _of_kind(drained, "san").is_empty(), "the false call's room drains SAN after 8 s")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(radio.capture()))
	var back := BroadcastModule.new(rooms, CampusData.patrol_nav())
	back.reset()
	check(back.validate(saved).is_empty(), "the broadcast state survives JSON")
	back.restore(saved)
	check(bool(back.b["book"]) and bool(back.b["fuse"]) and back.seed_value == 42, "and restores")


## The commands that solve the terminal for this puzzle (the intended reading of the files).


func _test_phone_rules() -> void:
	# Energy.
	var d := PhoneEnergy.fresh()
	d["initialized"] = true
	check(absf(PhoneEnergy.rate(d, {"held": true}) + 1.0 / 6.0) < 1e-9 and absf(PhoneEnergy.rate(d, {"held": true, "classroom": true}) - 1.0 / 3.0) < 1e-9, "the phone drains 1/6 % a second and charges in the classroom")
	d["wireless"] = {"status": "running", "elapsed": 0.0, "target": 200.0}
	var ev := PhoneEnergy.advance(d, 31.0, {"held": true})
	check(ev.count("wirelessSignal") == 2 and absf(float(d["battery"]) - (100.0 - 31.0 / 3.0)) < 1e-6, "cracking drains twice as fast and signals every 15 s")
	ev = PhoneEnergy.advance(d, 200.0, {"held": true, "classroom": true})
	check(ev.has("connected") and bool(d["network"]) and d["download"]["status"] == "running", "a cracked network starts the container download")
	ev = PhoneEnergy.advance(d, 60.0, {"held": true, "classroom": true})
	check(ev.has("downloaded") and d["download"]["status"] == "complete", "the container takes 60 s")
	var flat := PhoneEnergy.fresh()
	flat["initialized"] = true
	flat["battery"] = 1.0
	ev = PhoneEnergy.advance(flat, 10.0, {"held": true})
	check(ev.has("off") and not bool(flat["powered"]) and ev.has("low5") and ev.has("low20"), "an empty battery switches the phone off with the warnings")
	ev = PhoneEnergy.advance(flat, 20.0, {"held": true, "classroom": true})
	check(ev.has("on") and bool(flat["powered"]), "charging back to 5 % switches it on")
	# The terminal.
	var t := CampusTerminal.fresh("abc", 1)
	check(CampusTerminal.make("abc", 1)["answer"] == CampusTerminal.make("abc", 1)["answer"] and CampusTerminal.make("abc", 1)["answer"] != CampusTerminal.make("abc", 2)["answer"], "the puzzle depends on the seed and the attempt")
	check(CampusTerminal.run(t, "cat /school/site.txt")["text"].begins_with("试点区域=Z"), "cat reads the school files")
	check(CampusTerminal.run(t, "cat /school/assets.tsv | grep controller | head -n 2")["text"].split("\n").size() == 2, "pipes work")
	check(CampusTerminal.run(t, "rm -rf /")["error"] and CampusTerminal.run(t, "cat x > y")["error"], "unknown commands and redirection are refused")
	check(CampusTerminal.run(t, "edit /school/x \"a\"")["text"].contains("只允许写 /work/"), "only /work is writable")
	check(CampusTerminal.run(t, "campusctl shutdown --confirm")["text"].contains("先通过 T1—T3"), "no shutdown before the checks")
	check(CampusTerminal.run(t, "campusctl select ctl-decoy /school/assets.tsv")["error"], "the decoy controller is refused")
	var out: Dictionary = {}
	for line: String in _solve_lines(t):
		out = CampusTerminal.run(t, line)
	check(out.get("request") == "shutdown" and t["validated"] != null, "reading the files right solves T1–T4")
	# The phone module.
	var net := PhoneModule.new()
	net.reset()
	net.set_seed(5)
	var held := {"held": true, "scene": "teach1", "x": 0.0, "y": 0.0, "dead": false, "classroom": false}
	net.set_context(held)
	net.phone_menu()
	check(net.take_events()[0]["labels"][0] == "无线接入 · 开始破解", "the phone shows its apps")
	net.phone_choose(0)
	check(net.device["wireless"]["status"] == "running" and float(net.device["wireless"]["target"]) >= 180.0 and float(net.device["wireless"]["target"]) <= 600.0, "cracking takes 180–600 s")
	net.tick(15.0)
	check(net.take_events().any(func(e: Dictionary) -> bool: return e["kind"] == "reveal"), "every 15 s it gives the position away")
	net.set_context({"held": true, "scene": "lab3", "x": 500.0, "y": 500.0, "dead": false})
	net.computer_choose(2, 500.0, 500.0)
	check(not net.terminal_open and net.take_events().any(func(e: Dictionary) -> bool: return e["kind"] == "toast" and String(e["text"]).begins_with("需要手机有电")), "the terminal needs the network and the container")
	net.device["network"] = true
	net.device["wireless"]["status"] = "complete"
	net.device["download"] = {"status": "complete", "elapsed": 60.0, "target": 60.0}
	check(net.open_terminal(500.0, 500.0) and net.connected_computer(), "with them the computer opens the terminal")
	for line: String in _solve_lines(net.puzzle):
		net.run_line(line)
	check(net.termination["status"] == "accepted" and float(net.termination["remaining"]) == 600.0, "the shutdown is accepted: survive ten minutes")
	net.set_context({"held": true, "scene": "lab3", "x": 540.0, "y": 500.0, "dead": false})
	net.tick(1.0)
	check(not net.connected_computer() and not net.terminal_open, "walking away from the computer disconnects it")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(net.capture()))
	var back := PhoneModule.new()
	back.reset()
	check(back.validate(saved).is_empty(), "the phone state survives JSON")
	back.restore(saved)
	check(back.termination["status"] == "accepted" and absf(float(back.termination["remaining"]) - 599.0) < 0.01, "the accepted shutdown keeps its countdown")
	saved["termination"]["requestId"] = "forged"
	check(not back.validate(saved).is_empty(), "a forged request is refused")
	net.tick(600.0)
	check(net.take_events().any(func(e: Dictionary) -> bool: return e["kind"] == "ending" and e["id"] == "cyber"), "ten minutes alive is 《网安仙人》")
	var dream := PhoneModule.new()
	dream.reset()
	dream.set_seed(9)
	var first: Dictionary = CampusTerminal.make(dream.run_seed, 1)["answer"]
	dream.dream()
	check(dream.attempt_id == 2 and CampusTerminal.make(dream.run_seed, dream.attempt_id)["answer"] != first and dream.termination["status"] == "idle", "a dream wake is a new attempt with a new puzzle")


func _test_plane_rules() -> void:
	var g := PlaneGame.new()
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 7
	var roll := func() -> float: return rnd.randf()
	check(g.st == "ready" and g.flap() and g.st == "fly" and g.vy == PlaneGame.FLAP, "the first tap starts the round with an upward kick")
	var tick := g.tick(0.1, 1.0, roll)
	check(tick.is_empty() and g.y > PlaneGame.H * 0.45 - 30.0 and g.pipes.size() == 1 and float(g.pipes[0]["x"]) < PlaneGame.W + 20.0, "gravity pulls, a shelf comes in from the right")
	# Fall: the round ends on the floor with no score and no gain.
	var ended: Array = []
	for _i in 100:
		ended.append_array(g.tick(0.05, 1.0, roll))
	check(g.st == "over" and ended.size() == 1 and ended[0]["gain"] == 0.0 and g.msg == "", "falling ends the round; no score gives no rest")
	check(g.flap() == true and g.st == "ready" and g.score == 0, "a tap after the end restarts")
	# A hand-made scored round: pass shelves, end by the floor, and the SAN gain is scaled by the pressure.
	var h := PlaneGame.new()
	h.st = "fly"
	h.score = 3
	h.y = PlaneGame.H - 9.0
	h.vy = 200.0
	var scored := h.tick(0.1, 0.5, roll)
	check(scored.size() == 1 and absf(float(scored[0]["gain"]) - 1.5) < 0.001 and h.cool == PlaneGame.COOL and h.msg == "手指放松下来，远处声音又清楚了", "a scored round gives 1 SAN a point scaled by the rest factor, then the phone is hot for 45 s")
	var hot := h
	hot.reset()
	hot.st = "fly"
	hot.score = 5
	hot.y = PlaneGame.H - 9.0
	hot.vy = 200.0
	var none := hot.tick(0.1, 1.0, roll)
	check(none.size() == 1 and none[0]["gain"] == 0.0 and hot.msg == "手机发烫了，静不下心", "a hot phone gives nothing")
	var cap := PlaneGame.new()
	cap.st = "fly"
	cap.score = 20
	cap.y = PlaneGame.H - 9.0
	cap.vy = 200.0
	check(cap.tick(0.1, 1.0, roll)[0]["gain"] == 6.0, "at most 6 points of rest")
	cap.tick(40.0, 1.0, roll)
	check(cap.cool > 0.0 and cap.cool < PlaneGame.COOL, "the heat cools down with time")
	# Shelf pass counts a point and a collision ends the round.
	var s := PlaneGame.new()
	s.st = "fly"
	s.y = 150.0
	s.vy = 0.0
	s.pipes = [{"x": 20.0, "gy": 200.0, "pass": false}]
	s.tick(0.01, 1.0, roll)
	check(s.score == 0 and s.st == "over", "hitting a shelf ends the round")
	var p := PlaneGame.new()
	p.st = "fly"
	p.y = 150.0
	p.pipes = [{"x": 10.0, "gy": 100.0, "pass": false}]
	p.tick(0.01, 1.0, roll)
	check(p.score == 1 and p.st == "fly", "passing a shelf scores a point")
	check(PhoneEnergy.next_signal_in({"elapsed": 14.0}) > 0.99 and PhoneEnergy.next_signal_in({"elapsed": 15.0}) > 14.99, "the next exposure of the cracking comes every 15 run-seconds")


func _test_camera_rules() -> void:
	check(CameraModule.PHOTO.size() == 28 and CameraModule.PHOTO["rain"]["cap"].begins_with("雨幕后面站着一个没打伞的人") and CameraModule.PHOTO["cola"].get("secret", false), "the photo table is the Web version's: 26 anomalies, the window and the lift crowd")
	var cam := CameraModule.new()
	cam.reset()
	cam.set_context({"an": "", "gaze": false, "crowd": false, "day": 2, "tsec": 700.0, "place": "教学楼 1F", "clock": true})
	var calm := cam.plan()
	check(calm["an"] == "" and calm["cap"] == "照片里什么也没有。" and calm["kind"] == "" and calm["stamp"] == "%s  D2" % SchoolClock.fmt_clock(700.0), "with nothing happening the photo shows nothing extra")
	cam.set_context({"an": "rain", "gaze": false, "crowd": false, "day": 2, "tsec": 700.0, "place": "操场", "clock": false})
	var rain := cam.plan()
	check(rain["an"] == "rain" and rain["kind"] == "figure" and String(rain["cap"]).begins_with("照片里，雨幕后面") and rain["stamp"] == "--:--  D2" and rain["flash"], "a running anomaly adds its one extra thing; without a watch the stamp has no time")
	check(cam.plan()["seed"] == rain["seed"], "the same moment gives the same photo")
	cam.set_context({"an": "rain", "gaze": true, "crowd": false, "day": 2, "tsec": 700.0, "place": "x", "clock": false})
	check(cam.subject() == "window_gaze" and cam.plan()["kind"] == "eyes", "the window's eyes come before an anomaly")
	cam.set_context({"an": "rain", "gaze": true, "crowd": true, "day": 2, "tsec": 700.0, "place": "x", "clock": false})
	check(cam.subject() == "crowd", "the lift crowd comes first")
	cam.set_context({"an": "nothing", "gaze": false, "crowd": false, "day": 2, "tsec": 700.0, "place": "x", "clock": false})
	check(cam.subject() == "", "an anomaly without a photo adds nothing")
	# Album: newest first, at most six, records for public anomalies only.
	cam.set_context({"an": "rain", "gaze": false, "crowd": false, "day": 3, "tsec": 710.0, "place": "操场", "clock": true})
	var p := cam.plan()
	cam.add_photo(p, "AAAA", true)
	var ev := cam.take_events()
	check(ev[0]["kind"] == "say" and String(ev[0]["text"]).contains("闪光一亮") and ev[1]["kind"] == "record" and ev[1]["id"] == "photo_rain" and String(ev[1]["text"]).begins_with("手机里的照片（操场）"), "a photo says so, notes the clue and the flash drawing the patroller over")
	cam.set_context({"an": "cola", "gaze": false, "crowd": false, "day": 3, "tsec": 720.0, "place": "天台", "clock": true})
	cam.add_photo(cam.plan(), "BBBB", false)
	check(_of_kind(cam.take_events(), "record").is_empty(), "an internal anomaly's photo is not written into the notes")
	for i in 8:
		cam.add_photo(cam.plan(), "C%d" % i, false)
	check(cam.photos.size() == 6 and cam.photos[0]["img"] == "C7", "the album keeps the last six, newest first")
	var on_text := cam.copy_text()
	cam.toggle_flash()
	check(on_text.contains("闪光开着") and cam.copy_text().contains("闪光关着") and cam.copy_text().contains("6 张"), "the page text follows the flash and the album")
	var back := CameraModule.new()
	back.restore(cam.capture())
	check(back.photos == cam.photos and back.flash == cam.flash and back.validate(cam.capture()).is_empty() and not back.validate({"photos": [{"cap": 1}], "flash": true}).is_empty(), "the album saves and loads; a bad one is rejected")


func _test_snake_rules() -> void:
	var g := SnakeGame.new()
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 3
	var roll := func() -> float: return rnd.randf()
	g.start(roll)
	check(g.on and g.body == [Vector2i(8, 8)] and g.dir == Vector2i(1, 0) and g.cd == SnakeGame.COUNTDOWN, "a game starts with a one-segment snake in the middle, facing right, after a 3 s countdown")
	check(g.tick(1.0, Vector2i.ZERO, roll) and g.body.size() == 1 and g.body[0] == Vector2i(8, 8), "during the countdown nothing moves")
	g.tick(2.5, Vector2i.ZERO, roll)
	check(g.cd <= 0.0 and g.body[0] == Vector2i(8, 8), "(the countdown is over)")
	check(not g.tick(0.1, Vector2i.ZERO, roll) and g.tick(0.05, Vector2i.ZERO, roll) and g.body[0] == Vector2i(9, 8), "a step every 0.14 s")
	g.food = Vector2i(10, 8)
	g.tick(0.15, Vector2i.ZERO, roll)
	check(g.score == 1 and g.body.size() == 2 and g.food != Vector2i(10, 8), "eating grows the snake and scores a point")
	g.tick(0.15, Vector2i(-1, 0), roll)
	check(g.dir == Vector2i(1, 0), "with a body you cannot turn straight back")
	g.turn(Vector2i(0, 1))
	g.tick(0.15, Vector2i.ZERO, roll)
	check(g.dir == Vector2i(0, 1) and g.want == null, "a swipe is used on the next step")
	g.turn(Vector2i(-1, 0))
	g.tick(0.15, Vector2i(1, 0), roll)
	check(g.dir == Vector2i(1, 0) and g.want == Vector2i(-1, 0), "a held key beats a swipe; the swipe waits")
	var wall := SnakeGame.new()
	wall.start(roll)
	wall.cd = 0.0
	wall.body = [Vector2i(15, 8)]
	wall.tick(0.2, Vector2i.ZERO, roll)
	check(wall.dead and not wall.tick(0.2, Vector2i.ZERO, roll), "the wall ends the game")
	var own := SnakeGame.new()
	own.start(roll)
	own.cd = 0.0
	own.body = [Vector2i(5, 5), Vector2i(6, 5), Vector2i(6, 4), Vector2i(5, 4), Vector2i(4, 4)]
	own.dir = Vector2i(0, -1)
	own.tick(0.2, Vector2i.ZERO, roll)
	check(own.dead, "hitting yourself ends the game")
	var scorer := SnakeGame.new()
	check(scorer.gain(1.0) == 0.0, "no score, no rest")
	scorer.score = 3
	check(scorer.gain(1.0) == 12.0 and absf(scorer.gain(0.5) - 6.0) < 0.001, "rest is 6 + 2 a point, scaled by the pressure")
	scorer.score = 30
	check(scorer.gain(1.0) == 20.0, "at most 20")
	check(AchievementsModule.LIST.has("n.snake"), "the snake achievement exists")
	var ach := AchievementsModule.new(25)
	ach.reset()
	check(ach.fact({"kind": "snake", "score": 6}).is_empty() and ach.fact({"kind": "snake", "score": 7}).has("n.snake"), "seven bites unlock 一口一口")
