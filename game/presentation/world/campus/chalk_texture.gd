class_name ChalkTexture
extends RefCounted
## The hand-drawn chalk pictures of the marks (modules/chalk-marks/marks-fx.js, reference wd-fz.github.io@0bf508a):
## one 128 px picture per symbol, the strokes jittered and broken, each stroke drawn twice (an outer ring of grey
## chalk dust so the shape shows on a white wall, a white core so it shows in the dark), then grain: random
## specks rubbed out. Drawn here by hand on an Image (the old build used a canvas); the same symbols: x, up, right, left, o, tri, q, bar.

const SIZE := 128
const SYMBOLS := ["x", "up", "right", "left", "o", "tri", "q", "bar"]
static var _cache: Dictionary = {}


static func texture(sym: String) -> ImageTexture:
	if not _cache.has(sym):
		_cache[sym] = ImageTexture.create_from_image(image(sym))
	return _cache[sym]


static func image(sym: String) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	var seed_v := 0
	for ch in sym:
		seed_v = (seed_v * 31 + ch.unicode_at(0)) & 0x7fffffff
	rng.seed = seed_v
	var styles := [[Color(70.0 / 255.0, 72.0 / 255.0, 76.0 / 255.0, 0.55), 17.0], [Color(245.0 / 255.0, 243.0 / 255.0, 236.0 / 255.0, 0.95), 9.0]]
	for pass_i in 2:
		# Both passes use the same jitter, so the grey edge and the white core line up.
		rng.seed = seed_v
		_draw(img, sym, rng, styles[pass_i][0], float(styles[pass_i][1]), pass_i)
	# Grain: rub out random specks.
	rng.seed = seed_v + 1
	for i in 900:
		var a := 0.2 + rng.randf() * 0.7
		var x0 := int(rng.randf() * float(SIZE))
		var y0 := int(rng.randf() * float(SIZE))
		for dx in 1 + int(rng.randf() * 2.0):
			for dy in 1 + int(rng.randf() * 2.0):
				var x := x0 + dx
				var y := y0 + dy
				if x < SIZE and y < SIZE:
					var c := img.get_pixel(x, y)
					c.a *= 1.0 - a
					img.set_pixel(x, y, c)
	return img


static func _blend(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= SIZE or y >= SIZE:
		return
	var d := img.get_pixel(x, y)
	var a := c.a + d.a * (1.0 - c.a)
	if a <= 0.0:
		return
	var r := (c.r * c.a + d.r * d.a * (1.0 - c.a)) / a
	var g := (c.g * c.a + d.g * d.a * (1.0 - c.a)) / a
	var b := (c.b * c.a + d.b * d.a * (1.0 - c.a)) / a
	img.set_pixel(x, y, Color(r, g, b, a))


static func _stamp(img: Image, p: Vector2, w: float, c: Color, painted: Dictionary) -> void:
	var r := w / 2.0
	for y in range(int(p.y - r) - 1, int(p.y + r) + 2):
		for x in range(int(p.x - r) - 1, int(p.x + r) + 2):
			if Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(p) <= r:
				var key := y * SIZE + x
				if not painted.has(key):
					painted[key] = true
					_blend(img, x, y, c)


## A stroke along the points: one paint per pixel (a stroke is not darker where the stamps overlap).
static func _line(img: Image, pts: Array, rng: RandomNumberGenerator, c: Color, w: float) -> void:
	var jittered: Array = []
	for p: Vector2 in pts:
		jittered.append(p + Vector2(rng.randf() - 0.5, rng.randf() - 0.5) * 5.0)
	var painted := {}
	for i in range(jittered.size() - 1):
		var a: Vector2 = jittered[i]
		var b: Vector2 = jittered[i + 1]
		var steps := int(a.distance_to(b)) + 1
		for s in steps + 1:
			_stamp(img, a.lerp(b, float(s) / float(steps)), w, c, painted)


static func _arrow(img: Image, dir: int, rng: RandomNumberGenerator, c: Color, w: float) -> void:
	var pts: Array = [[Vector2(64, 108), Vector2(64, 22)], [Vector2(18, 64), Vector2(108, 64)], [Vector2(110, 64), Vector2(20, 64)]][dir]
	_line(img, pts, rng, c, w)
	var tip: Vector2 = pts[1]
	var b: Array = [[Vector2(36, 50), Vector2(92, 50)], [Vector2(80, 36), Vector2(80, 92)], [Vector2(48, 36), Vector2(48, 92)]][dir]
	_line(img, [b[0], tip, b[1]], rng, c, w)


static func _draw(img: Image, sym: String, rng: RandomNumberGenerator, c: Color, w: float, pass_i: int) -> void:
	match sym:
		"x":
			_line(img, [Vector2(24, 24), Vector2(104, 104)], rng, c, w)
			_line(img, [Vector2(104, 24), Vector2(24, 104)], rng, c, w)
		"up":
			_arrow(img, 0, rng, c, w)
		"right":
			_arrow(img, 1, rng, c, w)
		"left":
			_arrow(img, 2, rng, c, w)
		"o":
			var rx := 40.0 + (rng.randf() - 0.5) * 4.0
			var ry := 38.0 + (rng.randf() - 0.5) * 4.0
			var tilt := rng.randf() * 0.4
			var pts: Array = []
			for i in 61:
				var t := 0.2 + (TAU * 1.03 - 0.2) * float(i) / 60.0
				var p := Vector2(cos(t) * rx, sin(t) * ry)
				pts.append(Vector2(64, 64) + p.rotated(tilt))
			_line(img, pts, rng, c, w)
		"tri":
			_line(img, [Vector2(64, 18), Vector2(110, 104), Vector2(18, 104), Vector2(64, 18)], rng, c, w)
		"q":
			var arc: Array = []
			for i in 21:
				var t := PI * 1.1 + (PI * 2.35 - PI * 1.1) * float(i) / 20.0
				arc.append(Vector2(64, 46) + Vector2(cos(t), sin(t)) * 24.0)
			_line(img, arc, rng, c, w)
			_line(img, [Vector2(70, 70), Vector2(64, 82)], rng, c, w)
			var dot := {}
			_stamp(img, Vector2(64, 104), 8.0 if pass_i == 1 else 14.0, c, dot)
		"bar":
			_line(img, [Vector2(22, 22), Vector2(106, 22)], rng, c, w)
			_line(img, [Vector2(64, 22), Vector2(64, 106)], rng, c, w)
			_line(img, [Vector2(64, 62), Vector2(100, 62)], rng, c, w)
			_line(img, [Vector2(34, 58), Vector2(34, 106)], rng, c, w)
			_line(img, [Vector2(16, 106), Vector2(112, 106)], rng, c, w)
