class_name StoryModule
extends FeatureModule
## Death and difficulty, ported from the Web version (reference wd-fz.github.io@0bf508a): story.js
## (kill, DFX_EPI, DEATH_SOURCES, DEATH_HINTS, deathHints, elixirSave, survivalReset, dreamWake)
## and fx/death-timeline.js durations. The death CG scenes (fx/death-cg.js) are not ported: the
## presentation holds a red fade for the same duration. Talents (immunity) are not ported.
## Endings (triggerEnding / ENDINGS) arrive with their routes.

const STATE_VERSION := 1
const MAX_WAKES := 3
const DIFFICULTIES := ["easy", "hard"]
const DURATIONS := {"vignette": 2.0, "floor": 3.0, "grip": 3.2, "neck": 3.4, "shadow": 3.2, "swarm": 3.2, "drown": 3.4,
	"water": 3.4, "freeze": 3.4, "gaze": 3.4, "stare": 3.2, "voice": 3.2, "bell": 3.4, "follow": 3.4, "shatter": 3.2,
	"deep": 3.4, "ring": 3.4, "names": 2.0, "chalk": 2.0, "loop": 3.4, "twin": 3.2, "lamps": 3.4, "slit": 3.6,
	"squeeze": 3.6, "face": 3.0, "wall": 2.0, "laugh": 3.2, "mirror": 2.0, "hand": 2.0, "trash": 3.6, "liftdoor": 4.4, "void": 3.6, "abyss": 3.6}
const EPITAPH := {"misread": "你念的那份通知，是给你的。", "laugh": "你自己也觉得好笑。", "gaze": "你终于看清了。",
	"swarm": "它们很轻。", "water": "你没有挣扎。", "shadow": "它等了你一整天。", "hand": "那只手是温的。",
	"face": "它一直在等你先动。", "ring": "圈合上了。正中那个位置，从此有人了。", "shatter": "你碎成了很多个自己。每一个都在找回去的路。",
	"grip": "好几只手。都很有耐心。", "deep": "下面比你想的宽敞。", "slit": "缝在你身后合上了。", "follow": "你跟上得很好。",
	"drown": "你听见有人在岸上喊你的名字。", "voice": "你应了一声。", "bell": "第十三下。", "names": "他们等这个名字等了很久。",
	"squeeze": "你比墙软。", "freeze": "你最后想的是：衣服确实挂得很整齐。", "stare": "他们看得太整齐了。",
	"chalk": "这一次写的是你的名字。", "loop": "走廊没有尽头 —— 因为你一直在同一段里。", "twin": "他转过来的时候，你正在转过去。",
	"lamps": "灯停在你站的那一格上。", "neck": "他根本没打算绕路。", "mirror": "镜子里那个，先动的手。",
	"floor": "下面很宽敞。还有很多张课桌。", "wall": "你比墙软。", "vignette": "有人替你应了一声\"到\"。",
	"trash": "外面又敲了两下。这次更近了。", "liftdoor": "门缝很窄。它的手指更窄。", "void": "你从那扇门前走过了很多次。", "abyss": "下面站着的，是刚进来的你。"}
const SOURCES := {
	"void_lost": {"cause": "在白色的迷宫里待得太久，理智被一点点耗尽了：待得越久，掉得越快。", "hint": "迷宫里不能久留。出口是门缝漏着淡蓝色光的暗门，都不在出发的那一层，要走楼梯上下；用粉笔在拐角做记号，免得兜回原地。"},
	"void_fall": {"cause": "理智所剩无几的时候又掉进了虚空。每掉下去一次，都会再扣一点理智。", "hint": "理智低的时候别走没有栏杆的窄梁和断口，宁可绕远路；走窄的地方先停下转好方向，再一步步往前走。"},
	"san": {"cause": "你的理智已经耗尽；此前的危险与消耗累积到了极限。", "hint": "留意呼吸和画面变化。恢复前先离开危险区域，再选择吃饭、药片或其他恢复活动。"},
	"assimilation": {"cause": "同化到达了极限。长期按要求坐着也有代价。", "hint": "一直留在座位上会逐渐同化。安排离座探索，别只依赖上课恢复。"},
	"patrol": {"cause": "巡察者追到了你；灯光与脚步是它进入区域的信号。", "hint": "灯按拍子闪时先找遮蔽。被锁定后尽快脱离它的视线；当着它的面钻进柜子会被记住。"},
	"garage": {"cause": "你与车道上的黑影接触了。", "hint": "车库的黑影能被手电持续照射暂时逼退，也会被落地的硬币引开。先观察距离再穿过车道。"},
	"trash": {"cause": "那个垃圾桶是陷阱，合上的桶盖没有通向外面。", "hint": "垃圾桶不能带你逃离学校；找其他有证据支持的办法。"},
	"paper_sender": {"cause": "窗后飞来的纸飞机没有按时、按原路送回去。飞纸飞机的人自己来取了。", "hint": "两下拍窗的纸要尽快读完、折好，对准原来那扇窗投回去，飞的时候别碰墙。"},
	"window_gaze": {"cause": "窗里那双眼睛一直盯着我，我一直没有移开视线，精神被它耗尽了。", "hint": "窗后有呼吸声时，别直视那扇窗：低头、偏开，或者退到墙后面。"},
	"mirror": {"cause": "镜子里的轮廓先抬起了手，你还一直看着它。", "hint": "镜子里的它先动了，就别再看；先把精神缓回来。"},
	"campus_fall": {"cause": "从楼上翻过栏杆，掉了下去。", "hint": "「外侧悬空」的栏杆翻过去就是往下掉；天台的栏杆外面什么都没有。"},
	"misread": {"cause": "红笔、第 0 天的通知稿要求读到这里的人留在原地。你把它念进了广播。", "hint": "播音记录本记着原稿的墨水和日期。开口前先核对稿纸。"},
	"car_entry": {"cause": "试车门时，车库黑影仍守在车辆附近。", "hint": "拉车门需要原地停留。先照退或引开车道上的黑影，确认车旁安全再拧钥匙。"},
	"car_chase": {"cause": "驾驶中的路障、岔路或追兵使这次逃离中断。", "hint": "路口前看路牌并提前转向。可以向后拉摇杆或按 S 刹车；长时间停下会让追兵靠近。"},
	"liftdoor": {"cause": "它看着你进了电梯，门没在它碰到之前合上。", "hint": "被它看着进电梯时，进门就按关门。"},
}
const FX_HINTS := {"names": "坐久了，椅子会留人。该站起来的时候，就站起来。",
	"vignette": "撑不住的时候，吃药、吃饭、玩一会儿手机，都能缓过来一点。"}

var diff := "easy"
var wakes := 0
var dead := false
var death_fx := ""
var death_msg := ""
var death_source := ""
var death_t := 0.0
var wake_pending := false
## Set when an ending is reached: the run is over and the simulation stops (S.screen = 'end').
var ended := ""


func module_id() -> StringName:
	return &"story.death"


func state_version() -> int:
	return STATE_VERSION


func reset() -> void:
	wakes = 0
	dead = false
	death_fx = ""
	death_msg = ""
	death_source = ""
	death_t = 0.0
	wake_pending = false
	ended = ""


## story.js triggerEnding: returns the ending card, or {} when already dead or over.
func trigger_ending(id: String) -> Dictionary:
	if dead or ended != "":
		return {}
	var c := RoutesModule.card(id)
	if c.is_empty():
		return {}
	ended = id
	return c


func over() -> bool:
	return dead or ended != ""


func capture() -> Dictionary:
	return {"diff": diff, "wakes": wakes}


func validate(data: Dictionary) -> String:
	if not String(data.get("diff", "")) in DIFFICULTIES:
		return "难度无效"
	if not SaveSchema.is_integer(data.get("wakes"), 0, MAX_WAKES):
		return "预知梦次数无效"
	return ""


func restore(data: Dictionary) -> void:
	diff = String(data["diff"])
	wakes = int(data["wakes"])
	dead = false


static func duration(fx: String) -> float:
	return float(DURATIONS.get(fx, DURATIONS["vignette"]))


## story.js kill. ctx: day, has_elixir. Returns what the presentation must do.
func kill(msg: String, fx: String, source: String, ctx: Dictionary) -> Dictionary:
	if dead:
		return {}
	if bool(ctx.get("has_elixir", false)):
		return {"protected": "elixir", "notice": "我：……那粒药丸自己在舌根底下化开了。苦得发麻。我还站着——刚才那一下，像是有人替我挨了。",
			"toast": "不知名药丸 · 救了你一次"}
	if bool(ctx.get("immune", false)):
		return {"protected": "immune", "notice": "我：刚才那一下本该要了我的命。可它擦身而过，像是没有认出我。", "toast": "天生免疫 · 挡下了一次致命事件"}
	dead = true
	death_fx = fx if not fx.is_empty() else "vignette"
	death_msg = msg
	death_source = source
	death_t = 0.0
	wake_pending = diff == "easy" and int(ctx.get("day", 1)) == 1 and wakes < MAX_WAKES
	return {"dead": true, "hold": duration(death_fx), "wake": wake_pending, "notice": msg}


func epitaph() -> String:
	return String(EPITAPH.get(death_fx, ""))


func cause() -> String:
	return String(SOURCES.get(death_source, {}).get("cause", ""))


## Count this death in a cross-run log (deathLogAdd); the adapter stores the dictionary.
func log_death(record: Dictionary, day: int, where: String) -> Dictionary:
	var d := record.duplicate(true)
	var counts: Dictionary = d.get("counts", {})
	counts[death_fx] = int(counts.get(death_fx, 0)) + 1
	d["counts"] = counts
	var sources: Dictionary = d.get("sources", {})
	if not death_source.is_empty():
		sources[death_source] = int(sources.get(death_source, 0)) + 1
	d["sources"] = sources
	var last: Array = d.get("last", [])
	last.append({"fx": death_fx, "source": death_source if not death_source.is_empty() else null, "day": day, "where": where})
	d["last"] = last.slice(maxi(0, last.size() - 12))
	return d


## deathHints: deaths repeated at least twice that have a readable clue, latest first, at most three.
static func hints(record: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {}
	var last: Array = record.get("last", [])
	var counts: Dictionary = record.get("counts", {})
	var sources: Dictionary = record.get("sources", {})
	for i in range(last.size() - 1, -1, -1):
		if out.size() >= 3:
			break
		var entry: Dictionary = last[i]
		var source: Variant = entry.get("source")
		var fx := String(entry.get("fx", ""))
		var key := String(source) if source != null else fx
		if seen.has(key):
			continue
		seen[key] = true
		if source != null and SOURCES.has(source):
			if int(sources.get(source, 0)) >= 2:
				out.append(String(SOURCES[source]["hint"]))
		elif fx != "grip" and int(counts.get(fx, 0)) >= 2 and FX_HINTS.has(fx):
			out.append(String(FX_HINTS[fx]))
	return out


## After the death scene: the dream wake (first day on 预知梦, three times at most).
func finish_wake() -> int:
	wakes += 1
	dead = false
	wake_pending = false
	death_fx = ""
	return MAX_WAKES - wakes
