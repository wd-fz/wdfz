class_name RollcallCard
extends RefCounted
## One physical name card per student. Attendance and personal attendance duties
## are still settled by SchoolModule. A counterfoil belongs to this student.
const COST := 18.0
const LOOK_DOWN := -0.48
const EXIT_OFFSET := 24.0 # Original campus units, east of the old boundary wall.
const EXIT_NORTH := 13.0 # The pedestrian gap north of the vehicle gate is present in all five campus meshes.
const EXIT_HALF_WIDTH := 4.0
const EXIT_HINT := "沿闸机旁的白线向外走，看看门外通往哪里。"
const PROMISE := "纸角还有一行字。「要是先出去了，跟我妹说一声，我没忘。她在北门等我。」"
const PUNCH_EDGES := {"ink": "左边", "present": "上边", "proxy": "右边"}

var armed := ""
var answered := ""
var checked := false
var proxy_place := ""
var proof := "" # ink, present, proxy. A teammate's notebook entry cannot issue a receipt.
var present_slot := ""
var clearance := 0 # 1 accepted at the reader, 2 used for the trial.
var trial_punch := "" # The proof used at the west gate, kept even after a later borrowed roll call.
var heard_promise := false
var stair_promise := false
var reading_until := 0.0
var _previous := Vector2.INF


func capture() -> Dictionary:
	return {"armed": armed, "answered": answered, "checked": checked, "proxy_place": proxy_place,
		"proof": proof, "present_slot": present_slot, "clearance": clearance, "trial_punch": trial_punch, "heard_promise": heard_promise,
		"reading_until": reading_until, "stair_promise": stair_promise}


func restore(data: Dictionary) -> void:
	armed = data.get("armed", "")
	answered = data.get("answered", "")
	checked = data.get("checked", false)
	proxy_place = data.get("proxy_place", "")
	proof = data.get("proof", "proxy" if checked else "")
	present_slot = data.get("present_slot", "")
	clearance = int(data.get("clearance", 0))
	trial_punch = data.get("trial_punch", proof if clearance == 2 else "")
	heard_promise = data.get("heard_promise", false)
	stair_promise = data.get("stair_promise", false)
	reading_until = float(data.get("reading_until", 0.0))
	_previous = Vector2.INF


static func valid_slot(id: Variant) -> bool:
	if not id is String: return false
	var parts: PackedStringArray = id.split(":")
	if parts.size() != 2 or parts[1] not in ["0", "1"]: return false
	var day := parts[0].to_int()
	return day > 0 and day <= 100000 and str(day) == parts[0]


static func valid(data: Variant) -> bool:
	if not data is Dictionary: return false
	for field: String in ["armed", "answered"]:
		var id: Variant = data.get(field, "")
		if not id is String or (not id.is_empty() and not valid_slot(id)): return false
	var seen: Variant = data.get("checked", false)
	if not seen is bool: return false
	var last: String = data.get("answered", "")
	var next: String = data.get("armed", "")
	var basis: Variant = data.get("proof", "proxy" if seen else "")
	if basis not in ["", "ink", "present", "proxy"] or (basis == "proxy") != seen: return false
	var place: Variant = data.get("proxy_place", "")
	if not place is String or place.length() > 80 or (last.is_empty() and not place.is_empty()): return false
	var slot: Variant = data.get("present_slot", "")
	if not slot is String or (not slot.is_empty() and not valid_slot(slot)) or (basis == "present" and slot.is_empty()): return false
	var step: Variant = data.get("clearance", 0)
	if not SaveSchema.is_integer(step, 0, 2) or (basis == "" and step != 0): return false
	var punch: Variant = data.get("trial_punch", basis if step == 2 else "")
	if punch not in ["", "ink", "present", "proxy"] or (step == 2 and punch != basis) or (step == 1 and punch != ""): return false
	if not data.get("heard_promise", false) is bool: return false
	if not data.get("stair_promise", false) is bool: return false
	if not SaveSchema.number_in(data.get("reading_until", 0), 0, 1e12): return false
	if not last.is_empty() and not seen and basis != "": return false
	if last.is_empty(): return not seen
	return next.is_empty() or (seen and next.get_slice(":", 0).to_int() > last.get_slice(":", 0).to_int())


static func stamp(id: String) -> String:
	return "第%s天%s" % [id.get_slice(":", 0), "午间" if id.ends_with(":0") else "傍晚"]


func outstanding() -> bool:
	return not answered.is_empty() and not checked


func entry() -> String:
	if not armed.is_empty(): return "%s点名，我把名牌竖在了桌上。铃响时亲自坐好，就由我自己应声。" % stamp(armed)
	if answered.is_empty(): return ""
	var when := stamp(answered)
	if checked: return "%s，我没在自己的座位上答到。保安岗那张签着我名字的底联，我已经收好了。" % when
	return "%s，空座替我答了到。同化停止自然回落。去保安岗柜台核对那张有我签名的底联。" % when


func offer(next: Dictionary, today: int, promised: bool) -> Dictionary:
	var id: String = next["id"]
	if armed == id:
		return {"target": id, "leave": false, "text": entry(), "labels": ["放平名牌，自己应到", "保持竖立"]}
	var why := ""
	if outstanding(): why = entry()
	elif next["day"] != today: why = "今天的两次点名已经结束。"
	elif answered.get_slice(":", 0).to_int() >= today: why = "桌上的复写纸已经透了。一天只能替我答一次。"
	elif promised: why = "登记外出时我答应亲自到场。这一次得自己回来。"
	if not why.is_empty(): return {"text": why, "labels": ["收好纸条"]}
	return {"target": id, "leave": true,
		"text": "纸背上是同桌的字。「点到你，我替你应一声。」\n把名牌留在桌上。%s点名时你若在外，空座会应声，你可以继续行动。同化增加 18，直到去保安岗核对底联才会自然回落。" % stamp(id),
		"labels": ["竖起名牌，让空座应到", "保持平放，自己应到"]}


func check_counterfoil(active_seconds: float = 0.0) -> bool:
	var owed := outstanding()
	if owed: checked = true
	if proof.is_empty():
		recall_counterfoil()
		reading_until = active_seconds + 8.0
	return owed


## Also used when an older solo notebook proves this student visited the counter.
func recall_counterfoil() -> void:
	if proof.is_empty() and not outstanding():
		proof = "proxy" if checked else ("present" if not present_slot.is_empty() else "ink")


func reading(world_id: String, active_seconds: float) -> bool:
	return world_id == "guard1" and not proof.is_empty() and active_seconds < reading_until


func borrowed_at(id: String, place: String) -> void:
	answered = id
	checked = false
	proxy_place = place
	proof = ""
	clearance = 0
	_previous = Vector2.INF


func attended(id: String) -> void:
	if clearance > 0: return
	present_slot = id
	if proof == "ink": proof = "present"


func evidence() -> String:
	match proof:
		"proxy":
			if proxy_place.is_empty(): return "%s，空座替我答了到。底联上是我的签名，离校栏空着。" % stamp(answered)
			return "%s点名时我在%s。教室里的空座替我应了声。底联上是我的签名。" % [stamp(answered), proxy_place]
		"present": return "%s，我亲自在座位上答到。保安岗底联上早就有我的签名，离校栏却空着。" % stamp(present_slot)
		"ink": return "保安岗底联上是我的签名，离校栏空着。右下角盖着「西小门核验」。"
	return ""


func gate_goal() -> String:
	if trial_done() or proof.is_empty(): return ""
	if clearance == 1: return EXIT_HINT
	return "从手册打开校园图，去西小门递交底联。核验前可以重读调查笔记。"


func trial_done() -> bool:
	return not trial_punch.is_empty()


func trial_stage() -> int:
	return 2 if trial_done() else clearance


func journal() -> String:
	var lines := PackedStringArray()
	var trace := entry()
	if not trace.is_empty() and (proof.is_empty() or not armed.is_empty()): lines.append(trace)
	if not proof.is_empty(): lines.append(evidence())
	if clearance == 1: lines.append("西小门退回的底联，%s有个半圆缺口。" % PUNCH_EDGES[proof])
	if trial_done(): lines.append("试走时打在底联%s的半圆缺口还在。白线外又接回了校园。" % PUNCH_EDGES[trial_punch])
	if heard_promise: lines.append(PROMISE)
	if stair_promise: lines.append("我在西楼梯二楼答应同桌，先醒的话，就去北门替他捎句话。")
	return "\n".join(lines)


func gate_question(electronic: bool) -> Dictionary:
	if proof.is_empty() or clearance != 0 or trial_done(): return {}
	var wording := ""
	var labels: Array = []
	match proof:
		"proxy":
			if proxy_place.is_empty():
				wording = "%s，教室里是谁替你应了声？" % stamp(answered)
				labels = ["我亲自答的", "我的空座", "那天没有点名"]
			else:
				wording = "%s，点名册勾了你的名字。铃响时，你本人在哪儿？" % stamp(answered)
				labels = ["已经出了校门", "我在" + proxy_place, "我坐在自己的座位上"]
		"present":
			wording = "%s，你在哪里答的到？" % stamp(present_slot)
			labels = ["我坐在自己的座位上", "别人替我答了到", "我已经离校"]
		"ink":
			wording = "登记簿说你已经走了。你自己看过的底联上，离校栏填着什么？"
			labels = ["已经放行", "今天的日期", "那一栏是空的"]
	if electronic: labels.append("改用电子白名单")
	return {"text": "西小门 · 底联核验\n" + wording, "labels": labels, "reference": proof_reference()}


func proof_reference() -> String:
	match proof:
		"proxy": return "proxy/%s/%s" % [answered, proxy_place]
		"present": return "present/" + present_slot
	return proof


## Both callers rediscover the current gate and pass the authority's own paper.
func answer_gate(token: String, index: int, at: Vector2) -> String:
	if index < 0 or index >= 3: return ""
	if trial_done(): return "纸面核验已经完成。电子名单有自己的登记手续。"
	if proof.is_empty() or clearance != 0 or token != proof_reference(): return "这张回执和刚才不一样了。把现在的底联再递进去。"
	if index != {"present": 0, "proxy": 1, "ink": 2}[proof]:
		return "回执被退回来，红章上写着「请核原件」。我翻开随身的底联：" + evidence()
	clearance = 1
	_previous = at
	return "闸机只响了一声。「本人，到。」退回的底联%s被咬掉一个半圆。" % PUNCH_EDGES[proof] + EXIT_HINT


func crossed_line(outdoors: bool, at: Vector2, gate: Vector2) -> bool:
	if clearance != 1 or trial_done(): return false
	var last := _previous
	_previous = at if outdoors else Vector2.INF
	if not outdoors or not last.is_finite() or last.distance_squared_to(at) > 24.0 * 24.0: return false
	var line := gate.x + EXIT_OFFSET
	if last.x <= line or at.x > line: return false
	var y := lerpf(last.y, at.y, (last.x - line) / (last.x - at.x))
	if absf(y - (gate.y - EXIT_NORTH)) > EXIT_HALF_WIDTH: return false
	clearance = 2
	trial_punch = proof
	return true
