class_name PaperFlightPad
extends HBoxContainer
## Four original flight directions. Tracks each real finger independently, including cancel/drag-out.
var buttons: Dictionary = {}
var fingers: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_constant_override("separation",8)
	for spec: Array in [["l","◀"],["u","▲"],["d","▼"],["r","▶"]]:
		var button := Button.new()
		button.text = spec[1]
		button.custom_minimum_size = Vector2(58,52)
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.focus_mode = Control.FOCUS_NONE
		button.toggle_mode = true
		add_child(button)
		buttons[spec[0]] = button
	visibility_changed.connect(func() -> void: if not is_visible_in_tree(): clear())
	get_viewport().size_changed.connect(clear)
	get_window().focus_exited.connect(clear)

func value() -> Dictionary:
	var result := {"l":0.0,"r":0.0,"u":0.0,"d":0.0}
	for key: String in fingers.values():
		if result.has(key): result[key] = 1.0
	return result

func clear() -> void:
	fingers.clear()
	_paint()

func _paint() -> void:
	var state := value()
	for key: String in buttons: buttons[key].set_pressed_no_signal(state[key]>0)

func _at(point: Vector2) -> String:
	for key: String in buttons:
		if buttons[key].get_rect().has_point(point): return key
	return ""

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled: fingers[event.index] = _at(event.position)
		else: fingers.erase(event.index)
	elif event is InputEventScreenDrag and fingers.has(event.index):
		fingers[event.index] = _at(event.position)
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.device!=InputEvent.DEVICE_ID_EMULATION:
		if event.pressed: fingers[-1] = _at(event.position)
		else: fingers.erase(-1)
	elif event is InputEventMouseMotion and fingers.has(-1):
		fingers[-1] = _at(event.position)
	else: return
	_paint()
	accept_event()
