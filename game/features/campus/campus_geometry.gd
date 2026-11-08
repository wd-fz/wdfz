class_name CampusGeometry
extends RefCounted
## Pure ports of the Web version's spatial rules (reference wd-fz.github.io@0bf508a):
## world.js worldToScene, core.js angDiff, interact.js nearWorld/tileLOS/tileVisible,
## world.js doorWorld, modules/campus-link/doors.js port/local/cross.
## Layout dictionaries are the JSON exported by tools/export_scenes from the old game itself.
##
## Old coordinates: world units (1 unit = 1/9 m), x east, y south, heading `ang` with
## forward = (cos ang, sin ang). Godot: metres, forward = -Z rotated by yaw.

const U2M := 1.0 / 9.0
const TTILE := 9.0
const PRAD := 3.0
const NEAR_ROOM := 24.0
const NEAR_BUILDING := 70.0
const NORMALS := {"n": Vector2(0, -1), "s": Vector2(0, 1), "w": Vector2(-1, 0), "e": Vector2(1, 0)}
const SOLID_CH := "#S"


static func yaw_from_ang(ang: float) -> float:
	return wrapf(-ang - PI * 0.5, -PI, PI)


static func ang_from_yaw(yaw: float) -> float:
	return wrapf(-yaw - PI * 0.5, -PI, PI)


static func ang_diff(a: float, b: float) -> float:
	var d := absf(fmod(a - b, TAU))
	return minf(d, TAU - d)


## Scene metres (x, z) -> old world units. `room` is null for the campus outside.
static func to_world(room: Variant, x: float, z: float) -> Vector2:
	if room == null:
		return Vector2(x / U2M, z / U2M)
	return Vector2(float(room["cx"]) + x / U2M, float(room["cy"]) + z / U2M)


static func to_scene(room: Variant, w: Vector2) -> Vector2:
	if room == null:
		return w * U2M
	return Vector2((w.x - float(room["cx"])) * U2M, (w.y - float(room["cy"])) * U2M)


static func tile_at(room: Dictionary, w: Vector2) -> String:
	var c := int(floor((w.x - float(room["ox"])) / float(room["tw"])))
	var r := int(floor((w.y - float(room["oy"])) / float(room["th"])))
	if r < 0 or c < 0 or r >= int(room["rows"]) or c >= int(room["cols"]):
		return "#"
	return String(room["grid"][r]).substr(c, 1)


static func door_key(room: Dictionary, c: int, r: int) -> String:
	return "%s:%d:%d" % [room["id"], c, r]


static func tile_center(room: Dictionary, c: int, r: int) -> Vector2:
	return Vector2(float(room["ox"]) + (c + 0.5) * float(room["tw"]), float(room["oy"]) + (r + 0.5) * float(room["th"]))


## interact.js tileLOS: walls, solid stair cells and closed doors block; the target cell does not.
static func tile_los(room: Dictionary, a: Vector2, b: Vector2, tc: int, tr: int, open_doors: Dictionary) -> bool:
	var d := b - a
	var length := d.length()
	if length < 0.001:
		return true
	var step := maxf(0.5, minf(float(room["tw"]), float(room["th"])) * 0.25)
	var n := int(ceil(length / step))
	for i in range(1, n):
		var p := a + d * (float(i) / n)
		var c := int(floor((p.x - float(room["ox"])) / float(room["tw"])))
		var r := int(floor((p.y - float(room["oy"])) / float(room["th"])))
		if r < 0 or c < 0 or r >= int(room["rows"]) or c >= int(room["cols"]):
			return false
		if c == tc and r == tr:
			continue
		var ch := String(room["grid"][r]).substr(c, 1)
		if SOLID_CH.contains(ch):
			return false
		if ch == "=" and not open_doors.has(door_key(room, c, r)):
			return false
	return true


static func tile_visible(room: Dictionary, me: Vector2, hit: Dictionary, open_doors: Dictionary) -> bool:
	var target: Vector2 = hit["w"]
	if tile_los(room, me, target, hit["c"], hit["r"], open_doors):
		return true
	var ox := float(room["tw"]) * 0.42 * (1.0 if me.x > target.x else -1.0)
	var oy := float(room["th"]) * 0.42 * (1.0 if me.y > target.y else -1.0)
	return tile_los(room, me, target + Vector2(ox, 0), hit["c"], hit["r"], open_doors) \
		or tile_los(room, me, target + Vector2(0, oy), hit["c"], hit["r"], open_doors)


## interact.js nearWorld (indoor branch): facing cells first, nearer sideways/behind cells only.
static func near_tile(room: Dictionary, me: Vector2, ang: float, radius: float, open_doors: Dictionary) -> Dictionary:
	var hits: Array[Dictionary] = []
	var grid: Array = room["grid"]
	for r in grid.size():
		var row := String(grid[r])
		for c in row.length():
			var ch := row.substr(c, 1)
			if ch == "#" or ch == ".":
				continue
			var w := tile_center(room, c, r)
			var d := me.distance_to(w)
			if d >= radius:
				continue
			var off := 0.0 if d < 4.0 else ang_diff(atan2(w.y - me.y, w.x - me.x), ang)
			if off > 0.62 and d > 3.0:
				continue
			hits.append({"ch": ch, "c": c, "r": r, "w": w, "d": d, "score": off * 32.0 + d})
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] < b["score"])
	for hit: Dictionary in hits:
		if tile_visible(room, me, hit, open_doors):
			return hit
	return {}


## interact.js nearWorld (outdoor branch): nearest building door within 70 units.
static func near_building(outside: Dictionary, me: Vector2) -> Dictionary:
	var best := {}
	var best_d := 1e9
	for o: Dictionary in outside["objects"]:
		if o["k"] != "roof" or o.get("door_world") == null:
			continue
		var dw := Vector2(o["door_world"]["x"], o["door_world"]["y"])
		var d := me.distance_to(dw)
		if d < NEAR_BUILDING and d < best_d:
			best_d = d
			best = {"obj": o, "door": dw, "d": d}
	return best


## campus-link/doors.js port(): threshold mid point, outward normal (room coordinates).
static func door_port(room: Dictionary, d: Dictionary) -> Dictionary:
	var edge := String(d["edge"])
	var at := float(d["at"])
	var ox := float(room["ox"])
	var oy := float(room["oy"])
	var x := ox if edge == "w" else (ox + int(room["cols"]) * float(room["tw"]) if edge == "e" else ox + (at + 0.5) * float(room["tw"]))
	var y := oy if edge == "n" else (oy + int(room["rows"]) * float(room["th"]) if edge == "s" else oy + (at + 0.5) * float(room["th"]))
	return {"p": Vector2(x, y), "n": NORMALS[edge]}


static func door_local(port: Dictionary, w: Vector2) -> Vector2:
	var n: Vector2 = port["n"]
	var dd := w - (port["p"] as Vector2)
	return Vector2(dd.x * n.x + dd.y * n.y, -dd.x * n.y + dd.y * n.x) # (along, lat)


static func door_half(d: Dictionary, default_width: float) -> float:
	return float(d.get("width", default_width)) * TTILE * 0.5


static func shift_of(room: Dictionary) -> Vector2:
	var s: Dictionary = room["shift"]
	return Vector2(s["x"], s["y"])
