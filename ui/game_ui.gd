class_name GameUI
extends CanvasLayer

signal new_requested
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
	set_touch_enabled(DisplayServer.is_touchscreen_available())
	get_tree().root.size_changed.connect(_resize)
	_resize()
	set_mode("menu")


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed and not _touch_enabled:
		set_touch_enabled(true)


func _process(delta: float) -> void:
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


func show_choice(text: String, labels: Array) -> void:
	for child in _choice_box.get_children():
		child.queue_free()
	_choice_text.text = text
	for i in labels.size():
		var b := Button.new()
		b.text = "%d. %s" % [i + 1, labels[i]]
		b.pressed.connect(choice_selected.emit.bind(i))
		_choice_box.add_child(b)
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
		if index < _choice_box.get_child_count() - 1:
			choice_selected.emit(index)
			get_viewport().set_input_as_handled()
	elif key == KEY_ESCAPE:
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


func show_location(text: String) -> void:
	_location = text


func show_runtime(seconds: float) -> void:
	%Runtime.text = "%s · 运行 %ds" % [_location, int(seconds)]
