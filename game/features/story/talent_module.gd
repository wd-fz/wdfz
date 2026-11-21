class_name TalentModule
extends FeatureModule
## Talents, based on the Web version (reference wd-fz.github.io@0bf508a, talents.js).
## One talent per run, picked on the new-game screen (or at random). The other modules only ask
## "may I / how / by how much" through this module; the app passes the answers in their contexts.

const STATE_VERSION := 1
const RULES := 5
const DEF := {
	"tech": {"n": "科技党", "role": "随身带着一部旧手机。", "does": "开局拥有满电手机。", "limit": "所有手机耗电永久翻倍；接入网络与服务器谜题仍需完成。"},
	"code": {"n": "编程社", "role": "在电脑社团泡过三年。", "does": "不带 U 盘也能直接操作网络中心的门禁终端。西小门第一次答错时会对照后台核一遍，那一次不会受惊（仍然换题）。",
		"limit": "不开机房的门锁，仍须通过实体终端或联网手机完成数据同步；闸机三道题还是要自己答对。"},
	"drive": {"n": "车感好", "role": "家里人教过开车，也偷偷学过搭线。", "does": "在车库高亮标出正确的车。没有钥匙时可以搭线启动（4.8 秒）。有钥匙时优先用钥匙（1.6 秒）。",
		"limit": "车库的黑影照样会靠近，启动后还要自己把车开出去。"},
	"night": {"n": "暗处适应", "role": "从小怕黑，后来习惯了。", "does": "入夜自动开启夜视，能看清阴影里的细节。在车库和熄灯后的室外也更能坚持。", "limit": "夜视的亮度只有自己看得到。想逼退黑影还得用手电。"},
	"immune": {"n": "天生免疫", "role": "运气一直好得过分。", "does": "每局一次：要命的事被绕开，能缓过气来，暂时摆脱过分的注意。", "limit": "只有一次，用掉不会再回来；身上有不知名药丸时先用药丸。"},
	"ear": {"n": "顺风耳", "role": "隔着墙，也能辨出从哪边传来的脚步。", "does": "隔墙看见 15 米内巡察者的轮廓，雷达会标出相对方位和距离。",
		"limit": "雷达只追踪巡察者。超出 15 米，透视和标记同时消失。"},
}
const KEYS := ["tech", "code", "drive", "night", "immune", "ear"]
const HOTWIRE_SEC := 4.8
const DARK_MUL := 0.55
const PATROL_SENSE_METRES := 15.0

var id := "none"
var consumed: Dictionary = {}


func module_id() -> StringName:
	return &"story.talent"


func state_version() -> int:
	return STATE_VERSION


func reset() -> void:
	id = "none"
	consumed = {}


func capture() -> Dictionary:
	return {"id": id, "rules": RULES, "consumed": consumed.duplicate()}


func validate(data: Dictionary) -> String:
	var t: Variant = data.get("id")
	if not t is String or (t != "none" and not DEF.has(t) and t != "watch"):
		return "天赋无效"
	if not data.get("consumed", {}) is Dictionary:
		return "天赋使用状态无效"
	return ""


func restore(data: Dictionary) -> void:
	reset()
	pick(data["id"])
	consumed = (data.get("consumed", {}) as Dictionary).duplicate()


func pick(talent: String) -> void:
	id = talent if DEF.has(talent) else "none"


func has(talent: String) -> bool:
	return id == talent


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
