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

# The campus plan.
var plan: Dictionary = {}        # {bound, objects, gates, me, ang}
var plan_scale := 0.4


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
	custom_minimum_size = Vector2(bw * plan_scale, bh * plan_scale)
	_fit_scroll()
	queue_redraw()


## The scroll area follows the picture (a short floor does not leave a tall empty page).
func _fit_scroll() -> void:
	var sc := get_parent() as ScrollContainer
	if sc != null:
		sc.custom_minimum_size = Vector2(480, clampf(custom_minimum_size.y + 14.0, 120.0, 400.0))


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
	if here:
		var px := (me.x - float(room["ox"])) / float(room["tw"]) * cell
		var py := (me.y - float(room["oy"])) / float(room["th"]) * cell
		var L := maxf(9.0, cell * 0.9)
		var pts := PackedVector2Array([Vector2(px, py) + Vector2(cos(ang), sin(ang)) * L, Vector2(px, py) + Vector2(cos(ang + 2.45), sin(ang + 2.45)) * L * 0.62,
			Vector2(px, py) + Vector2(cos(ang - 2.45), sin(ang - 2.45)) * L * 0.62])
		draw_colored_polygon(pts, Color("#d9473e"))
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), PAPER, 2.0)


func _draw_plan() -> void:
	var b: Dictionary = plan["bound"]
	var x0 := float(b["x0"])
	var y0 := float(b["y0"])
	var sc := plan_scale
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.07, 0.08))
	draw_rect(Rect2(Vector2.ZERO, Vector2((float(b["x1"]) - x0) * sc, (float(b["y1"]) - y0) * sc)), Color(0.47, 0.71, 0.59, 0.35), false, 2.0)
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
	var placed: Array[Rect2] = []
	for o: Dictionary in plan["objects"]:
		if String(o["k"]) != "roof":
			continue
		var name := String(o["name"])
		var tw := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		var rect2 := Rect2((float(o["x"]) - x0) * sc, (float(o["y"]) - y0) * sc, float(o["w"]) * sc, float(o["h"]) * sc)
		var best := Vector2(rect2.position.x + 3.0, rect2.position.y + 12.0)
		if rect2.size.x <= tw + 6.0:
			# Narrow building: the name beside it, where it covers the least.
			var cands := [Vector2(rect2.end.x + 3.0, rect2.position.y + 12.0), Vector2(rect2.position.x, rect2.end.y + 11.0), Vector2(rect2.position.x - tw - 3.0, rect2.position.y + 12.0)]
			var cost_best := 1000000
			for cnd: Vector2 in cands:
				var p := Vector2(clampf(cnd.x, 3.0, size.x - tw - 3.0), clampf(cnd.y, 13.0, size.y - 4.0))
				var box := Rect2(p.x, p.y - 10.0, tw, 10.0)
				var cost := 0
				for u: Rect2 in placed:
					if u.intersects(box):
						cost += 10
				if cost < cost_best:
					cost_best = cost
					best = p
		var pos := Vector2(clampf(best.x, 3.0, size.x - tw - 3.0), clampf(best.y, 13.0, size.y - 4.0))
		draw_string(font, pos, name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.63, 0.78, 0.71, 0.75))
		placed.append(Rect2(pos.x, pos.y - 10.0, tw, 10.0))
	var gold := Color("#c8a24a")
	for g: Array in plan["gates"]:
		var gp := Vector2((float(g[1]) - x0) * sc, (float(g[2]) - y0) * sc)
		draw_rect(Rect2(gp - Vector2(2, 2), Vector2(4, 4)), gold)
		var gw := font.get_string_size(String(g[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(font, Vector2(clampf(gp.x - 11.0, 3.0, size.x - gw - 3.0), clampf(gp.y - 6.0, 13.0, size.y - 4.0)), String(g[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, gold)
	var me_pos: Vector2 = plan["me"]
	var mp := Vector2((me_pos.x - x0) * sc, (me_pos.y - y0) * sc)
	var green := Color("#79c8a4")
	draw_circle(mp, 4.5, green)
	draw_line(mp, mp + Vector2(cos(float(plan["ang"])), sin(float(plan["ang"]))) * 16.0, Color(0.47, 0.78, 0.64, 0.75), 1.5)
