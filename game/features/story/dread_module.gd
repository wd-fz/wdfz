class_name DreadModule
extends FeatureModule
## Atmosphere, ported from the Web version (reference wd-fz.github.io@0bf508a, dread.js and
## fx/dread-fx.js): only mood. It never changes an anomaly, the patroller, an inspection, the
## timetable or a hidden trigger, takes no stat and never kills.
## · Scare budget: strong scares 45 s apart (120 s in one area), mild ones 9 s (24 s per area).
## · False threats: placed sounds (knock, steps, chair, whisper, door, a call, running) at a door or
##   wall 4–16 m away, muffled through walls, left / right / behind; most of the time nothing comes.
## · Sudden hush: the ambience drops out for 3.2–5 s.
## · Sound first: 3.2 s before the next anomaly a low pressure comes up (not always right).
## · Revisits: the second visit to a room in a day changes it a little (a broken lamp, a note on
##   the floor, an echo in your steps, or someone just leaving as you come in); reproduced on load
##   from the room and the visit count.
## Nothing for the first 60 s of a run. The 5-minute debug slice is a dev tool and is not ported.
## 2026-11-14 (user-approved horror plan, docs/plan/中式与西式恐怖及吓人手法.md):
## · Director pacing (item 5): a pressure value rises while an anomaly, a chase or an inspection is on and
##   decays with a 60 s half-life. High pressure slows the false threats (a breather after something real);
##   a long calm (150 s with nothing real) speeds them up a little. Only the ambience; never a rule.
## · Revisits gain a fifth change (item 3): a line of chalk on a wall near you ("board").
## · The corridor notice (item 4): from day 2, once a day, in a free period indoors, a sheet from the
##   academic office appears on a wall ahead: two true lines read from the timetable and one false line in
##   red ink without the stamp. Nothing checks whether the player obeys it: following the false line simply
##   puts the player where the existing rules (lessons, lights-out, inspections) already count it.
## Events out: dread {cue, place}, duck {sec}, precursor {k}, visit {fx, ...}, clear.

const STATE_VERSION := 1
const CFG := {"strong_gap": 45.0, "strong_area": 120.0, "mild_gap": 9.0, "mild_area": 24.0, "amb_min": 24.0, "amb_max": 52.0, "safe_start": 60.0, "pre_lead": 3.2}
const NOTES := ["你昨天也来过。", "这张纸条不是写给你的。", "第二排靠窗的位子，今天也空着。",
	"我数过了，楼梯比早上多一级。", "有人在等你先走。", "如果你看到这张纸，就别再回来找它了。", "他走路的声音，和你一样。"]
const VISIT_KINDS := ["lamp", "note", "echo", "left", "board"]
const BOARD_LINES := ["今天的值日生：你", "下一节还是这一节", "这里少了一张桌子", "作业：明天交昨天的", "老师马上回来"]
const PACE := {"half": 60.0, "rest": 0.7, "quiet_after": 150.0, "quiet_boost": 1.4, "hold": 0.8, "inspect": 0.4}
## Corridor notice: chance per second while eligible (about once in 90 s of free time indoors).
const NOTICE_RATE := 1.0 / 90.0
const EAR_DREAD := 0.8   # talents.js earDread: the price of 顺风耳 is more frequent false threats

var visits: Dictionary = {}     # "day:room" → visits that day (saved: revisits replay on load)
var t := 0.0
var last: Dictionary = {}
var area_last: Dictionary = {}
var history: Array = []
var next_amb := 30.0
var pre_for := -1
var visit_fx: Dictionary = {}
var echo := false
var left_at := 0.0
var events: Array = []
var pressure := 0.0             # 0..1, director pacing (not saved: mood only)
var calm := 0.0                 # seconds since anything real
var notice: Dictionary = {}     # the corridor notice shown now {day, lines, fake, x, y}

var _rooms: Dictionary = {}
var _outdoor_scale := 1.0
var _c: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _init(rooms: Dictionary = {}, outdoor_scale: float = 1.0) -> void:
	_rooms = rooms
	_outdoor_scale = outdoor_scale if is_finite(outdoor_scale) and outdoor_scale > 0.0 else 1.0
	_rng.randomize()


func module_id() -> StringName:
	return &"story.dread"


func state_version() -> int:
	return STATE_VERSION


func reset() -> void:
	visits = {}
	_reset_run()


func _reset_run() -> void:
	t = 0.0
	last = {}
	area_last = {}
	history = []
	next_amb = 30.0
	pre_for = -1
	visit_fx = {}
	echo = false
	left_at = 0.0
	events = []
	pressure = 0.0
	calm = 0.0
	notice = {}


func capture() -> Dictionary:
	return {"random": RandomState.capture(_rng), "visits": visits.duplicate()}


func validate(data: Dictionary) -> String:
	if not (data.get("visits", {}) is Dictionary):
		return "氛围状态无效"
	for v: Variant in (data.get("visits", {}) as Dictionary).values():
		if not SaveSchema.is_integer(v, 0, 100000):
			return "氛围状态无效"
	return ""


func restore(data: Dictionary) -> void:
	reset()
	RandomState.restore(_rng, data)
	for k: String in (data.get("visits", {}) as Dictionary):
		visits[k] = int(data["visits"][k])


## ctx: scene, x, y, ang (world units), san, viol, night, day, busy, an_active, an_next, an_next0,
## ear (talent), door_open (Callable(c, r) -> bool), stand (Callable(Vector2) -> bool).
func set_context(ctx: Dictionary) -> void:
	_c = ctx


func take_events() -> Array:
	var out := events
	events = []
	return out


func _emit(kind: String, payload: Dictionary = {}) -> void:
	var e := payload.duplicate()
	e["kind"] = kind
	events.append(e)


func _me() -> Vector2:
	return Vector2(float(_c.get("x", 0.0)), float(_c.get("y", 0.0)))


func area() -> String:
	var scene := String(_c.get("scene", ""))
	if scene != "out":
		return "in:" + scene
	var sc := _outdoor_scale
	return "out:%d,%d" % [floori(_me().x / sc / 150.0), floori(_me().y / sc / 150.0)]


## 0..1: low SAN, violations and night (only sets how dense the false threats are).
func tension() -> float:
	return clampf((100.0 - float(_c.get("san", 100.0))) / 140.0 + float(_c.get("viol", 0.0)) / 260.0 + float(_c.get("night", 0.0)) * 0.25, 0.0, 1.0)


func allow(strength: int, where: String = "") -> bool:
	var s := "s" if strength >= 2 else "m"
	var gap: float = CFG["strong_gap"] if strength >= 2 else CFG["mild_gap"]
	var ag: float = CFG["strong_area"] if strength >= 2 else CFG["mild_area"]
	if where == "":
		where = area()
	if last.has(s) and t - float(last[s]) < gap:
		return false
	var key := where + ":" + s
	if area_last.has(key) and t - float(area_last[key]) < ag:
		return false
	if s == "m" and last.has("s") and t - float(last["s"]) < float(CFG["mild_gap"]):
		return false
	return true


func note(kind: String, strength: int, extra: Dictionary = {}) -> Dictionary:
	var s := "s" if strength >= 2 else "m"
	var where := area()
	if strength >= 1:
		last[s] = t
		area_last[where + ":" + s] = t
	var e := {"t": snappedf(t, 0.01), "kind": kind, "strength": strength, "area": where}
	e.merge(extra)
	history.append(e)
	if history.size() > 80:
		history.pop_front()
	return e


func _line_clear(a: Vector2, b: Vector2) -> bool:
	var scene := String(_c.get("scene", ""))
	var r: Dictionary = _rooms.get(scene, {})
	var n := maxi(1, ceili(a.distance_to(b) / 3.0))
	for i in range(1, n):
		var p := a.lerp(b, float(i) / n)
		if not r.is_empty():
			var tile := CampusGeometry.tile_at(r, p)
			if tile == "#":
				return false
			if tile == "=":
				var c := floori((p.x - float(r["ox"])) / float(r["tw"]))
				var rr := floori((p.y - float(r["oy"])) / float(r["th"]))
				var open: Callable = _c.get("door_open", Callable())
				if not (open.is_valid() and bool(open.call(c, rr))):
					return false
	return true


## A world point as left / right, how loud, behind, through a wall and metres (dreadPlace).
func place(w: Vector2) -> Dictionary:
	var d := w - _me()
	var m := d.length() * CampusGeometry.U2M
	var rel := atan2(d.y, d.x) - float(_c.get("ang", 0.0))
	var hear := 26.0 * (1.5 if bool(_c.get("ear", false)) else 1.0)
	return {"pan": clampf(sin(rel), -1.0, 1.0) * 0.9, "behind": cos(rel) < -0.2, "k": clampf(1.0 - m / hear, 0.12, 1.0),
		"muffled": not _line_clear(_me(), w), "m": m}


## Indoors a door or a wall min–max metres away (doors 70 % of the time); outdoors a point.
func spot(min_m: float, max_m: float) -> Variant:
	var scene := String(_c.get("scene", ""))
	var r: Dictionary = _rooms.get(scene, {})
	var best: Array = []
	if not r.is_empty():
		var grid: Array = r["grid"]
		for row in grid.size():
			for col in String(grid[row]).length():
				var ch := String(grid[row]).substr(col, 1)
				if ch != "=" and ch != "O" and ch != "#":
					continue
				if ch == "#" and (row + col) % 7 != 0:
					continue
				var p := Vector2(float(r["ox"]) + (col + 0.5) * float(r["tw"]), float(r["oy"]) + (row + 0.5) * float(r["th"]))
				var m := p.distance_to(_me()) * CampusGeometry.U2M
				if m >= min_m and m <= max_m:
					best.append({"p": p, "door": ch != "#"})
		var doors := best.filter(func(x: Dictionary) -> bool: return x["door"])
		if not doors.is_empty() and _rng.randf() < 0.7:
			best = doors
	else:
		for i in 12:
			var a := _rng.randf() * TAU
			var mm := (min_m + _rng.randf() * (max_m - min_m)) / CampusGeometry.U2M
			best.append({"p": _me() + Vector2(cos(a), sin(a)) * mm})
	if best.is_empty():
		return null
	return (best[_rng.randi() % best.size()] as Dictionary)["p"]


func false_threat(kind: String, strength: int = 1) -> bool:
	if not allow(strength):
		return false
	var p: Dictionary = {}
	if kind == "silence":
		_emit("duck", {"sec": 3.2 + _rng.randf() * 1.8})
	else:
		var far := 1.5 if bool(_c.get("ear", false)) else 1.0
		var sp: Variant = spot(2.0 if kind == "whisper" else 4.0, (40.0 if kind == "call" else 16.0) * (1.0 if kind == "whisper" else far))
		if sp == null:
			return false
		p = place(sp)
		_emit("dread", {"cue": kind, "place": p})
	note(kind, strength, {} if p.is_empty() else {"pan": snappedf(float(p["pan"]), 0.01), "m": snappedf(float(p["m"]), 0.1), "muffled": p["muffled"], "behind": p["behind"]})
	return true


func pick_ambient() -> String:
	var tt := tension()
	var r := _rng.randf()
	if r < 0.12:
		return "silence"
	if String(_c.get("scene", "")) != "out":
		if r < 0.36:
			return "knock"
		if r < 0.58:
			return "steps"
		if r < 0.74:
			return "chair"
		if r < 0.86 + 0.06 * tt:
			return "whisper"
		return "run" if tt > 0.55 and _rng.randf() < 0.5 else "door"
	if r < 0.45:
		return "steps"
	if r < 0.66:
		return "call"
	if r < 0.84:
		return "door"
	return "run" if tt > 0.55 and _rng.randf() < 0.5 else "whisper"


static func lhash(s: String) -> float:
	var h := 2166136261
	for i in s.length():
		h = (h ^ s.unicode_at(i)) & 0xFFFFFFFF
		h = (h * 16777619) & 0xFFFFFFFF
	return float(h % 100000) / 100000.0


## An atmosphere event (a stare, a vacancy) replaces the revisit change of the room.
func clear_revisit() -> void:
	visit_fx = {}
	echo = false
	left_at = 0.0
	_emit("clear")


## Entering a room; restoring rebuilds the saved room without counting a visit.
func enter(room: String, restoring: bool = false) -> void:
	_emit("clear")
	notice = {}
	visit_fx = {}
	echo = false
	left_at = 0.0
	if not _rooms.has(room):
		return
	var key := "%d:%s" % [int(_c.get("day", 1)), room]
	var n := maxi(1, int(visits.get(key, 0))) if restoring else int(visits.get(key, 0)) + 1
	visits[key] = n
	if n < 2 or room == "portal_tunnel" or room == "lift_dream":
		return
	var h := lhash("%s:%d" % [key, n])
	var kind: String = VISIT_KINDS[floori(h * VISIT_KINDS.size())]
	visit_fx = {"room": room, "visit": n, "kind": kind, "seed": h}
	match kind:
		"echo":
			echo = true
		"lamp":
			_emit("visit", {"fx": "lamp", "i": floori(lhash("%sL%d" % [key, n]) * 64.0)})
		"note":
			_emit("visit", {"fx": "note", "text": NOTES[floori(lhash("%sN%d" % [key, n]) * NOTES.size())], "seed": lhash("%sP%d" % [key, n])})
		"left":
			if not restoring:
				left_at = t + 0.8
		"board":
			var sp: Variant = spot(2.5, 7.0)
			if sp != null:
				_emit("visit", {"fx": "board", "text": BOARD_LINES[floori(lhash("%sB%d" % [key, n]) * BOARD_LINES.size())], "x": (sp as Vector2).x, "y": (sp as Vector2).y})
	note("visit:" + kind, 0, {"room": room, "visit": n})


## Real seconds; called only in normal play.
func tick(dt: float) -> void:
	t += dt
	if left_at > 0.0 and t >= left_at:
		left_at = 0.0
		var sp: Variant = spot(5.0, 14.0)
		if sp != null:
			_emit("dread", {"cue": "desk", "place": place(sp)})
	_pace_step(dt)
	var busy := bool(_c.get("busy", false))
	var nxt := float(_c.get("an_next", -1.0))
	if not bool(_c.get("an_active", false)) and nxt > 0.0 and nxt < float(CFG["pre_lead"]) and pre_for != int(_c.get("an_next0", 0)):
		pre_for = int(_c.get("an_next0", 0))
		if not busy:
			_emit("precursor", {"k": 0.6 + 0.4 * tension()})
			note("precursor", 0)
	if busy or t < float(CFG["safe_start"]):
		return
	_notice_step(dt)
	next_amb -= dt * (0.75 + tension() * 0.9) * pace() / (EAR_DREAD if bool(_c.get("ear", false)) else 1.0)
	if next_amb > 0.0:
		return
	next_amb = _rng.randf_range(float(CFG["amb_min"]), float(CFG["amb_max"]))
	var kind := pick_ambient()
	if not false_threat(kind, 2 if kind == "run" else 1):
		next_amb = _rng.randf_range(6.0, 12.0)


# ---- director pacing (item 5) ----

## Pressure follows what is really happening: held up while an anomaly or a chase is on, raised by an
## inspection, halving every 60 s otherwise.
func _pace_step(dt: float) -> void:
	pressure *= pow(0.5, dt / float(PACE["half"]))
	calm += dt
	if bool(_c.get("an_active", false)) or bool(_c.get("chase", false)):
		pressure = maxf(pressure, float(PACE["hold"]))
		calm = 0.0
	elif bool(_c.get("inspect", false)):
		pressure = maxf(pressure, float(PACE["inspect"]))
		calm = 0.0


## The rate multiplier for the false threats: a breather after something real, a nudge after a long calm.
func pace() -> float:
	if pressure > 0.05:
		return 1.0 - float(PACE["rest"]) * clampf(pressure, 0.0, 1.0)
	return float(PACE["quiet_boost"]) if calm > float(PACE["quiet_after"]) else 1.0


# ---- the corridor notice (item 4) ----

## Three lines for a day: two true ones read from the timetable, one false in red. Deterministic per day.
static func notice_lines(day: int, tsec: float) -> Dictionary:
	var next_class: Array = []
	for row: Array in SchoolClock.SCHED:
		if float(row[0]) > tsec and row[3] == "教室":
			next_class = row
			break
	var cls_name := String(next_class[2]) if not next_class.is_empty() else "晚自习一"
	var cls_at := SchoolClock.fmt_clock(float(next_class[0])) if not next_class.is_empty() else SchoolClock.fmt_clock(1090.0)
	var truths := ["%s %s 开始，请提前回本班教室就座。" % [cls_name, cls_at],
		"%s 熄灯，熄灯后请回宿舍。" % SchoolClock.fmt_clock(SchoolClock.LIGHTS_OUT),
		"学生会检查时，请留在本班教室。"]
	var lies := ["%s改在操场上，铃响后到操场集合。" % cls_name,
		"今晚熄灯推迟到 23:59，熄灯前可在校园内自由活动。",
		"学生会检查改在一楼走廊进行，请到走廊集合。"]
	var h := lhash("notice:%d" % day)
	var topic := floori(h * 3.0) % 3
	var lines: Array = []
	for i in 3:
		lines.append({"text": lies[i] if i == topic else truths[i], "fake": i == topic})
	# The false line does not always sit in the same row.
	var shift := floori(lhash("notice-row:%d" % day) * 3.0) % 3
	var ordered: Array = []
	for i in 3:
		ordered.append(lines[(i + shift) % 3])
	var fake := 0
	for i in 3:
		if ordered[i]["fake"]:
			fake = i
	return {"lines": ordered, "fake": fake}


func _notice_step(dt: float) -> void:
	var day := int(_c.get("day", 1))
	var key := "notice:%d" % day
	if day < 2 or visits.has(key) or not notice.is_empty() or not bool(_c.get("free", false)):
		return
	var scene := String(_c.get("scene", ""))
	if scene == "out" or not _rooms.has(scene) or scene == "portal_tunnel" or scene == "lift_dream":
		return
	if _rng.randf() >= dt * NOTICE_RATE or not allow(1):
		return
	var sp: Variant = spot(3.0, 8.0)
	if sp == null:
		return
	visits[key] = 1
	var content := notice_lines(day, float(_c.get("tsec", 700.0)))
	notice = {"day": day, "lines": content["lines"], "fake": content["fake"], "x": (sp as Vector2).x, "y": (sp as Vector2).y}
	_emit("notice", notice.duplicate(true))
	note("notice", 1, {"day": day})
