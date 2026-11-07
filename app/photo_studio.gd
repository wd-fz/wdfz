class_name PhotoStudio
extends Node
## Composes a phone photo (camera.js capture): the lens image shrunk to 192×108, the flash (or a dark
## veil), the one extra thing that exists only in photos, a little noise and the clock stamp. Drawn on a
## small SubViewport so text and shapes use the project's font; returns the finished image.


class Canvas extends Control:
	var base: Texture2D
	var plan: Dictionary = {}
	var stamp := ""

	func _lcg(seed: int) -> Callable:
		var state := [seed & 0xFFFFFFFF if seed != 0 else 7]
		return func() -> float:
			state[0] = (int(state[0]) * 1664525 + 1013904223) & 0xFFFFFFFF
			return float(state[0]) / 4294967296.0

	func _person(x: float, y: float, h: float, a: float) -> void:
		var col := Color(0.04, 0.04, 0.05, a)
		draw_circle(Vector2(x, y - h * 0.86), h * 0.09, col)
		draw_rect(Rect2(x - h * 0.11, y - h * 0.76, h * 0.22, h * 0.46), col)
		draw_rect(Rect2(x - h * 0.085, y - h * 0.3, h * 0.07, h * 0.3), col)
		draw_rect(Rect2(x + h * 0.015, y - h * 0.3, h * 0.07, h * 0.3), col)

	func _draw() -> void:
		var w := float(CameraModule.W)
		var h := float(CameraModule.H)
		draw_rect(Rect2(0, 0, w, h), Color("#16181a"))
		if base != null:
			draw_texture_rect(base, Rect2(0, 0, w, h), false)
		if bool(plan.get("flash", true)):
			for i in 8:
				var k := float(i) / 8.0
				draw_circle(Vector2(w / 2.0, h / 2.0), w * 0.6 * (1.0 - k), Color(1.0, 0.99, 0.94, 0.38 / 8.0))
		else:
			draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.42))
		var r := _lcg(int(plan.get("seed", 7)))
		var font := get_theme_default_font()
		match String(plan.get("kind", "")):
			"figure":
				_person(w * (0.3 + 0.4 * float(r.call())), h * 0.86, h * 0.55, 0.62)
			"behind":
				_person(w * 0.86, h * 1.12, h * 1.25, 0.7)
			"crowd":
				for i in 9:
					_person(w * (0.08 + i * 0.105) + float(r.call()) * 4.0, h * (0.9 + 0.05 * float(r.call())), h * (0.42 + 0.08 * float(r.call())), 0.5)
			"seated":
				for j in 6:
					_person(w * (0.12 + j * 0.15), h * 0.78, h * 0.36, 0.48)
			"eyes":
				var y0 := h * (0.42 + 0.05 * float(r.call()))
				for k in 7:
					var x0 := w * (0.1 + k * 0.13) + float(r.call()) * 5.0
					draw_rect(Rect2(x0, y0, 2, 1.4), Color(0.92, 0.91, 0.84, 0.85))
					draw_rect(Rect2(x0 + 5, y0, 2, 1.4), Color(0.92, 0.91, 0.84, 0.85))
			"face":
				var fx := w * (0.35 + 0.3 * float(r.call()))
				var fy := h * 0.38
				draw_set_transform(Vector2(fx, fy), 0.0, Vector2(10.0, 13.0))
				draw_circle(Vector2.ZERO, 1.0, Color(0.84, 0.82, 0.76, 0.55))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				draw_rect(Rect2(fx - 5, fy - 3, 3, 2), Color(0.04, 0.04, 0.05))
				draw_rect(Rect2(fx + 2, fy - 3, 3, 2), Color(0.04, 0.04, 0.05))
				draw_rect(Rect2(fx - 3, fy + 5, 6, 1.5), Color(0.04, 0.04, 0.05))
			"hands":
				for m in 3:
					var hx := w * (0.25 + m * 0.22)
					var hy := h * 0.82
					draw_rect(Rect2(hx, hy, 12, 7), Color(0.82, 0.8, 0.75, 0.6))
					for n in 4:
						draw_rect(Rect2(hx + n * 3, hy - 7 - (n % 2) * 2, 2, 8), Color(0.82, 0.8, 0.75, 0.6))
			"text":
				draw_string(font, Vector2(0, h * 0.45), String(plan.get("text", "")), HORIZONTAL_ALIGNMENT_CENTER, w, 15, Color(0.84, 0.82, 0.76, 0.7))
		var n := _lcg(int(plan.get("noise", 3)))
		for i in 260:
			draw_rect(Rect2(float(n.call()) * w, float(n.call()) * h, 1, 1), Color(1, 1, 1, 0.06))
		draw_string(font, Vector2(0, h - 5), stamp, HORIZONTAL_ALIGNMENT_RIGHT, w - 5.0, 10, Color(1.0, 0.75, 0.35, 0.85))


## lens: the screen image (without the interface). Returns the finished image, or null when nothing was drawn.
func compose(lens: Image, plan: Dictionary) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(CameraModule.W, CameraModule.H)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var canvas := Canvas.new()
	canvas.size = Vector2(CameraModule.W, CameraModule.H)
	if lens != null and not lens.is_empty():
		canvas.base = ImageTexture.create_from_image(lens)
	canvas.plan = plan
	canvas.stamp = String(plan.get("stamp", ""))
	vp.add_child(canvas)
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return img
