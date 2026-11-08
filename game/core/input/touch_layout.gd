class_name TouchLayout
extends RefCounted
## Persist centres as percentages; resolve sizes, safe edges and collisions for each viewport.
## Uses the reference mobile.js layout's 8 px clearance and nearest free-position search.

const IDS := ["stick", "actions", "tools"]
const BASE := {"stick": Vector2(160,160), "actions": Vector2(120,124), "tools": Vector2(252,48)}
const DEFAULTS := {"stick": Vector2(20,82), "actions": Vector2(85,82), "tools": Vector2(69,20)}


static func normalize(raw: Variant) -> Dictionary:
	var out := {}
	if not raw is Dictionary:
		return out
	for id: String in IDS:
		var p: Variant = raw.get(id)
		if p is Dictionary and (p.get("x") is float or p.get("x") is int):
			if not (p.get("y") is int or p.get("y") is float):
				continue
			if is_finite(float(p.x)) and is_finite(float(p.y)):
				out[id] = {"x": clampf(float(p.x),0,100), "y": clampf(float(p.y),0,100)}
	return out


static func resolve(view: Vector2, raw: Dictionary, percent: int, reserved: Array[Rect2] = []) -> Dictionary:
	var layout := normalize(raw)
	var bounds := Rect2(Vector2(8,8), (view-Vector2(16,16)).max(Vector2(44,44)))
	var used: Array[Rect2] = reserved.duplicate()
	var out := {}
	for id: String in IDS:
		var extent: Vector2 = BASE[id] * clampf(percent/100.0,.85,1.25)
		# Very short viewports still reserve a useful view area. Buttons keep 44 px targets.
		extent *= minf(1.0,maxf(.5,(view.y-92)/300.0))
		if id == "stick":
			extent = extent.max(Vector2(100,100))
		elif id == "actions":
			extent = extent.max(Vector2(80,96))
		else:
			extent = extent.max(Vector2(224,44))
		extent = extent.min(bounds.size)
		var centre: Vector2 = DEFAULTS[id]
		if layout.has(id):
			centre = Vector2(float(layout[id].x),float(layout[id].y))
		var desired := _clamp(Rect2(centre*view/100-extent*.5,extent),bounds)
		var rect := _nearest_clear(desired,bounds,used)
		out[id] = rect
		used.append(rect)
	return out


static func _clamp(rect: Rect2, bounds: Rect2) -> Rect2:
	return Rect2(rect.position.clamp(bounds.position,bounds.end-rect.size),rect.size)


static func _clear(rect: Rect2, used: Array[Rect2]) -> bool:
	for other: Rect2 in used:
		if rect.grow(4).intersects(other.grow(4)):
			return false
	return true


static func _nearest_clear(want: Rect2, bounds: Rect2, used: Array[Rect2]) -> Rect2:
	if _clear(want,used):
		return want
	var best := want
	var distance := INF
	for y in range(int(bounds.position.y),int(bounds.end.y-want.size.y)+1,8):
		for x in range(int(bounds.position.x),int(bounds.end.x-want.size.x)+1,8):
			var candidate := Rect2(Vector2(x,y),want.size)
			var d := candidate.position.distance_squared_to(want.position)
			if d < distance and _clear(candidate,used):
				distance = d
				best = candidate
	return best


static func centres(rects: Dictionary, view: Vector2) -> Dictionary:
	var out := {}
	for id: String in IDS:
		var p: Vector2 = (rects[id] as Rect2).get_center()/view*100.0
		out[id] = {"x": p.x, "y": p.y}
	return out
