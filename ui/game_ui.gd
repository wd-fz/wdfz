class_name GameUI
extends CanvasLayer

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
signal map_requested(id: String)
signal notes_requested(query: String)
signal notes_focus_requested(route: String)
signal setting_changed(key: String, value: int)

@onready var menu: Control = %Menu
@onready var pause_panel: Control = %PausePanel
@onready var hud: Control = %HUD
@onready var touch_controls: Control = %TouchControls
@onready var stick: TouchStick = %MovePad
@onready var look_pad: TouchLook = %LookPad

var _mode := "menu"
var choice_panel: PanelContainer
var lift_close_button: Button
var _choice_box: VBoxContainer
var _choice_scroll: ScrollContainer
var _choice_text: Label
var _touch_enabled := false
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
	%TouchSprint.toggled.connect(func(value: bool) -> void: touch_sprint.emit(value))
	stick.moved.connect(func(value: Vector2) -> void: touch_move.emit(value))
	look_pad.looked.connect(func(value: Vector2) -> void: touch_look.emit(value))
	%TouchToggle.toggled.connect(set_touch_enabled)
	_build_choice()
	_build_status()
	_build_bag()
	_build_death()
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
	# Same menu height as before: the load button shares a row with the list, the touch toggle with the sound toggle.
	var load_row := HBoxContainer.new()
	var option_row := HBoxContainer.new()
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
	var gear := Button.new()
	gear.name = "SettingsMenu"
	gear.text = "设置"
	gear.custom_minimum_size = Vector2(0, 48)
	gear.pressed.connect(func() -> void: settings_requested.emit())
	option_row.add_child(gear)
	var gear2 := Button.new()
	gear2.name = "SettingsPause"
	gear2.text = "设置"
	gear2.custom_minimum_size = Vector2(0, 48)
	gear2.pressed.connect(func() -> void: settings_requested.emit())
	%Save.add_sibling(gear2)
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
	load_button.owner = self
	touch_toggle.owner = self
	set_touch_enabled(DisplayServer.is_touchscreen_available())
	get_tree().root.size_changed.connect(_resize)
	_resize()
	set_mode("menu")


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed and not _touch_enabled:
		set_touch_enabled(true)


func _process(delta: float) -> void:
	tick_opening(delta)
	if _grain_rect != null and _grain_rect.visible:
		(_grain_rect.material as ShaderMaterial).set_shader_parameter("t", Time.get_ticks_msec() / 1000.0)
	if _bolt_rect != null and _bolt_level > 0.0:
		_bolt_level = maxf(0.0, _bolt_level - delta * 3.0)
		_bolt_rect.color.a = _bolt_level
	if _hurt_rect != null and _hurt_level > 0.0:
		_hurt_level = maxf(0.0, _hurt_level - delta * 0.5)
		_hurt_rect.color.a = _hurt_level
	if _toast_seconds > 0.0:
		_toast_seconds -= delta
		%Toast.visible = _toast_seconds > 0.0


func _resize() -> void:
	var window := get_tree().root
	var reference := Vector2i(480, 800) if window.size.x < window.size.y else Vector2i(960, 540)
	if window.content_scale_size != reference:
		window.content_scale_size = reference
	clear_touch()
	if choice_panel != null and choice_panel.visible:
		_fit_choice.call_deferred()


## Old UI.choice: a short prompt with buttons; keys 1–9 pick, Esc / 算了 closes.
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
	_choice_scroll = ScrollContainer.new()
	_choice_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_choice_scroll.add_child(_choice_box)
	box.add_child(_choice_scroll)
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
	_captions.position.y = _status_line.position.y + _status_line.size.y + 6.0 if _status_line.visible else 58.0


func captions_text() -> String:
	return _captions.text if _captions != null else ""


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
	# Sound captions sit right under the status card (sound-captions.js place()).
	_captions = Label.new()
	_captions.name = "SoundCaptions"
	_captions.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_captions.position = Vector2(16, 104)
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
	_location = clock
	_status_line.visible = true
	_status_line.text = "%s\n%s" % [place, period]
	_status_line.modulate = Color(0.95, 0.78, 0.4) if state == "warn" else Color(0.75, 0.95, 0.85)


func reset_status() -> void:
	_status_on = false
	_location = "移植测试场景"
	if _status_line != null:
		_status_line.visible = false
		_stamina.visible = false


func show_stamina(value: float, maximum: float, out_of_breath: bool) -> void:
	_stamina.visible = value < 99.5
	_stamina.max_value = 100.0
	_stamina.value = clampf(value, 0.0, 100.0)
	_stamina.modulate = Color(0.85, 0.45, 0.35) if out_of_breath else Color(0.55, 0.75, 0.95)


## Bag panel (old manual 背包 tab): name, description, 使用 and the two hot slots.
func _build_bag() -> void:
	bag_panel = PanelContainer.new()
	bag_panel.name = "BagPanel"
	bag_panel.visible = false
	bag_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	bag_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bag_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	bag_panel.custom_minimum_size = Vector2(460, 0)
	var box := VBoxContainer.new()
	var title := Label.new()
	title.text = "背包（Tab 关闭）"
	box.add_child(title)
	_bag_list = VBoxContainer.new()
	box.add_child(_bag_list)
	bag_panel.add_child(box)
	$Root.add_child(bag_panel)
	_search_ring = ProgressBar.new()
	_search_ring.name = "SearchRing"
	_search_ring.show_percentage = false
	_search_ring.custom_minimum_size = Vector2(90, 6)
	_search_ring.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_search_ring.position.y += 22
	_search_ring.max_value = 1.0
	_search_ring.visible = false
	hud.add_child(_search_ring)
	_hot_label = Label.new()
	_hot_label.name = "HotSlots"
	_hot_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_hot_label.position = Vector2(16, -40)
	_hot_label.add_theme_font_size_override("font_size", 14)
	hud.add_child(_hot_label)


func show_bag(entries: Array) -> void:
	for child in _bag_list.get_children():
		child.queue_free()
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "背包是空的。"
		_bag_list.add_child(empty)
	for e: Dictionary in entries:
		var row := VBoxContainer.new()
		var name := Label.new()
		name.text = String(e["name"])
		row.add_child(name)
		var desc := Label.new()
		desc.text = String(e["text"])
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(420, 0)
		desc.modulate = Color(0.8, 0.85, 0.82)
		row.add_child(desc)
		var buttons := HBoxContainer.new()
		var id := String(e["id"])
		for spec: Array in [["使用", -1], ["放到快捷栏 1", 0], ["放到快捷栏 2", 1], ["丢弃", -2]]:
			var b := Button.new()
			b.text = spec[0]
			b.name = "Drop_" + id if spec[1] == -2 else "Item_%s_%d" % [id, int(spec[1])]
			if spec[1] == -1:
				b.pressed.connect(item_use_requested.emit.bind(id))
			elif spec[1] == -2:
				b.pressed.connect(item_drop_requested.emit.bind(id))
			else:
				b.pressed.connect(item_hot_requested.emit.bind(int(spec[1]), id))
			buttons.add_child(b)
		row.add_child(buttons)
		_bag_list.add_child(row)
	bag_panel.visible = true


func hide_bag() -> void:
	bag_panel.visible = false


func bag_open() -> bool:
	return bag_panel != null and bag_panel.visible


func show_search(progress: float) -> void:
	_search_ring.visible = progress > 0.0
	_search_ring.value = progress


func show_hot(text: String) -> void:
	_hot_label.text = text


## Death: a dark red fade while the (not yet ported) death scene would play, then the record
## card with message, epitaph, cause and repeated-death hints (old #die panel).
var _death_fade: ColorRect
var death_panel: PanelContainer
var _death_text: Label


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
	death_panel.custom_minimum_size = Vector2(480, 0)
	var box := VBoxContainer.new()
	_death_text = Label.new()
	_death_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_death_text.custom_minimum_size = Vector2(440, 0)
	box.add_child(_death_text)
	var back := Button.new()
	back.text = "回到主菜单"
	back.pressed.connect(func() -> void: death_menu_requested.emit())
	box.add_child(back)
	death_panel.add_child(box)
	$Root.add_child(death_panel)


## Screen-space death scene (a placeholder for fx/death-cg.js): the style follows the family of the
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


func show_death_card(message: String, epitaph: String, cause: String, hints: PackedStringArray) -> void:
	var lines := [message]
	if not epitaph.is_empty():
		lines.append("「%s」" % epitaph)
	if not cause.is_empty():
		lines.append(cause)
	for h: String in hints:
		lines.append("· " + h)
	_death_text.text = "\n\n".join(lines)
	death_panel.visible = true


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


func show_achievements(entries: Array, points: int) -> void:
	var rows: Array = []
	var got := 0
	for e: Dictionary in entries:
		var text := "%s · %s" % [e["tier"], e["name"]]
		if e.has("progress"):
			text += "  （%d / %d）" % [e["progress"]["n"], e["progress"]["of"]]
		if e["unlocked"]:
			got += 1
		rows.append({"text": text, "on": e["unlocked"], "memo": e["memo"]})
	show_list("成就  %d / %d　·　积分 %d" % [got, entries.size(), points], rows)


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
		ach_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		ach_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		ach_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		ach_panel.custom_minimum_size = Vector2(560, 0)
		var back := StyleBoxFlat.new()
		back.bg_color = Color(0.03, 0.05, 0.07, 0.98)
		back.set_content_margin_all(16)
		back.set_corner_radius_all(6)
		ach_panel.add_theme_stylebox_override("panel", back)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		_ach_head = Label.new()
		box.add_child(_ach_head)
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(520, 360)
		_ach_list = VBoxContainer.new()
		_ach_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(_ach_list)
		box.add_child(scroll)
		var close := Button.new()
		close.text = "关闭"
		close.pressed.connect(func() -> void: ach_panel.visible = false)
		box.add_child(close)
		ach_panel.add_child(box)
		$Root.add_child(ach_panel)
	for child in _ach_list.get_children():
		child.queue_free()
	for r: Dictionary in rows:
		var line := Label.new()
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size = Vector2(500, 0)
		var text := String(r["text"])
		if r["on"] and not String(r["memo"]).is_empty():
			text += "\n    " + String(r["memo"])
		line.text = ("✓ " if r["on"] else "· ") + text
		line.modulate = Color(1, 1, 1, 1) if r["on"] else Color(1, 1, 1, 0.55)
		_ach_list.add_child(line)
	_ach_head.text = head
	ach_panel.visible = true


## The prologue (prologue.js PRO_PAGES): white text on black, page by page; E / Space / a tap goes on,
## 跳过 skips. It runs while the game is paused.
const OPENING := ["你是这学期转来的。", "高二（二）班。第四节，语文。老师在念一篇课文，念到一半，又从头念了一遍。",
	"前排的人回头问你借橡皮。你还没记住他的名字。\n他好像也不记得你的。", "才第三天。这栋楼你只认得三层。\n可是你数过——楼梯一共有五层半。",
	"粉笔灰在光里飘。你开始数秒：一，二，三……数到第七秒的时候，它们停在了半空。", "眼皮很重。黑板上的字开始往下淌，淌成一行一行的竖线。",
	"你把脸埋进胳膊里。袖子上有一股不属于你的味道。", "……", "你睁开眼。\n教室里还是坐满了人。只是没有一个人在呼吸。",
	"窗外的颜色不见了。走廊里很安静，安静得能听见灯管里的电流。", "下课铃没有响。\n你忽然很确定：这不是你转来的那个学校。\n而它，已经知道你醒了。"]
const OPENING_PAGE := 3.4
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


## The low-SAN picture (SensoryRules.view): tunnel, blur, colour drain, warp and black blinks,
## drawn over the world (under the HUD text) with the screen texture.
var _sense: ColorRect


func show_sensory(v: Dictionary, blink: float, t: float) -> void:
	if _sense == null:
		_sense = ColorRect.new()
		_sense.name = "Sensory"
		_sense.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sense.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var shader := Shader.new()
		# engine/three.js: warp (drift, rotation, breathing in), blur and focus, ghost, halo, drain,
		# tunnel (narrowing with the heartbeat, a crawling edge) and black-out, in the old order.
		shader.code = """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float tunnel = 0.0;
uniform float blur = 0.0;
uniform float focus = 0.0;
uniform float drain = 0.0;
uniform float warp = 0.0;
uniform float breath = 0.0;
uniform float pulse = 0.0;
uniform float ghost = 0.0;
uniform vec2 ghost_dir = vec2(1.0, 0.0);
uniform float halo = 0.0;
uniform float blink = 0.0;
uniform float t = 0.0;
void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	vec2 q = c * 2.0;
	float e = length(q);
	if (warp > 0.001) {
		vec2 asp = vec2(res.x / res.y, 1.0);
		vec2 p = c * asp;
		float r = length(p);
		float a = 0.045 * warp * sin(t * 0.31) * cos(t * 0.13 + 1.7);
		p = vec2(p.x * cos(a) - p.y * sin(a), p.x * sin(a) + p.y * cos(a));
		p *= 1.0 - 0.04 * warp * breath;
		vec2 w = vec2(sin(p.y * 6.0 + t * 0.9) + 0.6 * sin((p.x + p.y) * 4.1 - t * 0.7), sin(p.x * 5.2 - t * 0.8) + 0.6 * sin((p.x - p.y) * 3.7 + t * 1.1));
		p += w * 0.0125 * warp * smoothstep(0.03, 0.22, r);
		uv = p / asp + 0.5;
	}
	uv = clamp(uv, vec2(0.001), vec2(0.999));
	float bpx = mix(3.2 * blur * blur, 13.0 * blur, smoothstep(0.15, 0.85, e)) + 4.5 * focus;
	float lod = log2(max(1.0, bpx * min(res.x, res.y) / 720.0 * 0.45));
	vec3 col = textureLod(screen_tex, uv, bpx >= 0.3 ? lod : 0.0).rgb;
	if (ghost > 0.001) {
		vec2 go = ghost_dir * (10.0 * min(res.x, res.y) / 720.0) / res;
		col = mix(col, texture(screen_tex, clamp(uv + go, vec2(0.001), vec2(0.999))).rgb, 0.5 * ghost * smoothstep(0.05, 0.3, e));
	}
	if (halo > 0.001) {
		vec2 asp2 = vec2(res.y / res.x, 1.0);
		vec3 hl = vec3(0.0);
		for (int i = 0; i < 6; i++) {
			float ang = float(i) * 1.0472 + 0.5;
			vec2 o = vec2(cos(ang), sin(ang)) * asp2;
			hl += max(texture(screen_tex, uv + o * 0.012).rgb - 0.62, 0.0);
			hl += max(texture(screen_tex, uv + o * 0.026).rgb - 0.62, 0.0) * 0.6;
		}
		col += min(hl / 6.0 * halo * 0.9, vec3(0.5));
	}
	float g = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(col, vec3(g), 0.7 * drain);
	if (tunnel > 0.001) {
		float crawl = 0.0;
		if (warp > 0.001) {
			float th = atan(q.y, q.x + 0.000001);
			crawl = (0.05 * sin(th * 3.0 + t * 0.6) + 0.035 * sin(th * 5.0 - t * 0.9)) * warp;
		}
		float rr = 1.6 - 1.15 * tunnel - 0.09 * pulse;
		col *= 1.0 - smoothstep(rr - 0.12, rr + 0.42, e + crawl) * min(1.0, tunnel * 2.2) * 0.96;
	}
	col *= 1.0 - blink;
	COLOR = vec4(col, 1.0);
}"""
		var mat := ShaderMaterial.new()
		mat.shader = shader
		_sense.material = mat
		$Root.add_child(_sense)
		$Root.move_child(_sense, 0)
	var on := float(v.get("tunnel", 0.0)) > 0.01 or blink > 0.0 or float(v.get("halo", 0.0)) > 0.01 or float(v.get("ghost_env", 0.0)) > 0.01
	_sense.visible = on
	if not on:
		return
	var m := _sense.material as ShaderMaterial
	m.set_shader_parameter("tunnel", float(v["tunnel"]))
	m.set_shader_parameter("blur", float(v["blur"]))
	m.set_shader_parameter("focus", float(v.get("focus", 0.0)))
	m.set_shader_parameter("drain", float(v["drain"]))
	m.set_shader_parameter("warp", float(v["warp"]))
	m.set_shader_parameter("breath", float(v.get("inhale", 0.0)))
	m.set_shader_parameter("pulse", float(v.get("pulse_env", 0.0)))
	m.set_shader_parameter("ghost", float(v.get("ghost_env", 0.0)))
	var gd: Array = v.get("ghost_dir", [1.0, 0.0])
	m.set_shader_parameter("ghost_dir", Vector2(float(gd[0]), float(gd[1])))
	m.set_shader_parameter("halo", float(v.get("halo", 0.0)))
	m.set_shader_parameter("blink", blink)
	m.set_shader_parameter("t", t)


# ---- settings (settings.js): a panel over the menu or the pause screen ----

const SETTING_ROWS := [
	["声音", "", "", []],
	["vol", "音量", "slider", [0, 100, 5]],
	["amb", "环境声", "choice", [["开", 1], ["关", 0]]],
	["captions", "声音字幕", "choice", [["自动", 0], ["开", 1], ["关", 2]]],
	["sub", "提示文字大小", "choice", [["小", 0], ["中", 1], ["大", 2]]],
	["画面与舒适", "", "", []],
	["distortion", "视野扭曲", "choice", [["关", 0], ["减弱", 1], ["完整", 2]]],
	["reduce_flash", "减少闪光", "choice", [["关", 0], ["开", 1]]],
	["bright", "亮度", "slider", [50, 150, 5]],
	["grain", "胶片颗粒", "choice", [["开", 1], ["关", 0]]],
	["quality", "画质", "choice", [["流畅", 0], ["均衡", 1], ["精细", 2], ["超精细", 3], ["真实", 4]]],
	["操作与文字", "", "", []],
	["mouse", "鼠标灵敏度 %", "slider", [25, 250, 5]],
	["touch", "触屏灵敏度 %", "slider", [25, 250, 5]],
	["text", "文字大小 %", "slider", [85, 150, 5]],
	["touch_size", "触屏按钮大小 %", "slider", [85, 125, 5]],
	["auto_land", "自动横屏（手机）", "choice", [["开", 1], ["关", 0]]],
	["full_screen", "全屏", "choice", [["关", 0], ["开", 1]]],
]
var settings_panel: PanelContainer
var _settings_box: VBoxContainer
var _grain_rect: ColorRect


func show_settings(values: Dictionary) -> void:
	if settings_panel == null:
		settings_panel = PanelContainer.new()
		settings_panel.name = "SettingsPanel"
		settings_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		settings_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		settings_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		settings_panel.custom_minimum_size = Vector2(440, 0)
		var back := StyleBoxFlat.new()
		back.bg_color = Color(0.03, 0.05, 0.07, 0.98)
		back.set_content_margin_all(14)
		back.set_corner_radius_all(6)
		settings_panel.add_theme_stylebox_override("panel", back)
		var outer := VBoxContainer.new()
		outer.add_theme_constant_override("separation", 8)
		var head := Label.new()
		head.text = "设置"
		outer.add_child(head)
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(410, 340)
		_settings_box = VBoxContainer.new()
		_settings_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_settings_box.add_theme_constant_override("separation", 6)
		scroll.add_child(_settings_box)
		outer.add_child(scroll)
		var buttons := HBoxContainer.new()
		var reset := Button.new()
		reset.text = "恢复操作与文字默认"
		reset.pressed.connect(func() -> void: setting_changed.emit("reset_comfort", 0))
		buttons.add_child(reset)
		var close := Button.new()
		close.text = "关闭"
		close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		close.pressed.connect(func() -> void: settings_panel.visible = false)
		buttons.add_child(close)
		outer.add_child(buttons)
		settings_panel.add_child(outer)
		$Root.add_child(settings_panel)
	for child in _settings_box.get_children():
		child.queue_free()
	for row: Array in SETTING_ROWS:
		var key := String(row[0])
		if String(row[2]).is_empty():
			var title := Label.new()
			title.text = "— " + key + " —"
			title.modulate = Color(1, 1, 1, 0.6)
			_settings_box.add_child(title)
			continue
		var line := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = String(row[1])
		name_label.custom_minimum_size = Vector2(150, 0)
		line.add_child(name_label)
		var cur := int(values.get(key, 0))
		if row[2] == "slider":
			var spec: Array = row[3]
			var slider := HSlider.new()
			slider.name = "S_" + key
			slider.min_value = float(spec[0])
			slider.max_value = float(spec[1])
			slider.step = float(spec[2])
			slider.value = cur
			slider.custom_minimum_size = Vector2(170, 24)
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var value_label := Label.new()
			value_label.text = str(cur)
			value_label.custom_minimum_size = Vector2(36, 0)
			slider.value_changed.connect(func(v: float) -> void:
				value_label.text = str(int(v))
				setting_changed.emit(key, int(v)))
			line.add_child(slider)
			line.add_child(value_label)
		else:
			var group := ButtonGroup.new()
			for opt: Array in row[3]:
				var b := Button.new()
				b.name = "O_%s_%d" % [key, int(opt[1])]
				b.text = String(opt[0])
				b.toggle_mode = true
				b.button_group = group
				b.button_pressed = int(opt[1]) == cur
				b.pressed.connect(func() -> void: setting_changed.emit(key, int(opt[1])))
				line.add_child(b)
		_settings_box.add_child(line)
	settings_panel.visible = true


func apply_text_scale(pct: int) -> void:
	var theme := Theme.new()
	theme.default_font_size = roundi(16.0 * float(pct) / 100.0)
	$Root.theme = theme


func apply_touch_scale(pct: int) -> void:
	for c: Control in [%MovePad, %TouchInteract, %TouchSprint]:
		c.pivot_offset = c.size / 2.0
		c.scale = Vector2.ONE * float(pct) / 100.0


## sub: the size of toast and caption lines (SUB_MULT 0.6 / 1.0 / 1.6 in the Web version).
func apply_caption_scale(mult: float) -> void:
	if _captions != null:
		_captions.add_theme_font_size_override("font_size", roundi(15.0 * mult))
	%Toast.add_theme_font_size_override("font_size", roundi(18.0 * mult))


## Film grain over the picture (Engine.grain): faint moving noise.
func set_grain(on: bool) -> void:
	if _grain_rect == null:
		_grain_rect = ColorRect.new()
		_grain_rect.name = "Grain"
		_grain_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_grain_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var shader := Shader.new()
		shader.code = """shader_type canvas_item;
uniform float t = 0.0;
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	float n = h(floor(FRAGCOORD.xy / 2.0) + floor(t * 24.0) * 7.31) - 0.5;
	COLOR = vec4(vec3(n < 0.0 ? 0.0 : 1.0), abs(n) * 0.07);
}"""
		var mat := ShaderMaterial.new()
		mat.shader = shader
		_grain_rect.material = mat
		$Root.add_child(_grain_rect)
		$Root.move_child(_grain_rect, 1)
	_grain_rect.visible = on
	set_process(true)


# ---- the notes page (investigation.js render): the case card, recent finds, the records, route progress ----

var notes_panel: PanelContainer
var _notes_box: VBoxContainer
var _notes_search: LineEdit
const NOTE_COLORS := {"事实": Color(0.78, 0.86, 0.95), "推测": Color(0.95, 0.85, 0.6), "验证": Color(0.65, 0.9, 0.7), "线索": Color(0.88, 0.75, 0.95)}


## data: {goal, focus, routes [[id, name]], recent [rows], groups {kind: rows}, progress [[name, text, done]], found, query}
func show_notes(data: Dictionary) -> void:
	if notes_panel == null:
		notes_panel = PanelContainer.new()
		notes_panel.name = "NotesPanel"
		notes_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		notes_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		notes_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		notes_panel.custom_minimum_size = Vector2(520, 0)
		var back := StyleBoxFlat.new()
		back.bg_color = Color(0.03, 0.05, 0.07, 0.99)
		back.set_content_margin_all(14)
		back.set_corner_radius_all(6)
		notes_panel.add_theme_stylebox_override("panel", back)
		var outer := VBoxContainer.new()
		outer.add_theme_constant_override("separation", 8)
		var head := Label.new()
		head.text = "手册 · 笔记"
		outer.add_child(head)
		_notes_search = LineEdit.new()
		_notes_search.name = "NotesSearch"
		_notes_search.placeholder_text = "搜索记录（事实、地点）"
		_notes_search.text_changed.connect(func(t: String) -> void: notes_requested.emit(t))
		outer.add_child(_notes_search)
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(490, 380)
		_notes_box = VBoxContainer.new()
		_notes_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_notes_box.add_theme_constant_override("separation", 6)
		scroll.add_child(_notes_box)
		outer.add_child(scroll)
		var close := Button.new()
		close.text = "关闭"
		close.pressed.connect(func() -> void: notes_panel.visible = false)
		outer.add_child(close)
		notes_panel.add_child(outer)
		$Root.add_child(notes_panel)
	for child in _notes_box.get_children():
		child.queue_free()
	var query := String(data.get("query", ""))
	if _notes_search.text != query:
		_notes_search.text = query
	_note_label("当前调查" + ("  ·  %s路线" % _route_name(data) if not String(data.get("focus", "")).is_empty() else ""), Color(1, 0.9, 0.55))
	_note_label(String(data["goal"]), Color.WHITE)
	var routes: Array = data["routes"]
	if routes.size() > 1:
		var row := HBoxContainer.new()
		var tag := Label.new()
		tag.text = "关注"
		row.add_child(tag)
		for r: Array in routes:
			var b := Button.new()
			b.name = "Focus_" + String(r[0])
			b.text = String(r[1])
			b.toggle_mode = true
			b.button_pressed = r[0] == data.get("focus", "")
			b.pressed.connect(func() -> void: notes_focus_requested.emit(String(r[0])))
			row.add_child(b)
		_notes_box.add_child(row)
	if not query.is_empty():
		_note_label(("找到 %d 条" % int(data["found"])) if int(data["found"]) > 0 else "没有找到仍能回忆的对应记录。", Color(1, 1, 1, 0.7))
	var recent: Array = data["recent"]
	if not recent.is_empty():
		_note_label("最近发现", Color(1, 0.9, 0.55))
		for e: Dictionary in recent:
			_note_label("[%s] %s" % [e["kind"], e["text"]], NOTE_COLORS[e["kind"]])
	for kind: String in InvestigationModule.KINDS:
		var rows: Array = (data["groups"] as Dictionary).get(kind, [])
		if rows.is_empty():
			continue
		_note_label("%s  %d" % [kind, rows.size()], NOTE_COLORS[kind])
		for e: Dictionary in rows:
			_note_label("  第 %d 天 · %s" % [int(e.get("day", 1)), e["source"]], Color(1, 1, 1, 0.5))
			_note_label("  " + String(e["text"]), Color(1, 1, 1, 0.92))
	var progress: Array = data["progress"]
	if not progress.is_empty():
		_note_label("路线进度", Color(1, 0.9, 0.55))
		for p: Array in progress:
			_note_label("%s %s：%s" % ["✓" if bool(p[2]) else "·", p[0], p[1]], Color(0.65, 0.9, 0.7) if bool(p[2]) else Color.WHITE)
	notes_panel.visible = true


func _route_name(data: Dictionary) -> String:
	for r: Array in data["routes"]:
		if r[0] == data["focus"]:
			return String(r[1])
	return {"car": "车辆", "face": "白名单", "portal": "造门", "cyber": "网安仙人"}.get(String(data["focus"]), "")


func _note_label(text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(480, 0)
	l.modulate = color
	_notes_box.add_child(l)


# ---- the map page: the campus plan or the sketch of a walked floor ----

var map_panel: PanelContainer
var map_view: MapView
var _map_select: OptionButton
var _map_head: Label
var _map_note: Label


## options: [[id, label]] ("campus" is the plan); returns the view to configure.
func open_map(options: Array, selected: String, head: String, note: String) -> MapView:
	if map_panel == null:
		map_panel = PanelContainer.new()
		map_panel.name = "MapPanel"
		map_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		map_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		map_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		var back := StyleBoxFlat.new()
		back.bg_color = Color(0.03, 0.05, 0.07, 0.99)
		back.set_content_margin_all(12)
		back.set_corner_radius_all(6)
		map_panel.add_theme_stylebox_override("panel", back)
		var outer := VBoxContainer.new()
		outer.add_theme_constant_override("separation", 6)
		var top := HBoxContainer.new()
		var lab := Label.new()
		lab.text = "查看"
		top.add_child(lab)
		_map_select = OptionButton.new()
		_map_select.name = "MapSelect"
		_map_select.custom_minimum_size = Vector2(240, 0)
		_map_select.item_selected.connect(func(i: int) -> void: map_requested.emit(String(_map_select.get_item_metadata(i))))
		top.add_child(_map_select)
		outer.add_child(top)
		_map_head = Label.new()
		outer.add_child(_map_head)
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(480, 380)
		map_view = MapView.new()
		map_view.name = "MapView"
		scroll.add_child(map_view)
		outer.add_child(scroll)
		_map_note = Label.new()
		_map_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_map_note.custom_minimum_size = Vector2(480, 0)
		_map_note.modulate = Color(1, 1, 1, 0.6)
		outer.add_child(_map_note)
		var close := Button.new()
		close.text = "关闭"
		close.pressed.connect(func() -> void: map_panel.visible = false)
		outer.add_child(close)
		map_panel.add_child(outer)
		$Root.add_child(map_panel)
	_map_select.clear()
	for o: Array in options:
		_map_select.add_item(String(o[1]))
		_map_select.set_item_metadata(_map_select.item_count - 1, String(o[0]))
		if o[0] == selected:
			_map_select.select(_map_select.item_count - 1)
	_map_head.text = head
	_map_note.text = note
	map_panel.visible = true
	return map_view


func sensory_on() -> bool:
	return _sense != null and _sense.visible


## The lab3 maintenance terminal (TerminalUI): output, a command line, help / hint buttons, exit.
var terminal_panel: PanelContainer
var _term_out: RichTextLabel
var _term_status: Label
var _term_line: LineEdit


func show_terminal(history: String, status: String) -> void:
	if terminal_panel == null:
		terminal_panel = PanelContainer.new()
		terminal_panel.name = "TerminalPanel"
		terminal_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		terminal_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		terminal_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		terminal_panel.custom_minimum_size = Vector2(680, 0)
		var back := StyleBoxFlat.new()
		back.bg_color = Color(0.01, 0.03, 0.02, 0.97)
		back.set_content_margin_all(12)
		terminal_panel.add_theme_stylebox_override("panel", back)
		var box := VBoxContainer.new()
		var head := Label.new()
		head.text = "机房 · 模拟 Linux 终端　（世界仍在运行。留意脚步与灯光；Esc 退出）"
		box.add_child(head)
		_term_status = Label.new()
		_term_status.modulate = Color(0.6, 0.95, 0.7)
		box.add_child(_term_status)
		_term_out = RichTextLabel.new()
		_term_out.custom_minimum_size = Vector2(650, 320)
		_term_out.scroll_following = true
		_term_out.selection_enabled = true
		_term_out.add_theme_color_override("default_color", Color(0.75, 1.0, 0.8))
		box.add_child(_term_out)
		var row := HBoxContainer.new()
		_term_line = LineEdit.new()
		_term_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_term_line.placeholder_text = "help"
		_term_line.max_length = 4096
		_term_line.text_submitted.connect(func(t: String) -> void:
			terminal_command.emit(t)
			_term_line.text = ""
			_term_line.grab_focus())
		row.add_child(_term_line)
		for pair: Array in [["执行", ""], ["帮助", "help"], ["线索位置", "campusctl hint 1"], ["关联方法", "campusctl hint 2"], ["退出", "__exit"]]:
			var b := Button.new()
			b.text = pair[0]
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
		$Root.add_child(terminal_panel)
	_term_out.text = history
	_term_status.text = status
	if not terminal_panel.visible:
		terminal_panel.visible = true
		_term_line.grab_focus()


func hide_terminal() -> void:
	if terminal_panel != null:
		terminal_panel.visible = false


func terminal_open() -> bool:
	return terminal_panel != null and terminal_panel.visible


## Ending card (story.js showEndingCard): tag, title, lines, day/time, back to the menu.
var ending_panel: PanelContainer
var _ending_text: Label


func show_ending(title: String, tag: String, lines: Array, meta: String) -> void:
	if ending_panel == null:
		ending_panel = PanelContainer.new()
		ending_panel.name = "EndingPanel"
		ending_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		ending_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		ending_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		ending_panel.custom_minimum_size = Vector2(520, 0)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 14)
		_ending_text = Label.new()
		_ending_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_ending_text.custom_minimum_size = Vector2(480, 0)
		_ending_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(_ending_text)
		var back := Button.new()
		back.text = "回到主菜单"
		back.pressed.connect(func() -> void: death_menu_requested.emit())
		box.add_child(back)
		ending_panel.add_child(box)
		$Root.add_child(ending_panel)
	var head := "%s\n%s" % [tag, title] if not tag.is_empty() else title
	_ending_text.text = "%s\n\n%s\n\n%s" % [head, "\n".join(PackedStringArray(lines)), meta]
	ending_panel.visible = true


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


func show_choice(text: String, labels: Array, cancellable: bool = true) -> void:
	_choice_cancellable = cancellable
	for child in _choice_box.get_children():
		child.queue_free()
	_choice_text.text = text
	for i in labels.size():
		var b := Button.new()
		b.text = "%d. %s" % [i + 1, labels[i]]
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.pressed.connect(choice_selected.emit.bind(i))
		_choice_box.add_child(b)
	if cancellable:
		var cancel := Button.new()
		cancel.text = "算了"
		cancel.pressed.connect(choice_selected.emit.bind(-1))
		_choice_box.add_child(cancel)
	choice_panel.visible = true
	_choice_refit = false
	_fit_choice()


## Long lists (the talent pick) scroll inside the panel instead of running off a phone screen.
func _fit_choice() -> void:
	var view := get_viewport().get_visible_rect().size
	choice_panel.custom_minimum_size.x = minf(560.0, view.x - 32.0)
	_choice_text.custom_minimum_size.x = choice_panel.custom_minimum_size.x - 24.0
	var want := 0.0
	for child in _choice_box.get_children():
		if not child.is_queued_for_deletion():
			want += (child as Control).get_combined_minimum_size().y + 4.0
	var room := maxf(120.0, view.y * 0.86 - _choice_text.get_combined_minimum_size().y - 40.0)
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


## Wrapped labels know their height only after a layout pass: fit once more then.
func _refit_choice_later() -> void:
	await get_tree().process_frame
	_choice_refit = true
	if choice_panel.visible:
		_fit_choice()
	_choice_refit = false


func hide_choice() -> void:
	choice_panel.visible = false


func choice_open() -> bool:
	return choice_panel != null and choice_panel.visible


func set_lift_close(visible_now: bool) -> void:
	if lift_close_button.visible != visible_now:
		lift_close_button.visible = visible_now


func _unhandled_key_input(event: InputEvent) -> void:
	if not choice_open() or not event is InputEventKey or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).physical_keycode
	if key >= KEY_1 and key <= KEY_9:
		var index := key - KEY_1
		if index < _choice_box.get_child_count() - (1 if _choice_cancellable else 0):
			choice_selected.emit(index)
			get_viewport().set_input_as_handled()
	elif key == KEY_ESCAPE and _choice_cancellable:
		choice_selected.emit(-1)
		get_viewport().set_input_as_handled()


func set_touch_enabled(value: bool) -> void:
	_touch_enabled = value
	%TouchToggle.set_pressed_no_signal(value)
	touch_controls.visible = value and _mode == "play"
	clear_touch()


func touch_enabled() -> bool:
	return _touch_enabled


func clear_touch() -> void:
	stick.clear()
	look_pad.clear()
	%TouchSprint.set_pressed_no_signal(false)
	touch_sprint.emit(false)


func set_mode(mode: String) -> void:
	if _mode != mode:
		show_notice("")
	_mode = mode
	if ach_panel != null:
		ach_panel.visible = false
	if mode != "play":
		hide_terminal()
	menu.visible = mode == "menu"
	pause_panel.visible = mode == "pause"
	hud.visible = mode == "play"
	touch_controls.visible = mode == "play" and _touch_enabled
	clear_touch()
	if mode == "menu":
		%NewGame.grab_focus()
	elif mode == "pause":
		%Resume.grab_focus()
	else:
		var focused := get_viewport().gui_get_focus_owner()
		if focused != null:
			focused.release_focus()


func set_save_available(available: bool) -> void:
	%LoadGame.disabled = not available
	%Reload.disabled = not available


func show_notice(text: String) -> void:
	%Toast.text = text
	%Toast.visible = not text.is_empty()
	_toast_seconds = 6.0


func toast_text() -> String:
	return %Toast.text


func show_prompt(text: String) -> void:
	%Prompt.text = ("交互 · " if _touch_enabled else "E · ") + text if not text.is_empty() else ""


var _location := "移植测试场景"
var _status_line: Label
var _stamina: ProgressBar
var _status_on := false
var bag_panel: PanelContainer
var _bag_list: VBoxContainer
var _search_ring: ProgressBar
var _hot_label: Label


func show_location(text: String) -> void:
	_location = text


## The speedrun clock replaces the runtime line while a speedrun is on.
var speedrun_text := ""


func show_runtime(seconds: float) -> void:
	if speedrun_text != "":
		%Runtime.text = "%s · 速通 %s" % [_location, speedrun_text]
		return
	%Runtime.text = _location if _status_on else "%s · 运行 %ds" % [_location, int(seconds)]
