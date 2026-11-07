class_name PatrolNav
extends RefCounted
## Patrol navigation, ported from modules/patrol-world/navigation.js (reference
## wd-fz.github.io@0bf508a). Static proxy grids (0.25 m indoors / 1 m outdoors, body radius 0.30 m,
## doors walkable) plus an explicit connection graph, both exported from the old game.
## Points are Dictionaries {scene, x, y, fy}: old world units, fy = foot height in metres.
## Paths on the grids use AStarGrid2D (diagonals only when both neighbours are free — the old
## "no corner cutting" rule); ties between equal-cost routes can differ from the JavaScript heap.
## Not ported: the void maze scene (lift_dream) — its paths are reported unreachable.

const U2M := CampusGeometry.U2M
const SNAP_RINGS := 12

var speed := 16.0
var chase := 31.0
var door_open := func(_room: String, _c: int, _r: int) -> bool: return false

var _geometry: Dictionary = {}
var _rooms: Dictionary = {}
var _campus: Dictionary = {}
var nodes: Dictionary = {}
var edges: Array = []
var patrol_edges: Array = []
var _adj: Dictionary = {}
var _grids: Dictionary = {}
var _dijkstra_cache: Dictionary = {}
var _stair_cfg: Dictionary = {}


func _init(data: Dictionary = {}, rooms: Dictionary = {}, campus: Dictionary = {}) -> void:
	_geometry = data.get("geometry", {})
	_rooms = rooms
	_campus = campus
	var consts: Dictionary = data.get("consts", {})
	speed = float(consts.get("speed", 16))
	chase = float(consts.get("chase", 31))
	var graph: Dictionary = data.get("graph", {})
	nodes = graph.get("nodes", {})
	edges = graph.get("edges", [])
	patrol_edges = graph.get("patrolEdges", [])
	for i in edges.size():
		var e: Dictionary = edges[i]
		for pair: Array in [[e["a"], e["b"]], [e["b"], e["a"]]]:
			if not _adj.has(pair[0]):
				_adj[pair[0]] = []
			_adj[pair[0]].append({"to": pair[1], "weight": float(e["weight"]), "edge": i})
	for s: Dictionary in campus.get("stair_layout", []):
		_stair_cfg[s["id"]] = s


static func point(scene: String, x: float, y: float, fy: float = 0.0) -> Dictionary:
	return {"scene": scene, "x": x, "y": y, "fy": fy}


static func same_point(a: Dictionary, b: Dictionary) -> bool:
	return a["scene"] == b["scene"] and a["x"] == b["x"] and a["y"] == b["y"] and float(a.get("fy", 0.0)) == float(b.get("fy", 0.0))


func is_stairwell(id: String) -> bool:
	return _stair_cfg.has(id)


func stair_config(id: String) -> Dictionary:
	return _stair_cfg.get(id, {})


# ---- grids ----

func grid(id: String) -> Dictionary:
	if _grids.has(id):
		return _grids[id]
	if not _geometry.has(id):
		return {}
	var d: Dictionary = _geometry[id]
	var g := {"W": int(d["W"]), "H": int(d["H"]), "step": float(d["step"]), "ox": float(d["ox"]), "oy": float(d["oy"]),
		"bytes": Marshalls.base64_to_raw(String(d["bits"])), "astar": null}
	_grids[id] = g
	return g


func is_free(id: String, i: int, j: int) -> bool:
	var g := grid(id)
	if g.is_empty() or i < 0 or j < 0 or i >= g["W"] or j >= g["H"]:
		return false
	var k: int = i + j * int(g["W"])
	var bytes: PackedByteArray = g["bytes"]
	if (k >> 3) < bytes.size() and (bytes[k >> 3] & (1 << (k & 7))) != 0:
		return false
	if id == "bell1":
		var sp: Dictionary = _campus.get("spiral", {})
		var room: Dictionary = _rooms["bell1"]
		var p := cell_world(id, i, j)
		var x := (float(p["x"]) - float(room["cx"])) * U2M - float(sp["cx"])
		var z := (float(p["y"]) - float(room["cy"])) * U2M - float(sp["cz"])
		var r := Vector2(x, z).length()
		var angle := _wrap(atan2(z, x) - float(sp["th0"]))
		if r < float(sp["rIn"]) + 0.30:
			return false
		if r < float(sp["rOut"]) + 0.30 and (angle < float(sp["enter"][0]) or angle > float(sp["enter"][1])):
			return false
	return true


static func _wrap(a: float) -> float:
	return fposmod(a + PI, TAU) - PI


func cell(id: String, p: Dictionary) -> Vector2i:
	var g := grid(id)
	return Vector2i(int(floor((float(p["x"]) - float(g["ox"])) / float(g["step"]))), int(floor((float(p["y"]) - float(g["oy"])) / float(g["step"]))))


func cell_world(id: String, i: int, j: int) -> Dictionary:
	var g := grid(id)
	return point(id, float(g["ox"]) + (i + 0.5) * float(g["step"]), float(g["oy"]) + (j + 0.5) * float(g["step"]))


func _astar(id: String) -> AStarGrid2D:
	var g := grid(id)
	if g["astar"] != null:
		return g["astar"]
	var a := AStarGrid2D.new()
	a.region = Rect2i(0, 0, int(g["W"]), int(g["H"]))
	a.cell_size = Vector2.ONE
	a.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	a.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	a.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	a.update()
	for j in int(g["H"]):
		for i in int(g["W"]):
			if not is_free(id, i, j):
				a.set_point_solid(Vector2i(i, j), true)
	g["astar"] = a
	return a


## Nearest free cell centre within 12 rings (navigation.js snap); stairwells use their surfaces.
func snap(id: String, p: Dictionary) -> Dictionary:
	if is_stairwell(id):
		return stair_snap(id, p)
	if grid(id).is_empty():
		return {}
	var c := cell(id, p)
	var best := {}
	var best_d := INF
	var r := 0
	while r <= SNAP_RINGS and best.is_empty():
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				if maxi(absi(x), absi(y)) != r or not is_free(id, c.x + x, c.y + y):
					continue
				var q := cell_world(id, c.x + x, c.y + y)
				var d := Vector2(float(q["x"]) - float(p["x"]), float(q["y"]) - float(p["y"])).length()
				if d < best_d:
					best = q
					best_d = d
		r += 1
	return best


## Every cell along the segment must be free; diagonal grid corners also need both neighbours.
func segment(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty() or a["scene"] != b["scene"]:
		return false
	var id: String = a["scene"]
	var g := grid(id)
	if g.is_empty() or id == "bell1" or id == "lift_dream" or is_stairwell(id):
		return false
	var s := cell(id, a)
	var t := cell(id, b)
	var x := s.x
	var y := s.y
	if not is_free(id, x, y) or not is_free(id, t.x, t.y):
		return false
	var dx: float = float(b["x"]) - float(a["x"])
	var dy: float = float(b["y"]) - float(a["y"])
	var sx := int(signf(dx))
	var sy := int(signf(dy))
	var step := float(g["step"])
	var tx := ((float(g["ox"]) + (x + (1 if sx > 0 else 0)) * step) - float(a["x"])) / dx if sx != 0 else INF
	var ty := ((float(g["oy"]) + (y + (1 if sy > 0 else 0)) * step) - float(a["y"])) / dy if sy != 0 else INF
	var stepx := step / absf(dx) if sx != 0 else INF
	var stepy := step / absf(dy) if sy != 0 else INF
	var guard := 0
	while (x != t.x or y != t.y) and guard < 100000:
		guard += 1
		if absf(tx - ty) < 1e-10:
			if not is_free(id, x + sx, y) or not is_free(id, x, y + sy):
				return false
			x += sx
			y += sy
			tx += stepx
			ty += stepy
		elif tx < ty:
			x += sx
			tx += stepx
		else:
			y += sy
			ty += stepy
		if not is_free(id, x, y):
			return false
	return true


func planar(a: Dictionary, b: Dictionary) -> Array:
	if a["scene"] != b["scene"]:
		return []
	var id: String = a["scene"]
	if grid(id).is_empty():
		return []
	var s := snap(id, a)
	var t := snap(id, b)
	if s.is_empty() or t.is_empty():
		return []
	var ids := _astar(id).get_id_path(cell(id, s), cell(id, t))
	var out: Array = []
	for c: Vector2i in ids:
		out.append(cell_world(id, c.x, c.y))
	return out


# ---- stairwell shaft (StairWorld.navPath / navSnap) ----

func _stair_local(id: String, p: Dictionary) -> Dictionary:
	var r: Dictionary = _rooms[id]
	return {"x": (float(p["x"]) - float(r["cx"])) * U2M, "z": (float(p["y"]) - float(r["cy"])) * U2M, "h": float(p.get("fy", 0.0))}


func stair_point(id: String, p: Dictionary) -> Dictionary:
	var r: Dictionary = _rooms[id]
	return point(id, float(r["cx"]) + float(p["x"]) / U2M, float(r["cy"]) + float(p["z"]) / U2M, float(p["h"]))


func stair_snap(id: String, p: Dictionary) -> Dictionary:
	var s: Dictionary = _stair_cfg[id]
	var q := _stair_local(id, p)
	var list := CampusPortals.stair_surfaces((s["rooms"] as Array).size(), float(s["rise"]))
	var hit := CampusPortals.surface_at(list, q["x"], q["z"], q["h"], 0.6)
	return stair_point(id, q) if not hit.is_empty() else {}


func stair_path(a: Dictionary, b: Dictionary) -> Array:
	var id: String = a["scene"]
	var s: Dictionary = _stair_cfg[id]
	var out: Array = []
	for q: Dictionary in CampusPortals.stair_path(_stair_local(id, a), _stair_local(id, b), (s["rooms"] as Array).size(), float(s["rise"])):
		out.append(stair_point(id, q))
	return out


# ---- bell tower spiral (navigation.js bell) ----

func _spiral_polar(wx: float, wy: float) -> Vector2:
	var sp: Dictionary = _campus["spiral"]
	var r: Dictionary = _rooms["bell1"]
	var dx := (wx - float(r["cx"])) * U2M - float(sp["cx"])
	var dz := (wy - float(r["cy"])) * U2M - float(sp["cz"])
	return Vector2(Vector2(dx, dz).length(), atan2(dz, dx))


func _bell_point(angle: float) -> Dictionary:
	var sp: Dictionary = _campus["spiral"]
	var r: Dictionary = _rooms["bell1"]
	var rr := (float(sp["rIn"]) + float(sp["rOut"])) * 0.5
	var th := float(sp["th0"]) + angle
	return point("bell1", float(r["cx"]) + (float(sp["cx"]) + cos(th) * rr) / U2M, float(r["cy"]) + (float(sp["cz"]) + sin(th) * rr) / U2M, angle / TAU * float(sp["turnH"]))


func _bell_top_arc(q: Dictionary, reverse: bool) -> Array:
	var sp: Dictionary = _campus["spiral"]
	var r: Dictionary = _rooms["bell1"]
	var rr := (float(sp["rIn"]) + float(sp["rOut"])) * 0.5
	var polar := _spiral_polar(float(q["x"]), float(q["y"]))
	var angle := _wrap(polar.y - float(sp["th0"]))
	var steps := int(ceil(absf(angle) / 0.08))
	var points: Array = []
	for j in steps + 1:
		var th := float(sp["th0"]) + (angle * j / steps if steps > 0 else 0.0)
		points.append(point("bell1", float(r["cx"]) + (float(sp["cx"]) + cos(th) * rr) / U2M, float(r["cy"]) + (float(sp["cz"]) + sin(th) * rr) / U2M, float(sp["topH"])))
	points.append(q)
	if reverse:
		points.reverse()
	return points


func bell_path(a: Dictionary, b: Dictionary) -> Array:
	if float(a["fy"]) < 0.01 and float(b["fy"]) < 0.01:
		return planar(a, b)
	var sp: Dictionary = _campus["spiral"]
	var amax := float(sp["amax"])
	var aa := clampf(float(a["fy"]) / float(sp["turnH"]) * TAU, 0.0, amax)
	var bb := clampf(float(b["fy"]) / float(sp["turnH"]) * TAU, 0.0, amax)
	var out: Array = []
	if aa == 0.0:
		var start := planar(a, _bell_point(0.0))
		if start.is_empty():
			return []
		out.append_array(start)
	elif aa == amax:
		out = _bell_top_arc(a, true)
	else:
		out.append(a)
		out.append(_bell_point(aa))
	var steps := int(ceil(absf(bb - aa) / 0.08))
	for i in range(1, steps + 1):
		out.append(_bell_point(aa + (bb - aa) * i / steps))
	if bb == 0.0:
		var tail := planar(_bell_point(0.0), b)
		if tail.is_empty():
			return []
		out.append_array(tail)
	elif bb == amax:
		out.append_array(_bell_top_arc(b, false))
	else:
		out.append(b)
	return out


## Waypoints from a to b in one scene; empty when unreachable (navigation.js path).
func path(a: Dictionary, b: Dictionary) -> Array:
	if a.is_empty() or b.is_empty() or a["scene"] != b["scene"]:
		return []
	var id: String = a["scene"]
	if is_stairwell(id):
		return stair_path(a, b)
	if id == "lift_dream":
		return []
	if id == "bell1":
		return bell_path(a, b)
	return planar(a, b)


## Length in old world units, height counted in metres converted back (INF for no path).
func length(p: Array) -> float:
	if p.is_empty():
		return INF
	var n := 0.0
	for i in range(1, p.size()):
		var dh := (float(p[i].get("fy", 0.0)) - float(p[i - 1].get("fy", 0.0))) / U2M
		n += Vector3(float(p[i]["x"]) - float(p[i - 1]["x"]), float(p[i]["y"]) - float(p[i - 1]["y"]), dh).length()
	return n


# ---- graph (RouteGraph.shortest, deterministic) ----

func _dijkstra(src: String) -> Dictionary:
	if _dijkstra_cache.has(src):
		return _dijkstra_cache[src]
	var dist := {src: 0.0}
	var prev := {}
	var todo: Array = nodes.keys()
	todo.sort()
	while not todo.is_empty():
		var best := -1
		for i in todo.size():
			var n: String = todo[i]
			if not dist.has(n):
				continue
			if best < 0 or dist[n] < dist[todo[best]] - 1e-12 or (absf(dist[n] - dist[todo[best]]) <= 1e-12 and n < todo[best]):
				best = i
		if best < 0:
			break
		var a: String = todo[best]
		todo.remove_at(best)
		for link: Dictionary in _adj.get(a, []):
			var b: String = link["to"]
			if todo.find(b) < 0:
				continue
			var d: float = dist[a] + link["weight"]
			if not dist.has(b) or d < dist[b] - 1e-8:
				dist[b] = d
				prev[b] = {"node": a, "edge": link["edge"]}
	var result := {"dist": dist, "prev": prev}
	_dijkstra_cache[src] = result
	return result


func shortest(from: String, to: String) -> Dictionary:
	var d := _dijkstra(from)
	if not d["dist"].has(to):
		return {}
	var path_nodes: Array = [to]
	var path_edges: Array = []
	var cur := to
	while cur != from:
		var p: Variant = d["prev"].get(cur)
		if p == null:
			return {}
		path_edges.push_front(p["edge"])
		cur = p["node"]
		path_nodes.push_front(cur)
	return {"weight": d["dist"][to], "nodes": path_nodes, "edges": path_edges}


## Cheapest route node among `ids` from a point (nearest rejoin point of the patrol route).
func nearest_route(a: Dictionary, ids: Array) -> String:
	var best_id := ""
	var best_cost := INF
	var targets: Array = []
	for id: String in ids:
		if not targets.has(id):
			targets.append(id)
	targets.sort()
	var starts: Array = nodes.keys()
	starts.sort()
	for s: String in starts:
		if nodes[s]["scene"] != a["scene"]:
			continue
		var lead := length(path(a, nodes[s])) / speed
		if not is_finite(lead):
			continue
		for t: String in targets:
			var mid := shortest(s, t)
			if mid.is_empty():
				continue
			var cost := lead + float(mid["weight"])
			if best_id.is_empty() or cost < best_cost - 1e-8 or (absf(cost - best_cost) < 1e-8 and t < best_id):
				best_id = t
				best_cost = cost
	return best_id


## Route a -> b: waypoints in the same scene, otherwise the first leg towards a connection node,
## or a timed transition when already at the connection (navigation.js route).
func route(a: Dictionary, b: Dictionary) -> Dictionary:
	if a["scene"] == b["scene"]:
		return {"points": path(a, b), "transition": null}
	var starts: Array = []
	var ends: Array = []
	for k: String in nodes:
		if nodes[k]["scene"] == a["scene"]:
			starts.append(k)
		if nodes[k]["scene"] == b["scene"]:
			ends.append(k)
	var best := {}
	var tail := {}
	for e: String in ends:
		tail[e] = length(path(nodes[e], b)) / chase
	for s: String in starts:
		var approach_pts := path(a, nodes[s])
		var lead := length(approach_pts) / chase
		if not is_finite(lead):
			continue
		for e: String in ends:
			if not is_finite(tail[e]):
				continue
			var mid := shortest(s, e)
			if mid.is_empty():
				continue
			var cost := lead + float(mid["weight"]) + float(tail[e])
			if best.is_empty() or cost < float(best["cost"]):
				best = {"cost": cost, "points": approach_pts, "nodes": mid["nodes"], "edges": mid["edges"]}
	if best.is_empty():
		return {}
	if best["points"].size() > 1 and length(best["points"]) > 3.0:
		return {"points": best["points"], "transition": null}
	if best["nodes"].size() < 2:
		return {}
	var edge: Dictionary = edges[best["edges"][0]]
	var target: Dictionary = nodes[best["nodes"][1]]
	if a["scene"] == target["scene"]:
		return {"points": path(a, target), "transition": null}
	return {"points": null, "transition": {"from": a.duplicate(), "to": target.duplicate(), "remaining": float(edge["weight"]), "total": float(edge["weight"]), "kind": edge["kind"]}}


# ---- sight ----

func los(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty() or a["scene"] != b["scene"] or absf(float(a.get("fy", 0.0)) - float(b.get("fy", 0.0))) > 1.3:
		return false
	var id: String = a["scene"]
	if is_stairwell(id):
		var s: Dictionary = _stair_cfg[id]
		var list := CampusPortals.stair_surfaces((s["rooms"] as Array).size(), float(s["rise"]))
		return CampusPortals.stair_los(list, _stair_local(id, a), _stair_local(id, b))
	var steps := int(ceil(Vector2(float(a["x"]) - float(b["x"]), float(a["y"]) - float(b["y"])).length() / 2.0))
	var room: Variant = _rooms.get(id)
	for i in range(1, steps):
		var x: float = float(a["x"]) + (float(b["x"]) - float(a["x"])) * i / steps
		var y: float = float(a["y"]) + (float(b["y"]) - float(a["y"])) * i / steps
		if id == "out":
			for o: Array in _geometry["out"]["occluders"]:
				if x > float(o[0]) and x < float(o[2]) and y > float(o[1]) and y < float(o[3]):
					return false
		elif room != null:
			var tile := CampusGeometry.tile_at(room, Vector2(x, y))
			if tile == "#":
				return false
			if tile == "=":
				var c := int(floor((x - float(room["ox"])) / float(room["tw"])))
				var r := int(floor((y - float(room["oy"])) / float(room["th"])))
				if not door_open.call(id, c, r):
					return false
	return true


func door_at(p: Dictionary) -> String:
	var room: Variant = _rooms.get(p["scene"])
	if room == null:
		return ""
	var c := int(floor((float(p["x"]) - float(room["ox"])) / float(room["tw"])))
	var r := int(floor((float(p["y"]) - float(room["oy"])) / float(room["th"])))
	if r < 0 or r >= (room["grid"] as Array).size():
		return ""
	return "%s:%d:%d" % [room["id"], c, r] if String(room["grid"][r]).substr(c, 1) == "=" else ""


## The far end of the exit the player was seen using (no live position is leaked).
func observed_exit(from: String, to: String, seen: Dictionary) -> Dictionary:
	var best := {}
	var best_d := INF
	for e: Dictionary in edges:
		for pair: Array in [[e["a"], e["b"]], [e["b"], e["a"]]]:
			var a: Dictionary = nodes[pair[0]]
			var b: Dictionary = nodes[pair[1]]
			if a["scene"] != from or b["scene"] != to:
				continue
			if to == "out" and _rooms.has(from) and pair[1] != "out:" + String(_rooms[from]["host"]):
				continue
			var d := length(path(seen, a))
			if d < best_d:
				best_d = d
				best = b
	return best if is_finite(best_d) else {}


## Distance and first heading from a to b within `limit` units (navigation.js approach).
func approach(a: Dictionary, b: Dictionary, limit: float) -> Dictionary:
	if a["scene"] == b["scene"]:
		if Vector2(float(a["x"]) - float(b["x"]), float(a["y"]) - float(b["y"])).length() > limit:
			return {}
		return _metric(path(a, b), 0.0)
	var best := {}
	for e: Dictionary in edges:
		for pair: Array in [[e["a"], e["b"]], [e["b"], e["a"]]]:
			var x: Dictionary = nodes[pair[0]]
			var y: Dictionary = nodes[pair[1]]
			if x["scene"] != a["scene"] or y["scene"] != b["scene"]:
				continue
			if Vector2(float(a["x"]) - float(x["x"]), float(a["y"]) - float(x["y"])).length() + Vector2(float(b["x"]) - float(y["x"]), float(b["y"]) - float(y["y"])).length() > limit:
				continue
			var m := _metric(path(a, x), length(path(y, b)) + float(e["weight"]) * speed)
			if not m.is_empty() and (best.is_empty() or float(m["distance"]) < float(best["distance"])):
				best = m
	return best


func _metric(p: Array, extra: float) -> Dictionary:
	if p.is_empty():
		return {}
	var d := length(p) + extra
	if not is_finite(d):
		return {}
	return {"distance": d, "direction": p[mini(4, p.size() - 1)]}
