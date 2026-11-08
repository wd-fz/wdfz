class_name PaperPlaneModule
extends FeatureModule
## Paper planes and "the one who flies them", ported from the Web version (reference
## wd-fz.github.io@0bf508a, modules/paper-plane/paper.js PAPER_CFG): rolled once per run (10 %,
## half peaceful, half dangerous); after 150 s of play, in a room with outer windows (the same
## windows as the window gaze) a plane flies out of a visible window 3–14 m away and lands in front
## of the player. Peaceful: a note with a true tip (item 'paper'). Dangerous: pick it up within 8 s,
## read it within 8 s, aim at that window within 4 s, then steer it (W/S/A/D) back through the window
## (1.4 m wide, 1.0–2.25 m high) without touching walls, the floor or the ceiling, within distance ÷
## speed + 6 s; failing brings footsteps and, 4 s later, the paper sender death.

const STATE_VERSION := 1
const CHANCE := 0.10
const DANGER := 0.5
const MIN_RUN := 150.0
const NEAR := 3.0
const FAR := 14.0
const FLY_IN := 2.4
const WAIT := 8.0
const READ := 8.0
const AIM := 4.0
const SPEED := 2.6
const TURN := 1.7
const PITCH_MAX := 0.35
const SINK := 0.12
const SLACK := 6.0
const HUNT := 4.0
const CALM := 20.0
const WIN_HALF := 0.7
const WIN_LOW := 1.0
const WIN_HIGH := 2.25
const U2M := CampusGeometry.U2M
const TALL := "#S=dKbf"
const FURNITURE := "dTtkfblVqnRcpxKCNZYXDwBGQvAHM" # original FURN_SOLID keys, including patrol additions
const TIPS := ["学生会十二点五十、五点五十各查一次座位。坐在自己的位子上就行。", "食堂饭点以外，打饭窗口要一枚硬币。", "熄灯以后别在走廊里待太久。巡察者夜里也在走。", "听见窗后有呼吸声，就别往窗那边看。"]
const DANGER_TEXT := "他还在那扇窗后等。读完就折好，别留在手里。\n送回有缺角的那扇窗，转弯别碰墙。"
const FAIL_LINES := {"wall": "纸飞机一头撞在墙上，折痕裂开了。", "floor": "纸飞机栽到了地上。", "ceiling": "纸飞机撞上了天花板。", "timeout": "纸飞机在半空里停了一下，掉了下来。",
	"drop": "我把纸扔在了地上。", "wait": "我没有去捡那架纸飞机。", "read": "我还没读完，纸在手里皱了。", "aim": "我没能把纸投出去。", "lost": "那扇窗不见了。"}

var s: Dictionary = {}
var events: Array = []
var _rooms: Dictionary = {}
var _windows: WindowGazeModule
var _c: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var text_override: Callable


func _init(rooms: Dictionary = {}) -> void:
	_rooms = rooms
	_windows = WindowGazeModule.new(rooms)


func module_id() -> StringName:
	return &"story.paper_plane"


func state_version() -> int:
	return STATE_VERSION


func reset() -> void:
	s = {"roll": null, "ev": null, "used": false, "calm_until": 0.0}
	events = []


## A new run rolls once.
func roll(seed_value: int) -> void:
	_rng.seed = seed_value
	var u := _rng.randf()
	s["roll"] = {"hit": u < CHANCE, "kind": "danger" if u < CHANCE * DANGER else "peace"}


func capture() -> Dictionary:
	return {"roll": s["roll"], "used": s["used"], "calm_until": s["calm_until"], "random": RandomState.capture(_rng)}


func validate(_data: Dictionary) -> String:
	return ""


func restore(data: Dictionary) -> void:
	reset()
	RandomState.restore(_rng, data)
	s["roll"] = data.get("roll")
	s["used"] = bool(data.get("used", false))
	s["calm_until"] = float(data.get("calm_until", 0.0))


## ctx: scene, x, y, ang, now, busy, can_stand (Callable), dead, steer {l, r, u, d}.
func set_context(ctx: Dictionary) -> void:
	_c = ctx
	_windows.set_context(ctx)


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


func _me() -> Vector2:
	return Vector2(float(_c.get("x", 0.0)), float(_c.get("y", 0.0)))


func window_of(e: Dictionary) -> Dictionary:
	for w: Dictionary in _windows.windows(String(e["room"])):
		if int(w["c"]) == int(e["c"]) and int(w["r"]) == int(e["r"]):
			return w
	return {}


## Calm after a returned plane keeps the window gaze away for 20 s.
func calm(now: float) -> bool:
	return s["ev"] != null or now < float(s["calm_until"])


func start(kind: String) -> bool:
	var scene := String(_c.get("scene", ""))
	var cand: Array = _windows.windows(scene).filter(func(w: Dictionary) -> bool:
		var d := _me().distance_to(w["p"]) * U2M
		return d >= NEAR and d <= FAR and _windows._clear(scene, w))
	if cand.is_empty():
		return false
	var land := Vector2.INF
	var can: Callable = _c.get("can_stand", Callable())
	for a: float in [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6]:
		var ang := float(_c.get("ang", 0.0)) + a
		var p := _me() + Vector2(cos(ang), sin(ang)) * (1.4 / U2M)
		if not can.is_valid() or bool(can.call(p)):
			land = p
			break
	if land == Vector2.INF:
		return false
	var w: Dictionary = cand[_rng.randi() % cand.size()]
	s["used"] = true
	s["ev"] = {"kind": kind, "room": scene, "c": w["c"], "r": w["r"], "phase": "fly", "t": 0.0, "lx": land.x, "ly": land.y,
		"text": DANGER_TEXT if kind == "danger" else TIPS[_rng.randi() % TIPS.size()]}
	if text_override.is_valid():
		var replacement: Variant=text_override.call(kind)
		if replacement is String: s["ev"]["text"]=replacement
	_emit("fact", {"what": "delivery", "kind": kind})
	_say("（窗那边 · 两下拍窗）" if kind == "danger" else "（纸擦过地面的轻响）")
	return true


func _end(why: String) -> void:
	s["ev"] = null
	if why == "returned":
		s["calm_until"] = float(_c.get("now", 0.0)) + CALM


func near_paper() -> bool:
	var e: Variant = s["ev"]
	return e != null and e["phase"] in ["ground", "wait"] and String(_c.get("scene", "")) == e["room"] and _me().distance_to(Vector2(float(e["lx"]), float(e["ly"]))) * U2M < 1.3


func hint() -> String:
	var e: Variant = s["ev"]
	if e == null:
		return ""
	if near_paper():
		return "地上的纸飞机"
	if e["phase"] == "aim":
		return "对准那扇窗投出"
	return ""


func phase() -> String:
	return String(s["ev"]["phase"]) if s["ev"] != null else ""


## E: pick up, or throw at the window.
func use_here() -> bool:
	var e: Variant = s["ev"]
	if e == null:
		return false
	if near_paper():
		if e["kind"] == "peace":
			_emit("give", {"id": "paper", "text": e["text"]})
			return true
		e["phase"] = "read"
		e["t"] = 0.0
		_emit("read", {"text": e["text"]})
		_emit("fact", {"what": "picked"})
		return true
	if e["phase"] == "aim":
		var w := window_of(e)
		if w.is_empty():
			fail("lost")
			return true
		var to: Vector2 = w["p"] - _me()
		if absf(wrapf(atan2(to.y, to.x) - float(_c.get("ang", 0.0)), -PI, PI)) >= 0.45:
			_say("我：先对准那扇窗。")
			return true
		_launch(w)
		return true
	return false


## The peaceful note was put in the bag (or not).
func gave(ok: bool) -> void:
	var e: Variant = s["ev"]
	if e == null:
		return
	if not ok:
		_say("我：背包满了。纸飞机还在地上。")
		return
	_say("我：纸飞机里面写着一行字：\n「%s」" % e["text"])
	_emit("record", {"id": "paperNote", "text": "窗口飞来的纸飞机：「%s」" % e["text"], "kind": "线索", "source": ""})
	_emit("fact", {"what": "received"})
	_end("peace")


func fold() -> void:
	var e: Variant = s["ev"]
	if e == null or e["phase"] != "read":
		return
	e["phase"] = "aim"
	e["t"] = 0.0
	_emit("fact", {"what": "read"})
	_say("我：我把纸按原来的折痕折好。那扇窗还开着一条缝。")


func _launch(w: Dictionary) -> void:
	var e: Dictionary = s["ev"]
	var d := _me().distance_to(w["p"]) * U2M
	e["phase"] = "flight"
	e["t"] = 0.0
	e["limit"] = d / SPEED + SLACK
	var a := float(_c.get("ang", 0.0))
	e["f"] = {"x": _me().x + cos(a) * 0.45 / U2M, "y": _me().y + sin(a) * 0.45 / U2M, "h": 1.45, "yaw": a, "pitch": 0.0, "clean": true}
	_emit("fact", {"what": "launch"})


func fail(why: String) -> void:
	var e: Variant = s["ev"]
	if e == null or e["phase"] == "hunt":
		return
	e["phase"] = "hunt"
	e["t"] = 0.0
	_emit("fact", {"what": "failed", "why": why})
	_say("我：%s\n窗后那只手缩了回去。楼梯那边，脚步声响了起来。" % FAIL_LINES.get(why, ""))
	_emit("steps")


func _solid(r: Dictionary, p: Vector2, h: float) -> bool:
	var c := int(floor((p.x - float(r["ox"])) / float(r["tw"])))
	var row := int(floor((p.y - float(r["oy"])) / float(r["th"])))
	var grid: Array = r["grid"]
	if row < 0 or row >= grid.size() or c < 0 or c >= String(grid[row]).length():
		return true
	var ch := String(grid[row]).substr(c, 1)
	if TALL.contains(ch):
		return true
	return h < 0.85 and FURNITURE.contains(ch)


func _fly_step(e: Dictionary, w: Dictionary, r: Dictionary, dt: float) -> String:
	var f: Dictionary = e["f"]
	var steer: Dictionary = _c.get("steer", {})
	var tl := float(steer.get("r", 0.0)) - float(steer.get("l", 0.0))
	var tu := float(steer.get("u", 0.0)) - float(steer.get("d", 0.0))
	f["yaw"] = float(f["yaw"]) + clampf(tl, -1.0, 1.0) * TURN * dt
	var target := clampf(tu, -1.0, 1.0) * PITCH_MAX
	f["pitch"] = float(f["pitch"]) + clampf(target - float(f["pitch"]), -1.5 * dt, 1.5 * dt)
	var v := SPEED / U2M
	var cp := cos(float(f["pitch"]))
	var nx := float(f["x"]) + cos(float(f["yaw"])) * cp * v * dt
	var ny := float(f["y"]) + sin(float(f["yaw"])) * cp * v * dt
	var nh := float(f["h"]) + (SPEED * sin(float(f["pitch"])) - SINK) * dt
	var wp: Vector2 = w["p"]
	var nz := float(w["nz"])
	var crossed := (float(f["y"]) > wp.y and ny <= wp.y) if nz > 0.0 else (float(f["y"]) < wp.y and ny >= wp.y)
	if crossed:
		var t := (wp.y - float(f["y"])) / (ny - float(f["y"]))
		var cx := float(f["x"]) + (nx - float(f["x"])) * t
		var ch := float(f["h"]) + (nh - float(f["h"])) * t
		if absf(cx - wp.x) * U2M <= WIN_HALF and ch >= WIN_LOW and ch <= WIN_HIGH:
			return "in"
	f["x"] = nx
	f["y"] = ny
	f["h"] = nh
	if nh < 0.05:
		return "floor"
	if nh > 2.85:
		return "ceiling"
	if _solid(r, Vector2(nx, ny), nh):
		return "wall"
	var side := Vector2(-sin(float(f["yaw"])), cos(float(f["yaw"]))) * 0.3 / U2M
	if bool(f["clean"]) and (_solid(r, Vector2(nx, ny) + side, nh) or _solid(r, Vector2(nx, ny) - side, nh)):
		f["clean"] = false
		_say("（纸翼擦着墙）")
	return ""


func tick(dt: float) -> void:
	if not (dt > 0.0) or bool(_c.get("dead", false)):
		return
	var e: Variant = s["ev"]
	if e == null:
		var rl: Variant = s["roll"]
		if rl is Dictionary and bool(rl["hit"]) and not bool(s["used"]) and float(_c.get("now", 0.0)) >= MIN_RUN and not bool(_c.get("busy", false)):
			start(String(rl["kind"]))
		return
	e["t"] = float(e["t"]) + dt
	var here: bool = String(_c.get("scene", "")) == e["room"]
	match String(e["phase"]):
		"fly":
			if float(e["t"]) >= FLY_IN:
				e["phase"] = "wait" if e["kind"] == "danger" else "ground"
				e["t"] = 0.0
		"ground":
			if not here and float(e["t"]) > 1.0:
				_end("left")
		"wait":
			if float(e["t"]) >= WAIT:
				fail("wait")
		"read":
			if float(e["t"]) >= READ:
				fail("read")
		"aim":
			if float(e["t"]) >= AIM:
				fail("aim")
		"flight":
			var w := window_of(e)
			if w.is_empty() or not _rooms.has(String(e["room"])):
				fail("lost")
				return
			var res := ""
			for _i in 4:
				res = _fly_step(e, w, _rooms[String(e["room"])], dt / 4.0)
				if res != "":
					break
			if res == "in":
				var clean := bool(e["f"]["clean"])
				_emit("fact", {"what": "returned", "clean": clean})
				_say("我：纸飞机钻进窗缝。窗后那只手接住了它，缩了回去。\n玻璃上留下一块雾，没有掌纹。")
				_end("returned")
			elif res != "":
				fail(res)
			elif float(e["t"]) >= float(e["limit"]):
				fail("timeout")
		"hunt":
			if float(e["t"]) >= HUNT:
				_end("death")
				_emit("kill", {"msg": "他来取回没有送到的东西。", "fx": "grip", "source": "paper_sender"})
