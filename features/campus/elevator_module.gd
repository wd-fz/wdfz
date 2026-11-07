class_name ElevatorModule
extends FeatureModule
## The two elevators (teach, lab), ported from the Web version's elevator.js (reference
## wd-fz.github.io@0bf508a). All waiting, door motion and travel use simulation seconds.
## A floor's cabin is part of that floor scene (behind the J cell); only when the doors close
## and the car leaves does the player move to the cabin scene (lift_teach / lift_lab), and on
## arrival back to the same spot behind the target floor's doors.
##
## Not ported yet (documented in docs/plan): unsafe() blockers (anomalies, local chase, pending
## inspection) are treated as false; the rare "wrong elevator" is held back until the void maze
## is ported (see VOID_MAZE_PORTED); the internal 1 % cabin event is a separate module.

const STATE_VERSION := 1
const CFG := {"wait": 3.0, "travel": 2.0, "per_floor": 0.7, "rare_chance": 0.08, "dream_san": 5, "open": 0.9, "close": 1.0, "hold": 4.0}
const GEO := {"landing": 0.40, "car": -0.47, "inner": -0.5, "back": -1.95, "half": 0.47, "cabin_half": 0.75, "outer": 0.80, "depth": 2.05}
const HOSTS := ["teach", "lab"]
const RIDE_ROOMS := ["lift_teach", "lift_lab", "lift_dream"]
const PRAD_M := CampusGeometry.PRAD * CampusGeometry.U2M
## The wrong elevator (8 %) leads into the void maze. The exported lift_dream scene IS the maze
## (the void-maze module replaced the old white room), whose rules are not ported yet; until they
## are, the roll is not made so that no run can get stuck in a cabin offering only 67 / 89.
const VOID_MAZE_PORTED := false

var _rooms: Dictionary = {}
var _frames: Dictionary = {}
var lifts: Dictionary = {}
var ride: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _notices: PackedStringArray = []
## Elevator.unsafe(): anomaly active, local patrol chase or a pending inspection. The app wires
## the ported parts in (inspection); anomalies and patrol join when they are ported.
var unsafe_check := Callable()


func _init(rooms: Dictionary = {}) -> void:
	_rooms = rooms


func module_id() -> StringName:
	return &"campus.elevator"


func state_version() -> int:
	return STATE_VERSION


func reset() -> void:
	lifts.clear()
	for host: String in HOSTS:
		lifts[host] = _fresh_lift()
	ride = {}
	_rng.randomize()


func set_seed(value: int) -> void:
	_rng.seed = value


func _fresh_lift() -> Dictionary:
	return {"floor": 1, "phase": "idle", "remaining": 0.0, "target": 1, "door": 0.0, "dir": 0, "hold": 0.0, "flash": 0.0, "nudged": false}


func capture() -> Dictionary:
	return {"lifts": lifts.duplicate(true), "ride": ride.duplicate(true), "rng_state": str(_rng.state), "rng_seed": str(_rng.seed)}


func validate(data: Dictionary) -> String:
	if not data.get("lifts") is Dictionary or not data.get("ride") is Dictionary:
		return "电梯状态无效"
	for host: String in HOSTS:
		var lift: Variant = data["lifts"].get(host)
		if not lift is Dictionary:
			return "电梯状态缺少 %s" % host
		if not SaveSchema.is_integer(lift.get("floor"), 1, 5) or not SaveSchema.is_integer(lift.get("target"), 1, 5):
			return "电梯楼层无效"
		if not String(lift.get("phase", "")) in ["idle", "waiting", "occupied"]:
			return "电梯阶段无效"
		if not SaveSchema.number_in(lift.get("door"), 0, 1) or not SaveSchema.number_in(lift.get("remaining"), 0, 1000):
			return "电梯门或计时无效"
	var r: Dictionary = data["ride"]
	if not r.is_empty():
		if not String(r.get("host", "")) in HOSTS or not String(r.get("phase", "")) in ["cabin", "moving", "dream"]:
			return "乘梯状态无效"
	if not String(data.get("rng_state", "")).is_valid_int():
		return "电梯随机状态无效"
	return ""


func restore(data: Dictionary) -> void:
	lifts = data["lifts"].duplicate(true)
	for host: String in HOSTS:
		for key: String in ["floor", "target", "dir"]:
			lifts[host][key] = int(lifts[host][key])
	ride = data["ride"].duplicate(true)
	for key: String in ["origin", "target"]:
		if ride.has(key) and typeof(ride[key]) == TYPE_FLOAT:
			ride[key] = int(ride[key])
	_rng.seed = int(String(data.get("rng_seed", "0")))
	_rng.state = int(String(data["rng_state"]))


## Elevator.cancel (story.js kill): the ride ends, the car returns to its origin floor.
func cancel() -> void:
	if not ride.is_empty() and ride.get("host") in HOSTS:
		var lift: Dictionary = lifts[ride["host"]]
		lift["floor"] = int(ride["origin"])
		lift["phase"] = "idle"
		lift["remaining"] = 0.0
	ride = {}


func take_notices() -> PackedStringArray:
	var out := _notices
	_notices = PackedStringArray()
	return out


func _say(text: String) -> void:
	_notices.append(text)


# ---- geometry (Elevator.frame / local / world) ----

func frame(room_id: String) -> Dictionary:
	if _frames.has(room_id):
		return _frames[room_id]
	var f := {}
	var r: Variant = _rooms.get(room_id)
	if r != null and (r["host"] == "lift" or (r["host"] in HOSTS and r.get("floor") != null and int(r["floor"]) >= 1 and int(r["floor"]) <= 5)):
		var grid: Array = r["grid"]
		for y in grid.size():
			var row := String(grid[y])
			for x in row.length():
				if row.substr(x, 1) != "J" or not f.is_empty():
					continue
				var d := _open_side(grid, x, y)
				if d == Vector2.ZERO:
					continue
				var out := -d if r["host"] == "lift" else d
				var c := CampusGeometry.tile_center(r, x, y)
				f = {"c": x, "r": y, "j": c, "out": out, "lat": Vector2(-out.y, out.x)}
	_frames[room_id] = f
	return f


static func _open_side(grid: Array, x: int, y: int) -> Vector2:
	for d: Vector2i in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var yy := y + d.y
		var xx := x + d.x
		if yy < 0 or yy >= grid.size() or xx < 0 or xx >= String(grid[yy]).length():
			continue
		if String(grid[yy]).substr(xx, 1) != "#":
			return Vector2(d)
	return Vector2.ZERO


## World units -> (a, b) metres: a towards the corridor, b along the door width.
func local(room_id: String, w: Vector2) -> Variant:
	var f := frame(room_id)
	if f.is_empty():
		return null
	var d := (w - (f["j"] as Vector2)) * CampusGeometry.U2M
	return Vector2(d.dot(f["out"]), d.dot(f["lat"]))


func world(room_id: String, a: float, b: float) -> Vector2:
	var f := frame(room_id)
	return (f["j"] as Vector2) + ((f["out"] as Vector2) * a + (f["lat"] as Vector2) * b) / CampusGeometry.U2M


func _turn(from: String, to: String, ang: float) -> float:
	var f: Vector2 = frame(from)["out"]
	var t: Vector2 = frame(to)["out"]
	return ang - atan2(f.y, f.x) + atan2(t.y, t.x)


func _host_floor(room_id: String) -> Array:
	var r: Variant = _rooms.get(room_id)
	if r == null or not r["host"] in HOSTS or r.get("floor") == null or int(r["floor"]) > 5:
		return []
	return [String(r["host"]), int(r["floor"])]


func in_cabin(room_id: String, w: Vector2) -> bool:
	var hf := _host_floor(room_id)
	if hf.is_empty():
		return false
	var p: Variant = local(room_id, w)
	return p != null and p.x < GEO["landing"] - 0.05 and p.x > -GEO["depth"] and absf(p.y) < GEO["outer"]


func _in_doorway(room_id: String, w: Vector2) -> bool:
	var p: Variant = local(room_id, w)
	if p == null:
		return false
	return p.x + PRAD_M > GEO["car"] - 0.05 and p.x - PRAD_M < GEO["landing"] + 0.04 and absf(p.y) < GEO["half"] + PRAD_M


func _approaching(room_id: String, w: Vector2) -> bool:
	var p: Variant = local(room_id, w)
	if p == null:
		return false
	return p.x - PRAD_M < GEO["landing"] + 0.15 and p.x > GEO["landing"] - 0.05 and absf(p.y) < 0.6


## Landing-door opening 0..1 (closed unless the car is at this floor and not travelling).
func door_amount(host: String, floor: int) -> float:
	if not host in HOSTS or not lifts.has(host):
		return 0.0
	var lift: Dictionary = lifts[host]
	return float(lift["door"]) if int(lift["floor"]) == floor and not lift["phase"] in ["waiting", "occupied"] else 0.0


func door_amount_in(room_id: String) -> float:
	var hf := _host_floor(room_id)
	return 0.0 if hf.is_empty() else door_amount(hf[0], hf[1])


## Closed-door rectangles (scene metres) of a floor's landing and car doors (Elevator.doorRects).
func door_rects(room_id: String) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var f := frame(room_id)
	var r: Variant = _rooms.get(room_id)
	if f.is_empty() or r == null or r["host"] == "lift":
		return out
	for s: Array in [[GEO["landing"] - 0.04, GEO["landing"] + 0.04], [GEO["car"] - 0.04, GEO["car"] + 0.04]]:
		var p := CampusGeometry.to_scene(r, world(room_id, s[0], -GEO["half"]))
		var q := CampusGeometry.to_scene(r, world(room_id, s[1], GEO["half"]))
		out.append(Rect2(p, Vector2.ZERO).expand(q))
	return out


## Where the cabin opens out of the floor grid (for the room boundary): scene centre and edge.
func cabin_gap(room_id: String) -> Dictionary:
	var f := frame(room_id)
	var r: Variant = _rooms.get(room_id)
	if f.is_empty() or r == null or r["host"] == "lift":
		return {}
	var back: Vector2 = -(f["out"] as Vector2)
	var edge := "s" if back.y > 0 else ("n" if back.y < 0 else ("e" if back.x > 0 else "w"))
	var edge_point := (f["j"] as Vector2) + back * (float(r["th"]) if back.y != 0 else float(r["tw"])) * 0.5
	return {"edge": edge, "center": CampusGeometry.to_scene(r, edge_point), "half": GEO["outer"], "normal": back}


# ---- rules ----

func _pose(room_id: String, w: Vector2, ang: float, pitch: float) -> Dictionary:
	var s := CampusGeometry.to_scene(_rooms[room_id], w)
	return {"position": [s.x, 0.05, s.y], "yaw": CampusGeometry.yaw_from_ang(ang), "pitch": pitch}


func _unsafe() -> bool:
	return unsafe_check.is_valid() and bool(unsafe_check.call())


func _open(host: String, why: String = "") -> bool:
	var lift: Dictionary = lifts[host]
	if why != "ride" and _unsafe():
		lift["flash"] = 0.6
		return false
	if float(lift["door"]) < 1.0:
		lift["dir"] = 1
	else:
		lift["hold"] = CFG["hold"]
	return true


func _close(host: String) -> void:
	var lift: Dictionary = lifts[host]
	if float(lift["door"]) > 0.0:
		lift["dir"] = -1
		lift["hold"] = 0.0


## Hall call button / cabin panel (Elevator.interact). Returns {"notice"} or {"choice"}.
func use_at(room_id: String, w: Vector2) -> Dictionary:
	if room_id == "lift_dream":
		return _leave_dream()
	if room_id in ["lift_teach", "lift_lab"]:
		return controls(room_id, w)
	var hf := _host_floor(room_id)
	if hf.is_empty():
		return {}
	var host: String = hf[0]
	var floor: int = hf[1]
	if in_cabin(room_id, w):
		return controls(room_id, w)
	var lift: Dictionary = lifts[host]
	if lift["phase"] == "waiting":
		return {"notice": "我：电梯还在路上。" if int(lift["target"]) == floor else "我：电梯正在回应别的楼层。"}
	if lift["phase"] == "occupied":
		return {"notice": "我：电梯正在运行。"}
	if int(lift["floor"]) != floor:
		lift["target"] = floor
		lift["remaining"] = CFG["wait"] + absi(int(lift["floor"]) - floor) * CFG["per_floor"]
		lift["phase"] = "waiting"
		return {"notice": "我：按下呼梯键。楼层指示灯缓慢亮了起来。"}
	if float(lift["door"]) >= 1.0 and int(lift["dir"]) >= 0:
		lift["hold"] = CFG["hold"]
		return {"notice": ""}
	if _open(host):
		return {"notice": "我：按下呼梯键。门开了。"}
	return {"notice": "〔电梯没有反应〕楼层灯闪了一下。"}


## Cabin panel: doors close first when open; choosing the current floor opens them.
func controls(room_id: String, w: Vector2) -> Dictionary:
	if ride.is_empty():
		ride = {"host": "lab" if room_id == "lift_lab" else "teach", "origin": 1, "target": 1, "phase": "dream" if room_id == "lift_dream" else "cabin", "rare": false, "remaining": 0.0, "pending": null}
	if ride["phase"] == "moving":
		return {"notice": "我：电梯还在运行。"}
	var host: String = ride["host"]
	if float(lifts[host]["door"]) > 0.0 and not room_id in RIDE_ROOMS and not _in_doorway(room_id, w):
		_close(host)
	var labels: Array = []
	var values: Array = []
	if ride.get("rare", false):
		for n: String in ["67", "89"]:
			labels.append(n + " 层")
			values.append(n)
	else:
		for f in range(1, 6):
			labels.append("%d 层%s" % [f, "（开门）" if f == int(ride["origin"]) else ""])
			values.append(f)
	return {"choice": {"text": "轿厢里的按钮亮着。", "labels": labels, "values": values}}


func press(target: Variant, room_id: String, pose: Dictionary) -> Dictionary:
	if ride.is_empty() or ride["phase"] != "cabin":
		return {}
	var host: String = ride["host"]
	if typeof(target) != TYPE_STRING and int(target) == int(ride["origin"]):
		_open(host, "ride")
		ride["pending"] = null
		return {}
	ride["pending"] = target
	if float(lifts[host]["door"]) <= 0.0:
		return _depart(room_id, pose)
	_close(host)
	return {}


## V / 关门 button while standing in the cabin.
func close_door(room_id: String, w: Vector2) -> bool:
	var hf := _host_floor(room_id)
	if hf.is_empty() or not in_cabin(room_id, w):
		return false
	_close(hf[0])
	return true


func _depart(room_id: String, pose: Dictionary) -> Dictionary:
	if ride.is_empty() or ride["phase"] != "cabin" or ride.get("pending") == null:
		return {}
	var target: Variant = ride["pending"]
	ride["pending"] = null
	if typeof(target) == TYPE_STRING:
		return _enter_dream(String(target))
	var host: String = ride["host"]
	var lift: Dictionary = lifts[host]
	var from := "%s%d" % [host, int(ride["origin"])]
	var car := "lift_" + host
	var p: Array = pose["position"]
	var here := CampusGeometry.to_world(_rooms[room_id], float(p[0]), float(p[2]))
	var l: Variant = local(from, here) if room_id == from else null
	if l == null:
		l = Vector2((GEO["inner"] + GEO["back"]) * 0.5, 0.0)
	var w := world(car, l.x, l.y)
	var ang := _turn(from, car, CampusGeometry.ang_from_yaw(float(pose["yaw"])))
	ride["target"] = int(target)
	ride["phase"] = "moving"
	ride["remaining"] = CFG["travel"] + absi(int(target) - int(ride["origin"])) * CFG["per_floor"]
	lift["phase"] = "occupied"
	lift["door"] = 0.0
	lift["dir"] = 0
	return {"travel": {"world": car, "pose": _pose(car, w, ang, float(pose["pitch"])), "seamless": true}, "notice": "我：门合上，电梯向目标楼层运行。"}


func _enter_dream(button: String) -> Dictionary:
	if ride.is_empty() or ride["phase"] != "cabin" or not ride.get("rare", false):
		return {}
	ride["button"] = button
	ride["phase"] = "dream"
	var lift: Dictionary = lifts[ride["host"]]
	lift["door"] = 0.0
	lift["dir"] = 0
	# VoidMaze.enter(button) takes over here once the void-maze module is ported (-5 SAN first).
	return {"travel": {"world": "lift_dream", "pose": _pose("lift_dream", CampusGeometry.tile_center(_rooms["lift_dream"], 2, 5), 0.0, 0.0), "seamless": false}, "san": -int(CFG["dream_san"])}


func _leave_dream() -> Dictionary:
	if ride.is_empty() or ride["phase"] != "dream":
		return {}
	var r := _arrive(int(ride["origin"]), {}, false)
	r["notice"] = "我：门合上了。外面的走廊和刚才一样。"
	return r


## Arrival: back behind the target floor's closed doors at the same spot, then the doors open.
func _arrive(floor: int, pose: Dictionary, quiet: bool) -> Dictionary:
	if ride.is_empty():
		return {}
	var host: String = ride["host"]
	var lift: Dictionary = lifts[host]
	var room_id := "%s%d" % [host, floor]
	var car := "lift_" + host
	var f := frame(room_id)
	if ride["phase"] == "dream":
		var q := world(room_id, 1.0, 0.0)
		lift.merge({"floor": floor, "target": floor, "phase": "idle", "remaining": 0.0, "door": 0.0, "dir": 0, "hold": 0.0}, true)
		ride = {}
		var out: Vector2 = f["out"]
		return {"travel": {"world": room_id, "pose": _pose(room_id, q, atan2(out.y, out.x), 0.0), "seamless": false}}
	var l: Variant = null
	var ang := atan2((f["out"] as Vector2).y, (f["out"] as Vector2).x)
	var pitch := 0.0
	if not pose.is_empty():
		var pp: Array = pose["position"]
		l = local(car, CampusGeometry.to_world(_rooms[car], float(pp[0]), float(pp[2])))
		ang = _turn(car, room_id, CampusGeometry.ang_from_yaw(float(pose["yaw"])))
		pitch = float(pose["pitch"])
	if l == null or l.x > GEO["inner"] or l.x < GEO["back"]:
		l = Vector2((GEO["inner"] + GEO["back"]) * 0.5, 0.0)
	l = Vector2(clampf(l.x, GEO["back"] + 0.34, GEO["inner"] - 0.34), clampf(l.y, -GEO["cabin_half"] + 0.34, GEO["cabin_half"] - 0.34))
	var w := world(room_id, l.x, l.y)
	lift.merge({"floor": floor, "target": floor, "phase": "idle", "remaining": 0.0, "door": 0.0, "dir": 1, "hold": 0.0}, true)
	ride.merge({"origin": floor, "target": floor, "phase": "cabin", "remaining": 0.0, "pending": null}, true)
	return {"travel": {"world": room_id, "pose": _pose(room_id, w, ang, pitch), "seamless": true}, "notice": "" if quiet else "我：叮。电梯门打开了。"}


## One simulation step (Elevator.tick + boarding). Returns a travel/notice result or {}.
func step(delta: float, room_id: String, pose: Dictionary) -> Dictionary:
	var result := {}
	var here_w := Vector2.INF
	var hf := _host_floor(room_id)
	if not hf.is_empty() and not pose.is_empty():
		var p: Array = pose["position"]
		here_w = CampusGeometry.to_world(_rooms[room_id], float(p[0]), float(p[2]))
	for host: String in HOSTS:
		var lift: Dictionary = lifts[host]
		if float(lift["flash"]) > 0.0:
			lift["flash"] = maxf(0.0, float(lift["flash"]) - delta)
		if lift["phase"] == "waiting":
			lift["remaining"] = maxf(0.0, float(lift["remaining"]) - delta)
			if float(lift["remaining"]) == 0.0:
				lift.merge({"floor": lift["target"], "phase": "idle", "door": 0.0, "dir": 0}, true)
				if not hf.is_empty() and hf[0] == host and hf[1] == int(lift["floor"]):
					_say("我：叮。电梯到了。")
					_open(host)
			continue
		if lift["phase"] == "occupied":
			continue
		var here: bool = not hf.is_empty() and hf[0] == host and hf[1] == int(lift["floor"])
		var blocked := here and _in_doorway(room_id, here_w)
		var near := here and _approaching(room_id, here_w)
		if not near:
			lift["nudged"] = false
		if int(lift["dir"]) > 0:
			lift["door"] = minf(1.0, float(lift["door"]) + delta / CFG["open"])
			if float(lift["door"]) >= 1.0:
				lift["dir"] = 0
				lift["hold"] = CFG["hold"]
		elif int(lift["dir"]) < 0:
			if blocked or (near and not lift["nudged"]):
				lift["dir"] = 1
				if not blocked:
					lift["nudged"] = true
			else:
				lift["door"] = maxf(0.0, float(lift["door"]) - delta / CFG["close"])
				if float(lift["door"]) <= 0.0:
					lift["dir"] = 0
					if not ride.is_empty() and ride["host"] == host and ride["phase"] == "cabin" and ride.get("pending") != null and here_w != Vector2.INF and in_cabin(room_id, here_w):
						result = _depart(room_id, pose)
		elif float(lift["door"]) >= 1.0:
			if blocked:
				lift["hold"] = maxf(float(lift["hold"]), 1.0)
			else:
				lift["hold"] = maxf(0.0, float(lift["hold"]) - delta)
				if float(lift["hold"]) <= 0.0:
					lift["dir"] = -1
	# Departure already moved the player (old depart calls doEnterRoom) – skip boarding checks.
	if not result.is_empty():
		return result
	# Stepping in / out of a floor's cabin.
	if not hf.is_empty() and here_w != Vector2.INF:
		var inside := in_cabin(room_id, here_w)
		if inside and (ride.is_empty() or ride["phase"] != "cabin" or ride["host"] != hf[0]):
			_enter_cabin(hf[0], hf[1])
		elif not inside and not ride.is_empty() and ride["phase"] == "cabin" and ride["host"] == hf[0]:
			var l: Variant = local(room_id, here_w)
			if l != null and l.x > GEO["landing"] + 0.05:
				ride = {}
	if not ride.is_empty() and ride["phase"] == "moving" and room_id in ["lift_teach", "lift_lab"]:
		ride["remaining"] = maxf(0.0, float(ride["remaining"]) - delta)
		if float(ride["remaining"]) == 0.0:
			return _arrive(int(ride["target"]), pose, false)
	return {}


## Stepping over the landing door: the wrong-elevator roll happens here and is saved (no reroll on load).
func _enter_cabin(host: String, floor: int) -> void:
	if not ride.is_empty() and ride["host"] == host and ride["phase"] == "cabin":
		ride["origin"] = floor
		return
	ride = {"host": host, "origin": floor, "target": floor, "phase": "cabin", "rare": VOID_MAZE_PORTED and _rng.randf() < CFG["rare_chance"], "remaining": 0.0, "pending": null}


func show_close_button(room_id: String, pose: Dictionary) -> bool:
	if ride.is_empty() or ride["phase"] != "cabin" or pose.is_empty() or _host_floor(room_id).is_empty():
		return false
	var p: Array = pose["position"]
	return in_cabin(room_id, CampusGeometry.to_world(_rooms[room_id], float(p[0]), float(p[2])))
