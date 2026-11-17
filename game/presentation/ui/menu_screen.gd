class_name MenuScreen
extends Control
## Pause screen, with the current run on the left and fixed resume and exit actions.

var description: Label
var scroll: TouchScroll
var _layout: BoxContainer
var _hero: VBoxContainer
var _card: PanelContainer
var _title: Label
var _commands: VBoxContainer
var _grids: Array[GridContainer] = []


func setup(content: VBoxContainer) -> void:
	name = "PauseLayout"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout = BoxContainer.new()
	_layout.add_theme_constant_override("separation", 30)
	add_child(_layout)
	_hero = VBoxContainer.new()
	_hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero.alignment = BoxContainer.ALIGNMENT_CENTER
	_hero.add_theme_constant_override("separation", 10)
	_layout.add_child(_hero)
	_title = content.get_node("Title") as Label
	_title.reparent(_hero, false)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title.theme_type_variation = "HeadingLabel"
	var rule := ColorRect.new()
	rule.color = Color(UISkin.ACCENT, 0.8)
	rule.custom_minimum_size = Vector2(40, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero.add_child(rule)
	description = content.get_node("Description") as Label
	description.reparent(_hero, false)
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	description.add_theme_color_override("font_color", UISkin.MUTED)
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UISkin.panel(18))
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


func refit() -> void:
	if not is_instance_valid(_layout): return
	var view := get_viewport_rect().size
	var text_scale := get_theme_default_font_size() / 16.0
	var compact := view.x < 690
	var width := minf(840, view.x - 48)
	_layout.vertical = compact
	_card.custom_minimum_size.x = 0 if compact else minf(460, width * 0.55)
	_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", roundi((32.0 if compact else 54.0) * sqrt(text_scale)))
	for grid: GridContainer in _grids:
		grid.columns = 1 if width < 420 and text_scale > 1.25 else 2
	var height := _card.get_combined_minimum_size().y + _commands.get_combined_minimum_size().y
	if compact:
		height += _hero.get_combined_minimum_size().y + 30
	_layout.size = Vector2(width, minf(height, view.y - 48))
	_layout.position = (view - _layout.size) * 0.5
