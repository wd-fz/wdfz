class_name TouchScroll
extends ScrollContainer
## Scroll from cards and buttons as well as empty space. Use real finger events,
## independently of the platform's touchscreen hint and mouse emulation.
## Ranges, text editors and custom interactive views retain their own gestures.

const DRAG_THRESHOLD := 12.0
var _finger := -1
var _start := Vector2.ZERO
var _last := Vector2.ZERO
var _origin := Vector2.ZERO
var _dragging := false
var _velocity := Vector2.ZERO
var _last_time := 0
var _mouse_release: InputEventMouseButton


func _ready() -> void:
	follow_focus = true
	_watch(self)
	set_process(false)


func _watch(node: Node) -> void:
	if node != self:
		if node is Range or node is LineEdit or node is TextEdit or node is TouchScroll:
			return
		if node is BaseButton or node is Container:
			node.mouse_filter = Control.MOUSE_FILTER_PASS
	if not node.child_entered_tree.is_connected(_watch):
		node.child_entered_tree.connect(_watch)
	for child in node.get_children():
		_watch(child)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed and _finger == -1:
		_finger = event.index
		_start = get_global_transform() * event.position
		_last = _start
		_origin = Vector2(scroll_horizontal, scroll_vertical)
		_mouse_release = null
		_velocity = Vector2.ZERO
		set_process(false)
		_last_time = Time.get_ticks_usec()
		accept_event() # The innermost scroll area owns this gesture.
	elif event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		# The child button still receives its emulated click; don't also run the
		# engine's mouse-based touch scroller and apply the same movement twice.
		accept_event()
	elif event is InputEventMouseButton and event.pressed:
		_velocity = Vector2.ZERO
		set_process(false)


func _input(event: InputEvent) -> void:
	if _finger == -1 or not is_visible_in_tree():
		return
	# Godot may dispatch the emulated mouse-up BEFORE its ScreenTouch, whose
	# canceled flag decides whether this was a tap. Wait for that decision;
	# replay the release through the viewport so button focus is also cleared.
	if event is InputEventMouseButton and event.device == InputEvent.DEVICE_ID_EMULATION and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_mouse_release = event.duplicate()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenDrag and event.index == _finger:
		var delta: Vector2 = event.position - _start
		var axes := Vector2(1 if _horizontal() else 0, 1 if _vertical() else 0)
		if not _dragging and delta.length() >= DRAG_THRESHOLD:
			_dragging = true
			propagate_notification(Control.NOTIFICATION_SCROLL_BEGIN)
			scroll_started.emit()
		if _dragging:
			var now := Time.get_ticks_usec()
			var dt := maxf(.008, float(now - _last_time) / 1000000.0)
			_velocity = ((event.position - _last) * -axes / dt).limit_length(2400)
			_set_scroll(_origin - delta * axes)
			get_viewport().set_input_as_handled()
		_last = event.position
		_last_time = Time.get_ticks_usec()
	elif event is InputEventScreenTouch:
		if event.index == _finger and (not event.pressed or event.canceled):
			if event.canceled: propagate_notification(Control.NOTIFICATION_SCROLL_BEGIN)
			if event.canceled or Time.get_ticks_usec() - _last_time > 120000:
				_velocity = Vector2.ZERO
			_finish()
			set_process(_velocity.length() >= 5)
			_release_mouse()
		elif event.pressed and event.index != _finger:
			# A second finger cancels the pending click, without handing the
			# gesture to another row or firing an action under that finger.
			propagate_notification(Control.NOTIFICATION_SCROLL_BEGIN)
			_velocity = Vector2.ZERO
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _finger != -1 or _velocity.length() < 5.0:
		return
	var before := Vector2(scroll_horizontal, scroll_vertical)
	_set_scroll(before + _velocity * delta)
	_velocity *= exp(-8.0 * delta)
	if before.is_equal_approx(Vector2(scroll_horizontal, scroll_vertical)):
		_velocity = Vector2.ZERO
	if _velocity.length() < 5: set_process(false)


func _set_scroll(value: Vector2) -> void:
	if _horizontal(): scroll_horizontal = roundi(value.x)
	if _vertical(): scroll_vertical = roundi(value.y)


func _horizontal() -> bool:
	return horizontal_scroll_mode != SCROLL_MODE_DISABLED and get_h_scroll_bar().max_value > size.x


func _vertical() -> bool:
	return vertical_scroll_mode != SCROLL_MODE_DISABLED and get_v_scroll_bar().max_value > size.y


func _finish() -> void:
	_finger = -1
	if _dragging:
		_dragging = false
		propagate_notification(Control.NOTIFICATION_SCROLL_END)
		scroll_ended.emit()


func stop_motion() -> void:
	_velocity = Vector2.ZERO
	set_process(false)
	if _finger != -1: propagate_notification(Control.NOTIFICATION_SCROLL_BEGIN)
	_finish()
	_release_mouse()


func _release_mouse() -> void:
	if _mouse_release != null:
		if is_inside_tree(): get_viewport().push_input.call_deferred(_mouse_release, true)
		_mouse_release = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree() or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		stop_motion()
