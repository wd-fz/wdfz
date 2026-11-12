class_name SideMenu
extends Control
## The main menu, fixed to the left edge of the window: a black-iron spine from which, on entering the menu,
## a cracked frosted-glass panel tears open along the spine and stretches sideways, joined to the spine by a
## concave seam; the title, five items and the version surface one by one out of blur and noise. The active
## item is a wiped peephole in the glass that the pointer drags along; choosing an action sends a green
## shadow pulse out from the item and the colours seep back to the blood scab.
##
## 2026-11-11 revision (user request): no folded tag to click first — the menu opens by itself; actions no
## longer fold it. Cost: one alpha-composited CanvasItem shader (side_menu.gdshader: SDF shapes, one baked
## tileable FBM texture, a tiny pre-blurred background for the frost) under ordinary Control text; the reveal
## shader is attached only while text surfaces. idle() tells the app when nothing animates, so the menu can
## run at a lower frame rate. Sizes follow the window height (16:9 to 21:9). Reduced flashing shows the menu
## statically expanded. The original buttons keep their names and signals (继续入梦 is LoadGame itself).

signal quit_requested

## Menu copy: the five items, top to bottom.
@export var item_labels: PackedStringArray = ["继续入梦", "新的轮回", "画廊与遗物", "感官设置", "逃离现实"]
## Palette A (resting): blood scab and abyss black. Palette B (after a choice): corpse grey and ghost green.
@export var scab_color := Color(0.23, 0.035, 0.035)
@export var abyss_color := Color(0.012, 0.008, 0.012)
@export var corpse_color := Color(0.36, 0.40, 0.38)
@export var ghost_color := Color(0.18, 0.78, 0.48)
## Glass soiling: refraction strength, cracks / water stains, and how much shadow covers the background.
@export_range(0.0, 2.0) var glass_refraction := 1.0
@export_range(0.0, 2.0) var glass_stain := 1.0
@export_range(0.0, 1.0) var background_dim := 0.5
## Timeline (seconds).
@export var tear_time := 0.3
@export var stretch_time := 0.36
@export var reveal_step := 0.06
@export var reveal_time := 0.4
@export var pulse_time := 1.15
@export var fade_back_time := 2.6
## Reduced flashing / motion: open statically, no distortion.
@export var reduce_motion := false

const SHADER := preload("res://game/presentation/ui/side_menu.gdshader")
const REVEAL := preload("res://game/presentation/ui/text_reveal.gdshader")
const ITEM_IDS := ["LoadGame", "Rebirth", "Gallery", "Senses", "QuitGame"]
const GROUPS := {
	"Rebirth": ["NewGame", "HardGame", "Speedrun", "DlcMenu", "ImportMenu"],
	"Gallery": ["Achievements", "Archive", "RecordsMenu"],
	"Senses": ["SettingsMenu", "FullscreenMenu", "TouchToggle", "SoundToggle", "DebugTools"]}
## Buttons that are switches; every other leaf is an action that sends the pulse.
const STAY := ["FullscreenMenu", "TouchToggle", "SoundToggle"]

static var _noise_texture: Texture2D

var shell: ColorRect
var content: VBoxContainer
var scroll: TouchScroll
var items: Array[Button] = []
var groups: Dictionary = {}          # item id -> VBoxContainer of its child buttons
var description: Label
var version_label: Label
var hint_label: Label
var state := "opening"               # opening / open
var open_amount := 0.0               # 0 torn sliver … 1 panel (timeline position while opening)
var _title: Label
var _school: Button
var _new_game: Button
var _load: Button
var _mat: ShaderMaterial
var _reveal: Array[Control] = []     # in order of appearance
var _reveal_t := 0.0
var _revealing := false
var _t := 0.0
var _phase := 0.0
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
	_mat.set_shader_parameter("u_noise", noise_texture())
	_mat.set_shader_parameter("u_frost", _plain_frost())
	shell.material = _mat
	add_child(shell)
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
	set_touch(false)
	get_viewport().size_changed.connect(refit)
	content.minimum_size_changed.connect(func() -> void: refit.call_deferred())
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
	var sliver_w := roundf(h * 0.03)
	var sliver_h := roundf(h * 0.12)
	var cy := h * 0.5
	return {"h": h, "spine": Rect2(0, 0, spine_w, h),
		"sliver": Rect2(spine_w - 2.0, cy - sliver_h * 0.5, sliver_w, sliver_h),
		"strip": Rect2(spine_w - 2.0, h * 0.05, sliver_w * 2.0, h * 0.9),
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
	var inner := Vector2(p.size.x - h * 0.055 - h * 0.04, p.size.y - h * 0.045 - h * 0.025)
	# Wrapped labels measured at zero width ask for one line per glyph and stretch the column for good;
	# give them the real width up front and re-apply the size whenever a minimum changes.
	description.custom_minimum_size.x = inner.x
	content.size = inner
	_title.add_theme_font_size_override("font_size", roundi(h * 0.085 * font_k))
	for item: Button in items:
		item.add_theme_font_size_override("font_size", roundi(h * 0.04 * font_k))
	for box: VBoxContainer in groups.values():
		for child: Control in box.get_children():
			child.add_theme_font_size_override("font_size", roundi(h * 0.03 * font_k))
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
	if value:
		open_now()


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


static func _plain_frost() -> Texture2D:
	var image := Image.create(4, 4, false, Image.FORMAT_RGB8)
	image.fill(Color(0.05, 0.05, 0.06))
	return ImageTexture.create_from_image(image)


## The frosted glass shows a tiny, pre-blurred copy of what is behind the menu (the menu photo).
func set_frost(texture: Texture2D) -> void:
	if texture == null or _mat == null: return
	var image := texture.get_image()
	if image == null or image.is_empty(): return
	image = image.duplicate()
	if image.is_compressed(): image.decompress()
	image.convert(Image.FORMAT_RGB8)
	image.resize(48, 27, Image.INTERPOLATE_BILINEAR)
	_mat.set_shader_parameter("u_frost", ImageTexture.create_from_image(image))


## Entering the menu: the panel tears open by itself (statically open with reduced motion).
func enter() -> void:
	_pulse_t = -1.0
	_fade_t = -1.0
	_shift = 0.0
	if reduce_motion:
		open_now()
	else:
		state = "opening"
		open_amount = 0.0
		_phase = 0.0
		_reveal_t = 0.0
		_apply_state()
	focus_default()


func focus_default() -> void:
	var first: Button = _load if _load != null and not _load.disabled else items[1]
	first.grab_focus.call_deferred()


func is_open() -> bool:
	return true


## True when nothing moves except the slow background crawl: the app may lower the menu frame rate.
func idle() -> bool:
	return state == "open" and not _revealing and _pulse_t < 0.0 and _fade_t < 0.0 \
		and _hole.position.distance_to(_hole_target.position) < 0.5


func open() -> void:
	if state != "open":
		enter()


## Fully open at once (reduced motion, tests).
func open_now() -> void:
	state = "open"
	open_amount = 1.0
	_phase = tear_time + stretch_time
	_reveal_t = 0.0
	_revealing = false
	_apply_state()


## Open the group an original button lives in, so callers can reach any action.
func reveal(button: Control) -> void:
	open_now()
	for id: String in groups:
		if (groups[id] as Control).is_ancestor_of(button) and _open_group != id:
			_toggle_group(id)
	scroll.ensure_control_visible(button)
	_scroll_into_view(button)


## A group that has just opened is laid out on the next frame; scroll to the button once it has its place.
func _scroll_into_view(button: Control) -> void:
	await get_tree().process_frame
	if is_instance_valid(button) and button.is_visible_in_tree():
		scroll.ensure_control_visible(button)


func _toggle_group(id: String) -> void:
	refit.call_deferred()
	_open_group = "" if _open_group == id else id
	for gid: String in groups:
		var box := groups[gid] as VBoxContainer
		var on := gid == _open_group
		box.visible = on
		if on and not reduce_motion and state == "open":
			# The children surface one by one too.
			for i in box.get_child_count():
				var child := box.get_child(i) as Control
				_attach_reveal(child, 0.0)
				child.set_meta("reveal_at", _reveal_t + float(i) * reveal_step)
			_revealing = true


func _acted(from: Control) -> void:
	if reduce_motion: return
	var c := from.get_global_rect().get_center()
	_pulse_origin = get_global_transform().affine_inverse() * c
	_pulse_t = 0.0
	_fade_t = -1.0


func _aim(control: Control) -> void:
	_hot = control


func _attach_reveal(control: Control, k: float) -> void:
	var m := control.material as ShaderMaterial
	if m == null:
		m = ShaderMaterial.new()
		m.shader = REVEAL
		control.material = m
	m.set_shader_parameter("u_reveal", k)
	m.set_shader_parameter("u_time", _t)


## The reveal shader is dropped once text is sharp: plain text batches and costs nothing extra.
func _set_reveal(control: Control, k: float) -> void:
	if k >= 1.0:
		control.material = null
	else:
		_attach_reveal(control, k)


func _apply_state() -> void:
	content.visible = true
	var hidden := state == "opening" and not reduce_motion
	for control: Control in _reveal:
		_set_reveal(control, 0.0 if hidden else 1.0)
	for box: VBoxContainer in groups.values():
		for child: Control in box.get_children():
			_set_reveal(child, 1.0)
			child.remove_meta("reveal_at")
	_draw_params()


## Heartbeat: two swells per beat (lub-dub), period about 1.1 s (used by the boot animation).
static func heartbeat(t: float) -> float:
	var x := fposmod(t, 1.1)
	return exp(-pow((x - 0.08) / 0.05, 2.0)) + 0.65 * exp(-pow((x - 0.32) / 0.06, 2.0))


func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	_t += delta
	var opening := tear_time + stretch_time
	if state == "opening":
		_phase += delta
		open_amount = clampf(_phase / opening, 0.0, 1.0)
		if _phase >= opening:
			state = "open"
			_reveal_t = 0.0
			_revealing = true
	elif _revealing:
		_reveal_t += delta
		var done := true
		for i in _reveal.size():
			if _reveal[i].material == null and _reveal_t > 0.0 and i * reveal_step + reveal_time < _reveal_t: continue
			var k := clampf((_reveal_t - float(i) * reveal_step) / reveal_time, 0.0, 1.0)
			done = done and k >= 1.0
			_set_reveal(_reveal[i], k)
		for box: VBoxContainer in groups.values():
			if not box.visible: continue
			for child: Control in box.get_children():
				if not child.has_meta("reveal_at"): continue
				var k := clampf((_reveal_t - float(child.get_meta("reveal_at"))) / (reveal_time * 0.7), 0.0, 1.0)
				_set_reveal(child, k)
				if k >= 1.0: child.remove_meta("reveal_at")
				else: done = false
		_revealing = not done
	# The peephole follows the hovered / focused item, sticky like something wet.
	var target_on := 0.0
	if state == "open" and is_instance_valid(_hot) and _hot.is_visible_in_tree() and content.is_ancestor_of(_hot):
		var g := _hot.get_global_rect()
		_hole_target = Rect2(get_global_transform().affine_inverse() * g.position, g.size)
		target_on = 1.0
	if _hole.size == Vector2.ZERO: _hole = _hole_target
	var k_follow := 1.0 if reduce_motion else 1.0 - exp(-delta * 9.0)
	_hole = Rect2(_hole.position.lerp(_hole_target.position, k_follow), _hole.size.lerp(_hole_target.size, k_follow))
	_hole_on = move_toward(_hole_on, target_on, delta * 5.0)
	if _pulse_t >= 0.0:
		_pulse_t += delta
		_shift = minf(1.0, _shift + delta * 6.0)
		if _pulse_t >= pulse_time:
			_pulse_t = -1.0
			_fade_t = 0.0
	elif _fade_t >= 0.0:
		_fade_t += delta
		_shift = maxf(0.0, 1.0 - _fade_t / fade_back_time)
		if _fade_t >= fade_back_time: _fade_t = -1.0
	_draw_params()


## The body rect along the timeline: torn sliver → tall strip (tear) → panel (stretch).
func body_rect() -> Rect2:
	var r := layout_rects()
	var sliver: Rect2 = r["sliver"]
	var strip: Rect2 = r["strip"]
	var panel: Rect2 = r["panel"]
	var opening := tear_time + stretch_time
	var tt := open_amount * opening
	var a := clampf(tt / tear_time, 0.0, 1.0)
	var b := clampf((tt - tear_time) / stretch_time, 0.0, 1.0)
	a = a * a * (3.0 - 2.0 * a)
	b = 1.0 - pow(1.0 - b, 3.0)
	var body := Rect2(sliver.position.lerp(strip.position, a), sliver.size.lerp(strip.size, a))
	return Rect2(body.position, Vector2(lerpf(body.size.x, panel.size.x, b), body.size.y))


func _draw_params() -> void:
	if _mat == null: return
	var r := layout_rects()
	var h: float = r["h"]
	var spine: Rect2 = r["spine"]
	var body := body_rect()
	_mat.set_shader_parameter("u_size", size)
	_mat.set_shader_parameter("u_time", _t)
	_mat.set_shader_parameter("u_spine", Vector4(spine.position.x, spine.position.y, spine.end.x, spine.end.y))
	_mat.set_shader_parameter("u_body", Vector4(body.position.x, body.position.y, body.end.x, body.end.y))
	_mat.set_shader_parameter("u_radius", h * 0.022)
	_mat.set_shader_parameter("u_seam", h * 0.035)
	_mat.set_shader_parameter("u_open", open_amount)
	_mat.set_shader_parameter("u_tear", sin(open_amount * PI) * 1.4 if state == "opening" and not reduce_motion else 0.0)
	_mat.set_shader_parameter("u_hole", Vector4(_hole.position.x - h * 0.012, _hole.position.y + 2.0, _hole.end.x + h * 0.012, _hole.end.y - 2.0))
	_mat.set_shader_parameter("u_hole_on", _hole_on * open_amount)
	_mat.set_shader_parameter("u_a0", scab_color)
	_mat.set_shader_parameter("u_a1", abyss_color)
	_mat.set_shader_parameter("u_b0", corpse_color)
	_mat.set_shader_parameter("u_b1", ghost_color)
	_mat.set_shader_parameter("u_shift", _shift)
	_mat.set_shader_parameter("u_pulse_origin", _pulse_origin)
	var pk := clampf(_pulse_t / pulse_time, 0.0, 1.0) if _pulse_t >= 0.0 else 1.0
	_mat.set_shader_parameter("u_pulse_r", (1.0 - pow(1.0 - pk, 2.2)) * size.length())
	_mat.set_shader_parameter("u_pulse_a", (1.0 - pk) if _pulse_t >= 0.0 else 0.0)
	_mat.set_shader_parameter("u_refraction", glass_refraction)
	_mat.set_shader_parameter("u_stain", glass_stain)
	_mat.set_shader_parameter("u_bg_dim", background_dim)
	_mat.set_shader_parameter("u_motion", 0.0 if reduce_motion else 1.0)
