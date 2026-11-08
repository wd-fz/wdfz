class_name DayModule
extends FeatureModule
## Special school days and the desk lessons, ported from the Web version (reference
## wd-fz.github.io@0bf508a): day-events.js (DayEvents: anniversary halves per-second SAN drains,
## occupied closes the music room and the computer games and adds +2 to a right desk answer) and
## lesson.js (LESSON: once per lesson, seated at the own seat during class, a 12-second question on
## the desk; afterwards "study until the bell" runs the simulation at 6×). The checkup day (third
## day on, once a run) is played in TalesModule.

const STATE_VERSION := 1
const FIRST_DAY := 2
const CHECKUP_FIRST_DAY := 3
const P := {"anniversary": 0.18, "occupied": 0.22, "checkup": 0.14}
const CLOSED := ["piano", "pc"]
const SAY := {
	"anniversary": "广播：「今天是我校建校纪念日。各班照常上课，课间可以去教学楼前看看校庆横幅。」——喇叭里的声音很高兴。我也跟着松了一点。",
	"occupied": "广播：「今天的音乐课、信息课改上数学，琴房暂停开放，机房暂停游戏活动，维护终端照常可用。」——教室里响起一片很轻的叹气。",
	"checkup": "广播：「今天上午第三节课体检。各班同学十点二十到行政楼一楼医务室排队，不要缺席。」——喇叭里的声音很平。"}
const CLOSED_MSG := {"piano": "我：琴房的门锁着。门上贴着一张纸：「今天的音乐课改上数学。」", "pc": "我：今天机房暂停游戏活动。接线与维护终端仍可使用。"}
const TAG := {"anniversary": "校庆日", "occupied": "占课", "checkup": "体检日"}
const TASKS := [
	{"text": "老师让我校对课表。三行字里，有一行不该在这里。", "choices": ["课间可以离开座位", "熄灯后继续早读", "上课前把书翻开"], "answer": 1, "note": "我把「熄灯后继续早读」划掉了。下一秒，那几个字又渗了出来。"},
	{"text": "点名册翻到我这一页。有一处应该先圈出来。", "choices": ["同一个名字写满了第三排", "最后一行的字迹很淡", "纸的边缘有一道折痕"], "answer": 0, "note": "我圈出了第三排。每一个名字都是我的。老师没有再往下念。"},
	{"text": "课本夹着一张纸。哪一句像是留给我的提醒？", "choices": ["所有抽屉都是空的", "车库里别关手电", "铃响以后不用看时间"], "answer": 1, "note": "「车库里别关手电。」我把这句话记了下来，笔尖却没有沾墨。"},
	{"text": "同桌在草稿纸上写了一行字，又划掉了一半。他想提醒我的是哪一句？", "choices": ["灯按拍子闪的时候，别站在走廊中间", "下课铃一响就要离开教室", "窗外有人敲玻璃要回应"], "answer": 0, "note": "灯按拍子闪，是有东西要来了。走廊中间没有地方躲。"},
	{"text": "课本扉页上有人用铅笔写了一句话，写得很用力。", "choices": ["被普通巡察盯上，绕过遮挡脱离视线", "被盯上的时候，转身盯着它看", "被盯上的时候，大声喊老师"], "answer": 0, "note": "别让它看见你躲进柜子。先绕过遮挡，再隐藏。"},
	{"text": "窗外下起了雨。夹在课本里的纸条上，写着该怎么做。", "choices": ["找有顶的地方", "原地等雨停", "往操场中间跑"], "answer": 0, "note": "屋檐、柱廊、车棚。雨下大了，就往有顶的地方去。"},
	{"text": "后排有人把一张作业纸传了过来。上面只有一句话。", "choices": ["坐太久的话，记得站起来走走", "上课一定要一直坐着", "椅子是最安全的地方"], "answer": 0, "note": "「坐太久的话，记得站起来走走。」我回头，后排没有人。"},
	{"text": "同学的错题本上，有一道题被红笔圈了好几圈。", "choices": ["天台上那个人，你不看他的时候他才会动", "天台上那个人会跟着你说话", "天台上那个人怕光"], "answer": 0, "note": "我把那一行看了三遍：不看他的时候，他才会动。"},
	{"text": "教室后面的通知栏上，贴着一张撕掉一半的旧告示。", "choices": ["实验楼地上的粉笔圈不要踩", "实验楼的蜡烛要点亮", "实验楼的门要一直开着"], "answer": 0, "note": "剩下的那半张上只有一行：粉笔圈，不要踩。"},
	{"text": "桌肚里塞着一张揉皱的纸，字被什么粉末蹭花了。", "choices": ["蛾子聚过来的时候，离远一点", "蛾子怕声音，拍手就散", "蛾子只在白天出现"], "answer": 0, "note": "……离远一点。纸上的字是被翅膀上的粉蹭花的。"},
]
const LESSON_SECONDS := 12.0

var seed_value := 0
var day_events: Dictionary = {}
var said: Dictionary = {}
var lessons: Dictionary = {}
var lesson_key := ""          # the open lesson, "" when closed
var waiting: Variant = null   # {key, until, room}
var events: Array = []


func module_id() -> StringName:
	return &"school.days"


func state_version() -> int:
	return STATE_VERSION


func reset() -> void:
	day_events = {}
	said = {}
	lessons = {}
	lesson_key = ""
	waiting = null
	events = []


func set_seed(value: int) -> void:
	seed_value = value & 0xFFFFFFFF


func capture() -> Dictionary:
	return {"seed": seed_value, "day_events": day_events.duplicate(), "said": said.duplicate(), "lessons": lessons.duplicate(true)}


func validate(data: Dictionary) -> String:
	return "" if data.get("day_events") is Dictionary and data.get("lessons") is Dictionary else "特殊日或课堂状态无效"


func restore(data: Dictionary) -> void:
	reset()
	seed_value = int(data.get("seed", 0))
	day_events = (data["day_events"] as Dictionary).duplicate()
	said = (data.get("said", {}) as Dictionary).duplicate()
	lessons = (data["lessons"] as Dictionary).duplicate(true)


func take_events() -> Array:
	var out := events
	events = []
	return out


func _emit(kind: String, payload: Dictionary = {}) -> void:
	var e := payload.duplicate()
	e["kind"] = kind
	events.append(e)


# ---- special days ----

## day-events.js dayHash (32-bit integer mix, JavaScript semantics).
static func day_hash(seed_in: int, day: int) -> float:
	var h := (seed_in ^ _imul(day + 0x9e37, 0x85ebca6b)) & 0xFFFFFFFF
	h ^= h >> 13
	h = _imul(h, 0xc2b2ae35)
	h ^= h >> 16
	return float(h & 0xFFFFFFFF) / 4294967296.0


static func _imul(a: int, b: int) -> int:
	return ((a & 0xFFFFFFFF) * (b & 0xFFFFFFFF)) & 0xFFFFFFFF


func _had(id: String) -> bool:
	return day_events.values().has(id)


func roll(day: int) -> String:
	if day < FIRST_DAY:
		return "none"
	var u := day_hash(seed_value, day)
	if u < P["anniversary"]:
		return "none" if _had("anniversary") else "anniversary"
	if u < P["anniversary"] + P["occupied"]:
		return "none" if day_events.get(str(day - 1)) == "occupied" else "occupied"
	if u < P["anniversary"] + P["occupied"] + P["checkup"]:
		return "none" if day < CHECKUP_FIRST_DAY or _had("checkup") else "checkup"
	return "none"


func ensure(day: int) -> String:
	if not day_events.has(str(day)):
		day_events[str(day)] = roll(day)
	return String(day_events[str(day)])


## The special day in effect now (07:20 to 22:30 of that day).
func today(day: int, tsec: float) -> String:
	if tsec < 440.0 or tsec >= SchoolClock.LIGHTS_OUT + 10.0:
		return "none"
	var id := String(day_events.get(str(day), "none"))
	return id if SAY.has(id) else "none"


func drain_mul(day: int, tsec: float) -> float:
	return 0.5 if today(day, tsec) == "anniversary" else 1.0


func closed(act: String, day: int, tsec: float) -> bool:
	return today(day, tsec) == "occupied" and CLOSED.has(act)


func lesson_bonus(day: int, tsec: float) -> float:
	return 2.0 if today(day, tsec) == "occupied" else 0.0


func tick_day(day: int, tsec: float) -> void:
	ensure(day)
	var id := today(day, tsec)
	if id != "none" and not said.has(str(day)):
		said[str(day)] = true
		_emit("fact", {"what": "specialDay", "id": id})
		_emit("notice", {"text": SAY[id]})


# ---- desk lessons ----

static func lesson_key_of(day: int, tsec: float) -> String:
	return "%d:%d" % [day, int(SchoolClock.period_at(tsec)[0])]


## R at the desk: open the question, or offer to study until the bell, or stop studying.
## ctx: available (seated at the own seat in class and nothing dangerous), day, tsec, room.
func press(ctx: Dictionary) -> void:
	if waiting != null:
		waiting = null
		_emit("save")
		return
	if lesson_key != "" or not bool(ctx.get("available", false)):
		return
	var day := int(ctx["day"])
	var tsec := float(ctx["tsec"])
	var key := lesson_key_of(day, tsec)
	if lessons.has(key) and bool(lessons[key]["done"]):
		if not bool(lessons[key].get("waitUsed", false)):
			_emit("choice", {"menu": "wait", "text": "课堂任务已结束。整理笔记到下课：时间加快，恢复、同化与危险照常结算。遇到危险或集合预警立即停止，也可以随时按 R 停止。", "labels": ["开始整理（6 倍时间）", "现在离开座位"]})
		return
	if not lessons.has(key):
		lessons[key] = {"task": (day + int(floor(float(SchoolClock.period_at(tsec)[0]) / 5.0))) % TASKS.size(), "left": LESSON_SECONDS, "done": false}
	lesson_key = key
	var task: Dictionary = TASKS[int(lessons[key]["task"])]
	var title := "答卷边上的字" if bool(ctx.get("exam", false)) else ("被占的那节课" if today(day, tsec) == "occupied" else "课桌上的字")
	_emit("choice", {"menu": "lesson", "text": "%s\n%s" % [title, task["text"]], "labels": task["choices"], "timer": LESSON_SECONDS})


func answer(index: int, ctx: Dictionary) -> void:
	if lesson_key == "":
		return
	var r: Dictionary = lessons[lesson_key]
	lesson_key = ""
	if bool(r["done"]):
		return
	r["done"] = true
	if index < 0:
		_emit("notice", {"text": "我：老师把纸收走了。"})
		return
	var task: Dictionary = TASKS[int(r["task"])]
	var right := index == int(task["answer"])
	_emit("fact", {"what": "lesson", "task": int(r["task"]), "correct": right})
	if right:
		r["correct"] = true
		_emit("san", {"amount": 2.0 + lesson_bonus(int(ctx.get("day", 1)), float(ctx.get("tsec", 0.0))), "max": 100.0})
		_emit("notice", {"text": "我：" + String(task["note"])})
		_emit("record", {"id": "lesson:%d" % int(r["task"]), "text": String(task["note"]), "kind": "事实", "source": "课堂提醒"})
	else:
		_emit("notice", {"text": "我：老师没有说对不对，只让我把纸翻过去。"})
	_emit("save")


func start_wait(day: int, tsec: float, room: String) -> void:
	var key := lesson_key_of(day, tsec)
	if not lessons.has(key) or bool(lessons[key].get("waitUsed", false)):
		return
	lessons[key]["waitUsed"] = true
	waiting = {"key": key, "until": float(SchoolClock.period_at(tsec)[1]), "room": room}
	_emit("save")


## Studying stops at the bell, on leaving, or when anything needs attention.
func wait_allowed(ctx: Dictionary) -> bool:
	if waiting == null:
		return false
	var w: Dictionary = waiting
	return bool(ctx.get("available", false)) and not bool(ctx.get("quiet", false)) and w["key"] == lesson_key_of(int(ctx["day"]), float(ctx["tsec"])) 		and float(ctx["tsec"]) < float(w["until"]) and String(ctx.get("room", "")) == String(w["room"])
