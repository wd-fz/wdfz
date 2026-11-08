class_name TouchLook
extends Control
## Only actual touch events select the touch path. Mouse capture is independent.

signal looked(relative: Vector2)
var _finger := -1


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		clear()
		return
	if event is InputEventScreenTouch:
		if not event.pressed and event.index == _finger:
			clear()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _finger:
		looked.emit(event.relative)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	# Let GUI controls claim a new finger first. Once a look drag starts, keep it even
	# when that finger crosses a button; other fingers can still move or interact.
	if is_visible_in_tree() and event is InputEventScreenTouch and event.pressed \
		and _finger == -1 and get_global_rect().has_point(event.position):
		_finger = event.index
		get_viewport().set_input_as_handled()


func clear() -> void:
	_finger = -1
