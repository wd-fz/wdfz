class_name ExchangeModule
extends FeatureModule
## The international exchange visit and its public true ending 《外国语学生》, ported from the Web
## version (reference wd-fz.github.io@0bf508a, modules/exchange/exchange.js EXCHANGE_CFG / EXAM):
## rolled once per run (5 %); on day 2 from 09:00 a leader and three visitors wait outside the
## admin building's north side until 17:20; German and French checks (5 questions, 4 to pass, one
## retake each); qualifying grants the day's outing permit; departing walks the group along the
## navigation path to the north gate while up to three searchers patrol ahead and chase anyone they
## see away from the group. Losing the group for 4 s ends the chance. The ending cut is not ported.

const STATE_VERSION := 1
const CHANCE := 0.05
const MULTI := 0.15
const DAY := 2
const FROM := 540.0
const UNTIL := 1040.0
const PASS := 4
const QUESTIONS := 5
const EXAM_SAN := 6.0
const FOLLOW := 5.0
const WARN := 9.0
const GRACE := 4.0
const LEAD := 0.9
const SLOW := 0.6
const SEARCHERS := 3
const SEE_RANGE := 14.0
const CATCH_R := 1.2
const CHASE := 30.0
const TP_EVERY := 10.0
const TP_CHANCE := 0.25
const GAP := [1.2, 2.4, 3.6]
const U2M := CampusGeometry.U2M
const EXAM := {
	"de": {"n": "德语", "q": [["Bitte bleiben Sie bei der Gruppe.", "请跟着队伍", ["请在这里等", "请出示证件"]], ["Wo ist der Ausgang?", "出口在哪里", ["厕所在哪里", "现在几点"]],
		["Wir gehen jetzt zum Tor.", "我们现在去校门", ["我们现在去食堂", "我们现在去上课"]], ["Nicht zurückbleiben!", "别掉队", ["别说话", "别跑"]], ["Danke für Ihre Hilfe.", "谢谢你的帮助", ["请帮帮我", "不需要帮忙"]]]},
	"fr": {"n": "法语", "q": [["Restez avec le groupe, s'il vous plaît.", "请跟着队伍", ["请在这里等", "请出示证件"]], ["Où est la sortie ?", "出口在哪里", ["厕所在哪里", "现在几点"]],
		["Nous allons au portail.", "我们去校门", ["我们去食堂", "我们去上课"]], ["Ne restez pas en arrière !", "别掉队", ["别说话", "别跑"]], ["Merci pour votre aide.", "谢谢你的帮助", ["请帮帮我", "不需要帮忙"]]]},
}

var s: Dictionary = {}
var multilingual := false
var events: Array = []

var _rng := RandomNumberGenerator.new()
var _c: Dictionary = {}
var _nav: PatrolNav
var _gather := Vector2(1069, 1010)
var _gate := Vector2(1028, 190)
var _pending: Dictionary = {}


func _init(nav: PatrolNav = null, outside: Dictionary = {}, campus: Dictionary = {}) -> void:
	_nav = nav
	for o: Dictionary in outside.get("objects", []):
		if o["id"] == "admin":
			_gather = Vector2((float(o["x"]) + float(o["w"]) / 2.0) * 2.0, (float(o["y"]) - 10.0) * 2.0)
	var gn: Dictionary = campus.get("gates", {}).get("n", {"x": 514, "y": 95})
	_gate = Vector2(float(gn["x"]) * 2.0, float(gn["y"]) * 2.0)


func module_id() -> StringName:
	return &"story.exchange"


func state_version() -> int:
	return STATE_VERSION


func reset() -> void:
	s = {"hit": 0, "phase": "none", "tries": {"de": 0, "fr": 0}, "passed": {"de": 0, "fr": 0}, "warned": 0, "lag": 0.0, "prog": 0.0, "order": {}, "search": [], "how": ""}
	multilingual = false
	events = []
	_pending = {}


## A new run rolls the visit (5 %) and the quiet second-language background (15 %).
func roll(seed_value: int) -> void:
	_rng.seed = seed_value
	s["hit"] = 1 if _rng.randf() < CHANCE else 0
	multilingual = _rng.randf() < MULTI


func capture() -> Dictionary:
	var out := s.duplicate(true)
	out.erase("path")
	out["multi"] = multilingual
	out["rng"] = _rng.state
	return out


func validate(data: Dictionary) -> String:
	if not (String(data.get("phase", "none")) in ["none", "waiting", "qualified", "escort", "over", "done"]):
		return "交流团状态无效"
	return ""


func restore(data: Dictionary) -> void:
	reset()
	for k: String in s:
		if data.has(k):
			s[k] = data[k]
	multilingual = bool(data.get("multi", false))
	if data.get("rng") is float or data.get("rng") is int:
		_rng.state = int(data["rng"])


## ctx: scene, x, y, day, tsec, dead, busy, clock.
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


# ---- the route ----

func _route() -> Dictionary:
	if s.has("path"):
		return s["path"]
	var pts: Array = []
	if _nav != null:
		var a := _nav.snap("out", PatrolNav.point("out", _gather.x, _gather.y))
		var b := _nav.snap("out", PatrolNav.point("out", _gate.x, _gate.y))
		for p: Dictionary in _nav.path(a, b):
			pts.append(Vector2(float(p["x"]), float(p["y"])))
	if pts.size() < 2:
		pts = [_gather, _gate]
	var acc: Array = [0.0]
	for i in range(1, pts.size()):
		acc.append(float(acc[i - 1]) + (pts[i] as Vector2).distance_to(pts[i - 1]))
	s["path"] = {"pts": pts, "acc": acc, "len": float(acc[acc.size() - 1])}
	return s["path"]


func at(dist: float) -> Dictionary:
	var r := _route()
	var d := clampf(dist, 0.0, float(r["len"]))
	var acc: Array = r["acc"]
	var pts: Array = r["pts"]
	var i := 1
	while i < acc.size() - 1 and float(acc[i]) < d:
		i += 1
	var a: Vector2 = pts[i - 1]
	var b: Vector2 = pts[i]
	var seg := float(acc[i]) - float(acc[i - 1])
	var k := (d - float(acc[i - 1])) / seg if seg > 0.0 else 0.0
	return {"p": a.lerp(b, k), "yaw": atan2(b.y - a.y, b.x - a.x)}


## Leader first, then the three visitors (world points).
func members() -> Array:
	var out: Array = []
	if s["phase"] == "escort":
		out.append(at(float(s["prog"]))["p"])
		for m: float in GAP:
			out.append(at(float(s["prog"]) - m / U2M)["p"])
	else:
		out.append(_gather)
		for i in GAP.size():
			out.append(_gather + Vector2(float(i - 1) * 12.0, -14.0))
	return out


func visible() -> bool:
	return s["phase"] in ["waiting", "qualified", "escort"]


func tail_dist() -> float:
	if String(_c.get("scene", "")) != "out":
		return INF
	var best := INF
	for p: Vector2 in members():
		best = minf(best, _me().distance_to(p) * U2M)
	return best


func near_leader() -> bool:
	return String(_c.get("scene", "")) == "out" and s["phase"] in ["waiting", "qualified"] and _me().distance_to(members()[0]) * U2M < 2.6


func hint() -> String:
	if not near_leader():
		return ""
	return "跟带队老师说：出发" if s["phase"] == "qualified" else "国际交流接待登记"


# ---- registration and the checks ----

func use_here() -> bool:
	if not near_leader():
		return false
	if s["phase"] == "qualified":
		depart()
		return true
	var labels: Array = []
	var ids: Array = []
	if multilingual:
		labels.append("「我可以帮忙接待。」（Ich helfe gern. / Je peux aider.）")
		ids.append("multi")
	for k: String in ["de", "fr"]:
		if not int(s["passed"][k]) and int(s["tries"][k]) < 2:
			labels.append("参加%s资格考核（%d 题，答对 %d 题合格%s）" % [EXAM[k]["n"], QUESTIONS, PASS, "，补考" if int(s["tries"][k]) > 0 else ""])
			ids.append(k)
	_pending = {"kind": "menu", "ids": ids}
	_emit("choice", {"text": ("登记表上印着德语和法语。这两种发音，我以前都听过。\n" if multilingual else "登记表上印着德语和法语。接待的同学要能听懂集合和跟队的话。\n") +
		"德语：%s　法语：%s" % ["合格" if int(s["passed"]["de"]) else "未考", "合格" if int(s["passed"]["fr"]) else "未考"], "labels": labels})
	return true


func _order(k: String) -> Array:
	if not (s["order"] as Dictionary).has(k):
		var o: Array = []
		for _i in QUESTIONS:
			o.append(_rng.randi() % 3)
		s["order"][k] = o
	return s["order"][k]


func _ask(k: String, i: int, right: int) -> void:
	if i >= QUESTIONS:
		_exam_done(k, right)
		return
	var item: Array = EXAM[k]["q"][i]
	var opts: Array = (item[2] as Array).duplicate()
	var pos := int(_order(k)[i])
	opts.insert(pos, item[1])
	_pending = {"kind": "exam", "lang": k, "i": i, "right": right, "pos": pos}
	_emit("choice", {"text": "%s考核 · 第 %d 题（共 %d 题）\n「%s」是什么意思？" % [EXAM[k]["n"], i + 1, QUESTIONS, item[0]], "labels": opts, "locked": true})


func _exam_done(k: String, right: int) -> void:
	var ok := right >= PASS
	_emit("fact", {"what": "exam", "lang": k, "right": right, "ok": ok})
	if ok:
		s["passed"][k] = 1
		_say("我：%s答对了 %d 题。带队老师点了点头。" % [EXAM[k]["n"], right])
	else:
		_emit("san", {"amount": -EXAM_SAN, "min": 0.0})
		_say("我：%s只答对了 %d 题。%s" % [EXAM[k]["n"], right, "还能补考一次。" if int(s["tries"][k]) < 2 else "没有机会了。"])
	if int(s["passed"]["de"]) and int(s["passed"]["fr"]):
		_qualify("exam")
		return
	if (not int(s["passed"]["de"]) and int(s["tries"]["de"]) >= 2) or (not int(s["passed"]["fr"]) and int(s["tries"]["fr"]) >= 2):
		s["phase"] = "over"
		_say("我：带队老师把登记表收了回去。这次接待轮不到我了。")
		_emit("fact", {"what": "closed"})


func _qualify(how: String) -> void:
	s["phase"] = "qualified"
	s["how"] = how
	_emit("permit", {"until": (float(_c.get("day", DAY)) - 1.0) * 1440.0 + SchoolClock.LIGHTS_OUT})
	_emit("fact", {"what": "qualified", "how": how})
	_say("我：带队老师递给我一张临时接待证：「今天跟着我们。别掉队。」\n（当天的考试、学生会检查都已登记豁免。）")


func choose(index: int) -> void:
	var p := _pending
	_pending = {}
	match String(p.get("kind", "")):
		"menu":
			if index < 0 or index >= (p["ids"] as Array).size():
				return
			var id := String(p["ids"][index])
			if id == "multi":
				_qualify("multilingual")
			else:
				s["tries"][id] = int(s["tries"][id]) + 1
				_ask(id, 0, 0)
		"exam":
			var right := int(p["right"]) + (1 if index == int(p["pos"]) else 0)
			_ask(String(p["lang"]), int(p["i"]) + 1, right)


func depart() -> void:
	_route()
	s["phase"] = "escort"
	s["prog"] = 0.0
	s["lag"] = 0.0
	s["warned"] = 0
	var r := _route()
	var list: Array = []
	for i in SEARCHERS:
		var p: Vector2 = at(float(r["len"]) * (0.3 + 0.22 * i))["p"]
		list.append({"x": p.x + 20.0 * (i - 1), "y": p.y + 15.0, "mode": "patrol", "tp": 0.0})
	s["search"] = list
	_emit("fact", {"what": "depart"})
	_say("广播：「全校注意，现在核对离校名单。各区域开始检查。」")


# ---- the simulation step ----

func tick(dt: float) -> void:
	if not (dt > 0.0) or bool(_c.get("dead", false)) or not int(s["hit"]):
		return
	var day := int(_c.get("day", 1))
	var t := float(_c.get("tsec", 0.0))
	if s["phase"] == "none" and day == DAY and t >= FROM and t < UNTIL and not bool(_c.get("busy", false)):
		s["phase"] = "waiting"
		_emit("fact", {"what": "arrive"})
		_say("广播：「今天有一个国际交流团来访。需要会德语、法语的同学协助接待，请到行政楼北门外登记。」")
		return
	if s["phase"] in ["waiting", "qualified"] and (day != DAY or t >= UNTIL):
		s["phase"] = "over"
		return
	if s["phase"] != "escort":
		return
	var r := _route()
	var d := tail_dist()
	var v := LEAD * 21.0 * dt
	if d <= FOLLOW:
		s["lag"] = 0.0
		s["prog"] = minf(float(r["len"]), float(s["prog"]) + v)
	elif d <= WARN:
		s["lag"] = 0.0
		s["prog"] = minf(float(r["len"]), float(s["prog"]) + v * SLOW)
	else:
		var first := float(s["lag"]) <= 0.0
		s["lag"] = float(s["lag"]) + dt
		s["warned"] = 1
		if float(s["lag"]) >= GRACE:
			s["phase"] = "over"
			s["search"] = []
			_emit("fact", {"what": "lost", "why": "lag"})
			_say("我：队伍拐过前面的楼角，不见了。我掉队了。")
			return
		if first:
			_say("我：队伍在前面停了一下，有人回头找我。")
	if float(s["prog"]) >= float(r["len"]) and d <= FOLLOW:
		s["phase"] = "done"
		s["search"] = []
		_emit("fact", {"what": "arrived", "together": not int(s["warned"]), "how": s["how"]})
		_emit("ending", {"id": "international"})
		return
	_search_tick(dt, d <= FOLLOW)


func _search_tick(dt: float, with_group: bool) -> void:
	var outside := String(_c.get("scene", "")) == "out"
	var me := _me()
	for i in (s["search"] as Array).size():
		var h: Dictionary = s["search"][i]
		h["tp"] = float(h["tp"]) + dt
		var hp := Vector2(float(h["x"]), float(h["y"]))
		var d := hp.distance_to(me) * U2M if outside else INF
		var sees := false
		if outside and d <= SEE_RANGE:
			var los: Callable = _c.get("los", Callable())
			sees = not los.is_valid() or bool(los.call(hp, me))
		if sees and not with_group:
			h["mode"] = "chase"
		elif with_group and h["mode"] == "chase":
			h["mode"] = "patrol"
		if h["mode"] == "chase" and outside:
			var dir := (me - hp).normalized()
			hp += dir * CHASE * dt
			h["x"] = hp.x
			h["y"] = hp.y
			if hp.distance_to(me) * U2M < CATCH_R:
				s["search"] = []
				_emit("kill", {"msg": "搜查员看了看名单，又看了看我。名单上没有我。", "fx": "grip", "source": "search"})
				return
			continue
		var target: Vector2 = at(float(s["prog"]) + (40.0 + i * 35.0) / U2M)["p"]
		var to := target - hp
		if to.length() > 4.0:
			hp += to.normalized() * minf(to.length(), 16.0 * dt)
			h["x"] = hp.x
			h["y"] = hp.y
		if float(h["tp"]) >= TP_EVERY:
			h["tp"] = 0.0
			if _rng.randf() < TP_CHANCE and not sees:
				var p: Vector2 = at(float(s["prog"]) + (60.0 + i * 30.0) / U2M)["p"]
				h["x"] = p.x + 18.0
				h["y"] = p.y
