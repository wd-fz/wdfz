class_name TouchLook
extends Control
## Only actual touch events select the touch path. Mouse capture is independent.

signal looked(relative: Vector2)
var _finger := -1


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		if event.pressed and _finger == -1 and get_global_rect().has_point(event.position):
			_finger = event.index
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _finger:
			clear()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _finger:
		looked.emit(event.relative)
		get_viewport().set_input_as_handled()


func clear() -> void:
	_finger = -1
