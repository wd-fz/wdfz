class_name DutyRoster
extends Node3D
## The names on the duty roster (modules/campus-tales/duty.js, reference wd-fz.github.io@0bf508a):
## the roster by the blackboard of every classroom is rewritten with the assimilation tier (the assimilation
## value in steps of 20): tier 0 as it was; 1 your name in today's column; 2 on every day; 3 two of the three
## squares of every day; 4 and up only your name, in the same hand as the others. Your name looks like a
## name tag on the desk: you can tell it is a name, not which characters. No numbers on the wall.
## The old roster is baked into the room's geometry, so a new board is laid just in front of it.

const NAMES := ["王浩", "李欣然", "张一鸣", "陈思雨", "刘洋", "赵子涵", "周磊", "吴佳怡", "孙宇航", "郑晓", "黄俊杰", "林雨桐", "何静", "高翔", "马睿", "许诺"]
const DAYS := ["周一", "周二", "周三", "周四", "周五"]
const SIZE := Vector2i(384, 512)
## The board: 0.48 m wide, 0.64 m high, at 1.52 m, rows[0] + 0.75 from the north, on the front (west) wall.
const BOARD := Vector2(0.48, 0.64)

static var _cache: Dictionary = {}

var room: Dictionary = {}
var boards: Array[MeshInstance3D] = []
var tier := -1
var today := -1
var _busy := false


static func tier_of(tt: float) -> int:
	return clampi(floori(tt / 20.0), 0, 4)


static func is_mine(t: int, k: int, d: int, today_i: int) -> bool:
	return t >= 4 or (t == 3 and k < 2) or (t == 2 and k == 0) or (t == 1 and k == 0 and d == today_i)


func setup(r: Dictionary) -> void:
	room = r
	for i in ClassmatesModule.SPANS.size():
		var c0 := int(ClassmatesModule.SPANS[i][0])
		var wall := Vector2(float(r["ox"]) + c0 * float(r["tw"]), float(r["oy"]) + (7.0 + 0.75) * float(r["th"]))
		var s := CampusGeometry.to_scene(r, wall)
		var m := MeshInstance3D.new()
		m.name = "DutyRoster%d" % i
		var q := QuadMesh.new()
		q.size = BOARD
		m.mesh = q
		m.position = Vector3(s.x + 0.012, 1.52, s.y)
		m.rotation.y = PI * 0.5
		m.visible = false
		add_child(m)
		boards.append(m)


## Called every frame with the assimilation tier and the weekday (day - 1) % 5.
func update(t: int, today_i: int) -> void:
	if boards.is_empty() or (t == tier and today_i == today) or _busy:
		return
	tier = t
	today = today_i
	if t == 0:
		for b in boards:
			b.visible = false
		return
	_busy = true
	for i in boards.size():
		var tex: Texture2D = await texture(t, today_i, "duty%d:%d:%d" % [i, t, today_i])
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.roughness = 1.0
		boards[i].material_override = mat
		boards[i].visible = tier == t
	_busy = false


func texture(t: int, today_i: int, key: String) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var canvas := Sheet.new()
	canvas.size = Vector2(SIZE)
	canvas.t = t
	canvas.today = today_i
	canvas.key = key
	vp.add_child(canvas)
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


class Sheet extends Control:
	var t := 1
	var today := 0
	var key := ""

	func _lcg(seed: int) -> Callable:
		var state := [seed & 0xFFFFFFFF if seed != 0 else 1]
		return func() -> float:
			state[0] = (int(state[0]) * 1664525 + 1013904223) & 0xFFFFFFFF
			return float(state[0]) / 4294967296.0

	## Three joined strokes like a name tag: a name you cannot read.
	func _scribble(x: float, y: float, w: float, r: Callable, same: bool) -> void:
		var col := Color(0.11, 0.13, 0.27, 0.85)
		var lw := 2.2 if same else 2.6
		for k in 3:
			var ox := x + k * w / 3.0
			var pts := PackedVector2Array()
			var p0 := Vector2(ox + 2.0, y - 6.0 + float(r.call()) * 3.0)
			var c1 := Vector2(ox + 8.0, y - 12.0)
			var c2 := Vector2(ox + 12.0, y + 8.0)
			var p1 := Vector2(ox + w / 3.0 - 4.0, y - 2.0 + float(r.call()) * 3.0)
			for i in 13:
				var u := float(i) / 12.0
				pts.append(p0 * pow(1 - u, 3) + c1 * 3 * u * pow(1 - u, 2) + c2 * 3 * u * u * (1 - u) + p1 * pow(u, 3))
			draw_polyline(pts, col, lw, true)
			draw_line(Vector2(ox + 5.0, y + 4.0), Vector2(ox + w / 3.0 - 6.0, y - 8.0 + float(r.call()) * 4.0), col, lw, true)

	func _draw() -> void:
		var w := float(DutyRoster.SIZE.x)
		var h := float(DutyRoster.SIZE.y)
		var font := get_theme_default_font()
		var r := _lcg(key.length() * 97 + t * 13 + today)
		draw_rect(Rect2(0, 0, w, h), Color("#e7e2d3"))
		draw_rect(Rect2(0, 0, w, 64), Color("#3b6b47"))
		draw_string(font, Vector2(0, 44), "值 日 表", HORIZONTAL_ALIGNMENT_CENTER, w, 32, Color("#eef0e6"))
		draw_string(font, Vector2(0, 87), "扫地 · 拖地 · 擦黑板 · 倒垃圾", HORIZONTAL_ALIGNMENT_CENTER, w, 15, Color("#4a5a4a"))
		for d in 5:
			var yy := 102.0 + d * 78.0
			draw_rect(Rect2(16, yy, w - 32, 70), Color(0.23, 0.42, 0.28, 0.5), false, 1.2)
			draw_string(font, Vector2(26, yy + 42), DutyRoster.DAYS[d], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#3b6b47"))
			for k in 3:
				if DutyRoster.is_mine(t, k, d, today):
					_scribble(100.0 + k * 88.0, yy + 36.0, 78.0, r, t >= 4)
				else:
					var name := String(DutyRoster.NAMES[(key.length() * 5 + d * 3 + k) % DutyRoster.NAMES.size()])
					draw_string(font, Vector2(100.0 + k * 88.0 + float(r.call()) * 6.0, yy + 42.0 + (float(r.call()) - 0.5) * 5.0), name, HORIZONTAL_ALIGNMENT_LEFT, 82, 21, Color(0.11, 0.13, 0.27, 0.85))
