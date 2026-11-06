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

@onready var menu: Control = %Menu
@onready var pause_panel: Control = %PausePanel
@onready var hud: Control = %HUD
@onready var touch_controls: Control = %TouchControls
@onready var stick: TouchStick = %MovePad
@onready var look_pad: TouchLook = %LookPad

var _mode := "menu"
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
