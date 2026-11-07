class_name CampusPortals
extends RefCounted
## Walking portals of the Web version (reference wd-fz.github.io@0bf508a):
## - stairwells: modules/stairwell/stairwell.js (StairWorld port/toShaft/fromShaft/portalAt/moved)
##   and domain/stairwell-geometry.js (StairGeometry.surfaces/surface);
## - corridor bridges: modules/campus-link/link.js (CampusLink port/between/apply/cross).
## Pure functions over exported layout dictionaries. Old world units unless the name says metres.

const U2M := CampusGeometry.U2M
const DOOR_HALF := 0.85        # stair doorway half width (m), portalAt / doorwayFree
const ENTER_Z := -2.79         # walk past this shaft z to enter the stairwell
const EXIT_Z := -2.85          # walk below this shaft z on a landing to leave it
const LEVEL_TOLERANCE := 0.08


# ---- stairwells ----

## StairGeometry.surfaces(levels, rise): walkable rectangles (metres) with linear height along z.
static func stair_surfaces(levels: int, rise: float) -> Array[Dictionary]:
	var a: Array[Dictionary] = []
	for f in levels:
		a.append({"x0": -2.2, "x1": 2.2, "z0": -1.2, "z1": 0.8, "h0": f * rise, "h1": f * rise})
		a.append({"x0": -0.85, "x1": 0.85, "z0": -3.5, "z1": -1.2, "h0": f * rise, "h1": f * rise})
		if f == levels - 1:
			continue
		a.append({"x0": -2.2, "x1": -0.3, "z0": 0.8, "z1": 5.6, "h0": f * rise, "h1": (f + 0.5) * rise})
		a.append({"x0": -2.2, "x1": 2.2, "z0": 5.6, "z1": 7.2, "h0": (f + 0.5) * rise, "h1": (f + 0.5) * rise})
		a.append({"x0": 0.3, "x1": 2.2, "z0": 0.8, "z1": 5.6, "h0": (f + 1) * rise, "h1": (f + 0.5) * rise})
	return a


static func surface_height(s: Dictionary, z: float) -> float:
	return float(s["h0"]) + (float(s["h1"]) - float(s["h0"])) * clampf((z - float(s["z0"])) / (float(s["z1"]) - float(s["z0"])), 0.0, 1.0)


## StairGeometry.surface: the surface under (x, z) closest to height `near`, within max_delta.
static func surface_at(list: Array[Dictionary], x: float, z: float, near: float, max_delta: float = 0.28) -> Dictionary:
	var best := {}
	var dist := INF
	for s: Dictionary in list:
		if x < float(s["x0"]) or x > float(s["x1"]) or z < float(s["z0"]) or z > float(s["z1"]):
			continue
		var h := surface_height(s, z)
		var d := absf(h - near)
		if d < dist:
			dist = d
			best = {"h": h, "s": s}
	return best if not best.is_empty() and dist <= max_delta + 1e-8 else {}


static func stair_config(layout: Array, id: String) -> Dictionary:
	for s: Dictionary in layout:
		if s["id"] == id:
			return s
	return {}


## StairWorld.port: the threshold of shaft `s` on `level`, in that level's scene coordinates.
static func stair_port(s: Dictionary, level: int, rooms: Dictionary, outside: Dictionary) -> Dictionary:
	var id := String(s["rooms"][level])
	var n := Vector2(s["n"][0], s["n"][1])
	if id == "out":
		for o: Dictionary in outside.get("objects", []):
			if o["id"] == "garw" and o.get("door_world") != null:
				return {"scene": "out", "p": Vector2(o["door_world"]["x"], o["door_world"]["y"]), "n": Vector2(0, -1), "level": level}
		return {}
	var r: Dictionary = rooms[id]
	var c := int(s["col"])
	var row := int(s["row"])
	if id == "teach6" and s.has("roof"):
		c = int(s["roof"][0])
		row = int(s["roof"][1])
	var x := float(r["ox"]) + (c + (0.5 if n.x != 0 else 1.0)) * float(r["tw"])
	var y := float(r["oy"]) + (row + (1.0 if n.x != 0 else 0.5)) * float(r["th"])
	return {"scene": id, "p": Vector2(x, y), "n": n, "level": level}


## StairWorld.toShaft: scene point -> shaft-local metres (x lateral, z inward, door at -2.8).
static func to_shaft(port: Dictionary, w: Vector2) -> Vector2:
	var p: Vector2 = port["p"]
	var n: Vector2 = port["n"]
	var dx := (w.x - p.x) * U2M
	var dy := (w.y - p.y) * U2M
	return Vector2(dx * n.y - dy * n.x, dx * n.x + dy * n.y - 2.8)


static func from_shaft(port: Dictionary, q: Vector2) -> Vector2:
	var p: Vector2 = port["p"]
	var n: Vector2 = port["n"]
	return Vector2(p.x + (q.x * n.y + (q.y + 2.8) * n.x) / U2M, p.y + (-q.x * n.x + (q.y + 2.8) * n.y) / U2M)


static func stair_turn(n: Vector2) -> float:
	return atan2(n.y, n.x) - PI * 0.5


## StairWorld.portalAt: is this point in a stair doorway of `scene_id`? Returns {s, level, port, q}.
static func stair_portal_at(layout: Array, scene_id: String, w: Vector2, rooms: Dictionary, outside: Dictionary, radius: float = 0.0) -> Dictionary:
	var result := {}
	for s: Dictionary in layout:
		var level := (s["rooms"] as Array).find(scene_id)
		if level < 0:
			continue
		var port := stair_port(s, level, rooms, outside)
		if port.is_empty():
			continue
		var q := to_shaft(port, w)
		if absf(q.x) < DOOR_HALF + radius * U2M and q.y > -3.65 and q.y < -2.3:
			result = {"s": s, "level": level, "port": port, "q": q}
	return result


# ---- corridor bridges ----

## CampusLink.port: same threshold geometry as the campus doors, width from CAMPUS_LINK.
static func link_port(rooms: Dictionary, p: Dictionary, width: float) -> Dictionary:
	if not rooms.has(p["room"]):
		return {}
	var r: Dictionary = rooms[p["room"]]
	var port := CampusGeometry.door_port(r, p)
	port["room"] = p["room"]
	port["half"] = width * CampusGeometry.TTILE * 0.5
	return port


## CampusLink.between: rigid transform from side a to side b (a outward = b inward).
static func link_between(a: Dictionary, b: Dictionary) -> Dictionary:
	var an: Vector2 = a["n"]
	var bn: Vector2 = b["n"]
	var phi := atan2(-bn.y, -bn.x) - atan2(an.y, an.x)
	var r := (a["p"] as Vector2).rotated(phi)
	return {"phi": phi, "t": (b["p"] as Vector2) - r}


static func link_apply(t: Dictionary, w: Vector2) -> Vector2:
	return w.rotated(float(t["phi"])) + (t["t"] as Vector2)


static func link_ports(cfg: Dictionary, rooms: Dictionary, room_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if cfg.is_empty():
		return out
	var width := float(cfg.get("width", 3))
	for pair: Array in cfg.get("pairs", []):
		for side in 2:
			if pair[side]["room"] == room_id:
				var me := link_port(rooms, pair[side], width)
				var peer := link_port(rooms, pair[1 - side], width)
				if not me.is_empty() and not peer.is_empty():
					out.append({"self": me, "peer": peer})
	return out
