class_name BroadcastModule
extends FeatureModule
## The public broadcast station and the 《放学》 route, ported from the Web version (reference
## wd-fz.github.io@0bf508a): modules/broadcast/broadcast.js with domain/broadcast.js
## (BROADCAST_CFG / BroadcastRules). Pages hidden in four places, the piano lock, the fuse, the false
## red page, reading the notice into the microphone, the 60-second dismissal bell and the crowd to
## the north gate; plus the real and false calls on the speakers. Context in, events out.

const STATE_VERSION := 1
const ROOM := "admin2"
const STATION := [5, 3]
const SOURCES := [{"room": "admin1", "at": [46, 2], "title": "教导处文件柜"}, {"room": "lab5", "at": [5, 1], "title": "琴凳"},
	{"room": "guard1", "at": [2, 4], "title": "保安岗登记簿"}, {"room": "teach6", "at": [20, 2], "title": "天台喇叭箱"}]
const ARCHIVE_KEY := {"room": "admin5", "at": [6, 2]}
const FUSE := {"room": "gear1", "at": [3, 1]}
const FROM := 1040.0
const TO := 1340.0
const NORMAL_SECONDS := 15.0
const HARD_SECONDS := 20.0
const BELL_SECONDS := 60.0
const NOTES := [1, 3, 2, 5]
const PAGES := ["第二天，第八节下课以后。请全体同学收好课本。", "第二天。请核对蓝黑墨水的通知，不要念红色的那一页。",
	"第二天。听到长铃后，随同学们从北门离校。", "第二天。铃声结束前离校，明天见。"]
const CALLS := [{"room": "lab4", "at": [7, 1], "name": "实验楼四楼地理实验室"}, {"room": "lab2", "at": [7, 1], "name": "实验楼二楼化学实验室"}]

var b: Dictionary = {}
var held := false
var progress := 0.0
var origin: Variant = null
var events: Array = []
var seed_value := 0

var _c: Dictionary = {}
var _rooms: Dictionary = {}
var _pending: Dictionary = {}
var _crowd_path: Array = []
var _nav: PatrolNav


func _init(rooms: Dictionary = {}, nav: PatrolNav = null) -> void:
	_rooms = rooms
	_nav = nav


func module_id() -> StringName:
	return &"story.broadcast"


func state_version() -> int:
	return STATE_VERSION


static func normalize(v: Dictionary) -> Dictionary:
	var o := {"version": 1, "book": bool(v.get("book", false)), "fuse": bool(v.get("fuse", false)), "archiveOpen": bool(v.get("archiveOpen", false)),
		"boxSnack": bool(v.get("boxSnack", false)), "fakeSite": null, "completed": clampi(int(v.get("completed", 0)), 0, 4), "phase": "collect", "bell": 0.0,
		"attemptDay": maxi(0, int(v.get("attemptDay", 0))), "selected": "notice1", "piano": [], "pianoFails": clampi(int(v.get("pianoFails", 0)), 0, 3),
		"pianoUntil": maxf(0.0, float(v.get("pianoUntil", 0.0))), "verified": [], "clock": maxf(0.0, float(v.get("clock", 0.0))),
		"nextCall": maxf(0.0, float(v.get("nextCall", 180.0))), "callSeq": maxi(0, int(v.get("callSeq", 0))), "calls": [], "current": null}
	var fs: Variant = v.get("fakeSite")
	if (fs is int or fs is float) and int(fs) >= 0 and int(fs) < 4:
		o["fakeSite"] = int(fs)
	var sel := String(v.get("selected", "notice1"))
	if sel in ["notice1", "notice2", "notice3", "notice4", "notice_fake"]:
		o["selected"] = sel
	for n: Variant in v.get("piano", []):
		if o["piano"].size() < 4 and (n is int or n is float):
			o["piano"].append(int(n))
	for n: Variant in v.get("verified", []):
		if n is int or n is float:
			o["verified"].append(int(n))
	o["verified"] = (o["verified"] as Array).slice(-30)
	if v.get("phase") == "bell" and o["completed"] == 4 and o["book"] and o["fuse"] and float(v.get("bell", 0.0)) > 0.0:
		o["phase"] = "bell"
		o["bell"] = minf(BELL_SECONDS, float(v["bell"]))
	if o["phase"] != "bell" and o["completed"] == 4:
		o["completed"] = 3
	for c: Variant in v.get("calls", []):
		if c is Dictionary and (c.get("room") in ["lab2", "lab4"]):
			o["calls"].append({"id": int(c.get("id", 0)), "room": String(c["room"]), "text": String(c.get("text", ""))})
	o["calls"] = (o["calls"] as Array).slice(-20)
	var cur: Variant = v.get("current")
	if cur is Dictionary and cur.get("room") in ["lab2", "lab4"]:
		o["current"] = {"id": int(cur.get("id", 0)), "room": String(cur["room"]), "text": String(cur.get("text", "")), "real": bool(cur.get("real", false)),
			"done": bool(cur.get("done", false)), "arrived": bool(cur.get("arrived", false)), "age": maxf(0.0, float(cur.get("age", 0.0)))}
	return o


## BroadcastRules.hash: FNV-1a of "seed|key" mapped to [0, 1).
static func hash01(seed_in: int, key: String) -> float:
	var h := 2166136261
	var s := "%d|%s" % [seed_in, key]
	for i in s.length():
		h = (h ^ s.unicode_at(i)) & 0xFFFFFFFF
		h = (h * 16777619) & 0xFFFFFFFF
	return float(h) / 4294967296.0


static func paper(index: int, fake: bool) -> Dictionary:
	if fake:
		return {"id": "notice_fake", "ink": "红笔", "date": "第 0 天", "text": "第 0 天。请读到这里的同学留在原地。其他同学不要回头。"}
	return {"id": "notice%d" % (index + 1), "ink": "蓝黑墨水", "date": "第二天", "text": PAGES[index]}


static func in_window(day: int, t: float) -> bool:
	return day >= 2 and t >= FROM and t < TO


func reset() -> void:
	b = normalize({})
	held = false
	progress = 0.0
	origin = null
	events = []
	_pending = {}
	_crowd_path = []


func set_seed(value: int) -> void:
	seed_value = value


func capture() -> Dictionary:
	var out := b.duplicate(true)
	out["seed"] = seed_value
	return out


func validate(data: Dictionary) -> String:
	if not (data.get("book") is bool) or not (data.get("fuse") is bool):
		return "广播站状态无效"
	return ""


func restore(data: Dictionary) -> void:
	reset()
	b = normalize(data)
	seed_value = int(data.get("seed", 0))


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


func _has(id: String) -> bool:
	var f: Callable = _c.get("has", Callable())
	return f.is_valid() and bool(f.call(id))


func _add(id: String) -> bool:
	var f: Callable = _c.get("add", Callable())
	return f.is_valid() and bool(f.call(id))


func _remove(id: String) -> void:
	var f: Callable = _c.get("remove", Callable())
	if f.is_valid():
		f.call(id)


func _here() -> Vector2:
	return Vector2(float(_c.get("x", 0.0)), float(_c.get("y", 0.0)))


func _day() -> int:
	return int(_c.get("day", 1))


func _near(room: String, at: Array, distance: float = 14.0) -> bool:
	if String(_c.get("scene", "")) != room or not _rooms.has(room):
		return false
	var r: Dictionary = _rooms[room]
	var p := Vector2(float(r["ox"]) + (float(at[0]) + 0.5) * float(r["tw"]), float(r["oy"]) + (float(at[1]) + 0.5) * float(r["th"]))
	return _here().distance_to(p) <= distance


func ensure() -> Dictionary:
	if b["fakeSite"] == null:
		b["fakeSite"] = int(floor(hash01(seed_value, "false-notice") * 4.0))
	return b


func near_station() -> bool:
	return _near(ROOM, STATION, 19.0)


func assembled() -> bool:
	return [1, 2, 3, 4].all(func(n: int) -> bool: return _has("notice%d" % n))


func powered() -> bool:
	return not (bool(_c.get("anomaly_active", false)) and _c.get("anomaly_id") == "blackout")


func available() -> bool:
	return int(b["attemptDay"]) < _day() and in_window(_day(), float(_c.get("tsec", 0.0))) and powered() and not bool(_c.get("inspection_pending", false))


func ready() -> bool:
	return bool(b["book"]) and bool(b["fuse"]) and assembled()


func reason() -> String:
	if int(b["attemptDay"]) >= _day():
		return "今天的长铃已经停了。通知稿还在，明天第八节下课后再试。"
	if not bool(b["book"]):
		return "先读播音记录本。"
	if not bool(b["fuse"]):
		return "功放保险丝已烧，备用件在体育器材室。"
	if not assembled():
		return "通知稿还缺残页。"
	if bool(_c.get("inspection_pending", false)):
		return "学生会正在检查，先停播。"
	if not powered():
		return "停电了，功放没有反应。"
	if not in_window(_day(), float(_c.get("tsec", 0.0))):
		return "记录本：第二天起，第八节下课后、熄灯前播出。"
	return ""


func reading_seconds() -> float:
	return HARD_SECONDS if String(_c.get("diff", "easy")) == "hard" else NORMAL_SECONDS


func stop() -> void:
	var changed := held or progress > 0.0
	held = false
	progress = 0.0
	origin = null
	if changed:
		_emit("save")


func select(id: String) -> void:
	if not id in ["notice1", "notice2", "notice3", "notice4", "notice_fake"]:
		return
	stop()
	b["selected"] = id


## Start (or stop) reading the selected page into the microphone.
func hold(on: bool) -> bool:
	if not on:
		stop()
		return false
	if b["phase"] == "bell" or bool(_c.get("dead", false)) or bool(_c.get("hiding", false)) or not near_station() or not ready() or not available():
		return false
	if not _has(String(b["selected"])):
		_say("我：手里没有这一页。")
		return false
	held = true
	progress = 0.0
	origin = {"x": _here().x, "y": _here().y, "day": _day()}
	return true


func book() -> void:
	b["book"] = true
	_emit("record", {"id": "broadcastBook", "text": "行政楼二楼广播站：放学通知被撕成四页，蓝黑墨水、日期「第二天」。第二天起，第八节下课后至熄灯前播出。教导处文件柜、琴凳、保安岗登记簿、天台喇叭箱各有一页。", "kind": "线索", "source": "播音记录本"})
	_say("播音记录本：「未播出：放学通知。第二天，第八节下课以后，熄灯以前。四页，蓝黑墨水。功放保险丝已烧，备用件和一份补给在器材室。长铃只响六十秒，提前确认北门路线，准备疾跑。」")
	_emit("save")


func _collect(id: String) -> bool:
	if _has(id):
		return true
	if not _add(id):
		return false
	_emit("save")
	return true


func _page(index: int) -> void:
	var p := paper(index, false)
	var labels: Array = ["收好 · %s · %s" % [p["ink"], p["date"]]]
	var ids: Array = ["take"]
	var fake: bool = ensure()["fakeSite"] == index
	if fake:
		var f := paper(index, true)
		labels.append("收好另一张 · %s · %s" % [f["ink"], f["date"]])
		ids.append("fake")
	if index == 2:
		labels.append("柜台备用手电／停车记录")
		ids.append("guard")
	labels.append("先不拿")
	ids.append("none")
	_pending = {"kind": "page", "index": index, "ids": ids}
	_emit("choice", {"text": "%s里夹着通知稿。字迹、墨水和日期都看得清。\n%s · %s：「%s」%s" % [SOURCES[index]["title"], p["ink"], p["date"], p["text"],
		"\n另一张是红笔写的，日期是「第 0 天」。" if fake else ""], "labels": labels})


func _back_to_stairs() -> bool:
	var r: Dictionary = _rooms.get("teach6", {})
	if r.is_empty():
		return false
	var p := Vector2(float(r["ox"]) + 12.5 * float(r["tw"]), float(r["oy"]) + 16.5 * float(r["th"]))
	return cos(atan2(p.y - _here().y, p.x - _here().x) - float(_c.get("ang", 0.0))) < -0.3


func _take_page(index: int) -> void:
	if index == 0 and not bool(b["archiveOpen"]):
		if not _has("archivekey"):
			_say("文件柜上锁了，标签写着「教导处」。钥匙登记在五楼办公室。")
			return
		b["archiveOpen"] = true
		_remove("archivekey")
		_emit("save")
	if index == 1:
		if bool(_c.get("piano_closed", false)):
			_say("我：琴房的门锁着。门上贴着一张纸：「今天的音乐课改上数学。」")
			return
		piano(-1)
		return
	if index == 2 and not bool(_c.get("night", false)):
		_say("登记簿压在内侧柜台，保安岗的夜间窗口要熄灯以后才开。")
		return
	if index == 3:
		if not _has("coin"):
			_say("喇叭箱的螺丝槽很宽，需要一枚硬币。")
			return
		if not _back_to_stairs():
			_say("喇叭箱背面的字：「拧螺丝时，背对楼梯口。」")
			return
	_emit("job", {"seconds": 2.0 if index == 3 else 1.4, "index": index})


## The hold job finished (the app checks the player stayed put).
func job_done(index: int) -> void:
	if bool(_c.get("dead", false)) or not _near(String(SOURCES[index]["room"]), SOURCES[index]["at"]):
		return
	if index == 3 and (not _has("coin") or not _back_to_stairs()):
		return
	_page(index)


## The piano lock: the opening of the class bell, 1 · 3 · 2 · 5. note < 0 only shows the keys.
func piano(note: int) -> void:
	var clock := float(_c.get("clock", 0.0))
	if float(b["pianoUntil"]) > clock:
		_say("琴房的灯暗到底了。琴凳上写着：十分钟以后再试。")
		return
	if int(b["pianoFails"]) >= 3:
		b["pianoFails"] = 0
		b["pianoUntil"] = 0.0
	if note >= 0:
		if not note in [1, 2, 3, 5]:
			return
		_emit("note", {"note": note})
		b["piano"].append(note)
		if note != int(NOTES[(b["piano"] as Array).size() - 1]):
			b["piano"] = []
			b["pianoFails"] = int(b["pianoFails"]) + 1
			if int(b["pianoFails"]) >= 3:
				b["pianoUntil"] = clock + 10.0
			_emit("save")
			_say("弹错了一个音。琴房的灯又暗了一档。")
		elif (b["piano"] as Array).size() == 4:
			b["piano"] = []
			b["pianoFails"] = 0
			_emit("save")
			_page(1)
			return
	if float(b["pianoUntil"]) > clock:
		return
	_pending = {"kind": "piano"}
	var played: Array = (b["piano"] as Array).map(func(n: int) -> String: return str(n))
	_emit("choice", {"text": "琴凳锁着。谱面上印着下课铃开头：1 · 3 · 2 · 5。\n已弹：%s。琴凳内侧露出一角通知稿。" % (" · ".join(PackedStringArray(played)) if not played.is_empty() else "—"),
		"labels": ["1", "2", "3", "5", "离开琴边"]})


func install() -> bool:
	if not near_station():
		return false
	if bool(b["fuse"]):
		return true
	if not _has("broadcastfuse"):
		_say("功放保险丝已烧，备用件在体育器材室。")
		return false
	_remove("broadcastfuse")
	b["fuse"] = true
	_say("功放的红灯亮了。话筒里有很轻的呼吸声。")
	_emit("save")
	return true


func verify() -> bool:
	var call: Variant = b["current"]
	if call == null:
		_say("记录本里还没有新的广播。")
		return false
	var recorded := (b["calls"] as Array).any(func(c: Dictionary) -> bool: return int(c["id"]) == int(call["id"]))
	if not recorded and not (b["verified"] as Array).has(int(call["id"])):
		b["verified"].append(int(call["id"]))
		_emit("fact", {"what": "verified", "real": false})
		_emit("save")
	_say("记录本上有这一条，时间和地点对得上。" if recorded else "记录本上没有这一条。刚才喇叭里的啸叫还没停。")
	return not recorded


func menu() -> void:
	if not near_station():
		return
	_pending = {"kind": "menu"}
	_emit("choice", {"text": "广播站 · 功放与播音记录本", "labels": ["翻看播音记录本", "功放已修复" if bool(b["fuse"]) else "更换保险丝", "核对最近广播", "整理通知稿／朗读", "离开广播台"]})


## The papers in hand, for the microphone panel.
func papers() -> Array:
	return ["notice1", "notice2", "notice3", "notice4", "notice_fake"].filter(func(id: String) -> bool: return _has(id))


func paper_text(id: String) -> String:
	var p := paper(0, true) if id == "notice_fake" else paper(int(id.substr(6)) - 1, false)
	return "%s · %s：%s" % [p["ink"], p["date"], p["text"]]


func choose(index: int) -> void:
	var p := _pending
	_pending = {}
	match String(p.get("kind", "")):
		"menu":
			match index:
				0:
					book()
				1:
					install()
				2:
					verify()
				3:
					_emit("mic")
		"page":
			if index < 0 or index >= (p["ids"] as Array).size():
				return
			var what := String(p["ids"][index])
			var i := int(p["index"])
			if what == "take":
				if _collect("notice%d" % (i + 1)):
					var pp := paper(i, false)
					_emit("record", {"id": "notice%d" % (i + 1), "text": String(pp["text"]), "kind": "线索", "source": String(SOURCES[i]["title"])})
			elif what == "fake":
				_collect("notice_fake")
			elif what == "guard":
				_emit("guard")
		"piano":
			if index >= 0 and index < 4:
				piano([1, 2, 3, 5][index])
			else:
				b["piano"] = []


func _start_bell() -> void:
	stop()
	b["phase"] = "bell"
	b["bell"] = BELL_SECONDS
	b["attemptDay"] = _day()
	_crowd_path = []
	_emit("bell_start")
	_say("广播：「放学。全体同学从北门离校。」\n长铃只响六十秒。跟紧同学，铃声结束以前走出北门。")
	_emit("save")


## Where the crowd of leaving students is (old world units), or {} outside the bell.
func crowd() -> Dictionary:
	if b["phase"] != "bell" or _nav == null:
		return {}
	if _crowd_path.is_empty():
		var a: Variant = _nav.nodes.get("out:teach")
		var gate: Vector2 = _c.get("gate_n", Vector2(1028, 190))
		var end := _nav.snap("out", PatrolNav.point("out", gate.x, gate.y + 15.0))
		if a is Dictionary and not end.is_empty():
			_crowd_path = _nav.path(a, end)
	if _crowd_path.is_empty():
		return {}
	var total := _nav.length(_crowd_path)
	var distance := minf(total, maxf(0.0, BELL_SECONDS - float(b["bell"]) - 3.0) * total / 46.0)
	for i in range(1, _crowd_path.size()):
		var p0: Dictionary = _crowd_path[i - 1]
		var p1: Dictionary = _crowd_path[i]
		var d := Vector2(float(p1["x"]) - float(p0["x"]), float(p1["y"]) - float(p0["y"])).length()
		if distance <= d:
			var k := distance / d if d > 0.0 else 0.0
			return {"x": lerpf(float(p0["x"]), float(p1["x"]), k), "y": lerpf(float(p0["y"]), float(p1["y"]), k),
				"angle": atan2(float(p1["y"]) - float(p0["y"]), float(p1["x"]) - float(p0["x"])), "left": float(b["bell"])}
		distance -= d
	var last: Dictionary = _crowd_path[_crowd_path.size() - 1]
	return {"x": float(last["x"]), "y": float(last["y"]), "angle": -PI * 0.5, "left": float(b["bell"])}


## The crowd hides the player from the patroller (patrolCamouflage).
func cover() -> bool:
	var p := crowd()
	return not p.is_empty() and String(_c.get("scene", "")) == "out" and _here().distance_to(Vector2(float(p["x"]), float(p["y"]))) <= 34.0


func try_exit() -> bool:
	var gate: Vector2 = _c.get("gate_n", Vector2(1028, 190))
	if bool(_c.get("dead", false)) or b["phase"] != "bell" or int(b["completed"]) != 4 or not cover() or _here().distance_to(gate) > 45.0:
		return false
	stop()
	_emit("ending", {"id": "dismissal"})
	return true


func announce(real: bool, choice: int = -1) -> bool:
	if bool(_c.get("anomaly_active", false)) or b["phase"] == "bell" or held or bool(_c.get("inspection_quiet", false)):
		return false
	var spec: Dictionary = CALLS[choice % CALLS.size()] if choice >= 0 else CALLS[int(floor(hash01(seed_value, "call%d" % int(b["callSeq"])) * CALLS.size()))]
	b["callSeq"] = int(b["callSeq"]) + 1
	b["current"] = {"id": int(b["callSeq"]), "room": spec["room"], "text": "请高二（二）班同学到%s来一趟。" % spec["name"], "real": real, "done": false, "arrived": false, "age": 0.0}
	if real:
		b["calls"].append({"id": int(b["callSeq"]), "room": spec["room"], "text": b["current"]["text"]})
	b["calls"] = (b["calls"] as Array).slice(-20)
	_say("广播：「%s」%s" % [b["current"]["text"], "" if real else "喇叭里有轻微的回授啸叫。"])
	_emit("radio", {"real": real})
	_emit("save")
	return true


func tick(dt: float) -> void:
	if not (dt > 0.0) or bool(_c.get("dead", false)):
		return
	ensure()
	b["clock"] = float(b["clock"]) + dt
	if b["phase"] == "bell":
		b["bell"] = maxf(0.0, float(b["bell"]) - dt)
		if float(b["bell"]) <= 0.0:
			b["phase"] = "collect"
			b["completed"] = 0
			b["selected"] = "notice1"
			_crowd_path = []
			_emit("bell_stop")
			_say("长铃停了。同学们转身往教室走。通知稿还在，明天的放学时段可以再试。")
			_emit("save")
		else:
			try_exit()
		return
	if held:
		var o: Dictionary = origin if origin is Dictionary else {}
		if not near_station() or bool(_c.get("hiding", false)) or not ready() or not available() or o.is_empty() or int(o["day"]) != _day() \
				or _here().distance_to(Vector2(float(o["x"]), float(o["y"]))) > 3.0:
			stop()
		else:
			progress += dt
			if b["selected"] == "notice_fake" and progress >= 2.0:
				stop()
				_emit("kill", {"msg": "你念的那份通知，是给你的。", "fx": "misread", "source": "misread"})
				return
			var wanted := "notice%d" % (int(b["completed"]) + 1)
			if b["selected"] != wanted and b["selected"] != "notice_fake":
				stop()
				_say("页码不对，得从当前这一段开始。")
			elif progress >= reading_seconds():
				b["completed"] = int(b["completed"]) + 1
				progress = 0.0
				_emit("save")
				if int(b["completed"]) >= 4:
					_start_bell()
				else:
					b["selected"] = "notice%d" % (int(b["completed"]) + 1)
					_say("这一段播完了。门外的脚步还在靠近。")
	var call: Variant = b["current"]
	if call is Dictionary and not bool(call["done"]) and String(_c.get("scene", "")) == call["room"] and not bool(_c.get("inspection_quiet", false)) and not bool(_c.get("anomaly_active", false)):
		if not bool(call["arrived"]):
			call["arrived"] = true
			_say("老师没有抬头：「广播站的残页，拿硬币去天台喇叭箱找。拧的时候背对楼梯口。」" if bool(call["real"]) else "喇叭里开始念你的名字。啸叫越来越尖——先离开这间屋子。")
		if bool(call["real"]):
			call["done"] = true
			_emit("record", {"id": "broadcastTeacher", "text": "广播叫来的老师提到：天台喇叭箱要用硬币拧开，背对楼梯口。", "kind": "线索", "source": String(call["room"])})
		else:
			call["age"] = float(call["age"]) + dt
			if float(call["age"]) >= 8.0:
				_emit("san", {"amount": -1.5 * dt * float(_c.get("drain_mul", 1.0)), "min": 0.0})
	elif call is Dictionary and bool(call["arrived"]) and not bool(call["real"]) and String(_c.get("scene", "")) != call["room"]:
		call["done"] = true
	# The macro director (dread.js): a roll call is only made when nothing real is going on and the scare budget
	# allows it; it spends mild budget, and otherwise waits for a quieter moment.
	if float(b["clock"]) >= float(b["nextCall"]) and bool(_c.get("dread_ok", true)):
		if announce(hash01(seed_value, "real-call%d" % int(b["callSeq"])) > 0.5):
			_emit("dread_note", {"what": "broadcast-call"})
		b["nextCall"] = float(b["clock"]) + 180.0 + hash01(seed_value, "next-call%d" % int(b["callSeq"])) * 80.0


## E pressed: the broadcast places are checked before the ordinary tiles. Returns true when handled.
func use_here() -> bool:
	var scene := String(_c.get("scene", ""))
	if scene == "out":
		return try_exit()
	if _near(String(SOURCES[2]["room"]), SOURCES[2]["at"]) and bool(_c.get("night", false)) and not _has("broadcastkey"):
		_collect("broadcastkey")
		return true
	if near_station():
		menu()
		return true
	if _near(String(ARCHIVE_KEY["room"]), ARCHIVE_KEY["at"]):
		if not bool(b["archiveOpen"]):
			_collect("archivekey")
		else:
			_say("这把钥匙已经开过教导处的文件柜。")
		return true
	if _near(String(FUSE["room"]), FUSE["at"]):
		if not bool(b["fuse"]):
			_collect("broadcastfuse")
		if not bool(b["boxSnack"]) and (bool(b["fuse"]) or _has("broadcastfuse")) and _add("snack"):
			b["boxSnack"] = true
			_say("备用件旁还有一块士力架。放学铃只有六十秒，先记好北门的路。")
			_emit("save")
		elif bool(b["fuse"]):
			_say("备用保险丝已经装进广播站的功放。")
		return true
	for i in SOURCES.size():
		if _near(String(SOURCES[i]["room"]), SOURCES[i]["at"]):
			if i == 2 and not bool(_c.get("night", false)):
				return false
			_take_page(i)
			return true
	return false


func hint() -> String:
	var scene := String(_c.get("scene", ""))
	if scene == "out" and b["phase"] == "bell":
		return "随人群走向北门" if cover() else "追上离校的同学"
	if near_station():
		return "播音记录本／广播台"
	if _near(String(ARCHIVE_KEY["room"]), ARCHIVE_KEY["at"]):
		return "取教导处钥匙"
	if _near(String(FUSE["room"]), FUSE["at"]):
		return "备用保险丝"
	for i in SOURCES.size():
		if _near(String(SOURCES[i]["room"]), SOURCES[i]["at"]):
			if i == 2 and not bool(_c.get("night", false)):
				return ""
			return String(SOURCES[i]["title"])
	return ""


## The patrol zone of the station is active while the microphone is live.
func zone_live() -> bool:
	return held and near_station()
