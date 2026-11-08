class_name Playtest
extends RefCounted
## The optional local playtest log (playtest.js, reference wd-fz.github.io@0bf508a): independent of saves,
## never sent anywhere, no player identity. Seconds by mode (play / menu / background / death), frame
## intervals in four bins (only while playing), up to 500 events with the state at that moment, and the
## observer's notes. Written to user://playtest.json when stopped or exported.

const MAX_EVENTS := 500
const MODES := ["play", "menu", "background", "death"]

var path: String
var data: Dictionary = {}
var recording := false
var mode := "menu"
var _frame_bins := [0, 0, 0, 0]
var _elapsed := 0.0


func _init(file: String = "user://playtest.json") -> void:
	path = file


func start(settings: Dictionary, viewport: Vector2i) -> void:
	recording = true
	_elapsed = 0.0
	_frame_bins = [0, 0, 0, 0]
	data = {"version": 1, "startedAt": Time.get_datetime_string_from_system(true), "environment": "由执行者补录真实设备；引擎信息不证明是真机",
		"settings": settings.duplicate(true), "viewport": {"width": viewport.x, "height": viewport.y},
		"seconds": {"play": 0.0, "menu": 0.0, "background": 0.0, "death": 0.0}, "events": [], "discardedEvents": 0}
	event("开始记录")


func stop() -> void:
	if recording:
		recording = false
		save()


## Called every frame with the real delta and the mode now.
func frame(dt: float, now_mode: String) -> void:
	mode = now_mode
	if not recording or dt <= 0.0:
		return
	_elapsed += dt
	data["seconds"][mode] = float(data["seconds"][mode]) + dt
	if mode == "play":
		_frame_bins[0 if dt < 0.025 else (1 if dt < 0.05 else (2 if dt < 0.1 else 3))] += 1


## state: day, tsec, room, san, bag … whatever the app has at the moment.
func event(type: String, detail: String = "", state: Dictionary = {}) -> void:
	if not recording:
		return
	var ev := {"type": type, "detail": detail, "elapsedSeconds": _elapsed}
	ev.merge(state, true)
	var list: Array = data["events"]
	if list.size() >= MAX_EVENTS:
		list.pop_front()
		data["discardedEvents"] = int(data["discardedEvents"]) + 1
	list.append(ev)


func note(text: String, state: Dictionary = {}) -> bool:
	var t := text.strip_edges()
	if not recording or t.is_empty():
		return false
	event("观察者记录", t.substr(0, 500), state)
	return true


func export() -> Dictionary:
	if data.is_empty():
		return {}
	var out := data.duplicate(true)
	out["recording"] = recording
	out["elapsedSeconds"] = _elapsed
	out["frameIntervals"] = {"under25ms": _frame_bins[0], "from25to50ms": _frame_bins[1], "from50to100ms": _frame_bins[2], "over100ms": _frame_bins[3]}
	out["evidence"] = "本地事件与帧间隔记录；不自动推断理解度、真机性能、听感或试玩结论"
	return out


func save() -> bool:
	if data.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(export(), "  "))
	f.close()
	return true
