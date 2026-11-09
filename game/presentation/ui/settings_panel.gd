class_name GameSettingsPanel
extends Control
## Presentation-only settings editor. Values are persisted/applied by GameApp;
## widgets stay alive while values change so dragging never loses its pointer.

signal setting_changed(key: String, value: int)
signal layout_requested
## Key bindings: put key on (action, slot); clear a slot; reset one action ("" = all).
signal binding_changed(action: String, slot: int, key: int)
signal binding_cleared(action: String, slot: int)
signal bindings_reset(action: String)

const INK := Color("ece6da")
const MUTED := Color("9aa4a6")
const ACCENT := Color("8fd6c0")
const PAGES := [
	["画面", "选择清晰度与显示方式", [
		["quality", "画质", "仅改变画面，不影响碰撞、剧情和游戏难度。", [["流畅",0],["均衡",1],["精细",2],["超精细",3],["真实",4]]],
		["bright", "亮度", "调整游戏画面的整体明暗。", [50,150,5]],
		["grain", "胶片颗粒", "为画面添加细微的颗粒质感。", []],
		["full_screen", "全屏显示", "在窗口与全屏之间切换。", []],
		["auto_land", "横屏自动旋转", "开启时可左右翻转；关闭后固定横屏。", []],
	]],
	["声音", "让环境线索更容易听清", [
		["vol", "主音量", "控制游戏音乐、环境声与音效的音量。", [0,100,5]],
		["amb", "环境声", "保留校园底噪、风声等环境声层。", []],
		["captions", "声音字幕", "自动模式会在静音时显示声音线索。", [["自动",0],["开启",1],["关闭",2]]],
		["sub", "提示文字大小", "同时调整声音字幕与临时提示。", [["小",0],["中",1],["大",2]]],
	]],
	["操作", "按自己的习惯调整手感", [
		["touch", "触屏视角灵敏度", "数值越高，滑动时转动视角越快。", [25,250,5]],
		["touch_size", "触屏按钮大小", "一起调整摇杆、动作按钮和工具栏。", [85,125,5]],
		["mouse", "鼠标视角灵敏度", "影响桌面端鼠标环视的速度。", [25,250,5]],
	]],
	["键位", "把键盘按键改成顺手的位置", []],
	["舒适", "减轻视觉刺激，调整阅读体验", [
		["shake", "镜头晃动", "关闭后减少步行与奔跑时的镜头起伏。", []],
		["distortion", "视野扭曲", "调整低 SAN 时的动态扭曲强度。", [["关闭",0],["减弱",1],["完整",2]]],
		["reduce_flash", "减少闪光", "降低闪电等强光变化带来的刺激。", []],
		["text", "界面文字大小", "调整菜单与界面文字，下面可直接预览。", [85,150,5]],
	]],
	["数据", "管理设置与上一局留下的痕迹", []],
]
const QUALITY_NOTES := ["优先帧率：降低分辨率并用 FSR 放大，没有阴影。适合手机或性能较低的设备。", "帧率与细节平衡：FSR 放大，灯管与屏幕有辉光。", "完整分辨率：太阳与最近一盏灯的阴影、环境光遮蔽、手电投影。", "更精细的模型与 4× 抗锯齿，最近两盏灯投影。", "最高细节与 8× 抗锯齿，四盏灯投影与体积雾，设备负载最高。"]

var selected := "画面"
var fullscreen_toggle_allowed := GameSettings.can_toggle_fullscreen()
var values := {}
var shell: PanelContainer
var scroll: ScrollContainer
var controls := {}
var _page_boxes := {}
var _nav_buttons := {}
var _value_labels := {}
var _body: BoxContainer
var _nav: BoxContainer
var _status: Label
var _quality_note: Label
var _preview: Label
var _close: Button
var _clear: Button
var _confirm_clear := false
var _font_scale := 1.0
var _return_focus: WeakRef
var bindings: Dictionary = KeyBindings.defaults()
var _key_buttons := {}      # action -> [Button, Button]
var _capturing: Array = []  # [action, slot] while waiting for a key
var _bind_note: Label


func _ready() -> void:
	name = "SettingsPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = preload("res://content/ui/theme.tres").duplicate()
	var shade := ColorRect.new()
	shade.color = Color(0.008, 0.016, 0.025, 0.88)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	shell = PanelContainer.new()
	shell.name = "SettingsCard"
	shell.add_theme_stylebox_override("panel", _box(Color("0b1116"), Color("263238"), 14, 20))
	shell.minimum_size_changed.connect(func() -> void: fit.call_deferred())
	add_child(shell)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 16)
	shell.add_child(outer)
	var heading := HBoxContainer.new()
	outer.add_child(heading)
	var title := _label("设置", 28, INK)
	title.theme_type_variation = "HeadingLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	_close = _button("完成", "CloseSettings")
	_close.custom_minimum_size.x = 100
	_close.add_theme_stylebox_override("normal", _box(ACCENT, ACCENT, 10, 10))
	for state: String in ["font_color","font_hover_color","font_focus_color"]:
		_close.add_theme_color_override(state, Color("102c29"))
	_close.add_theme_stylebox_override("hover", _box(ACCENT.lightened(0.1), ACCENT, 10, 10))
	_close.pressed.connect(dismiss)
	heading.add_child(_close)
	_body = BoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 20)
	outer.add_child(_body)
	_nav = BoxContainer.new()
	_nav.vertical = true
	_nav.add_theme_constant_override("separation", 8)
	_body.add_child(_nav)
	scroll = ScrollContainer.new()
	scroll.name = "SettingsScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	_body.add_child(scroll)
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pages)
	var nav_group := ButtonGroup.new()
	for page: Array in PAGES:
		var id := String(page[0])
		var nav := _button(id, "Page_" + id)
		nav.toggle_mode = true
		nav.button_group = nav_group
		nav.alignment = HORIZONTAL_ALIGNMENT_LEFT
		nav.pressed.connect(select_page.bind(id))
		_nav.add_child(nav)
		_nav_buttons[id] = nav
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 12)
		pages.add_child(column)
		_page_boxes[id] = column
		var page_title := _label(id, 22, INK)
		page_title.theme_type_variation = "HeadingLabel"
		column.add_child(page_title)
		column.add_child(_label(page[1], 14, MUTED))
		for row: Array in page[2]:
			_add_setting(column, row)
		if id == "操作":
			var layout := _button("调整触屏布局 →", "EditTouchLayout")
			layout.pressed.connect(func() -> void: layout_requested.emit())
			column.add_child(layout)
			column.add_child(_label("摇杆控制移动；点按奔跑按钮切换走 / 跑。\n键盘按键在「键位」页修改。", 14, MUTED))
		elif id == "键位":
			_add_bindings(column)
		elif id == "舒适":
			var preview_card := _card(column)
			preview_card.add_child(_label("阅读预览", 13, ACCENT))
			_preview = _label("铃声响起，走廊里传来了脚步声。", 16, INK)
			preview_card.add_child(_preview)
		elif id == "数据":
			_add_data(column)
	_status = _label("更改即时生效并自动保存", 13, MUTED)
	outer.add_child(_status)
	visibility_changed.connect(_visibility_changed)
	get_viewport().size_changed.connect(fit)
	select_page(selected)
	fit()



func _box(color: Color, border: Color, radius: int, margin: int, thickness: int = 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_corner_radius_all(radius)
	box.set_border_width_all(thickness)
	box.set_content_margin_all(margin)
	return box


func _label(text: String, pixels: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_meta("base_font_size", pixels)
	label.add_theme_font_size_override("font_size", roundi(pixels * _font_scale))
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, id: String) -> Button:
	var button := Button.new()
	button.name = id
	button.text = text
	button.custom_minimum_size.y = 46
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button


func _card(parent: Control) -> VBoxContainer:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_theme_stylebox_override("panel", _box(UISkin.CARD, UISkin.CARD_EDGE, 10, 14))
	parent.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	card.add_child(column)
	return column


func _add_setting(parent: Control, row: Array) -> void:
	var key := String(row[0])
	if key == "full_screen" and not fullscreen_toggle_allowed: return
	var spec: Array = row[3]
	var column := _card(parent)
	column.name = "Setting_" + key
	var head := HBoxContainer.new()
	column.add_child(head)
	head.add_child(_label(row[1], 16, INK))
	if spec.is_empty():
		var toggle := _button("关闭", "O_" + key)
		toggle.toggle_mode = true
		toggle.custom_minimum_size.x = 94
		toggle.toggled.connect(func(on: bool) -> void: _changed(key, int(on)))
		head.add_child(toggle)
		controls[key] = toggle
	column.add_child(_label(row[2], 13, MUTED))
	if spec.is_empty(): return
	if spec[0] is Array:
		var choices := HFlowContainer.new()
		choices.add_theme_constant_override("h_separation", 8)
		choices.add_theme_constant_override("v_separation", 8)
		column.add_child(choices)
		var group := ButtonGroup.new()
		var options := {}
		for opt: Array in spec:
			var value := int(opt[1])
			var button := _button(opt[0], "O_%s_%d" % [key,value])
			button.custom_minimum_size.x = 76
			button.toggle_mode = true
			button.button_group = group
			button.pressed.connect(func() -> void: _changed(key,value))
			choices.add_child(button)
			options[value] = button
		controls[key] = options
		if key == "quality":
			_quality_note = _label("", 13, ACCENT)
			column.add_child(_quality_note)
	else:
		var value_label := _label("", 16, ACCENT)
		value_label.size_flags_horizontal = Control.SIZE_SHRINK_END
		value_label.custom_minimum_size.x = 62
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		head.add_child(value_label)
		_value_labels[key] = value_label
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		column.add_child(line)
		var slider := HSlider.new()
		slider.name = "S_" + key
		slider.min_value = spec[0]
		slider.max_value = spec[1]
		slider.step = spec[2]
		slider.custom_minimum_size = Vector2(60,46)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(func(value: float) -> void: _changed(key,int(value)))
		var less := _button("−", "Less_"+key)
		var more := _button("+", "More_"+key)
		for button: Button in [less,more]: button.custom_minimum_size.x = 46
		less.pressed.connect(func() -> void: slider.value -= slider.step)
		more.pressed.connect(func() -> void: slider.value += slider.step)
		line.add_child(less)
		line.add_child(slider)
		line.add_child(more)
		controls[key] = slider


func _add_data(column: VBoxContainer) -> void:
	var comfort := _card(column)
	comfort.add_child(_label("恢复操作与文字默认", 16, INK))
	comfort.add_child(_label("重置鼠标与触屏灵敏度、文字大小、按钮大小和触屏布局。保留画质、声音与游戏进度。", 13, MUTED))
	var reset := _button("恢复默认", "ResetComfort")
	reset.pressed.connect(func() -> void: setting_changed.emit("reset_comfort",0))
	comfort.add_child(reset)
	var traces := _card(column)
	traces.add_child(_label("上一局的痕迹", 16, INK))
	traces.add_child(_label("清除上一局留在校园里的痕迹，不删除当前存档。此操作无法撤销。", 13, MUTED))
	_clear = _button("清除痕迹", "ClearLastLife")
	_clear.add_theme_color_override("font_color", Color("efb8a5"))
	_clear.pressed.connect(func() -> void:
		if _confirm_clear:
			setting_changed.emit("clear_last_life",0)
			_cancel_clear()
			_status.text = "已清除上一局的痕迹"
		else:
			_confirm_clear = true
			_clear.text = "再次点击确认清除"
		)
	traces.add_child(_clear)


func _add_bindings(column: VBoxContainer) -> void:
	var top := _card(column)
	top.add_child(_label("点按一个键位，再按下新键。Esc 取消，退格清除这一格（每个动作至少留一个键）。新键已被别的动作使用时，两者互换。", 13, MUTED))
	_bind_note = _label("", 13, ACCENT)
	top.add_child(_bind_note)
	var all := _button("全部恢复默认", "ResetBindings")
	all.pressed.connect(func() -> void:
		_stop_capture()
		bindings_reset.emit(""))
	top.add_child(all)
	var group := ""
	var card: VBoxContainer
	for a: Array in KeyBindings.ACTIONS:
		if a[2] != group:
			group = String(a[2])
			column.add_child(_label(group, 15, ACCENT))
			card = _card(column)
		var line := HBoxContainer.new()
		line.name = "Bind_" + String(a[0])
		line.add_theme_constant_override("separation", 8)
		card.add_child(line)
		var name_label := _label(String(a[1]), 16, INK)
		line.add_child(name_label)
		var pair: Array = []
		for slot in 2:
			var b := _button("", "Key_%s_%d" % [a[0], slot])
			b.custom_minimum_size.x = 104
			b.pressed.connect(_start_capture.bind(String(a[0]), slot))
			line.add_child(b)
			pair.append(b)
		_key_buttons[a[0]] = pair
		var reset := _button("默认", "KeyReset_" + String(a[0]))
		reset.custom_minimum_size.x = 64
		reset.add_theme_color_override("font_color", MUTED)
		reset.pressed.connect(func() -> void:
			_stop_capture()
			bindings_reset.emit(String(a[0])))
		line.add_child(reset)
	var fixed := _card(column)
	var esc := HBoxContainer.new()
	fixed.add_child(esc)
	esc.add_child(_label("暂停 / 关闭菜单", 16, INK))
	esc.add_child(_label("Esc（固定）", 15, MUTED))
	set_bindings(bindings)


func set_bindings(current: Dictionary, note: String = "") -> void:
	bindings = current.duplicate(true)
	for id: String in _key_buttons:
		var pair: Array = _key_buttons[id]
		var keys: Array = bindings.get(id, [0, 0])
		for slot in 2:
			var k := int(keys[slot])
			(pair[slot] as Button).text = KeyBindings.key_name(k) if k != 0 else "—"
	if _bind_note != null:
		_bind_note.text = note
	if not _capturing.is_empty():
		_mark_capture()


func capturing() -> Array:
	return _capturing.duplicate()


func _start_capture(action: String, slot: int) -> void:
	set_bindings(bindings)
	_capturing = [action, slot]
	_mark_capture()
	((_key_buttons[action] as Array)[slot] as Button).grab_focus()   # scrolls the cell into view


func _mark_capture() -> void:
	var b: Button = (_key_buttons[_capturing[0]] as Array)[_capturing[1]]
	b.text = "按下新键…"
	if _bind_note != null:
		_bind_note.text = "正在设置「%s」：按下新键，Esc 取消" % KeyBindings.label(_capturing[0])


func _stop_capture() -> void:
	_capturing = []
	set_bindings(bindings, _bind_note.text if _bind_note != null else "")


## A key while capturing: Esc cancels, Backspace/Delete clears the slot, anything else is offered to the app.
func _capture_key(ev: InputEventKey) -> void:
	var action := String(_capturing[0])
	var slot := int(_capturing[1])
	var key := int(ev.physical_keycode) if ev.physical_keycode != KEY_NONE else int(ev.keycode)
	_capturing = []
	if key == KEY_ESCAPE:
		set_bindings(bindings, "已取消")
	elif key == KEY_BACKSPACE or key == KEY_DELETE:
		binding_cleared.emit(action, slot)
	else:
		binding_changed.emit(action, slot, key)


func _cancel_clear() -> void:
	_confirm_clear = false
	if is_instance_valid(_clear): _clear.text = "清除痕迹"


func open(current: Dictionary) -> void:
	if not visible: _return_focus = weakref(get_viewport().gui_get_focus_owner())
	set_values(current)
	show()
	fit()
	fit.call_deferred()
	_close.grab_focus()


func set_values(current: Dictionary) -> void:
	values = current.duplicate()
	for key: String in controls:
		var value := int(values.get(key, GameSettings.DEFAULTS[key]))
		var control: Variant = controls[key]
		if control is HSlider:
			control.set_value_no_signal(value)
			_value_labels[key].text = str(value) + "%"
		elif control is Button:
			control.set_pressed_no_signal(value == 1)
			control.text = "● 开启" if value == 1 else "○ 关闭"
		else:
			for option: int in control: control[option].set_pressed_no_signal(option == value)
	_quality_note.text = QUALITY_NOTES[clampi(int(values.get("quality",2)),0,4)]
	var scale := float(values.get("text",100)) / 100.0
	if not is_equal_approx(scale,_font_scale):
		_font_scale = scale
		theme.default_font_size = roundi(16 * scale)
		for label: Node in find_children("*","Label",true,false):
			if label.has_meta("base_font_size"):
				label.add_theme_font_size_override("font_size",roundi(int(label.get_meta("base_font_size"))*scale))
		fit.call_deferred()


func saved(current: Dictionary, success: bool) -> void:
	set_values(current)
	_status.text = "已保存 · 更改即时生效" if success else "已生效，但保存失败；下次启动可能无法保留"
	_status.add_theme_color_override("font_color", ACCENT if success else Color("efb8a5"))


func _changed(key: String, value: int) -> void:
	if int(values.get(key,-1)) == value: return
	values[key] = value
	set_values(values)
	setting_changed.emit(key,value)


func select_page(id: String) -> void:
	if not _page_boxes.has(id): return
	selected = id
	_cancel_clear()
	if not _capturing.is_empty(): _stop_capture()
	for page: String in _page_boxes:
		_page_boxes[page].visible = page == id
		_nav_buttons[page].set_pressed_no_signal(page == id)
	scroll.scroll_vertical = 0


func fit() -> void:
	if not is_instance_valid(shell): return
	var view := get_viewport_rect().size
	var compact := view.x < 700
	_body.vertical = compact
	_nav.vertical = not compact
	_nav.custom_minimum_size.x = 0 if compact else 132 * _font_scale
	for button: Button in _nav_buttons.values():
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL if compact else Control.SIZE_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER if compact else HORIZONTAL_ALIGNMENT_LEFT
	shell.size = Vector2(minf(1120,view.x-32),minf(760,view.y-24))
	shell.position = (view-shell.size)*0.5


func dismiss() -> void:
	hide()
	if _return_focus != null:
		var previous: Variant = _return_focus.get_ref()
		if is_instance_valid(previous) and previous is Control and previous.is_visible_in_tree(): previous.grab_focus()


func _visibility_changed() -> void:
	if not visible:
		_cancel_clear()
		_capturing = []


func _key_buttons_hit(at: Vector2) -> bool:
	for pair: Array in _key_buttons.values():
		for b: Button in pair:
			if b.get_global_rect().has_point(at): return true
	return false


func _input(event: InputEvent) -> void:
	if not visible: return
	if not _capturing.is_empty():
		if event is InputEventKey and event.pressed and not event.echo:
			_capture_key(event)
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.pressed and not _key_buttons_hit(event.position):
			_stop_capture()
		return
	# Keep keyboard navigation inside this modal, while retaining engine slider keys.
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		var focus := get_viewport().gui_get_focus_owner()
		if focus == null or not is_ancestor_of(focus):
			_close.grab_focus()
			get_viewport().set_input_as_handled()
			return
		var next := focus.find_prev_valid_focus() if event.shift_pressed else focus.find_next_valid_focus()
		if next == null or not is_ancestor_of(next):
			_close.grab_focus()
			get_viewport().set_input_as_handled()
