class_name MenuScreen
extends Control
## Shared responsive menu shell. Existing controls keep their signals and owner IDs.
var description: Label
var scroll: TouchScroll
var _layout: HBoxContainer
var _hero: VBoxContainer
var _card: PanelContainer
var _title: Label
var _hint: Label
var _grids: Array[GridContainer] = []
var _new_game: Button
var _continue: Button
var _pause := false
## The keyboard hint, filled from the key bindings (KeyBindings); the defaults until the app sets them.
var keys_hint := "WASD 移动 · 鼠标环视\nE 交互 · Esc 暂停"
var _touch_on := false


func setup(content: VBoxContainer, paused_menu: bool) -> void:
	_pause = paused_menu
	name = "MenuLayout"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout = HBoxContainer.new()
	_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layout.offset_left = 28
	_layout.offset_right = -28
	_layout.offset_top = 24
	_layout.offset_bottom = -24
	_layout.add_theme_constant_override("separation",32)
	add_child(_layout)
	_hero = VBoxContainer.new()
	_hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero.size_flags_stretch_ratio = 0.9
	_hero.alignment = BoxContainer.ALIGNMENT_CENTER
	_hero.add_theme_constant_override("separation",18)
	_layout.add_child(_hero)
	var eyebrow := content.get_node("Eyebrow") as Label
	eyebrow.reparent(_hero,false)
	eyebrow.text = "THE OTHER SIDE" if not _pause else "TAKE A BREATH"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	eyebrow.add_theme_color_override("font_color",UISkin.ACCENT)
	_title = content.get_node("Title") as Label
	_title.reparent(_hero,false)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title.theme_type_variation = "HeadingLabel"
	# A thin chalk rule under the title, like a line drawn on the blackboard.
	var rule := ColorRect.new()
	rule.name = "TitleRule"
	rule.color = Color(UISkin.ACCENT, 0.55)
	rule.custom_minimum_size = Vector2(96, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero.add_child(rule)
	if not _pause:
		var school := content.get_node("SchoolName") as Button
		school.reparent(_hero,false)
		school.alignment = HORIZONTAL_ALIGNMENT_LEFT
		school.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description = content.get_node("Description") as Label
	description.reparent(_hero,false)
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_color_override("font_color",UISkin.MUTED)
	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size",13)
	_hint.add_theme_color_override("font_color",UISkin.MUTED)
	_hero.add_child(_hint)
	_card = PanelContainer.new()
	_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card.add_theme_stylebox_override("panel",UISkin.panel(20))
	_layout.add_child(_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",12)
	_card.add_child(box)
	var heading := Label.new()
	heading.text = "游戏菜单" if _pause else "你的下一段旅程"
	heading.add_theme_color_override("font_color",UISkin.WARM)
	heading.add_theme_font_size_override("font_size",14)
	box.add_child(heading)
	_continue = content.find_child("Resume" if _pause else "LoadGame",true,false) as Button
	_continue.reparent(box,false)
	_continue.custom_minimum_size.y = 54
	_continue.theme_type_variation = "PrimaryButton"
	scroll = TouchScroll.new()
	scroll.name = "MenuScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	box.add_child(scroll)
	var commands := VBoxContainer.new()
	commands.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	commands.add_theme_constant_override("separation",12)
	scroll.add_child(commands)
	if _pause:
		_group(content,commands,["Save","Reload"])
		_group(content,commands,["NotesPause","MapPause","SettingsPause","DlcMenu","FullscreenPause","DebugTools"])
		var back := content.find_child("BackToMenu",true,false) as Button
		back.reparent(box,false)
		back.theme_type_variation = "DangerButton"
	else:
		_new_game = content.find_child("NewGame",true,false) as Button
		_group(content,commands,["NewGame","HardGame"])
		_group(content,commands,["Achievements","Archive","RecordsMenu"])
		_group(content,commands,["SettingsMenu","Speedrun","ImportMenu","DlcMenu","FullscreenMenu","DebugTools"])
		var options := HFlowContainer.new()
		commands.add_child(options)
		for id: String in ["TouchToggle","SoundToggle"]:
			var option := content.find_child(id,true,false) as Control
			option.reparent(options,false)
			option.custom_minimum_size.y = 44
	var art_ids := {"NewGame": "new_game", "HardGame": "warning", "LoadGame": "continue", "Resume": "continue", "Save": "save", "Reload": "load", "Achievements": "achievements", "Archive": "archive", "RecordsMenu": "records", "SettingsMenu": "settings", "SettingsPause": "settings", "NotesPause": "notes", "MapPause": "map", "Speedrun": "speedrun", "ImportMenu": "import", "FullscreenMenu": "fullscreen", "FullscreenPause": "fullscreen", "DebugTools": "debug", "DlcMenu": "dlc", "BackToMenu": "close"}
	for id: String in art_ids:
		var command := find_child(id, true, false) as Button
		if command != null: UIArt.button(command, UIArt.nav(art_ids[id]))
	UIArt.decorate(_card)
	set_touch(false)
	get_viewport().size_changed.connect(refit)
	theme_changed.connect(func() -> void: refit.call_deferred())
	refit()
	refit.call_deferred()


func _group(source: Control, target: Control, names: Array) -> void:
	var grid := GridContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.columns = 2 if names.size() == 2 else 3
	grid.set_meta("columns",grid.columns)
	grid.add_theme_constant_override("h_separation",8)
	grid.add_theme_constant_override("v_separation",8)
	target.add_child(grid)
	_grids.append(grid)
	for id: String in names:
		var button := source.find_child(id,true,false) as Button
		if button == null: continue
		button.reparent(grid,false)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 48
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func set_touch(on: bool) -> void:
	_touch_on = on
	_hint.text = "时间已暂停 · 可安全查看笔记与地图" if _pause else ("双指移动与环视\n点击动作按钮交互" if on else keys_hint)


func set_keys_hint(text: String) -> void:
	keys_hint = text
	set_touch(_touch_on)


func set_save_available(value: bool) -> void:
	if _pause: return
	_continue.theme_type_variation = "PrimaryButton" if value else "Button"
	_new_game.theme_type_variation = "Button" if value else "PrimaryButton"


func refit() -> void:
	if not is_instance_valid(_layout): return
	var view := get_viewport_rect().size
	var font_size := get_theme_default_font_size()
	_hero.visible = view.x >= 740
	_card.custom_minimum_size.x = minf(440,view.x-56) if _hero.visible else 0
	_title.add_theme_font_size_override("font_size",roundi((38.0 if _pause else 52.0)*font_size/16.0))
	for grid: GridContainer in _grids:
		grid.columns = mini(2,int(grid.get_meta("columns"))) if font_size > 20 else int(grid.get_meta("columns"))
