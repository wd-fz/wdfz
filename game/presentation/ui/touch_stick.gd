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
	draw_circle(size * 0.5, size.x * 0.46, Color(0.8, 0.87, 0.9, 0.12))
	draw_circle(size * 0.5, size.x * 0.46, Color(0.8, 0.87, 0.9, 0.45), false, 2.0)
	draw_circle(size * 0.5 + _value * size.x * 0.25, size.x * 0.17, Color(0.8, 0.87, 0.9, 0.65))
