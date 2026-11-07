class_name ClassmatesModule
extends FeatureModule
## Classmates in the teaching building's classrooms, ported from the Web version (reference
## wd-fz.github.io@0bf508a): domain/classroom-layout.js (four classes a floor, spans of columns,
## desk rows 7/8, 10/11, 13/14), domain/classmates.js ClassmateRules.layout (the own class nearly
## full: up to 36 of 42 seats, the own seat and the deskmate's empty; other classes sparse; at most
## 50 a floor; the same every visit in one run) and app/classmates.js (occupied desks cannot be
## searched; at 70 violations they all look at you and SAN drains 0.12 a second down to 1; at 92 they
## block the nearest door until violations fall under 80).

const STATE_VERSION := 1
const SPANS := [[9, 19], [21, 31], [33, 43], [45, 55]]
const DESK_ROWS := [7, 8, 10, 11, 13, 14]
const DESK_COLS := [2, 3, 4, 5, 6, 7, 8]
const OWN := {"room": "teach1", "class": 3, "col": 48, "row": 11}

var run_seed := ""
var state: Dictionary = {}
var events: Array = []
var _rooms: Dictionary = {}
var _cache: Dictionary = {}


func _init(rooms: Dictionary = {}) -> void:
	_rooms = rooms


func module_id() -> StringName:
	return &"school.classmates"


func state_version() -> int:
	return STATE_VERSION


func reset() -> void:
	state = {"room": "", "blocking": false, "door": null, "said": false}
	events = []
	_cache = {}


func set_seed(value: String) -> void:
	run_seed = value
	_cache = {}


func capture() -> Dictionary:
	return {"seed": run_seed}


func validate(_data: Dictionary) -> String:
	return ""


func restore(data: Dictionary) -> void:
	reset()
	run_seed = String(data.get("seed", ""))


func take_events() -> Array:
	var out := events
	events = []
	return out


static func eligible(room: Dictionary) -> bool:
	return not room.is_empty() and room.get("host") == "teach" and not room.get("flags", {}).get("stairwell", false) \
		and room.get("floor") != null and int(room["floor"]) >= 1 and int(room["floor"]) <= 5


static func seat_tiles(i: int) -> Array:
	var c0 := int(SPANS[i][0])
	var out: Array = []
	for dc: int in DESK_COLS:
		for r: int in DESK_ROWS:
			out.append(Vector2i(c0 + dc, r))
	return out


## ClassmateRules.layout with ClassroomLayout: {seats: [Vector2i], occupied: {"c,r": true}}.
func layout(room_id: String) -> Dictionary:
	if _cache.has(room_id):
		return _cache[room_id]
	var room: Dictionary = _rooms.get(room_id, {})
	var seats: Array = []
	var occupied := {}
	if eligible(room):
		var h := 2166136261
		var source := "%s|%s" % [run_seed, room_id]
		for i in source.length():
			h = ((h ^ source.unicode_at(i)) * 16777619) & 0xFFFFFFFF
		var grid: Array = room["grid"]
		var home := int(OWN["class"]) if room_id == OWN["room"] else -1
		var skip := {}
		var k := DESK_ROWS.find(int(OWN["row"]))
		if home >= 0 and k >= 0:
			skip["%d,%d" % [int(OWN["col"]), DESK_ROWS[k - 1 if k % 2 == 1 else k + 1]]] = true
		var order: Array = [0, 1, 2, 3]
		if home >= 0:
			order = [home] + order.filter(func(x: int) -> bool: return x != home)
		for ci: int in order:
			var tiles := seat_tiles(ci)
			tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
			var in_class := 0
			var cap := 36 if ci == home else 10
			var p := 0.86 if ci == home else (0.16 if home >= 0 else 0.2)
			for t: Vector2i in tiles:
				h = (h * 1664525 + 1013904223) & 0xFFFFFFFF
				var roll := float(h) / 4294967296.0
				if seats.size() >= 50 or in_class >= cap or t.y >= grid.size() or String(grid[t.y]).substr(t.x, 1) != "d" or skip.has("%d,%d" % [t.x, t.y]) or roll >= p:
					continue
				seats.append(t)
				occupied["%d,%d" % [t.x, t.y]] = true
				in_class += 1
	var out := {"seats": seats, "occupied": occupied}
	_cache[room_id] = out
	return out


func occupied(room_id: String, c: int, r: int) -> bool:
	return layout(room_id)["occupied"].has("%d,%d" % [c, r])


func _nearest_door(room: Dictionary, me: Vector2) -> Variant:
	var best: Variant = null
	var dist := INF
	var grid: Array = room["grid"]
	for r in range(1, grid.size() - 1):
		for c in range(1, String(grid[r]).length() - 1):
			if String(grid[r]).substr(c, 1) == "=":
				var d := absf(c * float(room["tw"]) + float(room["ox"]) - me.x) + absf(r * float(room["th"]) + float(room["oy"]) - me.y)
				if d < dist:
					dist = d
					best = {"x": float(room["ox"]) + (c + 0.5) * float(room["tw"]), "y": float(room["oy"]) + (r + 0.5) * float(room["th"]), "c": c, "r": r}
	return best


## Classmates.tick. Returns nothing; events: notice. blocked() answers the door question.
func tick(scene: String, me: Vector2, viol: float, dead: bool) -> void:
	var room: Dictionary = _rooms.get(scene, {})
	if state["room"] != scene:
		state = {"room": scene, "blocking": false, "door": null, "said": false}
	if not eligible(room):
		state["blocking"] = false
		state["door"] = null
		return
	if viol >= 92.0 and state["door"] == null:
		state["door"] = _nearest_door(room, me)
	if viol < 80.0:
		state["door"] = null
	state["blocking"] = viol >= 92.0 and state["door"] != null
	if viol >= 70.0 and not dead and not bool(state["said"]):
		state["said"] = true
		events.append({"kind": "notice", "text": "我：他们都在看着我。可是没有人说话。"})


func blocked(scene: String, c: int, r: int) -> bool:
	var d: Variant = state.get("door")
	return state.get("room") == scene and bool(state.get("blocking", false)) and d is Dictionary and int(d["c"]) == c and int(d["r"]) == r


## ncPressureTick: in a classroom of theirs, with 70+ violations, SAN drains 0.12 a second (not below 1).
func pressure(scene: String, viol: float) -> float:
	return 0.12 if eligible(_rooms.get(scene, {})) and viol >= 70.0 else 0.0
