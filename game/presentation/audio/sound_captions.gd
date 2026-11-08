class_name SoundCaptions
extends RefCounted
## Sound captions, ported from the Web version (reference wd-fz.github.io@0bf508a,
## modules/sensory/sound-captions.js and the queue of domain/sensory.js): every perceptible sound
## publishes one caption before it plays, whatever the volume, so a player without sound still
## gets the warning (CLAUDE.md horror rules 1 and 3). Direction words come from the place: left /
## right past 0.25 pan, behind / ahead, near under 5 m, through a wall when muffled. Heart and
## breath at most once in 20 s. At most eight queued, two shown, highest priority first.

const WORDS := {
	"dread.hum": "灯管的嗡声没有停", "threat.breath": "呼吸声近了些", "dread.knock": "轻轻的敲门声", "dread.door": "门轴拖着长音", "dread.steps": "缓慢的脚步声", "dread.run": "一阵急促脚步",
	"dread.chair": "椅脚刮过地面", "dread.desk": "桌椅轻响", "dread.whisper": "模糊的低语", "dread.radio": "喇叭里一阵杂音", "dread.call": "远处有人声",
	"event.dismissal": "放学长铃持续响着 · 跟随同学从北门离校", "death.misread": "所有喇叭都在叫你留在原地",
	"event.bellStart": "急促的上课铃", "event.bellEnd": "下课铃", "event.thunder": "雷声炸响", "event.thunderFar": "远处的闷雷",
	"foley.door": "门轴响了一声", "foley.cupFall": "风里有尖细的哨音", "foley.colaRattle": "上方有东西磕了一下",
	"threat.precursor": "耳边一阵低鸣", "threat.smileBack": "身后传来压低的笑声", "threat.smileJump": "耳边一声尖响",
	"threat.heartLow": "近处的心跳", "threat.heartPat": "急促的心跳", "world.crackle": "灯管噼啪作响",
	"distant.slam": "远处一声门响", "world.silence": "周围突然安静了", "distant.tinnitus": "耳边一阵闷响", "distant.aah": "远处有声音", "distant.ball": "远处一声落地响", "distant.giggle": "远处有声音"}

## 0 auto (only when the volume is at 5 % or less), 1 on (the old default), 2 off.
var mode := 1
var sub_mult := 1.0
var clock := 0.0
var _list: Array = []
var _seq := 0
var _body_at := -100.0


func reset() -> void:
	_list = []
	clock = 0.0
	_body_at = -100.0


func tick(dt: float) -> void:
	clock += minf(dt, 0.25)


func enabled(volume: float, muted: bool) -> bool:
	return mode == 1 or (mode == 0 and (volume <= 0.05 or muted))


## opts: caption (overrides the word), patrol (patroller steps), self_step, at, place {pan,
## behind, m, muffled}; busy: phone / lesson / terminal open (only priority 3 gets through).
func publish(id: String, opts: Dictionary, busy: bool = false) -> Dictionary:
	if bool(opts.get("self_step", false)):
		return {}
	var text := String(opts.get("caption", WORDS.get(id, "")))
	var body := id.begins_with("threat.heart") or id.begins_with("threat.breath")
	if bool(opts.get("patrol", false)):
		text = "脚步声"
	if text == "":
		return {}
	if body and clock - _body_at < 20.0:
		return {}
	if body:
		_body_at = clock
	var dir: PackedStringArray = []
	var p: Dictionary = opts.get("place", {})
	if not p.is_empty():
		if absf(float(p.get("pan", 0.0))) > 0.25:
			dir.append("左" if float(p["pan"]) < 0.0 else "右")
		if p.has("behind"):
			dir.append("后方" if bool(p["behind"]) else "前方")
		if p.has("m"):
			dir.append("近处" if float(p["m"]) < 5.0 else "远处")
		if bool(p.get("muffled", false)):
			dir.append("隔着墙")
	var priority := 3 if bool(opts.get("patrol", false)) or id.begins_with("event.") or id in ["foley.cupFall", "foley.colaRattle"] or id.begins_with("threat.smile") else (1 if body else 0)
	if busy and priority < 3:
		return {}
	var at := clock + maxf(0.0, float(opts.get("at", 0.0)))
	var e := {"source": String(opts.get("source", id)), "text": (" · ".join(dir) + " · " if dir.size() > 0 else "") + text,
		"at": at, "end": at + maxf(1.8, minf(5.0, 2.5 * sub_mult)), "priority": priority}
	return _push(e)


func _push(e: Dictionary) -> Dictionary:
	_list = _list.filter(func(x: Dictionary) -> bool: return float(x["end"]) > clock)
	for old: Dictionary in _list:
		if old["source"] == e["source"] and absf(float(old["at"]) - float(e["at"])) < 3.0:
			old["end"] = maxf(float(old["end"]), float(e["end"]))
			old["at"] = e["at"]
			old["text"] = e["text"]
			return old
	_seq += 1
	e["id"] = _seq
	_list.append(e)
	_list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["priority"]) > int(b["priority"]) or (int(a["priority"]) == int(b["priority"]) and float(a["at"]) < float(b["at"])))
	_list = _list.slice(0, 8)
	return e


func visible() -> Array:
	_list = _list.filter(func(x: Dictionary) -> bool: return float(x["end"]) > clock)
	return _list.filter(func(x: Dictionary) -> bool: return float(x["at"]) <= clock).slice(0, 2)


func lines() -> PackedStringArray:
	var out: PackedStringArray = []
	for e: Dictionary in visible():
		out.append("〔%s〕" % e["text"])
	return out
