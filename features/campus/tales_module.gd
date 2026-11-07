class_name TalesModule
extends FeatureModule
## Two campus tales, ported from the Web version (reference wd-fz.github.io@0bf508a,
## modules/campus-tales): the midnight canteen (canteen.js MidnightCanteen: after lights out one lit
## window serves one bowl a night, +40 SAN, +25 assimilation up to 95, and assimilation does not
## fall back until 07:20) and the late mirror (mirror.js MirrorLag: the mirrors over the teaching
## building's basins answer by SAN tier; below 20 the reflection raises a hand first and staring
## at it for 3 s more is the mirror death). The duty roster texture, the patrol log pages and the
## checkup day are not ported.

const STATE_VERSION := 1
const MEAL := {"san": 40.0, "tt": 25.0, "tt_cap": 95.0, "min": 10.0, "room": "canteen1"}
const MIRROR := {"near": 2.6, "face": 0.6, "stare_die": 3.0}

var meal: Dictionary = {}       # {night, until, n}
var raise := 0.0
var stare := 0.0
var events: Array = []

var _rooms: Dictionary = {}
var _c: Dictionary = {}
var _pending := ""
var _spots: Dictionary = {}


func _init(rooms: Dictionary = {}) -> void:
	_rooms = rooms


func module_id() -> StringName:
	return &"campus.tales"


func state_version() -> int:
	return STATE_VERSION


func reset() -> void:
	meal = {}
	raise = 0.0
	stare = 0.0
	events = []
	_pending = ""


func capture() -> Dictionary:
	return {"meal": meal.duplicate()}


func validate(data: Dictionary) -> String:
	return "" if data.get("meal", {}) is Dictionary else "校园怪谈状态无效"


func restore(data: Dictionary) -> void:
	reset()
	meal = (data.get("meal", {}) as Dictionary).duplicate()


## ctx: scene, x, y, ang, tsec, clock (game minutes), san, tt, dead.
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


func _me() -> Vector2:
	return Vector2(float(_c.get("x", 0.0)), float(_c.get("y", 0.0)))


# ---- the midnight canteen ----

func canteen_open() -> bool:
	return float(_c.get("tsec", 0.0)) >= SchoolClock.LIGHTS_OUT


func night() -> int:
	return int(floor((float(_c.get("clock", 0.0)) - 1000.0) / 1440.0))


func ate() -> bool:
	return not meal.is_empty() and int(meal.get("night", -999)) == night()


func near_window() -> bool:
	if String(_c.get("scene", "")) != MEAL["room"] or not canteen_open() or not _rooms.has(MEAL["room"]):
		return false
	var r: Dictionary = _rooms[MEAL["room"]]
	var grid: Array = r["grid"]
	for row in grid.size():
		for col in String(grid[row]).length():
			if String(grid[row]).substr(col, 1) == "k":
				var p := Vector2(float(r["ox"]) + (col + 0.5) * float(r["tw"]), float(r["oy"]) + (row + 0.5) * float(r["th"]))
				if _me().distance_to(p) < 3.2 * float(r["tw"]):
					return true
	return false


func hint() -> String:
	if near_window():
		return "窗口（「明天再来」）" if ate() else "亮着的窗口"
	return ""


func use_here() -> bool:
	if not near_window():
		return false
	if ate():
		_say("我：窗口里的人没有回头。「明天再来。」")
		return true
	_pending = "meal"
	_emit("choice", {"text": "熄了灯的食堂，只有这一个窗口亮着。打饭的人背对着我，台子上放着一碗热的。\n闻起来很香。香得不对。", "labels": ["吃一碗（游戏时间 %d 分钟）" % int(MEAL["min"]), "不吃"]})
	return true


func choose(index: int) -> void:
	if _pending != "meal":
		return
	_pending = ""
	if index != 0:
		_say("我：我往后退了一步。它还是没有回头。")
		return
	_emit("advance", {"minutes": float(MEAL["min"])})
	_emit("san", {"amount": float(MEAL["san"]), "max": 100.0})
	_emit("tt", {"amount": float(MEAL["tt"]), "cap": maxf(float(MEAL["tt_cap"]), float(_c.get("tt", 0.0)))})
	var n := int(meal.get("n", 0)) + 1
	meal = {"night": night(), "until": float(night() + 1) * 1440.0 + 440.0, "n": n}
	_emit("hold", {"until": float(meal["until"])})
	_emit("stamina", {"amount": 30.0})
	_say("我：吃完了。很好吃，是我在这里吃过最好吃的一顿。\n……我想不起来刚才为什么那么怕了。我想早点回宿舍，躺在自己的铺上。明天早上不用闹钟。")
	_emit("toast", {"text": "吃了一碗 · 到天亮前同化不会回落"})
	_emit("fact", {"n": n})


# ---- the late mirror ----

static func tier_of(san: float) -> int:
	return 0 if san >= 70.0 else (1 if san >= 40.0 else (2 if san >= 20.0 else 3))


## Mirrors: basins ('w') in the teaching building next to a wall; the normal points into the room.
func mirrors(scene: String) -> Array:
	if _spots.has(scene):
		return _spots[scene]
	var out: Array = []
	var r: Dictionary = _rooms.get(scene, {})
	if not r.is_empty() and r.get("host") == "teach":
		var grid: Array = r["grid"]
		for row in range(1, grid.size() - 1):
			for col in range(1, String(grid[row]).length() - 1):
				if String(grid[row]).substr(col, 1) != "w":
					continue
				for d: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
					if String(grid[row + d.y]).substr(col + d.x, 1) == "#":
						out.append({"w": Vector2(float(r["ox"]) + (col + 0.5) * float(r["tw"]), float(r["oy"]) + (row + 0.5) * float(r["th"])), "n": Vector2(-d.x, -d.y)})
						break
	_spots[scene] = out
	return out


func tick(dt: float) -> void:
	if not (dt > 0.0) or bool(_c.get("dead", false)):
		return
	var best: Dictionary = {}
	var bd := INF
	for m: Dictionary in mirrors(String(_c.get("scene", ""))):
		var d := _me().distance_to(m["w"]) * CampusGeometry.U2M
		if d < bd:
			bd = d
			best = m
	if best.is_empty() or bd > float(MIRROR["near"]) * 1.6:
		stare = 0.0
		raise = maxf(0.0, raise - dt * 2.0)
		return
	var ang := float(_c.get("ang", 0.0))
	var n: Vector2 = best["n"]
	var facing := -(cos(ang) * n.x + sin(ang) * n.y)
	var see := bd < float(MIRROR["near"]) and facing > float(MIRROR["face"])
	var t := tier_of(float(_c.get("san", 100.0)))
	raise = minf(1.0, raise + dt * 0.9) if t >= 3 and see else maxf(0.0, raise - dt * 2.0)
	if t >= 3 and raise >= 0.95 and see:
		stare += dt
		if stare >= float(MIRROR["stare_die"]):
			stare = 0.0
			_emit("kill", {"msg": "镜子里那个，先动的手。", "fx": "mirror", "source": "mirror"})
	else:
		stare = 0.0
