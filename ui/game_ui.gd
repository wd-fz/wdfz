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
signal achievements_requested
signal archive_requested
signal terminal_command(line: String)
signal terminal_closed
signal sound_toggled(on: bool)

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
	touch_toggle.reparent(option_row, false)
	option_row.add_child(sound)
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
		for spec: Array in [["使用", -1], ["放到快捷栏 1", 0], ["放到快捷栏 2", 1]]:
			var b := Button.new()
			b.text = spec[0]
			if spec[1] < 0:
				b.pressed.connect(item_use_requested.emit.bind(id))
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


func show_runtime(seconds: float) -> void:
	%Runtime.text = _location if _status_on else "%s · 运行 %ds" % [_location, int(seconds)]
