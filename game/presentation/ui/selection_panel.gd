class_name SelectionPanel
extends Control
## Persistent card selection: browsing changes the preview, only the fixed
## confirmation button commits. Timed gameplay choices keep their own flow.

signal confirmed(index: int)
signal canceled

var selected := -1
var cards: Array[Button] = []
var list_scroll: TouchScroll
var detail_scroll: TouchScroll
var confirm_button: Button
var back_button: Button
var shell: PanelContainer
var _entries: Array = []
var _title: Label
var _mode: Label
var _summary: Label
var _name: Label
var _role: Label
var _effect: Label
var _limit: Label
var _art: TextureRect
var _list: VBoxContainer
var _layout: HBoxContainer
var _submitted := false
var _return_focus: WeakRef


func _ready() -> void:
	name = "SelectionPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.015, .025, .035, .92)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	shell = PanelContainer.new()
	shell.add_theme_stylebox_override("panel", UISkin.panel(16))
	add_child(shell)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	shell.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	_title = _label("选择天赋", UISkin.INK)
	_title.theme_type_variation = "HeadingLabel"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	_mode = _label("", UISkin.ACCENT)
	_mode.autowrap_mode = TextServer.AUTOWRAP_OFF
	header.add_child(_mode)
	_layout = HBoxContainer.new()
	_layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_layout.add_theme_constant_override("separation", 16)
	box.add_child(_layout)
	list_scroll = TouchScroll.new()
	list_scroll.name = "CardsScroll"
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.size_flags_stretch_ratio = .9
	_layout.add_child(list_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	list_scroll.add_child(_list)
	var detail := PanelContainer.new()
	var style := UISkin.panel(14)
	style.bg_color = UISkin.CARD
	style.border_color = UISkin.CARD_EDGE
	style.shadow_size = 0
	detail.add_theme_stylebox_override("panel", style)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layout.add_child(detail)
	detail_scroll = TouchScroll.new()
	detail_scroll.name = "DetailScroll"
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail.add_child(detail_scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	detail_scroll.add_child(content)
	var intro := HBoxContainer.new()
	intro.add_theme_constant_override("separation", 12)
	content.add_child(intro)
	_art = UIArt.view(UIArt.surface("locked"), Vector2(100, 104))
	intro.add_child(_art)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	intro.add_child(words)
	_name = _label("先选一个天赋", UISkin.ACCENT)
	words.add_child(_name)
	_role = _label("每局只能选择一个。", UISkin.MUTED)
	words.add_child(_role)
	content.add_child(_label("天赋效果", UISkin.ACCENT))
	_effect = _label("点击左侧卡片查看效果与限制；可以上下滑动列表。", UISkin.INK)
	content.add_child(_effect)
	content.add_child(_label("使用限制", UISkin.WARM))
	_limit = _label("选好后，点击底部按钮确认开始。", UISkin.MUTED)
	content.add_child(_limit)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	box.add_child(footer)
	back_button = Button.new()
	back_button.name = "SelectionBack"
	back_button.text = "返回"
	back_button.custom_minimum_size = Vector2(108, 60)
	back_button.pressed.connect(_cancel)
	footer.add_child(back_button)
	_summary = _label("未选择 · 滑动浏览，点击选中", UISkin.MUTED)
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_summary)
	confirm_button = Button.new()
	confirm_button.name = "SelectionConfirm"
	confirm_button.text = "请选择天赋"
	confirm_button.custom_minimum_size = Vector2(212, 60)
	confirm_button.theme_type_variation = "PrimaryButton"
	confirm_button.disabled = true
	confirm_button.pressed.connect(_confirm)
	footer.add_child(confirm_button)
	get_viewport().size_changed.connect(_fit)
	shell.minimum_size_changed.connect(func() -> void: _fit.call_deferred())
	_fit()
	hide()


func open(title: String, mode: String, entries: Array) -> void:
	_return_focus = weakref(get_viewport().gui_get_focus_owner())
	_entries = entries.duplicate(true)
	selected = -1
	_submitted = false
	cards.clear()
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_title.text = title
	_mode.text = mode
	for i in _entries.size():
		var entry: Dictionary = _entries[i]
		var card := Button.new()
		card.name = "Card_%d" % i
		card.text = "%d  %s\n%s" % [i+1, entry["name"], entry["role"]]
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.icon = entry.get("art")
		card.expand_icon = true
		card.add_theme_constant_override("icon_max_width", 64)
		card.add_theme_constant_override("h_separation", 12)
		card.custom_minimum_size.y = 96
		card.toggle_mode = true
		card.pressed.connect(select.bind(i))
		_list.add_child(card)
		cards.append(card)
	_summary.text = "未选择 · 滑动浏览，点击选中"
	confirm_button.text = "请选择天赋"
	confirm_button.disabled = true
	_name.text = "先选一个天赋"
	_role.text = "每局只能选择一个。"
	_art.texture = UIArt.surface("locked")
	_effect.text = "点击左侧卡片查看效果与限制；可以上下滑动列表。"
	_limit.text = "选好后，点击底部按钮确认开始。"
	list_scroll.scroll_vertical = 0
	detail_scroll.scroll_vertical = 0
	show()
	_fit()
	if not cards.is_empty(): cards[0].grab_focus()


func select(index: int) -> void:
	if _submitted or index < 0 or index >= _entries.size(): return
	selected = index
	var entry: Dictionary = _entries[index]
	for i in cards.size():
		cards[i].set_pressed_no_signal(i == index)
	_name.text = entry["name"]
	_role.text = entry["role"]
	_effect.text = entry["effect"]
	_limit.text = entry["limit"]
	_art.texture = entry.get("art")
	_summary.text = "已选择：%s" % entry["name"]
	confirm_button.text = "确认并开始"
	confirm_button.disabled = false
	detail_scroll.stop_motion()
	detail_scroll.scroll_vertical = 0


func _confirm() -> void:
	if _submitted or selected < 0: return
	_submitted = true
	confirm_button.disabled = true
	confirmed.emit(selected)


func _cancel() -> void:
	if _submitted: return
	_submitted = true
	canceled.emit()
	var previous: Variant = _return_focus.get_ref() if _return_focus != null else null
	if is_instance_valid(previous) and previous is Control and previous.is_visible_in_tree():
		previous.grab_focus()


func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo: return
	var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if key == KEY_TAB:
		var targets: Array[Control] = []
		for card in cards: targets.append(card)
		targets.append(back_button)
		if not confirm_button.disabled: targets.append(confirm_button)
		var at := targets.find(get_viewport().gui_get_focus_owner())
		var next := wrapi(at + (-1 if event.shift_pressed else 1), 0, targets.size())
		targets[next].grab_focus()
		if targets[next] in cards: list_scroll.ensure_control_visible(targets[next])
	elif key >= KEY_1 and key < KEY_1 + cards.size():
		select(key - KEY_1)
		list_scroll.ensure_control_visible(cards[key - KEY_1])
	elif key == KEY_ESCAPE:
		_cancel()
	elif key in [KEY_ENTER, KEY_KP_ENTER]:
		if get_viewport().gui_get_focus_owner() == back_button: _cancel()
		else: _confirm()
	else:
		return
	get_viewport().set_input_as_handled()


func _fit() -> void:
	var view := get_viewport_rect().size
	var width := minf(1120, view.x - 24)
	shell.position = Vector2((view.x-width)*.5, 12)
	shell.size = Vector2(width, view.y-24)


func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
