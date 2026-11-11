class_name GameUI
extends CanvasLayer

const BASE_THEME: Theme = preload("res://content/ui/theme.tres")

signal new_requested
signal new_hard_requested
signal death_menu_requested
signal load_requested
signal save_requested
signal menu_requested
signal pause_requested
signal resume_requested
signal touch_move(value: Vector2)
signal touch_look(relative: Vector2)
signal touch_sprint(value: bool)
signal interact_requested
## A choice panel button (index into the labels given to show_choice).
signal choice_selected(index: int)
signal lift_close_requested
signal item_use_requested(id: String)
signal item_hot_requested(index: int, id: String)
signal item_drop_requested(id: String)
signal achievements_requested
signal archive_requested
signal speedrun_requested
signal terminal_command(line: String)
signal opening_finished(skipped: bool)
signal terminal_closed
signal sound_toggled(on: bool)
signal settings_requested
signal results_requested
signal records_requested
signal legacy_import_requested(text: String)
signal grade_sound(band: String)
signal fullscreen_requested
signal map_requested(id: String)
signal notes_requested(query: String)
signal notes_focus_requested(route: String)
signal setting_changed(key: String, value: int)
signal touch_layout_changed(layout: Dictionary)
signal binding_changed(action: String, slot: int, key: int)
signal binding_cleared(action: String, slot: int)
signal bindings_reset(action: String)
signal manual_requested
signal torch_requested
signal hot_requested(index: int)
signal bag_closed
signal debug_requested
signal dlc_requested
signal school_tapped
signal ending_wake_requested
signal quit_requested

@onready var menu: Control = %Menu
@onready var pause_panel: Control = %PausePanel
@onready var hud: Control = %HUD
@onready var touch_controls: Control = %TouchControls
@onready var stick: TouchStick = %MovePad
@onready var look_pad: TouchLook = %LookPad

var _mode := "menu"
var fullscreen_toggle_allowed := GameSettings.can_toggle_fullscreen()
var choice_panel: PanelContainer
var selection_panel: SelectionPanel
var lift_close_button: Button
var _choice_box: VBoxContainer
var _choice_scroll: TouchScroll
var _choice_text: Label
var _choice_cancel: Button
var _bag_drop_row: HBoxContainer
var _bag_drop_label: Label
var _bag_pending_drop := ""
var _touch_enabled := false
var _paper_flying := false
var _paper_pad: PaperFlightPad
var _paper_read := false
var _paper_progress: ProgressBar
var _toast_seconds := 0.0


func _ready() -> void:
	%NewGame.pressed.connect(func() -> void: new_requested.emit())
	%LoadGame.pressed.connect(func() -> void: load_requested.emit())
	%Resume.pressed.connect(func() -> void: resume_requested.emit())
	%Save.pressed.connect(func() -> void: save_requested.emit())
	%Reload.pressed.connect(func() -> void: load_requested.emit())
	%BackToMenu.pressed.connect(func() -> void: menu_requested.emit())
	%PauseButton.pressed.connect(func() -> void: pause_requested.emit())
	%TouchInteract.pressed.connect(func() -> void: interact_requested.emit())
	%TouchSprint.toggled.connect(func(value: bool) -> void:
		touch_sprint.emit(value)
		_update_sprint_label())
	stick.moved.connect(func(value: Vector2) -> void: touch_move.emit(value))
	look_pad.looked.connect(func(value: Vector2) -> void: touch_look.emit(value))
	%TouchToggle.toggled.connect(set_touch_enabled)
	_build_menu_photo()
	_build_choice()
	_build_status()
	_build_bag()
	%SchoolName.pressed.connect(func() -> void: school_tapped.emit())
	_build_touch_tools()
	_build_death()
	_style_hud()
	var hard := Button.new()
	hard.name = "HardGame"
	hard.text = "梦魇 · 新游戏"
	hard.custom_minimum_size = Vector2(0, 48)
	hard.pressed.connect(func() -> void: new_hard_requested.emit())
	%NewGame.add_sibling(hard)
	var ach := Button.new()
	ach.name = "Achievements"
	ach.text = "成就"
	ach.custom_minimum_size = Vector2(0, 48)
	ach.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ach.pressed.connect(func() -> void: achievements_requested.emit())
	var sound := CheckButton.new()
	sound.name = "SoundToggle"
	sound.text = "声音"
	sound.button_pressed = true
	sound.toggled.connect(func(on: bool) -> void: sound_toggled.emit(on))
	# Collect controls before MenuScreen arranges them into their responsive groups.
	var load_row := HFlowContainer.new()
	var option_row := HFlowContainer.new()
	var load_button: Button = %LoadGame
	var touch_toggle: CheckButton = %TouchToggle
	load_button.add_sibling(load_row)
	touch_toggle.add_sibling(option_row)
	load_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_button.reparent(load_row, false)
	load_row.add_child(ach)
	var arch := Button.new()
	arch.name = "Archive"
	arch.text = "档案馆"
	arch.custom_minimum_size = Vector2(0, 48)
	arch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arch.pressed.connect(func() -> void: archive_requested.emit())
	load_row.add_child(arch)
	var run := Button.new()
	run.name = "Speedrun"
	run.text = "速通"
	run.custom_minimum_size = Vector2(0, 48)
	run.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	run.pressed.connect(func() -> void: speedrun_requested.emit())
	load_row.add_child(run)
	touch_toggle.reparent(option_row, false)
	option_row.add_child(sound)
	var extra_row := HFlowContainer.new()
	option_row.add_sibling(extra_row)
	var imp := Button.new()
	imp.name = "ImportMenu"
	imp.text = "导入旧存档"
	imp.custom_minimum_size = Vector2(0, 48)
	imp.pressed.connect(func() -> void: show_import())
	extra_row.add_child(imp)
	var recs := Button.new()
	recs.name = "RecordsMenu"
	recs.text = "通关记录"
	recs.custom_minimum_size = Vector2(0, 48)
	recs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recs.pressed.connect(func() -> void: records_requested.emit())
	extra_row.add_child(recs)
	var gear := Button.new()
	gear.name = "SettingsMenu"
	gear.text = "设置"
	gear.custom_minimum_size = Vector2(0, 48)
	gear.pressed.connect(func() -> void: settings_requested.emit())
	extra_row.add_child(gear)
	var full := Button.new()
	full.name = "FullscreenMenu"
	full.visible = fullscreen_toggle_allowed
	full.disabled = not fullscreen_toggle_allowed
	full.text = "全屏"
	full.custom_minimum_size = Vector2(0, 48)
	full.pressed.connect(func() -> void: fullscreen_requested.emit())
	extra_row.add_child(full)
	var full2 := Button.new()
	full2.name = "FullscreenPause"
	full2.visible = fullscreen_toggle_allowed
	full2.disabled = not fullscreen_toggle_allowed
	full2.text = "全屏"
	full2.custom_minimum_size = Vector2(0, 48)
	full2.pressed.connect(func() -> void: fullscreen_requested.emit())
	%Save.add_sibling(full2)
	var gear2 := Button.new()
	gear2.name = "SettingsPause"
	gear2.text = "设置"
	gear2.custom_minimum_size = Vector2(0, 48)
	gear2.pressed.connect(func() -> void: settings_requested.emit())
	%Save.add_sibling(gear2)
	for anchor: Node in [gear,gear2]:
		var dlc:=Button.new()
		dlc.name="DlcMenu"
		dlc.text="DLC 与模块"
		dlc.custom_minimum_size.y=48
		dlc.pressed.connect(func() -> void: dlc_requested.emit())
		anchor.add_sibling(dlc)
	var notes_btn := Button.new()
	notes_btn.name = "NotesPause"
	notes_btn.text = "笔记"
	notes_btn.custom_minimum_size = Vector2(0, 48)
	notes_btn.pressed.connect(func() -> void: notes_requested.emit(""))
	%Save.add_sibling(notes_btn)
	var map_btn := Button.new()
	map_btn.name = "MapPause"
	map_btn.text = "地图"
	map_btn.custom_minimum_size = Vector2(0, 48)
	map_btn.pressed.connect(func() -> void: map_requested.emit(""))
	%Save.add_sibling(map_btn)
	if DebugPanel.enabled():
		for anchor: Node in [gear, gear2]:
			var dev := Button.new()
			dev.name = "DebugTools"
			dev.text = "开发工具"
			dev.custom_minimum_size.y = 44
			dev.pressed.connect(func() -> void: debug_requested.emit())
			anchor.add_sibling(dev)
	load_button.owner = self
	touch_toggle.owner = self
	menu_screen = _build_side_menu()
	pause_screen = _build_menu_screen(pause_panel,true)
	set_touch_enabled(DisplayServer.is_touchscreen_available())
	get_tree().root.size_changed.connect(_resize)
	_resize()
	set_mode("menu")


var _last_input_ms := 0


func _input(event: InputEvent) -> void:
	if not event is InputEventJoypadMotion:
		_last_input_ms = Time.get_ticks_msec()
	if event is InputEventScreenTouch and event.pressed and not _touch_enabled:
		set_touch_enabled(true)


func _process(delta: float) -> void:
	tick_opening(delta)
	if _sense != null and _sense.visible:
		_sense.tick(delta)
	if _bolt_rect != null and _bolt_level > 0.0:
		_bolt_level = maxf(0.0, _bolt_level - delta * 3.0)
		_bolt_rect.color.a = _bolt_level
	if _cam_rect != null and _cam_level > 0.0:
		_cam_level = maxf(0.0, _cam_level - delta * 2.4)
		_cam_rect.color.a = _cam_level
	if _hurt_rect != null and _hurt_level > 0.0:
		_hurt_level = maxf(0.0, _hurt_level - delta * 0.5)
		_hurt_rect.color.a = _hurt_level
	if _toast_seconds > 0.0:
		_toast_seconds -= delta
		%Toast.visible = _toast_seconds > 0.0 and not %Toast.text.is_empty()     # an empty pill is a stray box
		%Toast.modulate.a = clampf(_toast_seconds / 0.6, 0.0, 1.0)


## A phone held upright: the controls are roomier sideways (mobile.js asks for landscape).
var _orient_hint: Label


func _resize() -> void:
	var window := get_tree().root
	var reference := Vector2i(480, 800) if window.size.x < window.size.y else Vector2i(960, 540)
	if window.content_scale_size != reference:
		window.content_scale_size = reference
	clear_touch()
	_update_orient_hint()
	if choice_panel != null and choice_panel.visible:
		_fit_choice.call_deferred()
	_refit_touch.call_deferred()
	_fit_bag.call_deferred()
	_fit_toast.call_deferred()
	_fit_ending.call_deferred()
	_fit_settings.call_deferred()
	_fit_menu_scrolls.call_deferred()
	_resize_list.call_deferred()
	if is_instance_valid(map_panel) and map_panel.visible:
		_map_generation += 1
		_map_center_pending = true
	_fit_map.call_deferred()
	_fit_documents.call_deferred()


var menu_screen: SideMenu
var pause_screen: MenuScreen


var menu_preview: MenuPreview
var boot_splash: BootSplash
signal boot_cue(id: String)


## The main menu: the side menu (side_menu.gd) over the live orbiting campus; the pause menu keeps MenuScreen.
func _build_side_menu() -> SideMenu:
	var content: VBoxContainer = menu.get_node("Margin/Center/Content")
	menu_preview = MenuPreview.new()
	menu.add_child(menu_preview)
	# Above the static photo and its vignette (the side menu shader veils the live view itself).
	var under: Node = menu.get_node_or_null("MenuPhotoShade")
	if under == null: under = menu.get_node_or_null("MenuPhoto")
	menu.move_child(menu_preview, under.get_index() + 1 if under != null else 1)
	var side := SideMenu.new()
	menu.add_child(side)
	side.setup(content)
	if menu.has_node("MenuPhoto"):
		side.set_frost((menu.get_node("MenuPhoto") as TextureRect).texture)
	side.quit_requested.connect(func() -> void: quit_requested.emit())
	menu.get_node("Margin").hide()
	menu.get_node("Margin").queue_free()
	return side


func _build_menu_screen(panel: Control, is_pause: bool) -> MenuScreen:
	var content: VBoxContainer = panel.get_node("Margin/Center/Content")
	var screen := MenuScreen.new()
	panel.add_child(screen)
	screen.setup(content,is_pause)
	panel.get_node("Margin").hide()
	panel.get_node("Margin").queue_free()
	return screen


## The opening animation before the menu (boot_splash.gd); the live campus starts loading underneath.
func play_boot(reduce_motion: bool) -> void:
	if is_instance_valid(boot_splash):
		return
	boot_splash = BootSplash.new()
	boot_splash.reduce_motion = reduce_motion
	boot_splash.spine_x = menu_screen.layout_rects()["spine"].size.x if is_instance_valid(menu_screen) else 14.0
	boot_splash.cue.connect(func(id: String) -> void: boot_cue.emit(id))
	boot_splash.finished.connect(func(_skipped: bool) -> void:
		boot_splash = null
		if menu.visible: menu_screen.enter())
	$Root.add_child(boot_splash)
	if is_instance_valid(menu_preview):
		menu_preview.begin_load()


func boot_playing() -> bool:
	return is_instance_valid(boot_splash)


## The main menu with nothing to animate and nobody touching it for a moment: the app may lower the frame
## rate there (the background crawl is slow), which is most of the time a menu stays open.
func menu_idle() -> bool:
	if not menu.visible or boot_playing() or not menu_screen.idle(): return false
	if Time.get_ticks_msec() - _last_input_ms < 1500: return false
	for panel: Variant in [settings_panel, ach_panel, records_panel, results_panel, _import_panel, selection_panel, choice_panel, map_panel, notes_panel]:
		if is_instance_valid(panel) and (panel as CanvasItem).visible: return false
	if is_instance_valid(_layout_editor): return false
	return true


func _fit_menu_scrolls() -> void:
	if is_instance_valid(menu_screen): menu_screen.refit()
	if is_instance_valid(pause_screen): pause_screen.refit()


func show_pause_detail(text: String) -> void:
	pause_screen.description.text = "时间已暂停，进度保存在本机。\n" + text
	show_notice("")


func set_fullscreen(value: bool) -> void:
	for screen: Control in [menu_screen,pause_screen]:
		var button := screen.find_child("Fullscreen*",true,false) as Button
		button.text = "退出全屏" if value else "进入全屏"


func _update_orient_hint() -> void:
	var upright := get_tree().root.size.x < get_tree().root.size.y
	if _orient_hint == null:
		_orient_hint = Label.new()
		_orient_hint.name = "OrientationHint"
		_orient_hint.text = "请横屏游玩。竖屏不受维护。"
		_orient_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_orient_hint.custom_minimum_size = Vector2(320, 0)
		_orient_hint.modulate = Color(1, 1, 1, 0.6)
		_orient_hint.add_theme_font_size_override("font_size", 12)
		menu.add_child(_orient_hint)
		_orient_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		_orient_hint.position.y -= 24.0
		_orient_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_orient_hint.visible = upright and _touch_enabled


## Gameplay prompt: keys 1–9 pick; Esc / cancel closes when permitted.
func _build_choice() -> void:
	choice_panel = PanelContainer.new()
	choice_panel.name = "ChoicePanel"
	choice_panel.visible = false
	choice_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	choice_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	choice_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	choice_panel.custom_minimum_size = Vector2(360, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_choice_text = Label.new()
	_choice_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_choice_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_choice_text)
	_choice_box = VBoxContainer.new()
	_choice_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choice_scroll = TouchScroll.new()
	_choice_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_choice_scroll.add_child(_choice_box)
	box.add_child(_choice_scroll)
	_choice_cancel = Button.new()
	_choice_cancel.text = "返回 / 取消"
	_choice_cancel.custom_minimum_size.y = 48
	_choice_cancel.pressed.connect(choice_selected.emit.bind(-1))
	box.add_child(_choice_cancel)
	choice_panel.add_child(box)
	$Root.add_child(choice_panel)
	lift_close_button = Button.new()
	lift_close_button.name = "LiftClose"
	lift_close_button.text = "关门 · V"
	lift_close_button.visible = false
	lift_close_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	lift_close_button.position.x -= 40
	lift_close_button.pressed.connect(func() -> void: lift_close_requested.emit())
	hud.add_child(lift_close_button)


var _captions: Label


func show_captions(lines: PackedStringArray) -> void:
	if _captions == null:
		return
	var text := "\n".join(lines)
	if _captions.text != text:
		_captions.text = text
	_captions.position.y = _status_line.position.y + _status_line.size.y + 6.0 if _status_line.visible else 72.0


func captions_text() -> String:
	return _captions.text if _captions != null else ""


## The play HUD as quiet cards over the picture: clock and status with a coloured edge by state, the hot slots,
## a pill for the nearby action and a dot crosshair that opens to a ring when something can be used.
var interact_key := "E"          ## the first key bound to interact (KeyBindings), shown in the prompt


## The main menu's keyboard hint follows the key bindings.
func set_keys_hint(text: String) -> void:
	if is_instance_valid(menu_screen): menu_screen.set_keys_hint(text)
var _status_style: StyleBoxFlat
const STATE_EDGE := {"warn": Color("e6c27a"), "exam": Color("c56a5f"), "": Color("8fd6c0")}


func _style_hud() -> void:
	var runtime := %Runtime as Label
	runtime.theme_type_variation = "HudCard"
	runtime.visible = not runtime.text.is_empty()
	runtime.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	runtime.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	runtime.add_theme_font_size_override("font_size", 22)
	var spacer := Control.new()
	spacer.name = "TopSpacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	runtime.add_sibling(spacer)
	_status_line.theme_type_variation = "HudCard"
	_status_style = BASE_THEME.get_stylebox("normal", "HudCard").duplicate() as StyleBoxFlat
	_status_style.content_margin_left = 48
	_status_line.add_theme_stylebox_override("normal", _status_style)
	_status_line.position = Vector2(20, 72)
	_status_line.add_theme_font_size_override("font_size", 14)
	var prompt := %Prompt as Label
	prompt.theme_type_variation = "HudPill"
	prompt.autowrap_mode = TextServer.AUTOWRAP_OFF
	prompt.anchor_left = 0.5
	prompt.anchor_right = 0.5
	prompt.anchor_top = 0.6
	prompt.anchor_bottom = 0.6
	prompt.offset_left = 0
	prompt.offset_right = 0
	prompt.offset_top = 0
	prompt.offset_bottom = 0
	prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt.grow_vertical = Control.GROW_DIRECTION_BOTH
	prompt.add_theme_constant_override("shadow_outline_size", 0)
	prompt.visible = false
	var cross := hud.get_node("Crosshair") as Label
	cross.text = "·"
	cross.add_theme_font_size_override("font_size", 26)
	cross.add_theme_color_override("font_color", Color(0.93, 0.9, 0.84, 0.75))
	cross.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	cross.add_theme_constant_override("outline_size", 3)


## Old HUD (ui/hud.js): clock, place, period line coloured by state, and the stamina bar that
## appears only when stamina is below full (red while out of breath).
func _build_status() -> void:
	_status_line = Label.new()
	_status_line.name = "Status"
	_status_line.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_status_line.position = Vector2(16, 58)
	_status_line.add_theme_font_size_override("font_size", 15)
	_status_line.visible = false
	hud.add_child(_status_line)
	_status_art = UIArt.view(UIArt.nav("notes"), Vector2.ZERO)
	_status_art.name = "StatusIllustration"
	_status_art.position = Vector2(10, 10)
	_status_art.size = Vector2(28, 28)
	_status_line.add_child(_status_art)
	# Sound captions sit right under the status card (sound-captions.js place()).
	_captions = Label.new()
	_captions.name = "SoundCaptions"
	_captions.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_captions.position = Vector2(20, 120)
	_captions.add_theme_font_size_override("font_size", 14)
	_captions.add_theme_color_override("font_color", Color(0.86, 0.88, 0.92, 0.92))
	_captions.add_theme_constant_override("outline_size", 4)
	_captions.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_captions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_captions)
	_stamina = ProgressBar.new()
	_stamina.name = "Stamina"
	_stamina.show_percentage = false
	_stamina.custom_minimum_size = Vector2(180, 8)
	_stamina.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_stamina.position.y -= 90
	_stamina.visible = false
	hud.add_child(_stamina)


func show_status(place: String, period: String, state: String, clock: String) -> void:
	_status_on = true
	_clock_text = clock
	_status_line.visible = true
	_status_line.text = "%s\n%s" % [period, place]
	_status_art.texture = UIArt.nav("inspect" if period.contains("检查") else ("exam" if state == "exam" else ("warning" if state == "warn" else "notes")))
	_status_line.modulate = Color("#f0d6a0") if state == "warn" else (Color("#f0c4bc") if state == "exam" else Color("#ddd5c4"))
	if _status_style != null:
		_status_style.border_color = STATE_EDGE.get(state, STATE_EDGE[""])
	show_runtime(0)


func reset_status() -> void:
	_status_on = false
	_location = ""
	_clock_text = ""
	%Runtime.text = ""
	%Runtime.visible = false
	if _status_line != null:
		_status_line.visible = false
		_stamina.visible = false


func show_stamina(value: float, maximum: float, out_of_breath: bool) -> void:
	_stamina.visible = value < 99.5
	_stamina.max_value = 100.0
	_stamina.value = clampf(value, 0.0, 100.0)
	_stamina.modulate = Color(0.85, 0.45, 0.35) if out_of_breath else Color(0.55, 0.75, 0.95)


## Bag panel (old manual 背包 tab), redesigned 2026-11-11: a slot grid that shows the capacity on the left
## and the selected item's picture, description and actions on the right. The actions are the same
## as before (使用, the two hot slots, 丢弃); dropping now leaves the item on the floor.
const BAG_COLUMNS := 4
var _bag_detail: VBoxContainer
var _bag_count: Label
var _bag_hint: Label
var _bag_body: HBoxContainer
var _bag_entries: Array = []
var _bag_selected := ""
var _bag_capacity := 8
var _bag_group := ButtonGroup.new()


func _slot_style(bg: Color, edge: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = edge
	style.set_border_width_all(width)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(6)
	return style


func _build_bag() -> void:
	bag_panel = PanelContainer.new()
	bag_panel.name = "BagPanel"
	bag_panel.visible = false
	bag_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	bag_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bag_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	bag_panel.custom_minimum_size = Vector2(440, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var head := HBoxContainer.new()
	head.name = "BagHead"
	head.add_theme_constant_override("separation", 10)
	head.add_child(UIArt.view(UIArt.surface("empty_bag"), Vector2(30, 30)))
	var title := Label.new()
	title.text = "随身物品 · 背包"
	title.theme_type_variation = "HeadingLabel"
	title.add_theme_color_override("font_color", UISkin.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_bag_count = Label.new()
	_bag_count.name = "BagCount"
	_bag_count.theme_type_variation = "HudPill"
	_bag_count.add_theme_font_size_override("font_size", 14)
	head.add_child(_bag_count)
	box.add_child(head)
	_bag_scroll = TouchScroll.new()
	_bag_scroll.name = "BagScroll"
	_bag_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_bag_scroll.follow_focus = true
	_bag_scroll.custom_minimum_size.y = 300
	_bag_body = HBoxContainer.new()
	_bag_body.name = "BagBody"
	_bag_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bag_body.add_theme_constant_override("separation", 16)
	_bag_scroll.add_child(_bag_body)
	var grid := GridContainer.new()
	grid.name = "BagSlots"
	grid.columns = BAG_COLUMNS
	grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_bag_body.add_child(grid)
	_bag_list = grid
	var detail_panel := PanelContainer.new()
	detail_panel.name = "BagDetail"
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var detail_style := UISkin.panel(14)
	detail_style.bg_color = UISkin.CARD
	detail_style.border_color = UISkin.CARD_EDGE
	detail_style.shadow_size = 0
	detail_style.set_corner_radius_all(12)
	detail_panel.add_theme_stylebox_override("panel", detail_style)
	_bag_detail = VBoxContainer.new()
	_bag_detail.add_theme_constant_override("separation", 8)
	detail_panel.add_child(_bag_detail)
	_bag_body.add_child(detail_panel)
	box.add_child(_bag_scroll)
	_bag_drop_row = HBoxContainer.new()
	_bag_drop_row.name = "BagDropConfirm"
	_bag_drop_row.add_theme_constant_override("separation", 10)
	_bag_drop_row.visible = false
	box.add_child(_bag_drop_row)
	_bag_drop_label = Label.new()
	_bag_drop_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bag_drop_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bag_drop_row.add_child(_bag_drop_label)
	var keep := Button.new()
	keep.text = "保留"
	keep.name = "BagKeep"
	keep.custom_minimum_size.y = 48
	keep.pressed.connect(_cancel_drop)
	_bag_drop_row.add_child(keep)
	var discard := Button.new()
	discard.text = "确认丢弃"
	discard.name = "BagConfirmDrop"
	discard.custom_minimum_size.y = 48
	discard.theme_type_variation = "DangerButton"
	discard.pressed.connect(func() -> void:
		var id := _bag_pending_drop
		_cancel_drop()
		if not id.is_empty(): item_drop_requested.emit(id))
	_bag_drop_row.add_child(discard)
	var foot := HBoxContainer.new()
	foot.name = "BagFoot"
	foot.add_theme_constant_override("separation", 12)
	_bag_hint = Label.new()
	_bag_hint.name = "BagHint"
	_bag_hint.text = "丢弃的东西会留在脚边的地上，看着它按交互键可以捡回来。"
	_bag_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bag_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bag_hint.add_theme_font_size_override("font_size", 13)
	_bag_hint.add_theme_color_override("font_color", UISkin.MUTED)
	foot.add_child(_bag_hint)
	var close := Button.new()
	close.name = "BagClose"
	close.text = "关闭背包"
	close.custom_minimum_size = Vector2(140, 44)
	UIArt.button(close, UIArt.nav("close"), 20)
	close.pressed.connect(func() -> void: bag_closed.emit())
	foot.add_child(close)
	box.add_child(foot)
	bag_panel.add_child(box)
	$Root.add_child(bag_panel)
	bag_panel.minimum_size_changed.connect(func() -> void: _fit_bag.call_deferred())
	_search_ring = ProgressBar.new()
	_search_ring.name = "SearchRing"
	_search_ring.show_percentage = false
	_search_ring.custom_minimum_size = Vector2(90, 6)
	_search_ring.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_search_ring.position.y += 22
	_search_ring.max_value = 1.0
	_search_ring.visible = false
	hud.add_child(_search_ring)
	# The text line stays as a hidden record of the slots; the cards below carry key, picture and name.
	_hot_label = Label.new()
	_hot_label.name = "HotSlots"
	_hot_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_hot_label.position = Vector2(16, -40)
	_hot_label.add_theme_font_size_override("font_size", 14)
	_hot_label.visible = false
	hud.add_child(_hot_label)
	_hot_icons = HBoxContainer.new()
	_hot_icons.name = "HotItemArt"
	_hot_icons.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_hot_icons.offset_left = 20
	_hot_icons.offset_top = -98
	_hot_icons.offset_bottom = -20
	_hot_icons.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hot_icons.add_theme_constant_override("separation", 8)
	_hot_icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_hot_icons)
	for i in 2:
		var slot := PanelContainer.new()
		slot.name = "HotSlot%d" % (i + 1)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := _slot_style(Color(0.03, 0.05, 0.06, 0.66), Color(0.92, 0.9, 0.85, 0.18), 1)
		style.set_content_margin_all(6)
		slot.add_theme_stylebox_override("panel", style)
		_hot_icons.add_child(slot)
		var body := VBoxContainer.new()
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_theme_constant_override("separation", 2)
		slot.add_child(body)
		var art := UIArt.view(null, Vector2(56, 44))
		art.name = "HotIllustration%d" % (i + 1)
		body.add_child(art)
		_hot_art.append(art)
		var name_label := Label.new()
		name_label.name = "HotName%d" % (i + 1)
		name_label.text = "空"
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.clip_text = true
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.custom_minimum_size.x = 56
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.add_theme_color_override("font_color", UISkin.MUTED)
		body.add_child(name_label)
		var key := Label.new()
		key.name = "HotKey%d" % (i + 1)
		key.text = str(i + 1)
		key.theme_type_variation = "HudPill"
		key.add_theme_font_size_override("font_size", 11)
		var cap := BASE_THEME.get_stylebox("normal", "HudPill").duplicate() as StyleBoxFlat
		cap.set_content_margin_all(1)
		cap.content_margin_left = 6
		cap.content_margin_right = 6
		cap.set_corner_radius_all(5)
		key.add_theme_stylebox_override("normal", cap)
		key.position = Vector2(-4, -6)
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# A PanelContainer lays its children out; a plain Control keeps the key cap free in the corner.
		var anchor := Control.new()
		anchor.name = "HotKeyAnchor%d" % (i + 1)
		anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		anchor.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		anchor.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		anchor.add_child(key)
		slot.add_child(anchor)


func _bag_slot(e: Dictionary, size: float) -> Button:
	var id := String(e["id"])
	var slot := Button.new()
	slot.name = "Slot_" + id
	slot.toggle_mode = true
	slot.button_group = _bag_group
	slot.custom_minimum_size = Vector2(size, size)
	slot.tooltip_text = String(e["name"])
	slot.add_theme_stylebox_override("normal", _slot_style(UISkin.CARD, UISkin.CARD_EDGE, 1))
	slot.add_theme_stylebox_override("hover", _slot_style(UISkin.CARD.lightened(0.05), Color(UISkin.ACCENT, 0.55), 1))
	slot.add_theme_stylebox_override("pressed", _slot_style(UISkin.CARD.lightened(0.08), UISkin.ACCENT, 2))
	slot.add_theme_stylebox_override("hover_pressed", _slot_style(UISkin.CARD.lightened(0.1), UISkin.ACCENT, 2))
	slot.button_pressed = id == _bag_selected
	var art := UIArt.view(UIArt.item(id), Vector2.ZERO)
	art.name = "ItemArt_" + id
	art.tooltip_text = String(e["name"])
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.offset_left = 8
	art.offset_top = 6
	art.offset_right = -8
	art.offset_bottom = -20
	slot.add_child(art)
	var label := Label.new()
	label.name = "SlotName"
	label.text = String(e["short"]) if e.has("short") else String(e["name"])
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", UISkin.INK)
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_top = -20
	label.offset_left = 4
	label.offset_right = -4
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(label)
	var hot := int(e.get("hot", -1))
	if hot >= 0:
		var badge := Label.new()
		badge.name = "SlotHot"
		badge.text = str(hot + 1)
		badge.theme_type_variation = "HudPill"
		badge.add_theme_font_size_override("font_size", 11)
		var cap := BASE_THEME.get_stylebox("normal", "HudPill").duplicate() as StyleBoxFlat
		cap.set_content_margin_all(1)
		cap.content_margin_left = 6
		cap.content_margin_right = 6
		cap.set_corner_radius_all(5)
		cap.border_color = UISkin.WARM
		badge.add_theme_stylebox_override("normal", cap)
		badge.add_theme_color_override("font_color", UISkin.WARM)
		badge.position = Vector2(4, 4)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(badge)
	slot.pressed.connect(select_bag_item.bind(id))
	slot.focus_entered.connect(func() -> void:
		if _bag_selected != id: select_bag_item(id))
	return slot


func _empty_slot(index: int, size: float) -> Panel:
	var empty := Panel.new()
	empty.name = "SlotEmpty_%d" % index
	empty.custom_minimum_size = Vector2(size, size)
	empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := _slot_style(Color(UISkin.CARD, 0.45), Color(UISkin.CARD_EDGE, 0.7), 1)
	empty.add_theme_stylebox_override("panel", style)
	return empty


func _slot_size() -> float:
	var screen := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(960, 540)
	var width := minf(900.0, screen.x - 24.0)
	return clampf((width * 0.38 - 8.0 * (BAG_COLUMNS - 1)) / BAG_COLUMNS, 60.0, 86.0)


## entries: [{id, name, text, hot (-1, 0 or 1)}]; capacity is the bag size (empty slots are drawn).
func show_bag(entries: Array, capacity: int = -1) -> void:
	_bag_entries = entries.duplicate(true)
	if capacity > 0:
		_bag_capacity = capacity
	var ids: Array = entries.map(func(e: Dictionary) -> String: return String(e["id"]))
	if not ids.has(_bag_selected):
		_bag_selected = String(ids[0]) if not ids.is_empty() else ""
	_cancel_drop()
	_bag_scroll.stop_motion()
	for child in _bag_list.get_children():
		_bag_list.remove_child(child)
		child.queue_free()
	_bag_group = ButtonGroup.new()
	var size := _slot_size()
	for e: Dictionary in entries:
		_bag_list.add_child(_bag_slot(e, size))
	for i in range(entries.size(), maxi(_bag_capacity, entries.size())):
		_bag_list.add_child(_empty_slot(i, size))
	_bag_count.text = "%d / %d" % [entries.size(), maxi(_bag_capacity, entries.size())]
	_bag_count.add_theme_color_override("font_color", UISkin.WARM if entries.size() >= _bag_capacity else UISkin.INK)
	_show_bag_detail()
	var was_open := bag_panel.visible
	bag_panel.visible = true
	_fit_bag()
	_fit_bag.call_deferred()     # wrapped text and the action row settle after their first layout pass
	if not was_open:
		_bag_scroll.scroll_vertical = 0
	if not was_open and not _touch_enabled:
		var slot := _bag_list.get_node_or_null("Slot_" + _bag_selected) as Button
		if slot != null:
			slot.grab_focus.call_deferred()


func select_bag_item(id: String) -> void:
	if id != _bag_selected:
		_cancel_drop()
	_bag_selected = id
	for child in _bag_list.get_children():
		if child is Button:
			(child as Button).set_pressed_no_signal(child.name == "Slot_" + id)
	_show_bag_detail()


func bag_selected() -> String:
	return _bag_selected


func _show_bag_detail() -> void:
	for child in _bag_detail.get_children():
		_bag_detail.remove_child(child)
		child.queue_free()
	var entry: Dictionary = {}
	for e: Dictionary in _bag_entries:
		if String(e["id"]) == _bag_selected:
			entry = e
	if entry.is_empty():
		_bag_detail.add_child(UIArt.view(UIArt.surface("empty_bag"), Vector2(0, 120)))
		var empty := Label.new()
		empty.name = "BagEmpty"
		empty.text = "背包是空的。\n探索时找到的物品会收在这里。"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", UISkin.MUTED)
		_bag_detail.add_child(empty)
		return
	var id := String(entry["id"])
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	_bag_detail.add_child(top)
	var art := UIArt.view(UIArt.item(id), Vector2(96, 96))
	art.name = "BagDetailArt"
	top.add_child(art)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	copy.add_theme_constant_override("separation", 6)
	top.add_child(copy)
	var name_label := Label.new()
	name_label.name = "BagDetailName"
	name_label.text = String(entry["name"])
	name_label.theme_type_variation = "HeadingLabel"
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size.x = 140
	name_label.add_theme_color_override("font_color", UISkin.ACCENT)
	copy.add_child(name_label)
	var hot := int(entry.get("hot", -1))
	var tag := Label.new()
	tag.name = "BagDetailTag"
	tag.text = ("在快捷栏 %d · 按 %d 直接使用" % [hot + 1, hot + 1]) if hot >= 0 else "不在快捷栏"
	tag.add_theme_font_size_override("font_size", 13)
	tag.add_theme_color_override("font_color", UISkin.WARM if hot >= 0 else UISkin.MUTED)
	copy.add_child(tag)
	var desc := Label.new()
	desc.name = "BagDetailText"
	desc.text = String(entry["text"])
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A known wrap width from the first layout pass: an autowrapped label at width 0 asks for one line per glyph.
	desc.custom_minimum_size.x = 260
	desc.add_theme_color_override("font_color", UISkin.INK.darkened(0.12))
	_bag_detail.add_child(desc)
	# A grid (not a flow) so the panel always knows the row's height; large text gets two columns.
	var buttons := GridContainer.new()
	buttons.name = "BagActions"
	var root_theme := $Root.theme as Theme
	buttons.columns = 4 if root_theme == null or root_theme.default_font_size <= 18 else 2
	buttons.add_theme_constant_override("h_separation", 8)
	buttons.add_theme_constant_override("v_separation", 8)
	for spec: Array in [["使用", -1, "interact"], ["快捷栏 1", 0, ""], ["快捷栏 2", 1, ""], ["丢弃", -2, "close"]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(84, 44)
		b.name = "Drop_" + id if spec[1] == -2 else "Item_%s_%d" % [id, int(spec[1])]
		if spec[1] == -1:
			b.theme_type_variation = "PrimaryButton"
			b.custom_minimum_size.x = 100
			b.pressed.connect(item_use_requested.emit.bind(id))
		elif spec[1] == -2:
			b.theme_type_variation = "DangerButton"
			b.tooltip_text = "放在脚边的地上，之后可以捡回来"
			var shown := String(entry["short"]) if entry.has("short") else String(entry["name"])
			b.pressed.connect(func() -> void:
				_bag_pending_drop = id
				_bag_drop_label.text = "丢弃「%s」？它会留在脚边的地上。" % shown
				_bag_drop_row.show()
				_fit_bag.call_deferred())
		else:
			var slot_index := int(spec[1])
			if hot == slot_index:
				b.text = "✓ " + String(spec[0])
				b.tooltip_text = "已经在快捷栏 %d" % (slot_index + 1)
			else:
				b.tooltip_text = "放到快捷栏 %d" % (slot_index + 1)
			b.pressed.connect(item_hot_requested.emit.bind(slot_index, id))
		buttons.add_child(b)
	_bag_detail.add_child(buttons)


func _fit_bag() -> void:
	if bag_panel == null or not bag_panel.visible:
		return
	var size := _slot_size()
	for child in _bag_list.get_children():
		(child as Control).custom_minimum_size = Vector2(size, size)
	var grid_w := size * BAG_COLUMNS + 8.0 * (BAG_COLUMNS - 1)
	var rows := ceili(float(_bag_list.get_child_count()) / BAG_COLUMNS)
	PanelLayout.fit(bag_panel, _bag_scroll, grid_w + 540.0, maxf(rows * (size + 8.0), 300.0))


func hide_bag() -> void:
	_cancel_drop()
	bag_panel.visible = false


func _cancel_drop() -> void:
	_bag_pending_drop = ""
	if is_instance_valid(_bag_drop_row):
		_bag_drop_row.hide()
		_fit_bag.call_deferred()


func bag_open() -> bool:
	return bag_panel != null and bag_panel.visible


func show_search(progress: float) -> void:
	_search_ring.visible = progress > 0.0
	_search_ring.value = progress


## The two hot slots: key cap, the item's picture and its name (empty slots say so).
func show_hot(text: String, ids: Array = [], names: Array = []) -> void:
	_hot_label.text = text
	for i in 2:
		var id := String(ids[i]) if i < ids.size() and ids[i] != null else ""
		var texture := UIArt.item(id)
		if _hot_art[i].texture != texture:
			_hot_art[i].texture = texture
		var name_label := _hot_icons.get_child(i).find_child("HotName%d" % (i + 1), true, false) as Label
		var shown := String(names[i]) if i < names.size() and id != "" else ("空" if id == "" else id)
		if name_label != null and name_label.text != shown:
			name_label.text = shown
			name_label.add_theme_color_override("font_color", UISkin.INK if id != "" else UISkin.MUTED)
		(_hot_icons.get_child(i) as Control).modulate.a = 1.0 if id != "" else 0.6
		var button := _touch_buttons.get("hot%d" % (i + 1)) as Button
		if button != null and button.icon != texture:
			button.icon = texture


## Death: a dark red fade while the (not yet ported) death scene would play, then the record
## card with message, epitaph, cause and repeated-death hints (old #die panel).
var _death_fade: ColorRect
var death_panel: PanelContainer
var _death_text: Label
var _death_art: TextureRect


func _build_death() -> void:
	_death_fade = ColorRect.new()
	_death_fade.name = "DeathFade"
	_death_fade.color = Color(1, 1, 1, 1)
	_death_fade.material = _death_material()
	_death_fade.visible = false
	_death_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	$Root.add_child(_death_fade)
	death_panel = PanelContainer.new()
	death_panel.name = "DeathPanel"
	death_panel.visible = false
	death_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	death_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	death_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	death_panel.minimum_size_changed.connect(func() -> void: _fit_documents.call_deferred())
	var box := VBoxContainer.new()
	_death_scroll = TouchScroll.new()
	_death_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_death_scroll.follow_focus = true
	_death_text = Label.new()
	_death_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_death_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var death_content := VBoxContainer.new()
	death_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_death_art = UIArt.view(null, Vector2(0, 148))
	_death_art.name = "DeathIllustration"
	death_content.add_child(_death_art)
	death_content.add_child(_death_text)
	_death_scroll.add_child(death_content)
	box.add_child(_death_scroll)
	var back := Button.new()
	back.name = "DeathMenu"
	back.text = "回到主菜单"
	back.custom_minimum_size.y = 44
	back.pressed.connect(func() -> void: death_menu_requested.emit())
	box.add_child(back)
	death_panel.add_child(box)
	UIArt.decorate(death_panel)
	$Root.add_child(death_panel)


## Screen-space overlay accompanying the world death scene: the style follows the family of the
## cause. 0 closing vignette, 1 rising water, 2 flickering specks, 3 falling streaks, 4 hands from the sides.
const DEATH_STYLE := {"drown": [1, Color(0.04, 0.12, 0.15)], "water": [1, Color(0.05, 0.1, 0.16)], "freeze": [1, Color(0.55, 0.7, 0.78)],
	"swarm": [2, Color(0.06, 0.05, 0.03)], "shatter": [2, Color(0.75, 0.8, 0.85)], "floor": [3, Color(0.03, 0.03, 0.04)],
	"deep": [3, Color(0.02, 0.02, 0.03)], "slit": [3, Color(0.0, 0.0, 0.0)], "squeeze": [3, Color(0.04, 0.04, 0.04)],
	"campus_fall": [3, Color(0.03, 0.03, 0.04)], "grip": [4, Color(0.04, 0.0, 0.0)], "hand": [4, Color(0.05, 0.02, 0.02)],
	"liftdoor": [4, Color(0.03, 0.03, 0.04)], "follow": [4, Color(0.06, 0.06, 0.07)], "neck": [4, Color(0.03, 0.0, 0.0)],
	"trash": [4, Color(0.0, 0.0, 0.0)], "ring": [0, Color(0.1, 0.1, 0.09)], "names": [0, Color(0.1, 0.02, 0.02)]}


static func death_style(fx: String) -> Array:
	return DEATH_STYLE.get(fx, [0, Color(0.1, 0.0, 0.0)])


func _death_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.1, 0.0, 0.0, 1.0);
uniform float progress = 0.0;
uniform int style = 0;
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 uv = UV;
	float a = 0.0;
	float d = distance(uv, vec2(0.5)) * 1.4142;
	if (style == 0) {
		a = smoothstep(1.0 - progress, 1.25 - progress * 0.5, d);
		a = max(a, progress * 0.55);
	} else if (style == 1) {
		float lvl = 1.0 - progress;
		a = smoothstep(lvl - 0.04, lvl + 0.04, uv.y) * 0.9;
		a = max(a, progress * 0.3);
	} else if (style == 2) {
		float t = floor(TIME * 14.0);
		float s = step(0.95 - progress * 0.35, h(floor(uv * vec2(90.0, 50.0)) + t));
		a = max(s * 0.9, progress * 0.5);
	} else if (style == 3) {
		a = progress * progress;
		a = max(a, smoothstep(0.0, 1.0, (1.0 - uv.y) * progress) * 0.8);
		float st = step(0.985, h(vec2(floor(uv.x * 60.0), floor(TIME * 20.0))));
		a = max(a, st * progress * 0.6);
	} else {
		float side = min(uv.x, 1.0 - uv.x);
		a = smoothstep(progress * 0.5, progress * 0.5 - 0.12, side);
		a = max(a, progress * 0.45);
	}
	COLOR = vec4(tint.rgb, clamp(a, 0.0, 0.95));
}"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat


func show_death_scene(fx: String, progress: float) -> void:
	var info := death_style(fx)
	var mat := _death_fade.material as ShaderMaterial
	mat.set_shader_parameter("style", int(info[0]))
	mat.set_shader_parameter("tint", info[1])
	mat.set_shader_parameter("progress", clampf(progress, 0.0, 1.0))
	_death_fade.visible = progress > 0.0


func death_scene_style() -> int:
	return int((_death_fade.material as ShaderMaterial).get_shader_parameter("style"))


func show_death_card(message: String, epitaph: String, cause: String, hints: PackedStringArray, achieved: PackedStringArray = PackedStringArray(), score_line: String = "", source: String = "") -> void:
	_death_art.texture = UIArt.memory(source)
	_death_art.visible = _death_art.texture != null
	var lines := [message]
	if not epitaph.is_empty():
		lines.append("「%s」" % epitaph)
	if not cause.is_empty():
		lines.append(cause)
	for h: String in hints:
		lines.append("· " + h)
	if not achieved.is_empty():
		lines.append("本局新达成\n" + "\n".join(achieved))
	if not score_line.is_empty():
		lines.append(score_line)
	_death_text.text = "\n\n".join(lines)
	death_panel.visible = true
	_death_scroll.scroll_vertical = 0
	_fit_documents.call_deferred()


## The locker slits (old #hideslits): a dark screen with thin lit lines.
var _hide_overlay: Control


func show_hiding(on: bool) -> void:
	if _hide_overlay == null:
		_hide_overlay = Control.new()
		_hide_overlay.name = "HideSlits"
		_hide_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hide_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var dark := ColorRect.new()
		dark.color = Color(0.02, 0.025, 0.03, 0.96)
		dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_hide_overlay.add_child(dark)
		for i in 6:
			var slit := ColorRect.new()
			slit.color = Color(0.45, 0.5, 0.52, 0.35)
			slit.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slit.anchor_left = 0.2
			slit.anchor_right = 0.8
			slit.anchor_top = 0.25 + i * 0.075
			slit.anchor_bottom = 0.25 + i * 0.075
			slit.offset_bottom = 6
			_hide_overlay.add_child(slit)
		$Root.add_child(_hide_overlay)
		$Root.move_child(_hide_overlay, 0)
	_hide_overlay.visible = on


## Achievements list: unlocked entries show their memory line, locked ones only the name.
var ach_panel: PanelContainer
var _ach_list: VBoxContainer
var _ach_head: Label


var _ach_tab := "全部"
var _ach_tabs: HFlowContainer
var _list_extra: Button


## Tabs 全部 / 普通 / 精英 / 史诗 (achievements-ui.js); the head always counts all of them.
func show_achievements(entries: Array, points: int, tab: String = "") -> void:
	if tab != "":
		_ach_tab = tab
	var rows: Array = []
	var got := 0
	for e: Dictionary in entries:
		var text := "%s · %s" % [e["tier"], e["name"]]
		if e.has("progress"):
			text += "  （%d / %d）" % [e["progress"]["n"], e["progress"]["of"]]
		if e["unlocked"]:
			got += 1
		if _ach_tab == "全部" or e["tier"] == _ach_tab:
			rows.append({"id": e.get("id", ""), "text": text, "on": e["unlocked"], "memo": e["memo"]})
	show_list("成就  %d / %d　·　积分 %d" % [got, entries.size(), points], rows)
	if _ach_tabs == null:
		_ach_tabs = HFlowContainer.new()
		_ach_tabs.name = "AchievementTabs"
		var box: Node = _ach_head.get_parent()
		box.add_child(_ach_tabs)
		box.move_child(_ach_tabs, 1)
	for c in _ach_tabs.get_children():
		c.queue_free()
	_ach_tabs.show()
	for name: String in ["全部", "普通", "精英", "史诗"]:
		var b := Button.new()
		b.name = "Tab_" + name
		b.text = name
		b.toggle_mode = true
		b.button_pressed = name == _ach_tab
		b.pressed.connect(func() -> void: show_achievements(entries, points, name))
		_ach_tabs.add_child(b)


## The death archive: every real cause of death gets a file the first time it happens.
func show_archive(rows: Array, known: int, total: int) -> void:
	var list: Array = []
	for r: Dictionary in rows:
		list.append({"text": "%02d · %s%s" % [r["no"], r["name"] if r["on"] else "？？？", "  ×%d" % r["count"] if r["on"] and r["count"] > 1 else ""], "on": r["on"], "memo": r["memo"]})
	show_list("CG 档案馆 · 死亡与结局  已记录 %d / %d" % [known, total], list)


## A scrolling list over the menu: rows of {text, on, memo}; locked rows show their text only.
func show_list(head: String, rows: Array) -> void:
	if ach_panel == null:
		ach_panel = PanelContainer.new()
		ach_panel.name = "AchievementsPanel"
		ach_panel.resized.connect(_center_list)
		ach_panel.minimum_size_changed.connect(func() -> void: _resize_list.call_deferred())
		ach_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		ach_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		ach_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		ach_panel.custom_minimum_size = Vector2(560, 0)
		var back := UISkin.panel(16)
		ach_panel.add_theme_stylebox_override("panel", back)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		_ach_head = Label.new()
		_ach_head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_ach_head.add_theme_color_override("font_color",UISkin.ACCENT)
		box.add_child(_ach_head)
		var scroll := TouchScroll.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = true
		scroll.custom_minimum_size = Vector2(520, 360)
		_ach_list = VBoxContainer.new()
		_ach_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_ach_list.add_theme_constant_override("separation",10)
		scroll.add_child(_ach_list)
		box.add_child(scroll)
		var close := Button.new()
		close.text = "关闭"
		close.pressed.connect(func() -> void: ach_panel.visible = false)
		box.add_child(close)
		ach_panel.add_child(box)
		UIArt.decorate(ach_panel)
		$Root.add_child(ach_panel)
	if is_instance_valid(_ach_tabs): _ach_tabs.hide()
	(_ach_list.get_parent() as TouchScroll).stop_motion()
	if is_instance_valid(_list_extra):
		_list_extra.hide()
		_list_extra.queue_free()
		_list_extra = null
	for child in _ach_list.get_children():
		_ach_list.remove_child(child)
		child.queue_free()
	for r: Dictionary in rows:
		var row := UISkin.card(_ach_list)
		var details := HBoxContainer.new()
		details.add_theme_constant_override("separation", 12)
		var art := UIArt.view(UIArt.entry(String(r.get("id", "")), bool(r["on"])), Vector2(76, 76))
		art.name = "EntryArt_" + String(r.get("id", "legacy")).replace(":", "_").replace(".", "_")
		details.add_child(art)
		var line := Label.new()
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var text := String(r["text"])
		if r["on"] and not String(r["memo"]).is_empty():
			text += "\n    " + String(r["memo"])
		line.text = ("✓ " if r["on"] else "· ") + text
		line.modulate = Color(1, 1, 1, 1) if r["on"] else Color(1, 1, 1, 0.55)
		details.add_child(line)
		row.add_child(details)
		var action: Callable = r.get("action",Callable())
		if action.is_valid():
			var replay := Button.new()
			replay.text = r.get("label","查看")
			replay.custom_minimum_size.y = 44
			replay.set_meta("entry_id",r.get("id",""))
			replay.pressed.connect(action)
			row.add_child(replay)
	_ach_head.text = head
	_resize_list()
	ach_panel.visible = true


func list_tabs(tabs: Array) -> void:
	if _ach_tabs == null:
		_ach_tabs = HFlowContainer.new()
		_ach_head.get_parent().add_child(_ach_tabs)
		_ach_head.get_parent().move_child(_ach_tabs,1)
	for child in _ach_tabs.get_children():
		_ach_tabs.remove_child(child)
		child.queue_free()
	for tab: Dictionary in tabs:
		var button := Button.new()
		button.text = tab["text"]
		button.toggle_mode = true
		button.button_pressed = tab.get("on",false)
		button.custom_minimum_size.y = 44
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(tab["action"])
		_ach_tabs.add_child(button)
	_ach_tabs.show()
	_resize_list()


func list_footer(text: String, action: Callable) -> void:
	_list_extra = Button.new()
	_list_extra.text = text
	_list_extra.pressed.connect(action)
	_ach_head.get_parent().add_child(_list_extra)
	_resize_list()


func focus_list_entry(id: String) -> void:
	var first: Button
	for child in _ach_list.find_children("*","Button",true,false):
		if child is Button:
			if first == null: first = child
			if id != "" and child.get_meta("entry_id","") == id:
				child.grab_focus()
				return
	if first != null: first.grab_focus()


func _resize_list() -> void:
	if not is_instance_valid(ach_panel): return
	var view := get_viewport().get_visible_rect().size
	var width := minf(720,maxf(240,view.x-32))
	var scroll := _ach_list.get_parent() as ScrollContainer
	_ach_head.custom_minimum_size.x = width-32
	_ach_head.size.x = width-32
	_ach_list.custom_minimum_size.x = width-46
	var fixed := 32.0
	for child in _ach_head.get_parent().get_children():
		if child is Control and child != scroll and child.visible:
			fixed += child.get_combined_minimum_size().y + 8
	scroll.custom_minimum_size = Vector2(width-32,maxf(60,minf(390,view.y-fixed-32)))
	ach_panel.custom_minimum_size = Vector2(width,0)
	ach_panel.reset_size()
	_center_list()


func _center_list() -> void:
	if is_instance_valid(ach_panel):
		ach_panel.position = (get_viewport().get_visible_rect().size-ach_panel.size)*.5


## The prologue (prologue.js PRO_PAGES): white text on black, page by page; E / Space / a tap goes on,
## 跳过 skips. It runs while the game is paused.
const OPENING := ["你是这学期转来的。", "高二（二）班。第四节，语文。老师在念一篇课文，念到一半，又从头念了一遍。",
	"前排的人回头问你借橡皮。你还没记住他的名字。\n他好像也不记得你的。", "才第三天。这栋楼你只认得三层。\n可是你数过——楼梯一共有五层半。",
	"粉笔灰在光里飘。你开始数秒：一，二，三……数到第七秒的时候，它们停在了半空。", "眼皮很重。黑板上的字开始往下淌，淌成一行一行的竖线。",
	"你把脸埋进胳膊里。袖子上有一股不属于你的味道。", "……", "你睁开眼。\n教室里还是坐满了人。只是没有一个人在呼吸。",
	"窗外的颜色不见了。走廊里很安静，安静得能听见灯管里的电流。", "下课铃没有响。\n你忽然很确定：这不是你转来的那个学校。\n而它，已经知道你醒了。"]
const OPENING_PAGE := 3.4
## The menu photo (menu-photo.js): the campus at 22:18 behind the menu, under a dark vignette
## (radial gradient: clear-ish at 72% / 42%, nearly black at the edges). The picture is shot once by
## tools/capture/capture_menu_photo.gd and kept as assets/ui/menu_photo.jpg.
func _build_menu_photo() -> void:
	var path := "res://assets/ui/menu_photo.jpg"
	if not ResourceLoader.exists(path):
		return
	var pic := TextureRect.new()
	pic.name = "MenuPhoto"
	pic.texture = load(path) as Texture2D
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(pic)
	menu.move_child(pic, 1)
	if menu.has_node("Backdrop"):
		(menu.get_node("Backdrop") as ColorRect).color = Color(0.016, 0.027, 0.039, 1.0)
	var shade := TextureRect.new()
	shade.name = "MenuPhotoShade"
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(0.039, 0.07, 0.086, 0.34), Color(0.012, 0.024, 0.035, 0.92)])
	grad.offsets = PackedFloat32Array([0.0, 0.62])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.72, 0.42)
	gt.fill_to = Vector2(1.4, 1.1)
	gt.width = 256
	gt.height = 256
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(shade)
	menu.move_child(shade, 2)


var _cut_fade: ColorRect
var _hud_was := true
var _cut_caption: Label


## Over the live cutscenes: a black fade (0 clear … 1 black) and a caption line at the bottom.
## body.cut: while a cutscene plays the HUD (status, hotbar, prompt, crosshair, captions) is hidden.
func cut_mode(on: bool) -> void:
	if on:
		show_notice("") # Cut captions replace the last ordinary line, as os(..., OS_FORCE) did.
		_hud_was = hud.visible
		hud.visible = false
	else:
		hud.visible = _hud_was


func cut_fade(v: float) -> void:
	if _cut_fade == null:
		_cut_fade = ColorRect.new()
		_cut_fade.name = "CutFade"
		_cut_fade.color = Color.BLACK
		_cut_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cut_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_cut_fade.process_mode = Node.PROCESS_MODE_ALWAYS
		$Root.add_child(_cut_fade)
	_cut_fade.modulate.a = clampf(v, 0.0, 1.0)
	_cut_fade.visible = v > 0.001


var _import_panel: PanelContainer
var _import_text: TextEdit
var _import_msg: Label
var _import_scroll: TouchScroll
var _death_scroll: TouchScroll


## 导入旧存档: paste the old save's JSON (the localStorage entry "wdfz3d"), see game/features/compatibility/legacy_save.gd.
func show_import() -> void:
	if _import_panel == null:
		_import_panel = PanelContainer.new()
		_import_panel.name = "LegacyImport"
		_import_panel.minimum_size_changed.connect(func() -> void: _fit_documents.call_deferred())
		_import_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		_import_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_import_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		var back := UISkin.panel(14)
		_import_panel.add_theme_stylebox_override("panel", back)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		var head := Label.new()
		head.text = "导入旧版存档"
		head.modulate = Color(1.0, 0.9, 0.55)
		box.add_child(head)
		_import_scroll = TouchScroll.new()
		_import_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_import_scroll.follow_focus = true
		var body := VBoxContainer.new()
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_theme_constant_override("separation",8)
		_import_scroll.add_child(body)
		box.add_child(_import_scroll)
		var help := Label.new()
		help.text = "把旧版网页存档（浏览器里键名 wdfz3d 的那段 JSON）贴在下面。接续位置、时间、背包、路线、巡察、异象与调查记录。导入前会校验整局；不支持的 DLC 存档会说明原因。原文保留在新档中，这一局标记为「从旧存档继续」。"
		help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		help.modulate = Color(1, 1, 1, 0.75)
		body.add_child(help)
		_import_text = TextEdit.new()
		_import_text.name = "ImportText"
		_import_text.custom_minimum_size = Vector2(0, 180)
		body.add_child(_import_text)
		_import_msg = Label.new()
		_import_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_import_msg.modulate = Color(0.95, 0.6, 0.5)
		body.add_child(_import_msg)
		var row := HFlowContainer.new()
		var go := Button.new()
		go.name = "ImportGo"
		go.text = "导入并开始"
		go.custom_minimum_size.y = 44
		go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		go.pressed.connect(func() -> void: legacy_import_requested.emit(_import_text.text))
		row.add_child(go)
		var close := Button.new()
		close.name = "ImportClose"
		close.text = "关闭"
		close.custom_minimum_size.y = 44
		close.pressed.connect(func() -> void: _import_panel.visible = false)
		row.add_child(close)
		box.add_child(row)
		_import_panel.add_child(box)
		$Root.add_child(_import_panel)
	_import_msg.text = ""
	_import_panel.visible = true
	_import_scroll.scroll_vertical = 0
	_fit_documents.call_deferred()


func show_import_result(error: String) -> void:
	if _import_panel == null:
		return
	if error.is_empty():
		_import_panel.visible = false
	else:
		_import_msg.text = "没有导入：" + error
		_fit_documents.call_deferred()


var _cut_flash: ColorRect


## White flash over a cutscene (0 clear … 1 white).
func cut_flash(v: float) -> void:
	if _cut_flash == null:
		_cut_flash = ColorRect.new()
		_cut_flash.name = "CutFlash"
		_cut_flash.color = Color.WHITE
		_cut_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cut_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_cut_flash.process_mode = Node.PROCESS_MODE_ALWAYS
		$Root.add_child(_cut_flash)
	_cut_flash.modulate.a = clampf(v, 0.0, 1.0)
	_cut_flash.visible = v > 0.001


func cut_caption(text: String) -> void:
	if _cut_caption == null:
		_cut_caption = Label.new()
		_cut_caption.name = "CutCaption"
		_cut_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cut_caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		_cut_caption.offset_top = -150.0
		_cut_caption.offset_bottom = -60.0
		_cut_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_cut_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_cut_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_cut_caption.add_theme_font_size_override("font_size", 24)
		_cut_caption.add_theme_color_override("font_outline_color", Color.BLACK)
		_cut_caption.add_theme_constant_override("outline_size", 6)
		_cut_caption.process_mode = Node.PROCESS_MODE_ALWAYS
		$Root.add_child(_cut_caption)
	_cut_caption.text = text
	_cut_caption.visible = not text.is_empty()


var opening_panel: Control
var _opening_text: Label
var _opening_i := -1
var _opening_t := 0.0


func show_opening() -> void:
	if opening_panel == null:
		opening_panel = ColorRect.new()
		opening_panel.name = "Opening"
		(opening_panel as ColorRect).color = Color(0, 0, 0, 1)
		opening_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		opening_panel.process_mode = Node.PROCESS_MODE_ALWAYS
		_opening_text = Label.new()
		_opening_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_opening_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_opening_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_opening_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_opening_text.add_theme_font_size_override("font_size", 26)
		_opening_text.offset_left = 72.0
		_opening_text.offset_right = -72.0
		opening_panel.add_child(_opening_text)
		var skip := Button.new()
		skip.text = "跳过"
		skip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		skip.position -= Vector2(110, 70)
		skip.pressed.connect(func() -> void: _end_opening(true))
		opening_panel.add_child(skip)
		opening_panel.gui_input.connect(func(e: InputEvent) -> void:
			if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
				_next_opening())
		$Root.add_child(opening_panel)
	_opening_i = 0
	_opening_t = 0.0
	_opening_text.text = OPENING[0]
	opening_panel.visible = true


func opening_on() -> bool:
	return opening_panel != null and opening_panel.visible


func _next_opening() -> void:
	if not opening_on():
		return
	_opening_i += 1
	_opening_t = 0.0
	if _opening_i >= OPENING.size():
		_end_opening(false)
	else:
		_opening_text.text = OPENING[_opening_i]


func _end_opening(skipped: bool) -> void:
	if not opening_on():
		return
	opening_panel.visible = false
	opening_finished.emit(skipped)


func tick_opening(delta: float) -> void:
	if not opening_on():
		return
	_opening_t += delta
	if _opening_t >= OPENING_PAGE:
		_next_opening()


## One world pass under the HUD: original grading and low-SAN feedback.
var _sense: ScenePost


func scene_post() -> ScenePost:
	if _sense == null:
		_sense = ScenePost.new()
		var world_layer := CanvasLayer.new()
		world_layer.name = "WorldGrading"
		world_layer.layer = -2
		add_child(world_layer)
		world_layer.add_child(_sense)
		_sense.visible = _mode != "menu"
	return _sense


func show_sensory(v: Dictionary, blink: float, t: float) -> void:
	scene_post().sensory(v,blink,t)


func set_normal_world(value: float) -> void:
	var post := scene_post()
	post.world_normal = clampf(value,0.0,1.0)
	post.parameter("normal",post.normal())


func reset_post() -> void:
	scene_post().reset()


# ---- settings (settings.js): a panel over the menu or the pause screen ----

var settings_panel: GameSettingsPanel


func show_settings(values: Dictionary, bindings: Dictionary = {}) -> void:
	if settings_panel == null:
		settings_panel = GameSettingsPanel.new()
		settings_panel.fullscreen_toggle_allowed = fullscreen_toggle_allowed
		settings_panel.hide()
		$Root.add_child(settings_panel)
		settings_panel.setting_changed.connect(func(key: String, value: int) -> void: setting_changed.emit(key,value))
		settings_panel.layout_requested.connect(show_touch_layout_editor)
		settings_panel.binding_changed.connect(func(a: String, slot: int, key: int) -> void: binding_changed.emit(a, slot, key))
		settings_panel.binding_cleared.connect(func(a: String, slot: int) -> void: binding_cleared.emit(a, slot))
		settings_panel.bindings_reset.connect(func(a: String) -> void: bindings_reset.emit(a))
	if not bindings.is_empty():
		settings_panel.set_bindings(bindings)
	settings_panel.open(values)


func bindings_saved(bindings: Dictionary, note: String) -> void:
	if is_instance_valid(settings_panel): settings_panel.set_bindings(bindings, note)


func _fit_settings() -> void:
	if is_instance_valid(settings_panel): settings_panel.fit()


func settings_saved(values: Dictionary, success: bool) -> void:
	if is_instance_valid(settings_panel): settings_panel.saved(values,success)


func apply_text_scale(pct: int) -> void:
	var theme := BASE_THEME.duplicate() as Theme
	theme.default_font_size = roundi(16.0 * float(pct) / 100.0)
	$Root.theme = theme


var _touch_percent := 100
var _touch_layout: Dictionary = {}
var _touch_buttons := {}   # manual / torch / hot1 / hot2 -> TouchActionButton
var _layout_editor: TouchLayoutEditor


func _build_touch_tools() -> void:
	# Each tool button stands on its own, so the layout can place and size it separately (TouchLayout).
	for spec: Array in [["手册","Manual","manual"],["手电","Torch","torch"],["1","Hot1","hot1"],["2","Hot2","hot2"]]:
		var b := TouchActionButton.new()
		b.name = spec[1]
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(44,44)
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 28)
		b.pressed.connect(func() -> void:
			match spec[1]:
				"Manual": manual_requested.emit()
				"Torch": torch_requested.emit()
				"Hot1": hot_requested.emit(0)
				"Hot2": hot_requested.emit(1)
			)
		touch_controls.add_child(b)
		_touch_buttons[spec[2]] = b
	%TouchInteract.focus_mode = Control.FOCUS_NONE
	%TouchSprint.focus_mode = Control.FOCUS_NONE
	look_pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	look_pad.anchor_left = .42
	look_pad.offset_top = 70


func apply_touch_scale(pct: int, layout: Dictionary = {}) -> void:
	_touch_percent = pct
	_touch_layout = TouchLayout.normalize(layout)
	_refit_touch()


## The control that stands for a layout id.
func touch_control(id: String) -> Control:
	match id:
		"stick": return stick
		"sprint": return %TouchSprint
		"interact": return %TouchInteract
	return _touch_buttons.get(id) as Control


func _refit_touch() -> void:
	if _touch_buttons.is_empty():
		return
	clear_touch()
	var view := get_viewport().get_visible_rect().size
	var rects := TouchLayout.resolve(view,_touch_layout,_touch_percent,[Rect2(0,0,view.x,68)])
	var alpha := TouchLayout.opacity(_touch_layout)
	for id: String in TouchLayout.IDS:
		var c := touch_control(id)
		c.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		c.position = rects[id].position
		c.size = rects[id].size
		c.modulate.a = alpha
	UIArt.compact_button(_touch_buttons["manual"], UIArt.nav("notes"))
	UIArt.compact_button(_touch_buttons["torch"], UIArt.item("torch"))
	UIArt.compact_button(%TouchInteract, UIArt.nav(_prompt_art))
	UIArt.compact_button(%TouchSprint, UIArt.nav("sprint"))
	_hot_icons.visible = not _touch_enabled


func show_touch_layout_editor() -> void:
	if is_instance_valid(_layout_editor):
		return
	clear_touch()
	_layout_editor = TouchLayoutEditor.new()
	_layout_editor.layout = _touch_layout.duplicate(true)
	_layout_editor.percent = _touch_percent
	$Root.add_child(_layout_editor)
	if is_instance_valid(settings_panel):
		settings_panel.set_process_input(false)
		_layout_editor.tree_exited.connect(func() -> void:
			if is_instance_valid(settings_panel): settings_panel.set_process_input(true))
	_layout_editor.saved.connect(func(layout: Dictionary) -> void:
		touch_layout_changed.emit(layout)
		_layout_editor.queue_free())
	_layout_editor.cancelled.connect(func() -> void: _layout_editor.queue_free())


## sub: the size of toast and caption lines (SUB_MULT 0.6 / 1.0 / 1.6 in the Web version).
func apply_caption_scale(mult: float) -> void:
	if _captions != null:
		_captions.add_theme_font_size_override("font_size", roundi(15.0 * mult))
	%Toast.add_theme_font_size_override("font_size", roundi(18.0 * mult))
	_fit_toast()


## Film grain shares the world pass, so it never alters text or normal-world colours.
func set_grain(on: bool) -> void:
	scene_post().grain = on
	set_process(true)


# ---- the notes page (investigation.js render): the case card, recent finds, the records, route progress ----

var notes_panel: PanelContainer
var _notes_box: VBoxContainer
var _notes_search: LineEdit
var _notes_scroll: TouchScroll
const NOTE_COLORS := {"事实": Color(0.78, 0.86, 0.95), "推测": Color(0.95, 0.85, 0.6), "验证": Color(0.65, 0.9, 0.7), "线索": Color(0.88, 0.75, 0.95), "规则": Color(0.87, 0.81, 0.66)}
const NOTE_ART := {"事实": "fact", "推测": "guess", "验证": "verify", "线索": "clue", "规则": "rules"}


## data: {goal, focus, routes [[id, name]], recent [rows], groups {kind: rows}, progress [[name, text, done]], found, query}
func show_notes(data: Dictionary) -> void:
	if notes_panel == null:
		notes_panel = PanelContainer.new()
		notes_panel.name = "NotesPanel"
		notes_panel.minimum_size_changed.connect(func() -> void: _fit_documents.call_deferred())
		notes_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		notes_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		notes_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		var back := UISkin.panel(14)
		notes_panel.add_theme_stylebox_override("panel", back)
		var outer := VBoxContainer.new()
		outer.add_theme_constant_override("separation", 8)
		var head := Label.new()
		head.text = "手册 · 笔记"
		outer.add_child(head)
		_notes_search = LineEdit.new()
		_notes_search.name = "NotesSearch"
		_notes_search.custom_minimum_size.y = 44
		_notes_search.placeholder_text = "搜索记录（事实、地点）"
		_notes_search.text_changed.connect(func(t: String) -> void: notes_requested.emit(t))
		outer.add_child(_notes_search)
		_notes_scroll = TouchScroll.new()
		_notes_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_notes_scroll.follow_focus = true
		_notes_box = VBoxContainer.new()
		_notes_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_notes_box.add_theme_constant_override("separation", 6)
		_notes_scroll.add_child(_notes_box)
		outer.add_child(_notes_scroll)
		var close := Button.new()
		close.name = "NotesClose"
		close.text = "关闭"
		close.custom_minimum_size.y = 44
		close.pressed.connect(func() -> void: notes_panel.visible = false)
		outer.add_child(close)
		notes_panel.add_child(outer)
		UIArt.decorate(notes_panel)
		$Root.add_child(notes_panel)
	_notes_scroll.stop_motion()
	for child in _notes_box.get_children():
		_notes_box.remove_child(child)
		child.queue_free()
	var query := String(data.get("query", ""))
	if _notes_search.text != query:
		_notes_search.text = query
	UIArt.heading(_notes_box, "当前调查" + ("  ·  %s路线" % _route_name(data) if not String(data.get("focus", "")).is_empty() else ""), UIArt.route_hint(String(data.get("focus", ""))), UISkin.ACCENT)
	_note_label(String(data["goal"]), Color.WHITE)
	var routes: Array = data["routes"]
	if routes.size() > 1:
		var row := HFlowContainer.new()
		var tag := Label.new()
		tag.text = "关注"
		row.add_child(tag)
		for r: Array in routes:
			var b := Button.new()
			b.name = "Focus_" + String(r[0])
			UIArt.button(b, UIArt.route_hint(String(r[0])))
			b.text = String(r[1])
			b.custom_minimum_size.y = 44
			b.toggle_mode = true
			b.button_pressed = r[0] == data.get("focus", "")
			b.pressed.connect(func() -> void: notes_focus_requested.emit(String(r[0])))
			row.add_child(b)
		_notes_box.add_child(row)
	var duty := String(data.get("duty",""))
	if not duty.is_empty() or bool(data.get("permanent",false)):
		_note_label("外出记录",Color(1,.9,.55))
		if bool(data.get("permanent",false)):
			_note_label("登记后缺席：持续追踪仍生效。假条、重新登记和符纸不能解除。",Color(1,.7,.65))
		if not duty.is_empty():
			_note_label("仍须到教室参加："+duty+"。许可到期不免除责任；系统取消的检查会顺延。",Color.WHITE)
	if not query.is_empty():
		if int(data["found"]) == 0: _notes_box.add_child(UIArt.view(UIArt.surface("search_none"), Vector2(0, 108)))
		_note_label(("找到 %d 条" % int(data["found"])) if int(data["found"]) > 0 else "没有找到仍能回忆的对应记录。", Color(1, 1, 1, 0.7))
	var recent: Array = data["recent"]
	if not recent.is_empty():
		_note_label("最近发现", UISkin.ACCENT)
		for e: Dictionary in recent:
			_note_label("[%s] %s" % [e["kind"], e["text"]], NOTE_COLORS[e["kind"]])
	for kind: String in InvestigationModule.KINDS:
		var rows: Array = (data["groups"] as Dictionary).get(kind, [])
		if rows.is_empty():
			continue
		UIArt.heading(_notes_box, "%s  %d" % [kind, rows.size()], UIArt.surface(String(NOTE_ART[kind])), NOTE_COLORS[kind])
		for e: Dictionary in rows:
			var entry := UISkin.card(_notes_box)
			_note_label("第 %d 天 · %s" % [int(e.get("day", 1)), e["source"]], UISkin.MUTED,entry)
			_note_label(String(e["text"]), UISkin.INK,entry)
	var progress: Array = data["progress"]
	if not progress.is_empty():
		_note_label("路线进度", UISkin.ACCENT)
		for p: Array in progress:
			_note_label("%s %s：%s" % ["✓" if bool(p[2]) else "·", p[0], p[1]], Color(0.65, 0.9, 0.7) if bool(p[2]) else Color.WHITE)
	notes_panel.visible = true
	_fit_documents.call_deferred()


func _route_name(data: Dictionary) -> String:
	for r: Array in data["routes"]:
		if r[0] == data["focus"]:
			return String(r[1])
	return {"car": "车辆", "face": "白名单", "portal": "造门", "cyber": "网安仙人"}.get(String(data["focus"]), "")


func _note_label(text: String, color: Color, parent: Control = null) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color",color)
	(parent if parent != null else _notes_box).add_child(l)


# ---- the map page: the campus plan or the sketch of a walked floor ----

var map_panel: PanelContainer
var map_view: MapView
var _map_select: OptionButton
var _map_head: Label
var _map_note: Label
var _map_scroll: ScrollContainer
var _map_close_button: Button
var _map_center_pending := false
var _map_generation := 0


## options: [[id, label]] ("campus" is the plan); returns the view to configure.
func open_map(options: Array, selected: String, head: String, note: String) -> MapView:
	if map_panel == null:
		map_panel = PanelContainer.new()
		map_panel.name = "MapPanel"
		map_panel.minimum_size_changed.connect(func() -> void: _fit_map.call_deferred())
		map_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		map_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		map_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		var back := UISkin.panel(12)
		map_panel.add_theme_stylebox_override("panel", back)
		var outer := VBoxContainer.new()
		outer.add_theme_constant_override("separation", 6)
		var top := HBoxContainer.new()
		var lab := Label.new()
		lab.text = "查看"
		top.add_child(lab)
		_map_select = OptionButton.new()
		_map_select.name = "MapSelect"
		_map_select.custom_minimum_size.y = 44
		UIArt.button(_map_select, UIArt.nav("map"), 28)
		_map_select.fit_to_longest_item = false
		_map_select.clip_text = true
		_map_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_map_select.item_selected.connect(func(i: int) -> void: map_requested.emit(String(_map_select.get_item_metadata(i))))
		top.add_child(_map_select)
		outer.add_child(top)
		_map_head = Label.new()
		_map_head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		outer.add_child(_map_head)
		_map_scroll = ScrollContainer.new()
		_map_scroll.follow_focus = true
		map_view = MapView.new()
		map_view.name = "MapView"
		map_view.scroll_min_width = 0
		_map_scroll.add_child(map_view)
		outer.add_child(_map_scroll)
		_map_note = Label.new()
		_map_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_map_note.modulate = Color(1, 1, 1, 0.6)
		outer.add_child(_map_note)
		_map_close_button = Button.new()
		_map_close_button.text = "关闭"
		_map_close_button.pressed.connect(func() -> void: map_panel.visible = false)
		outer.add_child(_map_close_button)
		map_panel.add_child(outer)
		UIArt.decorate(map_panel)
		$Root.add_child(map_panel)
	_map_select.clear()
	for o: Array in options:
		_map_select.add_icon_item(UIArt.landmark(String(o[0])), String(o[1]))
		_map_select.get_popup().set_item_icon_max_width(_map_select.item_count - 1, 28)
		_map_select.set_item_metadata(_map_select.item_count - 1, String(o[0]))
		if o[0] == selected:
			_map_select.select(_map_select.item_count - 1)
	_map_head.text = head
	_map_note.text = note
	map_panel.visible = true
	_map_generation += 1
	_map_center_pending = true
	_map_scroll.scroll_vertical = 0
	_map_scroll.scroll_horizontal = 0
	_fit_map.call_deferred()
	return map_view


func _fit_map() -> void:
	if not is_instance_valid(map_panel) or not map_panel.visible: return
	var screen := get_viewport().get_visible_rect().size
	var width := minf(720,screen.x-24)
	map_panel.custom_minimum_size.x = width
	_map_head.size.x = width-24
	_map_note.size.x = width-24
	var fixed := 24.0
	for child in _map_head.get_parent().get_children():
		if child is Control and child != _map_scroll and child.visible:
			fixed += child.get_combined_minimum_size().y+6
	map_view.scroll_max_height = maxf(60,minf(500,screen.y-fixed-24))
	if not map_view.plan.is_empty():
		map_view.show_plan(map_view.plan,Vector2(width-52,map_view.scroll_max_height-14))
	elif not map_view.room.is_empty():
		map_view.show_floor(map_view.room,map_view.seen,map_view.label_of,map_view.me,map_view.ang,map_view.here,width-52)
	map_panel.reset_size()
	map_panel.position = (screen-map_panel.size)*.5
	if _map_center_pending:
		_map_center_pending = false
		_center_map_player.call_deferred(_map_generation)


func _center_map_player(generation: int) -> void:
	# Scroll ranges settle after the container has wrapped the header and legend.
	await get_tree().process_frame
	await get_tree().process_frame
	if generation != _map_generation or not is_instance_valid(map_view) or not map_panel.visible or map_view.room.is_empty() or not map_view.here: return
	var px := (map_view.me.x-float(map_view.room["ox"]))/float(map_view.room["tw"])*map_view.cell
	_map_scroll.scroll_horizontal = maxi(0,roundi(px-_map_scroll.size.x*.5))


func sensory_on() -> bool:
	return _sense != null and _sense.sensory_active


## The lab3 maintenance terminal (TerminalUI): output, a command line, help / hint buttons, exit.
var terminal_panel: PanelContainer
var _term_out: RichTextLabel
var _term_status: Label
var _term_line: LineEdit


func show_terminal(history: String, status: String) -> void:
	if terminal_panel == null:
		terminal_panel = PanelContainer.new()
		terminal_panel.name = "TerminalPanel"
		terminal_panel.visible = false
		terminal_panel.minimum_size_changed.connect(func() -> void: _fit_documents.call_deferred())
		terminal_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		terminal_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		terminal_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		var back := UISkin.panel(12)
		terminal_panel.add_theme_stylebox_override("panel", back)
		var box := VBoxContainer.new()
		var head := Label.new()
		head.text = "机房 · 模拟 Linux 终端　（世界仍在运行。留意脚步与灯光；Esc 退出）"
		head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UIArt.heading(box, head.text, UIArt.surface("terminal"), UISkin.ACCENT)
		head.free()
		_term_status = Label.new()
		_term_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_term_status.modulate = Color(0.6, 0.95, 0.7)
		box.add_child(_term_status)
		_term_out = RichTextLabel.new()
		_term_out.scroll_following = true
		_term_out.selection_enabled = true
		_term_out.add_theme_color_override("default_color", Color(0.75, 1.0, 0.8))
		box.add_child(_term_out)
		_term_line = LineEdit.new()
		_term_line.name = "TerminalInput"
		_term_line.custom_minimum_size.y = 44
		_term_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_term_line.placeholder_text = "help"
		_term_line.max_length = 4096
		_term_line.text_submitted.connect(func(t: String) -> void:
			terminal_command.emit(t)
			_term_line.text = ""
			_term_line.grab_focus())
		box.add_child(_term_line)
		var row := HFlowContainer.new()
		for pair: Array in [["执行", ""], ["帮助", "help"], ["线索位置", "campusctl hint 1"], ["关联方法", "campusctl hint 2"], ["退出", "__exit"]]:
			var b := Button.new()
			b.text = pair[0]
			b.custom_minimum_size.y = 44
			if pair[1] == "__exit": b.name = "TerminalExit"
			var cmd: String = pair[1]
			b.pressed.connect(func() -> void:
				if cmd == "__exit":
					hide_terminal()
					terminal_closed.emit()
				elif cmd == "":
					terminal_command.emit(_term_line.text)
					_term_line.text = ""
				else:
					terminal_command.emit(cmd))
			row.add_child(b)
		box.add_child(row)
		terminal_panel.add_child(box)
		UIArt.decorate(terminal_panel)
		$Root.add_child(terminal_panel)
	_term_out.text = history
	_term_status.text = status
	if not terminal_panel.visible:
		terminal_panel.visible = true
		_term_line.grab_focus()
	_fit_documents.call_deferred()


func hide_terminal() -> void:
	if terminal_panel != null:
		_term_line.release_focus()
		terminal_panel.visible = false


func _fit_documents() -> void:
	PanelLayout.fit(notes_panel,_notes_scroll,620,380)
	PanelLayout.fit(_import_panel,_import_scroll,620,380)
	PanelLayout.fit(terminal_panel,_term_out,720,320)
	if is_instance_valid(_death_text):
		PanelLayout.fit(death_panel,_death_scroll,520,minf(440,_death_scroll.get_child(0).get_combined_minimum_size().y))


func terminal_open() -> bool:
	return terminal_panel != null and terminal_panel.visible


## Ending card (story.js showEndingCard): tag, title, lines, day/time, back to the menu.
var ending_panel: PanelContainer
var _ending_text: Label
var _ending_scroll: TouchScroll
var _ending_art: TextureRect


func set_wuda_armed(armed: bool, tell: bool = false) -> void:
	%SchoolName.modulate=Color("#cdbb86") if armed else Color.WHITE
	if tell:
		%Description.text="……你想起来了：你家就住在珞珈山下。" if armed else "……还是当个普通的转学生吧。"


func set_ending_wake(shown: bool) -> void:
	if is_instance_valid(_ending_wake):
		_ending_wake.visible=shown
		_fit_ending.call_deferred()


func show_ending(title: String, tag: String, lines: Array, meta: String, achieved: PackedStringArray = PackedStringArray(), result_note: String = "", ending_id: String = "") -> void:
	if ending_panel == null:
		ending_panel = PanelContainer.new()
		ending_panel.name = "EndingPanel"
		ending_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		ending_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		ending_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		ending_panel.custom_minimum_size = Vector2(520, 0)
		ending_panel.minimum_size_changed.connect(func() -> void: _fit_ending.call_deferred())
		var outer := VBoxContainer.new()
		outer.add_theme_constant_override("separation",12)
		ending_panel.add_child(outer)
		_ending_scroll=TouchScroll.new()
		_ending_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
		outer.add_child(_ending_scroll)
		var box := VBoxContainer.new()
		box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 14)
		_ending_art = UIArt.view(null, Vector2(0, 172))
		_ending_art.name = "EndingIllustration"
		box.add_child(_ending_art)
		_ending_text = Label.new()
		_ending_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_ending_text.custom_minimum_size = Vector2.ZERO
		_ending_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(_ending_text)
		_ending_scroll.add_child(box)
		_ending_note = Label.new()
		_ending_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_ending_note.modulate = Color(1, 1, 1, 0.6)
		outer.add_child(_ending_note)
		var actions := HFlowContainer.new()
		actions.add_theme_constant_override("h_separation",8)
		outer.add_child(actions)
		_ending_results = Button.new()
		_ending_results.name = "EndingResults"
		_ending_results.text = "结算"
		_ending_results.custom_minimum_size = Vector2(144,60)
		_ending_results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_ending_results.pressed.connect(func() -> void: results_requested.emit())
		actions.add_child(_ending_results)
		_ending_wake=Button.new()
		_ending_wake.name="EndingWake"
		_ending_wake.text="……再睁开眼"
		_ending_wake.custom_minimum_size=Vector2(144,60)
		_ending_wake.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_ending_wake.pressed.connect(func() -> void: ending_wake_requested.emit())
		actions.add_child(_ending_wake)
		var back := Button.new()
		back.name = "EndingMenu"
		back.text = "回到主菜单"
		back.custom_minimum_size=Vector2(144,60)
		back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		back.pressed.connect(func() -> void: death_menu_requested.emit())
		actions.add_child(back)
		$Root.add_child(ending_panel)
	_ending_art.texture = UIArt.memory("end:" + ending_id)
	_ending_art.visible = _ending_art.texture != null
	var head := "%s\n%s" % [tag, title] if not tag.is_empty() else title
	_ending_text.text = "%s\n\n%s\n\n%s" % [head, "\n".join(PackedStringArray(lines)), meta]
	if not achieved.is_empty():
		_ending_text.text += "\n\n本局新达成\n" + "\n".join(achieved)
	_ending_results.visible = result_note == "rated"
	_ending_note.text = "调试局 · 不评级，不进通关记录" if result_note == "debug" else ""
	_ending_note.visible = result_note == "debug"
	_ending_wake.hide()
	_ending_scroll.stop_motion()
	_ending_scroll.scroll_vertical = 0
	ending_panel.visible = true
	_fit_ending.call_deferred()


func _fit_ending() -> void:
	PanelLayout.fit(ending_panel,_ending_scroll,620,440)


var _ending_results: Button
var _ending_note: Label
var _ending_wake: Button
var results_panel: ResultsPanel
var records_panel: RecordsPanel


func ensure_records(store: RunRecords, rooms: Dictionary) -> RecordsPanel:
	if records_panel == null:
		records_panel = RecordsPanel.new(store, rooms)
		$Root.add_child(records_panel)
	records_panel.records = store
	return records_panel


func show_records(store: RunRecords, rooms: Dictionary) -> RecordsPanel:
	ensure_records(store, rooms).open()
	return records_panel


func show_results(m: Dictionary, opts: Dictionary = {}) -> void:
	if results_panel == null:
		results_panel = ResultsPanel.new()
		results_panel.sound.connect(func(b: String) -> void: grade_sound.emit(b))
		$Root.add_child(results_panel)
	results_panel.open(m, opts)


func hide_results() -> void:
	if results_panel != null:
		results_panel.visible = false


func hide_ending() -> void:
	if ending_panel != null:
		ending_panel.visible = false


func hide_death() -> void:
	death_panel.visible = false
	_death_fade.visible = false


var _choice_timer_label: Label


## Seconds left of a timed choice ("超时随机选择"); 0 hides the line.
func show_choice_timer(seconds: float) -> void:
	if _choice_timer_label == null:
		_choice_timer_label = Label.new()
		_choice_timer_label.modulate = Color(0.85, 0.8, 0.6)
		_choice_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_choice_text.get_parent().add_child(_choice_timer_label)
	_choice_timer_label.visible = seconds > 0.0
	_choice_timer_label.text = "剩余 %d 秒 · 超时随机选择" % int(ceil(seconds))


## The hurt flash (VisualState.hurt / flash): a red-white pulse that fades.
var _hurt_rect: ColorRect
var _hurt_level := 0.0
var _bolt_rect: ColorRect
var _bolt_level := 0.0


## Lightning (fx/weather.js): the screen whitens and fades in a third of a second.
func flash_light(strength: float) -> void:
	if _bolt_rect == null:
		_bolt_rect = ColorRect.new()
		_bolt_rect.name = "Lightning"
		_bolt_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bolt_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_bolt_rect.color = Color(0.85, 0.9, 1.0, 0.0)
		$Root.add_child(_bolt_rect)
		$Root.move_child(_bolt_rect, 0)
	_bolt_level = maxf(_bolt_level, clampf(strength, 0.0, 0.5))


## The camera flash (camera.js flashScreen): the whole screen whitens (0.85, or 0.18 with reduce-flash on) and fades.
var _cam_rect: ColorRect
var _cam_level := 0.0


func flash_screen(reduced: bool) -> void:
	if _cam_rect == null:
		_cam_rect = ColorRect.new()
		_cam_rect.name = "CameraFlash"
		_cam_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cam_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_cam_rect.color = Color(1, 1, 0.97, 0.0)
		$Root.add_child(_cam_rect)
	$Root.move_child(_cam_rect, $Root.get_child_count() - 1)
	_cam_level = 0.18 if reduced else 0.85


func bolt_level() -> float:
	return _bolt_level


func flash_hurt(strength: float) -> void:
	if _hurt_rect == null:
		_hurt_rect = ColorRect.new()
		_hurt_rect.name = "HurtFlash"
		_hurt_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hurt_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_hurt_rect.color = Color(0.55, 0.05, 0.05, 0.0)
		$Root.add_child(_hurt_rect)
	_hurt_level = maxf(_hurt_level, clampf(strength, 0.0, 0.7))


var _choice_cancellable := true


func show_choice(text: String, labels: Array, cancellable: bool = true, illustrations: Array = []) -> void:
	if is_instance_valid(selection_panel): selection_panel.hide()
	_choice_scroll.stop_motion()
	_paper_read = false
	if is_instance_valid(_paper_progress): _paper_progress.hide()
	_choice_cancellable = cancellable
	_choice_has_art = not illustrations.is_empty()
	for child in _choice_box.get_children():
		_choice_box.remove_child(child)
		child.queue_free()
	_choice_text.text = text
	for i in labels.size():
		var b := Button.new()
		b.text = "%d. %s" % [i + 1, labels[i]]
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size.y = 48
		if i < illustrations.size() and illustrations[i] is Texture2D:
			b.icon = illustrations[i]
			b.expand_icon = true
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.add_theme_constant_override("icon_max_width", 108 if get_viewport().get_visible_rect().size.x >= 640 else 72)
			b.add_theme_constant_override("h_separation", 18)
			b.custom_minimum_size.y = 144
			b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(choice_selected.emit.bind(i))
		_choice_box.add_child(b)
	_choice_cancel.visible = cancellable
	_choice_scroll.scroll_vertical = 0
	choice_panel.visible = true
	_choice_refit = false
	_fit_choice()


## Gameplay choices keep their immediate responses; navigation stays outside the list.
func _fit_choice() -> void:
	var view := get_viewport().get_visible_rect().size
	choice_panel.custom_minimum_size.x = minf(840.0 if _choice_has_art else 560.0, view.x - 32.0)
	_choice_text.custom_minimum_size.x = choice_panel.custom_minimum_size.x - 24.0
	var want := 0.0
	for child in _choice_box.get_children():
		if not child.is_queued_for_deletion():
			want += (child as Control).get_combined_minimum_size().y + 4.0
	var footer := _choice_cancel.get_combined_minimum_size().y + 8.0 if _choice_cancel.visible else 0.0
	var room := maxf(64.0, view.y * 0.86 - _choice_text.get_combined_minimum_size().y - 40.0 - footer)
	_choice_scroll.custom_minimum_size.y = minf(want, room)
	var size := choice_panel.get_combined_minimum_size()
	choice_panel.offset_left = -size.x / 2.0
	choice_panel.offset_right = size.x / 2.0
	choice_panel.offset_top = -size.y / 2.0
	choice_panel.offset_bottom = size.y / 2.0
	if not _choice_refit:
		_choice_refit = true
		_refit_choice_later.call_deferred()


var _choice_refit := false
var _choice_has_art := false


## Wrapped labels know their height only after a layout pass: fit once more then.
func _refit_choice_later() -> void:
	await get_tree().process_frame
	_choice_refit = true
	if choice_panel.visible:
		_fit_choice()
	_choice_refit = false


func hide_choice() -> void:
	choice_panel.visible = false
	if is_instance_valid(selection_panel): selection_panel.hide()
	_paper_read = false
	if is_instance_valid(_paper_progress): _paper_progress.hide()


func choice_open() -> bool:
	return choice_panel != null and choice_panel.visible or is_instance_valid(selection_panel) and selection_panel.visible


func show_selection(title: String, mode: String, entries: Array) -> void:
	hide_choice()
	if not is_instance_valid(selection_panel):
		selection_panel = SelectionPanel.new()
		$Root.add_child(selection_panel)
		selection_panel.confirmed.connect(choice_selected.emit)
		selection_panel.canceled.connect(_selection_canceled)
	selection_panel.open(title, mode, entries)


func _selection_canceled() -> void:
	choice_selected.emit(-1)
	_restore_menu_focus.call_deferred()


func _restore_menu_focus() -> void:
	if _mode != "menu" or choice_open(): return
	var focused := get_viewport().gui_get_focus_owner()
	if focused == null or not focused.is_visible_in_tree():
		menu_screen.focus_default()


func set_lift_close(visible_now: bool) -> void:
	if lift_close_button.visible != visible_now:
		lift_close_button.visible = visible_now


func _unhandled_key_input(event: InputEvent) -> void:
	if is_instance_valid(selection_panel) and selection_panel.visible: return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if is_instance_valid(_layout_editor):
			_layout_editor.queue_free()
			get_viewport().set_input_as_handled()
			return
		if settings_panel != null and settings_panel.visible:
			settings_panel.dismiss()
			get_viewport().set_input_as_handled()
			return
		if bag_open():
			bag_closed.emit()
			get_viewport().set_input_as_handled()
			return
	if not choice_open() or not event is InputEventKey or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).physical_keycode
	if _paper_read and key in [KEY_E,KEY_ENTER,KEY_KP_ENTER]:
		choice_selected.emit(0)
		get_viewport().set_input_as_handled()
	elif key >= KEY_1 and key <= KEY_9:
		var index := key - KEY_1
		if index < _choice_box.get_child_count():
			choice_selected.emit(index)
			get_viewport().set_input_as_handled()
	elif key == KEY_ESCAPE and _choice_cancellable:
		choice_selected.emit(-1)
		get_viewport().set_input_as_handled()


func set_touch_enabled(value: bool) -> void:
	_touch_enabled = value
	if is_instance_valid(menu_screen): menu_screen.set_touch(value)
	%TouchToggle.set_pressed_no_signal(value)
	touch_controls.visible = value and _mode == "play" and not _paper_flying
	_refresh_paper_pad()
	clear_touch()
	if is_inside_tree():
		_update_orient_hint()
		_refit_touch()


func touch_enabled() -> bool:
	return _touch_enabled


func movement_touch() -> Vector2:
	return stick._value if _touch_enabled and touch_controls.is_visible_in_tree() else Vector2.ZERO


func set_paper_flight(on: bool) -> void:
	if on==_paper_flying: return
	_paper_flying = on
	clear_touch()
	if on and not is_instance_valid(_paper_pad):
		_paper_pad = PaperFlightPad.new()
		$Root.add_child(_paper_pad)
		_paper_pad.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		_paper_pad.offset_left = -128
		_paper_pad.offset_right = 128
		_paper_pad.offset_top = -82
		_paper_pad.offset_bottom = -30
	touch_controls.visible = _mode=="play" and _touch_enabled and not on
	_refresh_paper_pad()


func _refresh_paper_pad() -> void:
	if is_instance_valid(_paper_pad): _paper_pad.visible = _paper_flying and _mode=="play" and _touch_enabled


func paper_directions() -> Dictionary:
	return _paper_pad.value() if is_instance_valid(_paper_pad) and _paper_pad.is_visible_in_tree() else {}


func show_paper_time(seconds: float) -> void:
	_paper_read = true
	if is_instance_valid(_choice_timer_label): _choice_timer_label.hide()
	if not is_instance_valid(_paper_progress):
		_paper_progress = ProgressBar.new()
		_paper_progress.show_percentage = false
		_paper_progress.custom_minimum_size.y = 12
		_choice_text.get_parent().add_child(_paper_progress)
	_paper_progress.max_value = PaperPlaneModule.READ
	_paper_progress.value = maxf(seconds,0)
	_paper_progress.show()


func clear_touch() -> void:
	stick.clear()
	look_pad.clear()
	for button: Node in touch_controls.find_children("*", "TouchActionButton", true, false):
		button.cancel_touch()
	%TouchSprint.set_pressed_no_signal(false)
	touch_sprint.emit(false)
	_update_sprint_label()
	if is_instance_valid(_paper_pad): _paper_pad.clear()


var _sprint_available := true


func show_touch_sprint(value: bool) -> void:
	%TouchSprint.set_pressed_no_signal(value)
	_update_sprint_label()


func show_sprint_available(value: bool) -> void:
	_sprint_available = value
	_update_sprint_label()


func _update_sprint_label() -> void:
	%TouchSprint.text = "奔跑：关" if not %TouchSprint.button_pressed else ("奔跑：开" if _sprint_available else "暂不能跑")
	UIArt.compact_button(%TouchSprint, UIArt.nav("sprint"))


func set_mode(mode: String) -> void:
	if _mode != mode:
		show_notice("")
		_map_generation += 1
		for panel in [map_panel,notes_panel,_import_panel,settings_panel,records_panel,results_panel]:
			if is_instance_valid(panel): panel.hide()
	_mode = mode
	if _sense != null:
		_sense.visible = mode != "menu"
	if ach_panel != null:
		ach_panel.visible = false
	if mode != "play":
		hide_terminal()
	menu.visible = mode == "menu"
	pause_panel.visible = mode == "pause"
	hud.visible = mode == "play"
	touch_controls.visible = mode == "play" and _touch_enabled and not _paper_flying
	_refresh_paper_pad()
	clear_touch()
	if is_instance_valid(menu_preview):
		if mode == "menu":
			menu_preview.begin_load()
		else:
			menu_preview.release()
	if mode == "menu":
		menu_screen.enter()
	elif mode == "pause":
		%Resume.grab_focus()
	else:
		var focused := get_viewport().gui_get_focus_owner()
		if focused != null:
			focused.release_focus()


func set_save_available(available: bool) -> void:
	%LoadGame.disabled = not available
	%Reload.disabled = not available
	menu_screen.set_save_available(available)


func show_notice(text: String) -> void:
	%Toast.text = text
	%Toast.visible = not text.is_empty()
	%Toast.modulate.a = 1.0
	_toast_seconds = 6.0
	_fit_toast()


## The notice line sits on a translucent pill as wide as its text (at most 62 % of the screen, below the
## status card and clear of the captions), so it stays readable over a bright board or a busy wall
## without hiding the scene behind a band.
func _fit_toast() -> void:
	var toast := %Toast as Label
	if toast.theme_type_variation != "HudPill":
		toast.theme_type_variation = "HudPill"
		toast.anchor_left = 0.5
		toast.anchor_right = 0.5
		toast.anchor_top = 0.26
		toast.anchor_bottom = 0.26
		toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
		toast.grow_vertical = Control.GROW_DIRECTION_END
		toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		toast.add_theme_constant_override("shadow_outline_size", 3)
		var pill := BASE_THEME.get_stylebox("normal", "HudPill").duplicate() as StyleBoxFlat
		pill.set_corner_radius_all(14)
		pill.content_margin_top = 8
		pill.content_margin_bottom = 9
		pill.bg_color = Color(0.03, 0.05, 0.06, 0.72)
		toast.add_theme_stylebox_override("normal", pill)
	if toast.text.is_empty():
		return
	var screen := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(960, 540)
	var font := toast.get_theme_font("font")
	var font_size := toast.get_theme_font_size("font_size")
	var margins := toast.get_theme_stylebox("normal").get_minimum_size().x
	var width := 0.0
	for line: String in toast.text.split("\n"):
		width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	width = minf(ceilf(width + margins + 2.0), screen.x * 0.62)     # clear of the status card and captions on the left
	# An autowrapped label has almost no minimum width of its own: pin the width, the height follows the text.
	toast.custom_minimum_size = Vector2(width, 0.0)
	toast.offset_left = -width * 0.5
	toast.offset_right = width * 0.5
	toast.offset_top = 0.0
	toast.offset_bottom = 0.0


func toast_text() -> String:
	return %Toast.text


var _prompt_art := "interact"


func show_prompt(text: String) -> void:
	_prompt_art = "stand" if text.contains("站起") or text.contains("起身") else ("sit" if text.contains("坐下") or text.contains("落座") else ("hiding" if text.contains("躲") else "interact"))
	UIArt.compact_button(%TouchInteract, UIArt.nav(_prompt_art))
	%Prompt.text = ("交互 · " if _touch_enabled else interact_key + " · ") + text if not text.is_empty() else ""
	%Prompt.visible = not text.is_empty()
	var cross := hud.get_node("Crosshair") as Label
	cross.text = "◦" if not text.is_empty() else "·"
	cross.add_theme_color_override("font_color", Color(0.56, 0.84, 0.75, 0.95) if not text.is_empty() else Color(0.93, 0.9, 0.84, 0.75))


var _location := ""
var _clock_text := ""
var _status_line: Label
var _status_art: TextureRect
var _stamina: ProgressBar
var _status_on := false
var bag_panel: PanelContainer
var _bag_list: GridContainer
var _bag_scroll: TouchScroll
var _search_ring: ProgressBar
var _hot_label: Label
var _hot_icons: HBoxContainer
var _hot_art: Array[TextureRect] = []


func show_location(text: String) -> void:
	_location = text
	if not _status_on: show_runtime(0)


## In-world time is only as precise as the player's watch; developer elapsed time stays in its panel.
var speedrun_text := ""


func show_runtime(_seconds: float) -> void:
	var shown := _clock_text if _status_on else _location
	%Runtime.text = shown + (" · 速通 " + speedrun_text if speedrun_text != "" else "")
	%Runtime.visible = not %Runtime.text.is_empty()
