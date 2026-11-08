extends "res://tests/support/test_suite.gd"


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
	check(ach.points() > 0 and not ach.entries().any(func(r: Dictionary) -> bool: return String(r["id"]).begins_with("h.")), "undiscovered hidden achievements do not appear in the player list")
	var rows := ach.entries()
	check(rows.size() == AchievementsModule.LIST.keys().filter(func(k: String) -> bool: return not k.begins_with("h.")).size() and rows.filter(func(r: Dictionary) -> bool: return not r["unlocked"] and r["memo"] != "").is_empty(), "locked public entries show no memory line")


func _test_speedrun_rules() -> void:
	check(Speedrun.fmt(3723456) == "01:02:03.45", "times read hh:mm:ss.cc")
	var sr := Speedrun.new()
	var rec := {}
	sr.arm("hard")
	check(sr.active() and sr.elapsed() == 0, "armed, not yet running")
	check(sr.fail("abandoned", rec).is_empty() and sr.run.is_empty() and rec.is_empty(), "leaving before the first move records nothing")
	sr.arm("easy")
	sr.start()
	sr.run["p0"] = Time.get_ticks_msec() - 61000
	sr.run["w0"] = Time.get_unix_time_from_system() - 61.0
	var res := sr.finish("face", rec)
	check(res["pb"] and res["rec"]["status"] == "finished" and int(res["rec"]["ms"]) >= 61000 and rec["best"].has(Speedrun.key("easy", "face")), "a finished route is a personal best")
	sr.arm("easy")
	sr.start()
	sr.run["p0"] = Time.get_ticks_msec() - 90000
	sr.run["w0"] = Time.get_unix_time_from_system() - 90.0
	check(not sr.finish("face", rec)["pb"] and (rec["recent"] as Array).size() == 2, "a slower run is recorded but is no best")
	sr.arm("easy")
	sr.start()
	check(sr.finish("secret", rec).is_empty(), "only the public routes stop the clock")
	check(Speedrun.rows(rec).size() == 12 + 2 and Speedrun.rows(rec)[4]["on"], "the records list every route per difficulty and the recent runs")
	var ach := AchievementsModule.new(25)
	ach.reset()
	check(ach.fact({"kind": "speedrun", "status": "finished", "route": "face", "ms": 600000}).has("p.fast") and ach.unlocked.has("e.speedrun"), "a 10-minute finish: 计时 and 赶在铃响前")


func _test_run_new_rules() -> void:
	var ach := AchievementsModule.new(25)
	ach.reset()
	check(ach.run_new.is_empty() and ach.run_new_labels().is_empty(), "a fresh run has no new achievements")
	ach.fact({"kind": "snake", "score": 7})
	ach.fact({"kind": "day", "day": 2})
	check(ach.run_new == ["n.snake", "n.day2"] and ach.run_new_labels() == PackedStringArray(["普通 · 一口一口", "普通 · 熬过第一天"]), "what the run unlocks is listed in order with its tier")
	ach.fact({"kind": "snake", "score": 9})
	check(ach.run_new.size() == 2, "an achievement is listed once")
	var back := AchievementsModule.new(25)
	back.restore(ach.capture())
	check(back.run_new == ach.run_new, "the list is saved with the run")
	var prior := AchievementsModule.new(25)
	prior.reset()
	prior.load_profile({"unlocked": {"n.snake": true}, "sets": {}})
	prior.fact({"kind": "snake", "score": 8})
	check(prior.run_new.is_empty(), "something unlocked in an earlier run is not new")
	var other := AchievementsModule.new(25)
	other.reset()
	other.run_new.append("n.snake")
	other.reset()
	check(other.run_new.is_empty(), "a new run starts empty")


func _test_score_rules() -> void:
	# Time score: 400 × par/sec, clamped to 0.25–1.5.
	check(ScoreRules.time_score(1080.0, 1080.0) == 400 and ScoreRules.time_score(720.0, 1080.0) == 600 and ScoreRules.time_score(100.0, 1080.0) == 600 and ScoreRules.time_score(10800.0, 1080.0) == 100 and ScoreRules.time_score(0.0, 1080.0) == 0, "the time score is 400 × par / time, between 100 and 600")
	# Nine grades by grade score.
	check(ScoreRules.grade_of(0)["g"] == "F" and ScoreRules.grade_of(399)["g"] == "F" and ScoreRules.grade_of(400)["g"] == "E" and ScoreRules.grade_of(700)["g"] == "C" and ScoreRules.grade_of(1000)["g"] == "A"
		and ScoreRules.grade_of(1300)["g"] == "SS" and ScoreRules.grade_of(1450)["g"] == "SSS" and ScoreRules.grade_of(9999)["g"] == "SSS", "nine grades at 0, 400, 550, 700, 850, 1000, 1150, 1300, 1450")
	check(ScoreRules.band("D") == "low" and ScoreRules.band("B") == "mid" and ScoreRules.band("S") == "high" and ScoreRules.band("SSS") == "top" and ScoreRules.san_band(80) == "清醒" and ScoreRules.san_band(45) == "动摇" and ScoreRules.san_band(10) == "濒临", "the sound band of a grade and the SAN state")
	# SSS needs the nightmare difficulty, no rescue, no waking.
	var hard := {"diff": "hard", "saved": false, "wakes": 0}
	check(ScoreRules.gate(hard) and not ScoreRules.gate({"diff": "easy", "saved": false, "wakes": 0}) and not ScoreRules.gate({"diff": "hard", "saved": true, "wakes": 0}) and not ScoreRules.gate({"diff": "hard", "saved": false, "wakes": 1}), "SSS needs hard, no rescue, no waking")
	var sss := ScoreRules.rate(1100.0, 1080.0, 1080.0, hard)
	check(sss["grade"] == "SSS" and sss["gradeScore"] == 1500 and not sss["capped"], "enough grade score with the gate is SSS")
	var capped := ScoreRules.rate(1100.0, 1080.0, 1080.0, {"diff": "easy", "saved": false, "wakes": 0})
	check(capped["grade"] == "SS" and capped["capped"] and not capped["gate"], "without the gate an SSS score gives SS and says it was capped")
	# Exploration: places 50 %, sketch 30 %, clues 20 %.
	var ex := ScoreRules.explore({"places": 5, "places_total": 10, "cells": 50, "cells_total": 100, "clues": 10, "clues_total": 20})
	check(ex["pct"] == 50 and ex["place"] == 50 and ex["sketch"] == 50 and ex["clue"] == 50 and ScoreRules.explore({"places": 0, "places_total": 0, "cells": 0, "cells_total": 0, "clues": 0, "clues_total": 21})["pct"] == 0, "exploration is the weighted share of places, sketch and clues")
	# Total: the ending, achievements, SAN and exploration, the hard multiplier, and merged entries.
	var ledger: Array = [{"cat": "应对 · 选择", "text": "课桌任务答对", "pts": 5}, {"cat": "应对 · 选择", "text": "课桌任务答对", "pts": 5}, {"cat": "校规与巡察", "text": "甩掉了巡察者", "pts": 10}]
	var easy := ScoreRules.total(ledger, {"ending": true, "ending_name": "通关 · 闸门", "san": 70.0, "min_san": 50.0, "explore": {"pct": 40}, "diff": "easy",
		"achievements": [{"name": "普通 · 还活着", "pts": 10}, {"name": "x", "pts": 0}]})
	check(easy["sum"] == 300 + 5 + 5 + 10 + 10 + 70 + 80 and easy["total"] == 480 and easy["mult"] == 1.0, "ending 300 + the ledger + achievements + final SAN + 2 a point of exploration")
	var merged := ScoreRules.group(ledger)
	check(merged.size() == 2 and merged[0]["n"] == 2 and merged[0]["pts"] == 5, "like entries are merged: desk answer ×2")
	var nm := ScoreRules.total([], {"ending": true, "san": 100.0, "min_san": 10.0, "explore": {"pct": 50}, "diff": "hard"})
	check(nm["mult"] == 1.2 and nm["sum"] == 300 + 100 - 30 - 30 + 100 and nm["total"] == roundi(440 * 1.2), "the nightmare multiplies by 1.2; a low SAN low costs 30, a very low one 30 more")
	check(ScoreRules.total([{"cat": "保命与惊醒", "text": "x", "pts": -900}], {"diff": "easy"})["total"] == 0, "the total never goes below 0")
	check(ScoreRules.PAR["cyber"] == 1680 and ScoreRules.PAR["car"] == 1080 and ScoreRules.GRADES.size() == 9 and ScoreRules.CATS.size() == 8, "par times and the eight categories")
	# The track codec.
	var track: Array = [[0, 0, 100, 50, 3], [5, 0, 101, 52, 4], [12, 1, 400, -20, 63], [40, 1, 400, -20, 0]]
	var text := RunTrack.encode(track)
	check(RunTrack.decode(text) == track and text.length() < 40, "a track encodes small and decodes to the same samples")
	check(RunTrack.decode("AB!AB") == RunTrack.decode("AB") and RunTrack.decode("").is_empty(), "bad data stops there; what came before is used")
	var mid := RunTrack.at(track, 2.5)
	check(absf(float(mid[2]) - 100.5) < 0.0001 and absf(float(mid[3]) - 51.0) < 0.0001 and RunTrack.at(track, 20.0)[1] == 0 + 1 - 0 and RunTrack.at(track, -5.0) == track[0] and RunTrack.at(track, 999.0) == track[3], "between samples the position is interpolated; across a scene change it is not")
	# The ledger from facts.
	var rooms := CampusData.rooms()
	var sc := RunScoreModule.new(rooms, CampusData.layout("out"), CampusData.campus(), {"rain": "下不完的雨"})
	sc.begin("s1")
	var logged: Array = []
	sc.on_event = func(kind: String, text2: String, pts: int) -> void: logged.append([kind, text2, pts])
	sc.fact({"kind": "anomaly", "phase": "start", "id": "rain"})
	sc.fact({"kind": "anomaly", "phase": "end", "id": "rain", "survived": true, "lethal": true})
	sc.fact({"kind": "anomaly", "phase": "start", "id": "moth"})
	sc.fact({"kind": "anomaly", "phase": "hurt", "id": "moth"})
	sc.fact({"kind": "anomaly", "phase": "end", "id": "moth", "survived": true, "lethal": false})
	sc.fact({"kind": "anomaly", "phase": "start", "id": "turn"})
	sc.fact({"kind": "anomaly", "phase": "end", "id": "turn", "survived": false, "lethal": true})
	check(sc.ledger.size() == 2 and sc.ledger[0]["text"] == "化解「下不完的雨」" and sc.ledger[0]["pts"] == 40 and sc.ledger[1]["text"] == "「moth」受伤后脱身" and sc.ledger[1]["pts"] == -10, "a lethal anomaly survived is +40, one survived hurt is −10, one not survived is nothing")
	sc.fact({"kind": "fakeNormal", "laugh": true})
	sc.fact({"kind": "fakeNormal", "laugh": false})
	sc.fact({"kind": "face", "correct": true})
	sc.fact({"kind": "face", "correct": false})
	sc.fact({"kind": "lesson", "correct": true})
	sc.fact({"kind": "lesson", "correct": false})
	sc.fact({"kind": "exam", "phase": "paper", "pass": true})
	sc.fact({"kind": "exam", "phase": "bell"})
	sc.fact({"kind": "inspection", "compliant": true})
	sc.fact({"kind": "inspection", "compliant": false})
	sc.fact({"kind": "inspection", "compliant": false, "excused": true})
	var pts := []
	for e: Dictionary in sc.ledger.slice(2):
		pts.append(int(e["pts"]))
	check(pts == [-20, 15, 10, -15, 5, 20, 20, -30], "laugh −20, held back +15, quiz +10/−15, desk +5, exam +20, inspection +20/−30; an excused absence is nothing")
	for _i in 9:
		sc.fact({"kind": "patrol", "what": "locked"})
	var lock_sum := 0
	for e: Dictionary in sc.ledger:
		if e["text"] == "被巡察者盯上":
			lock_sum += int(e["pts"])
	check(lock_sum == -60 and sc.locked == -60, "being locked on costs 10 each, at most 60 in all")
	sc.fact({"kind": "patrol", "what": "lost"})
	sc.fact({"kind": "patrol", "what": "locker"})
	sc.fact({"kind": "patrol", "what": "door"})
	sc.fact({"kind": "patrol", "what": "permanent"})
	sc.fact({"kind": "protect", "by": "immune"})
	sc.fact({"kind": "wake"})
	check(sc.saved == 1 and sc.wakes == 1 and sc.ledger[sc.ledger.size() - 1]["pts"] == -80 and sc.ledger[sc.ledger.size() - 2]["pts"] == -60 and sc.ledger[sc.ledger.size() - 3]["pts"] == -80, "rescue −60, waking −80, permanent chase −80")
	check(logged.any(func(x: Array) -> bool: return x[0] == "anomaly" and x[1] == "遭遇「下不完的雨」") and logged.any(func(x: Array) -> bool: return x[0] == "choice" and x[1] == "课桌任务答错") and logged.any(func(x: Array) -> bool: return x[0] == "exam" and x[1] == "撞响了钟楼的钟"), "the replay log hears the ledger and the zero-point events too")
	# Save, restore, validate.
	var back := RunScoreModule.new(rooms, CampusData.layout("out"), CampusData.campus())
	back.restore(sc.capture())
	check(back.ledger == sc.ledger and back.saved == 1 and back.run == "s1" and back.validate(sc.capture()).is_empty() and not back.validate({"run": 5, "ledger": []}).is_empty(), "the ledger saves and loads; a bad one is rejected")
	# Clues and the totals of the exploration.
	sc.add_clue("server", 2)
	sc.add_clue("stall", 2)
	check(sc.clues.has("server") and not sc.clues.has("stall"), "only public clues count (a hidden route's is not kept)")
	var t := sc.totals()
	check((t["rooms"] as Array).size() >= 30 and (t["zones"] as Array).has("gateN") and int(t["cells"]) > 5000, "the totals: rooms with a sketch, open outdoor areas and three gates, walkable tiles (%d rooms, %d cells)" % [(t["rooms"] as Array).size(), int(t["cells"])])
	sc.rooms["teach1"] = 1
	sc.zones["gateN"] = 1
	var e1 := sc.explore(null, ["usb"])
	check(e1["pct"] > 0 and e1["clue"] == roundi(2.0 / 21.0 * 100.0), "visited places and found clues raise the exploration (%d%%)" % int(e1["pct"]))
	# Min SAN and a clear.
	sc.observe_san(80.0)
	sc.observe_san(12.0)
	sc.observe_san(40.0)
	check(sc.min_san == 12.0, "the lowest SAN is remembered")
	var res := sc.finish({"id": "car", "legit": true}, {"achievements": [], "san": 40.0, "explore": e1, "diff": "hard", "talent": "none", "day": 2, "clock": 900.0, "active": 1080.0, "route_name": "《闸门》", "mode": "normal", "version": "t"})
	check(res["rated"] and res["route"] == "car" and res["grade"] == ScoreRules.grade_of(float(res["gradeScore"]))["g"] and res["san"]["min"] == 12 and res["time"]["par"] == 1080.0 and res["timeScore"] == 400
		and res["score"]["mult"] == 1.2 and sc.result() == res, "a clear makes a rated record: score, time score (par time) and grade")
	check(res["score"]["items"][0]["cat"] == "结局" and res["score"]["items"][0]["text"] == "通关 · 《闸门》", "the first line of the detail is the ending")
	sc.trusted = false
	check(not sc.finish({"id": "car", "legit": true}, {"san": 40.0, "explore": e1, "diff": "easy", "active": 1080.0})["rated"], "a run that used the debug panel is not rated")
	sc.trusted = true
	var unlawful := sc.finish({"id": "car", "legit": false}, {"san": 40.0, "explore": e1, "diff": "easy", "active": 1080.0})
	check(not unlawful["rated"] and unlawful["score"]["items"][0]["cat"] != "结局", "an ending that is not legit gets no ending points and no record")
	var dl := sc.death_line({"san": 40.0, "explore": e1, "diff": "easy"})
	check(dl.has("total") and dl["explore"] == int(e1["pct"]) and not dl["debug"], "a death gives one line: the score and the exploration")


func _test_run_records() -> void:
	var dir := _test_path.get_base_dir() + "/records-test"
	var store := RunRecords.new(dir)
	for f in DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else PackedStringArray():
		DirAccess.remove_absolute(dir + "/" + f)
	check(store.list().is_empty() and store.grades().is_empty(), "no records at first")
	var pack := {"v": 1, "run": "r", "scenes": ["teach1"], "track": "AAAAA", "pat": [], "clock": [], "events": [], "start": 1, "partial": 0}
	var a := store.add(_rec("car", "easy", "C", 700, 900.0, 1000), pack)
	var b := store.add(_rec("car", "easy", "B", 860, 1100.0, 2000), pack)
	var c := store.add(_rec("face", "hard", "A", 1010, 800.0, 3000, {"mode": "speedrun", "time": {"active": 800.0, "rta": 805.0, "par": 1200.0, "used": 805.0}}), pack)
	check(store.list().size() == 3 and store.get_record(b)["grade"] == "B" and int(store.get_record(a)["replay"]) == 1 and not store.replay(a).is_empty() and store.replay(a)["track"] == "AAAAA", "records are kept with their replay files")
	check(store.grades()["B"]["count"] == 1 and store.grades()["B"]["best"] == b and float(store.grades()["C"]["first"]) == 1000.0, "the grade obtained summary: first time, count, best record")
	store.add(_rec("car", "easy", "B", 870, 1000.0, 4000), pack)
	check(store.grades()["B"]["count"] == 2 and store.grades()["B"]["best"] != b, "the best of a grade follows the higher grade score")
	# Debug records are marked and never count.
	var d := store.add(_rec("car", "easy", "SS", 1400, 500.0, 5000, {"source": "debug"}), {})
	check(not store.grades().has("SS") and store.best_grade("easy", "car") == "B" and int(store.get_record(d)["replay"]) == 0, "a debug record is not a real grade, not a best, and has no replay")
	check(store.remove_debug() == 1 and store.get_record(d).is_empty(), "debug records can be cleared")
	# Ranking: real speedrun records with an RTA.
	store.add(_rec("face", "hard", "B", 900, 700.0, 6000, {"mode": "speedrun", "time": {"active": 700.0, "rta": 705.0, "par": 1200.0, "used": 705.0}}), {})
	var by_time := store.ranking("hard", "face")
	var by_grade := store.ranking("hard", "face", "grade")
	check(by_time.size() == 2 and by_time[0]["time"]["rta"] == 705.0 and by_grade[0]["grade"] == "A" and store.ranking("easy", "car").is_empty(), "the speedrun ranking by time or by grade; none without an RTA")
	# Reload from disk.
	var again := RunRecords.new(dir)
	check(again.list().size() == store.list().size() and again.grades()["B"]["count"] == 3 and again.best_grade("hard", "face") == "A", "the records are read back from their file")
	# At most 50, but the bests of every route × difficulty survive and only the last 10 keep a replay.
	var many := RunRecords.new(dir + "-many")
	for f in DirAccess.get_files_at(dir + "-many") if DirAccess.dir_exists_absolute(dir + "-many") else PackedStringArray():
		DirAccess.remove_absolute(dir + "-many/" + f)
	var first := many.add(_rec("portal", "easy", "S", 1200, 600.0, 1), pack)
	for i in 55:
		many.add(_rec("car", "easy", "D", 560 + i, 1000.0 + i, 100 + i), pack)
	check(many.list().size() == 50 and not many.get_record(first).is_empty(), "at most 50 records; the oldest go, but the best of a route survives")
	var with_replay := 0
	for x: Dictionary in many.list():
		with_replay += int(x.get("replay", 0))
	check(with_replay <= RunRecords.REPLAYS_MAX + 3 and with_replay >= RunRecords.REPLAYS_MAX, "only the recent ten and the bests keep a replay (%d)" % with_replay)
	check(many.remove(first) and many.get_record(first).is_empty() and not many.remove("nope"), "a record can be deleted")
	# The log.
	var log := RunLog.new(CampusData.rooms())
	log.begin("r1")
	log.scene = "teach1"
	log.pos = Vector2(100, 60)
	log.now_s = 1.0
	log.tick(0.5, {}, [])
	log.pos = Vector2(100.5, 60.5)
	log.now_s = 1.5
	log.tick(0.5, {}, [])
	check(log.samples.size() == 1, "a point is kept only when the player moved, turned or changed scene")
	log.pos = Vector2(130, 60)
	log.now_s = 2.0
	log.tick(0.5, {}, [])
	check(log.samples.size() == 2 and log.samples[1][2] == 65, "moving adds a point (x/2)")
	log.event("anomaly", "遭遇「雨」")
	log.scene = "out"
	log.tick(10.0, {"walk": true, "room": "out", "x": 400.0, "y": 200.0}, ["还活着"])
	check(log.events.size() == 2 and log.events[1][1] == "achieve" and log.clock.size() == 1 and log.scenes == ["teach1", "out"] and log.pat.size() == 1, "events, the clock every 10 s, a new achievement event, and the patroller's position in the same building")
	var packed := log.pack()
	var restored := RunLog.new(CampusData.rooms())
	restored.restore("r1", packed)
	check(restored.run == "r1" and restored.samples == log.samples and restored.events == log.events and restored.partial == 0, "the log in progress carries on when the run id matches")
	var other := RunLog.new(CampusData.rooms())
	other.restore("r2", packed)
	check(other.run == "r2" and other.samples.is_empty() and other.partial == 1, "when it does not match it starts again, marked partial")
	var done := log.finish()
	check(done["track"] != "" and RunTrack.decode(String(done["track"])).size() == log.samples.size(), "a clear hands over the encoded track")


func _test_results_page() -> void:
	check(ResultsPanel.fmt(0) == "00:00" and ResultsPanel.fmt(1245.4) == "20:45" and ResultsPanel.fmt(-5) == "00:00", "times read mm:ss")
	var items: Array = [{"cat": "应对 · 异象", "text": "化解「下不完的雨」", "pts": 40, "n": 1}, {"cat": "校规与巡察", "text": "学生会检查 · 在教室", "pts": 20, "n": 3},
		{"cat": "校规与巡察", "text": "躲在柜子里躲过", "pts": 15, "n": 2}, {"cat": "校规与巡察", "text": "电梯门在它面前合上", "pts": 15, "n": 1}, {"cat": "保命与惊醒", "text": "不知名药丸挡下一次", "pts": -60, "n": 1}]
	var rep := ResultsPanel.report_card({"score": {"items": items}, "day": 2},
		{"events": [[100, "anomaly", "遭遇「下不完的雨」", 0, 0, 0, 0]], "clock": [[0, 1, 500], [200, 1, 700]]})
	check(rep.size() == 3 and String(rep[0]).begins_with("该生 ") and String(rep[0]).contains(SchoolClock.fmt_clock(500.0)) and String(rep[0]).ends_with("在「下不完的雨」里没有回头。") and String(rep[1]).contains("3 次检查都在座位上"), "the class teacher's remarks come from what happened, at most three")
	var plain := ResultsPanel.report_card({"score": {"items": []}, "day": 3})
	check(plain == ["该生第 3 天离开了学校。没有人看见是怎么走的。"], "with nothing to say: left without anyone seeing")
	var secret := ResultsPanel.report_card({"score": {"items": [{"cat": "应对 · 异象", "text": "化解「满员」", "pts": 20, "n": 1}, {"cat": "应对 · 异象", "text": "化解「可乐」", "pts": 20, "n": 1}]}, "day": 1})
	var leaked := false
	for line in secret:
		for w: String in ResultsPanel.REPORT_SECRET:
			if String(line).contains(w):
				leaked = true
	check(not leaked and secret.size() == 1 and String(secret[0]).contains("离开了学校"), "hidden content never reaches the report card (the secrecy guard)")
	var m := ScoreRules.sample_meta("SSS", "cyber")
	check(m["grade"] == "SSS" and m["diff"] == "hard" and m["score"]["mult"] == 1.2 and m["time"]["par"] == 1680.0, "a sample record for SSS is nightmare and clears the gate")
	for g: Dictionary in ScoreRules.GRADES:
		var sm := ScoreRules.sample_meta(String(g["g"]), "car")
		check(sm["grade"] == g["g"], "the sample for %s grades %s" % [g["g"], sm["grade"]])


func _test_records_panel() -> void:
	var dir := _test_path.get_base_dir() + "/records-ui"
	for f in DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else PackedStringArray():
		DirAccess.remove_absolute(dir + "/" + f)
	var store := RunRecords.new(dir)
	var samples: Array = [[0, 0, 40, 30, 0], [10, 0, 44, 30, 0], [20, 0, 44, 34, 16], [30, 0, 44, 34, 16]]
	var pack := {"v": 1, "run": "r", "scenes": ["teach1"], "track": RunTrack.encode(samples), "pat": [[10, 0, 46, 30]], "clock": [], "events": [[10, "anomaly", "遭遇「下不完的雨」", 0, 0, 44, 30]],
		"start": 1, "partial": 0}
	var a := store.add(_rec("car", "easy", "B", 860, 1100.0, 2000), pack)
	var b := store.add(_rec("face", "hard", "A", 1010, 800.0, 3000, {"mode": "speedrun", "time": {"active": 800.0, "rta": 805.0, "par": 1200.0, "used": 805.0}}), pack)
	var panel := RecordsPanel.new(store, CampusData.rooms())
	root.add_child(panel)
	panel.open()
	check(panel.filtered().size() == 2 and panel.filtered()[0]["id"] == b, "the list starts newest first")
	panel._diff = "easy"
	check(panel.filtered().size() == 1 and panel.filtered()[0]["id"] == a, "the difficulty filter narrows the list")
	panel._diff = ""
	panel._sort = "used"
	check(panel.filtered()[0]["id"] == b, "sorted by used time puts the fastest first")
	panel._mode = "rank"
	panel._refresh()
	check(panel.visible, "the ranking tab builds")
	panel._mode = "grades"
	panel._refresh()
	check(store.grades().has("B") and not store.grades().has("SSS"), "the result screens tab lists only grades a real run earned")
	check(panel.open_view(a, false) and panel._t_max == 30.0 and panel._scene == "teach1", "the replay opens on the first drawable scene")
	panel._t = 20.0
	panel._redraw()
	check(panel._map.here and panel._map.trails[0]["pts"].size() == 3, "the replay shows the path up to the time")
	check(panel.open_view(a, true) and panel._map.trails[0]["pts"].size() == 4 and not panel._map.here, "the footprint map shows the whole path, no marker")
	check(not panel.open_view("nope", true), "a missing replay does not open")
	panel.queue_free()
