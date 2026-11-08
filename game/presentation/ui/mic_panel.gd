class_name MicPanel
extends PanelContainer
## The microphone panel of the broadcast room (broadcast-ui.js): the papers in hand, the current page,
## the reading progress and a hold-to-read button. It does not pause the world.

signal paper_selected(id: String)
signal hold_changed(on: bool)
signal closed

var status: Label
var page: Label
var bar: ProgressBar
var hold_button: Button
var chooser: OptionButton
var _key := ""


func _init() -> void:
	name = "MicPanel"
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_bottom = -70.0
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.04, 0.06, 0.08, 0.97)
	back.set_content_margin_all(12)
	back.set_corner_radius_all(8)
	add_theme_stylebox_override("panel", back)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = "广播站 · 话筒"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var leave := Button.new()
	leave.text = "离开"
	leave.pressed.connect(func() -> void: closed.emit())
	head.add_child(leave)
	box.add_child(head)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(420, 0)
	box.add_child(status)
	chooser = OptionButton.new()
	chooser.name = "PaperChooser"
	chooser.item_selected.connect(func(i: int) -> void: paper_selected.emit(String(chooser.get_item_metadata(i))))
	box.add_child(chooser)
	page = Label.new()
	page.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.custom_minimum_size = Vector2(420, 0)
	page.modulate = Color(0.85, 0.9, 0.88)
	box.add_child(page)
	bar = ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(420, 8)
	box.add_child(bar)
	hold_button = Button.new()
	hold_button.name = "HoldRead"
	hold_button.custom_minimum_size = Vector2(0, 52)
	hold_button.button_down.connect(func() -> void: hold_changed.emit(true))
	hold_button.button_up.connect(func() -> void: hold_changed.emit(false))
	box.add_child(hold_button)
	var small := Label.new()
	small.text = "松开会重读当前段。广播响起时巡察者会来调查；先停播，再躲藏或从另一扇门离开。"
	small.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	small.custom_minimum_size = Vector2(420, 0)
	small.modulate = Color(1, 1, 1, 0.55)
	small.add_theme_font_size_override("font_size", 12)
	box.add_child(small)
	add_child(box)


## names: [[id, label]]; selected: the id chosen. The list is rebuilt only when the papers change.
func paint(names: Array, selected: String, text: String, state_text: String, progress: float, seconds: float, held: bool, can_read: bool) -> void:
	var key := "|".join(PackedStringArray(names.map(func(n: Array) -> String: return String(n[0]))))
	if key != _key:
		_key = key
		chooser.clear()
		for n: Array in names:
			chooser.add_item(String(n[1]))
			chooser.set_item_metadata(chooser.item_count - 1, String(n[0]))
	for i in chooser.item_count:
		if chooser.get_item_metadata(i) == selected:
			chooser.select(i)
	page.text = text
	status.text = state_text
	bar.max_value = maxf(1.0, seconds)
	bar.value = progress
	hold_button.disabled = not can_read
	hold_button.text = "正在朗读 · 松开停播" if held else "按住朗读 · 空格"
