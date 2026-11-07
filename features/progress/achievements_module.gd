class_name AchievementsModule
extends FeatureModule
## Achievements, ported from the Web version (reference wd-fz.github.io@0bf508a,
## domain/achievement-rules.js + modules/achievements). Record only, no bonuses.
## Ported here: the public entries whose facts the ported systems can produce. Entries that need
## systems not yet in Godot (exams, snake, garage, paper planes, the other routes, talents, the
## archive, speedrun, ...) are absent, not locked. Hidden entries are not part of this public table
## (see CLAUDE.md); the achievement method text stays internal, the player sees only the name and,
## once unlocked, a memory line.
## Run facts (rooms walked, inspections, wrong quiz answers, rescues) are saved with the session;
## the cross-run profile (unlocked, collected sets) is stored by the app in a side file.

const STATE_VERSION := 1
const TIERS := {"n": {"name": "普通", "pts": 10}, "e": {"name": "精英", "pts": 40}, "p": {"name": "史诗", "pts": 100}}
const PUBLIC_ENDS := ["car", "face", "portal", "cyber", "dismissal"]
const EXPLORE := ["teach1", "teach2", "teach3", "teach4", "teach5", "teach6", "admin1", "admin2", "admin3", "admin4", "admin5",
	"lab1", "lab2", "lab3", "lab4", "lab5", "canteen1", "garage1", "bell1", "guard1", "gear1", "trash1"]
const EXPLORE_ANY := [["dorm1", "dorm2", "dorm3"], ["dorm4", "dorm5", "dorm6"]]
## id -> [tier, name, memory]
const LIST := {
	"n.day2": ["n", "熬过第一天", "熄灯，换日。日历往后翻了一页。"],
	"n.anomaly": ["n", "看见了", "从那一刻起，我知道这所学校不对劲。"],
	"n.survive": ["n", "还活着", "它过去了。手还在发抖，但我还站着。"],
	"n.lost": ["n", "两短一长", "灯还在闪。脚步声停在了拐角另一边。"],
	"n.locker": ["n", "柜子里很安静", "铁皮的缝里，光一条一条地暗下去，又亮起来。"],
	"n.inspection": ["n", "按时到场", "黑影围成一圈，又散开。它们没有记下我。"],
	"n.wake": ["n", "梦里记得", "我猛地抬起头，后背全是汗。"],
	"n.saved": ["n", "被替了一次", "刚才那一下，像是有人替我挨了。"],
	"e.end_cyber": ["e", "《网安仙人》", "机柜一架架熄灭。天亮了。"],
	"p.talents": ["p", "七种活法", "换了好几种活法，每一种都走出了校门。"],
	"p.routes": ["p", "四条路", "我从这所学校出去过很多次，每一次走的路都不一样。"],
	"p.five_routes": ["p", "五条路", "最后一次，学校以为我只是放学回家。"],
	"e.end_international": ["e", "《外国语学生》", "队尾的人回头看了一眼。"],
	"e.exchange_together": ["e", "一个都没少", "一个都没少。"],
	"e.window_escape": ["e", "别看里面", "我低着头退开了，那双眼睛没有跟过来。"],
	"e.speedrun": ["e", "计时", "表停下的那一刻，我还在跑。"],
	"p.fast": ["p", "赶在铃响前", "铃还没响，我已经在外面了。"],
	"n.opening": ["n", "第四节", "粉笔灰停在半空。我趴到桌上，又抬起了头。"],
	"n.midnight": ["n", "明天再来", "那一碗是热的。打饭的人一直没有回头。"],
	"n.desk": ["n", "看课桌", "纸条上那一句，后来救过我。"],
	"n.special": ["n", "特别的一天", "今天的广播，和平时不一样。"],
	"e.notes": ["e", "十张纸条", "桌肚里的纸条，我一张一张都记下了。"],
	"n.vault": ["n", "换一条路", "我摔在地上，腿一阵剧痛，还能走。"],
	"n.first_aid": ["n", "还能走", "包扎好了，还能走。"],
	"e.campus_fall": ["e", "楼层之外", "手离开了栏杆。"],
	"e.nolaugh": ["e", "笑时莫出声", "那一天，我一直没有出声。"],
	"n.broadcast": ["n", "核对", "记录本里没有刚才那一条。喇叭里还在啸叫。"],
	"e.end_dismissal": ["e", "《放学》", "长铃还在响。我和同学一起走出了北门。"],
	"n.rest": ["n", "喘口气", "有那么一会儿，我忘了自己在哪儿。"],
	"n.bell": ["n", "钟声", "钟声一圈一圈荡开，广播里有人慢慢地念。"],
	"n.exam": ["n", "交卷", "监考的人收走卷子，没有看我。"],
	"e.end_portal": ["e", "《门》", "光圈合上之前，我回头看了一眼。"],
	"e.allexam": ["e", "全场交卷", "卷子一张接一张收上去，都写满了。"],
	"e.rest8": ["e", "八种喘息", "我找到了很多让自己缓过来的办法。"],
	"n.torch": ["n", "照亮", "光打过去的时候，它往后退了一步。"],
	"e.end_car": ["e", "《闸门》", "车灯照亮了北门。后视镜里，教学楼一层层暗下去。"],
	"e.firstcar": ["e", "一次就对", "引擎一下就着了。"],
	"e.end_face": ["e", "《白名单》", "闸机亮了一下。我的名字留在了最后一行。"],
	"e.day1": ["e", "当天离校", "那一天还没结束，我就已经不在学校里了。"],
	"e.hard": ["e", "梦魇", "没有惊醒，也没有第二次。我还是出来了。"],
	"e.attendance": ["e", "全勤", "两次点名，我都在。"],
	"e.whitelist": ["e", "三道全对", "闸机没有犹豫。"],
	"e.explore": ["e", "踏遍校园", "这所学校的每一层，我都走过。"],
	"e.lethal4": ["e", "见识", "有些东西，我见过不止一次了。"],
	"p.hard_day1": ["p", "梦魇·当天", "最深的梦，最短的一天。"],
	"p.oneshot": ["p", "一命", "从头到尾，没有人替我挡过一下。"],
	"p.anomalies": ["p", "异象图鉴", "这所学校能拿出来的东西，我都见过了。"],
}
const SCORELESS := ["n.wake", "n.saved", "e.campus_fall"]
## Cross-run goals (cross-run sets).
const LETHAL_GOAL := 4

var unlocked: Dictionary = {}     # profile: id -> true
var sets: Dictionary = {"lethal": {}, "anomalies": {}, "rest": {}, "talents": {}, "notes": {}}   # profile: collected ids
var rooms: Dictionary = {}        # run
var insp: Dictionary = {}         # run: "day" -> {slot: 0/1}
var face_wrong := 0               # run
var saved := false                # run: rescued by the pill
var started := ""                 # run: the anomaly that started
var exams: Dictionary = {}        # run: "day" -> {pass, fail}
var events: Array = []
var _anomaly_total := 25


func _init(anomaly_total: int = 25) -> void:
	_anomaly_total = anomaly_total


func module_id() -> StringName:
	return &"profile.achievements"


func state_version() -> int:
	return STATE_VERSION


func reset() -> void:
	rooms = {}
	insp = {}
	face_wrong = 0
	saved = false
	started = ""
	exams = {}
	events = []


func capture() -> Dictionary:
	return {"rooms": rooms.keys(), "insp": insp, "face_wrong": face_wrong, "saved": saved, "exams": exams.duplicate(true)}


func validate(data: Dictionary) -> String:
	if not (data.get("rooms") is Array) or not (data.get("insp") is Dictionary):
		return "成就记录无效"
	if not SaveSchema.is_integer(data.get("face_wrong"), 0, 999) or not (data.get("saved") is bool):
		return "成就记录无效"
	return ""


func restore(data: Dictionary) -> void:
	reset()
	for id: Variant in data["rooms"]:
		rooms[String(id)] = true
	for day: String in data["insp"]:
		insp[day] = (data["insp"][day] as Dictionary).duplicate(true)
	face_wrong = int(data["face_wrong"])
	saved = bool(data["saved"])
	exams = (data.get("exams", {}) as Dictionary).duplicate(true) if data.get("exams") is Dictionary else {}


func profile() -> Dictionary:
	return {"unlocked": unlocked.duplicate(), "sets": sets.duplicate(true)}


func load_profile(data: Dictionary) -> void:
	unlocked = {}
	for id: String in (data.get("unlocked", {}) as Dictionary):
		if LIST.has(id):
			unlocked[id] = true
	sets = {"lethal": {}, "anomalies": {}, "rest": {}, "talents": {}, "notes": {}}
	for name: String in sets:
		for k: String in ((data.get("sets", {}) as Dictionary).get(name, {}) as Dictionary):
			sets[name][k] = true


func take_events() -> Array:
	var out := events
	events = []
	return out


## Public entries in display order, with their state. Locked entries show only the name.
func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in LIST:
		var row: Array = LIST[id]
		var got := unlocked.has(id)
		var e := {"id": id, "tier": TIERS[row[0]]["name"], "name": row[1], "unlocked": got, "memo": row[2] if got else ""}
		var prog := progress(id)
		if not prog.is_empty():
			e["progress"] = prog
		out.append(e)
	return out


func progress(id: String) -> Dictionary:
	match id:
		"e.lethal4":
			return {"n": mini(sets["lethal"].size(), LETHAL_GOAL), "of": LETHAL_GOAL}
		"p.anomalies":
			return {"n": mini(sets["anomalies"].size(), _anomaly_total), "of": _anomaly_total}
		"p.talents":
			return {"n": mini(sets["talents"].size(), TalentModule.KEYS.size()), "of": TalentModule.KEYS.size()}
		"e.notes":
			return {"n": mini(sets["notes"].size(), DayModule.TASKS.size()), "of": DayModule.TASKS.size()}
		"e.rest8":
			return {"n": mini(sets["rest"].size(), FacilitiesModule.SAN_ACTS.size()), "of": FacilitiesModule.SAN_ACTS.size()}
	return {}


func points() -> int:
	var total := 0
	for id: String in unlocked:
		if not SCORELESS.has(id):
			total += int(TIERS[LIST[id][0]]["pts"])
	return total


## One fact from the run. Returns the ids unlocked by it.
## day {day}, anomaly {phase: start|end, id, survived, lethal, public}, patrol {what: lost|locker},
## inspection {day, slot, compliant}, room {id}, wake, protect, ending {id, day, diff, permanent},
## garage {what: torch|drive, tried}.
func fact(f: Dictionary) -> Array[String]:
	var got: Array[String] = []
	match String(f["kind"]):
		"room":
			rooms[String(f["id"])] = true
		"inspection":
			var d: Dictionary = insp.get(str(int(f["day"])), {})
			d[str(int(f["slot"]))] = 1 if bool(f["compliant"]) else 0
			insp[str(int(f["day"]))] = d
		"protect":
			saved = true
		"rest":
			sets["rest"][String(f["key"])] = true
		"lesson":
			if bool(f.get("correct", false)):
				sets["notes"][str(int(f["task"]))] = true
		"ending":
			if _public_end_id(String(f.get("id", ""))) and TalentModule.KEYS.has(String(f.get("talent", ""))):
				sets["talents"][String(f["talent"])] = true
		"exam":
			if f["phase"] == "paper":
				var x: Dictionary = exams.get(str(int(f.get("day", 1))), {"pass": 0, "fail": 0})
				x["pass" if bool(f.get("pass", false)) else "fail"] = int(x["pass" if bool(f.get("pass", false)) else "fail"]) + 1
				exams[str(int(f.get("day", 1)))] = x
		"anomaly":
			if f["phase"] == "start":
				started = String(f["id"])
				if bool(f.get("public", true)):
					sets["anomalies"][String(f["id"])] = true
			elif bool(f.get("survived", false)) and bool(f.get("lethal", false)) and started == String(f["id"]):
				sets["lethal"][String(f["id"])] = true
	# Entries that look at other entries (four routes, five routes) see this fact's unlocks too.
	var again := true
	while again:
		again = false
		for id: String in LIST:
			if not unlocked.has(id) and _test(id, f):
				unlocked[id] = true
				got.append(id)
				events.append({"kind": "unlock", "id": id, "name": LIST[id][1]})
				again = true
	return got


func _public_end_id(id: String) -> bool:
	return PUBLIC_ENDS.has(id)


func _public_end(f: Dictionary) -> bool:
	return String(f["kind"]) == "ending" and PUBLIC_ENDS.has(String(f.get("id", "")))


func _test(id: String, f: Dictionary) -> bool:
	var kind := String(f["kind"])
	match id:
		"n.day2":
			return kind == "day" and int(f["day"]) == 2
		"n.anomaly":
			return kind == "anomaly" and f["phase"] == "start"
		"n.survive":
			return kind == "anomaly" and f["phase"] == "end" and bool(f.get("survived", false)) and bool(f.get("lethal", false)) and started == String(f["id"])
		"n.lost":
			return kind == "patrol" and f["what"] == "lost"
		"n.locker":
			return kind == "patrol" and f["what"] == "locker"
		"n.inspection":
			return kind == "inspection" and bool(f["compliant"])
		"n.wake":
			return kind == "wake"
		"n.saved":
			return kind == "protect"
		"n.torch":
			return kind == "garage" and f["what"] == "torch"
		"n.rest":
			return kind == "rest"
		"e.end_international":
			return kind == "ending" and f["id"] == "international"
		"e.exchange_together":
			return kind == "exchange" and f.get("what") == "arrived" and bool(f.get("together", false))
		"e.window_escape":
			return kind == "gaze" and f.get("what") == "escape"
		"e.speedrun":
			return kind == "speedrun" and f.get("status") == "finished"
		"p.fast":
			return kind == "speedrun" and f.get("status") == "finished" and PUBLIC_ENDS.has(String(f.get("route", ""))) and int(f.get("ms", 0)) > 0 and int(f.get("ms", 0)) <= 900000
		"n.opening":
			return kind == "opening"
		"n.midnight":
			return kind == "midnightMeal"
		"n.desk":
			return kind == "lesson" and bool(f.get("correct", false))
		"n.special":
			return kind == "specialDay"
		"e.notes":
			return sets["notes"].size() >= DayModule.TASKS.size()
		"n.vault":
			return kind == "vault" and f.get("what") == "landed"
		"n.first_aid":
			return kind == "treated"
		"e.campus_fall":
			return kind == "death" and f.get("source") == "campus_fall"
		"e.nolaugh":
			return kind == "fakeNormal" and bool(f.get("done", false)) and int(f.get("laughs", 1)) == 0
		"n.broadcast":
			return kind == "broadcast" and f.get("what") == "verified" and f.get("real", true) == false
		"e.end_dismissal":
			return kind == "ending" and f["id"] == "dismissal"
		"e.end_cyber":
			return kind == "ending" and f["id"] == "cyber"
		"p.routes":
			return ["car", "face", "portal", "cyber"].all(func(e: String) -> bool: return unlocked.has("e.end_" + e))
		"p.talents":
			return sets["talents"].size() >= TalentModule.KEYS.size()
		"p.five_routes":
			return PUBLIC_ENDS.all(func(e: String) -> bool: return unlocked.has("e.end_" + e))
		"e.rest8":
			return kind == "rest" and sets["rest"].size() >= FacilitiesModule.SAN_ACTS.size()
		"n.bell":
			return kind == "exam" and f["phase"] == "start"
		"n.exam":
			return kind == "exam" and f["phase"] == "paper" and bool(f.get("pass", false))
		"e.allexam":
			if kind != "exam" or f["phase"] != "paper" or not bool(f.get("pass", false)):
				return false
			var x: Dictionary = exams.get(str(int(f.get("day", 1))), {})
			return int(x.get("pass", 0)) >= 2 and int(x.get("fail", 0)) == 0
		"e.end_portal":
			return kind == "ending" and f["id"] == "portal"
		"e.end_car":
			return kind == "ending" and f["id"] == "car"
		"e.firstcar":
			return kind == "garage" and f["what"] == "drive" and int(f.get("tried", 0)) == 0
		"e.end_face":
			return kind == "ending" and f["id"] == "face"
		"e.day1":
			return _public_end(f) and int(f.get("day", 1)) == 1
		"e.hard":
			return _public_end(f) and f.get("diff", "easy") == "hard"
		"e.attendance":
			if kind != "inspection" or not bool(f["compliant"]):
				return false
			var d: Dictionary = insp.get(str(int(f["day"])), {})
			var ok := 0
			var bad := 0
			for k: String in d:
				if int(d[k]) > 0:
					ok += 1
				else:
					bad += 1
			return ok >= 2 and bad == 0
		"e.whitelist":
			return kind == "ending" and f["id"] == "face" and face_wrong == 0
		"e.explore":
			if kind != "room":
				return false
			for r: String in EXPLORE:
				if not rooms.has(r):
					return false
			for group: Array in EXPLORE_ANY:
				if not group.any(func(r: String) -> bool: return rooms.has(r)):
					return false
			return true
		"e.lethal4":
			return sets["lethal"].size() >= LETHAL_GOAL
		"p.hard_day1":
			return _public_end(f) and f.get("diff", "easy") == "hard" and int(f.get("day", 1)) == 1
		"p.oneshot":
			return _public_end(f) and f.get("diff", "easy") == "hard" and not saved
		"p.anomalies":
			return sets["anomalies"].size() >= _anomaly_total
	return false
