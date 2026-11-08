class_name RunLog
extends RefCounted
## The replay log (modules/run-record/run-log.js, reference wd-fz.github.io@0bf508a): every 0.5 s of active
## play the position is looked at and a point is kept only when the player moved, turned or changed scene
## (encoded by RunTrack); events (anomalies, patrol, inspection, choices, achievements, endings…) are kept
## with where they happened, and every 10 s the day and the clock. The patroller's position is kept once a
## second while it is in the same building (not shown in play; only in the replay and the footprint map).
## The one in progress is written to a side file every ~10 s, matched to the run id of the save: on a
## load it carries on if the ids match, else starts again from that moment marked "partial". A clear hands
## it to the record; a death or a new run drops it.

const MAX_EVENTS := 600
const MAX_PAT := 7200

var run := ""
var scenes: Array = []
var samples: Array = []
var pat: Array = []          # [t, scene index, x/2, y/2]
var clock: Array = []        # [t, day, tsec]
var events: Array = []       # [t, kind, text, pts, scene index, x/2, y/2]
var start := 0
var partial := 0

var _acc := 0.0
var _save_acc := 0.0
var _clock_acc := 0.0
var _pat_acc := 0.0
var _last: Array = []
var _rooms: Dictionary = {}
var _fresh_seen := 0
var now_s := 0.0             # active play seconds, set by the app before each tick
var scene := ""              # the scene id now ("out" for outdoors)
var pos := Vector2.ZERO      # world position
var ang := 0.0
var day := 1
var tsec := 0.0


func _init(rooms: Dictionary = {}) -> void:
	_rooms = rooms


func begin(run_id: String) -> void:
	run = run_id
	scenes = []
	samples = []
	pat = []
	clock = []
	events = []
	start = int(Time.get_unix_time_from_system() * 1000.0)
	partial = 0
	_acc = 0.0
	_save_acc = 0.0
	_clock_acc = 0.0
	_pat_acc = 0.0
	_last = []
	_fresh_seen = 0


func discard() -> void:
	run = ""
	scenes = []
	samples = []
	pat = []
	clock = []
	events = []
	_last = []


func _scene_idx(id: String) -> int:
	var i := scenes.find(id)
	if i < 0:
		scenes.append(id)
		i = scenes.size() - 1
	return i


func _t() -> int:
	return roundi(now_s * 10.0)


func point(force: bool) -> void:
	var sc := _scene_idx(scene)
	var x := roundi(pos.x / 2.0)
	var y := roundi(pos.y / 2.0)
	var a := ((roundi(ang / TAU * 64.0) % 64) + 64) % 64
	if not force and not _last.is_empty() and _last[1] == sc and absi(int(_last[2]) - x) < 2 and absi(int(_last[3]) - y) < 2 \
			and mini(absi(int(_last[4]) - a), 64 - absi(int(_last[4]) - a)) < 2:
		return
	_last = [_t(), sc, x, y, a]
	samples.append(_last)


func event(kind: String, text: String, pts: int = 0) -> void:
	if run.is_empty():
		return
	if events.size() >= MAX_EVENTS:
		var i := -1
		for k in events.size():
			if events[k][1] == "room":
				i = k
				break
		events.remove_at(maxi(i, 0))
	events.append([_t(), kind, text, pts, _scene_idx(scene), roundi(pos.x / 2.0), roundi(pos.y / 2.0)])


func _building(id: String) -> String:
	if id == "" or id == "out":
		return "out"
	var r: Dictionary = _rooms.get(id, {})
	return String(r.get("host", id)) if not r.is_empty() else id


## The patroller walking in the same building: pat = {room, x, y} (world), walking.
func pat_point(room: String, x: float, y: float) -> void:
	if room.is_empty() or _building(room) != _building(scene):
		return
	var r: Dictionary = _rooms.get(room, {})
	if not r.is_empty() and bool(r.get("flags", {}).get("noMap", false)):
		return
	if pat.size() >= MAX_PAT:
		pat.pop_front()
	pat.append([_t(), _scene_idx(room), roundi(x / 2.0), roundi(y / 2.0)])


## Real seconds of active play. fresh_ach: names of achievements unlocked this run (new ones get an event).
func tick(dt: float, patrol_state: Dictionary, fresh_ach: Array) -> bool:
	if run.is_empty():
		return false
	_acc += dt
	_save_acc += dt
	_clock_acc += dt
	_pat_acc += dt
	if _acc >= 0.5:
		_acc = 0.0
		point(false)
	if _pat_acc >= 1.0:
		_pat_acc = 0.0
		if bool(patrol_state.get("walk", false)):
			pat_point(String(patrol_state.get("room", "")), float(patrol_state.get("x", 0.0)), float(patrol_state.get("y", 0.0)))
	if _clock_acc >= 10.0:
		_clock_acc = 0.0
		clock.append([_t(), day, roundi(tsec)])
	while _fresh_seen < fresh_ach.size():
		event("achieve", "成就「%s」" % String(fresh_ach[_fresh_seen]), 0)
		_fresh_seen += 1
	if _save_acc >= 10.0:
		_save_acc = 0.0
		return true      # time to persist
	return false


func pack() -> Dictionary:
	return {"v": 1, "run": run, "scenes": scenes.duplicate(), "track": RunTrack.encode(samples), "pat": pat.duplicate(true), "clock": clock.duplicate(true),
		"events": events.duplicate(true), "start": start, "partial": partial}


## A clear: the last point, and the pack to hand to the record.
func finish() -> Dictionary:
	point(true)
	return pack()


## Carry on from the side file when its run id matches, else start again from now, marked partial.
func restore(run_id: String, data: Variant) -> void:
	discard()
	if data is Dictionary and int(data.get("v", 0)) == 1 and String(data.get("run", "")) == run_id and not run_id.is_empty():
		run = run_id
		scenes = (data.get("scenes", []) as Array).duplicate()
		samples = RunTrack.decode(String(data.get("track", "")))
		pat = (data.get("pat", []) as Array).duplicate(true)
		clock = (data.get("clock", []) as Array).duplicate(true)
		events = (data.get("events", []) as Array).duplicate(true)
		start = int(data.get("start", 0))
		partial = 1 if bool(data.get("partial", false)) else 0
		_last = samples[samples.size() - 1] if not samples.is_empty() else []
		return
	run = run_id if not run_id.is_empty() else "l%d" % int(Time.get_unix_time_from_system())
	partial = 1
	start = int(Time.get_unix_time_from_system() * 1000.0)
