class_name PatrolSearch
extends RefCounted
## Bounded, deterministic search from observations. No player context is accepted here.
## Points stay in the observed scene; ordinary searches never guess a new floor or room.

const LIMIT := 4
const DEADLINE := 45.0


static func make(nav: PatrolNav, origin: Dictionary, heading: Array, memory: Dictionary, tier: int, seconds: float) -> Dictionary:
	var first := origin.duplicate()
	first["kind"] = "last_seen"
	var plan := {"points": [first], "index": 0, "arrived": false, "wait": 0.0, "ttl": DEADLINE, "tier": tier}
	var scene := String(origin["scene"])
	# These spaces have height-aware paths, but no planar search samples.
	if tier == 0 or scene in ["bell1", "lift_dream"] or nav.is_stairwell(scene):
		return plan
	var forward := Vector2(float(heading[0]), float(heading[1])).normalized()
	var radius := (3.0 + tier) / CampusGeometry.U2M
	var candidates: Array = []
	if not memory.is_empty():
		_candidate(candidates, nav, origin, memory, radius, forward, 4.0)
	# Building exits and stair/lift approaches are map knowledge, not the player's live route.
	for key: String in nav.nodes:
		var point: Dictionary = nav.nodes[key]
		if point["scene"] == scene:
			var exit := point.duplicate()
			exit["kind"] = "exit"
			_candidate(candidates, nav, origin, exit, radius, forward, 2.0)
	var base_angle := forward.angle() if forward.length_squared() > 0.0 else 0.0
	for offset: float in [0.0, PI * 0.5, -PI * 0.5, PI, PI * 0.25, -PI * 0.25, PI * 0.75, -PI * 0.75]:
		for reach: float in [radius, radius * 0.5]:
			var delta := Vector2.from_angle(base_angle + offset) * reach
			var sample := PatrolNav.point(scene, float(origin["x"]) + delta.x, float(origin["y"]) + delta.y, float(origin.get("fy", 0.0)))
			sample["kind"] = "corridor"
			_candidate(candidates, nav, origin, sample, radius, forward, 0.0)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
	var travel_budget := maxf(0.0, seconds - float(tier + 1)) * nav.speed
	var current := first
	var visited: Array = []
	for candidate: Dictionary in candidates:
		var point: Dictionary = candidate["point"]
		var ray := Vector2(float(point["x"]) - float(origin["x"]), float(point["y"]) - float(origin["y"])).normalized()
		if point["kind"] == "corridor" and visited.any(func(v: Vector2) -> bool: return ray.dot(v) > 0.85):
			continue
		var cost := nav.length(nav.path(current, point))
		if not is_finite(cost) or cost > travel_budget:
			continue
		plan["points"].append(point)
		visited.append(ray)
		travel_budget -= cost
		current = point
		if plan["points"].size() >= mini(LIMIT, tier + 1):
			break
	return plan


static func _candidate(out: Array, nav: PatrolNav, origin: Dictionary, raw: Dictionary, radius: float, heading: Vector2, priority: float) -> void:
	var scene := String(origin["scene"])
	var delta := Vector2(float(raw["x"]) - float(origin["x"]), float(raw["y"]) - float(origin["y"]))
	if delta.length() > radius or absf(float(raw.get("fy", 0.0)) - float(origin.get("fy", 0.0))) > 1.3:
		return
	var point := nav.snap(scene, raw)
	if point.is_empty():
		return
	delta = Vector2(float(point["x"]) - float(origin["x"]), float(point["y"]) - float(origin["y"]))
	if (delta.length() < 12.0 and raw["kind"] != "locker") or delta.length() > radius:
		return
	for entry: Dictionary in out:
		var old: Dictionary = entry["point"]
		if Vector2(float(old["x"]) - float(point["x"]), float(old["y"]) - float(point["y"])).length() < 12.0:
			return
	var distance := nav.length(nav.path(origin, point))
	if not is_finite(distance) or distance > radius * 1.5:
		return
	point["kind"] = raw["kind"]
	if raw["kind"] == "locker":
		point["c"] = raw["c"]
		point["r"] = raw["r"]
	out.append({"point": point, "score": priority + heading.dot(delta.normalized()) - distance / radius})


static func valid_point(point: Variant) -> bool:
	return point is Dictionary and point.get("scene") is String and not String(point["scene"]).is_empty() \
		and SaveSchema.number_in(point.get("x"), -1e7, 1e7) and SaveSchema.number_in(point.get("y"), -1e7, 1e7) \
		and SaveSchema.number_in(point.get("fy", 0.0), -2000.0, 2000.0)


static func valid_heading(value: Variant) -> bool:
	return value is Array and value.size() == 2 and SaveSchema.number_in(value[0], -1.0, 1.0) and SaveSchema.number_in(value[1], -1.0, 1.0)


static func valid_plan(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	if value.is_empty():
		return true
	var points: Variant = value.get("points")
	if not points is Array or points.is_empty() or points.size() > LIMIT:
		return false
	if not SaveSchema.is_integer(value.get("index"), 0, points.size() - 1) or not SaveSchema.is_integer(value.get("tier"), 0, 3) \
			or not value.get("arrived") is bool or not SaveSchema.number_in(value.get("wait"), 0.0, 15.0) or not SaveSchema.number_in(value.get("ttl"), 0.0, DEADLINE):
		return false
	for point: Variant in points:
		if not valid_point(point) or not point.get("kind") in ["last_seen", "corridor", "exit", "locker"]:
			return false
		if point["scene"] != points[0]["scene"] or absf(float(point.get("fy", 0.0)) - float(points[0].get("fy", 0.0))) > 1.3:
			return false
		if point["kind"] == "locker" and (not SaveSchema.is_integer(point.get("c"), 0, 1000) or not SaveSchema.is_integer(point.get("r"), 0, 1000)):
			return false
	return points[0]["kind"] == "last_seen"
