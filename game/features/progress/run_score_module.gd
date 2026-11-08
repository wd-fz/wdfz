class_name RunScoreModule
extends FeatureModule
## This run's score ledger and exploration (modules/run-record/run-score.js, reference
## wd-fz.github.io@0bf508a). Only judges, never changes play; the rules are in ScoreRules.
## The ledger is saved with the run: every plus and minus, the lowest SAN, the rooms entered and the open
## outdoor areas visited, and the clues found. On a real clear it works out the score, the time score and
## the grade for a record; on a death only one line is shown, no grade and no record. A run that used the
## debug panel (or a mod) is not rated.
## Events out: none (the app asks for results).

const STATE_VERSION := 1
## Public clues: the ones that do not belong to a hidden route (hidden ones count in neither part).
const CLUES := ["altar", "atlas", "bell", "comp", "gaten", "gatew", "geo", "hand", "keys", "lesson", "office", "pendulum", "portal", "portalDiary",
	"repeat", "roomkey", "roster", "server", "trash", "turn", "usb"]
const LEDGER_MAX := 400
const PUBLIC_ENDS := ["car", "face", "portal", "cyber", "dismissal", "international"]

var run := ""
var ledger: Array = []        # [{cat, text, pts}]
var min_san := 100.0
var saved := 0
var wakes := 0
var locked := 0
var rooms: Dictionary = {}
var zones: Dictionary = {}
var clues: Dictionary = {}    # clue id → day
var an := ""
var an_hurt := 0
var legacy := 0
var trusted := true           # false once the debug panel or a mod was used: not rated
## The replay log hears every ledger entry and some zero-point events: Callable(kind, text, pts).
var on_event := Callable()

var _rooms: Dictionary = {}
var _out: Dictionary = {}
var _campus: Dictionary = {}
var _zone_acc := 0.0
var _result: Dictionary = {}
var _death_line: Dictionary = {}
var _totals: Dictionary = {}
var _names: Dictionary = {}   # anomaly id → display name


func _init(rooms_in: Dictionary = {}, out: Dictionary = {}, campus: Dictionary = {}, names: Dictionary = {}) -> void:
	_rooms = rooms_in
	_out = out
	_campus = campus
	_names = names


func module_id() -> StringName:
	return &"progress.score"


func state_version() -> int:
	return STATE_VERSION


func reset() -> void:
	run = ""
	ledger = []
	min_san = 100.0
	saved = 0
	wakes = 0
	locked = 0
	rooms = {}
	zones = {}
	clues = {}
	an = ""
	an_hurt = 0
	legacy = 0
	trusted = true
	_result = {}
	_death_line = {}
	_zone_acc = 0.0


func begin(run_id: String) -> void:
	reset()
	run = run_id


func capture() -> Dictionary:
	return {"run": run, "ledger": ledger.duplicate(true), "min_san": min_san, "saved": saved, "wakes": wakes, "locked": locked, "rooms": rooms.duplicate(),
		"zones": zones.duplicate(), "clues": clues.duplicate(), "legacy": legacy, "trusted": trusted}


func validate(data: Dictionary) -> String:
	if not (data.get("run") is String) or not (data.get("ledger") is Array) or (data["ledger"] as Array).size() > LEDGER_MAX:
		return "积分记录无效"
	for e: Variant in data["ledger"]:
		if not (e is Dictionary) or not (e.get("cat") is String) or not (e.get("text") is String) or not (e.get("pts") is int or e.get("pts") is float):
			return "积分记录无效"
	for k: String in ["rooms", "zones", "clues"]:
		if not (data.get(k, {}) is Dictionary):
			return "积分记录无效"
	return ""


func restore(data: Dictionary) -> void:
	reset()
	run = String(data["run"])
	ledger = (data["ledger"] as Array).duplicate(true)
	min_san = float(data.get("min_san", 100.0))
	saved = int(data.get("saved", 0))
	wakes = int(data.get("wakes", 0))
	locked = int(data.get("locked", 0))
	rooms = (data.get("rooms", {}) as Dictionary).duplicate()
	zones = (data.get("zones", {}) as Dictionary).duplicate()
	clues = (data.get("clues", {}) as Dictionary).duplicate()
	legacy = int(data.get("legacy", 0))
	trusted = bool(data.get("trusted", true))


func set_context(_ctx: Dictionary) -> void:
	pass


func take_events() -> Array:
	return []


func _add(cat: String, text: String, pts: int, kind: String = "score") -> void:
	ledger.append({"cat": cat, "text": text, "pts": pts})
	if ledger.size() > LEDGER_MAX:
		ledger.pop_front()
	_log(kind, text, pts)


func _log(kind: String, text: String, pts: int = 0) -> void:
	if on_event.is_valid():
		on_event.call(kind, text, pts)


func an_name(id: String) -> String:
	return String(_names.get(id, id))


## One fact from the run (the same stream the achievements read).
func fact(f: Dictionary) -> void:
	var P := ScoreRules.PTS
	match String(f["kind"]):
		"anomaly":
			if f["phase"] == "start":
				an = String(f["id"])
				an_hurt = 0
				_log("anomaly", "遭遇「%s」" % String(f.get("name", an_name(an))))
			elif f["phase"] == "hurt":
				if an == String(f["id"]):
					an_hurt = 1
			elif f["phase"] == "end" and an == String(f["id"]):
				if bool(f.get("survived", false)):
					var nm := String(f.get("name", an_name(String(f["id"]))))
					if an_hurt > 0:
						_add("应对 · 异象", "「%s」受伤后脱身" % nm, int(P["anomalyHurt"]), "anomaly")
					else:
						_add("应对 · 异象", "化解「%s」" % nm, int(P["anomalyLethal"]) if bool(f.get("lethal", false)) else int(P["anomalyClean"]), "anomaly")
				an = ""
				an_hurt = 0
		"fakeNormal":
			if f.get("laugh") == true:
				_add("应对 · 选择", "笑出了声", int(P["laugh"]), "choice")
			elif f.get("laugh") == false:
				_add("应对 · 选择", "忍住了没笑", int(P["noLaugh"]), "choice")
		"broadcast":
			if f.get("what") == "verified" and f.get("real") == false:
				_add("应对 · 选择", "核对假广播", int(P["anomalyClean"]), "broadcast")
		"face":
			_add("应对 · 选择", "验证题答对" if bool(f["correct"]) else "验证题答错", int(P["faceRight"]) if bool(f["correct"]) else int(P["faceWrong"]), "choice")
		"lesson":
			if bool(f.get("correct", false)):
				_add("应对 · 选择", "课桌任务答对", int(P["lesson"]), "choice")
			else:
				_log("choice", "课桌任务答错")
		"exam":
			if f.get("phase") == "paper":
				_add("应对 · 选择", "考试合格交卷" if bool(f.get("pass", false)) else "考试没坐住", int(P["examPass"]) if bool(f.get("pass", false)) else int(P["examFail"]), "exam")
			else:
				_log("exam", "撞响了钟楼的钟")
		"inspection":
			if bool(f.get("excused", false)) or f.get("result") == "excused":
				return
			_add("校规与巡察", "学生会检查 · 在教室" if bool(f["compliant"]) else "学生会检查 · 缺席", int(P["inspectOk"]) if bool(f["compliant"]) else int(P["inspectAbsent"]), "inspection")
		"patrol":
			match String(f.get("what", "")):
				"permanent":
					_add("校规与巡察", "登记后缺席 · 持续追踪", int(P["permanent"]), "patrol")
				"locked":
					var room := int(P["patrolLockedCap"]) - locked
					if room < 0:
						var pts := maxi(int(P["patrolLocked"]), room)
						locked += pts
						_add("校规与巡察", "被巡察者盯上", pts, "patrol")
					else:
						_log("patrol", "被巡察者盯上")
				"lost":
					_add("校规与巡察", "甩掉了巡察者", int(P["patrolLost"]), "patrol")
				"locker":
					_add("校规与巡察", "躲在柜子里躲过", int(P["locker"]), "patrol")
				"door":
					_add("校规与巡察", "电梯门在它面前合上", int(P["locker"]), "patrol")
				"banish":
					_log("patrol", "符纸烧成了灰")
		"protect":
			saved = 1
			_add("保命与惊醒", "天生免疫挡下一次" if f.get("by") == "immune" else "不知名药丸挡下一次", int(P["protect"]), "protect")
		"wake":
			wakes += 1
			_add("保命与惊醒", "预知梦惊醒", int(P["wake"]), "wake")
		"death":
			if not bool(f.get("wake", false)):
				_on_death()


func add_clue(id: String, day: int) -> void:
	if CLUES.has(id) and not clues.has(id):
		clues[id] = day


func enter_room(id: String) -> void:
	rooms[id] = 1


# ---- exploration ----

func totals() -> Dictionary:
	if not _totals.is_empty():
		return _totals
	var room_ids: Array = []
	var cells := 0
	var ids: Array = _rooms.keys()
	ids.sort()
	for id: String in ids:
		var r: Dictionary = _rooms[id]
		if bool(r.get("flags", {}).get("noMap", false)):
			continue
		room_ids.append(id)
		for row in r["grid"]:
			for c in String(row).length():
				if String(row).substr(c, 1) != "#":
					cells += 1
	var zone_ids: Array = []
	var objs: Array = _out.get("objects", [])
	for i in objs.size():
		var o: Dictionary = objs[i]
		if o.has("k") and (o["k"] != "roof" or bool(o.get("open", false))):
			zone_ids.append(String(o.get("id", "%s%d" % [o["k"], zone_ids.size()])))
	for k: String in ["N", "W", "S"]:
		zone_ids.append("gate" + k)
	_totals = {"rooms": room_ids, "zones": zone_ids, "cells": cells}
	return _totals


## Outdoors: which open area the player stands in, which gate is close. world: campus units.
func zone_tick(dt: float, scene: String, world: Vector2) -> void:
	_zone_acc += dt
	if _zone_acc < 0.5 or scene != "out":
		return
	_zone_acc = 0.0
	var sc := float(_out.get("SC", 2.0))
	var mx := world.x / sc
	var my := world.y / sc
	var objs: Array = _out.get("objects", [])
	for i in objs.size():
		var o: Dictionary = objs[i]
		if not o.has("k") or (o["k"] == "roof" and not bool(o.get("open", false))):
			continue
		if mx > float(o["x"]) and mx < float(o["x"]) + float(o["w"]) and my > float(o["y"]) and my < float(o["y"]) + float(o["h"]):
			zones[String(o.get("id", "%s%d" % [o["k"], i]))] = 1
	var gates: Dictionary = _campus.get("gates", {})
	for k: String in ["n", "w", "s"]:
		if gates.has(k) and Vector2(mx, my).distance_to(Vector2(float(gates[k]["x"]), float(gates[k]["y"]))) < 14.0:
			zones["gate" + k.to_upper()] = 1


func observe_san(san: float) -> void:
	min_san = minf(min_san, san)


## ex: the exploration module (seen tiles per room); extra_clues: clue ids known to other modules.
func explore(ex: ExplorationModule, extra_clues: Array = []) -> Dictionary:
	var t := totals()
	var seen_places := 0
	var seen_cells := 0
	for id: String in t["rooms"]:
		if rooms.has(id) or (ex != null and ex.count(id) > 0):
			seen_places += 1
		if ex != null:
			var b := ex.seen(id)
			var grid: Array = _rooms[id]["grid"]
			var cols := int(_rooms[id]["cols"])
			for i in b.size():
				if b[i] != 0 and String(grid[floori(float(i) / float(cols))]).substr(i % cols, 1) != "#":
					seen_cells += 1
	for z: String in t["zones"]:
		if zones.has(z):
			seen_places += 1
	var known := {}
	for id: String in clues:
		known[id] = true
	for id: String in extra_clues:
		known[id] = true
	var n := 0
	for id: String in CLUES:
		if known.has(id):
			n += 1
	return ScoreRules.explore({"places": seen_places, "places_total": (t["rooms"] as Array).size() + (t["zones"] as Array).size(), "cells": seen_cells,
		"cells_total": t["cells"], "clues": n, "clues_total": CLUES.size()})


# ---- results ----

func _context(ctx: Dictionary, extra: Dictionary) -> Dictionary:
	var out := {"achievements": ctx.get("achievements", []), "san": ctx.get("san", 100.0), "min_san": minf(min_san, float(ctx.get("san", 100.0))),
		"explore": ctx.get("explore", {"pct": 0}), "diff": ctx.get("diff", "easy"), "saved": saved > 0, "wakes": wakes}
	out.merge(extra, true)
	return out


## ctx: achievements [{name, pts}], san, explore, diff, talent, day, clock, active (s), rta (s or 0), mode, version, run_id, new_ach [ids], run_ach [ids].
## f: the ending fact {id, legit, fake}. Returns the record (also kept as result()); {} when not a real clear.
func finish(f: Dictionary, ctx: Dictionary) -> Dictionary:
	_result = {}
	var id := String(f["id"])
	var ok := bool(f.get("legit", true)) and (PUBLIC_ENDS.has(id) or id == "beast")
	var c := _context(ctx, {"ending": ok, "ending_name": "通关 · " + String(ctx.get("route_name", id))})
	var sum := ScoreRules.total(ledger, c)
	var par := float(ScoreRules.PAR.get(id, 1200))
	var rta := float(ctx.get("rta", 0.0))
	var sec := rta if String(ctx.get("mode", "normal")) == "speedrun" and rta > 0.0 else float(ctx.get("active", 0.0))
	var rate := ScoreRules.rate(float(sum["total"]), sec, par, c)
	_result = {"id": "", "at": int(Time.get_unix_time_from_system() * 1000.0), "mode": String(ctx.get("mode", "normal")), "diff": String(ctx.get("diff", "easy")),
		"talent": String(ctx.get("talent", "none")), "route": id, "routeName": String(ctx.get("route_name", id)), "day": int(ctx.get("day", 1)), "clock": float(ctx.get("clock", 0.0)),
		"time": {"active": snappedf(float(ctx.get("active", 0.0)), 0.1), "rta": rta if rta > 0.0 else null, "par": par, "used": snappedf(sec, 0.1)},
		"score": {"rules": ScoreRules.RULES, "total": sum["total"], "sum": sum["sum"], "mult": sum["mult"], "items": sum["items"]},
		"grade": rate["grade"], "gradeName": rate["gradeName"], "band": rate["band"], "memo": rate["memo"], "gradeScore": rate["gradeScore"], "timeScore": rate["timeScore"],
		"gate": rate["gate"], "capped": rate["capped"], "explore": c["explore"], "san": {"final": roundi(float(ctx.get("san", 100.0))), "min": roundi(float(c["min_san"]))},
		"ach": {"run": ctx.get("run_ach", []), "newly": ctx.get("new_ach", [])}, "legacy": legacy, "source": "play", "version": String(ctx.get("version", "")),
		"rated": ok and trusted, "debug": not trusted}
	return _result


func result() -> Dictionary:
	return _result


## A death: one line, no grade, no record.
func _on_death() -> void:
	_death_line = {"pending": true}


## Called by the app after a death with the same ctx as finish.
func death_line(ctx: Dictionary) -> Dictionary:
	var c := _context(ctx, {"ending": false})
	var sum := ScoreRules.total(ledger, c)
	_death_line = {"total": sum["total"], "explore": int(c["explore"]["pct"]), "debug": not trusted}
	return _death_line


func last_death_line() -> Dictionary:
	return _death_line


## A rough estimate for the debug panel: as if the run ended now on this route.
func estimate(route: String, ctx: Dictionary) -> Dictionary:
	var c := _context(ctx, {"ending": true, "ending_name": "通关 · " + route})
	var sum := ScoreRules.total(ledger, c)
	var par := float(ScoreRules.PAR.get(route, 1200))
	return {"score": sum, "rate": ScoreRules.rate(float(sum["total"]), maxf(1.0, float(ctx.get("active", 0.0))), par, c), "explore": c["explore"], "trusted": trusted}
