class_name SchoolModule
extends FeatureModule
## The school day and the player's stats, ported from the Web version (reference wd-fz.github.io@0bf508a):
## systems.js (clockTick, advanceGameTime, NEED_RULE, sanTick, violTick, ttTick, settleSan),
## domain/player-stats.js (StatRules), input.js stamina, campus-pressure.js, interact.js sitDown,
## world.js leaveSeat (stand positions exported per seat), ui/hud.js place/period text.
##
## Deaths (SAN 0, assimilation 100) are requested through `take_deaths()` and resolved by the
## story module (story.js kill). Not ported yet: leave slips, exams, danger zones, anomalies,
## patrol threats and talents.

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
## inspection.js INSPECT_CONFIG.
const INSPECT := {"times": [770.0, 1070.0], "warning_seconds": 60.0, "late_limit": 3.0, "duration": 8.0, "move_every": 1.0,
	"move_violation": 2.0, "gaze_san": 2.0, "good_san": 3.0, "bad_san": 8.0, "good_violation": 8.0, "bad_violation": 10.0, "assimilation": 3.0}

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
var _deaths: Array = []
## Inspection state (RT.inspection) and the outing permit it grants (RT.outing).
var inspection := {}
var outing := {}
## Attendance duties (attendance.js): a registered outing promises attendance at the next check.
var duties := {"seq": 0, "list": [], "processed": {}}
var _events: Array = []
var active_seconds := 0.0
var _warn_times: Array = []
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
	_deaths = []
	_notices = PackedStringArray()
	inspection = {"seen": {}, "warned": {}, "queue": [], "current": {}, "settled": {}, "calm": 0.0, "calm_room": ""}
	outing = {}
	duties = {"seq": 0, "list": [], "processed": {}}
	_events = []
	active_seconds = 0.0


func capture() -> Dictionary:
	return {"tsec": tsec, "day": day, "san": san, "viol": viol, "tt": tt, "stam": stam, "tired": tired,
		"seated": seated, "seat_id": seat_id, "tt_tier": tt_tier, "pressure_clock": pressure_clock,
		"pressure_seen": pressure_seen, "viol_full": viol_full,
		"inspection": inspection.duplicate(true), "outing": outing.duplicate(true), "duties": duties.duplicate(true), "active_seconds": active_seconds}


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
	var ins: Variant = data.get("inspection", {})
	if not ins is Dictionary or not ins.get("queue", []) is Array or not ins.get("seen", {}) is Dictionary:
		return "检查状态无效"
	if not data.get("outing", {}) is Dictionary:
		return "外出登记无效"
	var d: Variant = data.get("duties", {"seq": 0, "list": [], "processed": {}})
	if not d is Dictionary or not d.get("list", []) is Array or not d.get("processed", {}) is Dictionary or not SaveSchema.is_integer(d.get("seq", 0), 0, 1000000000):
		return "到场责任无效"
	for duty: Variant in d.get("list", []):
		if not duty is Dictionary or not String(duty.get("targetCheckId", "")).contains(":") or not String(duty.get("status", "")) in ["pending", "fulfilled", "absent", "excused"]:
			return "到场责任条目无效"
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
	_deaths = []
	inspection = {"seen": {}, "warned": {}, "queue": [], "current": {}, "settled": {}, "calm": 0.0}
	inspection.merge(data.get("inspection", {}).duplicate(true), true)
	for item: Dictionary in inspection["queue"]:
		item["day"] = int(item["day"])
		item["slot"] = int(item["slot"])
	var cur: Dictionary = inspection["current"]
	if not cur.is_empty():
		cur["day"] = int(cur["day"])
		cur["slot"] = int(cur["slot"])
	outing = data.get("outing", {}).duplicate(true)
	duties = {"seq": 0, "list": [], "processed": {}}
	duties.merge(data.get("duties", {}).duplicate(true), true)
	duties["seq"] = int(duties["seq"])
	active_seconds = float(data.get("active_seconds", 0.0))
	_events = []
	inspection["calm_room"] = String(inspection.get("calm_room", ""))
	# attendance.js restore: pending duties whose check never ran and is long past roll forward.
	for duty: Dictionary in duties["list"]:
		if duty["status"] != "pending":
			continue
		var parts := String(duty["targetCheckId"]).split(":")
		var item := {"day": int(parts[0]), "slot": int(parts[1])}
		var running: Dictionary = inspection["current"]
		var exists: bool = (not running.is_empty() and int(running["day"]) == item["day"] and int(running["slot"]) == item["slot"])
		for q: Dictionary in inspection["queue"]:
			exists = exists or (int(q["day"]) == item["day"] and int(q["slot"]) == item["slot"])
		if not exists and _check_clock(item["day"], item["slot"]) < game_clock():
			_duty_cancel(item)


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
	if san <= 0.0 and not _requested("san"):
		_deaths.append({"msg": "你一直撑着的那根弦，断了。", "fx": "vignette", "source": "san"})


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
	if inspection_active():
		return "学生会检查 · 坐稳自己的座位"
	if inspection_upcoming():
		return "集合将至 · 请坐回自己的座位"
	if permit():
		return "外出登记 · " + return_label()
	var p := SchoolClock.period_at(tsec)
	var where := "可探索，留意巡察" if p[3] in ["教室", "操场"] else SchoolClock.need_where(tsec)
	return "%s · %s" % [p[2], where]


func period_class(frozen: bool) -> String:
	if frozen:
		return "ok"
	if inspection_upcoming() or wrong:
		return "warn"
	return "leave" if permit() else "ok"


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
		var before := float(slice["from"])
		tsec = float(slice["to"])
		_inspection_cross(day, before, tsec)
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
	active_seconds += dt
	_stamina(dt, bool(ctx.get("moving", false)), bool(ctx.get("running", false)), bool(ctx.get("snack", false)), bool(ctx.get("hiding", false)))
	change_san(float(ctx.get("pill_san", 0.0)))
	if bool(ctx.get("calendar", true)):
		clock_tick(dt)
	var world_id := String(ctx.get("world_id", ""))
	var w: Vector2 = ctx.get("w", Vector2.ZERO)
	_inspection_tick(dt, ctx)
	var nw := SchoolClock.need_where(tsec)
	_san_tick(dt, nw, world_id, w, ctx)
	_viol_tick(dt, nw, world_id, w, ctx)
	_tt_tick(dt, nw, world_id)
	_settle_san()
	_pressure_tick()


## Whether Shift may sprint now (input.js: tired below 6 until back to 30).
func can_run(snack: bool = false) -> bool:
	return snack or not tired


## input.js: the snack lets you run while out of breath and running costs nothing.
func _stamina(dt: float, moving: bool, running: bool, snack: bool = false, hiding: bool = false) -> void:
	var cfg: Dictionary = _campus.get("stamina", {"back": 30, "run": 8, "rest": 12})
	stam = clampf(stam, 0.0, stamina_max())
	if stam <= 6.0:
		tired = true
	elif stam >= float(cfg["back"]):
		tired = false
	if hiding:
		stam = minf(stamina_max(), stam + 11.0 * dt) # updatePlayer: hidden in a locker you recover 11 per second
		return
	if snack:
		if not (running and moving):
			stam = minf(stamina_max(), stam + float(cfg["rest"]) * dt)
		return
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


func _san_tick(dt: float, nw: String, world_id: String, w: Vector2, ctx: Dictionary) -> void:
	# systems.js sanTick: SAN <= 0 is judged first, before any recovery of this step.
	if san <= 0.0:
		_settle_san()
		return
	if inspection_active() or bool(ctx.get("patrol_threat", false)) or bool(ctx.get("hiding", false)):
		return # no daily recovery during an inspection, a patrol threat or while hiding.
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


func _viol_tick(dt: float, nw: String, world_id: String, w: Vector2, ctx: Dictionary) -> void:
	if inspection_active():
		wrong = not in_classroom_here(world_id, w)
		return
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
	if inspection_active():
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
	if not _requested("assimilation"):
		_deaths.append({"msg": "你在自己的位子上坐好了。椅子很合身，像是照着你做的。这一次，不用再起来了。", "fx": "names", "source": "assimilation"})


func _requested(source: String) -> bool:
	for d: Dictionary in _deaths:
		if d["source"] == source:
			return true
	return false


## addViolation(amount, source): exempt while on leave or at the evening activity.
func add_violation(amount: float) -> void:
	_add_violation(amount, SchoolClock.evening_activity(tsec))


## Inspection.cancel (story.js kill): a running check is dropped without settling.
func cancel_inspection() -> void:
	var cur: Dictionary = inspection["current"]
	if not cur.is_empty():
		_duty_cancel(cur)
	inspection["current"] = {}


## Deaths the rules ran into this step (systems.js settleSan / resolveAssimilation -> kill).
func take_deaths() -> Array:
	var out := _deaths
	_deaths = []
	return out


## story.js survivalReset after a protected death; the assimilation case falls back to 86.
func survive(source: String) -> void:
	san = maxf(san, 45.0)
	viol = minf(viol, 40.0)
	if source == "assimilation":
		tt = 86.0
		tt_tier = 4
	_settle_san()


## story.js dreamWake: back to 11:40 on the own seat; the day, bag and found things stay.
func dream_wake_reset() -> void:
	outing = {}
	duties = {"seq": 0, "list": [], "processed": {}}
	tsec = START_TSEC
	san = 78.0
	viol = 0.0
	stam = 100.0
	tired = false
	tt = 0.0
	tt_tier = 0
	wrong = false
	inspection["current"] = {}
	inspection["queue"] = []


func _pressure_tick() -> void:
	_observe_pressure()
	var stage := int(pressure()["stage"])
	var messages: Array = _campus.get("pressure_messages", [])
	if stage <= pressure_seen or stage >= messages.size():
		return
	pressure_seen = stage
	if messages[stage] != null:
		_say(String(messages[stage]))



# ---- outing permit (school-day.js) ----

func _deadline() -> float:
	return 770.0 if tsec < 770.0 else (1070.0 if tsec < 1070.0 else SchoolClock.LIGHTS_OUT)


func permit() -> bool:
	if day < 2 or outing.is_empty() or int(outing.get("day", 0)) != day:
		return false
	var from := float(outing["from"])
	var until := float(outing["until"])
	var expect := 770.0 if from < 770.0 else (1070.0 if from < 1070.0 else SchoolClock.LIGHTS_OUT)
	return from >= 440.0 and from <= tsec and until == expect and tsec < until


func grant_outing(quiet: bool) -> bool:
	if day == 1:
		if not quiet:
			_say("第一天暂不开放外出登记 · 假条仍可使用")
		return false
	if SchoolClock.is_night(tsec):
		if not quiet:
			_say("熄灯后不能登记外出 · 请回宿舍")
		return false
	outing = {"day": day, "from": tsec, "until": _deadline()}
	_duty_grant("inspection" if quiet else "manual")
	if not quiet:
		_say("外出登记已记下 · %s；到场责任：%s" % [return_label(), duty_summary()])
	return true


func return_label() -> String:
	var until := float(outing["until"]) if permit() else _deadline()
	return "熄灯前回宿舍" if until == SchoolClock.LIGHTS_OUT else SchoolClock.fmt_clock(until) + " 回教室"


# ---- student council inspection (inspection.js) ----

func _warn_time(i: int) -> float:
	if _warn_times.is_empty():
		for t: float in INSPECT["times"]:
			_warn_times.append(SchoolClock.clock_time_before(t, INSPECT["warning_seconds"]))
	return float(_warn_times[i])


func _inspection_cross(d: int, before: float, after: float) -> void:
	if after <= before:
		return
	var times: Array = INSPECT["times"]
	for i in times.size():
		var key := "%d:%d" % [d, i]
		if after >= _warn_time(i) and after < times[i] and not inspection["warned"].has(key):
			inspection["warned"][key] = true
			_say("广播：「请各班同学注意，学生会将于%s到各班检查，请坐回自己的座位。」" % ("五点五十" if i else "十二点五十"))
		if before <= times[i] and after >= times[i] and not inspection["seen"].has(key):
			inspection["seen"][key] = true
			inspection["warned"][key] = true
			inspection["queue"].append({"day": d, "slot": i})


func inspection_active() -> bool:
	return not (inspection.get("current", {}) as Dictionary).is_empty()


func inspection_pending() -> bool:
	return inspection_active() or not (inspection.get("queue", []) as Array).is_empty()


func inspection_upcoming() -> bool:
	if inspection_active():
		return false
	var times: Array = INSPECT["times"]
	for i in times.size():
		var key := "%d:%d" % [day, i]
		if not inspection["seen"].has(key) and tsec >= _warn_time(i) and tsec < times[i]:
			return true
	return false


func _stale(item: Dictionary) -> bool:
	return int(item["day"]) != day or tsec > float(INSPECT["times"][int(item["slot"])]) + INSPECT["late_limit"]


func inspection_points() -> Array:
	var cur: Dictionary = inspection.get("current", {})
	return cur.get("points", [])


## inspection.js points: up to six standing spots 30–66 units around the player, 15 apart.
static func ring_points(me: Vector2, can_stand: Callable) -> Array:
	var result: Array = []
	for i in 20:
		if result.size() >= 6:
			break
		var a := i * TAU / 20.0
		for j in 4:
			var p := me + Vector2(cos(a), sin(a)) * (30.0 + j * 12.0)
			if not can_stand.call(p):
				continue
			var spaced := true
			for q: Vector2 in result:
				if q.distance_to(p) <= 15.0:
					spaced = false
			if spaced:
				result.append(p)
			break
	return result


func _inspection_tick(dt: float, ctx: Dictionary) -> void:
	inspection["calm"] = maxf(0.0, float(inspection.get("calm", 0.0)) - dt)
	var c: Dictionary = inspection["current"]
	var world_id := String(ctx.get("world_id", ""))
	var w: Vector2 = ctx.get("w", Vector2.ZERO)
	var can_stand: Callable = ctx.get("can_stand", func(_p: Vector2) -> bool: return true)
	if c.is_empty():
		var queue: Array = inspection["queue"]
		while not queue.is_empty() and _stale(queue[0]):
			_duty_cancel(queue.pop_front())
		if not queue.is_empty():
			var item: Dictionary = queue.pop_front()
			var present := at_my_seat(world_id, w)
			inspection["current"] = {"day": item["day"], "slot": item["slot"], "t": 0.0, "look": 0.0, "move": 0.0,
				"compliant": present, "room": world_id, "points": _points_json(ring_points(w, can_stand))}
			_say("我：走廊里的声音一下子停了。一圈黑影站在附近——别动，也别看它们。")
		return
	if c["room"] != world_id:
		c["room"] = world_id
		c["points"] = _points_json(ring_points(w, can_stand))
	if not at_my_seat(world_id, w):
		c["compliant"] = false
	c["t"] = float(c["t"]) + dt
	if bool(ctx.get("moving", false)):
		c["move"] = float(c["move"]) + dt
		while float(c["move"]) >= INSPECT["move_every"]:
			c["move"] = float(c["move"]) - INSPECT["move_every"]
			_add_violation(INSPECT["move_violation"], false)
	if _looking(c, w, float(ctx.get("ang", 0.0)), float(ctx.get("pitch", 0.0)), ctx.get("line_clear", Callable())):
		c["look"] = float(c["look"]) + dt
		while float(c["look"]) >= 1.0:
			c["look"] = float(c["look"]) - 1.0
			san = maxf(0.0, san - INSPECT["gaze_san"])
	if float(c["t"]) >= INSPECT["duration"]:
		_inspection_finish(c, world_id, w)


static func _points_json(points: Array) -> Array:
	var out: Array = []
	for p: Vector2 in points:
		out.append([p.x, p.y])
	return out


## Looking at a silhouette: within 95 units, within 0.42 rad of the heading, line not blocked.
func _looking(c: Dictionary, me: Vector2, ang: float, pitch: float, line_clear: Callable) -> bool:
	if absf(pitch) > 0.9:
		return false
	for xy: Array in c["points"]:
		var p := Vector2(xy[0], xy[1])
		var d := me.distance_to(p)
		if d > 1.0 and d < 95.0 and CampusGeometry.ang_diff(ang, atan2(p.y - me.y, p.x - me.x)) < 0.42:
			if not line_clear.is_valid() or line_clear.call(me, p):
				return true
	return false


func _inspection_finish(c: Dictionary, world_id: String, w: Vector2) -> void:
	inspection["current"] = {}
	var key := "%d:%d" % [int(c["day"]), int(c["slot"])]
	if inspection["settled"].has(key):
		return
	var good := bool(c["compliant"])
	inspection["settled"][key] = "present" if good else "absent"
	inspection["calm"] = 8.0
	inspection["calm_room"] = String(c["room"])
	_duty_settle(c, false, good)
	san = maxf(0.0, san - (INSPECT["good_san"] if good else INSPECT["bad_san"]))
	_add_violation(-INSPECT["good_violation"] if good else INSPECT["bad_violation"], false)
	tt = clampf(tt + (INSPECT["assimilation"] if good else -INSPECT["assimilation"]), 0.0, 100.0)
	_say("我：黑影散开了。我一直坐在自己的座位上。" if good else "我：黑影散开了。它们记下了那个空着的座位。")
	_settle_san()
	if tt >= 100.0:
		_resolve_assimilation()
	if good and at_my_seat(world_id, w):
		grant_outing(true)



# ---- attendance duties (modules/patrol-world/attendance.js) ----

func _check_clock(d: int, slot: int) -> float:
	return (d - 1) * 1440.0 + float(INSPECT["times"][slot])


func duty_summary() -> String:
	var ids: Array = []
	for duty: Dictionary in duties["list"]:
		if duty["status"] == "pending" and not ids.has(duty["targetCheckId"]):
			ids.append(duty["targetCheckId"])
	ids.sort_custom(func(a: String, b: String) -> bool:
		var x := a.split(":")
		var y := b.split(":")
		return int(x[0]) < int(y[0]) or (int(x[0]) == int(y[0]) and int(x[1]) < int(y[1])))
	var parts: PackedStringArray = []
	for id: String in ids:
		var p := id.split(":")
		parts.append("第 %s 天 %s" % [p[0], SchoolClock.fmt_clock(float(INSPECT["times"][int(p[1])]))])
	return "、".join(parts)


## The next check that has not been seen (after `after` when given).
func _next_check(after: Variant = null) -> Dictionary:
	var now := game_clock()
	var d: int = int(after["day"]) if after != null else maxi(1, int(floor(now / 1440.0)) + 1)
	var slot := 0
	if after != null:
		slot = int(after["slot"]) + 1
		if slot > 1:
			d += 1
			slot = 0
	var guard := 0
	while ((after == null and _check_clock(d, slot) <= now) or inspection["seen"].has("%d:%d" % [d, slot])) and guard < 1000:
		guard += 1
		slot += 1
		if slot > 1:
			d += 1
			slot = 0
	return {"day": d, "slot": slot, "id": "%d:%d" % [d, slot]}


func _duty_prune() -> void:
	var pending: Array = []
	var done: Array = []
	for duty: Dictionary in duties["list"]:
		(pending if duty["status"] == "pending" else done).append(duty)
	duties["list"] = pending + done.slice(maxi(0, done.size() - 20))


func _duty_grant(source: String) -> void:
	var target := _next_check()
	for duty: Dictionary in duties["list"]:
		if duty["status"] == "pending" and duty["targetCheckId"] == target["id"]:
			return
	duties["seq"] = int(duties["seq"]) + 1
	duties["list"].append({"dutyId": "duty-%d" % duties["seq"], "source": source, "issuedAt": active_seconds, "targetCheckId": target["id"], "status": "pending"})
	_duty_prune()


func _duty_settle(c: Dictionary, excused: bool, compliant: bool) -> void:
	var key := "%d:%d" % [int(c["day"]), int(c["slot"])]
	var matching: Array = []
	for duty: Dictionary in duties["list"]:
		if duty["status"] == "pending" and duty["targetCheckId"] == key:
			matching.append(duty)
	if matching.is_empty() or duties["processed"].has(key):
		return
	var status := "excused" if excused else ("fulfilled" if compliant else "absent")
	duties["processed"][key] = status
	for duty: Dictionary in matching:
		duty["status"] = status
		duty["settledAt"] = active_seconds
	if not compliant and not excused:
		_events.append({"kind": "absence", "id": key})
	_duty_prune()


func _duty_cancel(c: Dictionary) -> void:
	var old := "%d:%d" % [int(c["day"]), int(c["slot"])]
	var next := _next_check(c)
	if _check_clock(next["day"], next["slot"]) <= game_clock():
		next = _next_check()
	for duty: Dictionary in duties["list"]:
		if duty["status"] == "pending" and duty["targetCheckId"] == old:
			duty["targetCheckId"] = next["id"]


## Events for other modules (an absence after a registered outing makes the patrol permanent).
func take_events() -> Array:
	var out := _events
	_events = []
	return out
