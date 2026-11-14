class_name LoadingScreen
extends Control
## The screen between choosing a talent (or continuing) and the run (user request 2026-11-13: confirming a
## talent used to freeze the window while the campus loaded; restyled 2026-11-14). A dark wall in slow fog
## with grain and a heavy vignette; the classroom clock from the boot animation (school_clock.gdshader)
## in the middle, its minute hand creeping from 17:00 towards 18:00 with the progress while the red second
## hand ticks; under it the title with breathing dots, a quiet line that changes every few seconds, and a
## thin blood-red progress line with an ember at its head, the current step on the left and the percentage
## on the right. GameApp loads the scene's models on worker threads and reports progress here; the last
## step (building the scene) runs on the main thread, so the screen is drawn first with its text saying so.
## It fades out over the start of the run. Takes all input while shown, so nothing behind it can be pressed
## twice. Reduced flashing: no heartbeat pulse, no warp and no ember flicker; the fog still drifts slowly.

const CLOCK := preload("res://game/presentation/ui/school_clock.gdshader")
const LINES: PackedStringArray = [
	"教室的灯还亮着。",
	"闭上眼睛，铃声就在耳边。",
	"走廊比记忆里更长一点。",
	"窗外的天色停在了傍晚。",
	"黑板上的字，好像不是你写的。",
	"有人在楼梯口数台阶。",
	"值日表上多了一个名字。",
	"广播里的沙沙声，一直没有停。",
]
## Seconds each line stays, and its crossfade.
const LINE_TIME := 4.5
const LINE_FADE := 0.6

@export var fade_in := 0.3
@export var fade_out := 0.5

var progress := 0.0                 # 0–1 as reported
var shown_progress := 0.0           # eased towards progress
var stage := ""
var reduce_motion := false          # reduced flashing: the glow holds still
var _t := 0.0
var _out_t := -1.0
var _line_index := 0
var _title: Label
var _line: Label
var _stage: Label
var _percent: Label
var _bar_back: ColorRect
var _bar: ColorRect
var _glow: ColorRect
var _clock: ColorRect


func _init() -> void:
	name = "LoadingScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	focus_mode = Control.FOCUS_ALL
	modulate.a = 0.0


func _ready() -> void:
	var back := ColorRect.new()
	back.name = "LoadingBack"
	back.color = Color(0.008, 0.006, 0.008)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	_glow = ColorRect.new()
	_glow.name = "LoadingGlow"
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
// Fog drifting over a dark wall, a heartbeat glow behind the clock, grain and a heavy vignette.
uniform sampler2D u_noise : repeat_enable, filter_linear;
uniform float beat = 0.0;
uniform float aspect = 1.78;
uniform float t = 0.0;
uniform float motion = 1.0;
uniform vec2 centre = vec2(0.5, 0.36);
float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
void fragment() {
	vec2 q = UV * vec2(aspect, 1.0);
	float fog = texture(u_noise, q * 0.35 + vec2(t * 0.012, t * 0.004)).r * 0.6
		+ texture(u_noise, q * 0.8 - vec2(t * 0.02, -t * 0.006)).r * 0.4;
	vec3 col = vec3(0.012, 0.011, 0.012) + vec3(0.07, 0.068, 0.066) * smoothstep(0.42, 0.85, fog);
	vec2 p = (UV - centre) * vec2(aspect, 1.0);
	float g = exp(-dot(p, p) * 4.0);
	col += vec3(0.42, 0.03, 0.03) * g * (0.12 + 0.26 * beat);
	col += vec3(0.05, 0.055, 0.05) * exp(-dot(p, p) * 9.0);
	col += vec3(0.018, 0.012, 0.012) * hash(floor(FRAGCOORD.xy / 2.0) + floor(t * 18.0) * motion);
	vec2 v = (UV - 0.5) * vec2(aspect, 1.0);
	col *= 1.0 - smoothstep(0.3, 1.0, length(v)) * 0.8;
	COLOR = vec4(col, 1.0);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("u_noise", SideMenu.noise_texture())
	_glow.material = mat
	add_child(_glow)
	var column := VBoxContainer.new()
	column.name = "LoadingColumn"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(column)
	var clock_row := CenterContainer.new()
	clock_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(clock_row)
	_clock = ColorRect.new()
	_clock.name = "LoadingClock"
	_clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var clock_mat := ShaderMaterial.new()
	clock_mat.shader = CLOCK
	clock_mat.set_shader_parameter("u_light", 0.78)
	_clock.material = clock_mat
	clock_row.add_child(_clock)
	var clock_gap := Control.new()
	clock_gap.name = "LoadingClockGap"
	clock_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(clock_gap)
	_title = Label.new()
	_title.name = "LoadingTitle"
	_title.theme_type_variation = "HeadingLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_color", Color(0.9, 0.84, 0.8))
	_title.add_theme_color_override("font_shadow_color", Color(0.45, 0.02, 0.02, 0.55))
	_title.add_theme_constant_override("shadow_offset_x", 0)
	_title.add_theme_constant_override("shadow_offset_y", 0)
	_title.add_theme_constant_override("shadow_outline_size", 5)
	column.add_child(_title)
	_line = Label.new()
	_line.name = "LoadingLine"
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.add_theme_color_override("font_color", Color(0.6, 0.55, 0.53))
	_line_index = randi() % LINES.size()
	_line.text = LINES[_line_index]
	column.add_child(_line)
	var gap := Control.new()
	gap.name = "LoadingGap"
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(gap)
	var bar_row := CenterContainer.new()
	bar_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(bar_row)
	var bar_column := VBoxContainer.new()
	bar_column.name = "LoadingBarColumn"
	bar_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_column.add_theme_constant_override("separation", 6)
	bar_row.add_child(bar_column)
	# The track is taller than the line so the ember's glow has room; the bar shader draws both.
	_bar_back = ColorRect.new()
	_bar_back.name = "LoadingBarBack"
	_bar_back.color = Color(1, 1, 1, 1)
	_bar_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar_shader := Shader.new()
	bar_shader.code = """
shader_type canvas_item;
// A thin blood line on a faint track; its head is a glowing ember that wavers.
uniform float amount = 0.0;
uniform float t = 0.0;
uniform float motion = 1.0;
uniform float line = 0.18;      // line thickness as a fraction of the rect's height
uniform vec2 size = vec2(400.0, 14.0);
void fragment() {
	float y = abs(UV.y - 0.5) * 2.0;
	float px = UV.x * size.x;
	float head = amount * size.x;
	float core = 1.0 - smoothstep(line, line + 0.12, y);
	vec3 col = vec3(0.0);
	float a = 0.0;
	// Track: a faint dotted chalk line.
	float dots = step(0.45, fract(px / 6.0));
	a = max(a, core * 0.22 * dots * step(head, px));
	col = mix(col, vec3(0.32, 0.27, 0.26), core * step(head, px));
	// Filled: dark to brighter red towards the head.
	float filled = step(px, head);
	vec3 fill = mix(vec3(0.32, 0.03, 0.03), vec3(0.78, 0.09, 0.07), smoothstep(head - size.x * 0.35, head, px));
	col = mix(col, fill, core * filled);
	a = max(a, core * filled);
	// Ember: a hot point with a glow that spills above and below the line.
	float flick = 1.0 + motion * 0.18 * sin(t * 23.0) * sin(t * 7.3);
	float d = length(vec2((px - head) / size.y, (UV.y - 0.5) * 1.0));
	float ember = exp(-d * d * 18.0) * flick * step(0.001, amount);
	col += vec3(1.0, 0.45, 0.25) * ember;
	a = max(a, clamp(ember, 0.0, 1.0));
	COLOR = vec4(col, a);
}
"""
	var bar_mat := ShaderMaterial.new()
	bar_mat.shader = bar_shader
	_bar_back.material = bar_mat
	bar_column.add_child(_bar_back)
	# Kept as a plain rect the size of the filled part, for code and tests that read the bar's length.
	_bar = ColorRect.new()
	_bar.name = "LoadingBar"
	_bar.color = Color(0, 0, 0, 0)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_back.add_child(_bar)
	var info := HBoxContainer.new()
	info.name = "LoadingInfo"
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_column.add_child(info)
	_stage = Label.new()
	_stage.name = "LoadingStage"
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage.add_theme_color_override("font_color", Color(0.48, 0.43, 0.42))
	info.add_child(_stage)
	_percent = Label.new()
	_percent.name = "LoadingPercent"
	_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_percent.add_theme_color_override("font_color", Color(0.62, 0.2, 0.18))
	info.add_child(_percent)
	resized.connect(_fit)
	_fit()
	_apply()
	grab_focus.call_deferred()


func _fit() -> void:
	var h := size.y if size.y > 0.0 else 540.0
	var w := size.x if size.x > 0.0 else 960.0
	var k := get_theme_default_font_size() / 16.0
	_title.add_theme_font_size_override("font_size", roundi(h * 0.06 * k))
	_line.add_theme_font_size_override("font_size", roundi(h * 0.028 * k))
	_stage.add_theme_font_size_override("font_size", roundi(h * 0.022 * k))
	_percent.add_theme_font_size_override("font_size", roundi(h * 0.022 * k))
	var side := roundf(h * 0.22)
	_clock.custom_minimum_size = Vector2(side, side)
	(get_node("LoadingColumn/LoadingClockGap") as Control).custom_minimum_size.y = h * 0.035
	(get_node("LoadingColumn/LoadingGap") as Control).custom_minimum_size.y = h * 0.045
	var bar := Vector2(minf(w * 0.42, h * 0.95), maxf(10.0, roundf(h * 0.022)))
	_bar_back.custom_minimum_size = bar
	(_bar_back.material as ShaderMaterial).set_shader_parameter("size", bar)
	(_bar_back.material as ShaderMaterial).set_shader_parameter("line", clampf(3.0 / bar.y, 0.08, 0.4))
	var mat := _glow.material as ShaderMaterial
	mat.set_shader_parameter("aspect", w / h)
	# The clock's centre, for the glow behind it (the column is centred, so estimate from its layout).
	var column := get_node("LoadingColumn") as Control
	var top := (h - column.get_combined_minimum_size().y) * 0.5
	mat.set_shader_parameter("centre", Vector2(0.5, clampf((top + side * 0.5) / h, 0.1, 0.9)))


## Progress 0–1 and, optionally, what is happening now.
func set_progress(amount: float, what: String = "") -> void:
	progress = clampf(maxf(progress, amount), 0.0, 1.0)
	if not what.is_empty():
		stage = what
	_apply()


## Fade out over what comes next, then free.
func close() -> void:
	if _out_t < 0.0:
		_out_t = 0.0
		mouse_filter = Control.MOUSE_FILTER_IGNORE


func closing() -> bool:
	return _out_t >= 0.0


func _gui_input(event: InputEvent) -> void:
	accept_event()


func _process(delta: float) -> void:
	# A heavy main-thread step can stall one frame for a long time: do not let it jump the animation.
	var step := minf(delta, 0.1)
	_t += step
	shown_progress = move_toward(shown_progress, progress, step * 1.6)
	if _out_t >= 0.0:
		_out_t += step
		modulate.a = clampf(1.0 - _out_t / fade_out, 0.0, 1.0)
		if _out_t >= fade_out:
			queue_free()
			return
	else:
		modulate.a = clampf(_t / fade_in, 0.0, 1.0) if fade_in > 0.0 else 1.0
	_apply()


## Which line shows at time t, and its opacity (crossfading through black between lines).
func line_at(t: float) -> Array:
	var turn := int(t / LINE_TIME)
	var into := t - turn * LINE_TIME
	var alpha := clampf(into / LINE_FADE, 0.0, 1.0) * clampf((LINE_TIME - into) / LINE_FADE, 0.0, 1.0)
	if turn == 0:
		alpha = clampf((LINE_TIME - into) / LINE_FADE, 0.0, 1.0)
	return [(_line_index + turn) % LINES.size(), alpha]


func _apply() -> void:
	if _title == null:
		return
	_title.text = "正在入梦" + ".".repeat(int(_t * 2.5) % 4)
	_stage.text = stage
	_percent.text = "%d%%" % roundi(shown_progress * 100.0)
	var line: Array = line_at(_t)
	_line.text = LINES[int(line[0])]
	_line.modulate.a = float(line[1])
	_bar.size = Vector2(_bar_back.custom_minimum_size.x * shown_progress, _bar_back.custom_minimum_size.y)
	var bar_mat := _bar_back.material as ShaderMaterial
	bar_mat.set_shader_parameter("amount", shown_progress)
	bar_mat.set_shader_parameter("t", _t)
	bar_mat.set_shader_parameter("motion", 0.0 if reduce_motion else 1.0)
	var beat := 0.3 if reduce_motion else SideMenu.heartbeat(_t)
	var mat := _glow.material as ShaderMaterial
	mat.set_shader_parameter("beat", beat)
	mat.set_shader_parameter("t", _t)
	mat.set_shader_parameter("motion", 0.0 if reduce_motion else 1.0)
	# The clock: 17:00 → 18:00 with the progress; the second hand ticks once a second.
	var clock := _clock.material as ShaderMaterial
	var minute := shown_progress * 60.0
	clock.set_shader_parameter("u_minute_hand", minute)
	clock.set_shader_parameter("u_minutes", 1020.0 + minute)
	var tick := floorf(_t)
	var since := _t - tick
	var wobble := 0.0 if reduce_motion else 0.15 * exp(-since * 30.0) * sin(since * 70.0)
	clock.set_shader_parameter("u_second", fposmod(tick * 1.0 + 7.0, 60.0) + wobble)
	clock.set_shader_parameter("u_time", _t)
