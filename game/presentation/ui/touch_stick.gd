class_name TouchStick
extends Control

signal moved(value: Vector2)
var _finger := -1
var _value := Vector2.ZERO


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _finger == -1:
			_finger = event.index
			_update_value(event.position)
		elif not event.pressed and event.index == _finger:
			clear()
		accept_event()
	elif event is InputEventScreenDrag and event.index == _finger:
		_update_value(event.position)
		accept_event()


func _update_value(local_position: Vector2) -> void:
	_value = ((local_position - size * 0.5) / (size.x * 0.35)).limit_length()
	moved.emit(_value)
	queue_redraw()


func clear() -> void:
	_finger = -1
	_value = Vector2.ZERO
	moved.emit(_value)
	queue_redraw()


func _draw() -> void:
	var centre := size * 0.5
	var radius := minf(size.x, size.y) * 0.46
	var knob := centre + _value * radius * 0.56
	draw_circle(centre, radius, Color(UISkin.SHADE, 0.48), true, -1.0, true)
	draw_circle(centre, radius, Color(UISkin.ACCENT, 0.44), false, 1.5, true)
	for direction: Vector2 in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		draw_line(centre + direction * radius * 0.83, centre + direction * radius * 0.95,
			Color(UISkin.ACCENT, 0.6), 1.5, true)
	draw_circle(knob, radius * 0.37, Color(UISkin.ACCENT, 0.66 if _finger >= 0 else 0.44), true, -1.0, true)
