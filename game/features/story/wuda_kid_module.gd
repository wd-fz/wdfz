class_name WudaKidModule
extends FeatureModule
## Hidden additive starting gift; never replaces the chosen talent or enters its random pool.
const CHANCE := .03
const TELL_AFTER := 6.0
const LINE := "我：书包侧袋里有一支手电。……小时候在珞珈山上跑，天一黑就得带着它。"
var on := false
var told := false
var t := 0.0
var via := ""


func module_id() -> StringName:
	return &"story.wuda_kid"


func reset() -> void:
	on=false
	told=false
	t=0
	via=""


func capture() -> Dictionary:
	return {"on":on,"told":told,"t":t,"via":via}


func validate(data: Dictionary) -> String:
	if not data.get("on") is bool or not data.get("told") is bool or not SaveSchema.number_in(data.get("t"),0,1e12) or not data.get("via") in ["","menu","chance"]:
		return "开局侧袋状态无效"
	return ""


func restore(data: Dictionary) -> void:
	on=data["on"]
	told=data["told"]
	t=data["t"]
	via=data["via"]


func start(armed: bool, roll: float, speedrun: bool) -> bool:
	if speedrun: return false
	via="menu" if armed else ("chance" if roll<CHANCE else "")
	on=via!=""
	told=false
	t=0
	return on


func tick(dt: float) -> String:
	if not on or told or dt<=0: return ""
	t+=dt
	if t<TELL_AFTER: return ""
	told=true
	return LINE


static func tap(taps: Array, now_ms: float) -> bool:
	for i in range(taps.size()-1,-1,-1):
		if now_ms-float(taps[i])>=1600: taps.remove_at(i)
	taps.append(now_ms)
	if taps.size()<3: return false
	taps.clear()
	return true
