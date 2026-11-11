class_name SideMenu
extends Control
## The main menu, fixed to the left edge of the window: a black-iron spine with a torn rune tag. Clicking the
## tag tears it open along the spine, then stretches it sideways into a cracked frosted-glass panel joined to
## the spine by a concave seam; the title, five items and the version surface one by one out of blur and noise.
## The active item is a wiped peephole in the glass that the pointer drags along; choosing an action sends a
## green shadow pulse out from the item while the panel folds back into the tag and the colours seep back.
##
## Drawing is one CanvasItem fragment shader (side_menu.gdshader: FBM noise + SDF) under ordinary Control text.
## Sizes follow the window height, so it holds from 16:9 to 21:9. With reduced flashing the menu shows
## statically expanded and nothing distorts. The original buttons keep their names and signals; they sit
## under the five items (继续入梦 is LoadGame itself).

signal quit_requested

## Menu copy: the five items, top to bottom.
@export var item_labels: PackedStringArray = ["继续入梦", "新的轮回", "画廊与遗物", "感官设置", "逃离现实"]
## Palette A (resting): blood scab and abyss black. Palette B (after a choice): corpse grey and ghost green.
@export var scab_color := Color(0.23, 0.035, 0.035)
@export var abyss_color := Color(0.012, 0.008, 0.012)
@export var corpse_color := Color(0.36, 0.40, 0.38)
@export var ghost_color := Color(0.18, 0.78, 0.48)
## Glass soiling: refraction strength, cracks / water stains, and how much shadow covers the campus.
@export_range(0.0, 2.0) var glass_refraction := 1.0
@export_range(0.0, 2.0) var glass_stain := 1.0
@export_range(0.0, 1.0) var background_dim := 0.5
## Timeline (seconds).
@export var tear_time := 0.36
@export var stretch_time := 0.42
@export var reveal_step := 0.085
@export var reveal_time := 0.5
@export var fold_time := 0.4
@export var pulse_time := 1.15
@export var fade_back_time := 2.6
## Reduced flashing / motion: open statically, no distortion, no folding.
@export var reduce_motion := false

const SHADER := preload("res://game/presentation/ui/side_menu.gdshader")
const REVEAL := preload("res://game/presentation/ui/text_reveal.gdshader")
const ITEM_IDS := ["LoadGame", "Rebirth", "Gallery", "Senses", "QuitGame"]
const GROUPS := {
	"Rebirth": ["NewGame", "HardGame", "Speedrun", "DlcMenu", "ImportMenu"],
	"Gallery": ["Achievements", "Archive", "RecordsMenu"],
	"Senses": ["SettingsMenu", "FullscreenMenu", "TouchToggle", "SoundToggle", "DebugTools"]}
## Buttons that stay in the menu (toggles); every other leaf is an action that folds the panel.
const STAY := ["FullscreenMenu", "TouchToggle", "SoundToggle"]

var shell: ColorRect
var content: VBoxContainer
var scroll: TouchScroll
var tag_button: Button
var items: Array[Button] = []
var groups: Dictionary = {}          # item id -> VBoxContainer of its child buttons
var description: Label
var version_label: Label
var hint_label: Label
var state := "folded"                # folded / opening / open / closing
var open_amount := 0.0               # 0 tag … 1 panel (timeline position while opening)
var _title: Label
var _school: Button
var _new_game: Button
var _load: Button
var _mat: ShaderMaterial
var _reveal: Array[Control] = []     # in order of appearance
var _reveal_t := 0.0
var _t := 0.0
var _phase := 0.0                    # opening / closing clock
var _hover := 0.0
var _beat := 0.0
var _hole := Rect2()
var _hole_target := Rect2()
var _hole_on := 0.0
var _hot: Control
var _shift := 0.0
var _pulse_t := -1.0
var _pulse_origin := Vector2.ZERO
var _fade_t := -1.0
var _keys_hint := "WASD 移动 · 鼠标环视\nE 交互 · Esc 暂停"
var _touch_on := false
var _open_group := ""


func setup(source: VBoxContainer) -> void:
	name = "SideMenu"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	shell = ColorRect.new()
	shell.name = "MenuShell"
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	shell.material = _mat
	add_child(shell)
	tag_button = Button.new()
	tag_button.name = "MenuTag"
	tag_button.flat = true
	tag_button.tooltip_text = "打开菜单"
	tag_button.focus_mode = Control.FOCUS_ALL
	tag_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for style: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		tag_button.add_theme_stylebox_override(style, StyleBoxEmpty.new())
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.border_color = Color(0.85, 0.2, 0.18, 0.7)
	ring.set_border_width_all(2)
	ring.set_corner_radius_all(8)
	tag_button.add_theme_stylebox_override("focus", ring)
	tag_button.pressed.connect(open)
	add_child(tag_button)
	content = VBoxContainer.new()
	content.name = "MenuContent"
	content.add_theme_constant_override("separation", 6)
	add_child(content)
	_title = source.get_node("Title") as Label
	_title.reparent(content, false)
	_title.theme_type_variation = "HeadingLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title.add_theme_color_override("font_color", Color(0.93, 0.86, 0.82))
	_title.add_theme_color_override("font_shadow_color", Color(0.45, 0.02, 0.02, 0.8))
	_title.add_theme_constant_override("shadow_offset_x", 0)
	_title.add_theme_constant_override("shadow_offset_y", 0)
	_title.add_theme_constant_override("shadow_outline_size", 8)
	_school = source.get_node("SchoolName") as Button
	_school.reparent(content, false)
	_school.flat = true
	_school.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_school.add_theme_color_override("font_color", Color(0.72, 0.64, 0.6))
	_school.add_theme_color_override("font_hover_color", Color(0.85, 0.75, 0.7))
	description = source.get_node("Description") as Label
	description.reparent(content, false)
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_color_override("font_color", Color(0.62, 0.56, 0.54))
	for id: String in ["Eyebrow", "Help"]:
		var spare := source.get_node_or_null(id) as Control
		if spare != null: spare.hide()
	scroll = TouchScroll.new()
	scroll.name = "MenuScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	content.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "MenuItems"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	_new_game = source.find_child("NewGame", true, false) as Button
	for i in ITEM_IDS.size():
		var id := String(ITEM_IDS[i])
		var item: Button
		if id == "LoadGame":
			item = source.find_child("LoadGame", true, false) as Button
			_load = item
			item.reparent(list, false)
		else:
			item = Button.new()
			item.name = id
			list.add_child(item)
		item.text = item_labels[i] if i < item_labels.size() else id
		_style_item(item, true)
		items.append(item)
		if GROUPS.has(id):
			item.toggle_mode = false
			item.pressed.connect(_toggle_group.bind(id))
			var box := VBoxContainer.new()
			box.name = id + "Items"
			box.visible = false
			box.add_theme_constant_override("separation", 0)
			list.add_child(box)
			groups[id] = box
			for child_id: String in GROUPS[id]:
				var child := source.find_child(child_id, true, false) as Button
				if child == null: continue
				child.reparent(box, false)
				_style_item(child, false)
				if not child_id in STAY:
					child.pressed.connect(_acted.bind(child))
		elif id == "QuitGame":
			item.pressed.connect(func() -> void:
				_acted(item)
				quit_requested.emit())
		else:
			item.pressed.connect(_acted.bind(item))
	var foot := HBoxContainer.new()
	foot.name = "MenuFoot"
	content.add_child(foot)
	version_label = Label.new()
	version_label.name = "MenuVersion"
	version_label.text = "v%s · Godot" % String(ProjectSettings.get_setting("application/config/version", "0"))
	version_label.add_theme_color_override("font_color", Color(0.5, 0.42, 0.42, 0.85))
	version_label.add_theme_font_size_override("font_size", 12)
	foot.add_child(version_label)
	hint_label = Label.new()
	hint_label.name = "MenuKeys"
	hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint_label.add_theme_color_override("font_color", Color(0.5, 0.45, 0.45, 0.75))
	hint_label.add_theme_font_size_override("font_size", 11)
	foot.add_child(hint_label)
	for control: Control in [_title, _school, description] + items + [version_label, hint_label]:
		_reveal.append(control)
		var m := ShaderMaterial.new()
		m.shader = REVEAL
		control.material = m
	for box: VBoxContainer in groups.values():
		for child: Control in box.get_children():
			var m := ShaderMaterial.new()
			m.shader = REVEAL
			child.material = m
	set_touch(false)
	get_viewport().size_changed.connect(refit)
	theme_changed.connect(func() -> void: refit.call_deferred())
	resized.connect(refit)
	refit()
	_apply_state()


func _style_item(button: Button, top: bool) -> void:
	button.flat = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.custom_minimum_size.y = 48 if top else 44
	for style: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var empty := StyleBoxEmpty.new()
		empty.content_margin_left = 14.0 if top else 34.0
		empty.content_margin_right = 10.0
		button.add_theme_stylebox_override(style, empty)
	button.add_theme_color_override("font_color", Color(0.85, 0.79, 0.76, 0.86) if top else Color(0.74, 0.69, 0.67, 0.82))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.9, 0.86))
	button.add_theme_color_override("font_focus_color", Color(1.0, 0.9, 0.86))
	button.add_theme_color_override("font_pressed_color", Color(1.0, 0.8, 0.76))
	button.add_theme_color_override("font_hover_pressed_color", Color(1.0, 0.8, 0.76))
	button.add_theme_color_override("font_disabled_color", Color(0.42, 0.36, 0.36, 0.7))
	button.mouse_entered.connect(_aim.bind(button))
	button.focus_entered.connect(_aim.bind(button))


## Sizes follow the window height (the logical height is fixed by the stretch settings, the width grows
## up to 21:9); the panel never takes more than about 60 % of the width.
func layout_rects() -> Dictionary:
	var view := size if size.x > 0.0 else get_viewport_rect().size
	var h := view.y
	var font_k := get_theme_default_font_size() / 16.0
	var spine_w := roundf(h * 0.026)
	var panel_w := clampf(h * 0.8 * sqrt(font_k), 320.0, maxf(320.0, minf(view.x * 0.62, view.x - spine_w - 12.0)))
	var tag_w := roundf(h * 0.062)
	var tag_h := roundf(h * 0.17)
	var cy := h * 0.5
	return {"h": h, "spine": Rect2(0, 0, spine_w, h),
		"tag": Rect2(spine_w - 2.0, cy - tag_h * 0.5, tag_w, tag_h),
		"strip": Rect2(spine_w - 2.0, h * 0.05, tag_w, h * 0.9),
		"panel": Rect2(spine_w - 2.0, h * 0.05, panel_w, h * 0.9)}


func panel_rect() -> Rect2:
	return layout_rects()["panel"]


func refit() -> void:
	if not is_instance_valid(content): return
	var r := layout_rects()
	var h: float = r["h"]
	var p: Rect2 = r["panel"]
	var font_k := get_theme_default_font_size() / 16.0
	content.position = Vector2(p.position.x + h * 0.055, p.position.y + h * 0.045)
	content.size = Vector2(p.size.x - h * 0.055 - h * 0.04, p.size.y - h * 0.045 - h * 0.025)
	_title.add_theme_font_size_override("font_size", roundi(h * 0.085 * font_k))
	for item: Button in items:
		item.add_theme_font_size_override("font_size", roundi(h * 0.04 * font_k))
	for box: VBoxContainer in groups.values():
		for child: Control in box.get_children():
			child.add_theme_font_size_override("font_size", roundi(h * 0.03 * font_k))
	var tag: Rect2 = r["tag"]
	tag_button.position = tag.position - Vector2(6, 6)
	tag_button.size = tag.size + Vector2(12, 12)
	_mat.set_shader_parameter("u_size", size)


func set_touch(on: bool) -> void:
	_touch_on = on
	if hint_label != null:
		hint_label.text = "双指移动与环视 · 点击动作按钮交互" if on else _keys_hint.replace("\n", " · ")


func set_keys_hint(text: String) -> void:
	_keys_hint = text
	set_touch(_touch_on)


func set_save_available(value: bool) -> void:
	if _load == null: return
	_load.theme_type_variation = "PrimaryButton" if value else "Button"
	_new_game.theme_type_variation = "Button" if value else "PrimaryButton"


func set_reduce_motion(value: bool) -> void:
	reduce_motion = value
	if value and state != "open":
		open_now()


## Back on the menu: folded tag (or the static open menu with reduced motion), keyboard focus on it.
func enter() -> void:
	_pulse_t = -1.0
	_fade_t = -1.0
	_shift = 0.0
	if reduce_motion:
		open_now()
		focus_default()
		return
	state = "folded"
	open_amount = 0.0
	_apply_state()
	focus_default()


func focus_default() -> void:
	if state == "closing":
		return     # the fold ends by focusing the tag
	if state == "folded":
		tag_button.grab_focus.call_deferred()
	else:
		var first: Button = _load if _load != null and not _load.disabled else items[1]
		first.grab_focus.call_deferred()


func is_open() -> bool:
	return state == "open" or state == "opening"


func open() -> void:
	if state == "open" or state == "opening": return
	if reduce_motion:
		open_now()
		return
	state = "opening"
	_phase = 0.0
	_reveal_t = 0.0
	_apply_state()


## Fully open at once (reduced motion, tests, returning focus after a dialog).
func open_now() -> void:
	state = "open"
	open_amount = 1.0
	_phase = tear_time + stretch_time
	_reveal_t = 999.0
	_apply_state()


func fold() -> void:
	if reduce_motion or state == "folded" or state == "closing": return
	state = "closing"
	_phase = 0.0
	_apply_state()


## Open the group an original button lives in (and the menu), so callers can reach any action.
func reveal(button: Control) -> void:
	open_now()
	for id: String in groups:
		if (groups[id] as Control).is_ancestor_of(button) and _open_group != id:
			_toggle_group(id)
	scroll.ensure_control_visible(button)


func _toggle_group(id: String) -> void:
	_open_group = "" if _open_group == id else id
	for gid: String in groups:
		var box := groups[gid] as VBoxContainer
		var on := gid == _open_group
		box.visible = on
		if on:
			for i in box.get_child_count():
				var child := box.get_child(i) as Control
				var m := child.material as ShaderMaterial
				if m != null:
					m.set_shader_parameter("u_reveal", 1.0 if reduce_motion else 0.0)
				child.set_meta("reveal_at", _reveal_clock() + float(i) * reveal_step * 0.6)


func _acted(from: Control) -> void:
	if reduce_motion: return
	var c := from.get_global_rect().get_center()
	_pulse_origin = get_global_transform().affine_inverse() * c
	_pulse_t = 0.0
	_fade_t = -1.0
	fold()


func _aim(control: Control) -> void:
	_hot = control


func _apply_state() -> void:
	var folded := state == "folded" or state == "closing"
	content.visible = not folded or state == "closing"
	tag_button.visible = state == "folded"
	for control: Control in _reveal:
		var m := control.material as ShaderMaterial
		if m != null:
			m.set_shader_parameter("u_reveal", 1.0 if state == "open" and _reveal_t >= 999.0 else 0.0)
	if state == "open" and _reveal_t >= 999.0:
		for box: VBoxContainer in groups.values():
			for child: Control in box.get_children():
				var m := child.material as ShaderMaterial
				if m != null: m.set_shader_parameter("u_reveal", 1.0)
	_set_input(state == "open")
	_draw_params(0.0)


func _set_input(on: bool) -> void:
	for b: Control in content.find_children("*", "BaseButton", true, false):
		(b as BaseButton).mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
		(b as BaseButton).focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE


func _reveal_clock() -> float:
	return _reveal_t


## Heartbeat: two swells per beat (lub-dub), period about 1.1 s.
static func heartbeat(t: float) -> float:
	var x := fposmod(t, 1.1)
	return exp(-pow((x - 0.08) / 0.05, 2.0)) + 0.65 * exp(-pow((x - 0.32) / 0.06, 2.0))


func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	_t += delta
	var r := layout_rects()
	var opening := tear_time + stretch_time
	match state:
		"opening":
			_phase += delta
			open_amount = clampf(_phase / opening, 0.0, 1.0)
			if _phase >= opening:
				state = "open"
				_reveal_t = 0.0
				_set_input(true)
				focus_default()
		"open":
			if _reveal_t < 999.0:
				_reveal_t += delta
		"closing":
			_phase += delta
			open_amount = clampf(1.0 - _phase / fold_time, 0.0, 1.0)
			if _phase >= fold_time:
				state = "folded"
				open_amount = 0.0
				_fade_t = 0.0
				_apply_state()
				if not get_viewport().gui_get_focus_owner() is LineEdit:
					focus_default()
	# Text surfacing one by one once the glass is out.
	if state == "open" and _reveal_t < 999.0:
		var done := true
		for i in _reveal.size():
			var k := clampf((_reveal_t - float(i) * reveal_step) / reveal_time, 0.0, 1.0)
			done = done and k >= 1.0
			_set_reveal(_reveal[i], k)
		if done:
			_reveal_t = 999.0
	elif state == "closing":
		for control: Control in _reveal:
			_set_reveal(control, clampf(1.0 - _phase / (fold_time * 0.4), 0.0, 1.0))
	for box: VBoxContainer in groups.values():
		if not box.visible: continue
		for child: Control in box.get_children():
			if child.has_meta("reveal_at") and state == "open":
				var start := float(child.get_meta("reveal_at"))
				var clock := _reveal_t if _reveal_t < 999.0 else start + reveal_time
				var k := 1.0 if reduce_motion else clampf((clock - start) / (reveal_time * 0.7), 0.0, 1.0)
				if _reveal_t >= 999.0 and k < 1.0:
					child.set_meta("reveal_at", start - delta)
				_set_reveal(child, k)
				if k >= 1.0: child.remove_meta("reveal_at")
			elif state == "closing":
				_set_reveal(child, clampf(1.0 - _phase / (fold_time * 0.4), 0.0, 1.0))
	# Pointer near the folded tag: heartbeat swell.
	var mouse := get_local_mouse_position()
	var tag: Rect2 = r["tag"]
	var near := 0.0
	if state == "folded":
		var d := maxf(0.0, maxf(absf(mouse.x - tag.get_center().x) - tag.size.x * 0.5, absf(mouse.y - tag.get_center().y) - tag.size.y * 0.5))
		near = clampf(1.0 - d / (r["h"] * 0.22), 0.0, 1.0)
		if tag_button.has_focus(): near = maxf(near, 0.6)
	_hover = move_toward(_hover, near, delta * 3.0)
	_beat = 0.0 if reduce_motion else heartbeat(_t * (1.0 + 0.5 * _hover)) * (0.25 + 0.75 * _hover)
	# The peephole follows the hovered / focused item, sticky like something wet.
	var target_on := 0.0
	if state == "open" and is_instance_valid(_hot) and _hot.is_visible_in_tree() and content.is_ancestor_of(_hot):
		var g := _hot.get_global_rect()
		var inv := get_global_transform().affine_inverse()
		_hole_target = Rect2(inv * g.position, g.size)
		target_on = 1.0
	if _hole.size == Vector2.ZERO: _hole = _hole_target
	var k_follow := 1.0 if reduce_motion else 1.0 - exp(-delta * 9.0)
	_hole = Rect2(_hole.position.lerp(_hole_target.position, k_follow), _hole.size.lerp(_hole_target.size, k_follow))
	_hole_on = move_toward(_hole_on, target_on, delta * 5.0)
	# Pulse and the slow fade back to the scab palette.
	if _pulse_t >= 0.0:
		_pulse_t += delta
		_shift = minf(1.0, _shift + delta * 6.0)
		if _pulse_t >= pulse_time: _pulse_t = -1.0
	elif _fade_t >= 0.0:
		_fade_t += delta
		_shift = maxf(0.0, 1.0 - _fade_t / fade_back_time)
		if _fade_t >= fade_back_time: _fade_t = -1.0
	_draw_params(delta)


func _set_reveal(control: Control, k: float) -> void:
	var m := control.material as ShaderMaterial
	if m == null: return
	m.set_shader_parameter("u_reveal", k)
	m.set_shader_parameter("u_time", _t)


## The body rect along the timeline: tag → tall torn strip (tear) → panel (stretch).
func body_rect() -> Rect2:
	var r := layout_rects()
	var tag: Rect2 = r["tag"]
	var strip: Rect2 = r["strip"]
	var panel: Rect2 = r["panel"]
	var opening := tear_time + stretch_time
	var tt := open_amount * opening
	var a := clampf(tt / tear_time, 0.0, 1.0)
	var b := clampf((tt - tear_time) / stretch_time, 0.0, 1.0)
	a = a * a * (3.0 - 2.0 * a)
	b = 1.0 - pow(1.0 - b, 3.0)
	var body := Rect2(tag.position.lerp(strip.position, a), tag.size.lerp(strip.size, a))
	body = Rect2(body.position, Vector2(lerpf(body.size.x, panel.size.x, b), body.size.y))
	if state == "folded":
		var swell := 1.0 + 0.1 * _beat
		var jitter := Vector2(sin(_t * 7.3) + 0.5 * sin(_t * 13.1), cos(_t * 6.1)) * 1.2 * _hover * (0.0 if reduce_motion else 1.0)
		var c := body.get_center() + jitter
		body = Rect2(Vector2(body.position.x, c.y - body.size.y * swell * 0.5), Vector2(body.size.x * swell, body.size.y * swell))
	return body


func _draw_params(_delta: float) -> void:
	if _mat == null: return
	var r := layout_rects()
	var h: float = r["h"]
	var spine: Rect2 = r["spine"]
	var body := body_rect()
	var moving := state == "opening" or state == "closing"
	var tear := 0.0
	if moving and not reduce_motion:
		tear = sin(open_amount * PI) * 1.4
	elif state == "folded":
		tear = 0.35
	_mat.set_shader_parameter("u_size", size)
	_mat.set_shader_parameter("u_time", _t)
	_mat.set_shader_parameter("u_spine", Vector4(spine.position.x, spine.position.y, spine.end.x, spine.end.y))
	_mat.set_shader_parameter("u_body", Vector4(body.position.x, body.position.y, body.end.x, body.end.y))
	_mat.set_shader_parameter("u_radius", h * (0.012 if state == "folded" else 0.022))
	_mat.set_shader_parameter("u_seam", h * 0.035)
	_mat.set_shader_parameter("u_open", open_amount)
	_mat.set_shader_parameter("u_tear", tear)
	_mat.set_shader_parameter("u_hover", _hover)
	_mat.set_shader_parameter("u_beat", _beat)
	_mat.set_shader_parameter("u_hole", Vector4(_hole.position.x - h * 0.012, _hole.position.y + 2.0, _hole.end.x + h * 0.012, _hole.end.y - 2.0))
	_mat.set_shader_parameter("u_hole_on", _hole_on * open_amount)
	_mat.set_shader_parameter("u_a0", scab_color)
	_mat.set_shader_parameter("u_a1", abyss_color)
	_mat.set_shader_parameter("u_b0", corpse_color)
	_mat.set_shader_parameter("u_b1", ghost_color)
	_mat.set_shader_parameter("u_shift", _shift)
	_mat.set_shader_parameter("u_pulse_origin", _pulse_origin)
	var diag := size.length()
	var pk := clampf(_pulse_t / pulse_time, 0.0, 1.0) if _pulse_t >= 0.0 else 1.0
	_mat.set_shader_parameter("u_pulse_r", (1.0 - pow(1.0 - pk, 2.2)) * diag)
	_mat.set_shader_parameter("u_pulse_a", (1.0 - pk) if _pulse_t >= 0.0 else 0.0)
	_mat.set_shader_parameter("u_refraction", glass_refraction)
	_mat.set_shader_parameter("u_stain", glass_stain)
	_mat.set_shader_parameter("u_bg_dim", background_dim)
	_mat.set_shader_parameter("u_motion", 0.0 if reduce_motion else 1.0)


## Keyboard: with the menu folded, Enter / Space / arrows open it.
func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or state != "folded": return
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_DOWN, KEY_UP, KEY_RIGHT]:
		open()
		get_viewport().set_input_as_handled()
