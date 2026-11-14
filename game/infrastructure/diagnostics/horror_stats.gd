class_name HorrorStats
extends RefCounted
## Fear pacing measured during an opt-in playtest (2026-11-14 horror plan, items 1 and 8;
## docs/plan/中式与西式恐怖及吓人手法.md). Part of the local playtest log (playtest.gd): never sent anywhere,
## only while the observer records. It reads the state the app already has and changes nothing.
## · Encounters: when an anomaly, a chase, an inspection or a blackout starts; the gaps between starts.
## · Overlaps (item 1): seconds and episodes where two forced threats run at once (a lethal anomaly, a chase,
##   an inspection, a blackout), by combination.
## · Behaviour (item 8): look-backs (a turn of more than 120° within 0.6 s), hides and how long, chases and how
##   many were escaped, deaths by cause (a repeat of the same cause is counted), skips and pauses.
## The recreational-fear research behind it: enjoyment follows an inverted U; read flat stretches (long gaps,
## no look-backs) and grinding ones (overlaps, repeated deaths in one place) from these numbers.

const KINDS := ["anomaly", "chase", "inspection", "blackout"]
const LOOK_TURN := deg_to_rad(120.0)
const LOOK_WINDOW := 0.6

var seconds := 0.0
var starts: Dictionary = {}       # kind → count
var gaps: Array = []              # seconds between consecutive encounter starts (any kind)
var overlap_seconds: Dictionary = {}  # "a+b" → seconds
var overlap_episodes: Dictionary = {} # "a+b" → count
var look_backs := 0
var hides := 0
var hide_seconds := 0.0
var hide_longest := 0.0
var chases := 0
var chase_escapes := 0
var deaths: Dictionary = {}       # cause → count
var repeat_deaths := 0
var skips := 0
var pauses := 0

var _on: Dictionary = {}
var _last_start := -1.0
var _combo := ""
var _yaws: Array = []             # [t, yaw]
var _hide_t := -1.0
var _last_death := ""


## state: anomaly (bool, any anomaly on), lethal (bool, the one on can kill), chase, inspection, blackout,
## hiding (bool), yaw (radians), dead (bool).
func tick(dt: float, state: Dictionary) -> void:
	if not (dt > 0.0):
		return
	seconds += dt
	var now := {"anomaly": bool(state.get("anomaly", false)), "chase": bool(state.get("chase", false)),
		"inspection": bool(state.get("inspection", false)), "blackout": bool(state.get("blackout", false))}
	for kind: String in KINDS:
		if now[kind] and not bool(_on.get(kind, false)):
			starts[kind] = int(starts.get(kind, 0)) + 1
			if _last_start >= 0.0:
				gaps.append(snappedf(seconds - _last_start, 0.1))
				if gaps.size() > 200:
					gaps.pop_front()
			_last_start = seconds
			if kind == "chase":
				chases += 1
		if kind == "chase" and not now[kind] and bool(_on.get(kind, false)) and not bool(state.get("dead", false)):
			chase_escapes += 1
	_on = now
	# Forced threats at once: a lethal anomaly (a harmless one is not forced), a chase, an inspection, a blackout.
	var forced: PackedStringArray = []
	if now["anomaly"] and bool(state.get("lethal", false)):
		forced.append("anomaly")
	for kind: String in ["chase", "inspection", "blackout"]:
		if now[kind]:
			forced.append(kind)
	var combo := "+".join(forced) if forced.size() >= 2 else ""
	if combo != "":
		overlap_seconds[combo] = float(overlap_seconds.get(combo, 0.0)) + dt
		if combo != _combo:
			overlap_episodes[combo] = int(overlap_episodes.get(combo, 0)) + 1
	_combo = combo
	_look(float(state.get("yaw", 0.0)))
	var hiding := bool(state.get("hiding", false))
	if hiding and _hide_t < 0.0:
		_hide_t = seconds
		hides += 1
	elif not hiding and _hide_t >= 0.0:
		_end_hide()


func _look(yaw: float) -> void:
	_yaws.append([seconds, yaw])
	while _yaws.size() > 1 and seconds - float(_yaws[0][0]) > LOOK_WINDOW:
		_yaws.pop_front()
	if _yaws.size() >= 2 and absf(wrapf(yaw - float(_yaws[0][1]), -PI, PI)) >= LOOK_TURN:
		look_backs += 1
		_yaws = [[seconds, yaw]]


func _end_hide() -> void:
	var d := seconds - _hide_t
	hide_seconds += d
	hide_longest = maxf(hide_longest, d)
	_hide_t = -1.0


func death(cause: String) -> void:
	deaths[cause] = int(deaths.get(cause, 0)) + 1
	if cause == _last_death:
		repeat_deaths += 1
	_last_death = cause
	_on = {}
	_combo = ""
	if _hide_t >= 0.0:
		_end_hide()


func skip() -> void:
	skips += 1


func pause() -> void:
	pauses += 1


func report() -> Dictionary:
	var sorted := gaps.duplicate()
	sorted.sort()
	var mean := 0.0
	for g: float in gaps:
		mean += g
	mean = mean / gaps.size() if not gaps.is_empty() else 0.0
	return {"seconds": snappedf(seconds, 0.1), "starts": starts.duplicate(),
		"gap": {"count": gaps.size(), "min": sorted[0] if not sorted.is_empty() else 0.0, "median": sorted[sorted.size() / 2] if not sorted.is_empty() else 0.0, "mean": snappedf(mean, 0.1), "max": sorted[sorted.size() - 1] if not sorted.is_empty() else 0.0},
		"overlap": {"seconds": _rounded(overlap_seconds), "episodes": overlap_episodes.duplicate()},
		"lookBacks": look_backs, "lookBacksPerMinute": snappedf(look_backs / maxf(seconds / 60.0, 1.0 / 60.0), 0.01),
		"hide": {"count": hides, "seconds": snappedf(hide_seconds, 0.1), "longest": snappedf(hide_longest, 0.1)},
		"chase": {"count": chases, "escaped": chase_escapes},
		"deaths": deaths.duplicate(), "repeatDeaths": repeat_deaths, "skips": skips, "pauses": pauses}


func _rounded(d: Dictionary) -> Dictionary:
	var out := {}
	for k: String in d:
		out[k] = snappedf(float(d[k]), 0.1)
	return out
