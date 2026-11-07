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
	box.add_child(_choice_box)
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
	_death_fade.color = Color(0.1, 0.0, 0.0, 0.0)
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


func show_death_fade(alpha: float) -> void:
	_death_fade.color.a = clampf(alpha, 0.0, 0.92)


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
	_death_fade.color.a = 0.0


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
		b.pressed.connect(choice_selected.emit.bind(i))
		_choice_box.add_child(b)
	if cancellable:
		var cancel := Button.new()
		cancel.text = "算了"
		cancel.pressed.connect(choice_selected.emit.bind(-1))
		_choice_box.add_child(cancel)
	choice_panel.visible = true


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
