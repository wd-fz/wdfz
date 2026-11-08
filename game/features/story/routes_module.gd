class_name RoutesModule
extends FeatureModule
## Escape routes and endings, ported from the Web version (reference wd-fz.github.io@0bf508a):
## the whitelist route (interact.js useTerminal / useData / tryGateWest, modules/phone-network
## WhitelistSync.commit, story.js FaceChallenge), the trash-bin death, the three gates' lines, and
## story.js ENDINGS / triggerEnding. Ported routes so far: 《白名单》. The other public routes
## (the car, the portal, 《网安仙人》, 《放学》) keep their cards here and arrive with their systems.
## Undiscovered routes are kept out of player-facing lists until reached.

const STATE_VERSION := 1
const FACE_WRONG_SAN := 4.0
const GATE_REACH := 70.0
const SC := 2.0
const QUESTIONS := [
	{"text": "方程 x² − 5x + 6 = 0 的较大根是多少？", "choices": ["2", "3", "6"], "answer": 1},
	{"text": "同时掷两枚均匀六面骰，点数之和不小于 10 的概率是多少？", "choices": ["1/12", "1/6", "1/4"], "answer": 1},
	{"text": "等差数列首项为 2、公差为 3，第 8 项是多少？", "choices": ["20", "23", "26"], "answer": 1},
	{"text": "函数 y = x² − 4x + 7 的最小值是多少？", "choices": ["3", "4", "7"], "answer": 0},
	{"text": "sin 30° + cos 60° 等于多少？", "choices": ["1/2", "1", "√3"], "answer": 1},
	{"text": "log₂ 32 等于多少？", "choices": ["4", "5", "16"], "answer": 1},
	{"text": "自由落体 2 秒末的速度约是多少？（g 取 10 m/s²）", "choices": ["10 m/s", "20 m/s", "40 m/s"], "answer": 1},
	{"text": "1 mol 水（H₂O）的质量约是多少克？", "choices": ["16", "18", "20"], "answer": 1},
	{"text": "「先天下之忧而忧，后天下之乐而乐」出自哪一篇？", "choices": ["《岳阳楼记》", "《醉翁亭记》", "《出师表》"], "answer": 0},
	{"text": "阻值 6 Ω 和 3 Ω 的两个电阻并联，总电阻是多少？", "choices": ["2 Ω", "4.5 Ω", "9 Ω"], "answer": 0},
]
const EXPLANATIONS := [
	"分解为 (x−2)(x−3)=0，较大根是 3。",
	"满足条件的点数有 6 种，共 36 种等可能结果，所以是 1/6。",
	"第 8 项是 2+(8−1)×3=23。",
	"配方得到 (x−2)²+3，最小值是 3。",
	"sin 30° 和 cos 60° 都是 1/2，相加为 1。",
	"2 的 5 次方是 32，因此结果为 5。",
	"由 v=gt 得 10×2=20 m/s。",
	"两个氢加一个氧：2×1+16=18 g/mol。",
	"这是范仲淹《岳阳楼记》中的句子。",
	"并联电阻满足 1/R=1/6+1/3=1/2，所以是 2 Ω。",
]
## story.js ENDINGS (public ones): title, true ending, lines.
const ENDINGS := {
	"beast": {"t":"《先 辈》", "secret":true, "l":["门是被从外面撞开的。","你看清了那个背影——穿着很多年前的校服，一直在往外跑。","你跟着他跑了出去。","整座学校，第一次有了颜色。"]},
	"dismissal": {"t": "《放学》", "true": true, "l": ["通知稿最后一句，从学校每一只喇叭里同时响起。", "长铃响着，同学们收好书包，从北门走了出去。", "登记簿翻到新的一页：放学 · 全体。", "你回头时，教学楼的灯一层一层熄了。", "明天见。"]},
	"cyber": {"t": "《网安仙人》", "true": true, "l": ["服务器接受了最后一条指令。名单、门禁和巡察停止运行。", "AnthroPrank AI（安抄派智能）的校园试点终止了。更早的纸质档案和断链后的回执，仍没有答案。", "您未能完全理解里世界"]},
	"car": {"t": "《闸 门》", "true": true, "l": ["你踩下油门的时候，雨刷自己动了起来。", "后视镜里，教学楼的窗户一扇一扇地暗下去，像有人在挨个关灯。", "开出校门很远，你才敢看一眼副驾。", "那里放着一张学生证。照片上的人，你终于认得了。"]},
	"face": {"t": "《白名单》", "true": true, "l": ["闸机「嘀」地亮了一下绿光。", "你走出去，回头看了一眼——", "里面的天还是黑白的。所有窗口后面都站着一个人，在目送你。", "你的名字从那天起，一直留在白名单的最后一行。"]},
	"international": {"t": "《外国语学生》", "true": true, "l": ["队尾的人回头看了一眼，确认你还在。", "门卫核对的是接待名单。搜查员停在门里，没有再往前走。", "门外的颜色和声音都很平常。有人把临时接待证递还给你。", "证上的学校名字，好像和你记得的不太一样。"]},
	"portal": {"t": "《门》", "true": true, "l": ["光圈合上之前，你回头看了一眼。", "实验台、显微镜、离心机，还有教室里那一排排低着的头——都在原地，一动不动。", "你没有再回头。", "门的那一边是一个普通的下午。铃响了，有人在走廊里叫你的名字，你答应了一声。"]},
}

## Wrong quiz answers of this run: every swap replaced a question that was answered wrong.
func wrong_answers() -> int:
	return maxi(0, int(face_quiz.get("used", []).size()) - 3) if not face_quiz.is_empty() else 0


## The programming-club talent: the first wrong answer costs nothing (Talent.faceRemedy).
var face_remedy: Callable
var hacked := false
var beast_drop := false
var data_synced := false
var data_source := ""
var face_quiz: Dictionary = {}
var clues: Dictionary = {}
var ending := ""
var events: Array = []

var _rng := RandomNumberGenerator.new()
var _delayed: Array = []
var _pending := {}
var _campus: Dictionary = {}


func _init(campus: Dictionary = {}) -> void:
	_campus = campus


func module_id() -> StringName:
	return &"story.routes"


func state_version() -> int:
	return STATE_VERSION


func reset() -> void:
	beast_drop = false
	hacked = false
	data_synced = false
	data_source = ""
	face_quiz = {}
	clues = {}
	ending = ""
	events = []
	_delayed = []
	_pending = {}
	_rng.randomize()


func set_seed(value: int) -> void:
	_rng.seed = value


func capture() -> Dictionary:
	return {"hacked": hacked, "beast_drop": beast_drop, "data": data_synced, "data_source": data_source, "face_quiz": face_quiz.duplicate(true), "clues": clues.duplicate(),
		"ending": ending, "delayed": _delayed.duplicate(true), "rng_seed": str(_rng.seed), "rng_state": str(_rng.state)}


func validate(data: Dictionary) -> String:
	if not data.get("beast_drop",false) is bool:
		return "隔间进度无效"
	if not data.get("hacked") is bool or not data.get("data") is bool:
		return "路线状态无效"
	if data["data"] and not data["hacked"]:
		return "白名单同步早于写入"
	var q: Variant = data.get("face_quiz", {})
	if not q is Dictionary:
		return "白名单题目无效"
	if not (q as Dictionary).is_empty():
		var order: Variant = q.get("order")
		if not order is Array or (order as Array).size() != 3 or not SaveSchema.is_integer(q.get("done"), 0, 3) or not q.get("used") is Array:
			return "白名单题目无效"
		for i: Variant in order:
			if not SaveSchema.is_integer(i, 0, QUESTIONS.size() - 1):
				return "白名单题号无效"
	if not String(data.get("ending", "")) in [""] + ENDINGS.keys():
		return "结局编号无效"
	if not String(data.get("rng_state", "")).is_valid_int():
		return "路线随机状态无效"
	return ""


func restore(data: Dictionary) -> void:
	beast_drop = bool(data.get("beast_drop",false))
	hacked = bool(data["hacked"])
	data_synced = bool(data["data"])
	data_source = String(data.get("data_source", ""))
	face_quiz = data.get("face_quiz", {}).duplicate(true)
	for key: String in ["order", "used"]:
		if face_quiz.has(key):
			var ints: Array = []
			for v: Variant in face_quiz[key]:
				ints.append(int(v))
			face_quiz[key] = ints
	if face_quiz.has("done"):
		face_quiz["done"] = int(face_quiz["done"])
	clues = data.get("clues", {}).duplicate()
	ending = String(data.get("ending", ""))
	_delayed = data.get("delayed", []).duplicate(true)
	_pending = {}
	_rng.seed = int(String(data.get("rng_seed", "0")))
	_rng.state = int(String(data["rng_state"]))
	events = []


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


func _clue(id: String, day: int) -> void:
	if not clues.has(id):
		clues[id] = day


## Delayed lines (os2later) count simulation seconds.
func tick(dt: float) -> void:
	for d: Dictionary in _delayed:
		d["t"] = float(d["t"]) - dt
	while not _delayed.is_empty() and float(_delayed[0]["t"]) <= 0.0:
		_say(String(_delayed[0]["text"]))
		_delayed.pop_front()


# ---- terminals (interact.js useTerminal / useData, WhitelistSync) ----

func use_terminal(scene: String, has_usb: bool, day: int) -> void:
	if scene != "lab3":
		_say("我：这台终端连不上。")
		return
	if hacked:
		_say("我：白名单里已经有我那一行了。光标还在闪，像在等我再写点什么。")
		return
	if not has_usb:
		_say("我：屏幕上是一串我看不懂的东西。旁边贴着一张便签：「门禁 U 盘插这里」。")
		_clue("usb", day)
		return
	hacked = true
	_emit("record", {"id": "whitelistWritten", "text": "网络中心已经写入我的学号。后台记录里，同一个名字对应着不同时期的照片。下一步要到行政楼三楼同步数据。", "kind": "验证", "source": "实验楼三楼 · 网络中心"})
	_clue("comp", day)
	_say("我：U 盘插进去，屏幕自己跳出一个窗口，光标在最后一行闪。我输了自己的学号。机柜同时闪了一下。")
	_delayed.append({"t": 5.2, "text": "我：还得去行政楼三楼，把数据同步过去。"})


func use_data(scene: String) -> void:
	if scene != "admin3":
		_say("我：这台机器不归我管。")
		return
	if not hacked:
		_say("我：得先在实验楼三楼的网络中心写入白名单。")
		return
	if data_synced:
		_emit("toast", {"text": "白名单数据已经同步"})
		return
	sync("terminal")


## WhitelistSync.commit (the admin3 machine or the phone).
func sync(source: String) -> bool:
	if not hacked:
		_say("我：得先在实验楼三楼的网络中心写入白名单。")
		return false
	if data_synced:
		_emit("toast", {"text": "白名单数据已经同步"})
		return true
	data_synced = true
	data_source = source
	_emit("record", {"id": "whitelistSynced", "text": "白名单同步完成：门禁认的是学号与照片。西小门现在认得我了。", "kind": "验证", "source": "手机 · 门禁同步" if source == "phone" else "行政楼三楼 · 门禁机"})
	_say("我：同步完成。照片底下写着：已登记。西小门现在认得我了。")
	return true


# ---- the gates ----

## Which gate the player stands at (GATE_HINT order: north, west, south); "" if none.
func gate_at(w: Vector2) -> String:
	var gates: Dictionary = _campus.get("gates", {})
	for key: String in ["n", "w", "s"]:
		if gates.has(key) and Vector2(float(gates[key]["x"]) * SC, float(gates[key]["y"]) * SC).distance_to(w) < GATE_REACH:
			return key
	return ""


static func gate_name(key: String) -> String:
	return {"n": "校门", "w": "西小门", "s": "南门"}.get(key, "")


func use_gate(key: String, day: int) -> void:
	match key:
		"n":
			_say("我：北门的闸机屏幕上显示：「查无此人」。门外的路上没有车，也没有声音，一直延伸到雾里。")
			_clue("gaten", day)
		"s":
			_say("我：南门锁着，锁上全是锈。门缝外面——是另一个南门。")
		"w":
			if not hacked or not data_synced:
				_say("我：小门上挂着锁，旁边那台闸机的屏幕亮着：「未登记」。")
				_clue("gatew", day)
				return
			face_open()


# ---- the whitelist quiz (story.js FaceChallenge) ----

func _quiz() -> Dictionary:
	var q := face_quiz
	var ok := q.has("order") and (q["order"] as Array).size() == 3
	if ok:
		var seen_ids := {}
		for i: int in q["order"]:
			ok = ok and i >= 0 and i < QUESTIONS.size() and not seen_ids.has(i)
			seen_ids[i] = true
	if not ok:
		var pool: Array = range(QUESTIONS.size())
		var order: Array = []
		while order.size() < 3:
			order.append(pool.pop_at(int(floor(_rng.randf() * pool.size()))))
		face_quiz = {"order": order, "done": 0, "used": order.duplicate()}
	face_quiz["done"] = clampi(int(face_quiz["done"]), 0, 3)
	return face_quiz


func _swap(q: Dictionary) -> void:
	var left: Array = []
	for i in QUESTIONS.size():
		if not (q["used"] as Array).has(i) and not (q["order"] as Array).has(i):
			left.append(i)
	if left.is_empty():
		return
	var next: int = left[int(floor(_rng.randf() * left.size()))]
	q["order"][int(q["done"])] = next
	q["used"].append(next)


func face_open() -> void:
	var q := _quiz()
	if int(q["done"]) >= 3:
		_pending = {"handler": "face_pass"}
		_emit("choice", {"text": "闸机亮起绿灯。外面的路安静得出奇。", "labels": ["通过闸机", "暂时留下"]})
		return
	var qid: int = q["order"][int(q["done"])]
	var question: Dictionary = QUESTIONS[qid]
	var labels: Array = (question["choices"] as Array).duplicate()
	labels.append("暂时离开")
	_pending = {"handler": "face_question", "qid": qid}
	_emit("choice", {"text": "白名单验证 %d/3：%s" % [int(q["done"]) + 1, question["text"]], "labels": labels})


## The open choice was answered (index -1: dismissed).
func choose(index: int, diff: String) -> void:
	var pending := _pending
	_pending = {}
	if pending.is_empty() or index < 0:
		return
	match pending["handler"]:
		"beast":
			if index == 0:
				ending = "beast"
				_emit("ending", {"id":"beast"})
			else:
				_say("我：门后没有再催促。")
		"face_pass":
			if index == 0:
				ending = "face"
				_emit("ending", {"id": "face"})
		"face_retry":
			if index == 0:
				face_open()
		"face_question":
			var qid: int = pending["qid"]
			var question: Dictionary = QUESTIONS[qid]
			if index >= (question["choices"] as Array).size():
				return
			var q := _quiz()
			if index == int(question["answer"]):
				q["done"] = int(q["done"]) + 1
				face_open()
				_emit("fact_face", {"correct": true})
				return
			var loss := 0.0 if face_remedy.is_valid() and bool(face_remedy.call()) else FACE_WRONG_SAN * (1.15 if diff == "hard" else 0.82)
			_emit("san", {"amount": -loss, "min": 0.0})
			var feedback: String = EXPLANATIONS[qid]
			_emit("record", {"id": "face:" + str(qid), "text": feedback, "kind": "验证", "source": "西小门 · 验证反馈"})
			_swap(q)
			_pending = {"handler": "face_retry"}
			_emit("choice", {"text": "验证未通过。耳边猛地响了一下。" + feedback + " 已通过的题目仍然保留。", "labels": ["继续验证", "先离开"]})
			_emit("fact_face", {"correct": false})


# ---- the trash bin (story.js tryTrashRoute) ----

## items.js dropSelected / inBeastWindow: the successful inventory removal must
## happen first. The one-second school-clock window is half a real second.
func offer_item(room: Variant, w: Vector2, tsec: float, day: int) -> bool:
	if room == null or room["id"] != "teach1" or beast_drop or tsec < 705.0+14.0/60.0 or tsec >= 705.0+15.0/60.0:
		return false
	if not in_stall(room,w):
		return false
	beast_drop = true
	_clue("beast",day)
	_say('我：东西刚落地，就被地砖缝里的什么接住了。很轻的一声："嗯。" 第三个隔间的门锁，自己弹开了。')
	_emit("save")
	return true


static func in_stall(room: Variant, w: Vector2) -> bool:
	if room == null:
		return false
	var col := floori((w.x-float(room["ox"]))/float(room["tw"]))
	var row := floori((w.y-float(room["oy"]))/float(room["th"]))
	return CampusGeometry.tile_at(room,w) in ["B","G"] or (room.get("host")=="teach" and col>=58 and col<=61 and row>=16 and row<=19)


func open_stall(scene: String) -> bool:
	if scene != "teach1" or not beast_drop:
		return false
	_pending = {"handler":"beast"}
	_emit("choice", {"text":"门后传来一个声音：「你愿意跟我一起走吗？」", "labels":["跟上","先等等"]})
	return true

func use_trash(scene: String, day: int) -> void:
	if scene != "trash1":
		_say("我：这个桶太小了。")
		return
	_clue("trash", day)
	_emit("kill", {"msg": "桶盖合上了。外面有人敲了两下，像在确认里面有没有人。", "fx": "trash", "source": "trash"})


## Card data for an ending (title, tag, lines).
static func card(id: String) -> Dictionary:
	var e: Dictionary = ENDINGS.get(id, {})
	if e.is_empty():
		return {}
	return {"title": e["t"], "tag": "真 结 局" if e.get("true", false) else "", "lines": e["l"]}
