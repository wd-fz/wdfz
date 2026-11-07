class_name FakeNormalModule
extends FeatureModule
## The note on day 1 and the "fake normal" second day (systems.js FN_CHANCE / advanceGameTime note,
## story.js FN_EVENTS / fnTick, reference wd-fz.github.io@0bf508a): with a 30 % roll taken when the
## note appears at lights out, day 2 offers four everyday moments; laughing adds 14, holding it in 5;
## at 100 the player laughs to death, after four moments the day lets go. The crowd of "normal
## people" (fnPeople) is not drawn.

const STATE_VERSION := 1
const CHANCE := 0.30
const EVENTS := [
	{"where": ["teach"], "seen": "有同学拍我肩膀，问我去不去打球。", "real": "我回头。我后面那两排座位是空的。"},
	{"where": ["teach"], "seen": "课代表把作业收上来了，问我交没交。", "real": "他手里那摞本子最上面一本，名字是我的。"},
	{"where": ["canteen"], "seen": "食堂阿姨多给我打了一勺菜。", "real": "勺子下面那层一直是温的。窗户外面没有人在排队。"},
	{"where": ["out"], "seen": "保安在门口冲我点头。", "real": "他点头的幅度和昨天一模一样。我数了：三下。"},
	{"where": ["teach"], "seen": "同桌借我的笔，说还挺好写。", "real": "我借出去的笔。我手里的笔还在。"},
	{"where": ["teach", "lab"], "seen": "广播里念到我的名字，说我考得不错。", "real": "念名字的那个人，一个字也没有换气。"},
	{"where": ["out"], "seen": "体育课点名，点到我的时候我答了一声。", "real": "没有人记。名单上那一行本来就是空的。"},
	{"where": ["teach"], "seen": "走廊里有人喊我，说快点要上课了。", "real": "那个声音是从我背后贴着我耳朵发出来的。"},
	{"where": ["any"], "seen": "手机收到一条消息：今天放学早。", "real": "发消息的人没有头像。聊天记录里只有这一条。"},
	{"where": ["teach"], "seen": "黑板右上角写着今天的日期。", "real": "日期没变过。昨天也是这一天。"},
	{"where": ["dorm"], "seen": "室友问我几点了，我说快熄灯了。", "real": "宿舍里只有我一个人的床铺是铺开的。"},
	{"where": ["admin", "teach"], "seen": "老师叫我去办公室，说有事找我谈。", "real": "办公室里所有的椅子都朝门摆着，没有人坐过。"},
]

var fn: Dictionary = {}
var laughs := 0
var events: Array = []
var _rng := RandomNumberGenerator.new()
var _pending := -1


func module_id() -> StringName:
	return &"story.fake_normal"


func state_version() -> int:
	return STATE_VERSION


func reset() -> void:
	fn = {"v": 0.0, "on": false, "note": false, "roll": null, "n": 0, "next": 0.0, "shown": false, "used": {}, "left": 4, "done": false}
	laughs = 0
	events = []
	_pending = -1


func set_seed(value: int) -> void:
	_rng.seed = value


func capture() -> Dictionary:
	var out := fn.duplicate(true)
	out["laughs"] = laughs
	out["rng"] = _rng.state
	return out


func validate(data: Dictionary) -> String:
	if not SaveSchema.number_in(data.get("v", 0.0), 0, 200):
		return "假正常状态无效"
	return ""


func restore(data: Dictionary) -> void:
	reset()
	for k: String in fn:
		if data.has(k):
			fn[k] = data[k]
	var used := {}
	for k: Variant in (fn["used"] as Dictionary):
		used[int(k)] = true
	fn["used"] = used
	laughs = int(data.get("laughs", 0))
	if data.get("rng") is float or data.get("rng") is int:
		_rng.state = int(data["rng"])


func take_events() -> Array:
	var out := events
	events = []
	return out


func _emit(kind: String, payload: Dictionary = {}) -> void:
	var e := payload.duplicate()
	e["kind"] = kind
	events.append(e)


## Day 1 at lights out: the folded note, and the roll for day 2.
func lights_out_note() -> void:
	if bool(fn["note"]):
		return
	fn["note"] = true
	if fn["roll"] == null:
		fn["roll"] = 1 if _rng.randf() < CHANCE else 0
	_emit("notice", {"text": "我：口袋里多了一张对折的纸。上面写着——灯前看字字如旧，月下认人人已非。　　　　　——笑时莫出声。"})


## The second day begins.
func day_two() -> void:
	if bool(fn["note"]) and fn["roll"] == null:
		fn["roll"] = 0
	if bool(fn["note"]) and int(fn["roll"]) == 1 and not bool(fn["on"]) and int(fn["n"]) == 0:
		fn["on"] = true
		fn["v"] = 0.0
		fn["next"] = 10.0
		fn["used"] = {}
		fn["left"] = 4
		fn["done"] = false
		_emit("notice", {"text": "我：第二天。所有东西都回到了原来的位置，颜色也回来了。"})


func active() -> bool:
	return bool(fn["on"])


static func where_tag(scene: String, host: String) -> String:
	if scene == "out" or scene == "":
		return "out"
	if scene == "canteen1":
		return "canteen"
	if host in ["dormN", "dormS"]:
		return "dorm"
	if host in ["admin", "lab", "teach"]:
		return host
	return "out"


## ctx: tag (where_tag), busy (a choice open or a quiet inspection), dead.
func tick(dt: float, ctx: Dictionary) -> void:
	if not bool(fn["on"]) or bool(ctx.get("dead", false)) or _pending >= 0:
		return
	if float(fn["v"]) >= 100.0:
		fn["on"] = false
		_emit("kill", {"msg": "你笑得停不下来。笑了很久。", "fx": "laugh", "source": "laugh"})
		return
	if int(fn["left"]) <= 0:
		fn["on"] = false
		fn["done"] = true
		_emit("fact", {"done": true, "laughs": laughs})
		_emit("notice", {"text": "我：……天黑了。刚才那些都很正常，正常得不对。"})
		return
	if float(fn["v"]) > 72.0 and not bool(fn["shown"]):
		fn["shown"] = true
		_emit("hurt")
		_emit("notice", {"text": "我：……刚才那些，我是不是笑得太大声了。"})
	if bool(ctx.get("busy", false)):
		return
	var tag := String(ctx.get("tag", "out"))
	var pool: Array = []
	for i in EVENTS.size():
		if (fn["used"] as Dictionary).has(i):
			continue
		var wz: Array = EVENTS[i]["where"]
		if wz.has("any") or wz.has(tag):
			pool.append(i)
	if pool.is_empty():
		return
	fn["next"] = float(fn["next"]) - dt
	if float(fn["next"]) > 0.0:
		return
	fn["next"] = 22.0 + _rng.randf() * 12.0
	var pick: int = pool[_rng.randi() % pool.size()]
	fn["used"][pick] = true
	fn["n"] = int(fn["n"]) + 1
	fn["left"] = maxi(0, int(fn["left"]) - 1)
	_pending = pick
	_emit("choice", {"text": "看起来是——\n" + String(EVENTS[pick]["seen"]), "labels": ["笑一下", "不笑，装作没这回事"]})


func choose(index: int) -> void:
	if _pending < 0:
		return
	var e: Dictionary = EVENTS[_pending]
	_pending = -1
	var laughed := index == 0
	fn["v"] = float(fn["v"]) + (14.0 if laughed else 5.0)
	if laughed:
		laughs += 1
	_emit("notice", {"text": "其实——" + String(e["real"])})
	_emit("toast", {"text": "（你笑出了声）" if laughed else "（你忍住了）"})
