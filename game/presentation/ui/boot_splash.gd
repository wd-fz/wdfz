class_name BootSplash
extends Control
## The animation when the app opens, before the menu: black and breathing grain; a blood crack opens down
## the left edge where the menu spine will stand; the title and school surface out of blur and noise over a
## heartbeat glow; then the black bleeds away from the crack and leaves the menu with its folded tag.
## Any key, click or touch skips (a short fade). With reduced flashing it is only a calm 1.2 s title fade.
## While it plays the menu's live campus loads in the background (GameUI starts MenuPreview.begin_load).

signal finished(skipped: bool)
signal cue(id: String)

const SHADER := preload("res://game/presentation/ui/boot_splash.gdshader")
const REVEAL := preload("res://game/presentation/ui/text_reveal.gdshader")
## Timeline (seconds).
@export var crack_at := 0.45
@export var crack_time := 0.9
@export var title_at := 1.15
@export var school_at := 1.65
@export var reveal_time := 0.8
@export var bleed_at := 2.85
@export var bleed_time := 0.9
@export var skip_time := 0.28
@export var reduced_total := 1.2
var reduce_motion := false
var spine_x := 14.0

var _t := 0.0
var _skip_t := -1.0
var _done := false
var _mat: ShaderMaterial
var _back: ColorRect
var _title: Label
var _school: Label
var _beat_sent := false


func _init() -> void:
	name = "BootSplash"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	focus_mode = Control.FOCUS_ALL


func _ready() -> void:
	_back = ColorRect.new()
	_back.name = "BootBack"
	_back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("u_noise", SideMenu.noise_texture())
	_back.material = _mat
	add_child(_back)
	var column := VBoxContainer.new()
	column.name = "BootTitle"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	column.anchor_left = 0.32
	column.anchor_right = 0.32
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(column)
	_title = Label.new()
	_title.name = "BootGameTitle"
	_title.text = "里世界"
	_title.theme_type_variation = "HeadingLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_color", Color(0.92, 0.84, 0.8))
	_title.add_theme_color_override("font_shadow_color", Color(0.5, 0.02, 0.02, 0.85))
	_title.add_theme_constant_override("shadow_offset_x", 0)
	_title.add_theme_constant_override("shadow_offset_y", 0)
	_title.add_theme_constant_override("shadow_outline_size", 10)
	column.add_child(_title)
	_school = Label.new()
	_school.name = "BootSchool"
	_school.text = "武汉大学附属中学"
	_school.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_school.add_theme_color_override("font_color", Color(0.62, 0.55, 0.52))
	column.add_child(_school)
	for label: Label in [_title, _school]:
		var m := ShaderMaterial.new()
		m.shader = REVEAL
		m.set_shader_parameter("u_reveal", 0.0)
		label.material = m
	resized.connect(_fit)
	_fit()
	_apply(0.0)
	grab_focus.call_deferred()


func _fit() -> void:
	var h := size.y if size.y > 0.0 else 540.0
	var font_k := get_theme_default_font_size() / 16.0
	_title.add_theme_font_size_override("font_size", roundi(h * 0.12 * font_k))
	_school.add_theme_font_size_override("font_size", roundi(h * 0.034 * font_k))
	_mat.set_shader_parameter("u_size", size)


func elapsed() -> float:
	return _t


func total() -> float:
	return reduced_total if reduce_motion else bleed_at + bleed_time


func skip() -> void:
	if _done or _skip_t >= 0.0:
		return
	_skip_t = 0.0


func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton or event is InputEventScreenTouch) and event.is_pressed():
		skip()
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if (event is InputEventKey or event is InputEventJoypadButton) and event.is_pressed() and not event.is_echo():
		skip()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if _skip_t >= 0.0:
		_skip_t += delta
		modulate.a = clampf(1.0 - _skip_t / skip_time, 0.0, 1.0)
		if _skip_t >= skip_time:
			_finish(true)
		return
	_apply(delta)
	if _t >= total():
		_finish(false)


func _apply(_delta: float) -> void:
	_mat.set_shader_parameter("u_t", _t)
	_mat.set_shader_parameter("u_spine_x", spine_x)
	_mat.set_shader_parameter("u_motion", 0.0 if reduce_motion else 1.0)
	if reduce_motion:
		# Calm: title fades in and the whole card fades out; no crack, no flicker.
		var k := clampf(_t / (reduced_total * 0.35), 0.0, 1.0)
		var out := clampf((_t - reduced_total * 0.65) / (reduced_total * 0.35), 0.0, 1.0)
		for label: Label in [_title, _school]:
			(label.material as ShaderMaterial).set_shader_parameter("u_reveal", 1.0)
			label.modulate.a = k
		_mat.set_shader_parameter("u_crack", 0.0)
		_mat.set_shader_parameter("u_glow", 0.0)
		_mat.set_shader_parameter("u_bleed", 0.0)
		modulate.a = 1.0 - out
		return
	_mat.set_shader_parameter("u_crack", ease(clampf((_t - crack_at) / crack_time, 0.0, 1.0), 0.4))
	var beat := SideMenu.heartbeat(maxf(0.0, _t - title_at)) if _t > title_at else 0.0
	_mat.set_shader_parameter("u_glow", beat * clampf((_t - title_at) / 0.4, 0.0, 1.0) * (1.0 - clampf((_t - bleed_at) / bleed_time, 0.0, 1.0)))
	if _t >= title_at and not _beat_sent:
		_beat_sent = true
		cue.emit("threat.heartLow")
	(_title.material as ShaderMaterial).set_shader_parameter("u_reveal", clampf((_t - title_at) / reveal_time, 0.0, 1.0))
	(_title.material as ShaderMaterial).set_shader_parameter("u_time", _t)
	(_school.material as ShaderMaterial).set_shader_parameter("u_reveal", clampf((_t - school_at) / reveal_time, 0.0, 1.0))
	(_school.material as ShaderMaterial).set_shader_parameter("u_time", _t)
	var bleed := clampf((_t - bleed_at) / bleed_time, 0.0, 1.0)
	_mat.set_shader_parameter("u_bleed", bleed)
	var fade := 1.0 - clampf((bleed - 0.2) / 0.5, 0.0, 1.0)
	_title.modulate.a = fade
	_school.modulate.a = fade


func _finish(skipped: bool) -> void:
	_done = true
	finished.emit(skipped)
	queue_free()
