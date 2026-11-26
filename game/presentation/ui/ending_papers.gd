class_name EndingPapers
extends Control
## The physical objects seen after waking. Only confirmed evidence is passed to this view.
var _samples := ""
var _ticket := ""
const INK := Color("#323c37")
const BOARD := Color("#3d4947")
const PAPER := Color("#e5d9ba")
const PALE := Color("#e3ddce")


func set_evidence(evidence: Dictionary) -> void:
	_samples = evidence.get("sample", "")
	_ticket = evidence.get("ticket", "")
	visible = not _samples.is_empty() or not _ticket.is_empty()
	custom_minimum_size.y = (142 if not _samples.is_empty() else 0) + (117 if not _ticket.is_empty() else 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _caption(caption: String, x: float, y: float, width: float, color: Color, font_size: int) -> void:
	draw_string(get_theme_default_font(), Vector2(x, y), caption, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, color)


func _sheet(rect: Rect2, edge: String) -> void:
	var corners := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	var poly := PackedVector2Array()
	for i in 4:
		var start := corners[i]
		var finish := corners[(i + 1) % 4]
		poly.append(start)
		if edge != ["上边", "右边", "下边", "左边"][i]: continue
		var axis := start.direction_to(finish)
		var inside := Vector2(-axis.y, axis.x)
		var mid := start.lerp(finish, 0.5)
		for j in 13:
			var a := PI - j * PI / 12
			poly.append(mid + 8.0 * (axis * cos(a) + inside * sin(a)))
	draw_colored_polygon(poly, PAPER)


func _draw() -> void:
	var width := minf(size.x, 370)
	if width < 80: return
	var x := (size.x - width) / 2
	var y := 0.0
	if _samples != "":
		draw_rect(Rect2(x, y, width, 133), BOARD)
		_caption("北门岗亭  ·  封存纸样 四·二", x, y + 24, width, PALE, 16)
		for i in 2:
			var w := minf((width - 26) / 2, 101)
			var cx := x + width * (0.29 if i == 0 else 0.71)
			var rect := Rect2(cx - w / 2, y + 36, w, 66)
			_sheet(rect, "上边" if i == 0 and _samples == "甲" else "")
			_caption("甲" if i == 0 else "乙", rect.position.x, y + 79, w, INK, 20)
			if i == 0 and _samples == "甲":
				var chip := PackedVector2Array()
				for j in 13:
					var a := j * PI / 12 - 0.28
					chip.append(Vector2(cx - 19, y + 108) + 8 * Vector2(cos(a), sin(a)))
				draw_colored_polygon(chip, PAPER)
		_caption("配对表  ·  甲", x, y + 123, width, PALE, 14)
		y += 142
	if _ticket != "":
		draw_rect(Rect2(x, y, width, 110), BOARD)
		_caption("课桌下的复写联", x, y + 23, width, PALE, 16)
		var w := minf(width - 30, 229)
		var sheet_x := x + (width - w) / 2
		_sheet(Rect2(sheet_x, y + 34, w, 63), _ticket)
		_caption("点名联　姓名", sheet_x, y + 62, w, INK, 16)
		draw_line(Vector2(sheet_x + w * 0.24, y + 75), Vector2(sheet_x + w * 0.76, y + 75), INK, 1)
