class_name SelectionPanel
extends Control
## Persistent card selection: browsing changes the preview, only the fixed
## confirmation button commits. Timed gameplay choices keep their own flow.

signal confirmed(index: int)
signal canceled

var selected := -1
var reduce_motion := false
var cards: Array[Button] = []
var list_scroll: TouchScroll
var detail_scroll: TouchScroll
var confirm_button: Button
var back_button: Button
var cast_button: Button
var cast_picker: StudentPicker
var character_id := StudentCast.DEFAULT
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
var _list: GridContainer
var _layout: HBoxContainer
var _effects: BoxContainer
var _portrait: HBoxContainer
var _preview := -1
var _submitted := false
var _return_focus: WeakRef


func _ready() -> void:
	name = "SelectionPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UISkin.shade(self, 0.78)
	shell = PanelContainer.new()
	shell.add_theme_stylebox_override("panel", UISkin.cinematic_panel(16))
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
	_mode.theme_type_variation = "HudPill"
	_mode.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mode.size_flags_horizontal = Control.SIZE_SHRINK_END
	header.add_child(_mode)
	box.add_child(HSeparator.new())
	_layout = HBoxContainer.new()
	_layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_layout.add_theme_constant_override("separation", 16)
	box.add_child(_layout)
	list_scroll = TouchScroll.new()
	list_scroll.name = "CardsScroll"
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.size_flags_stretch_ratio = 1.04
	_layout.add_child(list_scroll)
	_list = GridContainer.new()
	_list.columns = 2
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("h_separation", 8)
	_list.add_theme_constant_override("v_separation", 8)
	list_scroll.add_child(_list)
	var detail := PanelContainer.new()
	detail.add_theme_stylebox_override("panel", UISkin.cinematic_panel(10))
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
	var backdrop := PanelContainer.new()
	var portrait_style := UISkin.cinematic_panel(8)
	portrait_style.bg_color = Color("0c151e")
	portrait_style.shadow_size = 0
	backdrop.add_theme_stylebox_override("panel", portrait_style)
	content.add_child(backdrop)
	var spotlight := Gradient.new()
	spotlight.colors = PackedColorArray([Color("375c6d"), Color("0d182100")])
	var light := GradientTexture2D.new()
	light.gradient = spotlight
	light.fill = GradientTexture2D.FILL_RADIAL
	light.fill_from = Vector2(0.28, 0.48)
	light.fill_to = Vector2(0.83, 1.0)
	light.width = 192
	light.height = 128
	var glow := UIArt.view(light, Vector2.ZERO)
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	backdrop.add_child(glow)
	_portrait = HBoxContainer.new()
	_portrait.add_theme_constant_override("separation", 16)
	backdrop.add_child(_portrait)
	_art = UIArt.view(UIArt.surface("locked"), Vector2(174, 166))
	_portrait.add_child(_art)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	_portrait.add_child(words)
	_name = _label("选择天赋以查看详情", UISkin.INK)
	_name.theme_type_variation = "HeadingLabel"
	words.add_child(_name)
	_role = _label("", UISkin.MUTED)
	words.add_child(_role)
	_effects = BoxContainer.new()
	_effects.add_theme_constant_override("separation", 8)
	content.add_child(_effects)
	var effect_card := UISkin.card(_effects)
	(effect_card.get_parent() as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	effect_card.add_child(_label("天赋效果", UISkin.ACCENT))
	_effect = _label("", UISkin.INK)
	effect_card.add_child(_effect)
	var limit_card := UISkin.card(_effects)
	(limit_card.get_parent() as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	limit_card.add_child(_label("使用限制", UISkin.DANGER))
	_limit = _label("", UISkin.MUTED)
	limit_card.add_child(_limit)
	box.add_child(HSeparator.new())
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	box.add_child(footer)
	back_button = Button.new()
	back_button.name = "SelectionBack"
	back_button.text = "返回"
	back_button.custom_minimum_size = Vector2(96, 52)
	back_button.theme_type_variation = "QuietButton"
	back_button.pressed.connect(_cancel)
	footer.add_child(back_button)
	cast_button = Button.new()
	cast_button.name = "ChooseCharacter"
	cast_button.pressed.connect(func() -> void: cast_picker.open(character_id))
	footer.add_child(cast_button)
	cast_picker = StudentPicker.new()
	add_child(cast_picker)
	cast_picker.picked.connect(func(id: String) -> void:
		character_id = id
		cast_button.text = "角色 · " + String(StudentCast.PEOPLE[id]["name"]))
	_summary = _label("", UISkin.MUTED)
	_summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_summary)
	confirm_button = Button.new()
	confirm_button.name = "SelectionConfirm"
	confirm_button.text = "确认并开始"
	confirm_button.custom_minimum_size = Vector2(176, 52)
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
	cast_picker.close()
	character_id = StudentCast.DEFAULT
	cast_button.text = "角色 · " + String(StudentCast.PEOPLE[character_id]["name"])
	_entries = entries.duplicate(true)
	selected = -1
	_preview = -1
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
		card.text = entry["name"]
		card.tooltip_text = "%d · %s" % [i+1, entry["role"]]
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		card.icon = entry.get("art")
		card.expand_icon = true
		card.add_theme_constant_override("icon_max_width", 72)
		card.custom_minimum_size.y = 124
		card.toggle_mode = true
		card.theme_type_variation = "CommandButton"
		card.mouse_entered.connect(_preview_card.bind(i))
		card.focus_entered.connect(_preview_card.bind(i))
		card.pressed.connect(select.bind(i))
		_list.add_child(card)
		cards.append(card)
	_summary.text = ""
	confirm_button.disabled = true
	_name.text = "选择天赋以查看详情"
	_role.text = ""
	_art.texture = UIArt.surface("locked")
	_effects.hide()
	list_scroll.scroll_vertical = 0
	detail_scroll.scroll_vertical = 0
	show()
	_fit()
	UISkin.reveal(shell, reduce_motion)
	if not cards.is_empty():
		_present(0, false)
		cards[0].grab_focus()


func select(index: int) -> void:
	if _submitted or index < 0 or index >= _entries.size(): return
	selected = index
	for i in cards.size():
		cards[i].set_pressed_no_signal(i == index)
	_present(index, true)
	_summary.text = "已选  %s" % _entries[index]["name"]
	confirm_button.disabled = false


func _preview_card(index: int) -> void:
	if not visible or _submitted or selected >= 0 or index >= _entries.size(): return
	_present(index, true)


func _present(index: int, animated: bool) -> void:
	if index == _preview: return
	_preview = index
	var entry: Dictionary = _entries[index]
	_name.text = entry["name"]
	_role.text = entry["role"]
	_effects.show()
	_effect.text = entry["effect"]
	_limit.text = entry["limit"]
	_art.texture = entry.get("art")
	detail_scroll.stop_motion()
	detail_scroll.scroll_vertical = 0
	UISkin.reveal(_portrait, reduce_motion or not animated, 0.28)


func set_reduce_motion(value: bool) -> void:
	reduce_motion = value
	if value:
		UISkin.reveal(shell, true)
		UISkin.reveal(_portrait, true)


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
	if not visible or cast_picker.visible or not event is InputEventKey or not event.pressed or event.echo: return
	var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if key == KEY_TAB:
		var targets: Array[Control] = []
		for card in cards: targets.append(card)
		targets.append(back_button)
		targets.append(cast_button)
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
		var focus := get_viewport().gui_get_focus_owner()
		if focus == back_button:
			_cancel()
		elif focus == cast_button:
			cast_picker.open(character_id)
		elif selected < 0 and focus in cards:
			select(cards.find(focus))
		else:
			_confirm()
	else:
		return
	get_viewport().set_input_as_handled()


func _fit() -> void:
	var view := get_viewport_rect().size
	var width := minf(1120, view.x - 24)
	var font_scale := get_theme_default_font_size() / 16.0
	_list.columns = 1 if width < 670 else 2
	var compact := width < 820 or font_scale > 1.2
	_art.custom_minimum_size = Vector2(114, 106) if compact else Vector2(174, 166)
	_effects.vertical = width < 760
	_title.add_theme_font_size_override("font_size", roundi(26.0 * sqrt(font_scale)))
	_name.add_theme_font_size_override("font_size", roundi(25.0 * sqrt(font_scale)))
	shell.position = Vector2((view.x-width)*.5, 12)
	shell.size = Vector2(width, view.y-24)


func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
