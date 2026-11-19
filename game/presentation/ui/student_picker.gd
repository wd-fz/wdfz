class_name StudentPicker
extends Control
## Touch and keyboard both preview a cast member before confirming a reservation.
signal picked(id: String)
signal dismissed
var selected := ""
var cards: Dictionary = {}
var confirm: Button
var studio: StudentStudio
var _stage_box: PanelContainer
var _role: Label
var _name_label: Label
var _line: Label
var _pose: Button
var _back: Button
var _slots := {}
var _local_id := ""
var _labels := {}
var _from: WeakRef
var _scene_box: MarginContainer


func _ready() -> void:
	name = "CharacterPicker"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	UISkin.shade(self, .96)
	_scene_box = MarginContainer.new()
	_scene_box.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_scene_box)
	_scene_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	_scene_box.add_child(row)
	_stage_box = PanelContainer.new()
	_stage_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage_box.size_flags_stretch_ratio = .8
	_stage_box.add_theme_stylebox_override("panel", _surface(Color("182832"),Color("46606b")))
	row.add_child(_stage_box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)
	_role = _label(column, 17)
	_name_label = _label(column, 32)
	_line = _label(column, 17)
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var grid := GridContainer.new()
	grid.name = "Cast"
	grid.columns = 2
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(grid)
	for id: String in StudentCast.IDS:
		var card := Button.new()
		card.name = "Cast_" + id
		card.custom_minimum_size = Vector2(78,47)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.clip_contents = true
		grid.add_child(card)
		var inside := HBoxContainer.new()
		inside.mouse_filter = MOUSE_FILTER_IGNORE
		card.add_child(inside)
		inside.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inside.offset_left = 3
		inside.offset_right = -3
		inside.add_theme_constant_override("separation", 5)
		var portrait := TextureRect.new()
		portrait.texture = load("res://assets/characters/%s.webp" % id)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait.custom_minimum_size.x = 40
		portrait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		portrait.mouse_filter = MOUSE_FILTER_IGNORE
		inside.add_child(portrait)
		var words := _label(inside, 16)
		words.custom_minimum_size.x = 68
		words.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		words.clip_text = true
		_labels[id] = words
		card.pressed.connect(_select.bind(id))
		cards[id] = card
	var footer := HBoxContainer.new()
	column.add_child(footer)
	_back = _button(footer, "返回", close)
	_pose = _button(footer, "试走", _cycle)
	confirm = _button(footer, "选用角色", _confirm)
	confirm.theme_type_variation = "PrimaryButton"
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resized.connect(_fit)
	hide()


func open(id: String, owners: Dictionary = {}, local: String = "") -> void:
	_from = weakref(get_viewport().gui_get_focus_owner())
	_slots = owners
	_local_id = local
	studio = StudentStudio.new()
	_stage_box.add_child(studio)
	show()
	move_to_front()
	_fit()
	_select(StudentCast.resolve(id))
	(cards[selected] as Button).grab_focus()


func set_slots(owners: Dictionary) -> void:
	_slots = owners
	if visible: _paint()


func _select(id: String) -> void:
	selected = id
	studio.select_character(id)
	_pose.text = "试走"
	_paint()


func _paint() -> void:
	var data: Dictionary = StudentCast.PEOPLE[selected]
	var color := Color(data["color"])
	_role.text = "选择角色  /  " + String(data["club"])
	_role.modulate = color
	_name_label.text = data["name"]
	_line.text = "“%s”" % data["line"]
	for id: String in cards:
		var taken := _taken(id)
		var label: Label = _labels[id]
		var status := "队友已选" if taken else "已选用" if _slots.has(id) else "预览" if id == selected else ""
		label.text = String(StudentCast.PEOPLE[id]["name"]) + ("\n" + status if status != "" else "")
		var card: Button = cards[id]
		card.accessibility_name = "%s · %s" % [StudentCast.PEOPLE[id]["name"], label.text.get_slice("\n", 1)]
		card.modulate = Color("99a7ad") if taken else Color.WHITE
		var style := _surface(Color("253a45") if id == selected else Color("17242e"), Color(StudentCast.PEOPLE[id]["color"]) if id == selected else UISkin.CARD_EDGE)
		for state in ["normal","pressed","hover"]: card.add_theme_stylebox_override(state,style)
	confirm.disabled = _taken(selected)
	confirm.text = "已被队友选用" if confirm.disabled else "选用角色"


func _taken(id: String) -> bool:
	return _slots.has(id) and _slots[id] != _local_id


func _cycle() -> void:
	var poses := ["idle", "walk", "run", "sit"]
	var i := (poses.find(studio.action) + 1) % poses.size()
	studio.action = poses[i]
	_pose.text = ["试走", "试跑", "坐下", "起身"][i]


func _confirm() -> void:
	if not visible or _taken(selected): return
	var choice := selected
	close()
	picked.emit(choice)


func close() -> void:
	if not visible: return
	hide()
	if is_instance_valid(studio):
		_stage_box.remove_child(studio)
		studio.queue_free()
		studio = null
	var prior := _from.get_ref() as Control if _from != null else null
	if is_instance_valid(prior) and prior.is_visible_in_tree(): prior.grab_focus()
	dismissed.emit()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_pressed() or event.is_echo(): return
	if event.is_action("ui_cancel"):
		close()
	elif event is InputEventKey and event.physical_keycode == KEY_TAB:
		var targets := cards.values() + [_back, _pose]
		if not confirm.disabled: targets.append(confirm)
		var at := targets.find(get_viewport().gui_get_focus_owner())
		targets[wrapi(at + (-1 if event.shift_pressed else 1), 0, targets.size())].grab_focus()
	elif event is InputEventKey and event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_4:
		_select(StudentCast.IDS[event.physical_keycode-KEY_1])
		cards[selected].grab_focus()
	else: return
	get_viewport().set_input_as_handled()


func _fit() -> void:
	var margin := 12 if size.y < 440 else clampi(roundi(size.y * .055), 18, 54)
	for side in ["left","top","right","bottom"]: _scene_box.add_theme_constant_override("margin_"+side, margin)
	_name_label.add_theme_font_size_override("font_size", 25 if size.y < 440 else 40)


static func _surface(background: Color, edge: Color) -> StyleBoxFlat:
	var style := UISkin.cinematic_panel(2)
	style.bg_color = background
	style.border_color = edge
	style.set_border_width_all(1)
	style.shadow_size = 0
	return style


static func _label(parent: Control, font_size: int) -> Label:
	var label := Label.new()
	label.mouse_filter = MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


static func _button(parent: Control, label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size.y = 46
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
