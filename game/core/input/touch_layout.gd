class_name TouchLayout
extends RefCounted
## Every touch control placed on its own: centres as percentages of the view, a size per control (70–150 %) and one
## opacity for all. Sizes, safe edges and collisions are resolved for each viewport with the reference mobile.js
## clearance (8 px edges, nearest free position). Version 1 stored three groups (stick, actions, tools); they are
## migrated to the single controls they held.

const IDS := ["stick", "sprint", "interact", "manual", "torch", "hot1", "hot2"]
const LABELS := {"stick": "移动摇杆", "sprint": "奔跑", "interact": "交互", "manual": "手册", "torch": "手电", "hot1": "1", "hot2": "2"}
const BASE := {"stick": Vector2(160, 160), "sprint": Vector2(120, 58), "interact": Vector2(120, 58),
	"manual": Vector2(60, 48), "torch": Vector2(60, 48), "hot1": Vector2(60, 48), "hot2": Vector2(60, 48)}
## Smallest size on any screen: 44 px touch targets, a stick that can still be steered.
const MIN := {"stick": Vector2(100, 100), "sprint": Vector2(80, 44), "interact": Vector2(80, 44),
	"manual": Vector2(52, 44), "torch": Vector2(52, 44), "hot1": Vector2(52, 44), "hot2": Vector2(52, 44)}
## Default places: the version-1 group centres (percent) plus a pixel offset per control, scaled with the controls,
## so the tool row and the two action buttons stay evenly spaced on every screen width.
const DEFAULTS := {"stick": Vector2(20, 82), "sprint": Vector2(85, 82), "interact": Vector2(85, 82),
	"manual": Vector2(69, 20), "torch": Vector2(69, 20), "hot1": Vector2(69, 20), "hot2": Vector2(69, 20)}
const DEFAULT_OFFSET := {"stick": Vector2.ZERO, "sprint": Vector2(0, -35), "interact": Vector2(0, 35),
	"manual": Vector2(-105, 0), "torch": Vector2(-35, 0), "hot1": Vector2(35, 0), "hot2": Vector2(105, 0)}
const SIZE_LIMITS := [70, 150]
const OPACITY_LIMITS := [35, 100]
## Version-1 group members: offsets of each control's centre from the group centre, in percent of 1280 × 720.
const V1 := {"actions": {"sprint": Vector2(0, -4.9), "interact": Vector2(0, 4.9)},
	"tools": {"manual": Vector2(-8.2, 0), "torch": Vector2(-2.7, 0), "hot1": Vector2(2.7, 0), "hot2": Vector2(8.2, 0)}}


static func _num(v: Variant) -> bool:
	return (v is int or v is float) and is_finite(float(v))


## Keep only finite centres inside 0–100 %, sizes inside the limits and the opacity; migrate version-1 groups.
static func normalize(raw: Variant) -> Dictionary:
	var out := {}
	if not raw is Dictionary:
		return out
	var src: Dictionary = (raw as Dictionary).duplicate(true)
	for group: String in V1:
		var g: Variant = src.get(group)
		if g is Dictionary and _num(g.get("x")) and _num(g.get("y")):
			for id: String in V1[group]:
				if not src.has(id):
					var off: Vector2 = V1[group][id]
					src[id] = {"x": float(g.x) + off.x, "y": float(g.y) + off.y}
	for id: String in IDS:
		var p: Variant = src.get(id)
		if not p is Dictionary or not _num(p.get("x")) or not _num(p.get("y")):
			continue
		var e := {"x": clampf(float(p.x), 0, 100), "y": clampf(float(p.y), 0, 100)}
		if _num(p.get("s")):
			e["s"] = clampi(roundi(float(p.s)), SIZE_LIMITS[0], SIZE_LIMITS[1])
		out[id] = e
	if _num(src.get("opacity")):
		out["opacity"] = clampi(roundi(float(src.opacity)), OPACITY_LIMITS[0], OPACITY_LIMITS[1])
	return out


static func size_of(raw: Dictionary, id: String) -> int:
	var e: Variant = raw.get(id)
	return int(e.get("s", 100)) if e is Dictionary else 100


static func opacity(raw: Dictionary) -> float:
	return float(raw.get("opacity", 100)) / 100.0


static func resolve(view: Vector2, raw: Dictionary, percent: int, reserved: Array[Rect2] = []) -> Dictionary:
	var layout := normalize(raw)
	var bounds := Rect2(Vector2(8, 8), (view - Vector2(16, 16)).max(Vector2(44, 44)))
	var used: Array[Rect2] = reserved.duplicate()
	var out := {}
	for id: String in IDS:
		var extent: Vector2 = BASE[id] * clampf(percent / 100.0, .85, 1.25) * (float(size_of(layout, id)) / 100.0)
		# Very short viewports still reserve a useful view area. Buttons keep 44 px targets.
		extent *= minf(1.0, maxf(.5, (view.y - 92) / 300.0))
		extent = extent.max(MIN[id]).min(bounds.size)
		var at: Vector2 = DEFAULTS[id] * view / 100 + DEFAULT_OFFSET[id] * (extent.y / BASE[id].y)
		if layout.has(id):
			at = Vector2(float(layout[id].x), float(layout[id].y)) * view / 100
		var desired := _clamp(Rect2(at - extent * .5, extent), bounds)
		var rect := _nearest_clear(desired, bounds, used)
		out[id] = rect
		used.append(rect)
	return out


static func _clamp(rect: Rect2, bounds: Rect2) -> Rect2:
	return Rect2(rect.position.clamp(bounds.position, bounds.end - rect.size), rect.size)


static func _clear(rect: Rect2, used: Array[Rect2]) -> bool:
	for other: Rect2 in used:
		if rect.grow(4).intersects(other.grow(4)):
			return false
	return true


static func _nearest_clear(want: Rect2, bounds: Rect2, used: Array[Rect2]) -> Rect2:
	if _clear(want, used):
		return want
	var best := want
	var distance := INF
	for y in range(int(bounds.position.y), int(bounds.end.y - want.size.y) + 1, 8):
		for x in range(int(bounds.position.x), int(bounds.end.x - want.size.x) + 1, 8):
			var candidate := Rect2(Vector2(x, y), want.size)
			var d := candidate.position.distance_squared_to(want.position)
			if d < distance and _clear(candidate, used):
				distance = d
				best = candidate
	return best


## The resolved places written back as centres, keeping each control's size and the opacity.
static func centres(rects: Dictionary, view: Vector2, keep: Dictionary = {}) -> Dictionary:
	var out := {}
	for id: String in IDS:
		var p: Vector2 = (rects[id] as Rect2).get_center() / view * 100.0
		out[id] = {"x": p.x, "y": p.y}
		var e: Variant = keep.get(id)
		if e is Dictionary and e.has("s"):
			out[id]["s"] = e.s
	if keep.has("opacity"):
		out["opacity"] = keep.opacity
	return out


## Snap a centre (percent) to the editor grid.
static func snap(p: Vector2, step: float = 2.5) -> Vector2:
	return Vector2(roundf(p.x / step) * step, roundf(p.y / step) * step)
