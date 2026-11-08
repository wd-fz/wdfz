class_name TalentModule
extends FeatureModule
## Talents, ported from the Web version (reference wd-fz.github.io@0bf508a, talents.js TALENT_DEF /
## Talent.capability / modifier / tryPreventDeath / faceRemedy / tickWatch, rules version 4).
## One talent per run, picked on the new-game screen (or at random). The other modules only ask
## "may I / how / by how much" through this module; the app passes the answers in their contexts.

const STATE_VERSION := 1
const RULES := 4
const DEF := {
	"tech": {"n": "科技党", "role": "随身带着一部旧手机。", "does": "开局拥有满电手机。", "limit": "所有手机耗电永久翻倍；接入网络与服务器谜题仍需完成。"},
	"code": {"n": "编程社", "role": "在电脑社团泡过三年。", "does": "不带 U 盘也能直接操作网络中心的门禁终端。西小门第一次答错时会对照后台核一遍，那一次不会受惊（仍然换题）。",
		"limit": "不开机房的门锁，仍须通过实体终端或联网手机完成数据同步；闸机三道题还是要自己答对。"},
	"drive": {"n": "车感好", "role": "家里人教过开车，也偷偷学过搭线。", "does": "没有车钥匙也能在车库试着搭线启动。搭线要蹲在车门边 4.8 秒（用钥匙 1.6 秒）；有钥匙时优先用钥匙。",
		"limit": "车库的黑影照样会靠近，错车照样打不着，之后还要自己把车开出去。"},
	"night": {"n": "暗处适应", "role": "从小怕黑，后来习惯了。", "does": "在车库和熄灯后的室外，更能坚持。", "limit": "不会让暗处变亮——看不清的还是看不清，手电还是要带；黑影贴近、异象伤害照常。"},
	"watch": {"n": "守时", "role": "手腕上一直戴着一块旧表。", "does": "不用找手表也能看到分钟时钟。开饭、饭点结束和熄灯前会看一眼表，提醒一次。", "limit": "只显示到分钟；不预告异象，也不替你请假。"},
	"immune": {"n": "天生免疫", "role": "运气一直好得过分。", "does": "每局一次：要命的事被绕开，能缓过气来，暂时摆脱过分的注意。", "limit": "只有一次，用掉不会再回来；身上有不知名药丸时先用药丸。"},
	"ear": {"n": "顺风耳", "role": "宿舍里谁翻个身，你都会醒。", "does": "巡察者的脚步、门轴和远处的异响，在更远处就能听到（可闻距离 ×1.5）。",
		"limit": "假威胁也听得一清二楚。不分真假，不预告异象，不改变巡察者和异象的规则。"},
}
const KEYS := ["tech", "code", "drive", "night", "watch", "immune", "ear"]
const HOTWIRE_SEC := 4.8
const DARK_MUL := 0.55
const EAR_RANGE := 1.5
const WATCH_LEAD := 20.0
const WATCH_MARKS := [[735.0, "午饭开饭了"], [800.0, "午饭时间快过了"], [1060.0, "晚饭开饭了"], [1090.0, "晚饭时间快过了"], [1340.0, "快熄灯了"]]

var id := "none"
var consumed: Dictionary = {}
var notified: Dictionary = {}
var events: Array = []


func module_id() -> StringName:
	return &"story.talent"


func state_version() -> int:
	return STATE_VERSION


func reset() -> void:
	id = "none"
	consumed = {}
	notified = {}
	events = []


func capture() -> Dictionary:
	return {"id": id, "rules": RULES, "consumed": consumed.duplicate(), "notified": notified.duplicate()}


func validate(data: Dictionary) -> String:
	var t := String(data.get("id", ""))
	if t != "none" and not DEF.has(t):
		return "天赋无效"
	return ""


func restore(data: Dictionary) -> void:
	reset()
	id = String(data["id"])
	consumed = (data.get("consumed", {}) as Dictionary).duplicate()
	notified = (data.get("notified", {}) as Dictionary).duplicate()


func pick(talent: String) -> void:
	id = talent if DEF.has(talent) else "none"


func has(talent: String) -> bool:
	return id == talent


func take_events() -> Array:
	var out := events
	events = []
	return out


func name_of(talent: String = "") -> String:
	var t := talent if talent != "" else id
	return String(DEF[t]["n"]) if DEF.has(t) else "没有天赋"


## Talent.capability('car'): the key, or hot-wiring with the driving talent.
func car(has_key: bool) -> Dictionary:
	if has_key:
		return {"ok": true, "via": "key", "sec": GarageModule.KEY_SEC}
	if has("drive"):
		return {"ok": true, "via": "hotwire", "sec": HOTWIRE_SEC}
	return {"ok": false, "via": "", "sec": GarageModule.KEY_SEC}


## Talent.modifier('danger.garage' / 'danger.night').
func danger_mul(kind: String) -> float:
	return DARK_MUL if has("night") and (kind == "garage" or kind == "night") else 1.0


func hear_range() -> float:
	return EAR_RANGE if has("ear") else 1.0


## Talent.tryPreventDeath: once per run.
func prevent_death() -> bool:
	if not has("immune") or bool(consumed.get("fatalProtection", false)):
		return false
	consumed["fatalProtection"] = true
	return true


## Talent.faceRemedy: the first wrong gate answer costs no SAN.
func face_remedy() -> bool:
	if not has("code") or bool(consumed.get("faceRemedy", false)):
		return false
	consumed["faceRemedy"] = true
	return true


## Talent.tickWatch: a glance at the watch shortly before the meals and lights out.
## rate: game seconds per real second at this time.
func tick_watch(day: int, tsec: float, rate: float) -> void:
	if not has("watch"):
		return
	var lead := rate / 60.0 * WATCH_LEAD
	for m: Array in WATCH_MARKS:
		var key := "%d:%d" % [day, int(m[0])]
		var ahead := float(m[0]) - tsec
		if notified.has(key):
			continue
		if ahead > 0.0 and ahead <= lead:
			notified[key] = true
			for k: String in notified.keys():
				if int(k.split(":")[0]) < day - 1:
					notified.erase(k)
			events.append({"kind": "notice", "text": "我：（看了一眼表）%s。" % m[1]})
			return
		if ahead <= 0.0 and ahead > -lead:
			notified[key] = true


## The pause line (Talent.pauseText).
func pause_text() -> String:
	if not DEF.has(id):
		return "天赋 · 没有天赋"
	var status := ""
	if id == "immune":
		status = "（已经用掉了）" if bool(consumed.get("fatalProtection", false)) else "（还能用 1 次）"
	elif id == "code":
		status = "（答错补救已用）" if bool(consumed.get("faceRemedy", false)) else "（答错补救还在）"
	return "天赋 · %s%s　%s %s" % [DEF[id]["n"], status, DEF[id]["does"], DEF[id]["limit"]]
