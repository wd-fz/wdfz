class_name BootSplash
extends Control
## The animation when the app opens, before the menu (redesigned 2026-11-14, user request).
## A dark classroom wall at the end of the day: a fluorescent tube starter-flickers on and lights a wall clock
## under it; the red second hand ticks the last seconds to 18:00 and the minute hand drops onto twelve;
## the title and the school surface out of blur under a heartbeat glow; then the second hand ticks one step
## back, the face reddens, and the tube dies — leaving black, which the menu's eyelids (menu_wake.gd) open
## from. Any key, click or touch skips (a short fade to black). With reduced flashing there is no flicker,
## no backward tick and no warp: the light fades up on the clock at 18:00, the title fades in, then out.
## GameUI calls MenuPreview.begin_load when it starts (the menu's panorama, when the setting is on).

signal finished(skipped: bool)
signal cue(id: String)

const SHADER := preload("res://game/presentation/ui/boot_splash.gdshader")
const CLOCK := preload("res://game/presentation/ui/school_clock.gdshader")
const REVEAL := preload("res://game/presentation/ui/text_reveal.gdshader")
## 17:59 in minutes since noon; the hour hand rests just short of six.
const START_MINUTES := 1079.0
const START_SECOND := 52.0
## Timeline (seconds).
@export var light_at := 0.25        # the tube's starter clicks
@export var tick_from := 0.95       # the first visible tick of the second hand
@export var tick_step := 0.15       # time per tick (the last seconds hurry)
@export var title_at := 1.35
@export var school_at := 1.8
@export var reveal_time := 0.8
@export var back_tick_at := 2.5     # the second hand slips one step back
@export var die_at := 2.9           # the tube starts to die
@export var die_time := 0.3
@export var black_hold := 0.4       # black before the menu's eyes open
@export var skip_time := 0.28
@export var reduced_total := 1.4
var reduce_motion := false

var _t := 0.0
var _skip_t := -1.0
var _done := false
var _mat: ShaderMaterial
var _clock_mat: ShaderMaterial
var _back: ColorRect
var _clock: ColorRect
var _veil: ColorRect
var _column: VBoxContainer
var _title: Label
var _school: Label
var _sent := {}


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
	_clock = ColorRect.new()
	_clock.name = "BootClock"
	_clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock_mat = ShaderMaterial.new()
	_clock_mat.shader = CLOCK
	_clock.material = _clock_mat
	add_child(_clock)
	_column = VBoxContainer.new()
	_column.name = "BootTitle"
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(_column)
	_title = Label.new()
	_title.name = "BootGameTitle"
	_title.text = "里世界"
	_title.theme_type_variation = "HeadingLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_color", Color(0.92, 0.86, 0.8))
	_title.add_theme_color_override("font_shadow_color", Color(0.45, 0.02, 0.02, 0.6))
	_title.add_theme_constant_override("shadow_offset_x", 0)
	_title.add_theme_constant_override("shadow_offset_y", 0)
	_title.add_theme_constant_override("shadow_outline_size", 6)
	_column.add_child(_title)
	_school = Label.new()
	_school.name = "BootSchool"
	_school.text = "武汉大学附属中学"
	_school.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_school.add_theme_color_override("font_color", Color(0.62, 0.56, 0.52))
	_column.add_child(_school)
	for label: Label in [_title, _school]:
		var m := ShaderMaterial.new()
		m.shader = REVEAL
		m.set_shader_parameter("u_reveal", 0.0)
		label.material = m
	# Skipping fades to black (not to the menu): the menu's eyelids open from black either way.
	_veil = ColorRect.new()
	_veil.name = "BootVeil"
	_veil.color = Color(0.0, 0.0, 0.0, 0.0)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_veil)
	resized.connect(_fit)
	_fit()
	_apply()
	grab_focus.call_deferred()


func _fit() -> void:
	var h := size.y if size.y > 0.0 else 540.0
	var w := size.x if size.x > 0.0 else 960.0
	var font_k := get_theme_default_font_size() / 16.0
	_title.add_theme_font_size_override("font_size", roundi(h * 0.11 * font_k))
	_school.add_theme_font_size_override("font_size", roundi(h * 0.032 * font_k))
	_school.add_theme_constant_override("line_spacing", 0)
	var side := roundf(h * 0.34)
	_clock.size = Vector2(side, side)
	_clock.position = Vector2(roundf(w * 0.5 - side * 0.5), roundf(h * 0.205))
	_column.position = Vector2(0.0, roundf(h * 0.585))
	_column.size = Vector2(w, h * 0.3)
	_mat.set_shader_parameter("u_size", Vector2(w, h))
	_mat.set_shader_parameter("u_tube", Vector2(0.5, 0.1))
	_mat.set_shader_parameter("u_tube_w", h * 0.2 / w)
	_mat.set_shader_parameter("u_glow_at", Vector2(0.5, 0.67))


func elapsed() -> float:
	return _t


func total() -> float:
	return reduced_total if reduce_motion else die_at + die_time + black_hold


func skip() -> void:
	if _done or _skip_t >= 0.0:
		return
	_skip_t = 0.0


## The tube's output at time t (0–1): starter flicker, steady hum, dying flicker, off.
func light(t: float) -> float:
	if reduce_motion:
		var up := clampf(t / (reduced_total * 0.3), 0.0, 1.0)
		var down := clampf((t - reduced_total * 0.6) / (reduced_total * 0.3), 0.0, 1.0)
		return up * (1.0 - down) * 0.85
	if t < light_at:
		return 0.0
	if t >= die_at:
		var y := t - die_at
		var k := y / die_time
		if k < 0.2: return 0.3
		if k < 0.4: return 1.0
		if k < 0.65: return 0.0
		if k < 0.8: return 0.55
		return 0.0
	var x := t - light_at
	if x < 0.05: return 1.0
	if x < 0.16: return 0.0
	if x < 0.2: return 0.8
	if x < 0.3: return 0.08
	if x < 0.65: return lerpf(0.35, 1.0, smoothstep(0.3, 0.65, x))
	return 0.96 + 0.04 * sin(t * 37.0)


## The second hand at time t (0–60, 60 is twelve), with a small overshoot on each tick.
func second_hand(t: float) -> float:
	if reduce_motion:
		return 60.0
	if t < tick_from:
		return START_SECOND
	var ticks := mini(int((t - tick_from) / tick_step) + 1, int(60.0 - START_SECOND))
	var s := START_SECOND + ticks
	var since := t - tick_from - (ticks - 1) * tick_step
	if t >= back_tick_at:
		s = 59.0
		since = t - back_tick_at
	return s + 0.18 * exp(-since * 30.0) * sin(since * 70.0)


## True once the clock reads 18:00 (the minute hand has dropped onto twelve).
func at_six(t: float) -> bool:
	return reduce_motion or t >= tick_from + (60.0 - START_SECOND - 1.0) * tick_step


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
		_veil.color.a = clampf(_skip_t / skip_time, 0.0, 1.0)
		if _skip_t >= skip_time:
			_finish(true)
		return
	_apply()
	if _t >= total():
		_finish(false)


func _send(id: String, at: float) -> void:
	var key := "%s@%.3f" % [id, at]
	if _t >= at and not _sent.has(key):
		_sent[key] = true
		cue.emit(id)


func _apply() -> void:
	var lit := light(_t)
	_mat.set_shader_parameter("u_t", _t)
	_mat.set_shader_parameter("u_light", lit)
	_mat.set_shader_parameter("u_motion", 0.0 if reduce_motion else 1.0)
	_clock_mat.set_shader_parameter("u_time", _t)
	_clock_mat.set_shader_parameter("u_second", second_hand(_t))
	var six := at_six(_t)
	_clock_mat.set_shader_parameter("u_minute_hand", 60.0 if six else 59.0)
	_clock_mat.set_shader_parameter("u_minutes", START_MINUTES + (1.0 if six else 0.0))
	# The clock is lit by the tube; a little of it stays readable in the dark gaps of the flicker.
	_clock_mat.set_shader_parameter("u_light", 0.08 + 0.92 * lit if _t >= light_at or reduce_motion else 0.0)
	var dread := 0.0 if reduce_motion else clampf((_t - back_tick_at) / 0.3, 0.0, 1.0)
	_clock_mat.set_shader_parameter("u_dread", dread)
	if reduce_motion:
		var k := clampf(_t / (reduced_total * 0.35), 0.0, 1.0)
		var out := clampf((_t - reduced_total * 0.6) / (reduced_total * 0.3), 0.0, 1.0)
		for label: Label in [_title, _school]:
			(label.material as ShaderMaterial).set_shader_parameter("u_reveal", 1.0)
			label.modulate.a = k * (1.0 - out)
		_mat.set_shader_parameter("u_glow", 0.0)
		_mat.set_shader_parameter("u_after", 0.0)
		_veil.color.a = clampf((_t - reduced_total * 0.85) / (reduced_total * 0.15), 0.0, 1.0)
		return
	_send("world.lampFlicker", light_at)
	_send("threat.heartLow", title_at)
	_send("dread.knock", back_tick_at)
	_send("world.lampFlicker", die_at)
	var dead := _t >= die_at + die_time
	_mat.set_shader_parameter("u_after", 0.8 * (1.0 - clampf((_t - die_at - die_time) / 0.35, 0.0, 1.0)) if dead else 0.0)
	var beat := SideMenu.heartbeat(maxf(0.0, _t - title_at)) if _t > title_at else 0.0
	_mat.set_shader_parameter("u_glow", beat * clampf((_t - title_at) / 0.4, 0.0, 1.0) * (1.0 - clampf((_t - die_at) / die_time, 0.0, 1.0)))
	(_title.material as ShaderMaterial).set_shader_parameter("u_reveal", clampf((_t - title_at) / reveal_time, 0.0, 1.0))
	(_title.material as ShaderMaterial).set_shader_parameter("u_time", _t)
	(_school.material as ShaderMaterial).set_shader_parameter("u_reveal", clampf((_t - school_at) / reveal_time, 0.0, 1.0))
	(_school.material as ShaderMaterial).set_shader_parameter("u_time", _t)
	# When the tube dies the school line goes with the light; the title lingers as a red afterimage.
	var gone := clampf((_t - die_at) / die_time, 0.0, 1.0)
	_school.modulate.a = 1.0 - gone
	var after := clampf((_t - die_at - die_time) / maxf(black_hold, 0.01), 0.0, 1.0)
	_title.modulate = Color(1.0, lerpf(1.0, 0.25, gone), lerpf(1.0, 0.22, gone), (1.0 - after) * lerpf(1.0, 0.55, gone))
	_clock.modulate.a = 1.0 if not dead else maxf(0.0, 1.0 - after * 2.0)


func _finish(skipped: bool) -> void:
	_done = true
	finished.emit(skipped)
	queue_free()
