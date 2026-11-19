class_name RollcallCard
extends RefCounted
## One physical name card per student. Attendance and personal attendance duties
## are still settled by SchoolModule. A counterfoil belongs to this student.
const COST := 18.0
const LOOK_DOWN := -0.48
const INVITATION := "同桌推来一张纸条：「北门旁的保安岗有张单子，签的是你的名字。你去看，我替你答到。」低头看名牌，或起身去保安岗。"

var armed := ""
var answered := ""
var checked := false


func capture() -> Dictionary:
	return {"armed": armed, "answered": answered, "checked": checked}


func restore(data: Dictionary) -> void:
	armed = data.get("armed", "")
	answered = data.get("answered", "")
	checked = data.get("checked", false)


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
	if checked: return "保安岗底联和点名册上都有我的名字。%s，我只在其中一个地方。底联我收好了。" % when
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
		"text": "同桌压低声音：「你先走，我替你答。」\n把名牌留在桌上。%s点名时你若在外，空座会应声，你可以继续行动。同化增加 18，直到去保安岗核对底联才会自然回落。" % stamp(id),
		"labels": ["竖起名牌，让空座应到", "保持平放，自己应到"]}


func check_counterfoil() -> bool:
	if not outstanding(): return false
	checked = true
	return true
