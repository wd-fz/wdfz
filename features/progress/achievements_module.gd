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
const SCORELESS := ["n.wake", "n.saved"]
## Cross-run goals (cross-run sets).
const LETHAL_GOAL := 4

var unlocked: Dictionary = {}     # profile: id -> true
var sets: Dictionary = {"lethal": {}, "anomalies": {}}   # profile: collected ids
var rooms: Dictionary = {}        # run
var insp: Dictionary = {}         # run: "day" -> {slot: 0/1}
var face_wrong := 0               # run
var saved := false                # run: rescued by the pill
var started := ""                 # run: the anomaly that started
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
	events = []


func capture() -> Dictionary:
	return {"rooms": rooms.keys(), "insp": insp, "face_wrong": face_wrong, "saved": saved}


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


func profile() -> Dictionary:
	return {"unlocked": unlocked.duplicate(), "sets": sets.duplicate(true)}


func load_profile(data: Dictionary) -> void:
	unlocked = {}
	for id: String in (data.get("unlocked", {}) as Dictionary):
		if LIST.has(id):
			unlocked[id] = true
	sets = {"lethal": {}, "anomalies": {}}
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
	return {}


func points() -> int:
	var total := 0
	for id: String in unlocked:
		if not SCORELESS.has(id):
			total += int(TIERS[LIST[id][0]]["pts"])
	return total


## One fact from the run. Returns the ids unlocked by it.
## day {day}, anomaly {phase: start|end, id, survived, lethal, public}, patrol {what: lost|locker},
## inspection {day, slot, compliant}, room {id}, wake, protect, ending {id, day, diff, permanent}.
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
		"anomaly":
			if f["phase"] == "start":
				started = String(f["id"])
				if bool(f.get("public", true)):
					sets["anomalies"][String(f["id"])] = true
			elif bool(f.get("survived", false)) and bool(f.get("lethal", false)) and started == String(f["id"]):
				sets["lethal"][String(f["id"])] = true
	for id: String in LIST:
		if not unlocked.has(id) and _test(id, f):
			unlocked[id] = true
			got.append(id)
			events.append({"kind": "unlock", "id": id, "name": LIST[id][1]})
	return got


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
