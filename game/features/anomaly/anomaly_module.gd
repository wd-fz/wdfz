class_name AnomalyModule
extends FeatureModule
## Anomaly scheduler and the rules of the 26 anomalies, ported from anomaly.js (reference
## wd-fz.github.io@0bf508a). Context in (player state), events out (notice / hurt / san / kill /
## violation / remove_item / advance_time / choice / turn / clue); the app applies them.
##
## Not ported yet: the on-screen effects (fx/anomaly-fx.js, fx/cup.js, fx/cola.js, traces, the smile
## face, the blackboard / roster / wall paper models), their sounds, exam mode, the fake-normal
## second day, talents and the umbrella. The rules, numbers, timings and messages are the old ones.

const STATE_VERSION := 1
const U2M := CampusGeometry.U2M
const SC := 2.0
const CUP_H := 10.6
const CUP_R := 0.95
const CUP_WOB := {"easy": 0.85, "normal": 0.60, "hard": 0.40}
const COLA_H := 14.0
const COLA_R := 0.85
const COLA_WARN := 1.6
const COLA_SETTLE := 2.5
const TURN_SMILE_P := 0.25
const FEAST_NORMAL := 9.0
## DEFS: w weight, small, cool (game minutes), lethal, warn (foretold before it happens), rained,
## late (not in the first-day dream), exam, dfx death scene, cn the name in forecasts.
const DEFS := {
	"blackout": {"w": 0.5, "small": true, "cool": 180.0, "dfx": "lamps", "cn": "楼里的灯全灭了", "msg": "我：灯一盏接一盏灭了。走廊尽头也暗下来，只剩自己的呼吸。"},
	"rain": {"w": 0.26, "lethal": true, "warn": true, "rained": true, "cool": 260.0, "dfx": "drown", "cn": "下不完的雨",
		"msg": "我：天一下子暗了。雨不是从云里落下来的——它从很高的地方垂下来，像有人在上面一桶一桶地倒。"},
	"moth": {"w": 0.24, "lethal": true, "warn": true, "late": true, "rained": true, "cool": 200.0, "dfx": "swarm", "cn": "蛾群",
		"msg": "我：灯下面聚了一团飞蛾。不对，不是一团。是一整面墙。它们在往我这边挪。"},
	"turn": {"w": 0.5, "small": true, "dfx": "gaze", "cn": "有人在我背后拍了一下", "msg": "……有人从后面拍了一下我的肩膀。很轻。手指是湿的。"},
	"broad": {"w": 0.75, "small": true, "exam": true, "dfx": "voice", "cn": "广播点名", "msg": "广播：「沙……高二（二）班的同学，请你……留在原地。不要走动。」"},
	"bell13": {"w": 0.85, "dfx": "bell", "cn": "钟敲十三下", "msg": "我：钟响了。一下，两下……我下意识地开始数。"},
	"exercise": {"w": 0.85, "lethal": true, "dfx": "follow", "cn": "操场做操的人", "msg": "我：操场上有一群人在做操。动作整齐得过分。领操台上没有人。"},
	"bells": {"w": 0.75, "dfx": "shatter", "cn": "车棚所有铃一起响", "msg": "我：车棚里所有的车铃，在同一刻响了起来。没有风。"},
	"hand": {"w": 0.9, "small": true, "dfx": "hand", "cn": "隔间底下伸来的手", "msg": "我：隔间底下的缝里，伸出来一只手。手心朝上，指甲缝里是黑的。"},
	"repeat": {"w": 0.9, "exam": true, "dfx": "gaze", "cn": "你作业交了吗", "msg": "后桌（贴着我的后脑勺）：「……你作业，交了吗？」"},
	"chalk": {"w": 0.42, "small": true, "exam": true, "dfx": "chalk", "cn": "黑板上的「下一次」", "msg": "我：黑板上，有人在写字。粉笔自己在动。"},
	"loop": {"w": 1.0, "small": true, "dfx": "loop", "cn": "无尽的走廊", "msg": "我：走廊尽头那扇门……我已经第三次走到它面前了。"},
	"roster": {"w": 0.42, "small": true, "exam": true, "dfx": "names", "cn": "被划掉的名字", "msg": "我：墙上多了一张名单。纸是新的。上面有我的名字——被一道红线划掉了。"},
	"leak": {"w": 0.55, "small": true, "dfx": "water", "cn": "天花板渗水", "msg": "我：天花板在往下滴水。今天没有下雨。水是温的。"},
	"rite": {"w": 0.85, "lethal": true, "late": true, "dfx": "ring", "cn": "实验楼仪式现场",
		"msg": "我：地上有一个粉笔画的圈，线还很新。圈里摆着四根白蜡烛。圈的正中，空着一个人的位置。"},
	"cold": {"w": 0.9, "small": true, "dfx": "freeze", "cn": "冷库", "msg": "我：食堂最东边那扇门后面冷得像冰柜。门缝里，有什么东西在轻轻地敲。"},
	"shifting": {"w": 0.9, "small": true, "exam": true, "dfx": "twin", "cn": "窗外的楼在动", "msg": "我：窗外的楼……在动。很慢，一栋一栋地挪。"},
	"stare": {"w": 0.95, "exam": true, "dfx": "stare", "cn": "全体回头", "msg": "我：全班同时回过头来看着我。没有人眨眼。"},
	"lamps": {"w": 0.9, "small": true, "dfx": "lamps", "cn": "熄灯后的走廊灯", "msg": "我：走廊的灯一盏一盏亮了起来。它在跟着我。"},
	"feast": {"w": 0.5, "dfx": "deep", "cn": "食堂的盛宴", "msg": "我：食堂里摆了一长桌菜，还冒着热气。每一副碗筷前面，都有一张写着名字的纸条。"},
	"necker": {"w": 0.7, "lethal": true, "late": true, "dfx": "neck", "cn": "围墙外的行人", "msg": "我：围墙外面有个人在走。我走他也走，我停他也停。他的脖子……太长了。"},
	"shadow": {"w": 0.8, "small": true, "dfx": "shadow", "cn": "影子慢一拍", "msg": "我：我的影子慢了半拍。它刚刚，自己动了一下。"},
	"twin": {"w": 0.55, "lethal": true, "late": true, "dfx": "twin", "cn": "天台的第二个你", "msg": "我：天台的另一头站着一个人。穿着我们学校的校服。他站的姿势，和我一模一样。"},
	"raindots": {"w": 0.32, "rained": true, "dfx": "water", "cn": "雨点落成的字", "msg": "我：雨点落在地上，没有散开。它们在排队。"},
	"cup": {"w": 0.8, "lethal": true, "warn": true, "cool": 150.0, "dfx": "floor", "cn": "清华水杯",
		"msg": "我：头顶上叮叮当当地响。抬头——四楼的窗台上，一只白色的杯子在晃，盖子是淡紫色的。"},
	"cola": {"w": 0.0, "warn": true, "dfx": "floor", "cn": "天降可乐", "msg": "我：头顶很高的地方「哐啷」一声，像有人踢翻了一个易拉罐。它还在滚。"},
}
const IDS := ["blackout", "rain", "moth", "turn", "broad", "bell13", "exercise", "bells", "hand", "repeat", "chalk", "loop", "roster", "leak",
	"rite", "cold", "shifting", "stare", "lamps", "feast", "necker", "shadow", "twin", "raindots", "cup", "cola"]

var an: Dictionary = {}
var hist: Array = []
var seen: Dictionary = {}
var pre_told := false
var cola_pending: Variant = null
var cola_seq := 0
var cola_done := 0
var cola_wait := 0.0
var clues: Dictionary = {}
var events: Array = []

var _c: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _outside: Dictionary = {}
var _rooms: Dictionary = {}
var _campus: Dictionary = {}


func _init(rooms: Dictionary = {}, outside: Dictionary = {}, campus: Dictionary = {}) -> void:
	_rooms = rooms
	_outside = outside
	_campus = campus


func module_id() -> StringName:
	return &"anomaly.world"


func state_version() -> int:
	return STATE_VERSION


func reset() -> void:
	traces = []
	an = {"id": "", "t": 0.0, "acc": 0.0, "next": 60.0, "data": {}, "rained": false, "cool": {}, "lastBig": false, "active": false,
		"sub": 0, "pre": "", "locked": false, "preNext": 0.0, "lockWait": false, "next0": 0}
	hist = []
	seen = {}
	pre_told = false
	cola_pending = null
	cola_seq = 0
	cola_done = 0
	cola_wait = 0.0
	clues = {}
	events = []
	_c = {}
	_rng.randomize()


func set_seed(value: int) -> void:
	_rng.seed = value


## Game.start: the first anomaly comes after 40 s on 梦魇, 60 s on 预知梦.
func begin_run(diff: String) -> void:
	an["next"] = 40.0 if diff == "hard" else 60.0


func capture() -> Dictionary:
	return {"an": an.duplicate(true), "hist": hist.duplicate(), "seen": seen.duplicate(), "pre_told": pre_told, "cola_pending": cola_pending,
		"cola_seq": cola_seq, "cola_done": cola_done, "cola_wait": cola_wait, "clues": clues.duplicate(), "traces": traces.duplicate(true), "rng_seed": str(_rng.seed), "rng_state": str(_rng.state)}


func validate(data: Dictionary) -> String:
	var a: Variant = data.get("an")
	if not a is Dictionary or not String(a.get("id", "")) in IDS + [""] or not a.get("active") is bool or not a.get("data") is Dictionary:
		return "异象状态无效"
	for key: String in ["t", "acc", "next", "preNext"]:
		if not SaveSchema.number_in(a.get(key), -1e6, 1e6):
			return "异象计时无效：%s" % key
	if not a.get("cool") is Dictionary or not data.get("hist") is Array or not data.get("seen") is Dictionary:
		return "异象记录无效"
	for id: Variant in data["hist"]:
		if not id is String or (not DEFS.has(id) and id != "_"):
			return "异象历史无效"
	if not String(data.get("rng_state", "")).is_valid_int():
		return "异象随机状态无效"
	var tr: Variant = data.get("traces", [])
	if not tr is Array or (tr as Array).size() > TRACE_MAX:
		return "异象痕迹无效"
	for t: Variant in tr:
		if not t is Dictionary or not String(t.get("k", "")) in TRACE_KINDS or not String(t.get("room", "")) is String:
			return "异象痕迹无效"
	return ""


func restore(data: Dictionary) -> void:
	an = data["an"].duplicate(true)
	hist = data["hist"].duplicate()
	seen = data["seen"].duplicate()
	pre_told = bool(data.get("pre_told", false))
	traces = (data.get("traces", []) as Array).duplicate(true)
	cola_pending = data.get("cola_pending")
	cola_seq = int(data.get("cola_seq", 0))
	cola_done = int(data.get("cola_done", 0))
	cola_wait = float(data.get("cola_wait", 0.0))
	clues = data.get("clues", {}).duplicate()
	an["sub"] = int(an.get("sub", 0))
	an["next0"] = int(an.get("next0", 0))
	# A choice that was open when saving is asked again.
	if an["active"] and an["data"].get("asked", false) and an["data"].get("chosen") == null:
		an["data"]["asked"] = false
	_rng.seed = int(String(data.get("rng_seed", "0")))
	_rng.state = int(String(data["rng_state"]))
	events = []


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


func _say(text: String, force: bool = false) -> void:
	_emit("notice", {"text": text, "force": force})


func _rnd(a: float, b: float) -> float:
	return a + _rng.randf() * (b - a)


func _hard() -> bool:
	return String(_c.get("diff", "easy")) == "hard"


func is_active() -> bool:
	return bool(an["active"])


func active_id() -> String:
	return String(an["id"])


## Lighting: the blackout switches the room lamps off, the rains press the sky down.
func blackout_now() -> bool:
	return bool(an["active"]) and an["id"] == "blackout"


func overcast_target() -> float:
	return 1.0 if bool(an["active"]) and an["id"] in ["rain", "raindots"] else 0.0


## The foretold anomaly is on the blackboard / a quiet "I dreamt this time" line (anNotifyWarning).
func warning_seen(visible_now: bool) -> void:
	if visible_now and String(_c.get("diff", "easy")) == "easy" and an["pre"] != "" and not pre_told:
		pre_told = true
		_say("我：这个时间……我梦见过。")


func warning_visible() -> bool:
	return not bool(an["active"]) and an["pre"] != "" and DEFS[an["pre"]].get("warn", false) and _allowed(String(an["pre"])) and float(an["next"]) > 0.0


# ---- place predicates (anomaly.js helpers) ----

func _in_room() -> bool:
	return String(_c.get("scene", "")) != "out"


func _room() -> Variant:
	return _rooms.get(String(_c.get("scene", "")))


func _wall_room() -> bool:
	var r: Variant = _room()
	return r != null and not r["flags"].get("stairwell", false)


func _corridor_here() -> bool:
	var r: Variant = _room()
	if r == null or r["host"] != "teach" or r.get("floor") == null or int(r["floor"]) > 5:
		return false
	var row := int(floor((float(_c["y"]) - float(r["oy"])) / float(r["th"])))
	return row >= 16 and row <= 20


func _in_lab() -> bool:
	var r: Variant = _room()
	return r != null and r["host"] == "lab"


func _in_toilet() -> bool:
	var r: Variant = _room()
	if r == null:
		return false
	var t := String(_c.get("tile", ""))
	if t == "B" or t == "G":
		return true
	if r["host"] == "teach":
		var c := int(floor((float(_c["x"]) - float(r["ox"])) / float(r["tw"])))
		var rr := int(floor((float(_c["y"]) - float(r["oy"])) / float(r["th"])))
		return c >= 58 and c <= 61 and rr >= 16 and rr <= 19
	return false


func _in_canteen() -> bool:
	return String(_c.get("scene", "")) == "canteen1"


func _on_roof() -> bool:
	return String(_c.get("scene", "")) == "teach6"


func _in_classroom() -> bool:
	return bool(_c.get("in_classroom", false))


func _obj(id: String) -> Dictionary:
	for o: Dictionary in _outside.get("objects", []):
		if o["id"] == id:
			return o
	return {}


func _near_obj(id: String) -> float:
	var o := _obj(id)
	if o.is_empty():
		return 99999.0
	var cx := float(o["x"]) * SC + float(o["w"]) * SC / 2.0
	var cy := float(o["y"]) * SC + float(o["h"]) * SC / 2.0
	return Vector2(float(_c["x"]) - cx, float(_c["y"]) - cy).length()


## The nearest tall building's outer wall for the falling cup (teach / admin / lab).
func _cup_wall() -> Dictionary:
	if String(_c.get("scene", "")) != "out":
		return {}
	var mx := float(_c["x"]) / SC
	var my := float(_c["y"]) / SC
	var best := {}
	for id: String in ["teach", "admin", "lab"]:
		var o := _obj(id)
		if o.is_empty():
			continue
		var px := clampf(mx, float(o["x"]), float(o["x"]) + float(o["w"]))
		var py := clampf(my, float(o["y"]), float(o["y"]) + float(o["h"]))
		var dd := Vector2(mx - px, my - py).length()
		if dd > 0.01 and (best.is_empty() or dd < float(best["d"])):
			best = {"x": px, "y": py, "d": dd, "id": id}
	if not best.is_empty():
		best["m"] = float(best["d"]) * SC * U2M
	return best


func under_roof() -> bool:
	if _in_room():
		return true
	var mx := float(_c["x"]) / SC
	var my := float(_c["y"]) / SC
	for o: Dictionary in _outside.get("objects", []):
		var x := float(o["x"])
		var y := float(o["y"])
		var w := float(o["w"])
		var h := float(o["h"])
		if o["k"] == "link" and mx > x and mx < x + w and my > y and my < y + h:
			return true
		if o.get("open1f", false) and mx > x and mx < x + w and my > y + h and my < y + h + 12.0:
			return true
		if o["id"] == "shed" and mx > x - 3.0 and mx < x + w + 3.0 and my > y - 3.0 and my < y + h + 3.0:
			return true
	return false


func under_cover() -> bool:
	if _in_room():
		return true
	if bool(_c.get("brolly", false)):
		return true
	return under_roof()


func _ahead_point(dist: float) -> Vector2:
	var tries := [0.0, 0.6, -0.6, 1.2, -1.2, PI]
	var can: Callable = _c.get("can_stand", Callable())
	for t: float in tries:
		var a := float(_c["ang"]) + t
		var p := Vector2(float(_c["x"]) + cos(a) * dist, float(_c["y"]) + sin(a) * dist)
		if not can.is_valid() or bool(can.call(p)):
			return p
	return Vector2(float(_c["x"]), float(_c["y"]))


func _when(id: String) -> bool:
	var tsec := float(_c.get("tsec", 700.0))
	match id:
		"blackout":
			return _in_room() and String(_c["scene"]) != "teach6"
		"rain":
			return not _in_room() and String(_c.get("need_where", "")) != "教室"
		"moth", "raindots":
			return bool(an["rained"])
		"turn":
			return true
		"broad", "leak":
			return _in_room()
		"bell13":
			var r: Variant = _room()
			return r != null and r["host"] in ["teach", "dormN"]
		"exercise", "shadow":
			return not _in_room() and bool(_c.get("on_field", false))
		"bells":
			return _near_obj("shed") < 320.0
		"hand":
			return _in_toilet()
		"repeat", "shifting", "stare":
			return _in_classroom()
		"chalk", "roster":
			return _wall_room()
		"loop":
			return _corridor_here()
		"rite":
			return _in_lab()
		"cold":
			return _in_canteen()
		"lamps":
			return _corridor_here() and bool(_c.get("night", false))
		"feast":
			if not _in_canteen():
				return false
			for m: Array in _campus.get("meals", [[735, 800], [1060, 1090]]):
				if tsec >= float(m[0]) and tsec < float(m[1]):
					return true
			return false
		"necker":
			return not _in_room() and float(_c["x"]) > (float(_campus.get("bound_map", {}).get("x1", 830)) - 220.0) * SC
		"twin":
			return _on_roof()
		"cup":
			var cw := _cup_wall()
			return not cw.is_empty() and float(cw["m"]) < 2.4 and not under_roof()
	return false


func _allowed(id: String) -> bool:
	return DEFS.has(id) and _when(id)


# ---- picking and pacing ----

func _pick() -> String:
	var pool: Array = []
	var clock := float(_c.get("game_clock", 0.0))
	for id: String in IDS:
		if not _allowed(id):
			continue
		var cool: Variant = DEFS[id].get("cool")
		if cool != null and an["cool"].has(id) and clock - float(an["cool"][id]) < float(cool):
			continue
		pool.append(id)
	if pool.is_empty():
		return ""
	var preferred: Array = []
	if String(_c.get("need_where", "")) == "教室":
		for id: String in pool:
			if DEFS[id].get("small", false):
				preferred.append(id)
	if preferred.size() >= 3 and _rng.randf() < 0.8:
		pool = preferred
	if int(_c.get("day", 1)) == 1 and String(_c.get("diff", "easy")) == "easy":
		pool = pool.filter(func(a: String) -> bool: return not DEFS[a].get("late", false))
		if pool.is_empty():
			return ""
	var last: String = hist[hist.size() - 1] if not hist.is_empty() else ""
	if pool.size() > 1:
		pool = pool.filter(func(a: String) -> bool: return a != last)
	elif pool[0] == last:
		return ""
	var recent := hist.slice(maxi(0, hist.size() - 4))
	var fresh: Array = pool.filter(func(a: String) -> bool: return recent.count(a) < 2)
	if fresh.is_empty():
		hist.append("_")
		hist = hist.slice(maxi(0, hist.size() - 6))
		return ""
	pool = fresh
	if hist.is_empty() and pool.has("chalk"):
		return "chalk"
	var total := 0.0
	var weights: Array = []
	for id: String in pool:
		var w := float(DEFS[id].get("w", 1.0))
		if w == 0.0:
			w = 1.0
		if DEFS[id].get("small", false):
			w *= 1.25
		if recent.has(id):
			w *= 0.35
		if not seen.has(id):
			w *= 2.2
		weights.append(w)
		total += w
	var r := _rng.randf() * total
	var acc := 0.0
	for i in pool.size():
		acc += weights[i]
		if r < acc:
			return pool[i]
	return pool[pool.size() - 1]


func _interval() -> float:
	var base := _rnd(24.0, 40.0) if _hard() else _rnd(40.0, 64.0)
	base *= 0.62 + 0.38 * clampf(float(_c.get("san", 100.0)), 0.0, 100.0) / 100.0
	base *= 1.0 - clampf(float(_c.get("viol", 0.0)), 0.0, 100.0) / 260.0
	if an["lastBig"]:
		base *= 1.25
	var r: Variant = _room()
	if r != null and r["flags"].get("principal", false):
		base *= 0.5
	return maxf(10.0, base * float(_c.get("pressure_anomaly", 1.0)))


func _schedule_next() -> void:
	if float(an["preNext"]) == 0.0 or an["pre"] == "":
		an["pre"] = _pick()
	an["next"] = _interval()
	an["next0"] = int(an["next0"]) + 1
	if float(an["preNext"]) > 0.0:
		an["next"] = an["preNext"]
		an["preNext"] = 0.0


func _start() -> void:
	var id := ""
	var planned := String(an["pre"])
	var forced: bool = String(_c.get("diff", "easy")) == "easy" or bool(an["locked"]) or (planned != "" and DEFS[planned].get("warn", false))
	if forced and planned != "":
		if _allowed(planned):
			id = planned
		elif an["locked"] and not an["lockWait"]:
			an["lockWait"] = true
			an["next"] = 4.0
			return
	an["locked"] = false
	an["lockWait"] = false
	an["pre"] = ""
	if id.is_empty():
		id = _pick()
	if id.is_empty():
		_schedule_next()
		an["next"] = minf(float(an["next"]), 6.0)
		return
	if DEFS[id].get("warn", false) and id != planned:
		an["pre"] = id
		an["next"] = 8.0
		return
	an["id"] = id
	an["t"] = 0.0
	an["acc"] = 0.0
	an["active"] = true
	an["data"] = {"scene": String(_c.get("scene", ""))}
	an["sub"] = 0
	if id == "cup":
		_cola_owe()
	hist.append(id)
	hist = hist.slice(maxi(0, hist.size() - 6))
	seen[id] = true
	an["lastBig"] = not DEFS[id].get("small", false)
	if DEFS[id].has("cool") or DEFS[id].get("rained", false):
		an["cool"][id] = float(_c.get("game_clock", 0.0))
	if DEFS[id].get("rained", false):
		an["rained"] = true
	_say(String(DEFS[id]["msg"]))
	_on(id)


## What an anomaly leaves on the ground (app/traces.js traceAdd): a puddle where the rain fell, stains of the leak, the remains of
## the chalk circle, dead moths, footprint rows, paper, a handprint, a fence, a bowl, chalk dust, the dented cup. Kept in the save,
## at most 40 (the oldest go). room "" means outdoors; outdoor positions are old world units. The picture is game/presentation/world/campus/traces.gd.
const TRACE_KINDS := ["puddle", "stain", "chalkring", "moths", "rows", "feet", "paper", "handprint", "fence", "bowl", "dust", "cup"]
const TRACE_MAX := 40
var traces: Array = []


func trace_for(id: String, d: Dictionary, me: Vector2, scene: String, fence_x: float) -> Dictionary:
	var t: Dictionary = {}
	if id == "rain" or id == "raindots":
		t = {"k": "puddle", "x": me.x, "y": me.y}
	elif id == "leak" and d.has("pts"):
		var pts: Array = []
		for p: Variant in (d["pts"] as Array).slice(0, 5):
			pts.append({"x": float(p["x"]), "y": float(p["y"])})
		t = {"k": "stain", "pts": pts}
	elif id == "rite" and d.has("c"):
		t = {"k": "chalkring", "x": float(d["c"]["x"]), "y": float(d["c"]["y"])}
	elif id == "moth" and d.has("src"):
		t = {"k": "moths", "x": float(d["src"]["x"]), "y": float(d["src"]["y"])}
	elif id == "exercise" and d.has("src"):
		t = {"k": "rows", "x": float(d["src"]["x"]), "y": float(d["src"]["y"])}
	elif id == "twin" and d.has("x"):
		t = {"k": "feet", "x": float(d["x"]), "y": float(d["y"]), "a": atan2(me.y - float(d["y"]), me.x - float(d["x"]))}
	elif id == "roster" and d.has("rx"):
		t = {"k": "paper", "x": float(d["rx"]), "y": float(d["ry"])}
	elif id == "hand":
		t = {"k": "handprint", "x": me.x, "y": me.y}
	elif id == "necker":
		t = {"k": "fence", "x": fence_x, "y": me.y}
	elif id == "feast":
		t = {"k": "bowl", "x": me.x, "y": me.y}
	elif id == "chalk":
		t = {"k": "dust", "x": me.x, "y": me.y}
	elif id == "cup" and int(d.get("phase", 0)) == 2 and d.has("lx"):
		t = {"k": "cup", "x": float(d["lx"]), "y": float(d["ly"])}
	if t.is_empty():
		return t
	t["room"] = "" if (id == "cup" or scene == "out") else scene      # the cup only lands outdoors
	return t


func _leave_trace(id: String) -> void:
	var t := trace_for(id, an["data"], Vector2(float(_c.get("x", 0.0)), float(_c.get("y", 0.0))), String(_c.get("scene", "")), float(_c.get("fence_x", 0.0)))
	if t.is_empty():
		return
	traces.append(t)
	while traces.size() > TRACE_MAX:
		traces.pop_front()


func _end() -> void:
	if not an["active"] and an["id"] == "":
		return
	var id := String(an["id"])
	_leave_trace(id)
	if id == "roster" and not an["data"].get("done", false):
		_emit("violation", {"amount": 18.0})
		_say("我：那张名单我没动。走开的时候，我听见身后有笔尖划过纸的声音。")
	var resume: Variant = an["data"].get("resume") if id == "cola" else null
	an["id"] = ""
	an["active"] = false
	an["acc"] = 0.0
	if resume != null:
		_cola_resume(resume)
	else:
		_schedule_next()


## story.js dreamWake: the running anomaly is dropped and the next one comes in 60 s.
func dream_wake() -> void:
	an["id"] = ""
	an["active"] = false
	an["data"] = {}
	an["t"] = 0.0
	an["acc"] = 0.0
	an["pre"] = ""
	an["preNext"] = 0.0
	an["locked"] = false
	an["next"] = 60.0


## Force-end (death protection, scene reset): the next anomaly is paced again.
## What the physics lab pendulum can read (interact.js useFacility 'Z').
func pendulum_info() -> Dictionary:
	var pre := String(an["pre"])
	return {"active": is_active(), "id": active_id(), "pre": pre,
		"warn_ok": pre != "" and DEFS.has(pre) and bool(DEFS[pre].get("warn", false)) and _allowed(pre),
		"minutes": maxi(1, roundi(float(an["next"]) * SchoolClock.rate_at(float(_c.get("tsec", 700.0))) / 60.0)),
		"cn": String(DEFS.get(pre, {}).get("cn", pre))}


## The pendulum read the forecast: it will come as told.
func lock_forecast() -> void:
	an["locked"] = true


func end_now() -> void:
	if an["active"]:
		_end()


func _on(id: String) -> void:
	var d: Dictionary = an["data"]
	match id:
		"rain":
			an["rained"] = true
		"moth", "exercise":
			d["src"] = {"x": float(_c["x"]), "y": float(_c["y"])}
		"turn":
			d["chosen"] = null
			d["smile"] = _rng.randf() < TURN_SMILE_P
			if d["smile"]:
				_say("我：背后有脚步声。很轻，一步一步走近……停在我身后。然后，有人拍了拍我的肩膀。很轻，像在叫我。", true)
		"hand":
			d["chosen"] = null
		"repeat", "cold":
			d["chosen"] = null
		"chalk":
			var nxt := _pick()
			if nxt != "" and DEFS[nxt].get("warn", false):
				an["pre"] = nxt
				an["locked"] = true
				an["preNext"] = _interval()
				var mins := roundi((16.0 + float(an["preNext"])) * SchoolClock.rate_at(float(_c.get("tsec", 700.0))) / 60.0)
				d["until"] = float(_c.get("tsec", 700.0)) + mins
				_say("我：黑板上写着一个时间——%s。字迹和我的一模一样。" % SchoolClock.fmt_clock(float(d["until"])), false)
			else:
				an["pre"] = ""
				an["preNext"] = 0.0
				_say("我：粉笔在黑板上写了几笔，又慢慢擦掉了。")
		"roster":
			d["rx"] = float(_c["x"])
			d["ry"] = float(_c["y"])
			d["done"] = false
		"leak":
			var pts: Array = []
			for _i in 5:
				var lp := _ahead_point(_rnd(10.0, 34.0))
				pts.append({"x": lp.x + _rnd(-14.0, 14.0), "y": lp.y + _rnd(-14.0, 14.0)})
			d["pts"] = pts
		"rite":
			var rp := _ahead_point(40.0)
			d["c"] = {"x": rp.x, "y": rp.y}
		"shadow":
			d["acc"] = 0.0
		"twin":
			var r: Variant = _room()
			if r != null:
				var cxr := float(r["ox"]) + float(r["cols"]) * float(r["tw"]) / 2.0
				var cyr := float(r["oy"]) + float(r["rows"]) * float(r["th"]) / 2.0
				var tx := cxr - (float(_c["x"]) - cxr) * 0.8
				var ty := cyr - (float(_c["y"]) - cyr) * 0.8
				var can: Callable = _c.get("can_stand", Callable())
				if can.is_valid() and not bool(can.call(Vector2(tx, ty))):
					tx = float(r["ox"]) + float(r["cols"]) * float(r["tw"]) * 0.22
					ty = float(r["oy"]) + float(r["rows"]) * float(r["th"]) * 0.25
				d["x"] = tx
				d["y"] = ty
				d["room"] = String(_c["scene"])
		"cup":
			d["wall"] = _cup_wall()
			d["phase"] = 0
			d["wob"] = float(CUP_WOB.get(String(_c.get("diff", "easy")), CUP_WOB["normal"]))
		"cola":
			d["phase"] = 0
			d["warn"] = COLA_WARN


# ---- damage helpers (anHurt / anKill / sanDrain) ----

func _drain(rate: float, dt: float) -> void:
	if rate > 0.0 and dt > 0.0:
		_emit("san", {"amount": -dt * rate * float(_c.get("drain_mul", 1.0)), "min": 0.0})


func _hurt(msg: String, loss: float, quiet: bool = false, keep: bool = false) -> void:
	var k := 1.25 if _hard() else 0.9
	_emit("hurt", {"amount": loss * k, "quiet": quiet, "msg": msg})
	if not keep:
		_end()


func _kill(msg: String, fx: String = "") -> void:
	var f := fx if not fx.is_empty() else String(DEFS.get(String(an["id"]), {}).get("dfx", "vignette"))
	_emit("kill", {"msg": msg, "fx": f, "source": "an:" + String(an["id"])})


func _ask(d: Dictionary, text: String, labels: Array, ids: Array) -> void:
	d["asked"] = true
	_emit("choice", {"text": text, "labels": labels, "ids": ids, "timeout": 5.0})


## Called by the app with the chosen id of the open choice.
func choose(id: String) -> void:
	if not an["active"]:
		return
	var d: Dictionary = an["data"]
	d["chosen"] = id
	if an["id"] == "roster":
		_roster_choice(id)


# ---- the roster wall paper (interact.js nearRoster / useRoster) ----

func near_roster() -> bool:
	if not an["active"] or an["id"] != "roster" or an["data"].get("done", false) or not an["data"].has("rx"):
		return false
	return Vector2(float(_c["x"]) - float(an["data"]["rx"]), float(_c["y"]) - float(an["data"]["ry"])).length() < 80.0


## E on the roster: with a pen or chalk write the name back; otherwise choose.
func use_roster(has_pen_or_chalk: bool) -> void:
	var d: Dictionary = an["data"]
	if has_pen_or_chalk:
		d["done"] = true
		_emit("san", {"amount": 6.0, "max": 100.0})
		_say("我：我在那道红线旁边，把自己的名字一笔一画重新写了一遍。写完以后，红线淡了。")
		_emit("clue", {"id": "roster"})
		return
	_ask(d, "名单上，我的名字被一道红线划掉了。手边没有笔。", ["把它撕下来", "用指甲把名字刻回去", "不管它"], ["tear", "scratch", "ignore"])


func _roster_choice(id: String) -> void:
	var d: Dictionary = an["data"]
	d["asked"] = false
	d.erase("chosen")
	match id:
		"tear":
			d["done"] = true
			_emit("violation", {"amount": 8.0})
			_emit("san", {"amount": -5.0, "min": 0.0})
			_say("我：纸撕下来的时候，下面还贴着一张。一模一样，连那道红线都是新的。……至少我把它撕了。")
		"scratch":
			d["done"] = true
			_emit("san", {"amount": -10.0, "min": 0.0})
			_say("我：指甲劈了。名字刻上去了，歪歪扭扭的，渗着一点红。")


# ---- the falling can (cola) ----

func _cola_owe() -> void:
	if cola_pending != null:
		return
	cola_seq += 1
	cola_pending = {"seq": cola_seq, "day": int(_c.get("day", 1)), "clock": float(_c.get("game_clock", 0.0))}


func _cola_safe() -> bool:
	if cola_pending == null or bool(_c.get("dead", false)):
		return false
	if not bool(_c.get("night", false)) or _in_room():
		return false
	if an["active"] or bool(_c.get("patrol_chase", false)) or bool(_c.get("hiding", false)):
		return false
	if bool(_c.get("inspection_quiet", false)) or bool(_c.get("choice_open", false)) or bool(_c.get("in_lift", false)):
		return false
	return true


func _cola_drive(dt: float) -> bool:
	if not _cola_safe():
		cola_wait = 0.0
		return false
	cola_wait += dt
	if cola_wait < COLA_SETTLE:
		return false
	return _cola_start()


func _cola_start() -> bool:
	var p: Variant = cola_pending
	cola_wait = 0.0
	if p == null:
		return false
	cola_pending = null
	if int(p["seq"]) <= cola_done:
		return false
	cola_done = int(p["seq"])
	var resume := {"pre": an["pre"], "next": an["next"], "locked": an["locked"], "lockWait": an["lockWait"], "preNext": an["preNext"]}
	an["id"] = "cola"
	an["t"] = 0.0
	an["acc"] = 0.0
	an["active"] = true
	an["data"] = {"seq": p["seq"], "owed": p["day"], "resume": resume}
	an["sub"] = 0
	hist.append("cola")
	hist = hist.slice(maxi(0, hist.size() - 6))
	seen["cola"] = true
	an["lastBig"] = true
	_say(String(DEFS["cola"]["msg"]))
	_on("cola")
	return true


func _cola_resume(r: Dictionary) -> void:
	an["pre"] = String(r.get("pre", ""))
	an["locked"] = bool(r.get("locked", false))
	an["lockWait"] = bool(r.get("lockWait", false))
	an["preNext"] = float(r.get("preNext", 0.0))
	an["next"] = maxf(float(r.get("next", 0.0)), 12.0)


# ---- the per-anomaly rules (each anomaly's `tick`) ----

func _tick_anomaly(dt: float) -> void:
	var id := String(an["id"])
	var d: Dictionary = an["data"]
	var hard := _hard()
	var t := float(an["t"])
	var px := float(_c["x"])
	var py := float(_c["y"])
	var me := Vector2(px, py)
	match id:
		"blackout":
			if _in_room() and String(_c["scene"]) != "teach6":
				_drain(0.7, dt)
			if t >= 24.0:
				_say("我：灯管轻轻响了一声，又亮了。")
				_end()
		"rain":
			if under_cover():
				an["acc"] = maxf(0.0, float(an["acc"]) - dt * 0.6)
				if not d.get("cov", false) and not _in_room():
					d["cov"] = true
					_say("我：躲到了檐下。雨声一下子远了，可我还是能听见它在找我。")
			else:
				an["acc"] = float(an["acc"]) + dt
				_drain(0.7, dt)
				d["cov"] = false
			if float(an["acc"]) > (9.0 if hard else 14.0):
				_kill("雨灌进了你的肺里。你听见自己在身体里晃，像一只装满水的桶。", "drown")
			elif float(an["acc"]) > (5.0 if hard else 8.0) and not d.get("warn", false):
				d["warn"] = true
				_say("我：喘不上气了。得找个有顶的地方——屋檐、柱廊、车棚，哪里都行。")
			if t > 26.0:
				_end()
		"moth":
			var src := Vector2(float(d["src"]["x"]), float(d["src"]["y"]))
			if src.distance_to(me) > 120.0:
				an["acc"] = maxf(0.0, float(an["acc"]) - dt * 1.4)
			else:
				an["acc"] = float(an["acc"]) + dt
				_drain(1.6, dt)
			if float(an["acc"]) > (4.5 if hard else 6.5):
				_kill("蛾群把你裹住了。翅膀上的粉落进你的眼睛里，很痒。然后什么都不痒了。", "swarm")
			if t > 24.0:
				_end()
		"turn":
			_tick_turn(dt, d)
		"broad":
			if bool(_c.get("moving", false)) and not bool(_c.get("seated", false)):
				an["acc"] = float(an["acc"]) + dt
			if float(an["acc"]) > 1.6:
				_hurt("广播停了一下。然后，它念出了我现在站着的位置——精确到哪一块地砖。", 18.0)
			elif t > 5.2:
				_say("广播：「……谢谢配合。」")
				_end()
		"bell13":
			if bool(_c.get("seated", false)) and String(_c["scene"]) == "teach1":
				_say("我：我坐回自己的位子上。钟声在第十二下停了。")
				_end()
				return
			_drain(0.22, dt)
			if t > 15.0:
				_hurt("第十三下。我数得很清楚——可是我不记得自己是从哪一下开始数的。", 20.0)
		"exercise":
			var origin := Vector2(float(d["src"]["x"]), float(d["src"]["y"]))
			if origin.distance_to(me) > 120.0:
				an["acc"] = maxf(0.0, float(an["acc"]) - dt * 0.8)
			else:
				an["acc"] = float(an["acc"]) + dt
			if float(an["acc"]) > (3.6 if hard else 5.2):
				_kill("你开始跟着做操。手臂抬起来的时候你才发现，你早就停不下来了。", "follow")
			if t > 22.0:
				_end()
		"bells":
			if _near_obj("shed") < 110.0:
				an["acc"] = float(an["acc"]) + dt
			else:
				an["acc"] = maxf(0.0, float(an["acc"]) - dt * 1.2)
			if float(an["acc"]) > 2.0:
				_hurt("所有车铃同时响的那一刻，耳朵里只剩下\"嗡\"的一声。过了很久，我才听见自己的心跳。", 15.0)
			if t > 18.0:
				_end()
		"hand":
			_tick_hand(dt, d)
		"repeat":
			_tick_repeat(dt, d)
		"chalk":
			_drain(0.25, dt)
			if t > 16.0:
				_end()
		"loop":
			if not _corridor_here():
				_say("我：推开门，外面是校园。回头看，那条走廊又只有原来那么长了。" if not _in_room() else "我：我拐进了一间教室。身后的走廊安静下来，不再往前延伸了。")
				_end()
				return
			if bool(_c.get("running", false)):
				an["acc"] = float(an["acc"]) + dt * 2.6
			else:
				an["acc"] = float(an["acc"]) + dt
			_drain(0.3, dt)
			if float(an["acc"]) > 14.0:
				_say("我：门终于是另一扇了。门牌上的班号，比刚才大了一。")
				_end()
		"roster":
			if d.get("done", false):
				_end()
				return
			if t > 18.0:
				_end()
		"leak":
			if d.get("hurt", false):
				if t > 20.0:
					_end()
				return
			var on := false
			for p: Dictionary in d["pts"]:
				if Vector2(float(p["x"]), float(p["y"])).distance_squared_to(me) < 100.0:
					on = true
			if on:
				an["acc"] = float(an["acc"]) + dt
			else:
				an["acc"] = maxf(0.0, float(an["acc"]) - dt)
			if float(an["acc"]) > 1.5:
				d["hurt"] = true
				_hurt("水滴进了我的衣领。是温的，有一股铁锈味。我抬头——天花板上那块水渍，形状像一个人趴在上面。", 12.0, false, true)
			if t > 20.0:
				_end()
		"rite":
			var circle := Vector2(float(d["c"]["x"]), float(d["c"]["y"]))
			if circle.distance_to(me) < 19.0:
				an["acc"] = float(an["acc"]) + dt
				_drain(2.0, dt)
				if not d.get("warn", false):
					d["warn"] = true
					_say("我：我踩到粉笔线了。蜡烛的火苗一起朝我这边歪。")
			else:
				an["acc"] = maxf(0.0, float(an["acc"]) - dt * 0.5)
			if float(an["acc"]) > (1.4 if hard else 2.2):
				_kill("你走进了那个圈。正中那个空着的位置，刚好是你的大小。", "ring")
			if t > 20.0:
				_end()
		"cold":
			if d["chosen"] == null:
				if t > 1.4 and not d.get("asked", false):
					_ask(d, "最东边那扇门后面，冷得像冰柜。门缝里有东西在敲，很有节奏。", ["把门拉开一条缝", "转身就走"], ["near", "away"])
			elif d["chosen"] == "near":
				_emit("san", {"amount": 14.0, "max": 100.0})
				_say("我：里面挂着一排冻硬的校服，袖子在风里互相敲。最外面那件的胸口，绣着我的名字。……我反而不怕了。")
				_end()
			else:
				_emit("san", {"amount": -16.0, "min": 0.0})
				_say("我：我走了。那股冷气跟着我，一直贴在后颈上，走了很远都没散。")
				_end()
		"shifting":
			_drain(0.5, dt)
			if t > 18.0:
				_say("我：楼停下来了。整片校园里，只有钟楼一直没动——它在看着别的楼。")
				_end()
		"stare":
			if d.get("hit", false):
				d["hitT"] = float(d["hitT"]) + dt
				if float(d["hitT"]) > 1.6:
					_end()
				return
			if not bool(_c.get("moving", false)):
				an["acc"] = float(an["acc"]) + dt
			else:
				an["acc"] = maxf(0.0, float(an["acc"]) - dt)
			if float(an["acc"]) > 1.8:
				d["hit"] = true
				d["hitT"] = 0.0
				_hurt("我站住了。于是全班一起站了起来，椅子腿在地上刮出同一声。然后他们又一起坐下。", 18.0, false, true)
			elif t > 12.0:
				_say("我：他们慢慢地转回去了。最后转回去的，是我的同桌。")
				_end()
		"lamps":
			if not bool(_c.get("moving", false)):
				an["acc"] = float(an["acc"]) + dt
			else:
				an["acc"] = maxf(0.0, float(an["acc"]) - dt * 0.8)
			if float(an["acc"]) > 1.6:
				_hurt("灯停在了我头顶，亮得发白。有一瞬间，我看见了自己手背里的骨头。", 16.0)
			elif t > 16.0:
				_say("我：灯一盏一盏地灭回去。最后一盏在我前面，灭得很慢，像在等我。")
				_end()
		"feast":
			if not _in_canteen():
				an["acc"] = maxf(0.0, float(an["acc"]) - dt * 0.5)
			else:
				an["acc"] = float(an["acc"]) + dt
			if float(an["acc"]) > FEAST_NORMAL:
				_emit("advance_time", {"minutes": 20.0})
				_hurt("我回过神来的时候，嘴里有东西。我不记得自己坐下过。面前的碗是空的，上面那张纸条写着我的名字。", 22.0)
			if an["active"] and t > 24.0:
				_end()
		"necker":
			var wall_x := float(_campus.get("bound_map", {}).get("x1", 830)) * SC
			var to_wall := absf(wall_x - px)
			if to_wall < 150.0 * SC / 2.0:
				_drain(1.2, dt)
			if to_wall < 90.0 * SC / 2.0:
				an["acc"] = float(an["acc"]) + dt
				if not d.get("warn", false):
					d["warn"] = true
					_say("我：他停下来了。他在等我再走近一点。")
			else:
				an["acc"] = maxf(0.0, float(an["acc"]) - dt)
			if float(an["acc"]) > (1.4 if hard else 2.2):
				_kill("他没有绕到校门口。他把脖子从围栏的缝里伸了进来，一直伸，一直伸。", "neck")
			if t > 20.0:
				_end()
		"shadow":
			if under_cover():
				an["acc"] = maxf(0.0, float(an["acc"]) - dt * 0.6)
			else:
				an["acc"] = float(an["acc"]) + dt
				_drain(0.8, dt)
			if float(an["acc"]) > 10.0:
				_hurt("影子追上来了，和我叠在一起。有一瞬间，我分不清是谁先抬的手。", 18.0)
			if an["active"] and t > 22.0:
				_end()
		"twin":
			_tick_twin(dt, d, hard)
		"raindots":
			_drain(0.4, dt)
			if t > 14.0:
				_say("我：地上的字写着——明天的天气：阴。明天的值日：你。")
				_end()
		"cup":
			_tick_cup(d, hard)
		"cola":
			_tick_cola(d, hard)


func _tick_turn(dt: float, d: Dictionary) -> void:
	var t := float(an["t"])
	if d.get("smile", false):
		_tick_turn_smile(dt, d)
		return
	if d["chosen"] == null:
		if t > 1.2 and not d.get("asked", false):
			_ask(d, "背后有只手，拍了一下我的肩膀。它还搭在那儿。", ["不回头", "回头看"], ["no", "yes"])
	elif d["chosen"] == "yes":
		an["acc"] = float(an["acc"]) + dt
		if float(an["acc"]) > 0.5:
			_hurt("我回头了。它的脸离我只有一寸——没有五官，只有一层湿透的皮。下一秒，什么都没有了。肩膀上还是凉的。", 26.0, true)
	else:
		an["acc"] = float(an["acc"]) + dt
		if float(an["acc"]) >= 7.8:
			_emit("san", {"amount": 6.0, "max": 100.0})
			_emit("clue", {"id": "turn"})
			_say("我：那只手慢慢松开了。我一直没有回头。")
			_end()


## The other turn: footsteps -> a tap -> you must look back (the big smiling face is a later effect).
func _tick_turn_smile(dt: float, d: Dictionary) -> void:
	var t := float(an["t"])
	d["steps"] = int(d.get("steps", 0))
	if d["chosen"] == null and not d.get("asked", false) and t > float(d["steps"]) * 0.42 and int(d["steps"]) < 4:
		d["steps"] = int(d["steps"]) + 1
	if d["chosen"] == null:
		if t > 1.9 and not d.get("asked", false):
			_ask(d, "脚步声停在我身后。那只手拍了拍我的肩膀，没有拿开——像在等我回头。", ["不回头", "回头看"], ["no", "yes"])
		return
	an["acc"] = float(an["acc"]) + dt
	if d.get("done", false):
		if float(an["acc"]) > 2.2:
			_end()
		return
	if d["chosen"] == "yes" and float(an["acc"]) > 0.3:
		d["done"] = true
		an["acc"] = 0.0
		_emit("turn", {"angle": PI})
		_emit("smile", {"mode": "behind"})
		_hurt("我：我回头了。身后是一张很大很大的笑脸，眼睛弯成两道缝，嘴角一直咧到耳根。它冲我点了点头，就不见了。我的手心全是汗。", 5.0, true, true)
	elif d["chosen"] == "no" and float(an["acc"]) > 1.0:
		d["done"] = true
		_emit("violation", {"amount": 15.0})
		_emit("smile", {"mode": "jump"})
		_hurt("我没有回头。它等不及了——那张脸从我肩膀上绕过来，贴着我的鼻尖，一点一点咧开了嘴。", 30.0)


func _tick_hand(dt: float, d: Dictionary) -> void:
	var t := float(an["t"])
	if d["chosen"] == null:
		if t > 1.6 and not d.get("asked", false):
			_ask(d, "隔间底下伸来一只手。手心朝上，像在等什么。", ["不动", "把手放上去"], ["no", "yes"])
	elif d["chosen"] == "yes":
		var bag: Array = _c.get("bag", [])
		var lost := ""
		if not bag.is_empty():
			lost = String(bag[int(floor(_rng.randf() * bag.size()))])
			_emit("remove_item", {"id": lost})
		var tail := "口袋里的「%s」不见了。" % String(_c.get("item_names", {}).get(lost, lost)) if lost != "" else "掌心多了一道指甲印，弯弯的，像在笑。"
		_hurt("它握住了我，握得很紧，指甲陷进肉里。等我把手抽回来——" + tail, 20.0)
	else:
		an["acc"] = float(an["acc"]) + dt
		if float(an["acc"]) > 2.2:
			_emit("clue", {"id": "hand"})
			_say("我：那只手在原地停了很久，然后慢慢缩了回去。")
			_end()


func _tick_repeat(dt: float, d: Dictionary) -> void:
	var t := float(an["t"])
	if d["chosen"] == null:
		if t > 1.0 and not d.get("asked", false):
			var labels: Array = []
			var ids: Array = []
			if (_c.get("bag", []) as Array).has("hw"):
				labels.append("把作业本递过去")
				ids.append("hw")
			labels.append("不出声")
			ids.append("quiet")
			labels.append("说出一个名字")
			ids.append("name")
			_ask(d, "后桌：「你作业交了吗？」", labels, ids)
	elif d["chosen"] == "hw":
		_emit("san", {"amount": 12.0, "max": 100.0})
		_emit("remove_item", {"id": "hw"})
		_say("我：后面那只手接过了作业本，翻了一页，又翻了一页。然后安静了。")
		_end()
	elif d["chosen"] == "name":
		_hurt("我说出了一个名字。全班同时应了一声——\"到\"。没有一个声音是我认识的。", 20.0)
	else:
		an["acc"] = float(an["acc"]) + dt
		if float(an["acc"]) > 14.0:
			_emit("san", {"amount": -6.0})
			_emit("clue", {"id": "repeat"})
			_say("我：他问了十四遍。第十五遍的时候，他叫的是我的名字。")
			_end()


func _tick_twin(dt: float, d: Dictionary, hard: bool) -> void:
	var t := float(an["t"])
	if _room() == null or String(_c["scene"]) != String(d.get("room", "")):
		_say("我：我下了楼。楼梯上一直有第二个人的脚步声，比我慢半拍。")
		_end()
		return
	var twin := Vector2(float(d["x"]), float(d["y"]))
	var me := Vector2(float(_c["x"]), float(_c["y"]))
	var dtwin := twin.distance_to(me)
	var look: bool = CampusGeometry.ang_diff(atan2(twin.y - me.y, twin.x - me.x), float(_c["ang"])) < 0.6
	if not look and dtwin > 16.0:
		var speed := (26.0 if hard else 18.0) * dt
		twin += (me - twin) / dtwin * speed
		d["x"] = twin.x
		d["y"] = twin.y
		if not d.get("moved", false):
			d["moved"] = true
			_say("我：……他刚才是不是动了？")
	if dtwin < 16.0:
		_kill("他走到了你面前。你们同时抬起手。他的手，是热的。", "twin")
	if t > 22.0:
		_say("我：他转身，从天台边上走了下去。没有声音。")
		_end()


func _tick_cup(d: Dictionary, hard: bool) -> void:
	var t := float(an["t"])
	var me := Vector2(float(_c["x"]), float(_c["y"]))
	if (d["wall"] as Dictionary).is_empty() or (_in_room() and int(d["phase"]) < 2):
		_end() # indoors it cannot hit you
		return
	var fall_time := sqrt(2.0 * CUP_H / 9.8)
	if int(d["phase"]) == 0 and t >= float(d["wob"]):
		d["phase"] = 1
		d["tf"] = t
		d["lx"] = me.x
		d["ly"] = me.y
		if not d.get("said", false):
			d["said"] = true
			_say("我：它掉下来了——", true)
	if int(d["phase"]) == 1 and t - float(d["tf"]) >= fall_time:
		d["phase"] = 2
		d["tl"] = t
		var miss := Vector2(float(d["lx"]), float(d["ly"])).distance_to(me) * U2M
		if miss < CUP_R and not under_roof():
			_kill("头顶上一声闷响。我最后看见的，是一只白色的杯子，杯身上画着清华的二校门，金色的两个字：清華。它比我想象的要重。", "floor")
			return
		if miss < CUP_R:
			_say("我：「当」的一声，砸在头顶的雨棚上，又弹到了地上。")
		elif miss < 2.6:
			_emit("san", {"amount": -(9.0 if hard else 6.0)})
			_say("我：就砸在我脚边。杯子摔瘪了，杯身上画着清华的二校门。淡紫色的杯盖滚开，里面的水还是热的。")
		else:
			_say("我：不远处「哐」的一声，一只杯子在地上弹了两下。我不敢抬头。")
	if int(d["phase"]) == 2 and t - float(d["tl"]) > 2.6:
		_end()


func _tick_cola(d: Dictionary, hard: bool) -> void:
	var t := float(an["t"])
	var me := Vector2(float(_c["x"]), float(_c["y"]))
	var fall_time := sqrt(2.0 * COLA_H / 9.8)
	if _in_room() and int(d["phase"]) < 2:
		_say("我：我钻进了楼里。外面「嘭」的一声，接着是很长很长的「嘶——」。")
		_end()
		return
	if int(d["phase"]) == 0 and t >= float(d["warn"]):
		d["phase"] = 1
		d["tf"] = t
		d["lx"] = me.x
		d["ly"] = me.y
		_say("我：有东西从天上掉下来了——", true)
	if int(d["phase"]) == 1 and t - float(d["tf"]) >= fall_time:
		d["phase"] = 2
		d["tl"] = t
		var miss := Vector2(float(d["lx"]), float(d["ly"])).distance_to(me) * U2M
		if miss < COLA_R and under_roof():
			_say("我：「嘭」地砸在头顶的棚子上，滚下来，在我脚边打转。是一罐可乐。")
		elif miss < COLA_R and bool(_c.get("brolly", false)):
			_emit("san", {"amount": -(4.0 if hard else 2.0), "min": 0.0})
			_say("我：伞面猛地一沉，有什么东西弹了出去——一罐可乐，摔瘪了，还在往外冒泡。")
		elif miss < COLA_R:
			d["hit"] = true
			_hurt("我：「嘭」——正砸在我肩膀上。是一罐可乐，冰的。罐子瘪了，泡沫顺着袖子往下淌。抬头，天上什么都没有。", 13.0, false, true)
		elif miss < 2.4:
			_emit("san", {"amount": -(5.0 if hard else 3.0), "min": 0.0})
			_say("我：就在我脚边炸开了。一罐可乐，瘪成一团，泡沫「嘶嘶」地往外冒。抬头——天上什么都没有。")
		else:
			_say("我：不远处「嘭」的一声。一罐可乐在地上打转，泡沫喷了一地。")
	if int(d["phase"]) == 2 and t - float(d["tl"]) > 2.8:
		_end()


## One simulation step (anDrive). Skipped in the portal tunnel; the void maze, fake-normal day
## and special-day gates are not ported.
func tick(dt: float) -> void:
	if not (dt > 0.0) or bool(_c.get("dead", false)):
		return
	if not an["active"]:
		if String(_c.get("scene", "")) == "portal_tunnel":
			return
		if _cola_drive(dt):
			return
		if bool(_c.get("inspection_quiet", false)):
			return
		an["next"] = float(an["next"]) - dt
		if float(an["next"]) <= 0.0:
			_start()
	else:
		if an["id"] == "":
			return
		an["t"] = float(an["t"]) + dt
		if float(an["t"]) > 45.0:
			_end()
			return
		_tick_anomaly(dt)
