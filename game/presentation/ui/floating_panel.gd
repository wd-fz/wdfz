class_name FloatingPanel
extends PanelContainer
## A bounded, draggable tool window. Only the window itself intercepts input; the rest of
## the game remains interactive. The collapsed state draws a small dot with a larger touch target.

signal dismissed
signal collapsed_changed(collapsed: bool)

var collapsed := false
var compact := false
var heading: Label
var _frame: VBoxContainer
var _scroll: ScrollContainer
var _body: Control
var _dot: Control
var _pointer := -2
var _dragging := false
var _press := Vector2.ZERO
var _start := Vector2.ZERO
var _window_position := Vector2(24, 80)
var _dot_position := Vector2(-1, -1)
var _placed := false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	var back := UISkin.panel(8)
	add_theme_stylebox_override("panel",back)
	_frame = VBoxContainer.new()
	_frame.add_theme_constant_override("separation",6)
	add_child(_frame)
	var bar := HBoxContainer.new()
	heading = Label.new()
	heading.text = "开发工具 · 拖动标题移动"
	heading.clip_text = true
	heading.mouse_filter = Control.MOUSE_FILTER_STOP
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.custom_minimum_size.y = 40
	heading.gui_input.connect(_drag_input.bind(false))
	bar.add_child(heading)
	var collapse := Button.new()
	collapse.name = "Collapse"
	collapse.text = "•"
	collapse.tooltip_text = "收起为悬浮球"
	collapse.custom_minimum_size = Vector2(44,40)
	collapse.pressed.connect(func() -> void: set_collapsed(true))
	bar.add_child(collapse)
	var close := Button.new()
	close.name = "CloseWindow"
	close.text = "×"
	close.custom_minimum_size = Vector2(44,40)
	close.pressed.connect(dismiss)
	bar.add_child(close)
	_frame.add_child(bar)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_frame.add_child(_scroll)
	_dot = Control.new()
	_dot.custom_minimum_size = Vector2(44,44)
	_dot.mouse_filter = Control.MOUSE_FILTER_STOP
	_dot.tooltip_text = "开发工具 · 轻点展开，拖动移动"
	_dot.draw.connect(func() -> void:
		_dot.draw_circle(_dot.size*.5,7.0,UISkin.ACCENT)
		_dot.draw_circle(_dot.size*.5,8.5,Color(.05,.06,.08,.9),false,2))
	_dot.gui_input.connect(_drag_input.bind(true))
	add_child(_dot)
	_dot.hide()
	visibility_changed.connect(_visibility)


func set_body(body: Control) -> void:
	_body = body
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(body)


func _ready() -> void:
	get_viewport().size_changed.connect(refit)
	refit()


func _visibility() -> void:
	_pointer = -2
	_dragging = false
	if visible and is_inside_tree():
		refit()


func _drag_input(ev: InputEvent, dot: bool) -> void:
	var begin := false
	var end := false
	var point := Vector2.ZERO
	var index := -1
	if ev is InputEventMouse:
		if ev.device == -1:
			return
		point = get_global_mouse_position()
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			begin = ev.pressed
			end = not ev.pressed
	elif ev is InputEventScreenTouch:
		index = ev.index
		point = (_dot if dot else heading).get_global_transform() * ev.position
		begin = ev.pressed
		end = not ev.pressed
	elif ev is InputEventScreenDrag:
		index = ev.index
		point = (_dot if dot else heading).get_global_transform() * ev.position
	else:
		return
	if begin and _pointer == -2:
		_pointer = index
		_press = point
		_start = position
		_dragging = false
	if index != _pointer:
		return
	if point.distance_to(_press) > 5:
		_dragging = true
	if _dragging:
		position = _bounded(_start+point-_press, size*scale)
		if collapsed:
			_dot_position = position
		else:
			_window_position = position
	if end:
		_pointer = -2
		if dot and not _dragging:
			set_collapsed(false)
	accept_event()


func _bounded(pos: Vector2, extent: Vector2) -> Vector2:
	var viewport := get_viewport_rect().size
	return Vector2(clampf(pos.x,8,maxf(8,viewport.x-extent.x-8)),clampf(pos.y,8,maxf(8,viewport.y-extent.y-8)))


func refit() -> void:
	if not is_inside_tree():
		return
	var viewport := get_viewport_rect().size
	compact = DisplayServer.is_touchscreen_available() or viewport.x < 900 or viewport.y < 600
	add_theme_font_size_override("font_size",14 if compact else 16)
	if collapsed:
		scale = Vector2.ONE
		custom_minimum_size = Vector2(60,60)
		size = Vector2(60,60)
		position = _bounded(_dot_position if _dot_position.x >= 0 else _window_position,size)
	else:
		scale = Vector2.ONE * (.86 if compact else 1.0)
		custom_minimum_size = Vector2.ZERO
		size = Vector2(minf(570,(viewport.x-16)/scale.x),minf(570,(viewport.y-16)/scale.y))
		if not _placed:
			_window_position = Vector2(viewport.x-size.x*scale.x-24,72)
			_placed = true
		position = _bounded(_window_position,size*scale)
	queue_sort()


func set_collapsed(value: bool) -> void:
	if collapsed == value:
		return
	if value:
		_window_position = position
		_dot_position = position
	else:
		_dot_position = position
	collapsed = value
	_frame.visible = not value
	_dot.visible = value
	# A dot has no rectangular window background.
	var panel := get_theme_stylebox("panel") as StyleBoxFlat
	panel.bg_color.a = 0.0 if value else .97
	refit()
	collapsed_changed.emit(value)


func dismiss() -> void:
	hide()
	_pointer = -2
	dismissed.emit()
