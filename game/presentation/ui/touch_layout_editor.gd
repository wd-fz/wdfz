class_name TouchLayoutEditor
extends Control
## A full-size preview. Dragging edits a copy; only Done persists it.

signal saved(layout: Dictionary)
signal cancelled
var layout: Dictionary = {}
var percent := 100
var _handles := {}
var _pointer := -2
var _active := ""
var _offset := Vector2.ZERO
var _rects := {}
var _buttons: HBoxContainer


func _ready() -> void:
	name = "TouchLayoutEditor"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var back := ColorRect.new()
	back.color = Color(.03,.04,.06,.94)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	var tip := Label.new()
	tip.text = "拖动三个区域，调整触屏布局\n按钮会避开彼此和屏幕边缘"
	tip.position = Vector2(16,12)
	tip.add_theme_font_size_override("font_size",16)
	add_child(tip)
	for id: String in TouchLayout.IDS:
		var h := Panel.new()
		h.name = id.capitalize()+"Handle"
		var style := StyleBoxFlat.new()
		style.bg_color = Color(.15,.25,.32,.85)
		style.border_color = Color(.6,.8,.9)
		style.set_border_width_all(2)
		style.set_corner_radius_all(10)
		h.add_theme_stylebox_override("panel",style)
		var label := Label.new()
		label.text = {"stick":"移动摇杆","actions":"奔跑\n\n交互","tools":"手册 · 手电 · 快捷物品"}[id]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(label)
		add_child(h)
		h.gui_input.connect(_drag.bind(id))
		_handles[id] = h
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation",8)
	for spec: Array in [["恢复默认","reset"],["取消","cancel"],["完成","done"]]:
		var b := Button.new()
		b.text = spec[0]
		b.name = spec[1]
		b.custom_minimum_size = Vector2(96,44)
		b.pressed.connect(func() -> void:
			match spec[1]:
				"reset":
					layout = {}
					_refit()
				"cancel": cancelled.emit()
				"done": saved.emit(layout.duplicate(true))
			)
		_buttons.add_child(b)
	add_child(_buttons)
	get_viewport().size_changed.connect(_resized)
	_refit()


func _resized() -> void:
	_pointer = -2
	_active = ""
	_refit()


func _refit() -> void:
	if not is_node_ready():
		return
	var view := get_viewport_rect().size
	_buttons.position = Vector2((view.x-304)*.5,view.y*.5-22)
	_rects = TouchLayout.resolve(view,layout,percent,[Rect2(0,0,view.x,68)])
	for id: String in TouchLayout.IDS:
		var rect: Rect2 = _rects[id]
		_handles[id].position = rect.position
		_handles[id].size = rect.size


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
		point = (_handles[id] as Control).get_global_transform()*event.position
		begin = event.pressed
		end = not event.pressed
	elif event is InputEventScreenDrag:
		index = event.index
		point = (_handles[id] as Control).get_global_transform()*event.position
	else:
		return
	if begin and _pointer == -2:
		_pointer = index
		_active = id
		_offset = point-(_rects[id] as Rect2).get_center()
	if _pointer != index or _active != id:
		return
	var centre := (point-_offset)/get_viewport_rect().size*100
	layout[id] = {"x": centre.x,"y": centre.y}
	_refit()
	if end:
		layout = TouchLayout.centres(_rects,get_viewport_rect().size)
		_pointer = -2
		_active = ""
	accept_event()
