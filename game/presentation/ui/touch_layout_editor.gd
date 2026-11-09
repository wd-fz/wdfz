class_name TouchLayoutEditor
extends Control
## A full-size preview of every touch control. Drag one to move it; the selected control's size and the
## controls' opacity are set in the top bar; the grid snaps centres to 2.5 %. Dragging edits a copy; only Done persists it.

signal saved(layout: Dictionary)
signal cancelled
const ACCENT := Color("8ce0cc")
const INK := Color("e9f0f4")
var layout: Dictionary = {}
var percent := 100
var selected := "stick"
var snap_on := true
var _handles := {}
var _pointer := -2
var _active := ""
var _offset := Vector2.ZERO
var _rects := {}
var _buttons: HBoxContainer
var _bar: HFlowContainer
var _size_slider: HSlider
var _size_label: Label
var _alpha_slider: HSlider
var _snap: Button
var _grid: Control


func _ready() -> void:
	name = "TouchLayoutEditor"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	layout = TouchLayout.normalize(layout)
	var back := ColorRect.new()
	back.color = Color(.03, .04, .06, .9)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	_grid = Control.new()
	_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.draw.connect(_draw_grid)
	add_child(_grid)
	for id: String in TouchLayout.IDS:
		var h := Panel.new()
		h.name = id.capitalize() + "Handle"
		var label := Label.new()
		label.text = TouchLayout.LABELS[id]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_color_override("font_color", INK)
		h.add_child(label)
		add_child(h)
		h.gui_input.connect(_drag.bind(id))
		_handles[id] = h
	_bar = HFlowContainer.new()   # wraps on narrow screens so every button stays reachable
	_bar.name = "EditorBar"
	_bar.add_theme_constant_override("h_separation", 10)
	_bar.add_theme_constant_override("v_separation", 6)
	add_child(_bar)
	_size_label = Label.new()
	_size_label.custom_minimum_size.x = 150
	_bar.add_child(_size_label)
	_size_slider = _slider(TouchLayout.SIZE_LIMITS[0], TouchLayout.SIZE_LIMITS[1], 5)
	_size_slider.name = "SizeSlider"
	_size_slider.value_changed.connect(func(v: float) -> void:
		var e: Dictionary = layout.get(selected, {})
		if e.is_empty():
			var c: Vector2 = (_rects[selected] as Rect2).get_center() / get_viewport_rect().size * 100.0
			e = {"x": c.x, "y": c.y}
		e["s"] = int(v)
		layout[selected] = e
		_refit())
	_bar.add_child(_size_slider)
	var alpha_label := Label.new()
	alpha_label.text = "透明度"
	_bar.add_child(alpha_label)
	_alpha_slider = _slider(TouchLayout.OPACITY_LIMITS[0], TouchLayout.OPACITY_LIMITS[1], 5)
	_alpha_slider.name = "OpacitySlider"
	_alpha_slider.value_changed.connect(func(v: float) -> void:
		layout["opacity"] = int(v)
		_refit())
	_bar.add_child(_alpha_slider)
	_snap = Button.new()
	_snap.name = "snap"
	_snap.toggle_mode = true
	_snap.custom_minimum_size = Vector2(96, 44)
	_snap.toggled.connect(func(on: bool) -> void:
		snap_on = on
		_snap.text = "网格吸附：开" if on else "网格吸附：关"
		_grid.queue_redraw())
	_bar.add_child(_snap)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 8)
	for spec: Array in [["恢复默认", "reset"], ["取消", "cancel"], ["完成", "done"]]:
		var b := Button.new()
		b.text = spec[0]
		b.name = spec[1]
		b.custom_minimum_size = Vector2(84, 44)
		b.pressed.connect(func() -> void:
			match spec[1]:
				"reset":
					layout = {}
					_refit()
				"cancel": cancelled.emit()
				"done": saved.emit(TouchLayout.normalize(layout))
			)
		_buttons.add_child(b)
	_bar.add_child(_buttons)
	_snap.button_pressed = snap_on
	_snap.text = "网格吸附：开"
	get_viewport().size_changed.connect(_resized)
	_refit()


func _slider(lo: int, hi: int, step: int) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(130, 44)
	return s


func _resized() -> void:
	_pointer = -2
	_active = ""
	_refit()


func _style(id: String, on: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(.13, .2, .26, .82) if id != "stick" else Color(.8, .87, .9, .12)
	style.border_color = ACCENT if on else Color(.6, .74, .82, .8)
	style.set_border_width_all(3 if on else 2)
	var rect: Rect2 = _rects.get(id, Rect2(0, 0, 60, 60))
	style.set_corner_radius_all(int(rect.size.x * .5) if id == "stick" else 12)
	return style


func _refit() -> void:
	if not is_node_ready():
		return
	var view := get_viewport_rect().size
	# The bar sits in the band reserved for the status line, where no control may go.
	_bar.position = Vector2(8, 10)
	_bar.size = Vector2(view.x - 16, 0)
	_rects = TouchLayout.resolve(view, layout, percent, [Rect2(0, 0, view.x, 68)])
	var alpha := TouchLayout.opacity(layout)
	for id: String in TouchLayout.IDS:
		var rect: Rect2 = _rects[id]
		var h: Panel = _handles[id]
		h.position = rect.position
		h.size = rect.size
		h.add_theme_stylebox_override("panel", _style(id, id == selected))
		h.modulate.a = maxf(alpha, .5) if id != selected else 1.0
	_size_label.text = "%s 大小 %d%%" % [TouchLayout.LABELS[selected], TouchLayout.size_of(layout, selected)]
	_size_slider.set_value_no_signal(TouchLayout.size_of(layout, selected))
	_alpha_slider.set_value_no_signal(int(alpha * 100.0))
	_grid.queue_redraw()


func _draw_grid() -> void:
	if not snap_on:
		return
	var view := get_viewport_rect().size
	var c := Color(.55, .7, .8, .07)
	for i in range(0, 41):
		var x := view.x * i / 40.0
		var y := view.y * i / 40.0
		_grid.draw_line(Vector2(x, 68), Vector2(x, view.y), c)
		if y >= 68:
			_grid.draw_line(Vector2(0, y), Vector2(view.x, y), c)


func select(id: String) -> void:
	selected = id
	_refit()


func _drag(event: InputEvent, id: String) -> void:
	var begin := false
	var end := false
	var point := Vector2.ZERO
	var index := -1
	if event is InputEventMouse:
		if event.device == -1:
			return
		point = get_global_mouse_position()
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			begin = event.pressed
			end = not event.pressed
	elif event is InputEventScreenTouch:
		index = event.index
		point = (_handles[id] as Control).get_global_transform() * event.position
		begin = event.pressed
		end = not event.pressed
	elif event is InputEventScreenDrag:
		index = event.index
		point = (_handles[id] as Control).get_global_transform() * event.position
	else:
		return
	if begin and _pointer == -2:
		_pointer = index
		_active = id
		selected = id
		_offset = point - (_rects[id] as Rect2).get_center()
	if _pointer != index or _active != id:
		return
	var centre := (point - _offset) / get_viewport_rect().size * 100
	if snap_on:
		centre = TouchLayout.snap(centre)
	var e: Dictionary = layout.get(id, {})
	e["x"] = centre.x
	e["y"] = centre.y
	layout[id] = e
	_refit()
	if end:
		layout = TouchLayout.centres(_rects, get_viewport_rect().size, layout)
		_pointer = -2
		_active = ""
	accept_event()
