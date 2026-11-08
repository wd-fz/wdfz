class_name AtmosModule
extends FeatureModule
## Global atmosphere A1–A7, ported from the Web version (reference wd-fz.github.io@0bf508a,
## modules/atmosphere/atmos.js): the school feels wrong even when nothing happens. Only mood: it takes
## no stat, never kills and never changes an anomaly, the patroller, an inspection, the timetable or any
## trigger. The pictures (classmates turning, the window figure, the mop and bucket, dark lamps,
## emergency signs) are read from this state in game/app/game_app.gd and game/presentation/world/campus/campus_world.gd.
## · A1 too quiet: the daytime campus noise (whistle, car, bird) goes one by one from day 2; before an
##   anomaly, half of the time (from day 2) the whole place hushes for a few seconds.
## · A2 lamp layers: a stretch of each corridor has dead tubes; emergency signs glow green (fixed).
## · A3 classmates' stare: from day 2 walking into a seated classroom, everyone turns to you and back;
##   leave and return and one more seat is empty. Per classroom per day once, 3 a day in total.
## · A4 window: a still figure far outside a classroom window; look at it twice and it is gone.
## · A5 bell goes flat: from day 2 the end-of-class bell sinks half a tone, from day 3 a whole one;
##   the one before lights-out lower and slower.
## · A6 shifted objects: the mop and bucket in a corridor move when you are 8 m away and not looking.
## · A7 sky and tint: from day 2 dusk comes earlier, everything a little colder and darker.
## A3, A4 and A6 pass the scare budget (DreadModule.allow / note); not during inspections, anomalies,
## fake-normal or cut scenes.
## Two small timed scenes (modules/sensory/scenes.js) share the same budget and yield to anything real:
## a lamp hums and dims, then the hum moves to the nearest door; a door you just closed may be knocked
## on from the other side 1.4 s later (30 %, a door once per 120 s).
## Events out: campus {kind, pan, k, lp}, duck {sec}, dread {cue, place}, say {text}.

const STATE_VERSION := 1
const CFG := {
	"hush_lead": [3.3, 6.0], "hush_chance": 0.5, "hush_sec": 3.4,
	"campus_gap": [16.0, 38.0],
	"stare_chance": 0.45, "stare_max": 3, "stare_turn": 0.6, "stare_hold": 1.5,
	"window_chance": 0.35,
	"shift_min": 8.0, "shift_chance": 0.6,
	"bell_drop": [0.0, 0.5, 1.0], "night_bell_drop": 1.6, "night_bell_at": 1320.0,
}
const CAMPUS_KINDS := ["whistle", "car", "bird"]

static var seed := ""

var stares: Dictionary = {}     # "day:cls" → 1 turned, 2 vacancy used, 0 declined
var shift: Dictionary = {}      # "day:room" → "push" | "face" | 0
var shift_pose: Dictionary = {} # "day:room" → {dx, dy, angle}
var seats: Dictionary = {}      # "day:cls" → which seat is gone (1..7)
var said: Dictionary = {}
var left: Dictionary = {}       # cls → day it was last left

var hush := 0.0
var stare: Dictionary = {}      # {cls, room, t} while the class turns
var window: Dictionary = {}     # {room, cls, seed, seen, gone, anchor}
var window_look := false
var events: Array = []

var _rooms: Dictionary = {}
var _window_anchor: Dictionary = {}
var _c: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _campus_t := 12.0
var _hush_for := -1
var _pre_for := -1
var _last_cls := ""
var _last_win := ""
var _in_cls := ""
var _shift_new := ""
var _pat_seen: Dictionary = {}
var _pat_last: Dictionary = {}
var _sc_clock := 0.0
var _sc_next := 85.0
var _sc_event: Dictionary = {}
var _sc_doors: Dictionary = {}


func _init(rooms: Dictionary = {}, outdoor: Dictionary = {}) -> void:
	_rooms = rooms
	for object: Dictionary in outdoor.get("objects",[]):
		if object.get("id")=="lab":
			var scale := float(outdoor.get("SC",1))
			_window_anchor = {"x":(float(object["x"])+float(object["w"])*.5)*scale,"y":(float(object["y"])+float(object["h"])*.5)*scale,"height":16.2}
			break
	_rng.randomize()


func module_id() -> StringName:
	return &"story.atmos"


func state_version() -> int:
	return STATE_VERSION


func set_seed(value: String) -> void:
	seed = value


func reset() -> void:
	stares = {}
	shift = {}
	shift_pose = {}
	seats = {}
	said = {}
	left = {}
	_reset_run()


func _reset_run() -> void:
	hush = 0.0
	stare = {}
	window = {}
	window_look = false
	events = []
	_campus_t = 12.0
	_hush_for = -1
	_pre_for = -1
	_last_cls = ""
	_last_win = ""
	_in_cls = ""
	_shift_new = ""
	_pat_seen = {}
	_pat_last = {}
	_sc_clock = 0.0
	_sc_next = 85.0
	_sc_event = {}
	_sc_doors = {}


func capture() -> Dictionary:
	return {"random": RandomState.capture(_rng), "stares": stares.duplicate(), "shift": shift.duplicate(), "shift_pose": shift_pose.duplicate(true), "seats": seats.duplicate(), "said": said.duplicate(), "left": left.duplicate()}


func validate(data: Dictionary) -> String:
	for k: String in ["stares", "shift", "shift_pose", "seats", "said", "left"]:
		if not (data.get(k, {}) is Dictionary):
			return "氛围状态无效"
	for v: Variant in (data.get("stares", {}) as Dictionary).values():
		if not SaveSchema.is_integer(v, 0, 2):
			return "氛围状态无效"
	for v: Variant in (data.get("seats", {}) as Dictionary).values():
		if not SaveSchema.is_integer(v, 0, 7):
			return "氛围状态无效"
	for v: Variant in (data.get("shift", {}) as Dictionary).values():
		if not (v is int or v is float or (v is String and (v == "push" or v == "face"))):
			return "氛围状态无效"
	return ""


func restore(data: Dictionary) -> void:
	reset()
	RandomState.restore(_rng, data)
	stares = (data.get("stares", {}) as Dictionary).duplicate()
	shift = (data.get("shift", {}) as Dictionary).duplicate()
	shift_pose = (data.get("shift_pose", {}) as Dictionary).duplicate(true)
	seats = (data.get("seats", {}) as Dictionary).duplicate()
	said = (data.get("said", {}) as Dictionary).duplicate()
	left = (data.get("left", {}) as Dictionary).duplicate()


## ctx: scene, x, y, ang (world units), day, tsec, viol, busy, an_active, an_next, an_next0, age (seconds
## into the run), dread (DreadModule), pat {room, walk, x, y}, prop (Vector2 or null: the mop's world
## position), prop_ok (far enough and out of sight), sees_shifted.
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


func _hash(s: String) -> float:
	return DreadModule.lhash(s + ":" + seed)


func _day() -> int:
	return maxi(1, int(_c.get("day", 1)))


func _me() -> Vector2:
	return Vector2(float(_c.get("x", 0.0)), float(_c.get("y", 0.0)))


func _dread() -> DreadModule:
	return _c.get("dread") as DreadModule


func _busy() -> bool:
	return bool(_c.get("busy", false))


func _allow(strength: int) -> bool:
	var d := _dread()
	return d != null and d.allow(strength)


func _note(kind: String, strength: int, extra: Dictionary = {}) -> void:
	var d := _dread()
	if d != null:
		d.note(kind, strength, extra)


## The teaching or laboratory floor the player is on (storeys 1–5, not a stairwell), else {}.
func floor_room() -> Dictionary:
	var r: Dictionary = _rooms.get(String(_c.get("scene", "")), {})
	if r.is_empty() or not (r.get("host") == "teach" or r.get("host") == "lab") or r.get("floor") == null:
		return {}
	var fl := int(r["floor"])
	if fl < 1 or fl > 5 or r.get("flags", {}).get("stairwell", false):
		return {}
	return r


func cell(r: Dictionary) -> Vector2i:
	var me := _me()
	return Vector2i(floori((me.x - float(r["ox"])) / float(r["tw"])), floori((me.y - float(r["oy"])) / float(r["th"])))


## ClassroomLayout.classAt: 0..3 for the four classes of a teaching floor, else -1.
static func class_index(c: int, r: int) -> int:
	if r < 7 or r > 14:
		return -1
	for i in ClassmatesModule.SPANS.size():
		if c >= int(ClassmatesModule.SPANS[i][0]) and c <= int(ClassmatesModule.SPANS[i][1]):
			return i
	return -1


func class_at(r: Dictionary, c: int, row: int) -> String:
	if r.is_empty() or r.get("host") != "teach":
		return ""
	var grid: Array = r["grid"]
	if row < 0 or row >= grid.size():
		return ""
	var ch := String(grid[row]).substr(c, 1)
	if ch == "#" or ch == "=" or ch == "":
		return ""
	var k := class_index(c, row)
	return "%s:%d" % [r["id"], k] if k >= 0 else ""


# ---- A1 ----

func campus_kinds() -> Array:
	return CAMPUS_KINDS.slice(mini(2, _day() - 1))


func _campus_tick(dt: float) -> void:
	var tsec := float(_c.get("tsec", 0.0))
	if hush > 0.0 or bool(_c.get("an_active", false)) or _busy() or tsec < 420.0 or tsec >= 1080.0:
		return
	_campus_t -= dt
	if _campus_t > 0.0:
		return
	var gap: Array = CFG["campus_gap"]
	_campus_t = _rng.randf_range(float(gap[0]), float(gap[1]))
	var kinds := campus_kinds()
	if kinds.is_empty():
		return
	if _day() >= 4 and _rng.randf() < 0.6:
		return
	var indoor := String(_c.get("scene", "")) != "out"
	_emit("campus", {"cue": kinds[_rng.randi() % kinds.size()], "pan": _rng.randf_range(-0.8, 0.8), "k": 0.45 if indoor else 0.85, "lp": 0.35 if indoor else 1.0})


func _hush_tick() -> void:
	var nxt := float(_c.get("an_next", -1.0))
	var nxt0 := int(_c.get("an_next0", 0))
	var active := bool(_c.get("an_active", false))
	if not active and nxt > 0.0 and nxt <= 3.0 and _pre_for != nxt0 and not _busy():
		_pre_for = nxt0
		hush = 3.0
		_emit("duck", {"sec": 3.0})
	if _day() < 2 or active or not (nxt > 0.0):
		return
	var lead: Array = CFG["hush_lead"]
	if nxt > float(lead[1]) or nxt < float(lead[0]) or _hush_for == nxt0:
		return
	_hush_for = nxt0
	if _busy() or _hash("hush:%d:%d" % [_day(), nxt0]) >= float(CFG["hush_chance"]):
		return
	hush = float(CFG["hush_sec"])
	_emit("duck", {"sec": hush})
	_note("hush", 0)


# ---- A3 ----

func _clear_revisit() -> void:
	var d := _dread()
	if d != null:
		d.clear_revisit()


func _stare_tick() -> void:
	var r := floor_room()
	if r.is_empty() or r.get("host") != "teach":
		_last_cls = ""
		return
	var p := cell(r)
	var cls := class_at(r, p.x, p.y)
	if cls == _last_cls:
		return
	_last_cls = cls
	if cls.is_empty():
		return
	if _day() < 2 or float(_c.get("viol", 0.0)) >= 35.0 or _busy():
		return
	var key := "%d:%s" % [_day(), cls]
	var today := 0
	for k: String in stares:
		if k.begins_with("%d:" % _day()) and int(stares[k]) > 0:
			today += 1
	if int(stares.get(key, -1)) > 0 or today >= int(CFG["stare_max"]):
		return
	# A return can change one other seat. It consumes the same daily and regional budget as turning.
	if int(left.get(cls, 0)) == _day() and _hash("seat:" + key) < 0.35:
		if not _allow(1):
			return
		seats[key] = 1 + floori(_hash("seatN:" + key) * 7.0)
		stares[key] = 2
		_note("vacancy", 1, {"cls": cls})
		_clear_revisit()
		return
	if int(stares.get(key, -1)) == 0:
		return
	if _hash("stare:" + key) >= float(CFG["stare_chance"]):
		stares[key] = 0
		return
	var ci := int(cls.split(":")[1])
	var span: Array = ClassmatesModule.SPANS[ci]
	var spot := Vector2(float(r["ox"]) + (int(span[0]) + 5) * float(r["tw"]), float(r["oy"]) + 11.0 * float(r["th"]))
	var me := _me()
	if cos(atan2(spot.y - me.y, spot.x - me.x) - float(_c.get("ang", 0.0))) < 0.15:
		return
	if not _allow(1):
		return
	stares[key] = 1
	stare = {"cls": cls, "room": r["id"], "t": 0.0}
	_note("stare", 1, {"cls": cls})
	_clear_revisit()
	_emit("dread", {"cue": "chair", "place": {"pan": 0.0, "k": 0.45, "muffled": false, "behind": false, "m": 0.0}})


func _left_tick() -> void:
	var r := floor_room()
	if r.is_empty():
		return
	var p := cell(r)
	var cls := class_at(r, p.x, p.y)
	if not _in_cls.is_empty() and _in_cls != cls:
		left[_in_cls] = _day()
	_in_cls = cls


# ---- A4 ----

func _window_tick() -> void:
	var r := floor_room()
	if r.is_empty() or r.get("host") != "teach":
		_last_win = ""
		return
	var p := cell(r)
	var cls := class_at(r, p.x, p.y)
	if cls == _last_win:
		return
	_last_win = cls
	if cls.is_empty() or (not window.is_empty() and window["cls"] == cls):
		return
	var d := _dread()
	if not stare.is_empty() or float(_c.get("tsec", 0.0)) < 420.0 or _busy() or float(_c.get("age", 0.0)) < 90.0:
		return
	var visit := 1
	if d != null:
		visit = maxi(1, int(d.visits.get("%d:%s" % [_day(), r["id"]], 1)))
	if _hash("win:%d:%s:%d" % [_day(), cls, visit]) >= float(CFG["window_chance"]) or not _allow(1):
		return
	window = {"room": r["id"], "cls": cls, "seed": _hash("winP:%d:%s:%d" % [_day(), cls, visit]), "seen": 0.0, "gone": false}
	if not _window_anchor.is_empty(): window["anchor"] = _window_anchor.duplicate()
	_note("window", 1)


# ---- A6 ----

func _shift_tick() -> void:
	var r := floor_room()
	if r.is_empty() or _day() < 2:
		return
	var key := "%d:%s" % [_day(), r["id"]]
	if shift.has(key):
		return
	if not _c.has("prop") or _c["prop"] == null or not bool(_c.get("prop_ok", false)) or _busy():
		return
	if _hash("shift:" + key) >= float(CFG["shift_chance"]):
		shift[key] = 0
		return
	if not _allow(1):
		return
	var age := float(_c.get("age", 0.0))
	var patrol: bool = not _pat_seen.is_empty() and _pat_seen["room"] == r["id"] and age - float(_pat_seen["t"]) < 8.0
	var spot: Vector2 = _c["prop"]
	var me := _me()
	var dx: float = float(_pat_seen["dx"]) if patrol else me.x - spot.x
	var dy: float = float(_pat_seen["dy"]) if patrol else me.y - spot.y
	var len := maxf(0.0001, Vector2(dx, dy).length())
	shift_pose[key] = {"dx": dx / len, "dy": dy / len, "angle": atan2(dx, dy)}
	shift[key] = "push" if patrol else "face"
	_note("shift", 1, {"kind": shift[key]})
	if _hash("shiftS:" + key) < 0.5:
		_emit("dread", {"cue": "chair", "place": {"pan": 0.0, "k": 0.3, "muffled": false, "behind": true, "m": 0.0}})
	_shift_new = key


func _shift_notice() -> void:
	if _shift_new.is_empty() or said.has("shift"):
		return
	if bool(_c.get("sees_shifted", false)):
		said["shift"] = 1
		_shift_new = ""
		_emit("say", {"text": "我：……拖把刚才不在这儿吧？"})


## Real seconds; called only in normal play.
func tick(dt: float) -> void:
	if not (dt > 0.0):
		return
	hush = maxf(0.0, hush - dt)
	var pat: Dictionary = _c.get("pat", {})
	var spot: Variant = _c.get("prop")
	if not _pat_last.is_empty() and spot is Vector2 and not pat.is_empty() and bool(pat.get("walk", false)) \
			and pat.get("room") == _c.get("scene") and _pat_last.get("room") == pat.get("room") \
			and Vector2(float(pat["x"]), float(pat["y"])).distance_to(spot as Vector2) < 18.0:
		var dx := float(pat["x"]) - float(_pat_last["x"])
		var dy := float(pat["y"]) - float(_pat_last["y"])
		if Vector2(dx, dy).length() > 0.001:
			_pat_seen = {"room": pat["room"], "t": float(_c.get("age", 0.0)), "dx": dx, "dy": dy}
	_pat_last = {"room": pat.get("room"), "x": float(pat.get("x", 0.0)), "y": float(pat.get("y", 0.0))} if not pat.is_empty() else {}
	if not stare.is_empty():
		stare["t"] = float(stare["t"]) + dt
		if _busy() or stare["room"] != _c.get("scene") or float(_c.get("viol", 0.0)) >= 35.0 \
				or float(stare["t"]) >= 2.0 * float(CFG["stare_turn"]) + float(CFG["stare_hold"]):
			stare = {}
	if not window.is_empty() and not bool(window["gone"]):
		if _busy():
			window = {}
		elif window_look:
			window["seen"] = float(window["seen"]) + dt
		elif float(window["seen"]) >= 0.8:
			window["gone"] = true
	_scene_tick(dt)
	_campus_tick(dt)
	_hush_tick()
	_left_tick()
	_stare_tick()
	_window_tick()
	_shift_tick()
	_shift_notice()


## Entering a room: the per-room trackers start over.
func enter(room: String) -> void:
	_last_cls = ""
	_last_win = ""
	_in_cls = ""
	if not window.is_empty() and window["room"] != room:
		window = {}
	stare = {}
	_sc_event = {}


# ---- timed small scenes (sensory/scenes.js) ----

func _place_at(w: Vector2) -> Dictionary:
	var d := _dread()
	return d.place(w) if d != null else {"pan": 0.0, "k": 0.5, "muffled": false, "behind": false, "m": 0.0}


func _scene_lamp() -> bool:
	var lamps: Array = _c.get("lamps", [])
	var r: Dictionary = _rooms.get(String(_c.get("scene", "")), {})
	if _busy() or float(_c.get("age", 0.0)) < 60.0 or not _allow(1) or r.is_empty() or r.get("flags", {}).get("stairwell", false) or lamps.is_empty():
		return false
	var i := _rng.randi() % lamps.size()
	var lamp: Vector2 = lamps[i]
	var doors: Array = []
	var grid: Array = r["grid"]
	for row in grid.size():
		for col in String(grid[row]).length():
			if String(grid[row]).substr(col, 1) == "=":
				doors.append(CampusGeometry.tile_center(r, col, row))
	if doors.is_empty():
		return false
	doors.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_to(lamp) < b.distance_to(lamp))
	_sc_event = {"kind": "lamp", "at": _sc_clock, "room": _c.get("scene"), "index": i, "door": doors[0], "moved": false}
	_note("lamp-hum", 1)
	_emit("dread", {"cue": "hum", "place": _place_at(lamp)})
	return true


## A door was opened or closed by the player (key "room:c:r").
func door_action(room: String, c: int, row: int, open: bool) -> void:
	var r: Dictionary = _rooms.get(room, {})
	if r.is_empty():
		return
	var pos := CampusGeometry.tile_center(r, c, row)
	if open:
		if _sc_event.get("kind", "") == "door" and _sc_event["room"] == room and (_sc_event["pos"] as Vector2).is_equal_approx(pos):
			_sc_event = {}
		return
	if _busy() or float(_c.get("age", 0.0)) < 60.0 or not _allow(1) or not _sc_event.is_empty():
		return
	var key := "%s:%d:%d" % [room, c, row]
	if _sc_doors.has(key) and _sc_clock - float(_sc_doors[key]) < 120.0:
		return
	if _rng.randf() > 0.30:
		return
	_sc_doors[key] = _sc_clock
	_sc_event = {"kind": "door", "at": _sc_clock, "room": room, "pos": pos}
	_note("door-answer", 1)


func _scene_tick(dt: float) -> void:
	if _busy():
		_sc_event = {}
		return
	_sc_clock += minf(0.25, dt)
	if not _sc_event.is_empty():
		if _sc_event["room"] != _c.get("scene"):
			_sc_event = {}
			return
		var elapsed := _sc_clock - float(_sc_event["at"])
		if _sc_event["kind"] == "door" and elapsed >= 1.4:
			_emit("dread", {"cue": "knock", "place": _place_at(_sc_event["pos"])})
			_sc_event = {}
		elif _sc_event["kind"] == "lamp":
			if elapsed >= 3.0 and not bool(_sc_event["moved"]):
				_sc_event["moved"] = true
				_emit("dread", {"cue": "hum", "place": _place_at(_sc_event["door"])})
			if elapsed >= 7.0:
				_sc_event = {}
	elif _sc_clock >= _sc_next:
		_sc_next = _sc_clock + 85.0 / (1.0 + 0.08 * float(_c.get("stage", 0))) + _rng.randf() * 40.0
		_scene_lamp()


## The lamp scene's multiplier for room light i: dims over 2 s, holds low, comes back after 5 s.
func lamp_mul() -> Dictionary:
	if _sc_event.get("kind", "") != "lamp":
		return {}
	var t := _sc_clock - float(_sc_event["at"])
	return {int(_sc_event["index"]): (1.0 - t * 0.44 if t < 2.0 else (0.12 + (t - 5.0) * 0.44 if t > 5.0 else 0.12))}


func scene_event() -> Dictionary:
	return _sc_event


# ---- A5: bell ----

## {tail, tailLength, caption}: only the eighth note changes; the start bell never changes.
func bell_tune(kind: String, tsec: float) -> Dictionary:
	if kind == "start":
		return {}
	var drops: Array = CFG["bell_drop"]
	var d := _day()
	var semi := float(drops[mini(drops.size() - 1, d - 1)])
	var night := tsec >= float(CFG["night_bell_at"])
	if night and d >= 2:
		semi += float(CFG["night_bell_drop"])
	if not (semi > 0.0):
		return {}
	return {"tail": pow(2.0, -semi / 12.0), "tailLength": 1.8 if night and d >= 2 else 1.0,
		"caption": "下课铃，拖得很长，最后一个音沉了下去" if night else "下课铃，最后一个音低了一点"}


# ---- A7: sky and tint ----

static func _smooth(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## {dusk, cold, tint [r,g,b], fog}: multipliers the lighting applies (day light × (1−dusk), ambient × cold…).
static func light_mods(day: int, tsec: float) -> Dictionary:
	var h := fposmod(tsec, 1440.0) / 60.0
	var k := minf(1.0, float(day - 1) / 2.0)
	var dusk := k * 0.35 * _smooth(15.5, 18.0, h) * (1.0 - _smooth(19.5, 20.5, h))
	var cold := 1.0 - 0.07 * k
	var warm := 0.10 * _smooth(15.0, 17.0, h) * (1.0 - _smooth(17.5, 19.0, h))
	var cool := 0.04 * k + 0.10 * _smooth(17.5, 21.0, h)
	return {"dusk": dusk, "cold": cold, "tint": [1.0 + warm - cool, 1.0 - cool * 0.2, 1.0 - warm + cool],
		"fog": 1.0 + 0.10 * _smooth(16.0, 22.0, h) + k * 0.07}


# ---- A2: dark stretch of corridor lamps ----

## Lamp indexes (of a floor's corridor lights) that are dead, fixed by room id and run seed.
static func dark_lamps(room: Dictionary, lamp_rows: Array) -> Dictionary:
	if room.is_empty() or not ["teach", "admin", "lab"].has(String(room.get("host", ""))) or room.get("floor") == null:
		return {}
	var fl := int(room["floor"])
	if fl < 1 or fl > 5 or room.get("flags", {}).get("stairwell", false):
		return {}
	var door := -1
	var grid: Array = room["grid"]
	for y in grid.size():
		if String(grid[y]).contains("="):
			door = y
	var set: Array = []
	for i in lamp_rows.size():
		var row := int(lamp_rows[i])
		if row > door and row < grid.size() - 1:
			set.append(i)
	if set.size() > 1:
		var keep := floori(DreadModule.lhash("dark-section:" + String(room["id"]) + ":" + seed) * set.size())
		var kept: Array = []
		for j in set.size():
			if j == keep or (j + 1) % 3 == keep % 3:
				kept.append(set[j])
		set = kept
	var out := {}
	for i: int in set:
		out[i] = true
	return out
