class_name LoadingScreen
extends Control
## The screen between choosing a talent (or continuing) and the run (user request 2026-11-13: confirming a
## talent used to freeze the window while the campus loaded). Black, a slow heartbeat glow, the title with
## breathing dots, one quiet line, and a thin blood-red progress line. GameApp loads the scene's models on
## worker threads and reports progress here; the last step (building the scene) runs on the main thread,
## so the screen is drawn first with its text saying so. It fades out over the start of the run.
## Takes all input while shown, so nothing behind it can be pressed twice.

const LINES: PackedStringArray = [
	"教室的灯还亮着。",
	"闭上眼睛，铃声就在耳边。",
	"走廊比记忆里更长一点。",
	"窗外的天色停在了傍晚。",
]

@export var fade_in := 0.25
@export var fade_out := 0.45

var progress := 0.0                 # 0–1 as reported
var shown_progress := 0.0           # eased towards progress
var stage := ""
var reduce_motion := false          # reduced flashing: the glow holds still
var _t := 0.0
var _out_t := -1.0
var _title: Label
var _line: Label
var _stage: Label
var _bar_back: ColorRect
var _bar: ColorRect
var _glow: ColorRect


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
uniform float beat = 0.0;
uniform float aspect = 1.78;
void fragment() {
	vec2 p = (UV - vec2(0.5, 0.56)) * vec2(aspect, 1.0);
	float g = exp(-dot(p, p) * 5.0) * (0.10 + 0.22 * beat);
	COLOR = vec4(0.42, 0.03, 0.03, g);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_glow.material = mat
	add_child(_glow)
	var column := VBoxContainer.new()
	column.name = "LoadingColumn"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(column)
	_title = Label.new()
	_title.name = "LoadingTitle"
	_title.theme_type_variation = "HeadingLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_color", Color(0.9, 0.82, 0.78))
	column.add_child(_title)
	_line = Label.new()
	_line.name = "LoadingLine"
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.add_theme_color_override("font_color", Color(0.58, 0.52, 0.5))
	_line.text = LINES[randi() % LINES.size()]
	column.add_child(_line)
	var gap := Control.new()
	gap.name = "LoadingGap"
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(gap)
	var bar_row := CenterContainer.new()
	bar_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(bar_row)
	_bar_back = ColorRect.new()
	_bar_back.name = "LoadingBarBack"
	_bar_back.color = Color(0.16, 0.12, 0.12, 0.8)
	_bar_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_row.add_child(_bar_back)
	_bar = ColorRect.new()
	_bar.name = "LoadingBar"
	_bar.color = Color(0.62, 0.07, 0.06)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_back.add_child(_bar)
	_stage = Label.new()
	_stage.name = "LoadingStage"
	_stage.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage.add_theme_color_override("font_color", Color(0.45, 0.4, 0.4))
	column.add_child(_stage)
	resized.connect(_fit)
	_fit()
	_apply()
	grab_focus.call_deferred()


func _fit() -> void:
	var h := size.y if size.y > 0.0 else 540.0
	var w := size.x if size.x > 0.0 else 960.0
	var k := get_theme_default_font_size() / 16.0
	_title.add_theme_font_size_override("font_size", roundi(h * 0.07 * k))
	_line.add_theme_font_size_override("font_size", roundi(h * 0.03 * k))
	_stage.add_theme_font_size_override("font_size", roundi(h * 0.024 * k))
	(get_node("LoadingColumn/LoadingGap") as Control).custom_minimum_size.y = h * 0.05
	_bar_back.custom_minimum_size = Vector2(minf(w * 0.4, h * 0.9), maxf(2.0, h * 0.005))
	(_glow.material as ShaderMaterial).set_shader_parameter("aspect", w / h)


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


func _apply() -> void:
	if _title == null:
		return
	_title.text = "正在入梦" + ".".repeat(int(_t * 2.5) % 4)
	_stage.text = stage
	_bar.size = Vector2(_bar_back.custom_minimum_size.x * shown_progress, _bar_back.custom_minimum_size.y)
	var beat := 0.3 if reduce_motion else SideMenu.heartbeat(_t)
	(_glow.material as ShaderMaterial).set_shader_parameter("beat", beat)
