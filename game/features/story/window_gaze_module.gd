class_name WindowGazeModule
extends FeatureModule
## The gaze behind a window, ported from the Web version (reference wd-fz.github.io@0bf508a,
## modules/window-gaze/gaze.js WG): only on real outer-wall windows of the admin, lab, dorm,
## canteen, guard and gear buildings. A breath behind the glass, a still figure and a pair of eyes;
## looking at it within 12° from 2–18 m for 0.35 s catches the eye: the view is pulled towards the
## window (it can be broken by looking down 35° or away 28° for 0.6 s, or by a wall), SAN drains 2 a
## second and 4 after 2 s; drained to zero it is the window gaze death. First chance after 240 s of
## play, then every 300–480 s; it waits for anomalies, chases, checks and hiding.

const STATE_VERSION := 1
const FIRST := 240.0
const GAP := [300.0, 480.0]
const LIFE := 28.0
const NEAR := 2.0
const FAR := 18.0
const CONE := 12.0
const HOLD := 0.35
const BREAK_ANG := 28.0
const BREAK_DOWN := 35.0
const BREAK_HOLD := 0.6
const PULL := 1.1
const DRAIN := 2.0
const DRAIN_HARD := 4.0
const HARD_AFTER := 2.0
const EYE := 1.62
const HOSTS := ["admin", "lab", "dormN", "dormS", "canteen", "guard"]
const TALL := "#S=dKbf"

var s: Dictionary = {}
var events: Array = []
var _rooms: Dictionary = {}
var _c: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _cache: Dictionary = {}


func _init(rooms: Dictionary = {}) -> void:
	_rooms = rooms


func module_id() -> StringName:
	return &"story.window_gaze"


func state_version() -> int:
	return STATE_VERSION


func reset() -> void:
	s = {"next": FIRST, "ev": null, "n": 0, "escaped": 0}
	events = []


func set_seed(value: int) -> void:
	_rng.seed = value


func capture() -> Dictionary:
	return {"random": RandomState.capture(_rng), "next": s["next"], "n": s["n"], "escaped": s["escaped"]}


func validate(data: Dictionary) -> String:
	return "" if SaveSchema.number_in(data.get("next", 0.0), 0, 1e9) else "窗内视线状态无效"


func restore(data: Dictionary) -> void:
	reset()
	RandomState.restore(_rng, data)
	s["next"] = float(data["next"])
	s["n"] = int(data.get("n", 0))
	s["escaped"] = int(data.get("escaped", 0))


## ctx: scene, x, y, ang, pitch (radians, up positive), eye (metres above floor), now (active seconds), busy, san, drain_mul, dead.
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


func windows(room_id: String) -> Array:
	if _cache.has(room_id):
		return _cache[room_id]
	var list: Array = []
	var r: Dictionary = _rooms.get(room_id, {})
	if not r.is_empty() and (HOSTS.has(r.get("host")) or room_id == "gear1"):
		var grid: Array = r["grid"]
		var w := int(r["cols"])
		var h := int(r["rows"])
		for side in 2:
			var rr := h - 1 if side == 1 else 0
			var inner := h - 2 if side == 1 else 1
			var nz := -1 if side == 1 else 1
			var x := 2
			while x < w - 2:
				var row := String(grid[rr])
				var irow := String(grid[inner])
				var ok := row.substr(x, 1) == "#" and row.substr(x - 1, 1) == "#" and row.substr(x + 1, 1) == "#"
				var ic := irow.substr(x, 1)
				if ok and not (ic == "#" or ic == "S" or ic == "O" or irow.substr(x - 1, 1) in ["#", "S"] or irow.substr(x + 1, 1) in ["#", "S"]):
					list.append({"c": x, "r": rr, "nz": nz, "p": Vector2(float(r["ox"]) + (x + 0.5) * float(r["tw"]), float(r["oy"]) + float(h - 1 if side == 1 else 1) * float(r["th"]))})
				x += 3
	_cache[room_id] = list
	return list


func _clear(room_id: String, win: Dictionary) -> bool:
	var r: Dictionary = _rooms[room_id]
	var grid: Array = r["grid"]
	var p0 := Vector2((float(_c.get("x", 0.0)) - float(r["ox"])) / float(r["tw"]), (float(_c.get("y", 0.0)) - float(r["oy"])) / float(r["th"]))
	var wp: Vector2 = win["p"]
	var p1 := Vector2((wp.x - float(r["ox"])) / float(r["tw"]), (wp.y - float(r["oy"])) / float(r["th"]) + float(win["nz"]) * 0.15)
	var n := int(ceil(p0.distance_to(p1) * 3.0))
	for i in range(1, n):
		var t := float(i) / n
		var c := int(floor(lerpf(p0.x, p1.x, t)))
		var row := int(floor(lerpf(p0.y, p1.y, t)))
		if row >= 0 and row < grid.size() and c >= 0 and c < String(grid[row]).length() and TALL.contains(String(grid[row]).substr(c, 1)):
			return false
	return true


func geom(win: Dictionary) -> Dictionary:
	var wp: Vector2 = win["p"]
	var d2 := (wp - Vector2(float(_c.get("x", 0.0)), float(_c.get("y", 0.0)))) * CampusGeometry.U2M
	var dz := EYE - float(_c.get("eye", 1.65))
	var d := d2.length()
	var p := float(_c.get("pitch", 0.0))
	var a := float(_c.get("ang", 0.0))
	var v := Vector3(cos(p) * cos(a), cos(p) * sin(a), sin(p))
	var len := maxf(0.0001, Vector2(d, dz).length())
	var dot := (v.x * d2.x + v.y * d2.y + v.z * dz) / len
	return {"d": d, "ang": rad_to_deg(acos(clampf(dot, -1.0, 1.0))), "yaw": atan2(d2.y, d2.x), "pitch": atan2(dz, d)}


func current() -> Dictionary:
	var e: Variant = s["ev"]
	if e == null or String(_c.get("scene", "")) != String(e["room"]):
		return {}
	for w: Dictionary in windows(String(e["room"])):
		if int(w["c"]) == int(e["c"]) and int(w["r"]) == int(e["r"]):
			return {"e": e, "w": w}
	return {}


func _start() -> bool:
	var scene := String(_c.get("scene", ""))
	var cand: Array = windows(scene).filter(func(w: Dictionary) -> bool:
		var g := geom(w)
		return float(g["d"]) >= NEAR + 1.0 and float(g["d"]) <= FAR and float(g["ang"]) > 25.0 and _clear(scene, w))
	if cand.is_empty():
		return false
	var w: Dictionary = cand[_rng.randi() % cand.size()]
	s["n"] = int(s["n"]) + 1
	s["ev"] = {"room": scene, "c": w["c"], "r": w["r"], "t": 0.0, "contact": 0.0, "pull": 0.0, "away": 0.0, "pulled": false, "escaped": false}
	_emit("breath", {"p": w["p"]})
	_emit("fact", {"what": "start"})
	return true


func _stop(why: String) -> void:
	var e: Variant = s["ev"]
	if e == null:
		return
	if bool(e["pulled"]) and why != "death" and not bool(e["escaped"]):
		e["escaped"] = true
		s["escaped"] = int(s["escaped"]) + 1
		_emit("fact", {"what": "escape"})
	s["ev"] = null
	s["next"] = float(_c.get("now", 0.0)) + GAP[0] + _rng.randf() * (GAP[1] - GAP[0])
	if why == "end":
		_emit("notice", {"text": "我：窗玻璃上留下一块雾。雾上没有掌纹。"})


func tick(dt: float) -> void:
	if not (dt > 0.0) or bool(_c.get("dead", false)):
		return
	var scene := String(_c.get("scene", ""))
	if s["ev"] == null:
		if not windows(scene).is_empty() and float(_c.get("now", 0.0)) >= float(s["next"]) and not bool(_c.get("busy", false)):
			if not _start():
				s["next"] = float(_c.get("now", 0.0)) + 20.0
		return
	var cur := current()
	if cur.is_empty():
		_stop("left")
		return
	var e: Dictionary = cur["e"]
	var w: Dictionary = cur["w"]
	e["t"] = float(e["t"]) + dt
	if float(e["t"]) >= LIFE and float(e["pull"]) <= 0.0:
		_stop("end")
		return
	var g := geom(w)
	var see := _clear(scene, w) and float(g["d"]) >= NEAR and float(g["d"]) <= FAR
	if not see:
		e["pull"] = 0.0
		e["contact"] = 0.0
		e["away"] = 0.0
		if bool(e["pulled"]):
			_stop("blocked")
		return
	if float(e["pull"]) <= 0.0:
		e["contact"] = float(e["contact"]) + dt if float(g["ang"]) < CONE else 0.0
		if float(e["contact"]) >= HOLD:
			e["pull"] = 0.001
			e["pulled"] = true
			_emit("fact", {"what": "contact"})
			_emit("notice", {"text": "我：……窗里有一双眼睛。我挪不开眼。"})
		return
	var away := float(g["ang"]) > BREAK_ANG or float(_c.get("pitch", 0.0)) < -deg_to_rad(BREAK_DOWN)
	e["away"] = float(e["away"]) + dt if away else 0.0
	if float(e["away"]) >= BREAK_HOLD:
		_stop("escape")
		_emit("notice", {"text": "我：我低着头退开了。那双眼睛没有跟过来。"})
		return
	e["pull"] = float(e["pull"]) + dt
	if away:
		return
	var k := minf(1.0, PULL * dt)
	var dy := wrapf(float(g["yaw"]) - float(_c.get("ang", 0.0)), -PI, PI)
	_emit("pull", {"yaw": clampf(dy, -k, k), "pitch": clampf(float(g["pitch"]) - float(_c.get("pitch", 0.0)), -k * 0.6, k * 0.6)})
	var rate := DRAIN_HARD if float(e["pull"]) > HARD_AFTER else DRAIN
	var loss := rate * dt * float(_c.get("drain_mul", 1.0))
	if float(_c.get("san", 100.0)) - loss <= 0.0:
		_emit("san_zero")
		_emit("kill", {"msg": "窗里那双眼睛一直没有眨。我也是。", "fx": "gaze", "source": "window_gaze"})
		return
	_emit("san", {"amount": -loss, "min": 0.0})


## The death killed (or a rescue happened): the eyes go away.
func after_kill(dead: bool) -> void:
	_stop("death" if dead else "saved")
