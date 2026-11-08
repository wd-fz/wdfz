class_name MonoModule
extends FeatureModule
## The protagonist's muttering, ported from the Web version (reference wd-fz.github.io@0bf508a, mono.js):
## the same place, different SAN, different thoughts. Four tiers: steady (>= 75), uneasy (50–75),
## frayed (25–50), breaking (< 25). Every 40–75 s it finds a gap to say one line (never during an
## anomaly, a choice, the phone or a dialogue, and half the time not while seated in class), the last eight
## are not repeated. Only mood: no stat. Events out: say {text}.

const STATE_VERSION := 1
const LINES := {
 "calm": {
  "any": [
   "我：今天和昨天没有什么不一样。",
   "我：把作息表记住，就不会出事。",
   "我：口袋里的东西还在。好。",
   "我：先想清楚下一节课在哪。"
  ],
  "class": [
   "我：黑板上的字和昨天一模一样，连写错又涂掉的那一笔都一样。",
   "我：前排的人一直没有翻页。",
   "我：坐在这里，至少没人会来找我。"
  ],
  "hall": [
   "我：走廊很长。我数过窗户，今天还是二十四扇。",
   "我：走廊尽头那扇门，好像比刚才远了一点。"
  ],
  "toilet": [
   "我：水龙头没关紧。滴答，滴答。",
   "我：镜子里的我，比我先眨了一下眼。"
  ],
  "dorm": [
   "我：床铺叠得很整齐。我不记得是我叠的。",
   "我：宿舍里有一股洗衣粉的味道。很正常。"
  ],
  "canteen": [
   "我：食堂的饭还冒着热气。没有人在吃。",
   "我：窗口后面的阿姨一直低着头。"
  ],
  "garage": [
   "我：车库里有一股机油和铁锈的味道。",
   "我：别把手电晃来晃去。"
  ],
  "bell": [
   "我：楼梯一圈一圈往上，扶手是凉的。"
  ],
  "roof": [
   "我：天台上的风很大。整个学校都在脚下。"
  ],
  "outDay": [
   "我：操场上没有人。广播在放一首我没听过的歌。",
   "我：阳光很好。影子很淡。"
  ],
  "outNight": [
   "我：路灯一盏一盏亮着，可是照不到路中间。",
   "我：夜里的校园比白天大。"
  ]
 },
 "uneasy": {
  "any": [
   "我：刚才那一下……是我听错了吧。",
   "我：我总觉得身后有人在走，和我同一个步子。",
   "我：我是不是已经在这里待了很久了？",
   "我：别想。走就是了。"
  ],
  "class": [
   "我：老师讲到一半停下来了，看着我这边。",
   "我：后排一直有人在小声念我的名字。",
   "我：同桌的笔一直在动，可本子上什么都没写。"
  ],
  "hall": [
   "我：灯管在嗡嗡响。刚才是不是闪了一下？",
   "我：走廊里的回声，比我的脚步多了一下。"
  ],
  "toilet": [
   "我：第三个隔间的门，自己晃了一下。",
   "我：镜子上起了雾。雾上有一个手印，在里面那一侧。"
  ],
  "dorm": [
   "我：上铺有人在翻身。我们宿舍上铺是空的。"
  ],
  "canteen": [
   "我：所有人都在同一个时候放下了筷子。"
  ],
  "garage": [
   "我：远处那辆车的车灯，刚刚是不是亮了一下？",
   "我：滴水声停了。"
  ],
  "bell": [
   "我：我数着台阶上去。下来的时候，台阶多了一级。"
  ],
  "roof": [
   "我：天台的门，我出来的时候是关着的吗？"
  ],
  "outDay": [
   "我：太阳一直停在那个位置，没有动过。"
  ],
  "outNight": [
   "我：围墙外面有人在走。我走他也走。",
   "我：路灯下面站着一个人，我一走近，路灯就灭了。"
  ]
 },
 "frayed": {
  "any": [
   "我：我的手一直在抖。",
   "我：今天……今天是几号来着？",
   "我：有人在叫我。是用我的声音。",
   "我：我想回家。我家……在哪儿？"
  ],
  "class": [
   "我：全班都在写。写的都是我的名字。",
   "我：讲台上站着的那个人，脸是空的。",
   "我：我的座位上已经坐着一个人了。他穿着我的校服。"
  ],
  "hall": [
   "我：走廊在变长。我走了好久，教室门牌还是那一间。",
   "我：墙上的画，眼睛跟着我转。"
  ],
  "toilet": [
   "我：隔间底下，有一双鞋，鞋尖朝着我。"
  ],
  "dorm": [
   "我：我的床上躺着一个人，被子盖过了头。"
  ],
  "canteen": [
   "我：碗里的饭，长出了头发。"
  ],
  "garage": [
   "我：它就在那排车后面。我听得见它在等。"
  ],
  "bell": [
   "我：钟在响。可是没有人在敲。"
  ],
  "roof": [
   "我：往下看。往下看一眼就好。……不行。"
  ],
  "outDay": [
   "我：天的颜色不对。像一张洗褪了色的照片。"
  ],
  "outNight": [
   "我：路灯照出来的影子，有两个是我的。"
  ]
 },
 "breaking": {
  "any": [
   "我：我是谁？我是谁？我是谁？",
   "我：不要回头不要回头不要回头。",
   "我：它们都知道我在这儿。",
   "我：……醒过来。快醒过来。",
   "我：我听见自己的心跳，从外面传进来。"
  ],
  "class": [
   "我：所有人都转过来了。所有人都在笑。",
   "我：黑板上写着：值日生——我。日期——每一天。"
  ],
  "hall": [
   "我：走廊尽头站着我。他在朝我招手。"
  ],
  "toilet": [
   "我：镜子里没有我。"
  ],
  "garage": [
   "我：手电照到哪里，哪里就有一张脸。"
  ],
  "outNight": [
   "我：天上没有月亮。只有一只眼睛。"
  ]
 }
}

var t := 30.0
var recent: Array = []
var events: Array = []

var _rooms: Dictionary = {}
var _c: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _init(rooms: Dictionary = {}) -> void:
	_rooms = rooms
	_rng.randomize()


func module_id() -> StringName:
	return &"story.mono"


func state_version() -> int:
	return STATE_VERSION


func reset() -> void:
	t = 30.0
	recent = []
	events = []


func capture() -> Dictionary:
	return {}


func validate(_data: Dictionary) -> String:
	return ""


func restore(_data: Dictionary) -> void:
	reset()


## ctx: scene, x, y (world), tile (the tile under the player), san, night, busy (anomaly, choice, phone,
## dialogue or any panel open), seated_class (seated while the timetable says classroom).
func set_context(ctx: Dictionary) -> void:
	_c = ctx


func take_events() -> Array:
	var out := events
	events = []
	return out


func tier() -> String:
	var s := float(_c.get("san", 100.0))
	return "calm" if s >= 75.0 else ("uneasy" if s >= 50.0 else ("frayed" if s >= 25.0 else "breaking"))


func place() -> String:
	var scene := String(_c.get("scene", ""))
	if scene == "out":
		return "outNight" if bool(_c.get("night", false)) else "outDay"
	var r: Dictionary = _rooms.get(scene, {})
	if r.is_empty():
		return "any"
	if scene == "garage1":
		return "garage"
	if scene == "bell1":
		return "bell"
	if scene == "teach6":
		return "roof"
	var host := String(r.get("host", ""))
	if host == "canteen":
		return "canteen"
	if host == "dormN" or host == "dormS":
		return "dorm"
	var tile := String(_c.get("tile", ""))
	var col := floori((float(_c.get("x", 0.0)) - float(r["ox"])) / float(r["tw"]))
	var row := floori((float(_c.get("y", 0.0)) - float(r["oy"])) / float(r["th"]))
	var teach := host == "teach" and r.get("floor") != null and int(r["floor"]) <= 5
	if tile == "B" or tile == "G" or (teach and col >= 58 and col <= 61 and row >= 16 and row <= 19):
		return "toilet"
	if host == "teach":
		return "hall" if teach and row >= 16 and row <= 20 else "class"
	return "any"


## The line this moment would say (the tests use it too).
func pick() -> String:
	var tiers: Dictionary = LINES[tier()]
	var pool: Array = (tiers.get(place(), []) as Array) + (tiers["any"] as Array)
	var fresh := pool.filter(func(l: String) -> bool: return not recent.has(l))
	if fresh.is_empty():
		fresh = pool
	return fresh[_rng.randi() % fresh.size()]


func tick(dt: float) -> void:
	t -= dt
	if t > 0.0:
		return
	if bool(_c.get("busy", false)) or (bool(_c.get("seated_class", false)) and _rng.randf() < 0.5):
		t = 6.0
		return
	var line := pick()
	recent.append(line)
	if recent.size() > 8:
		recent.pop_front()
	events.append({"kind": "say", "text": line})
	t = 40.0 + _rng.randf() * 35.0
