class_name TouchActionButton
extends Button
## BaseButton only handles the mouse emulated from the primary finger. Handle real
## touches as well, so actions work while another finger owns the stick or look pad.

var _finger := -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouse and event.device == -1:
		accept_event() # Real touch below owns activation; do not activate twice.
		return
	if event is InputEventScreenTouch:
		if event.pressed and not disabled and _finger == -1:
			_finger = event.index
			button_down.emit()
		accept_event()


func _input(event: InputEvent) -> void:
	if _finger < 0:
		return
	if not is_visible_in_tree() or disabled:
		cancel_touch()
		return
	if event is InputEventScreenTouch and event.index == _finger and not event.pressed:
		_finger = -1
		get_viewport().set_input_as_handled()
		button_up.emit()
		if not event.canceled and get_global_rect().has_point(event.position):
			if toggle_mode: button_pressed = not button_pressed
			pressed.emit()
	elif event is InputEventScreenDrag and event.index == _finger:
		get_viewport().set_input_as_handled()


func cancel_touch() -> void:
	if _finger >= 0:
		_finger = -1
		button_up.emit()
