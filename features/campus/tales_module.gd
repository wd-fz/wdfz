class_name TalesModule
extends FeatureModule
## Two campus tales, ported from the Web version (reference wd-fz.github.io@0bf508a,
## modules/campus-tales): the midnight canteen (canteen.js MidnightCanteen: after lights out one lit
## window serves one bowl a night, +40 SAN, +25 assimilation up to 95, and assimilation does not
## fall back until 07:20) and the late mirror (mirror.js MirrorLag: the mirrors over the teaching
## building's basins answer by SAN tier; below 20 the reflection raises a hand first and staring
## at it for 3 s more is the mirror death), the checkup day (checkup.js CheckupDay: on that special
## day, third lesson 10:20–11:05 in the admin1 office; missing it is 10 violations and −8 SAN unless
## on leave; the eye chart's last line is one real public risk by run seed) and the patrol log pages
## (notes.js PatrolNotes: two torn duty sheets, each six floors of the patroller's fixed route by run
## seed). The duty roster texture is not ported.

const STATE_VERSION := 1
const MEAL := {"san": 40.0, "tt": 25.0, "tt_cap": 95.0, "min": 10.0, "room": "canteen1"}
const MIRROR := {"near": 2.6, "face": 0.6, "stare_die": 3.0}
const CHECKUP := {"room": "admin1", "from": 620.0, "to": 665.0, "warn": 600.0, "violation": 10.0, "san": 8.0, "minutes": 5.0,
	"ruler": Vector2(1.0, 15.45), "scale": Vector2(2.7, 15.45), "chart": Vector2(9.0, 15.45),
	"queue": [Vector2(1.45, 17.32), Vector2(2.22, 17.32), Vector2(3.0, 17.32), Vector2(3.78, 17.32), Vector2(4.55, 17.32)]}
const LINES := ["十二点五十 坐回座位", "熄灯以后 别吃那碗饭", "镜子先动 就别再看", "喇叭叫你 先查记录本", "电梯的门 不等人"]
const NOTE_SPOTS := [{"id": "admin", "room": "admin3", "c": 30, "r": 3, "where": "行政楼三楼办公室的抽屉"}, {"id": "guard", "room": "guard1", "c": 4, "r": 2, "where": "保安岗的值班台"}]
const FORM := "体检表\n姓名：（三个认不出的字）　班级：高二（二）班\n身高：—　　体重：正常\n心率：0　　视力：5.0 / 5.0\n医生意见：合格。"

var meal: Dictionary = {}       # {night, until, n}
var raise := 0.0
var stare := 0.0
var checkup: Dictionary = {}    # {done: {day: 1}, missed: {...}, warned: {...}}
var notes: Dictionary = {}      # {admin: 1, guard: 1}
var route: Array = []           # the patroller's fixed route nodes (patrol_data)
var events: Array = []

var _rooms: Dictionary = {}
var _c: Dictionary = {}
var _pending := ""
var _spots: Dictionary = {}


func _init(rooms: Dictionary = {}, patrol_route: Array = []) -> void:
	_rooms = rooms
	route = patrol_route


func module_id() -> StringName:
	return &"campus.tales"


func state_version() -> int:
	return STATE_VERSION


func reset() -> void:
	meal = {}
	raise = 0.0
	stare = 0.0
	checkup = {"done": {}, "missed": {}, "warned": {}}
	notes = {}
	events = []
	_pending = ""


func capture() -> Dictionary:
	return {"meal": meal.duplicate(), "checkup": checkup.duplicate(true), "notes": notes.duplicate()}


func validate(data: Dictionary) -> String:
	for key: String in ["meal", "checkup", "notes"]:
		if not (data.get(key, {}) is Dictionary):
			return "校园怪谈状态无效"
	return ""


func restore(data: Dictionary) -> void:
	reset()
	meal = (data.get("meal", {}) as Dictionary).duplicate()
	var c: Dictionary = data.get("checkup", {})
	for key: String in ["done", "missed", "warned"]:
		checkup[key] = (c.get(key, {}) as Dictionary).duplicate() if c.get(key, {}) is Dictionary else {}
	notes = (data.get("notes", {}) as Dictionary).duplicate()


## ctx: scene, x, y, ang, tsec, clock (game minutes), san, tt, dead, day, special (today's special
## day id), on_leave, seed (run seed).
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
	var h := _checkup_hint()
	if h != "":
		return h
	for sp: Dictionary in NOTE_SPOTS:
		if _near_note(sp):
			return "再看一眼值班表" if notes.has(sp["id"]) else "撕下来的一页纸"
	return ""


func use_here() -> bool:
	if _checkup_use():
		return true
	for i in NOTE_SPOTS.size():
		if _near_note(NOTE_SPOTS[i]):
			_read_note(i)
			return true
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
	_checkup_tick()
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


# ---- the checkup day ----

static func hstr(text: String) -> float:
	return float(text.hash() & 0x7FFFFFFF) / 2147483648.0


func checkup_today() -> bool:
	return String(_c.get("special", "none")) == "checkup"


func _day_key() -> String:
	return str(int(_c.get("day", 1)))


func checkup_done() -> bool:
	return (checkup["done"] as Dictionary).has(_day_key())


func checkup_window() -> bool:
	var t := float(_c.get("tsec", 0.0))
	return t >= float(CHECKUP["from"]) and t < float(CHECKUP["to"])


## The queue in the corridor, facing the wall: from 10 minutes before until the end.
func queue_on() -> bool:
	var t := float(_c.get("tsec", 0.0))
	return checkup_today() and t >= float(CHECKUP["from"]) - 10.0 and t < float(CHECKUP["to"])


func chart_line() -> String:
	return LINES[int(floor(hstr("checkup-line:" + String(_c.get("seed", ""))) * LINES.size())) % LINES.size()]


func _near_tile(room: String, at: Vector2, k: float) -> bool:
	if String(_c.get("scene", "")) != room or not _rooms.has(room):
		return false
	var r: Dictionary = _rooms[room]
	var w := Vector2(float(r["ox"]) + at.x * float(r["tw"]), float(r["oy"]) + at.y * float(r["th"]))
	return _me().distance_to(w) < k * float(r["tw"])


## HUD period line on the checkup day (null when nothing to say).
func checkup_period() -> String:
	if not checkup_today() or checkup_done():
		return ""
	var t := float(_c.get("tsec", 0.0))
	if t >= float(CHECKUP["warn"]) and t < float(CHECKUP["from"]):
		return "体检将至 · 行政楼一楼医务室"
	return "体检 · 行政楼一楼医务室" if checkup_window() else ""


func _checkup_tick() -> void:
	if not checkup_today():
		return
	var t := float(_c.get("tsec", 0.0))
	var d := _day_key()
	var warned: Dictionary = checkup["warned"]
	if t >= float(CHECKUP["warn"]) and t < float(CHECKUP["from"]) and not warned.has(d):
		warned[d] = 1
		_say("广播：「第三节课体检。请各班同学到行政楼一楼医务室排队。」")
	var missed: Dictionary = checkup["missed"]
	if t >= float(CHECKUP["to"]) and not checkup_done() and not missed.has(d):
		missed[d] = 1
		if bool(_c.get("on_leave", false)):
			_say("我：体检的时间过了。我在请假，名单上我那一栏写着「缺」，后面画了个勾。")
			return
		_emit("viol", {"amount": float(CHECKUP["violation"])})
		_emit("san", {"amount": -float(CHECKUP["san"]), "max": 100.0, "min": 0.0})
		_say("我：体检的时间过了。听说名单上只有我那一栏是空的。班主任在本子上记了一笔。")


func _checkup_hint() -> String:
	if not checkup_today() or String(_c.get("scene", "")) != CHECKUP["room"]:
		return ""
	if _near_tile(CHECKUP["room"], CHECKUP["chart"], 1.6):
		return "视力表"
	if _near_tile(CHECKUP["room"], CHECKUP["ruler"], 1.4) or _near_tile(CHECKUP["room"], CHECKUP["scale"], 1.4):
		if checkup_done():
			return "再看一眼体检表"
		var t := float(_c.get("tsec", 0.0))
		return "体检（量身高、称体重）" if checkup_window() else ("体检还没开始" if t < float(CHECKUP["from"]) else "体检已经结束")
	return ""


func _checkup_use() -> bool:
	if not checkup_today() or String(_c.get("scene", "")) != CHECKUP["room"]:
		return false
	if _near_tile(CHECKUP["room"], CHECKUP["chart"], 1.6):
		_say("我：视力表最下面一行不是字母。是一行很小的字：\n「%s」" % chart_line())
		_emit("clue", {"id": "checkupChart", "text": "医务室视力表最下面一行：「%s」" % chart_line(), "source": "行政楼一楼医务室"})
		return true
	if not (_near_tile(CHECKUP["room"], CHECKUP["ruler"], 1.4) or _near_tile(CHECKUP["room"], CHECKUP["scale"], 1.4)):
		return false
	if checkup_done():
		_say(FORM)
		return true
	var t := float(_c.get("tsec", 0.0))
	if t < float(CHECKUP["from"]):
		_say("我：医务室里没有人。墙上贴着：「十点二十开始」。")
		return true
	if t >= float(CHECKUP["to"]):
		_say("我：体检已经结束了。体重秤上的指针还没回到零。")
		return true
	_emit("advance", {"minutes": float(CHECKUP["minutes"])})
	(checkup["done"] as Dictionary)[_day_key()] = 1
	_say("我：我站上去。没有人报数，尺子自己落下来，停在我头顶上方很高的地方。\n" + FORM)
	_emit("clue", {"id": "checkupForm", "text": "体检表：身高「—」，心率「0」，医生意见「合格」。", "source": "行政楼一楼医务室"})
	_emit("saved")
	return true


# ---- the patrol log pages ----

func _room_name(id: String) -> String:
	if id == "out":
		return "室外"
	var r: Dictionary = _rooms.get(id, {})
	return String(r.get("name", id)).split(" · ")[0] if not r.is_empty() else id


## The floors the patroller passes in order (stairwells and links left out, repeats merged).
func route_rooms() -> Array:
	var seq: Array = []
	for n: Variant in route:
		var r := String(n).split(":")[0]
		if r.begins_with("stair_") or r.begins_with("link"):
			continue
		if seq.is_empty() or seq[-1] != r:
			seq.append(r)
	return seq


func note_segment(i: int) -> Array:
	var seq := route_rooms()
	if seq.is_empty():
		return []
	var start := int(floor(hstr("patrol-note:%d:%s" % [i, String(_c.get("seed", ""))]) * seq.size()))
	var out: Array = []
	for k in 6:
		out.append(seq[(start + k) % seq.size()])
	return out


func note_text(i: int) -> String:
	var names: PackedStringArray = []
	for r: String in note_segment(i):
		names.append(_room_name(r))
	return "值班表（撕下的一页）\n" + " → ".join(names) + "\n若有事，另行处置。\n备注：高二（二）班 ×××，未离校。"


func _near_note(sp: Dictionary) -> bool:
	return _near_tile(sp["room"], Vector2(float(sp["c"]) + 0.5, float(sp["r"]) + 0.5), 1.3)


func _read_note(i: int) -> void:
	var sp: Dictionary = NOTE_SPOTS[i]
	var first := not notes.has(sp["id"])
	notes[sp["id"]] = 1
	_say(note_text(i))
	if first:
		_emit("clue", {"id": "patrolNote%d" % i, "text": note_text(i).replace("\n", "　"), "source": String(sp["where"])})
		_emit("saved")

