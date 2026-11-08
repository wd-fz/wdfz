class_name MapView
extends Control
## The handbook's map pages (exploration-map.js and ui.js renderMap): the walked-floor sketch of one
## room, or the campus plan. Drawn on a dark paper; only what was seen is inked.

const PAPER := Color("#14110e")
const DOT := Color(0.867, 0.835, 0.769, 0.07)
const WALL_FILL := Color("#3a342c")
const WALL_LINE := Color("#c2b596")
const FLOOR_A := Color("#272119")
const FLOOR_B := Color("#2a241c")
const TONES := {"route": Color("#e6dcc4"), "seal": Color("#e0675c"), "brass": Color("#e2bd6a"), "done": Color("#8fa28a"), "prop": Color("#9c9384")}
const MARKS := {"S": "梯", "J": "电", "L": "廊", "O": "出", "H": "藏", "T": "台", "K": "台", "D": "机", "Q": "服", "u": "书", "j": "门", "M": "售", "d": "桌", "f": "柜", "R": "架", "q": "柜", "k": "台", "N": "镜", "C": "仪", "Y": "球", "Z": "摆"}

var room: Dictionary = {}
var seen: PackedByteArray
var label_of: Callable           # (room, c, r) -> String, for the dynamic marks (open, locked, left behind)
var me := Vector2.ZERO           # world position and facing on this sketch
var ang := 0.0
var here := false
var cell := 12.0
var scroll_min_width := 480.0
var scroll_max_height := 400.0
## Overlays for the replay and the footprint map: {pts: PackedVector2Array (world), col: Color} polylines, {p: Vector2, r: float} dwell circles.
var trails: Array = []
var dwells: Array = []

# The campus plan.
var plan: Dictionary = {}        # {bound, objects, gates, me, ang}
var plan_scale := 0.4


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN


static func tone(mark: String) -> String:
	if mark == "留":
		return "brass"
	if mark == "锁" or mark == "×":
		return "seal"
	if mark == "✓" or mark == "开":
		return "done"
	if "梯电廊出".contains(mark):
		return "route"
	return "prop"


static func static_mark(ch: String) -> String:
	return String(MARKS.get(ch, ""))


## Floor sketch of one room.
func show_floor(r: Dictionary, bits: PackedByteArray, labeler: Callable, player: Vector2, facing: float, is_here: bool, avail: float = 460.0) -> void:
	room = r
	seen = bits
	label_of = labeler
	me = player
	ang = facing
	here = is_here
	plan = {}
	cell = clampf(floorf(avail / float(r["cols"])), 9.0, 22.0)
	custom_minimum_size = Vector2(float(r["cols"]) * cell, float(r["rows"]) * cell)
	_fit_scroll()
	queue_redraw()


func show_plan(p: Dictionary, avail: Vector2 = Vector2(440, 520)) -> void:
	room = {}
	plan = p
	var b: Dictionary = p["bound"]
	var bw := float(b["x1"]) - float(b["x0"])
	var bh := float(b["y1"]) - float(b["y0"])
	plan_scale = minf(avail.x / bw, avail.y / bh)
	custom_minimum_size = Vector2(roundf(bw * plan_scale), roundf(bh * plan_scale))
	_fit_scroll()
	queue_redraw()


## The scroll area follows the picture (a short floor does not leave a tall empty page).
func _fit_scroll() -> void:
	var sc := get_parent() as ScrollContainer
	if sc != null:
		sc.custom_minimum_size = Vector2(scroll_min_width, clampf(custom_minimum_size.y + 14.0, minf(120,scroll_max_height), scroll_max_height))


func _draw() -> void:
	if not plan.is_empty():
		_draw_plan()
		return
	if room.is_empty():
		return
	var cols := int(room["cols"])
	var rows := int(room["rows"])
	var grid: Array = room["grid"]
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	for gy in rows:
		for gx in cols:
			draw_rect(Rect2(gx * cell + cell / 2.0 - 0.5, gy * cell + cell / 2.0 - 0.5, 1, 1), DOT)
	var is_seen := func(c: int, r: int) -> bool: return c >= 0 and r >= 0 and c < cols and r < rows and seen[r * cols + c] != 0
	for r in rows:
		var row := String(grid[r])
		for c in cols:
			if not is_seen.call(c, r):
				continue
			if row.substr(c, 1) == "#":
				draw_rect(Rect2(c * cell, r * cell, cell, cell), WALL_FILL)
			else:
				draw_rect(Rect2(c * cell, r * cell, cell, cell), FLOOR_A if ((c + r) & 1) == 1 else FLOOR_B)
	var lw := maxf(1.5, cell / 8.0)
	for r in rows:
		var row2 := String(grid[r])
		for c in cols:
			if row2.substr(c, 1) != "#" or not is_seen.call(c, r):
				continue
			for d: Vector2i in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
				var nc := c + d.x
				var nr := r + d.y
				var wall_there := nc < 0 or nr < 0 or nc >= cols or nr >= rows or String(grid[nr]).substr(nc, 1) == "#"
				if wall_there or not is_seen.call(nc, nr):
					continue
				var x0 := c * cell
				var y0 := r * cell
				if d.y == -1:
					draw_line(Vector2(x0, y0), Vector2(x0 + cell, y0), WALL_LINE, lw)
				elif d.y == 1:
					draw_line(Vector2(x0, y0 + cell), Vector2(x0 + cell, y0 + cell), WALL_LINE, lw)
				elif d.x == -1:
					draw_line(Vector2(x0, y0), Vector2(x0, y0 + cell), WALL_LINE, lw)
				else:
					draw_line(Vector2(x0 + cell, y0), Vector2(x0 + cell, y0 + cell), WALL_LINE, lw)
	var font := get_theme_default_font()
	for r in rows:
		for c in cols:
			if not is_seen.call(c, r):
				continue
			var mark := String(label_of.call(room, c, r)) if label_of.is_valid() else ""
			if mark.is_empty():
				continue
			var t := tone(mark)
			var fs := roundi(cell * (0.62 if t == "prop" else 0.74))
			if t == "brass" or t == "seal":
				draw_rect(Rect2(c * cell + 1, r * cell + 1, cell - 2, cell - 2), Color(0.84, 0.69, 0.37, 0.22) if t == "brass" else Color(0.71, 0.2, 0.18, 0.28))
			var tw := font.get_string_size(mark, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, Vector2((c + 0.5) * cell - tw / 2.0, (r + 0.5) * cell + fs * 0.36), mark, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, TONES[t])
	for tr: Dictionary in trails:
		var pts := PackedVector2Array()
		for w: Vector2 in tr["pts"]:
			pts.append(Vector2((w.x - float(room["ox"])) / float(room["tw"]), (w.y - float(room["oy"])) / float(room["th"])) * cell)
		if pts.size() >= 2:
			draw_polyline(pts, tr["col"], 2.0)
	for dw: Dictionary in dwells:
		var dwp: Vector2 = dw["p"]
		var dp := Vector2((dwp.x - float(room["ox"])) / float(room["tw"]), (dwp.y - float(room["oy"])) / float(room["th"])) * cell
		draw_circle(dp, cell * (0.35 + minf(float(dw["r"]), 4.0) * 0.18), Color(0.85, 0.28, 0.24, 0.28))
	if here:
		var px := (me.x - float(room["ox"])) / float(room["tw"]) * cell
		var py := (me.y - float(room["oy"])) / float(room["th"]) * cell
		var L := maxf(9.0, cell * 0.9)
		var pts := PackedVector2Array([Vector2(px, py) + Vector2(cos(ang), sin(ang)) * L, Vector2(px, py) + Vector2(cos(ang + 2.45), sin(ang + 2.45)) * L * 0.62,
			Vector2(px, py) + Vector2(cos(ang - 2.45), sin(ang - 2.45)) * L * 0.62])
		draw_colored_polygon(pts, Color("#d9473e"))
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), PAPER, 2.0)


static func road_rects(data: Dictionary, sc: float) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var bound: Dictionary = data["bound"]
	for road: Array in data.get("roads",[]):
		out.append(Rect2((float(road[0])-float(bound["x0"]))*sc,(float(road[1])-float(bound["y0"]))*sc,(float(road[2])-float(road[0]))*sc,(float(road[3])-float(road[1]))*sc))
	return out


## Original UI.renderMap label placement. Text metrics are provided by the active font.
static func plan_labels(data: Dictionary, sc: float, extent: Vector2, measure: Callable) -> Array[Dictionary]:
	var labels: Array[Dictionary] = []
	var boxes: Array[Rect2] = []
	var used: Array[Rect2] = []
	var bound: Dictionary = data["bound"]
	var origin := Vector2(bound["x0"],bound["y0"])
	var at := func(x: float,y: float) -> Vector2: return (Vector2(x,y)-origin)*sc
	var clamp_label := func(p: Vector2,w: float) -> Vector2: return Vector2(clampf(p.x,3,extent.x-w-3),clampf(p.y,13,extent.y-4))
	for object: Dictionary in data["objects"]:
		if object["k"] == "roof": boxes.append(Rect2(at.call(object["x"],object["y"]),Vector2(object["w"],object["h"])*sc))
	for object: Dictionary in data["objects"]:
		if object["k"] != "roof" or float(object["w"])*sc<=34: continue
		var pos: Vector2 = at.call(object["x"],object["y"])+Vector2(3,12)
		var text := String(object["name"])
		var width: float = measure.call(text,10)
		labels.append({"text":text,"pos":pos,"size":10,"gate":false})
		used.append(Rect2(pos-Vector2(0,10),Vector2(width,10)))
	# Reserve gate labels before placing small buildings, as the source does.
	var gates: Array[Dictionary] = []
	for gate: Array in data["gates"]:
		var width: float = measure.call(gate[0],11)
		var pos: Vector2 = clamp_label.call(at.call(gate[1],gate[2])+Vector2(-11,-6),width)
		used.append(Rect2(pos-Vector2(0,11),Vector2(width,11)))
		gates.append({"text":gate[0],"pos":pos,"size":11,"gate":true})
	for object: Dictionary in data["objects"]:
		if object["k"] != "roof" or float(object["w"])*sc>34: continue
		var text := String(object.get("short",object["name"]))
		var width: float = measure.call(text,10)
		var own: Vector2 = at.call(object["x"],object["y"])
		var end := own+Vector2(object["w"],object["h"])*sc
		var candidates := [Vector2(end.x+3,own.y+12),Vector2(own.x,end.y+11),Vector2(own.x-width-3,own.y+12)]
		var best: Vector2 = candidates[0]
		var cost_best := 1000000
		for candidate: Vector2 in candidates:
			var pos: Vector2 = clamp_label.call(candidate,width)
			var rect := Rect2(pos-Vector2(0,10),Vector2(width,10))
			var cost := 0
			for other: Rect2 in used:
				if rect.intersects(other): cost += 10
			for building: Rect2 in boxes:
				if not building.position.is_equal_approx(own) and rect.intersects(building): cost += 1
			if cost<cost_best:
				cost_best = cost
				best = pos
		best = clamp_label.call(best,width)
		labels.append({"text":text,"pos":best,"size":10,"gate":false})
		used.append(Rect2(best-Vector2(0,10),Vector2(width,10)))
	labels.append_array(gates)
	return labels


func _draw_plan() -> void:
	var b: Dictionary = plan["bound"]
	var x0 := float(b["x0"])
	var y0 := float(b["y0"])
	var sc := plan_scale
	draw_rect(Rect2(Vector2.ZERO, size), Color("0d0b09"))
	draw_rect(Rect2(Vector2.ZERO, Vector2((float(b["x1"]) - x0) * sc, (float(b["y1"]) - y0) * sc)), Color(0.47, 0.71, 0.59, 0.35), false, 2.0)
	for road: Rect2 in road_rects(plan,sc): draw_rect(road,Color(150.0/255,160.0/255,150.0/255,.16))
	var font := get_theme_default_font()
	for o: Dictionary in plan["objects"]:
		var col := Color("#182420")
		match String(o["k"]):
			"roof":
				col = Color("#1c2a30")
			"field":
				col = Color("#16241b")
			"court":
				col = Color("#1a2427")
			"garden":
				col = Color("#17251e")
		var rect := Rect2((float(o["x"]) - x0) * sc, (float(o["y"]) - y0) * sc, float(o["w"]) * sc, float(o["h"]) * sc)
		draw_rect(rect, col)
		draw_rect(rect, Color(0.47, 0.71, 0.59, 0.3), false, 1.0)
	var measure := func(text: String,font_size: int) -> float: return font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	for label: Dictionary in plan_labels(plan,sc,custom_minimum_size,measure):
		draw_string(font,label["pos"],label["text"],HORIZONTAL_ALIGNMENT_LEFT,-1,label["size"],Color("c8a24a") if label["gate"] else Color(160.0/255,200.0/255,180.0/255,.62))
	for gate: Array in plan["gates"]:
		var gp := Vector2((float(gate[1])-x0)*sc,(float(gate[2])-y0)*sc)
		draw_rect(Rect2(gp-Vector2(2,2),Vector2(4,4)),Color("c8a24a"))
	var me_pos: Vector2 = plan["me"]
	var mp := Vector2((me_pos.x - x0) * sc, (me_pos.y - y0) * sc)
	var green := Color("#79c8a4")
	draw_circle(mp, 4.5, green)
	draw_line(mp, mp + Vector2(cos(float(plan["ang"])), sin(float(plan["ang"]))) * 16.0, Color(0.47, 0.78, 0.64, 0.75), 1.5)
