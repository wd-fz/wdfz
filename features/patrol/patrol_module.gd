class_name PatrolModule
extends FeatureModule
## The school's single resident patroller, ported from modules/patrol-world/world.js, patrol.js
## (locker hiding) and attendance.js (reference wd-fz.github.io@0bf508a). Authority lives here:
## position, behaviour, locking, searching, transitions between scenes, region reports, the
## lift-door rush and the catch. Scenes only draw it.
##
## Context in, events out: the app calls `set_context()` with the player's state before `tick()` and
## hiding calls, then drains `take_events()` (kill / violation / remove_item / notice / toast).
## Not ported yet (marked where they plug in): the phone network wireless signal source
## (`reveal_wireless` is ready), the void maze gateway, talents (hearing range), the car chase,
## the knife / camouflage hooks, the broadcast region (`zone_active`).

const STATE_VERSION := 1
const ROUTE_VERSION := 3
const TRAVEL_CD := 8.0
const TRAVEL_MIN := 240.0
const TRAVEL_MAX := 480.0
const TRAVEL_CLEAR := 260.0
const SEE := 135.0
const CATCH := 19.0
const LIFT_RUSH_MIN := 2.2
const LIFT_REACH := 7.0
const BEHAVIORS := ["patrol", "investigate", "chase", "search", "return", "transit"]
const U2M := CampusGeometry.U2M

var nav: PatrolNav
var elevator: ElevatorModule
var zones: Array = []
var route_nodes: Array = []
## Region reports that depend on another module (the broadcast room): inactive until it is ported.
var zone_active := func(_zone: Dictionary) -> bool: return false

var pat: Dictionary = {}
var hide: Dictionary = {}
var events: Array = []
## Presentation outputs (VisualState.patrolFlick / patrolRed).
var flick := 0.0
var red := 0.0

var _rooms: Dictionary = {}
var _c: Dictionary = {}
var _frame_path: Dictionary = {}
var _approach_cache: Dictionary = {}
var _halt := false


func _init(navigation: PatrolNav = null, rooms: Dictionary = {}, data: Dictionary = {}) -> void:
	nav = navigation
	_rooms = rooms
	zones = data.get("zones", [])
	route_nodes = data.get("route", {}).get("nodes", [])


func module_id() -> StringName:
	return &"patrol.world"


func state_version() -> int:
	return STATE_VERSION


# ---- state ----

static func fresh_pat() -> Dictionary:
	return {"version": 1, "state": "walk", "room": "admin1", "x": 0.0, "y": 0.0, "fy": 0.0, "behavior": "patrol",
		"permanent": false, "routeVersion": ROUTE_VERSION, "routeIndex": 1, "rejoin": false, "cycle": 0, "lockerMemory": {},
		"memoryVisit": null, "transition": null, "lock": 0.0, "locked": false, "cited": false, "lost": 0.0, "lastSeen": null,
		"search": 0.0, "queue": [], "investigation": null, "wirelessSignal": null, "regionSeq": 0, "lastRegion": null,
		"respawn": 0.0, "safety": 3.6, "warning": 0.0, "near": false, "blinkCD": TRAVEL_CD, "afterBlink": 0.22, "step": 0.0,
		"stuck": 0, "diagnostic": null, "doorRush": null, "absence": ""}


func reset() -> void:
	pat = fresh_pat()
	hide = {"on": false, "c": 0, "r": 0, "seen": false, "t": 0.0, "near": false}
	events = []
	flick = 0.0
	red = 0.0
	_frame_path = {}
	_approach_cache = {}
	_halt = false
	_c = {}
	if nav != null and nav.nodes.has("admin1:stairs"):
		_put(nav.nodes["admin1:stairs"])


func capture() -> Dictionary:
	return {"pat": pat.duplicate(true), "hide": hide.duplicate(true)}


func validate(data: Dictionary) -> String:
	var p: Variant = data.get("pat")
	var h: Variant = data.get("hide")
	if not p is Dictionary or not h is Dictionary:
		return "巡察状态无效"
	for key: String in ["x", "y", "fy", "lock", "lost", "search", "respawn", "safety", "warning", "blinkCD", "afterBlink", "step"]:
		if not SaveSchema.number_in(p.get(key), -1e7, 1e7):
			return "巡察数值无效：%s" % key
	if not String(p.get("state", "")) in ["walk", "idle"] or not String(p.get("room", "")) is String:
		return "巡察状态无效"
	if not SaveSchema.is_integer(p.get("routeIndex"), 0, 100000) or not SaveSchema.is_integer(p.get("cycle"), 0, 1000000000):
		return "巡察路线无效"
	for key: String in ["permanent", "locked", "cited", "rejoin", "near"]:
		if not p.get(key) is bool:
			return "巡察标志无效：%s" % key
	if not h.get("on") is bool or not SaveSchema.is_integer(h.get("c"), 0, 1000) or not SaveSchema.is_integer(h.get("r"), 0, 1000):
		return "躲藏状态无效"
	return ""


func restore(data: Dictionary) -> void:
	var saved: Dictionary = data["pat"]
	var base := fresh_pat()
	if int(saved.get("version", 0)) != 1 or int(saved.get("routeVersion", 0)) != ROUTE_VERSION:
		reset()
		pat["permanent"] = bool(saved.get("permanent", false))
		return
	pat = base
	for key: String in base:
		if saved.has(key):
			pat[key] = saved[key]
	for key: String in ["routeIndex", "cycle", "regionSeq", "stuck"]:
		pat[key] = int(pat[key])
	pat["lock"] = clampf(float(pat["lock"]), 0.0, 1.0)
	pat["respawn"] = clampf(float(pat["respawn"]), 0.0, 30.0)
	pat["safety"] = clampf(float(pat["safety"]), 0.0, 3.6)
	pat["warning"] = clampf(float(pat["warning"]), 0.0, 3.6)
	if not String(pat["behavior"]) in BEHAVIORS:
		pat["behavior"] = "patrol"
	pat["routeIndex"] = clampi(int(pat["routeIndex"]), 0, maxi(0, route_nodes.size() - 1))
	if not _navigable(String(pat["room"])):
		_put(nav.nodes["admin1:stairs"])
		pat["transition"] = null
		pat["safety"] = 3.6
	var h: Dictionary = data["hide"]
	hide = {"on": bool(h["on"]), "c": int(h["c"]), "r": int(h["r"]), "seen": bool(h.get("seen", false)), "t": 0.0, "near": bool(h.get("near", false))}
	_frame_path = {}
	_approach_cache = {}
	_halt = false
	flick = 0.0
	red = 0.0


func _navigable(scene: String) -> bool:
	return nav != null and (nav.is_stairwell(scene) or not nav.grid(scene).is_empty())


func set_context(ctx: Dictionary) -> void:
	_c = ctx


func take_events() -> Array:
	var out := events
	events = []
	return out


func _emit(kind: String, payload: Dictionary = {}) -> void:
	var e := payload.duplicate()
	e["kind"] = kind
	events.append(e)


# ---- helpers ----

func position() -> Dictionary:
	return PatrolNav.point(String(pat["room"]), float(pat["x"]), float(pat["y"]), float(pat["fy"]))


func _put(p: Dictionary) -> void:
	pat["room"] = String(p["scene"])
	pat["x"] = float(p["x"])
	pat["y"] = float(p["y"])
	pat["fy"] = float(p.get("fy", 0.0))


func spawn() -> Dictionary:
	return nav.nodes["admin1:stairs"]


func _player_scene() -> String:
	return String(_c.get("scene", ""))


func player_point() -> Dictionary:
	return PatrolNav.point(_player_scene(), float(_c.get("x", 0.0)), float(_c.get("y", 0.0)), float(_c.get("fy", 0.0)))


func same() -> bool:
	return not bool(_c.get("car_chase", false)) and pat["room"] == _player_scene() and pat["transition"] == null \
		and absf(float(pat["fy"]) - float(_c.get("fy", 0.0))) < 1.3


func distance() -> float:
	return Vector2(float(_c.get("x", 0.0)) - float(pat["x"]), float(_c.get("y", 0.0)) - float(pat["y"])).length() if same() else INF


## Talent.modifier('hear.range') (the ear talent), set by the app.
var hear_mul := 1.0


func _hear_range() -> float:
	return hear_mul


func hear_distance() -> float:
	return 200.0 * _hear_range()


func _locker_front(scene: String, c: int, r: int) -> Vector2:
	var room: Dictionary = _rooms[scene]
	return Vector2(float(room["ox"]) + (c + 0.5) * float(room["tw"]), float(room["oy"]) + (r + 1.5) * float(room["th"]))


func _tile_point(scene: String, c: float, r: float) -> Dictionary:
	var room: Dictionary = _rooms[scene]
	return PatrolNav.point(scene, float(room["ox"]) + (c + 0.5) * float(room["tw"]), float(room["oy"]) + (r + 0.5) * float(room["th"]))


func _zone_by_id(id: Variant) -> Dictionary:
	for z: Dictionary in zones:
		if z["id"] == id:
			return z
	return {}


func approach() -> Dictionary:
	if bool(_c.get("car_chase", false)):
		return {}
	var a := player_point()
	var tr: Variant = pat["transition"]
	var b: Dictionary = tr["to"] if tr != null else position()
	var key := "%s:%d:%d:%d:%s:%d:%d:%d:%d:%f" % [a["scene"], roundi(float(a["x"]) / 4.0), roundi(float(a["y"]) / 4.0), roundi(float(a["fy"]) * 10.0),
		b["scene"], roundi(float(b["x"]) / 4.0), roundi(float(b["y"]) / 4.0), roundi(float(b.get("fy", 0.0)) * 10.0), int(ceil(float(tr["remaining"]) * 2.0)) if tr != null else 0, _hear_range()]
	if _approach_cache.get("key") == key:
		return _approach_cache["value"]
	var m := nav.approach(a, b, 220.0 * _hear_range())
	if not m.is_empty() and tr != null:
		m["distance"] = float(m["distance"]) + float(tr["remaining"]) * nav.speed
	_approach_cache = {"key": key, "value": m}
	return m


## Regions with door-access reporting (PATROL_ZONES); the cell bounds exclude the right/lower edge.
func region() -> Variant:
	var room: Variant = _rooms.get(_player_scene())
	if room == null:
		return null
	var c := (float(_c.get("x", 0.0)) - float(room["ox"])) / float(room["tw"])
	var r := (float(_c.get("y", 0.0)) - float(room["oy"])) / float(room["th"])
	for z: Dictionary in zones:
		if z["scene"] == _player_scene() and c >= float(z["c0"]) and c < float(z["c1"]) and r >= float(z["r0"]) and r < float(z["r1"]):
			if not z.has("when") or bool(zone_active.call(z)):
				return z["id"]
	return null


func eligible() -> bool:
	if bool(_c.get("dead", false)) or not bool(_c.get("playing", true)):
		return false
	if bool(_c.get("night", false)):
		return _player_scene() == "out"
	if region() != null:
		return true
	var room: Variant = _rooms.get(_player_scene())
	return room != null and room["host"] in ["teach", "admin", "lab"] and room.get("floor") != null and int(room["floor"]) >= 1 and int(room["floor"]) <= 5 and String(_c.get("need_where", "")) == "教室"


func exempt() -> bool:
	return (bool(_c.get("seated", false)) and bool(_c.get("at_seat", false))) or bool(_c.get("on_leave", false)) \
		or (bool(_c.get("excused", false)) and not bool(_c.get("night", false)) and region() == null)


## patrolCamouflage hook: the dismissal crowd hides the player entirely.
var camouflage: Callable


func camouflaged() -> bool:
	return camouflage.is_valid() and bool(camouflage.call())


func hunting() -> bool:
	return not camouflaged() and (bool(pat["permanent"]) or pat["wirelessSignal"] != null or (eligible() and not exempt()))


func sees() -> bool:
	return not camouflaged() and pat["state"] == "walk" and same() and not bool(hide["on"]) and distance() <= SEE and nav.los(position(), player_point())


func local_quiet() -> bool:
	var calm_here: bool = float(_c.get("calm", 0.0)) > 0.0 and String(_c.get("calm_room", "")) == pat["room"]
	var checking_here: bool = String(_c.get("inspection_room", "")) == pat["room"]
	return same() and distance() < 190.0 and (checking_here or calm_here)


func locker_target() -> Dictionary:
	var signal_data: Variant = pat["wirelessSignal"]
	var l: Variant = signal_data["locker"] if signal_data != null else null
	var known: bool = l != null and l["scene"] == _player_scene() and int(l["c"]) == int(hide["c"]) and int(l["r"]) == int(hide["r"])
	if not same() or not bool(hide["on"]) or not (bool(pat["permanent"]) or bool(hide["seen"]) or known):
		return {}
	var f := _locker_front(_player_scene(), int(hide["c"]), int(hide["r"]))
	return PatrolNav.point(_player_scene(), f.x, f.y, float(_c.get("fy", 0.0)))


func threat() -> bool:
	if camouflaged():
		return false
	if pat["state"] != "walk" or not same() or float(pat["safety"]) > 0.0 or local_quiet() or distance() > SEE:
		return false
	var cabinet := locker_target()
	if not cabinet.is_empty():
		return nav.los(position(), cabinet) and (bool(pat["locked"]) or bool(pat["permanent"]))
	return not bool(hide["on"]) and (bool(pat["locked"]) or bool(pat["permanent"])) and nav.los(position(), player_point())


func hide_threat() -> bool:
	if not bool(hide["on"]) or not same() or not hunting() or float(pat["safety"]) > 0.0 or local_quiet() or pat["state"] != "walk" or distance() > SEE:
		return false
	var f := _locker_front(_player_scene(), int(hide["c"]), int(hide["r"]))
	return nav.los(position(), PatrolNav.point(_player_scene(), f.x, f.y, float(_c.get("fy", 0.0))))


func local_chase() -> bool:
	return threat() and bool(pat["locked"])


func local_threat() -> bool:
	return threat() or hide_threat()


## SAN pressure the patroller adds for the fear system (not used by the ported rules yet).
func pressure() -> float:
	return 0.35 if threat() else (0.18 if hide_threat() else 0.0)


func _grip(msg: String) -> void:
	_emit("kill", {"msg": msg, "fx": "grip", "source": "patrol"})
	_halt = true


func _clear_chase() -> void:
	var active: bool = bool(pat["locked"]) or pat["lastSeen"] != null or float(pat["search"]) > 0.0 or bool(pat["cited"])
	pat["doorRush"] = null
	pat["cited"] = false
	pat["lock"] = 0.0
	pat["locked"] = false
	pat["lost"] = 0.0
	pat["lastSeen"] = null
	pat["search"] = 0.0
	if active:
		pat["rejoin"] = true
		pat["behavior"] = "investigate" if pat["investigation"] != null else "return"
		_frame_path = {}


func clear_chase() -> void:
	_clear_chase()


## story.js survivalReset -> PatrolWorld.rescued: it loses interest and gives the player 3.6 s.
func rescued() -> void:
	hide["seen"] = false
	pat["permanent"] = false
	pat["wirelessSignal"] = null
	_clear_chase()
	pat["rejoin"] = true
	pat["safety"] = 3.6
	red = 0.0


## An outing the player registered and then did not honour (attendance.js settle): permanent chase.
func registered_absence(id: String) -> void:
	pat["permanent"] = true
	pat["absence"] = id
	pat["behavior"] = "chase"
	_frame_path = {}
	_emit("toast", {"text": "外出登记后未归：持续追踪已生效，重新登记和假条不能解除。"})


func _banish() -> void:
	pat["doorRush"] = null
	pat["state"] = "idle"
	pat["respawn"] = 30.0
	pat["rejoin"] = true
	pat["locked"] = false
	pat["lock"] = 0.0
	pat["lost"] = 0.0
	pat["lastSeen"] = null
	pat["search"] = 0.0
	pat["cited"] = false
	hide["seen"] = false
	pat["transition"] = null
	pat["warning"] = 0.0
	pat["near"] = false
	_frame_path = {}
	flick = 0.0
	red = 0.0
	_emit("notice", {"text": "我：符纸烧成了灰。高个子的身影随之散开。"})


func _enqueue(id: String) -> void:
	for e: Dictionary in pat["queue"]:
		if e["regionId"] == id:
			return
	var inv: Variant = pat["investigation"]
	if inv != null and inv["regionId"] == id:
		return
	pat["regionSeq"] = int(pat["regionSeq"]) + 1
	pat["queue"].append({"regionId": id, "sequence": pat["regionSeq"], "enteredAt": float(_c.get("active_seconds", 0.0))})
	var zone := _zone_by_id(id)
	if not zone.is_empty() and zone.get("marked", false):
		_emit("toast", {"text": "区域门禁已上报：%s。巡察者将前往调查。" % zone["label"]})


func _observation(id: String) -> Dictionary:
	var z := _zone_by_id(id)
	if z.is_empty():
		return {}
	return nav.snap(String(z["scene"]), _tile_point(String(z["scene"]), float(z["observe"][0]), float(z["observe"][1])))


func _landing(host: String, floor: int) -> Dictionary:
	var id := "%s%d" % [host, floor]
	return _tile_point(id, 20.0 if host == "teach" else 10.0, 20.0 if host == "teach" else 18.0)


func _permanent_target() -> Dictionary:
	var scene := _player_scene()
	if scene in ["lift_teach", "lift_lab"] and elevator != null and not elevator.ride.is_empty():
		var ride: Dictionary = elevator.ride
		var floor := int(ride["target"]) if ride["phase"] == "moving" else int(ride["origin"])
		var landing := _landing(String(ride["host"]), floor)
		return PatrolNav.point("%s%d" % [ride["host"], floor], landing["x"], landing["y"])
	var cabinet := locker_target()
	return cabinet if not cabinet.is_empty() else player_point()


## The phone network exposes a static position for three seconds (not wired until the phone exists).
func reveal_wireless() -> void:
	var p := _permanent_target()
	var locker: Variant = null
	if bool(hide["on"]):
		var f := _locker_front(_player_scene(), int(hide["c"]), int(hide["r"]))
		p = PatrolNav.point(_player_scene(), f.x, f.y, float(_c.get("fy", 0.0)))
		locker = {"scene": _player_scene(), "c": hide["c"], "r": hide["r"]}
	pat["wirelessSignal"] = {"point": p.duplicate(), "remaining": 3.0, "locker": locker}
	_frame_path = {}


## Where the patroller wants to go now, by priority (world.js target).
func _target() -> Dictionary:
	if pat["permanent"] and not camouflaged():
		pat["behavior"] = "chase"
		return _permanent_target()
	if pat["locked"] or float(pat["search"]) > 0.0:
		pat["behavior"] = "chase" if pat["locked"] else "search"
		return pat["lastSeen"] if pat["lastSeen"] != null else {}
	var sig: Variant = pat["wirelessSignal"]
	if sig != null:
		var p: Dictionary = sig["point"]
		pat["behavior"] = "investigate"
		if p["scene"] == "bell1" or p["scene"] == "lift_dream" or nav.is_stairwell(String(p["scene"])):
			return p
		var snapped := nav.snap(String(p["scene"]), p)
		return snapped if not snapped.is_empty() else p
	if pat["investigation"] == null and not (pat["queue"] as Array).is_empty():
		var first: Dictionary = pat["queue"].pop_front()
		first["remaining"] = 6.0
		pat["investigation"] = first
	if pat["investigation"] != null:
		pat["behavior"] = "investigate"
		return _observation(pat["investigation"]["regionId"])
	var mem: Variant = pat["lockerMemory"].get(pat["room"])
	if pat["memoryVisit"] == null and mem != null and int(mem["cycle"]) != int(pat["cycle"]):
		pat["memoryVisit"] = {"scene": pat["room"], "c": mem["c"], "r": mem["r"], "remaining": 4.0}
		mem["cycle"] = pat["cycle"]
	if pat["memoryVisit"] != null:
		var m: Dictionary = pat["memoryVisit"]
		var f := _locker_front(String(m["scene"]), int(m["c"]), int(m["r"]))
		pat["behavior"] = "investigate"
		return PatrolNav.point(String(m["scene"]), f.x, f.y)
	if pat["rejoin"]:
		var nearest := nav.nearest_route(position(), route_nodes)
		if not nearest.is_empty():
			pat["routeIndex"] = route_nodes.find(nearest)
			pat["rejoin"] = false
			pat["behavior"] = "return"
			_frame_path = {}
		else:
			pat["behavior"] = "return"
	if pat["behavior"] == "return":
		return nav.nodes[route_nodes[int(pat["routeIndex"])]]
	pat["behavior"] = "patrol"
	return nav.nodes[route_nodes[int(pat["routeIndex"]) % route_nodes.size()]]


func _patrol_route(a: Dictionary, b: Dictionary) -> Dictionary:
	var prev: String = route_nodes[maxi(0, int(pat["routeIndex"]) - 1)]
	var next: String = route_nodes[int(pat["routeIndex"])]
	var from: Dictionary = nav.nodes[prev]
	var edge := {}
	for e: Dictionary in nav.edges:
		if (e["a"] == prev and e["b"] == next) or (e["b"] == prev and e["a"] == next):
			edge = e
			break
	if edge.is_empty():
		return {}
	if from["scene"] == b["scene"]:
		return {"points": nav.path(a, b)} if a["scene"] == b["scene"] else nav.route(a, from)
	if a["scene"] != from["scene"]:
		return nav.route(a, from)
	if Vector2(float(a["x"]) - float(from["x"]), float(a["y"]) - float(from["y"])).length() > 3.0:
		return {"points": nav.path(a, from)}
	return {"transition": {"from": a.duplicate(), "to": b.duplicate(), "kind": edge["kind"], "remaining": float(edge["weight"]), "total": float(edge["weight"])}}


func _prepare_path(goal: Dictionary) -> bool:
	var a := position()
	var key := "%s:%d:%d:%d" % [goal["scene"], roundi(float(goal["x"]) / 3.0), roundi(float(goal["y"]) / 3.0), roundi(float(goal.get("fy", 0.0)) * 10.0)]
	if _frame_path.get("key") == key and not (_frame_path.get("points", []) as Array).is_empty():
		return true
	var route_result := _patrol_route(a, goal) if pat["behavior"] == "patrol" else nav.route(a, goal)
	var pts: Variant = route_result.get("points") if not route_result.is_empty() else null
	if pts != null and (pts as Array).is_empty():
		pts = null
	var tr: Variant = route_result.get("transition") if not route_result.is_empty() else null
	if route_result.is_empty() or (pts == null and tr == null):
		pat["stuck"] = int(pat["stuck"]) + 1
		if int(pat["stuck"]) % 4 == 1:
			pat["diagnostic"] = "暂不可达，重规划：%s → %s" % [a["scene"], goal["scene"]]
		_frame_path = {}
		return false
	if tr != null and tr["kind"] == "stair-portal":
		_put(tr["to"])
		_frame_path = {}
		return false
	if tr != null:
		pat["transition"] = tr
		pat["behavior"] = "transit"
		_frame_path = {}
		return false
	var points: Array = (pts as Array).duplicate()
	if points.size() > 1 and nav.segment(a, points[1]):
		points.pop_front()
	_frame_path = {"key": key, "points": points}
	return true


## Outdoor long jumps on a normal patrol only, never within 260 units of the player's reachable path.
func _travel_blink() -> bool:
	if float(pat["blinkCD"]) > 0.0 or pat["room"] != "out" or pat["behavior"] != "patrol" or pat["locked"] or pat["permanent"] \
			or float(pat["search"]) > 0.0 or pat["wirelessSignal"] != null or pat["investigation"] != null or pat["memoryVisit"] != null or _frame_path.is_empty():
		return false
	var player := player_point()
	var clear := func(p: Dictionary) -> bool:
		return not (player["scene"] == p["scene"] and Vector2(float(player["x"]) - float(p["x"]), float(player["y"]) - float(p["y"])).length() <= TRAVEL_CLEAR) \
			and nav.approach(player, p, TRAVEL_CLEAR).is_empty()
	if not clear.call(position()):
		return false
	var points: Array = _frame_path["points"]
	var p := position()
	var cost := 0.0
	var count := 0
	var destination := {}
	for i in points.size():
		var q: Dictionary = points[i]
		if q["scene"] != "out":
			break
		cost += Vector2(float(q["x"]) - float(p["x"]), float(q["y"]) - float(p["y"])).length()
		if cost > TRAVEL_MAX:
			break
		p = q
		if cost >= TRAVEL_MIN and clear.call(q):
			count = i + 1
			destination = q
	if destination.is_empty():
		return false
	_put(destination)
	for _i in count:
		points.pop_front()
	pat["blinkCD"] = TRAVEL_CD
	pat["afterBlink"] = 0.22
	return true


func _dist3(a: Dictionary, b: Dictionary) -> float:
	return Vector3(float(a["x"]) - float(b["x"]), float(a["y"]) - float(b["y"]), (float(a.get("fy", 0.0)) - float(b.get("fy", 0.0))) / U2M).length()


func _navigate(goal: Dictionary, budget: float) -> bool:
	var a := position()
	if goal.is_empty():
		return false
	if a["scene"] == goal["scene"] and _dist3(a, goal) < 6.0:
		return true
	if not _prepare_path(goal):
		return false
	if _travel_blink():
		budget = 0.0
	while budget > 1e-8 and not _frame_path.is_empty() and not (_frame_path["points"] as Array).is_empty():
		var points: Array = _frame_path["points"]
		var next: Dictionary = points[0]
		var p := position()
		var door := nav.door_at(next)
		if door.is_empty():
			door = nav.door_at(p)
		var d := _dist3(p, next)
		if d <= budget:
			_put(next)
			points.pop_front()
			budget -= d
		else:
			var t := budget / d
			_put(PatrolNav.point(String(p["scene"]), float(p["x"]) + (float(next["x"]) - float(p["x"])) * t, float(p["y"]) + (float(next["y"]) - float(p["y"])) * t,
				float(p.get("fy", 0.0)) + (float(next.get("fy", 0.0)) - float(p.get("fy", 0.0))) * t))
			budget = 0.0
	pat["stuck"] = 0
	pat["diagnostic"] = null
	return pat["room"] == goal["scene"] and _dist3(position(), goal) < 6.0


# ---- elevator door rush (calls out of the lift) ----

func _lift_front(room_id: String) -> Dictionary:
	var w := elevator.world(room_id, 0.75, 0.0)
	return PatrolNav.point(room_id, w.x, w.y)


## The doors finished closing with the patroller rushing: it is shut out and searches at the door.
func elevator_closed(host: String, floor: int) -> bool:
	var rush: Variant = pat["doorRush"]
	var room_id := "%s%d" % [host, floor]
	if rush == null or rush["host"] != host or int(rush["floor"]) != floor or pat["room"] != rush["scene"] or pat["state"] != "walk" or pat["transition"] != null \
			or not hunting() or float(pat["safety"]) > 0.0 or local_quiet():
		return false
	if elevator.door_amount(host, floor) > 0.0:
		return false
	var fp := _lift_front(room_id)
	pat["doorRush"] = null
	pat["locked"] = false
	pat["lock"] = 0.0
	pat["search"] = 3.0
	pat["lastSeen"] = fp
	_frame_path = {}
	_emit("notice", {"text": "〔门外〕脚步停在了门口。", "keep": true})
	return true


func _lift_door() -> bool:
	var scene := _player_scene()
	var room: Variant = _rooms.get(scene)
	var rush: Variant = pat["doorRush"]
	var cabin: bool = room != null and room["host"] != "lift" and elevator != null and not elevator.frame(scene).is_empty() \
		and elevator.in_cabin(scene, Vector2(float(_c.get("x", 0.0)), float(_c.get("y", 0.0))))
	var open: float = elevator.door_amount(String(room["host"]), int(room["floor"])) if cabin else 0.0
	var fp: Dictionary = _lift_front(scene) if cabin else {}
	var at_door: bool = cabin and pat["room"] == scene and pat["transition"] == null \
		and Vector2(float(pat["x"]) - float(fp["x"]), float(pat["y"]) - float(fp["y"])).length() < LIFT_REACH
	if rush != null:
		if not cabin or scene != rush["scene"] or not same() or not hunting() or pat["state"] != "walk" or float(pat["safety"]) > 0.0:
			pat["doorRush"] = null
			return false
		if open <= 0.0:
			elevator_closed(String(room["host"]), int(room["floor"]))
			return false
		pat["locked"] = true
		pat["lost"] = 0.0
		pat["lastSeen"] = fp
		if at_door and float(pat["warning"]) <= 0.0 and float(pat["afterBlink"]) <= 0.0:
			_emit("kill", {"msg": "它比门快。", "fx": "liftdoor", "source": "liftdoor"})
			_halt = true
			return true
		return false
	if not cabin or open <= 0.0 or pat["state"] != "walk" or pat["transition"] != null or not same() or not hunting() or float(pat["safety"]) > 0.0 or local_quiet():
		return false
	if pat["locked"] and at_door and float(pat["warning"]) <= 0.0 and float(pat["afterBlink"]) <= 0.0:
		_grip("一只手按住了你的头顶。它在点名。")
		return true
	# "Watching you board": it is locked on and just saw you, or the sight line passes the doorway.
	var watching: bool = pat["locked"] and float(pat["lost"]) < 1.0
	if not watching:
		var me_w := Vector2(float(_c.get("x", 0.0)), float(_c.get("y", 0.0)))
		var loc: Variant = elevator.local(scene, Vector2(float(pat["x"]), float(pat["y"])))
		var me: Variant = elevator.local(scene, me_w)
		if loc == null or me == null or loc.x < 0.6 or me_w.distance_to(Vector2(float(pat["x"]), float(pat["y"]))) > SEE:
			return false
		var through := true
		for a0: float in [ElevatorModule.GEO["landing"], ElevatorModule.GEO["car"]]:
			if me.x >= a0:
				continue
			var t: float = (a0 - loc.x) / (me.x - loc.x)
			if absf(loc.y + t * (me.y - loc.y)) >= float(ElevatorModule.GEO["half"]) - 0.05:
				through = false
		if not through or not nav.los(position(), fp):
			return false
	var pts := nav.path(position(), fp)
	var dist: float = nav.length(pts) if not pts.is_empty() else Vector2(float(pat["x"]) - float(fp["x"]), float(pat["y"]) - float(fp["y"])).length()
	var eta := maxf(0.0, dist - LIFT_REACH) / nav.chase
	if not pat["locked"]:
		if bool(_c.get("has_seal", false)):
			_emit("remove_item", {"id": "seal"})
			_banish()
			return false
		pat["locked"] = true
		pat["lock"] = 1.0
		pat["behavior"] = "chase"
		if not pat["permanent"] and not pat["cited"]:
			pat["cited"] = true
			_emit("violation", {"amount": 8.0})
	pat["lost"] = 0.0
	pat["lastSeen"] = fp
	_frame_path = {}
	if eta >= LIFT_RUSH_MIN:
		pat["doorRush"] = {"host": room["host"], "floor": room["floor"], "scene": scene, "x": fp["x"], "y": fp["y"], "eta": eta}
		pat["warning"] = maxf(float(pat["warning"]), minf(3.6, eta))
		pat["near"] = true
		_emit("notice", {"text": "〔门外 · 正在靠近〕脚步加快。", "keep": true})
	return false


# ---- hiding in lockers (patrol.js) ----

## Pose of the body inside the locker cell (old world units) and what the patroller makes of it.
func hide_in(c: int, r: int) -> Dictionary:
	var room: Dictionary = _rooms[_player_scene()]
	hide["seen"] = pat["state"] == "walk" and sees() and hunting()
	if hide["seen"]:
		observe_locker(c, r)
	hide["on"] = true
	hide["c"] = c
	hide["r"] = r
	hide["t"] = 0.0
	hide["near"] = false
	_emit("notice", {"text": "我：我钻进了柜子。……它看见了。脚步声没有停，正朝这边来。" if hide["seen"] else "我：我钻进储物柜，把门带上。铁皮上一排缝，外面的光一条一条的。"})
	return {"x": float(room["ox"]) + (c + 0.5) * float(room["tw"]), "y": float(room["oy"]) + (r + 0.62) * float(room["th"]), "ang": PI * 0.5}


func hide_out() -> Dictionary:
	var ok: bool = bool(hide["on"]) and bool(hide["near"]) and not bool(hide["seen"]) and not bool(pat["locked"])
	var room: Variant = _rooms.get(_player_scene())
	hide["on"] = false
	hide["near"] = false
	_emit("notice", {"text": "我：我推开柜门出来。"})
	if room == null:
		return {"dodged": ok}
	var f := _locker_front(_player_scene(), int(hide["c"]), int(hide["r"]))
	return {"x": f.x, "y": f.y, "dodged": ok}


## It saw the player enter: it remembers the locker for its next visit to this scene.
func observe_locker(c: int, r: int) -> void:
	var f := _locker_front(_player_scene(), c, r)
	pat["lastSeen"] = PatrolNav.point(_player_scene(), f.x, f.y, float(_c.get("fy", 0.0)))
	pat["lockerMemory"][_player_scene()] = {"c": c, "r": r, "cycle": -1}
	_frame_path = {}


## Leaving a scene while locked on and seen: only the far end of the exit becomes known.
func left_scene(from: String, to: String) -> void:
	if pat["locked"] and not pat["permanent"] and sees() and from != to and pat["room"] == from:
		var p := nav.observed_exit(from, to, player_point())
		if not p.is_empty():
			pat["lastSeen"] = p
	_frame_path = {}


# ---- the simulation step (world.js step) ----

func _step(dt: float) -> void:
	var new_region: Variant = region()
	if new_region != pat["lastRegion"]:
		pat["lastRegion"] = new_region
		if new_region != null:
			_enqueue(String(new_region))
	pat["safety"] = maxf(0.0, float(pat["safety"]) - dt)
	pat["afterBlink"] = maxf(0.0, float(pat["afterBlink"]) - dt)
	if pat["state"] == "idle":
		pat["respawn"] = maxf(0.0, float(pat["respawn"]) - dt)
		if float(pat["respawn"]) <= 1e-7:
			_put(spawn())
			pat["state"] = "walk"
			pat["behavior"] = "return"
			pat["afterBlink"] = 0.22
			pat["blinkCD"] = TRAVEL_CD
			pat["near"] = false
		return
	var approaching := approach()
	if not approaching.is_empty() and float(approaching["distance"]) < 190.0 and not pat["near"]:
		pat["near"] = true
		pat["warning"] = 3.6
	if approaching.is_empty() or float(approaching["distance"]) > 220.0:
		pat["near"] = false
	if hide["on"] and pat["near"]:
		hide["near"] = true
	pat["warning"] = maxf(0.0, float(pat["warning"]) - dt)
	var tr: Variant = pat["transition"]
	if tr != null:
		if pat["locked"]:
			pat["lost"] = float(pat["lost"]) + dt
			if float(pat["lost"]) > 2.5:
				pat["locked"] = false
				pat["lock"] = 0.0
				if not pat["permanent"]:
					pat["search"] = 3.0
		tr["remaining"] = maxf(0.0, float(tr["remaining"]) - dt)
		if float(tr["remaining"]) <= 1e-8:
			_put(tr["to"])
			pat["transition"] = null
			pat["afterBlink"] = 0.22
			_frame_path = {}
		return
	var d := distance()
	var visible := sees()
	var cabinet := locker_target()
	var known_cabinet := not cabinet.is_empty() and nav.los(position(), cabinet)
	# Only the scene with the inspection waits; a far permanent chaser keeps walking.
	if local_quiet():
		pat["doorRush"] = null
		pat["lock"] = 0.0
		red = 0.0
		return
	if not hunting():
		_clear_chase()
	if _lift_door():
		return
	var hostile := hunting() and float(pat["safety"]) <= 0.0
	if hostile and (visible or known_cabinet):
		pat["lastSeen"] = cabinet if known_cabinet else player_point()
		pat["lost"] = 0.0
		if float(pat["warning"]) <= 0.0:
			pat["lock"] = float(pat["lock"]) + dt * (2.2 if d < 60.0 else 1.1)
			if not pat["locked"] and float(pat["lock"]) >= 1.0:
				if bool(_c.get("has_seal", false)):
					_emit("remove_item", {"id": "seal"})
					_banish()
					return
				pat["locked"] = true
				pat["behavior"] = "chase"
				if not pat["permanent"] and not pat["cited"]:
					pat["cited"] = true
					_emit("violation", {"amount": 8.0})
	elif pat["locked"]:
		pat["lost"] = float(pat["lost"]) + dt
		if float(pat["lost"]) > 2.5:
			pat["locked"] = false
			pat["lock"] = 0.0
			if not pat["permanent"]:
				pat["search"] = 3.0
			_frame_path = {}
	elif not pat["locked"]:
		pat["lock"] = maxf(0.0, float(pat["lock"]) - dt)
	var goal := _target()
	pat["blinkCD"] = maxf(0.0, float(pat["blinkCD"]) - dt)
	if float(pat["safety"]) <= 0.0:
		var chasing: bool = hunting() and (pat["permanent"] or pat["locked"])
		var arrived := _navigate(goal, (nav.chase if chasing else nav.speed) * dt)
		if arrived and (pat["behavior"] == "patrol" or pat["behavior"] == "return"):
			pat["behavior"] = "patrol"
			pat["routeIndex"] = int(pat["routeIndex"]) + 1
			if int(pat["routeIndex"]) >= route_nodes.size():
				pat["routeIndex"] = 1
				pat["cycle"] = int(pat["cycle"]) + 1
			_frame_path = {}
	var at_goal: bool = not goal.is_empty() and pat["room"] == goal["scene"] and _dist3(position(), goal) < 6.0
	if float(pat["search"]) > 0.0 and at_goal:
		pat["search"] = maxf(0.0, float(pat["search"]) - dt)
		if float(pat["search"]) == 0.0:
			pat["lastSeen"] = null
			pat["cited"] = false
			pat["rejoin"] = true
			_frame_path = {}
	elif at_goal and not pat["permanent"] and not pat["locked"] and float(pat["search"]) <= 0.0:
		var sig: Variant = pat["wirelessSignal"]
		if sig != null:
			if float(pat["warning"]) <= 0.0:
				sig["remaining"] = float(sig["remaining"]) - dt
			if float(sig["remaining"]) <= 1e-7:
				pat["wirelessSignal"] = null
				pat["rejoin"] = true
				_frame_path = {}
		elif pat["investigation"] != null:
			pat["investigation"]["remaining"] = float(pat["investigation"]["remaining"]) - dt
		elif pat["memoryVisit"] != null:
			pat["memoryVisit"]["remaining"] = float(pat["memoryVisit"]["remaining"]) - dt
	if pat["investigation"] != null and float(pat["investigation"]["remaining"]) <= 0.0:
		pat["investigation"] = null
		pat["rejoin"] = true
		_frame_path = {}
	if pat["memoryVisit"] != null and float(pat["memoryVisit"]["remaining"]) <= 0.0:
		pat["memoryVisit"] = null
		pat["rejoin"] = true
		_frame_path = {}
	if pat["doorRush"] == null and pat["locked"] and hostile and float(pat["afterBlink"]) <= 0.0 and distance() < CATCH \
			and (sees() or (not cabinet.is_empty() and nav.los(position(), cabinet))) and float(pat["warning"]) <= 0.0:
		_grip("柜门被拉开了。它一直知道你在这里。" if hide["on"] else "一只手按住了你的头顶。它在点名。")


func _visuals() -> void:
	if pat["state"] == "idle":
		var sp := spawn()
		var audible: bool = sp["scene"] == _player_scene() and float(pat["respawn"]) <= 3.6 and nav.length(nav.path(player_point(), sp)) < 190.0
		var rt := fposmod(3.6 - float(pat["respawn"]), 1.8)
		flick = 0.7 if audible and (rt < 0.15 or (rt > 0.3 and rt < 0.45) or (rt > 0.75 and rt < 1.25)) else 0.0
		red = 0.0
		return
	var metric := approach()
	var near: bool = not metric.is_empty() and float(metric["distance"]) < hear_distance() and pat["state"] == "walk"
	red = 1.0 if threat() else 0.0
	var p := fposmod(3.6 - float(pat["warning"]), 1.8)
	flick = 0.7 if near and float(pat["warning"]) > 0.0 and (p < 0.15 or (p > 0.3 and p < 0.45) or (p > 0.75 and p < 1.25)) else 0.0


## One simulation slice of at most 0.1 s per step, as the old tick did.
func tick(dt: float) -> void:
	if not (dt > 0.0) or bool(_c.get("dead", false)) or not bool(_c.get("playing", true)):
		return
	_halt = false
	var left := dt
	var guard := 0
	while left > 1e-8 and not _halt and guard < 64:
		guard += 1
		var n := minf(left, 0.1)
		if pat["state"] == "idle" and float(pat["respawn"]) > 0.0:
			n = minf(n, float(pat["respawn"]))
		_step(n)
		left -= n
	_visuals()


## Whether the figure should be drawn in the player's scene, and where (scene metres).
func figure_visible() -> bool:
	return pat["state"] == "walk" and pat["room"] == _player_scene() and pat["transition"] == null


func location_label() -> String:
	if pat["state"] == "idle":
		return "信号暂不可用"
	var tr: Variant = pat["transition"]
	if tr != null:
		var a: Variant = _rooms.get(tr["from"]["scene"])
		var b: Variant = _rooms.get(tr["to"]["scene"])
		if tr["kind"] == "stairs" and a != null and b != null:
			return "楼梯／%dF→%dF" % [int(a["floor"]), int(b["floor"])]
		if tr["kind"] == "bridge":
			return ("连廊①" if (a != null and a["host"] == "c1") or (b != null and b["host"] == "c1") else "连廊②") + "／2F"
		return "连接通道"
	if pat["room"] == "out":
		return "校园室外"
	var room: Variant = _rooms.get(pat["room"])
	if room == null:
		return "信号暂不可用"
	var names := {"admin": "行政楼", "teach": "教学楼", "lab": "实验楼", "c1": "连廊①", "c2": "连廊②", "dream": "未知区域", "garw": "地下车库", "bell": "钟楼", "dormN": "北宿舍", "dormS": "南宿舍", "tunnel": "隧道"}
	return "%s／%dF" % [names.get(room["host"], room["name"]), int(room.get("floor", 1)) if room.get("floor") != null else 1]
