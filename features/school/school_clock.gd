class_name SchoolClock
extends RefCounted
## Calendar rules of the Web version (reference wd-fz.github.io@0bf508a): core.js SCHED, DAY_PHASES,
## periodAt, needWhere, rateAt, clockBoundary, fmtClock, and domain/game-time.js GameTimeRules.
## Game time `tsec` is minutes of the day; one natural day is 1200 simulation seconds.

const LIGHTS_OUT := 1340.0
const EVENING := 1090.0
const DAY_START := 440.0
const DAY_END := 1500.0
const DAY_PHASES := [[440.0, 770.0, 360.0], [770.0, 1070.0, 360.0], [1070.0, 1340.0, 360.0], [1340.0, 1500.0, 120.0]]
## Internal slow window of the first phase (core.js); its ten seconds are part of the 1200 s day.
const SLOW_T0 := 705.0
const SLOW_T1 := 705.0 + 20.0 / 60.0
const SLOW_RATE := 2.0
const SCHED := [
	[440, 480, "早读", "教室"], [480, 525, "第 1 节", "教室"], [525, 540, "课间", "自由"],
	[540, 585, "第 2 节", "教室"], [585, 620, "课间操", "操场"], [620, 665, "第 3 节", "教室"],
	[665, 690, "课间", "自由"], [690, 735, "第 4 节", "教室"], [735, 800, "午饭", "自由"],
	[800, 840, "午休", "自由"], [840, 885, "第 5 节", "教室"], [885, 890, "课间", "自由"],
	[890, 935, "第 6 节", "教室"], [935, 945, "课间", "自由"], [945, 990, "第 7 节", "教室"],
	[990, 995, "课间", "自由"], [995, 1040, "第 8 节", "教室"], [1040, 1060, "课外活动", "自由"],
	[1060, 1090, "晚饭", "自由"], [1090, 1180, "晚自习一", "教室"], [1180, 1200, "课间", "自由"],
	[1200, 1320, "晚自习二", "教室"], [1320, 1340, "洗漱", "自由"], [1340, 1500, "熄灯后", "自由"],
]


static func fmt_clock(tsec: float) -> String:
	var t := fposmod(tsec, 1440.0)
	return "%02d:%02d" % [int(floor(t / 60.0)), int(floor(fmod(t, 60.0)))]


static func period_at(t: float) -> Array:
	for s: Array in SCHED:
		if t >= s[0] and t < s[1]:
			return s
	return SCHED[SCHED.size() - 1]


static func need_where(t: float) -> String:
	var p := period_at(t)
	if p[3] == "教室":
		return "教室"
	if p[3] == "操场":
		return "操场"
	if t >= LIGHTS_OUT:
		return "宿舍"
	return "自由"


static func evening_activity(t: float) -> bool:
	return t >= 1040.0 and t < 1090.0


static func is_night(t: float) -> bool:
	return t >= LIGHTS_OUT or t < DAY_START


static func day_phase_at(t: float) -> Array:
	for p: Array in DAY_PHASES:
		if t >= p[0] and t < p[1]:
			return p
	return DAY_PHASES[3]


## Game minutes per real minute (core.js rateAt).
static func rate_at(t: float) -> float:
	if t >= SLOW_T0 and t < SLOW_T1:
		return SLOW_RATE
	var p := day_phase_at(t)
	var slow := SLOW_T1 - SLOW_T0 if p == DAY_PHASES[0] else 0.0
	return (float(p[1]) - float(p[0]) - slow) * 60.0 / (float(p[2]) - slow * 60.0 / SLOW_RATE)


static func clock_boundary(t: float) -> float:
	var end := minf(float(period_at(t)[1]), float(day_phase_at(t)[1]))
	if t < SLOW_T0:
		end = minf(end, SLOW_T0)
	elif t < SLOW_T1:
		end = minf(end, SLOW_T1)
	return end


## GameTimeRules.continuous: continuous game minutes (day changes at 22:30).
static func continuous(day: int, t: float) -> float:
	day = maxi(1, day)
	return (day - 1 - (1 if t >= LIGHTS_OUT + 10.0 and day > 1 else 0)) * 1440.0 + t


## GameTimeRules.forwardSlice.
static func forward_slice(t: float, day: int, remaining: float) -> Dictionary:
	var used := minf(remaining, maxf(0.0, DAY_END - t))
	var to := t + used
	var next_day := day
	if (t < LIGHTS_OUT + 10.0 and to >= LIGHTS_OUT + 10.0) or (day == 1 and t >= LIGHTS_OUT + 10.0):
		next_day = maxi(day, 1) + 1
	return {"from": t, "to": to, "used": used, "remaining": remaining - used, "day": next_day, "time": DAY_START if to >= DAY_END - 1e-9 else to}


## GameTimeRules.realTimeSlice.
static func real_time_slice(t: float, seconds: float, boundary: float, rate: float) -> Dictionary:
	var until := maxf(0.0, (boundary - t) * 60.0 / rate)
	var used := minf(seconds, until)
	var minutes := 1e-8 if until < 1e-9 else (boundary - t if used == until else used * rate / 60.0)
	return {"seconds": used, "minutes": minutes, "nudge": until < 1e-9}


## GameTimeRules.pressure over CampusPressure.curve.
static func pressure(points: Array, clock: float) -> Dictionary:
	var a: Dictionary = points[0]
	var b := a
	var stage := 1 if clock > float(a["clock"]) else 0
	for i in range(1, points.size()):
		b = points[i]
		if clock < float(b["clock"]):
			break
		a = b
		stage = i + 1
	var t := 0.0 if a == b else clampf((clock - float(a["clock"])) / (float(b["clock"]) - float(a["clock"])), 0.0, 1.0)
	var value := {"clock": clock, "stage": stage}
	for key: String in ["anomaly", "danger", "passive", "rest"]:
		value[key] = float(a[key]) + (float(b[key]) - float(a[key])) * t
	return value


## core.js realSecondsBetween within one natural day.
static func real_seconds_between(from: float, to: float) -> float:
	var seconds := 0.0
	var t := from
	while t < to - 1e-9:
		var end := minf(to, clock_boundary(t))
		if end <= t:
			break
		seconds += (end - t) * 60.0 / rate_at(t)
		t = end
	return seconds


## core.js clockTimeBefore: the game time `seconds` of simulation before `time`.
static func clock_time_before(time: float, seconds: float) -> float:
	var lo := DAY_START
	var hi := time
	for _i in 48:
		var mid := (lo + hi) * 0.5
		if real_seconds_between(mid, time) > seconds:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5
