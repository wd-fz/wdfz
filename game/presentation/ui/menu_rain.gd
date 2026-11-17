class_name MenuRain
extends Control
## Two short batches of 2D rain strokes over the cover. Update only while the menu is visible.

const STROKES := 72
const DRAW_INTERVAL := 0.05

var _time := 0.0
var _since_draw := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	resized.connect(queue_redraw)
	visibility_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	set_process(is_visible_in_tree())
	queue_redraw()


func _process(delta: float) -> void:
	_time = fposmod(_time + delta, 200.0)
	_since_draw += delta
	if _since_draw >= DRAW_INTERVAL:
		_since_draw = fposmod(_since_draw, DRAW_INTERVAL)
		queue_redraw()


func _draw() -> void:
	if not is_visible_in_tree() or size.y < 1.0: return
	var far := PackedVector2Array()
	var near := PackedVector2Array()
	for i in STROKES:
		var close := i % 4 == 0
		var fraction := fposmod(float(i) * 0.618034 + 0.29, 1.0)
		var speed := 0.64 if close else 0.38
		var y := fposmod(float(i) * 0.414214 + _time * speed, 1.09) - 0.04
		var start := Vector2(size.x * (0.46 + 0.56 * fraction) - y * size.y * 0.06, size.y * y)
		var length := size.y * (0.027 if close else 0.016)
		var end := start + Vector2(-length * 0.12, length)
		if close:
			near.append(start)
			near.append(end)
		else:
			far.append(start)
			far.append(end)
	draw_multiline(far, Color(0.60, 0.79, 0.92, 0.17), 1.0, true)
	draw_multiline(near, Color(0.76, 0.91, 1.0, 0.24), 1.0, true)
