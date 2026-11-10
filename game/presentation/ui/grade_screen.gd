class_name GradeScreen
extends Control
## The nine-grade result picture (modules/run-record/grade-screen.js): drawn on the spot — F chalk letters
## wiped on a blackboard, E a soaked report card stamped in blue "补考", D a file folder tagged "察看",
## C/B/A a report card with red pen, S/SS red school seals, SSS the school gate at dawn stamped "准予离校".
## The reveal runs 1.1 s (writing, circling, stamping); with reduced motion it draws the last frame at once;
## nothing flashes. About a third in, the grade's sound group plays (ui.grade.low / mid / high / top).

signal sound(band: String)

const RED := Color("#b5332f")
const DURATION := 1.1

var grade := "C"
var k := 1.0
var _t := 0.0
var _playing := false
var _fired := true
var silent := true
var reduced := false


func _init() -> void:
	custom_minimum_size = Vector2(560, 150)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_grade(letter: String, play_reveal: bool = true, mute: bool = false, reduce: bool = false) -> void:
	grade = letter
	silent = mute
	reduced = reduce
	_t = 0.0
	_fired = mute
	_playing = play_reveal and not reduce
	k = 0.0 if _playing else 1.0
	set_process(_playing)
	queue_redraw()


func _process(delta: float) -> void:
	if not _playing: return
	_t += delta
	k = minf(1.0, _t / DURATION)
	if not _fired and k >= 0.35:
		_fired = true
		sound.emit(ScoreRules.band(grade))
	if k >= 1.0:
		_playing = false
		set_process(false)
	queue_redraw()


func cancel() -> void:
	_playing = false
	_fired = true
	set_process(false)


static func _ease(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)


static func _rng(seed: int) -> Callable:
	var st := [maxi(1, seed % 2147483647)]
	return func() -> float:
		st[0] = (int(st[0]) * 16807) % 2147483647
		return float(int(st[0]) - 1) / 2147483646.0


func _grain(col: Color, n: int, seed: int) -> void:
	var r := _rng(seed)
	for i in n:
		draw_rect(Rect2(float(r.call()) * size.x, float(r.call()) * size.y, 1.0 + float(r.call()) * 1.5, 1.0 + float(r.call()) * 1.5), col)


func _paper(tint: Color = Color("#ddd5c2")) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), tint)
	_grain(Color(0.35, 0.27, 0.16, 0.06), int(size.x * size.y / 900.0), 11)
	var c := size / 2.0
	for i in 6:
		var rr := maxf(size.x, size.y) * (0.45 + 0.05 * i)
		draw_arc(c, rr, 0.0, TAU, 64, Color(0.16, 0.11, 0.06, 0.06), maxf(size.x, size.y) * 0.1)


func _lines(u: float) -> void:
	var y := 40.0 * u
	while y < size.y:
		draw_line(Vector2(30.0 * u, y), Vector2(size.x - 30.0 * u, y), Color(0.31, 0.43, 0.59, 0.22), 1.0 * u)
		y += 26.0 * u


func _letter(txt: String, x: float, y: float, px: float, col: Color, u: float, alpha: float = 1.0) -> void:
	var font := get_theme_default_font()
	var fs := roundi(px * u)
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(x - w / 2.0, y + fs * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col.r, col.g, col.b, col.a * alpha))


func _stamp(x: float, y: float, r: float, kk: float, col: Color, text: String, u: float, rot: float) -> void:
	var s := 1.0 + 0.5 * (1.0 - _ease(kk))
	var a := minf(1.0, kk * 1.6)
	draw_set_transform(Vector2(x, y), rot, Vector2(s, s))
	var c := Color(col.r, col.g, col.b, 0.9 * a)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, c, 4.0 * u, true)
	draw_arc(Vector2.ZERO, r * 0.8, 0.0, TAU, 48, c, 1.5 * u, true)
	var font := get_theme_default_font()
	var fs := roundi(r * 0.42)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(-w / 2.0, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _rect_stamp(x: float, y: float, w: float, h: float, kk: float, col: Color, text: String, u: float, rot: float) -> void:
	var s := 1.0 + 0.4 * (1.0 - _ease(kk))
	var a := minf(1.0, kk * 1.6)
	draw_set_transform(Vector2(x, y), rot, Vector2(s, s))
	var c := Color(col.r, col.g, col.b, 0.85 * a)
	draw_rect(Rect2(-w / 2.0, -h / 2.0, w, h), c, false, 3.0 * u)
	var font := get_theme_default_font()
	var fs := roundi(h * 0.55)
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(-tw / 2.0, fs * 0.35 + 1.0 * u), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw() -> void:
	# Nested responsive containers briefly allocate zero width during reflow.
	# Wait for layout before scaling text, stamps or the ruled-paper loop.
	if size.x < 16 or size.y < 16: return
	var W := size.x
	var H := size.y
	var u := minf(W / 640.0, H / 220.0)
	match grade:
		"F":
			draw_rect(Rect2(Vector2.ZERO, size), Color("#1c2420"))
			_grain(Color(0.86, 0.9, 0.86, 0.05), int(W * H / 500.0), 3)
			_letter("F", W / 2.0, H / 2.0, 150, Color(0.93, 0.93, 0.89, 0.85), u, clampf(k * 1.4, 0.0, 1.0))
			if k > 0.55:
				var e := _ease((k - 0.55) / 0.45)
				draw_rect(Rect2(W / 2.0 - 90.0 * u, H / 2.0 - 30.0 * u, 180.0 * u * e, 46.0 * u), Color(0.11, 0.14, 0.13, 0.5))
				draw_rect(Rect2(W / 2.0 - 96.0 * u, H / 2.0 - 34.0 * u, 200.0 * u * e, 54.0 * u), Color(0.86, 0.86, 0.82, 0.1))
		"E":
			_paper(Color("#d3cfc0"))
			for i in 5:
				var y := H * (0.15 + i * 0.18)
				draw_polyline(PackedVector2Array([Vector2(0, y), Vector2(W * 0.3, y - H * 0.03), Vector2(W * 0.6, y + H * 0.04), Vector2(W, y - H * 0.02)]), Color(0.24, 0.24, 0.2, 0.12), 2.0 * u)
			_letter("E", W * 0.36, H / 2.0, 130, Color(0.59, 0.16, 0.14, 0.8), u)
			_rect_stamp(W * 0.66, H * 0.52, 150.0 * u, 58.0 * u, k, Color("#2f4f8f"), "补 考", u, -0.16)
		"D":
			draw_rect(Rect2(Vector2.ZERO, size), Color("#7a5a38"))
			_grain(Color(0.12, 0.08, 0.04, 0.12), int(W * H / 600.0), 5)
			draw_polyline(PackedVector2Array([Vector2(0, 0), Vector2(W / 2.0, H * 0.55), Vector2(W, 0)]), Color(0.12, 0.08, 0.04, 0.45), 2.0 * u)
			_letter("D", W * 0.3, H * 0.62, 110, Color(0.11, 0.08, 0.05, 0.75), u)
			var x := W * 0.62 - 60.0 * u + (1.0 - _ease(k)) * W * 0.4
			var y2 := H * 0.5
			var a := minf(1.0, k * 1.5)
			draw_rect(Rect2(x, y2 - 22.0 * u, 170.0 * u, 44.0 * u), Color(0.91, 0.89, 0.82, a))
			draw_rect(Rect2(x + 4.0 * u, y2 - 18.0 * u, 162.0 * u, 36.0 * u), Color(RED, a), false, 2.0 * u)
			var font := get_theme_default_font()
			draw_string(font, Vector2(x + 28.0 * u, y2 + 9.0 * u), "察 看", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(24.0 * u), Color(RED, a))
		"C":
			_paper()
			_lines(u)
			_letter("C", W / 2.0, H / 2.0, 130, RED, u, clampf(k * 1.3, 0.0, 1.0))
			if k > 0.7:
				var e2 := clampf((k - 0.7) / 0.3, 0.0, 1.0)
				var p0 := Vector2(W / 2.0 + 78.0 * u, H / 2.0 + 10.0 * u)
				var p1 := Vector2(W / 2.0 + 92.0 * u, H / 2.0 + 26.0 * u)
				var p2 := Vector2(W / 2.0 + 118.0 * u, H / 2.0 - 14.0 * u)
				draw_polyline(PackedVector2Array([p0, p0.lerp(p1, minf(1.0, e2 * 2.0)), p1.lerp(p2, clampf(e2 * 2.0 - 1.0, 0.0, 1.0)) if e2 > 0.5 else p0.lerp(p1, minf(1.0, e2 * 2.0))]), RED, 4.0 * u)
		"B":
			_paper()
			_lines(u)
			_letter("B", W / 2.0, H / 2.0 - 6.0 * u, 130, RED, u, clampf(k * 1.4, 0.0, 1.0))
			if k > 0.6:
				var e3 := clampf((k - 0.6) / 0.4, 0.0, 1.0)
				for o in [0.0, 10.0]:
					draw_line(Vector2(W / 2.0 - 62.0 * u, H / 2.0 + 58.0 * u + o * u), Vector2(W / 2.0 - 62.0 * u + 124.0 * u * e3, H / 2.0 + 56.0 * u + o * u), RED, 3.0 * u)
		"A":
			_paper()
			_lines(u)
			_letter("A", W / 2.0, H / 2.0, 120, RED, u, minf(1.0, k * 2.0))
			draw_set_transform(Vector2(W / 2.0, H / 2.0), -0.2, Vector2(92.0 * u, 80.0 * u))
			draw_arc(Vector2.ZERO, 1.0, -1.2, -1.2 + TAU * _ease(k), 48, RED, 3.5 * u / (86.0 * u), true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			if k > 0.75:
				var a2 := (k - 0.75) / 0.25
				var pen := Color(0.16, 0.16, 0.24, 0.8 * a2)
				draw_polyline(PackedVector2Array([Vector2(W / 2.0 + 120.0 * u, H / 2.0 + 60.0 * u), Vector2(W / 2.0 + 140.0 * u, H / 2.0 + 30.0 * u), Vector2(W / 2.0 + 150.0 * u, H / 2.0 + 80.0 * u), Vector2(W / 2.0 + 175.0 * u, H / 2.0 + 50.0 * u),
					Vector2(W / 2.0 + 200.0 * u, H / 2.0 + 70.0 * u), Vector2(W / 2.0 + 225.0 * u, H / 2.0 + 55.0 * u)]), pen, 2.0 * u)
		"S":
			_paper(Color("#e2d8c0"))
			_letter("S", W * 0.4, H / 2.0, 130, Color(0.43, 0.12, 0.1, 0.85), u)
			_stamp(W * 0.62, H * 0.52, 64.0 * u, k, RED, "表 彰", u, -0.18)
		"SS":
			_paper(Color("#e8dcbc"))
			for i in 8:
				draw_circle(Vector2(W / 2.0, H / 2.0), W * 0.5 * (1.0 - i / 8.0), Color(1.0, 0.86, 0.59, 0.28 / 8.0))
			_letter("SS", W * 0.36, H / 2.0, 120, Color(0.43, 0.12, 0.1, 0.88), u)
			_stamp(W * 0.6, H * 0.55, 58.0 * u, minf(1.0, k * 1.5), RED, "保 送", u, -0.2)
			_stamp(W * 0.74, H * 0.45, 52.0 * u, maxf(0.0, (k - 0.35) / 0.65), RED, "保 送", u, 0.12)
		"SSS":
			var top := Color("#2b3550")
			var mid := Color("#c98a5a")
			var low := Color("#f1d3a0")
			for i in 24:
				var f := float(i) / 23.0
				var col := top.lerp(mid, f / 0.55) if f < 0.55 else mid.lerp(low, (f - 0.55) / 0.45)
				draw_rect(Rect2(0, H * float(i) / 24.0, W, H / 24.0 + 1.0), col)
			for i in 8:
				draw_circle(Vector2(W * 0.5, H * 0.86), W * 0.35 * (1.0 - i / 8.0), Color(1.0, 0.93, 0.75, 0.55 * _ease(k) / 8.0))
			var dark := Color("#1a1512")
			draw_rect(Rect2(0, H * 0.86, W, H * 0.14), dark)
			draw_rect(Rect2(W * 0.3, H * 0.32, 22.0 * u, H * 0.56), dark)
			draw_rect(Rect2(W * 0.7 - 22.0 * u, H * 0.32, 22.0 * u, H * 0.56), dark)
			draw_rect(Rect2(W * 0.28, H * 0.27, W * 0.44, 16.0 * u), dark)
			var gx := W * 0.3 + 40.0 * u
			while gx < W * 0.7 - 30.0 * u:
				var open := _ease(k) * W * 0.12 * (-1.0 if gx < W / 2.0 else 1.0)
				draw_line(Vector2(gx + open, H * 0.42), Vector2(gx + open, H * 0.86), dark, 3.0 * u)
				gx += 22.0 * u
			_letter("SSS", W * 0.5, H * 0.2, 52, Color(1.0, 0.96, 0.89, 0.92), u)
			_stamp(W * 0.82, H * 0.6, 50.0 * u, maxf(0.0, (k - 0.3) / 0.7), Color("#c0392b"), "准予离校", u, -0.16)
		_:
			_paper()
			_letter(grade, W / 2.0, H / 2.0, 130, RED, u)
