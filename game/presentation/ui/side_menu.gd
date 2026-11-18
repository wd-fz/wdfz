class_name SideMenu
extends Control
## Main menu over the campus panorama. The primary actions share the front page;
## the other modes, archive and quick settings each get their own short list.

signal quit_requested
signal backdrop_requested

const GROUPS := {
	"Rebirth": ["HardGame", "Speedrun", "DlcMenu", "ImportMenu"],
	"Gallery": ["Achievements", "Archive", "RecordsMenu"],
	"QuickOptions": ["FullscreenMenu", "TouchToggle", "SoundToggle", "DebugTools"],
}
const ICONS := {
	"NewGame": "new_game", "LoadGame": "continue", "HardGame": "warning",
	"Rebirth": "speedrun", "Gallery": "archive", "SettingsMenu": "settings",
	"QuickOptions": "controls", "Achievements": "achievements", "Archive": "archive",
	"RecordsMenu": "records", "Speedrun": "speedrun", "DlcMenu": "dlc",
	"ImportMenu": "import", "FullscreenMenu": "fullscreen", "DebugTools": "debug",
}
const DETAILS := {
	"NewGame": "选择一项天赋，从第一天的教室开始。",
	"LoadGame": "读取最近一次保存的单人进度。",
	"LanCoop": "创建房间或加入好友，2–4 人一起寻找出口。",
	"Rebirth": "进入梦魇、速通或规则怪谈，也可导入旧存档。",
	"Gallery": "回看已发现的结局、成就和通关记录。",
	"SettingsMenu": "调整画质、帧率、声音、操作与阅读体验。",
	"QuickOptions": "快速切换声音、触屏等常用选项。",
	"HardGame": "以梦魇难度开始新游戏。",
	"Speedrun": "开启速通计时，挑战通关路线。",
}
const ENTRANCE_SECONDS := 0.56
const TITLE_LIGHT := preload("res://game/presentation/ui/title_light.gdshader")

static var _noise_texture: Texture2D

var content: VBoxContainer
var scroll: TouchScroll
var groups: Dictionary = {}
var description: Label
var version_label: Label
var hint_label: Label
var state := "opening"
var reduce_motion := false
var _title: Label
var _school: Button
var _new_game: Button
var _load: Button
var _play_actions: VBoxContainer
var _primary: BoxContainer
var _front: VBoxContainer
var _utilities: GridContainer
var _backdrop_button: Button
var _detail: PanelContainer
var _detail_copy: Label
var _group_buttons: Dictionary = {}
var _open_group := ""
var _entrance := 0.0
var _keys_hint := "WASD 移动 · 鼠标环视\nE 交互 · Esc 暂停"
var _touch_on := false


func setup(source: VBoxContainer) -> void:
	name = "SideMenu"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_scrim()
	content = VBoxContainer.new()
	content.name = "MenuContent"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 8)
	add_child(content)
	_school = source.get_node("SchoolName") as Button
	_school.reparent(content, false)
	_school.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_school.add_theme_color_override("font_color", UISkin.ACCENT)
	_school.add_theme_color_override("font_hover_color", UISkin.INK)
	_school.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_school.custom_minimum_size.y = 28
	_title = source.get_node("Title") as Label
	_title.reparent(content, false)
	_title.theme_type_variation = "HeadingLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title.add_theme_color_override("font_color", UISkin.INK)
	var title_font := FontVariation.new()
	title_font.base_font = _title.get_theme_font("font")
	title_font.spacing_glyph = 3
	_title.add_theme_font_override("font", title_font)
	description = source.get_node("Description") as Label
	description.reparent(content, false)
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_color_override("font_color", UISkin.MUTED)
	var rule := ColorRect.new()
	rule.color = Color(UISkin.ACCENT, 0.8)
	rule.custom_minimum_size = Vector2(46, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(rule)
	scroll = TouchScroll.new()
	scroll.name = "MenuScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pages)
	_front = VBoxContainer.new()
	_front.add_theme_constant_override("separation", 10)
	pages.add_child(_front)
	_play_actions = VBoxContainer.new()
	_play_actions.add_theme_constant_override("separation", 6)
	_front.add_child(_play_actions)
	_primary = BoxContainer.new()
	_primary.vertical = true
	_primary.add_theme_constant_override("separation", 6)
	_play_actions.add_child(_primary)
	_load = _move_action(source, _primary, "LoadGame")
	_new_game = _move_action(source, _primary, "NewGame")
	_new_game.text = "开始游戏"
	_new_game.tooltip_text = "普通难度 · 预知梦"
	_utilities = GridContainer.new()
	_utilities.columns = 2
	_front.add_child(_utilities)
	_add_group(source, pages, "Rebirth", "其他玩法")
	_add_group(source, pages, "Gallery", "档案与记录")
	_move_action(source, _utilities, "SettingsMenu")
	_add_group(source, pages, "QuickOptions", "快捷选项")
	for button: Button in _utilities.get_children():
		button.theme_type_variation = "RailButton"
	_build_footer()
	_build_backdrop_button()
	_build_detail()
	set_save_available(not _load.disabled)
	set_touch(false)
	get_viewport().size_changed.connect(refit)
	theme_changed.connect(func() -> void: refit.call_deferred())
	refit()


func _add_scrim() -> void:
	# One baked gradient over either campus photo. No screen texture or blur pass.
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.28, 0.48, 0.8, 1.0])
	ramp.colors = PackedColorArray([
		Color(UISkin.SHADE, 0.98), Color(UISkin.SHADE, 0.95),
		Color(UISkin.SHADE, 0.70), Color(UISkin.SHADE, 0.08), Color(UISkin.SHADE, 0.0),
	])
	var gradient := GradientTexture2D.new()
	gradient.gradient = ramp
	gradient.width = 512
	gradient.height = 4
	var veil := UIArt.view(gradient, Vector2.ZERO)
	veil.name = "MenuScrim"
	veil.stretch_mode = TextureRect.STRETCH_SCALE
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)


func _build_footer() -> void:
	content.add_child(HSeparator.new())
	var footer := HBoxContainer.new()
	content.add_child(footer)
	version_label = Label.new()
	version_label.name = "MenuVersion"
	version_label.text = "v%s" % String(ProjectSettings.get_setting("application/config/version", "0"))
	version_label.add_theme_color_override("font_color", UISkin.MUTED)
	version_label.add_theme_font_size_override("font_size", 12)
	footer.add_child(version_label)
	hint_label = Label.new()
	hint_label.name = "MenuKeys"
	hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.add_theme_color_override("font_color", UISkin.MUTED)
	hint_label.add_theme_font_size_override("font_size", 12)
	footer.add_child(hint_label)
	var quit := _action(footer, "QuitGame", "退出")
	quit.size_flags_horizontal = Control.SIZE_SHRINK_END
	quit.autowrap_mode = TextServer.AUTOWRAP_OFF
	quit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	quit.theme_type_variation = "QuietButton"
	quit.pressed.connect(quit_requested.emit)


func _build_backdrop_button() -> void:
	_backdrop_button = _action(self, "MenuBackdrop", "校园实景")
	_backdrop_button.autowrap_mode = TextServer.AUTOWRAP_OFF
	_backdrop_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_backdrop_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_backdrop_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_backdrop_button.offset_right = -26
	_backdrop_button.offset_bottom = -24
	_backdrop_button.pressed.connect(backdrop_requested.emit)


func _build_detail() -> void:
	_detail = PanelContainer.new()
	_detail.name = "CommandDetail"
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := UISkin.cinematic_panel(12)
	style.bg_color.a = 0.69
	style.border_color = Color("7090a1")
	style.set_border_width_all(0)
	style.border_width_left = 2
	style.shadow_size = 0
	_detail.add_theme_stylebox_override("panel", style)
	_detail.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_detail.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_detail.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_detail.offset_right = -26
	_detail.offset_bottom = -78
	_detail_copy = Label.new()
	_detail_copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_copy.add_theme_color_override("font_color", UISkin.INK)
	_detail.add_child(_detail_copy)
	add_child(_detail)


func _describe(button: Button) -> void:
	var detail := String(DETAILS.get(String(button.name), ""))
	if _detail_copy == null or detail.is_empty() or detail == _detail_copy.text or button.disabled: return
	_detail_copy.text = detail
	UISkin.reveal(_detail_copy, reduce_motion, 0.17)


func _restore_detail() -> void:
	var focus := get_viewport().gui_get_focus_owner() as Button
	if focus != null and not focus.disabled and focus.is_visible_in_tree() and is_ancestor_of(focus) and DETAILS.has(String(focus.name)):
		_describe(focus)
	else:
		_describe(_new_game if _load.disabled else _load)


func set_backdrop_orbit(on: bool) -> void:
	_backdrop_button.text = "雨夜封面" if on else "校园实景"


func _add_group(source: Control, pages: Control, id: String, title: String) -> void:
	var button := _action(_utilities, id, title)
	_group_buttons[id] = button
	button.pressed.connect(_show_page.bind(id))
	var page := VBoxContainer.new()
	page.name = id + "Items"
	page.hide()
	pages.add_child(page)
	groups[id] = page
	var back := _action(page, id + "Back", "‹  主菜单")
	back.theme_type_variation = "QuietButton"
	back.pressed.connect(_show_page.bind(""))
	var heading := Label.new()
	heading.text = title
	heading.theme_type_variation = "HeadingLabel"
	heading.add_theme_color_override("font_color", UISkin.ACCENT)
	page.add_child(heading)
	for child_id: String in GROUPS[id]:
		_move_action(source, page, child_id)


func _action(parent: Control, id: String, label: String) -> Button:
	var button := Button.new()
	button.name = id
	button.text = label
	parent.add_child(button)
	_style_action(button)
	return button


func _move_action(source: Control, target: Control, id: String) -> Button:
	var button := source.find_child(id, true, false) as Button
	if button == null: return null
	button.reparent(target, false)
	_style_action(button)
	return button


func _style_action(button: Button) -> void:
	button.custom_minimum_size.y = 44
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if not button is CheckButton:
		button.theme_type_variation = "CommandButton"
	if ICONS.has(String(button.name)):
		UIArt.button(button, UIArt.nav(ICONS[String(button.name)]), 22)
	if DETAILS.has(String(button.name)):
		button.focus_entered.connect(_describe.bind(button))
		button.mouse_entered.connect(_describe.bind(button))
		button.mouse_exited.connect(_restore_detail)


func add_coop_action(action: Callable) -> void:
	var button := _action(_play_actions, "LanCoop", "好友联机")
	button.tooltip_text = "2–4 人合作"
	UIArt.button(button, UIArt.nav("interact"), 22)
	button.pressed.connect(action)


func panel_rect() -> Rect2:
	return content.get_rect()


func refit() -> void:
	if not is_instance_valid(content): return
	var view := get_viewport_rect().size
	var text_scale := get_theme_default_font_size() / 16.0
	var compact := view.x < 690
	var dense := text_scale > 1.2 or view.x > view.y * 2.0
	var margin := clampf(view.x * 0.046, 24.0, 70.0)
	var top := 18.0 if compact or dense else 20.0
	var width := minf(378.0 * sqrt(text_scale), view.x * 0.47)
	if compact: width = view.x - margin * 2.0
	content.position = Vector2(margin, top)
	content.size = Vector2(width, view.y - top * 2.0)
	content.add_theme_constant_override("separation", 6)
	_title.add_theme_font_size_override("font_size", roundi((52.0 if dense else 73.0) * sqrt(text_scale)))
	_school.add_theme_font_size_override("font_size", roundi(14.0 * text_scale))
	description.add_theme_font_size_override("font_size", roundi(15.0 * sqrt(text_scale)))
	_primary.vertical = not dense or width < 344
	_utilities.columns = 1 if width < 310 and text_scale > 1.25 else 2
	_backdrop_button.visible = not compact
	_detail.visible = not compact and not dense
	_detail.offset_left = _detail.offset_right - minf(300.0, view.x * 0.32)
	_sync_title_width()


func set_touch(on: bool) -> void:
	_touch_on = on
	hint_label.text = "摇杆移动 · 滑动环视" if on else _keys_hint


func set_keys_hint(text: String) -> void:
	_keys_hint = text
	set_touch(_touch_on)


func set_save_available(value: bool) -> void:
	_load.theme_type_variation = "PrimaryButton" if value else "CommandButton"
	_new_game.theme_type_variation = "CommandButton" if value else "PrimaryButton"
	_primary.move_child(_load if value else _new_game, 0)
	_restore_detail()


func set_reduce_motion(value: bool) -> void:
	reduce_motion = value
	if value:
		open_now()
		if _detail_copy != null: UISkin.reveal(_detail_copy, true)
		UISkin.reveal(_front if _open_group.is_empty() else groups[_open_group], true)


func enter() -> void:
	_show_page("", false)
	if reduce_motion:
		open_now()
	else:
		state = "opening"
		_entrance = 0.0
		content.modulate.a = 0.5
		var light := ShaderMaterial.new()
		light.shader = TITLE_LIGHT
		_title.material = light
		_sync_title_width()
		set_process(true)
	focus_default()


func _process(delta: float) -> void:
	_entrance += delta
	if _entrance >= ENTRANCE_SECONDS:
		open_now()
	else:
		content.modulate.a = 0.5 + 0.5 * smoothstep(0.0, ENTRANCE_SECONDS, _entrance)
		(_title.material as ShaderMaterial).set_shader_parameter("progress", _entrance / ENTRANCE_SECONDS)


func _sync_title_width() -> void:
	if _title.material == null: return
	var font := _title.get_theme_font("font")
	var width := font.get_string_size(_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _title.get_theme_font_size("font_size")).x
	(_title.material as ShaderMaterial).set_shader_parameter("title_width", width)


func idle() -> bool:
	return state == "open"


func open_now() -> void:
	state = "open"
	content.modulate.a = 1.0
	_title.material = null
	set_process(false)


func focus_default() -> void:
	_focus_default.call_deferred()


func _focus_default() -> void:
	if not is_visible_in_tree(): return
	var first := _new_game if _load.disabled else _load
	if not _open_group.is_empty():
		var page := groups[_open_group] as VBoxContainer
		for child: Node in page.get_children():
			if child is Button and child.is_visible_in_tree() and not child.disabled:
				first = child
				break
	first.grab_focus()


func _show_page(id: String, restore_focus: bool = true) -> void:
	var previous := _open_group
	_open_group = id
	scroll.stop_motion()
	scroll.scroll_vertical = 0
	_front.visible = id.is_empty()
	for key: String in groups:
		groups[key].visible = key == id
	if not restore_focus: return
	UISkin.reveal(_front if id.is_empty() else groups[id], reduce_motion)
	if id.is_empty() and _group_buttons.has(previous):
		(_group_buttons[previous] as Button).grab_focus()
	else:
		focus_default()


func reveal(button: Control) -> void:
	open_now()
	var page := ""
	for id: String in groups:
		if (groups[id] as Control).is_ancestor_of(button):
			page = id
			break
	if _open_group != page: _show_page(page, false)
	if scroll.is_ancestor_of(button):
		await get_tree().process_frame
		if is_instance_valid(button) and button.is_visible_in_tree():
			scroll.ensure_control_visible(button)


func _unhandled_key_input(event: InputEvent) -> void:
	if _open_group.is_empty() or not is_visible_in_tree(): return
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		var focus := get_viewport().gui_get_focus_owner()
		if focus != null and not is_ancestor_of(focus): return
		_show_page("")
		get_viewport().set_input_as_handled()


## One tileable FBM texture shared by the menu and the boot animation (baked once, 256², single channel).
static func noise_texture() -> Texture2D:
	if _noise_texture == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = 5
		noise.frequency = 1.0 / 32.0
		noise.seed = 1338
		var image := noise.get_seamless_image(256, 256, false, false, 0.1, true)
		image.convert(Image.FORMAT_L8)
		_noise_texture = ImageTexture.create_from_image(image)
	return _noise_texture


## Heartbeat: two swells per beat (lub-dub), period about 1.1 s (used by the boot animation).
static func heartbeat(t: float) -> float:
	var x := fposmod(t, 1.1)
	return exp(-pow((x - 0.08) / 0.05, 2.0)) + 0.65 * exp(-pow((x - 0.32) / 0.06, 2.0))
