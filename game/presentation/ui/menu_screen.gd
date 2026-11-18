class_name MenuScreen
extends Control
## Pause screen, with the current run on the left and fixed resume and exit actions.

var description: Label
var scroll: TouchScroll
var _layout: BoxContainer
var _overview: TouchScroll
var _hero: VBoxContainer
var _card: PanelContainer
var _title: Label
var _run_status: Label
var _commands: VBoxContainer
var _grids: Array[GridContainer] = []


func setup(content: VBoxContainer) -> void:
	name = "PauseLayout"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout = BoxContainer.new()
	add_child(_layout)
	# Wrapped labels can report a tall minimum before their first layout.
	# Keep that height inside the overview so it cannot push the actions off screen.
	_overview = TouchScroll.new()
	_overview.name = "OverviewScroll"
	_overview.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_overview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layout.add_child(_overview)
	_hero = VBoxContainer.new()
	_hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hero.alignment = BoxContainer.ALIGNMENT_CENTER
	_hero.add_theme_constant_override("separation", 10)
	_overview.add_child(_hero)
	_title = content.get_node("Title") as Label
	_title.reparent(_hero, false)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.theme_type_variation = "HeadingLabel"
	var rule := ColorRect.new()
	rule.color = Color(UISkin.ACCENT, 0.8)
	rule.custom_minimum_size = Vector2(40, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero.add_child(rule)
	_run_status = Label.new()
	_run_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_run_status.add_theme_color_override("font_color", UISkin.ACCENT)
	_run_status.hide()
	_hero.add_child(_run_status)
	description = content.get_node("Description") as Label
	description.reparent(_hero, false)
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_color_override("font_color", UISkin.MUTED)
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UISkin.cinematic_panel(18))
	_layout.add_child(_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_card.add_child(box)
	var resume := _move(content, box, "Resume", "continue")
	resume.text = "继续游戏"
	resume.custom_minimum_size.y = 52
	resume.theme_type_variation = "PrimaryButton"
	scroll = TouchScroll.new()
	scroll.name = "MenuScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_commands = VBoxContainer.new()
	_commands.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_commands.add_theme_constant_override("separation", 10)
	scroll.add_child(_commands)
	_group(content, _commands, {"NotesPause": "notes", "MapPause": "map", "Save": "save", "Reload": "load"})
	_commands.add_child(HSeparator.new())
	_group(content, _commands, {"SettingsPause": "settings", "DlcMenu": "dlc", "FullscreenPause": "fullscreen", "DebugTools": "debug"})
	box.add_child(HSeparator.new())
	var back := _move(content, box, "BackToMenu", "close")
	back.theme_type_variation = "QuietButton"
	back.add_theme_color_override("font_color", UISkin.DANGER)
	get_viewport().size_changed.connect(refit)
	theme_changed.connect(func() -> void: refit.call_deferred())
	_commands.minimum_size_changed.connect(func() -> void: refit.call_deferred())
	refit()


func _move(source: Control, target: Control, id: String, icon: String) -> Button:
	var button := source.find_child(id, true, false) as Button
	if button == null: return null
	button.reparent(target, false)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 44
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.theme_type_variation = "CommandButton"
	UIArt.button(button, UIArt.nav(icon), 22)
	return button


func _group(source: Control, target: Control, buttons: Dictionary) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	target.add_child(grid)
	_grids.append(grid)
	for id: String in buttons:
		_move(source, grid, id, buttons[id])


func set_context(detail: String, cooperative: bool = false) -> void:
	_title.text = "联机菜单" if cooperative else "已暂停"
	description.text = detail


func set_run_status(place_and_period: String, time: String) -> void:
	_run_status.text = place_and_period
	if not time.is_empty():
		_run_status.text = "%s\n%s" % [time, place_and_period]
	_run_status.visible = not _run_status.text.is_empty()
	_overview.scroll_vertical = 0
	refit()


func reveal(reduced: bool) -> void:
	UISkin.reveal(_hero, reduced, 0.32)
	UISkin.reveal(_card, reduced, 0.24)


func refit() -> void:
	if not is_instance_valid(_layout): return
	var view := get_viewport_rect().size
	var text_scale := get_theme_default_font_size() / 16.0
	var compact := view.x < 690
	var width := minf(840, view.x - 48)
	var height_limit := view.y - 48
	var separation := 12 if compact else 30
	_layout.vertical = compact
	_layout.add_theme_constant_override("separation", separation)
	_card.custom_minimum_size.x = 0 if compact else minf(460, width * 0.55)
	_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", roundi((32.0 if compact else 54.0) * sqrt(text_scale)))
	for grid: GridContainer in _grids:
		grid.columns = 1 if width < 420 and text_scale > 1.25 else 2
	var fixed_height := _card.get_combined_minimum_size().y
	var height := fixed_height + _commands.get_combined_minimum_size().y
	var overview_height := 0.0
	if compact:
		# Leave room for the fixed buttons and an action row in the stacked layout.
		overview_height = clampf(height_limit - fixed_height - separation - 56.0, 0.0, height_limit / 3.0)
		height += overview_height + separation
	_overview.custom_minimum_size.y = overview_height
	_layout.size = Vector2(width, minf(height, height_limit))
	_layout.position = (view - _layout.size) * 0.5
