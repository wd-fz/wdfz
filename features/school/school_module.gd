class_name SchoolModule
extends FeatureModule
## The school day and the player's stats, ported from the Web version (reference wd-fz.github.io@0bf508a):
## systems.js (clockTick, advanceGameTime, NEED_RULE, sanTick, violTick, ttTick, settleSan),
## domain/player-stats.js (StatRules), input.js stamina, campus-pressure.js, interact.js sitDown,
## world.js leaveSeat (stand positions exported per seat), ui/hud.js place/period text.
##
## Not ported yet (each says where it plugs in): death on SAN 0 and the assimilation ending
## (story.js kill / resolveAssimilation) — reported through `pending_story`; inspections, leave
## slips, outing permits, exams, danger zones, anomalies, patrol threats and talents.

const STATE_VERSION := 1
const TT_CFG := {"seat": 0.26, "dorm": 0.22, "decay": 0.6}
const TT_LINES := [
	"我：最近睡得挺好。铃一响就醒，不用闹钟。醒的时候，我已经坐在位子上了。",
	"我：课表不用看了。我知道下一节是什么。我还知道下下节、下下下节。",
	"我：……今天几号来着？黑板右上角的日期，我从来没见它变过。",
	"我：走廊里的人走得真整齐。我低头看了一眼——我的脚也在跟着拍子。",
	"我：座位表上，我的名字在哪一格？……哪一格都是我的名字。",
	"我：我好像一直都在这里。在我转来之前，就在这里。",
]
const TT_SEAT := {
	3: "我：……今天几号来着？我想站起来看一眼黑板，椅子没让我起来。",
	4: "我：腿麻了。不对——是腿不想动。椅子贴着我的背，像是不想让我起来。",
}
const FIELD_IDS := ["field", "court2", "track", "bad2", "bad3"]
const START_TSEC := 700.0

var _rooms: Dictionary = {}
var _outside: Dictionary = {}
var _campus: Dictionary = {}

var tsec := START_TSEC
var day := 1
var san := 100.0
var viol := 0.0
var tt := 0.0
var stam := 100.0
var tired := false
var seated := false
var seat_id := ""
var wrong := false
var tt_tier := 0
var pressure_clock := START_TSEC
var pressure_seen := 0
var viol_full := false
var pending_story := ""          # "san" | "assimilation" once the story port takes over
var _notices: PackedStringArray = []


func _init(rooms: Dictionary = {}, outside: Dictionary = {}, campus: Dictionary = {}) -> void:
	_rooms = rooms
	_outside = outside
	_campus = campus


func module_id() -> StringName:
	return &"school.day"


func state_version() -> int:
	return STATE_VERSION


func reset() -> void:
	tsec = START_TSEC
	day = 1
	san = 100.0
	viol = 0.0
	tt = 0.0
	stam = 100.0
	tired = false
	seated = false
	seat_id = ""
	wrong = false
	tt_tier = 0
	pressure_clock = START_TSEC
	pressure_seen = 0
	viol_full = false
	pending_story = ""
	_notices = PackedStringArray()


func capture() -> Dictionary:
	return {"tsec": tsec, "day": day, "san": san, "viol": viol, "tt": tt, "stam": stam, "tired": tired,
		"seated": seated, "seat_id": seat_id, "tt_tier": tt_tier, "pressure_clock": pressure_clock,
		"pressure_seen": pressure_seen, "viol_full": viol_full, "pending_story": pending_story}


func validate(data: Dictionary) -> String:
	if not SaveSchema.number_in(data.get("tsec"), 0, 1500) or not SaveSchema.is_integer(data.get("day"), 1, 100000):
		return "时间无效"
	for key: String in ["san", "viol", "tt"]:
		if not SaveSchema.number_in(data.get(key), 0, 100):
			return "数值无效：%s" % key
	if not SaveSchema.number_in(data.get("stam"), 0, 100) or not data.get("tired") is bool or not data.get("seated") is bool:
		return "体力或座位无效"
	if not data.get("seat_id") is String or (data["seated"] and _seat(String(data["seat_id"])).is_empty()):
		return "座位无效"
	if not SaveSchema.number_in(data.get("pressure_clock"), 0, 1e9) or not SaveSchema.is_integer(data.get("pressure_seen"), 0, 5):
		return "校园压力无效"
	if not data.get("pending_story") is String:
		return "剧情状态无效"
	return ""


func restore(data: Dictionary) -> void:
	tsec = float(data["tsec"])
	day = int(data["day"])
	san = float(data["san"])
	viol = float(data["viol"])
	tt = float(data["tt"])
	stam = float(data["stam"])
	tired = bool(data["tired"])
	seated = bool(data["seated"])
	seat_id = String(data["seat_id"])
	tt_tier = int(data.get("tt_tier", 0))
	pressure_clock = float(data["pressure_clock"])
	pressure_seen = int(data["pressure_seen"])
	viol_full = bool(data.get("viol_full", false))
	pending_story = String(data["pending_story"])


func take_notices() -> PackedStringArray:
	var out := _notices
	_notices = PackedStringArray()
	return out


func _say(text: String) -> void:
	_notices.append(text)


# ---- stats (StatRules) ----

static func stamina_max_for(value: float) -> float:
	return 40.0 + 0.6 * clampf(value, 0.0, 100.0)


func stamina_max() -> float:
	return stamina_max_for(san)


static func sanity_stage(value: float) -> int:
	return 0 if value > 60 else (1 if value > 30 else (2 if value > 12 else 3))


func change_san(amount: float, minimum: float = -INF) -> void:
	san = maxf(san + amount, minimum)


func _settle_san() -> void:
	san = clampf(san, 0.0, 100.0)
	stam = clampf(stam, 0.0, stamina_max())
	if san <= 0.0:
		# systems.js settleSan -> kill(..., 'san'). Story/death is not ported: hold at 1 and flag it.
		if pending_story.is_empty():
			pending_story = "san"
			_say("（死亡与结局尚未移植：SAN 已耗尽）")
		san = 1.0


func _add_violation(amount: float, exempt: bool) -> void:
	if amount > 0.0 and exempt:
		return
	viol = clampf(viol + amount, 0.0, 100.0)


# ---- places ----

func _room(world_id: String) -> Variant:
	return _rooms.get(world_id)


func _seat(id: String) -> Dictionary:
	var parts := id.split(":")
	if parts.size() != 3 or not _rooms.has(parts[0]):
		return {}
	for s: Dictionary in _rooms[parts[0]].get("seats", []):
		if s["seat_id"] == id:
			return s
	return {}


func in_classroom_here(world_id: String, w: Vector2) -> bool:
	var r: Variant = _room(world_id)
	if r == null or r["host"] != "teach" or r.get("floor") == null or int(r["floor"]) < 1 or int(r["floor"]) > 5 or r["flags"].get("stairwell", false):
		return false
	var row := int(floor((w.y - float(r["oy"])) / float(r["th"])))
	var rows: Array = _campus.get("classroom_rows", [7, 14])
	return row >= int(rows[0]) and row <= int(rows[1])


func in_dorm(world_id: String) -> bool:
	var r: Variant = _room(world_id)
	return r != null and r["host"] in ["dormN", "dormS"]


func on_field(world_id: String, w: Vector2) -> bool:
	if world_id != "out":
		return false
	var sc := float(_campus.get("SC", 2.0))
	var m := w / sc
	for o: Dictionary in _outside.get("objects", []):
		if o["id"] in FIELD_IDS and m.x > float(o["x"]) - 6 and m.x < float(o["x"]) + float(o["w"]) + 6 and m.y > float(o["y"]) - 6 and m.y < float(o["y"]) + float(o["h"]) + 6:
			return true
	return false


## ClassroomLayout.atOwn: seated on the own seat, within 1.5 units of its anchor.
func at_my_seat(world_id: String, w: Vector2) -> bool:
	var own: Dictionary = _campus.get("own_seat", {})
	if not seated or seat_id != String(own.get("seatId", "")) or world_id != String(own.get("room", "")):
		return false
	var s := _seat(seat_id)
	return not s.is_empty() and w.distance_to(Vector2(s["seated"]["x"], s["seated"]["y"])) <= 1.5


func place_name(world_id: String, height: float) -> String:
	if world_id == "out":
		return "武大附中 · 校园"
	var r: Variant = _room(world_id)
	if r == null:
		return "武大附中"
	if r["flags"].get("stairwell", false):
		var rise := 3.2
		for s: Dictionary in _campus.get("stair_layout", []):
			if s["id"] == world_id:
				rise = float(s["rise"])
		return "武大附中 · %s · %dF 附近" % [r["name"], int(floor(height / rise)) + 1]
	return "武大附中 · " + String(r["name"])


## ui/hud.js period line (leave, exam, outing, inspection and patrol parts wait for their systems).
func period_text(frozen: bool) -> String:
	if frozen:
		return "???"
	var p := SchoolClock.period_at(tsec)
	var where := "可探索，留意巡察" if p[3] in ["教室", "操场"] else SchoolClock.need_where(tsec)
	return "%s · %s" % [p[2], where]


func period_class(frozen: bool) -> String:
	return "ok" if frozen else ("warn" if wrong else "ok")


## Watch talent or item (Talent.capability('clock')); neither is ported, so time is unknown.
func clock_text(has_clock: bool) -> String:
	return SchoolClock.fmt_clock(tsec) if has_clock else "时间不明"


# ---- seats (interact.js sitDown / world.js leaveSeat) ----

func sit(world_id: String, c: int, r: int) -> Dictionary:
	var id := "%s:%d:%d" % [world_id, c, r]
	var s := _seat(id)
	if s.is_empty():
		return {}
	seated = true
	seat_id = id
	var own: Dictionary = _campus.get("own_seat", {})
	var text := "我坐下了。这是我自己的位子。" if id == String(own.get("seatId", "")) else "我坐下了。这个位子不是我的。"
	return {"notice": text, "pose": _pose_of(s["seated"])}


func stand_up() -> Dictionary:
	if not seated:
		return {}
	var s := _seat(seat_id)
	seated = false
	seat_id = ""
	return {} if s.is_empty() else {"pose": _pose_of(s["stand"])}


func start_seated(world_id: String) -> Dictionary:
	var own: Dictionary = _campus.get("own_seat", {})
	var s := _seat(String(own.get("seatId", "")))
	if s.is_empty() or world_id != String(own.get("room", "")):
		return {}
	seated = true
	seat_id = String(own["seatId"])
	return _pose_of(s["seated"])


static func _pose_of(p: Dictionary) -> Dictionary:
	return {"position": [p["scene_x"], 0.05, p["scene_z"]], "yaw": CampusGeometry.yaw_from_ang(float(p["ang"])), "pitch": 0.0}


# ---- clock ----

func game_clock() -> float:
	return SchoolClock.continuous(day, tsec)


func _observe_pressure() -> void:
	pressure_clock = maxf(pressure_clock, game_clock())


func pressure() -> Dictionary:
	return SchoolClock.pressure(_campus.get("pressure_curve", [{"clock": 0, "anomaly": 1, "danger": 1, "passive": 1, "rest": 1}]), pressure_clock)


func advance_game_time(minutes: float) -> void:
	_observe_pressure()
	var remaining := maxf(0.0, minutes)
	while remaining > 0.0:
		var slice := SchoolClock.forward_slice(tsec, day, remaining)
		tsec = float(slice["to"])
		remaining = float(slice["remaining"])
		if int(slice["day"]) != day:
			day = int(slice["day"])
			if day == 2:
				_say("我：……今天几号来着？我想不起来了。")
		if float(slice["time"]) != tsec:
			tsec = float(slice["time"])
		elif float(slice["used"]) <= 0.0:
			break
	_observe_pressure()


## systems.js clockTick: split real seconds across rate boundaries.
func clock_tick(dt: float) -> void:
	var left := maxf(0.0, dt)
	var guard := 0
	while left > 1e-9 and guard < 64:
		guard += 1
		var slice := SchoolClock.real_time_slice(tsec, left, SchoolClock.clock_boundary(tsec), SchoolClock.rate_at(tsec))
		advance_game_time(float(slice["minutes"]))
		if not slice["nudge"]:
			left -= float(slice["seconds"])


# ---- per-step simulation ----

## ctx: world_id, w (world units), height, moving, running, calendar (bool)
func step(dt: float, ctx: Dictionary) -> void:
	if dt <= 0.0 or not is_finite(dt):
		return
	_stamina(dt, bool(ctx.get("moving", false)), bool(ctx.get("running", false)))
	if bool(ctx.get("calendar", true)):
		clock_tick(dt)
	var world_id := String(ctx.get("world_id", ""))
	var w: Vector2 = ctx.get("w", Vector2.ZERO)
	var nw := SchoolClock.need_where(tsec)
	_san_tick(dt, nw, world_id, w)
	_viol_tick(dt, nw, world_id, w)
	_tt_tick(dt, nw, world_id)
	_settle_san()
	_pressure_tick()


## Whether Shift may sprint now (input.js: tired below 6 until back to 30).
func can_run() -> bool:
	return not tired


func _stamina(dt: float, moving: bool, running: bool) -> void:
	var cfg: Dictionary = _campus.get("stamina", {"back": 30, "run": 8, "rest": 12})
	stam = clampf(stam, 0.0, stamina_max())
	if stam <= 6.0:
		tired = true
	elif stam >= float(cfg["back"]):
		tired = false
	if running and moving and not tired:
		stam = maxf(0.0, stam - float(cfg["run"]) * dt)
	else:
		stam = minf(stamina_max(), stam + float(cfg["rest"]) * dt)


func _rule_there(nw: String, world_id: String, w: Vector2) -> bool:
	match nw:
		"教室":
			return at_my_seat(world_id, w)
		"宿舍":
			return in_dorm(world_id)
		"操场":
			return on_field(world_id, w)
	return true


func _san_tick(dt: float, nw: String, world_id: String, w: Vector2) -> void:
	var gain := dt * float(pressure()["passive"])
	match nw:
		"教室":
			if at_my_seat(world_id, w):
				change_san(0.42 * gain)
		"宿舍":
			if in_dorm(world_id):
				change_san(0.22 * gain)
		"操场":
			if on_field(world_id, w):
				change_san(0.5 * gain)
		_:
			change_san(0.8 * gain)


func _viol_tick(dt: float, nw: String, world_id: String, w: Vector2) -> void:
	var is_wrong := not _rule_there(nw, world_id, w)
	if nw in ["教室", "操场"]:
		is_wrong = false
	var mul := 1.4 if nw == "教室" else 1.0
	if world_id == "out" and SchoolClock.is_night(tsec):
		mul *= 0.5
	var evening := SchoolClock.evening_activity(tsec)
	if evening:
		is_wrong = false
	wrong = is_wrong
	if not evening and (is_wrong or nw == "宿舍"):
		_add_violation(dt * 0.85 * mul, evening)
	else:
		viol = maxf(0.0, viol - dt * 3.2)
	viol = clampf(viol, 0.0, 100.0)
	if viol >= 100.0 and not viol_full:
		viol_full = true
		_say("我：走廊那头，班主任看了我一眼，在本子上划了一笔。违规记满了——以后的请假条，他不会再签。")
	elif viol_full and viol < 60.0:
		viol_full = false


func _tt_tick(dt: float, nw: String, world_id: String) -> void:
	if tt >= 100.0:
		_resolve_assimilation()
		return
	if seated and nw == "教室":
		tt += TT_CFG["seat"] * dt
	elif in_dorm(world_id) and tsec >= SchoolClock.EVENING:
		tt += TT_CFG["dorm"] * dt
	else:
		tt = maxf(0.0, tt - TT_CFG["decay"] * dt)
	tt = clampf(tt, 0.0, 100.0)
	if tt >= 100.0:
		_resolve_assimilation()
		return
	var tier := int(floor(tt / 20.0))
	if tier > 0 and tier != tt_tier:
		tt_tier = tier
		if seated and TT_SEAT.has(tier):
			_say(TT_SEAT[tier])
		elif tier <= 6:
			_say(TT_LINES[tier - 1])


func _resolve_assimilation() -> void:
	# systems.js resolveAssimilation leads into the assimilation ending; the story port takes over here.
	if pending_story.is_empty():
		pending_story = "assimilation"
		_say("（结局尚未移植：同化已满）")


func _pressure_tick() -> void:
	_observe_pressure()
	var stage := int(pressure()["stage"])
	var messages: Array = _campus.get("pressure_messages", [])
	if stage <= pressure_seen or stage >= messages.size():
		return
	pressure_seen = stage
	if messages[stage] != null:
		_say(String(messages[stage]))
