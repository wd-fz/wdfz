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
var leave_button: Button
var _scroll: TouchScroll
var _holding := false
var _key := ""


func _init() -> void:
	name = "MicPanel"
	visible = false
	minimum_size_changed.connect(func() -> void: _fit.call_deferred())
	visibility_changed.connect(func() -> void:
		if not visible: cancel_hold()
		else: _fit.call_deferred())
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_bottom = -70.0
	var back := UISkin.panel(12)
	add_theme_stylebox_override("panel", back)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var head := HBoxContainer.new()
	head.add_child(UIArt.view(UIArt.nav("sound"), Vector2(32, 32)))
	var title := Label.new()
	title.text = "广播站 · 话筒"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	leave_button = Button.new()
	leave_button.text = "离开"
	leave_button.custom_minimum_size.y = 44
	leave_button.pressed.connect(func() -> void:
		release_hold()
		closed.emit())
	head.add_child(leave_button)
	box.add_child(head)
	_scroll = TouchScroll.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",6)
	_scroll.add_child(body)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(status)
	chooser = OptionButton.new()
	chooser.name = "PaperChooser"
	chooser.fit_to_longest_item = false
	chooser.clip_text = true
	chooser.custom_minimum_size.y = 44
	chooser.item_selected.connect(func(i: int) -> void: paper_selected.emit(String(chooser.get_item_metadata(i))))
	box.add_child(chooser)
	box.add_child(_scroll)
	page = Label.new()
	page.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.modulate = Color(0.85, 0.9, 0.88)
	body.add_child(page)
	bar = ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 8)
	box.add_child(bar)
	hold_button = Button.new()
	hold_button.name = "HoldRead"
	hold_button.custom_minimum_size = Vector2(0, 52)
	hold_button.focus_mode = Control.FOCUS_NONE
	hold_button.button_down.connect(func() -> void: _set_holding(true))
	hold_button.button_up.connect(release_hold)
	box.add_child(hold_button)
	var small := Label.new()
	small.text = "松开会重读当前段。广播响起时巡察者会来调查；先停播，再躲藏或从另一扇门离开。"
	small.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	small.modulate = Color(1, 1, 1, 0.55)
	small.add_theme_font_size_override("font_size", 12)
	body.add_child(small)
	add_child(box)
	UIArt.decorate(self)


func _ready() -> void:
	get_viewport().size_changed.connect(func() -> void:
		cancel_hold()
		_fit.call_deferred())


func _fit() -> void:
	PanelLayout.fit(self,_scroll,480,minf(280,_scroll.get_child(0).get_combined_minimum_size().y),70)


func _set_holding(on: bool) -> void:
	if _holding == on: return
	_holding = on
	hold_changed.emit(on)


func release_hold() -> void:
	_set_holding(false)


func cancel_hold() -> void:
	release_hold()
	# Hiding a pressed BaseButton clears its drawing but can leave the press sequence armed.
	# Reset it as well, so the first touch after reopening emits button_down again.
	if is_instance_valid(hold_button) and not hold_button.disabled:
		hold_button.disabled = true
		hold_button.disabled = false


## names: [[id, label]]; selected: the id chosen. The list is rebuilt only when the papers change.
func paint(names: Array, selected: String, text: String, state_text: String, progress: float, seconds: float, held: bool, can_read: bool) -> void:
	var key := "|".join(PackedStringArray(names.map(func(n: Array) -> String: return String(n[0]))))
	if key != _key:
		_key = key
		chooser.clear()
		for n: Array in names:
			chooser.add_icon_item(UIArt.item(String(n[0])), String(n[1]))
			chooser.get_popup().set_item_icon_max_width(chooser.item_count - 1, 28)
			UIArt.button(chooser, chooser.icon, 28)
			chooser.set_item_metadata(chooser.item_count - 1, String(n[0]))
	for i in chooser.item_count:
		if chooser.get_item_metadata(i) == selected:
			chooser.select(i)
	page.text = text
	status.text = state_text
	bar.max_value = maxf(1.0, seconds)
	bar.value = progress
	hold_button.disabled = not can_read
	if not can_read: release_hold()
	hold_button.text = "正在朗读 · 松开停播" if held else "按住朗读 · 空格"
	_fit.call_deferred()
