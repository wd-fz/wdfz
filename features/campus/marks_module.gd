class_name MarksModule
extends FeatureModule
## Chalk marks and the last life, ported from the Web version (reference wd-fz.github.io@0bf508a):
## modules/chalk-marks/marks.js (use the chalk: a mark on the wall ahead when looking level, on the
## floor ahead when looking down — eight symbols; using it on an existing mark erases it; marks stay
## with the save, at most 80 a room and 240 in all) and modules/last-life/last-life.js (the place and
## time of the last run's death shows as a faint chalk × in the next run; an ending clears it).

const STATE_VERSION := 1
const SYMS := [["x", "X"], ["up", "↑"], ["o", "O"], ["left", "←"], ["right", "→"], ["tri", "△"], ["q", "?"], ["bar", "正"]]
const MAX := 240
const PER_ROOM := 80
const REACH := 1.45
const FLOOR_REACH := 2.0
const ERASE_R := 0.75
const LOOK_DOWN := -0.32
const U2M := CampusGeometry.U2M

var marks: Array = []
var serial := 0
var last_life: Variant = null   # {scene, x, y, tsec, day} copied in at the start of the run
var events: Array = []
var _c: Dictionary = {}
var _pending: Dictionary = {}


func module_id() -> StringName:
	return &"campus.marks"


func state_version() -> int:
	return STATE_VERSION


func reset() -> void:
	marks = []
	serial = 0
	last_life = null
	events = []
	_pending = {}


func capture() -> Dictionary:
	return {"marks": marks.duplicate(true), "serial": serial, "last_life": last_life}


func validate(data: Dictionary) -> String:
	return "" if data.get("marks", []) is Array else "粉笔记号无效"


func restore(data: Dictionary) -> void:
	reset()
	for m: Variant in data.get("marks", []):
		if m is Dictionary and _sym(String(m.get("s", ""))) != "" and m.get("face") in ["floor", "wall"]:
			marks.append(m)
	serial = int(data.get("serial", marks.size()))
	last_life = data.get("last_life") if data.get("last_life") is Dictionary else null


## ctx: scene, x, y, ang, pitch, solid (Callable(Vector2) -> bool), has_chalk.
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


func _say(text: String) -> void:
	_emit("notice", {"text": text})


static func _sym(id: String) -> String:
	for s: Array in SYMS:
		if s[0] == id:
			return s[1]
	return ""


func _solid(p: Vector2) -> bool:
	var f: Callable = _c.get("solid", Callable())
	return f.is_valid() and bool(f.call(p))


## Where the crosshair points: the wall ahead when looking level, the floor ahead when looking down.
func target() -> Dictionary:
	var me := Vector2(float(_c.get("x", 0.0)), float(_c.get("y", 0.0)))
	var a := float(_c.get("ang", 0.0))
	var dir := Vector2(cos(a), sin(a))
	var pitch := float(_c.get("pitch", 0.0))
	var step := 0.05 / U2M
	if pitch > LOOK_DOWN:
		var last := 0.0
		var hit := -1.0
		var d := step
		while d <= REACH / U2M:
			if _solid(me + dir * d):
				hit = d
				break
			last = d
			d += step
		if hit < 0.0:
			return {}
		var wall_a := PI if absf(dir.x) > absf(dir.y) and dir.x > 0.0 else (0.0 if absf(dir.x) > absf(dir.y) else (-PI * 0.5 if dir.y > 0.0 else PI * 0.5))
		var h := clampf(1.65 + tan(pitch) * last * U2M, 0.35, 2.3)
		var p := me + dir * last
		return {"face": "wall", "x": p.x, "y": p.y, "h": h, "a": wall_a, "room": String(_c.get("scene", ""))}
	var down := maxf(0.12, -pitch)
	var dist := minf(FLOOR_REACH, 1.65 / tan(down)) / U2M
	var fp := me + dir * dist
	var back := 0
	while back < 6 and _solid(fp):
		fp -= dir * 0.2 / U2M
		back += 1
	if _solid(fp):
		return {}
	return {"face": "floor", "x": fp.x, "y": fp.y, "h": 0.0, "a": a, "room": String(_c.get("scene", ""))}


func _near_mark(t: Dictionary) -> int:
	var best := -1
	var bd := ERASE_R / U2M
	for i in marks.size():
		var m: Dictionary = marks[i]
		if m["room"] != t["room"] or m["face"] != t["face"]:
			continue
		if absf(float(m["h"]) - float(t["h"])) > (0.8 if t["face"] == "wall" else 0.6):
			continue
		var d := Vector2(float(m["x"]), float(m["y"])).distance_to(Vector2(float(t["x"]), float(t["y"])))
		if d < bd:
			bd = d
			best = i
	return best


## Use the chalk (from the bag): pick a symbol, or erase the mark there.
func use_chalk() -> bool:
	if not bool(_c.get("has_chalk", false)):
		_emit("toast", {"text": "没有粉笔"})
		return false
	var t := target()
	if t.is_empty():
		_say("我：够不着能画的地方。走近一面墙，或者低头看着地面。")
		return false
	var near := _near_mark(t)
	var labels: Array = []
	for s: Array in SYMS:
		labels.append("画「%s」" % s[1])
	if near >= 0:
		labels.append("擦掉这里的「%s」" % _sym(String(marks[near]["s"])))
	_pending = {"t": t, "near": near}
	_emit("choice", {"text": "在墙上画什么？" if t["face"] == "wall" else "在地上画什么？", "labels": labels})
	return true


func choose(index: int) -> void:
	var p := _pending
	_pending = {}
	if p.is_empty() or index < 0:
		return
	var t: Dictionary = p["t"]
	if index < SYMS.size():
		place(String(SYMS[index][0]), t)
		_say("我：在%s画了个「%s」。" % ["墙上" if t["face"] == "wall" else "地上", SYMS[index][1]])
		_emit("save")
	elif int(p["near"]) >= 0:
		marks.remove_at(int(p["near"]))
		_say("我：用袖子把记号擦掉了，只剩一片白印。")
		_emit("changed")
		_emit("save")


func place(sym: String, t: Dictionary) -> Dictionary:
	if _sym(sym) == "":
		return {}
	serial += 1
	var m := {"room": t["room"], "x": snappedf(float(t["x"]), 0.01), "y": snappedf(float(t["y"]), 0.01), "h": snappedf(float(t["h"]), 0.001),
		"face": t["face"], "a": snappedf(float(t["a"]), 0.0001), "s": sym, "n": serial}
	marks.append(m)
	var in_room: Array = marks.filter(func(q: Dictionary) -> bool: return q["room"] == m["room"])
	if in_room.size() > PER_ROOM:
		marks.erase(in_room[0])
	while marks.size() > MAX:
		marks.pop_front()
	_emit("fact", {"sym": sym})
	_emit("changed")
	return m


func visible(room: String) -> Array:
	return marks.filter(func(m: Dictionary) -> bool: return m["room"] == room)
