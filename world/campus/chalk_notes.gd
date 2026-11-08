class_name ChalkNotes
extends Node3D
## Chalk writing that appears by itself (fx/classroom.js, reference wd-fz.github.io@0bf508a):
##  · the forecast (anwSpawn): when an anomaly is about to come the clock time of it is written in chalk on the
##    wall in front of you (the board if it is the classroom's front wall), or on the floor two metres ahead if
##    there is no wall within six tiles. It is the hint the "dream" difficulty gives: "I have dreamt this time".
##  · the truancy writing (skipSpawn): while you are in a wrong place with violation 12 or more, short
##    handwritten warnings (不要逃课 …) appear around you on the floor and walls, faster the more violation
##    (every 5.6 − 0.048·v seconds, at least 1 s, at most 28 at a time); they are cleared below 8.
## The old build draws the forecast digits in seven segments; here the text is a Label3D in chalk white.

const SKIP_TEXT := ["不要逃课", "回去上课", "这节是数学", "老师在等你", "点名了", "你又迟到了", "回去"]
const MAX_SKIP := 28

var _forecast: Label3D
var _forecast_key := ""
var _forecast_age := 0.0
var _skips: Array[Label3D] = []
var _skip_t := 0.0
var _skip_room := ""
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	name = "ChalkNotes"
	_rng.seed = 5150


## The first wall within six tiles straight ahead (anwSpot): {kind: "wall", c, r, nx, nz, d} or {kind: "floor"}.
## fwd is the facing in world axes (x, y).
static func spot(room: Dictionary, w: Vector2, fwd: Vector2) -> Dictionary:
	if room.is_empty():
		return {"kind": "floor"}
	var nx := 0
	var nz := 0
	if absf(fwd.x) >= absf(fwd.y):
		nx = 1 if fwd.x >= 0.0 else -1
	else:
		nz = 1 if fwd.y >= 0.0 else -1
	var sx := floori((w.x - float(room["ox"])) / float(room["tw"]))
	var sy := floori((w.y - float(room["oy"])) / float(room["th"]))
	for d in range(1, 7):
		var cx := sx + nx * d
		var cy := sy + nz * d
		if cx < 0 or cy < 0 or cx >= int(room["cols"]) or cy >= int(room["rows"]):
			return {"kind": "floor"}
		if String((room["grid"] as Array)[cy]).substr(cx, 1) == "#":
			return {"kind": "wall", "c": cx, "r": cy, "nx": nx, "nz": nz, "d": d}
	return {"kind": "floor"}


static func skip_interval(viol: float) -> float:
	return maxf(1.0, 5.6 - viol * 0.048)


## Whether the truancy writing should be around at this violation (12 to start, below 8 it is wiped).
static func skip_active(wrong: bool, viol: float, was_on: bool) -> bool:
	if not wrong or viol < 12.0:
		return was_on and viol >= 8.0 and wrong
	return true


func _chalk(text: String, size: int, alpha: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.003
	l.modulate = Color(0.914, 0.933, 0.902, alpha)
	l.double_sided = true
	l.shaded = false
	l.outline_size = 0
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return l


## The forecast: text (clock) at a place; on = false removes it. room is the room dict ({} outdoors).
func update_forecast(on: bool, text: String, room: Dictionary, w: Vector2, fwd: Vector2, scene_pos: Vector3, delta: float) -> bool:
	var key := "%s|%s" % [text, String(room.get("id", "out"))]
	if not on:
		clear_forecast()
		return false
	if _forecast == null or key != _forecast_key:
		clear_forecast()
		_forecast_key = key
		_forecast_age = 0.0
		_forecast = _chalk(text, 110, 0.0)
		add_child(_forecast)
		var sp := spot(room, w, fwd)
		if String(sp["kind"]) == "wall":
			var nnx := -int(sp["nx"])
			var nnz := -int(sp["nz"])
			var wx := float(room["ox"]) + (int(sp["c"]) + 0.5) * float(room["tw"]) + nnx * float(room["tw"]) * 0.5
			var wy := float(room["oy"]) + (int(sp["r"]) + 0.5) * float(room["th"]) + nnz * float(room["th"]) * 0.5
			var s := CampusGeometry.to_scene(room, Vector2(wx, wy))
			var board := String(room.get("host", "")) == "teach" and int(sp["nx"]) == -1
			var deep := 0.095 if board else 0.035
			_forecast.position = Vector3(s.x + nnx * deep, 1.55 if board else 1.42, s.y + nnz * deep)
			_forecast.rotation.y = atan2(float(nnx), float(nnz))
		else:
			var snap := roundf(atan2(fwd.y, fwd.x) / (PI / 2.0)) * (PI / 2.0)
			var f := Vector2(cos(snap), sin(snap))
			_forecast.position = Vector3(scene_pos.x + f.x * 2.0, 0.014, scene_pos.z + f.y * 2.0)
			_forecast.basis = Basis(Vector3.UP, atan2(-f.x, -f.y)) * Basis(Vector3.RIGHT, -PI / 2.0)
	_forecast_age += delta
	var a := clampf(_forecast_age / 1.5, 0.0, 0.94)
	_forecast.modulate.a = a
	return true


func clear_forecast() -> void:
	if _forecast != null and is_instance_valid(_forecast):
		_forecast.queue_free()
	_forecast = null
	_forecast_key = ""


func has_forecast() -> bool:
	return _forecast != null and is_instance_valid(_forecast)


func forecast_text() -> String:
	return _forecast.text if has_forecast() else ""


## The truancy writing. active: wrong place and violation high enough; room is {} outdoors.
func update_skip(delta: float, active: bool, viol: float, room: Dictionary, scene_pos: Vector3) -> void:
	if not active:
		clear_skips()
		return
	var rid := String(room.get("id", "out"))
	if rid != _skip_room:
		clear_skips()
		_skip_room = rid
	for l in _skips:
		l.modulate.a = minf(0.92, l.modulate.a + delta * 1.6)
	_skip_t -= delta
	if _skip_t > 0.0:
		return
	_skip_t = skip_interval(viol)
	var l := _chalk(String(SKIP_TEXT[_rng.randi() % SKIP_TEXT.size()]), 70 + _rng.randi() % 20, 0.0)
	var ang := _rng.randf() * TAU
	var rad := 1.4 + _rng.randf() * 3.3
	var placed := false
	if not room.is_empty() and _rng.randf() < 0.45:
		# The first wall tile along that direction, within the radius.
		var w := CampusGeometry.to_world(room, scene_pos.x, scene_pos.z)
		var dir := Vector2(cos(ang), sin(ang))
		var steps := int(rad * 4.0)
		for i in range(1, steps + 1):
			var q := w + dir * (float(i) * rad / float(maxi(1, steps)))
			var c := floori((q.x - float(room["ox"])) / float(room["tw"]))
			var r := floori((q.y - float(room["oy"])) / float(room["th"]))
			if c < 0 or r < 0 or c >= int(room["cols"]) or r >= int(room["rows"]):
				break
			if String((room["grid"] as Array)[r]).substr(c, 1) == "#":
				var back := q - dir * float(room["tw"]) * 0.5
				var s := CampusGeometry.to_scene(room, back)
				var face := -dir
				var horizontal := absf(face.x) >= absf(face.y)
				var n := Vector2(signf(face.x), 0.0) if horizontal else Vector2(0.0, signf(face.y))
				l.position = Vector3(s.x + n.x * 0.04, 1.15 + _rng.randf() * 0.5, s.y + n.y * 0.04)
				l.rotation.y = atan2(n.x, n.y)
				placed = true
				break
	if not placed:
		l.position = Vector3(scene_pos.x + cos(ang) * rad, 0.016 + _rng.randf() * 0.004, scene_pos.z + sin(ang) * rad)
		l.basis = Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, -PI / 2.0)
	add_child(l)
	_skips.append(l)
	while _skips.size() > MAX_SKIP:
		var old: Label3D = _skips.pop_front()
		old.queue_free()


func clear_skips() -> void:
	for l in _skips:
		if is_instance_valid(l):
			l.queue_free()
	_skips.clear()
	_skip_t = 0.0
	_skip_room = ""


func skip_count() -> int:
	return _skips.size()
