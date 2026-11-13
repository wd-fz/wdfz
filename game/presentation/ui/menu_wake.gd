class_name MenuWake
extends ColorRect
## The main menu's entrance (user request 2026-11-13): the campus behind the menu is seen as if waking up.
## Two dark eyelids part, blink once half-open, then open fully while the view sharpens out of a dark
## blur and the panorama eases back from a slight push-in. It sits above the menu picture/panorama and below
## the side menu (whose panel tears open at the same time), takes no input, and frees itself at the end.
## Reduced flashing / motion: a calm fade from black, no blink and no push-in.

signal finished

const SHADER := """
shader_type canvas_item;
uniform float open = 0.0;     // 0 lids shut … 1 fully open
uniform float dark = 1.0;     // extra darkness over the whole view (the eye adjusting)
uniform float aspect = 1.78;
void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	// The lids meet along a gentle almond: the opening is widest in the middle, closed at the corners.
	float lid = open * (0.78 - 0.18 * p.x * p.x / (aspect * aspect * 0.25)) - 0.08 * (1.0 - open);
	float edge = abs(p.y) - lid;
	float shut = smoothstep(-0.10, 0.04, edge);
	float vig = smoothstep(0.25, 1.05, length(p / vec2(aspect * 0.55, 0.62)));
	float a = clamp(max(shut, dark) + vig * (1.0 - open) * 0.6, 0.0, 1.0);
	COLOR = vec4(0.0, 0.0, 0.0, a);
}
"""

## Timeline (seconds).
@export var blink_open_at := 0.35       # the first crack of light
@export var blink_peak := 0.75          # half open …
@export var blink_shut := 1.0           # … and shut again
@export var open_time := 2.4            # fully open
@export var reduced_time := 0.8
@export var blink_amount := 0.38
var reduce_motion := false
## The panorama to push in (optional; the still photo has nothing to move).
var preview: MenuPreview

var _t := 0.0
var _mat: ShaderMaterial
var _done := false


func _init() -> void:
	name = "MenuWake"
	color = Color.BLACK
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	var shader := Shader.new()
	shader.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	material = _mat
	_apply()


func total() -> float:
	return reduced_time if reduce_motion else open_time


func elapsed() -> float:
	return _t


## Openness of the lids at time t (0 shut … 1 open): crack, half-open blink, shut, then open with ease-out.
func openness(t: float) -> float:
	if reduce_motion:
		return 1.0
	if t < blink_open_at:
		return 0.0
	if t < blink_peak:
		return blink_amount * ease((t - blink_open_at) / (blink_peak - blink_open_at), 0.5)
	if t < blink_shut:
		return blink_amount * (1.0 - ease((t - blink_peak) / (blink_shut - blink_peak), 2.0)) * 0.85
	return 1.0 - pow(1.0 - clampf((t - blink_shut) / (open_time - blink_shut), 0.0, 1.0), 3.0)


## Darkness laid over everything (the eye adjusting to the dusk).
func darkness(t: float) -> float:
	if reduce_motion:
		return 1.0 - clampf(t / reduced_time, 0.0, 1.0)
	return 0.6 * (1.0 - smoothstep(blink_open_at, open_time, t))


func finish() -> void:
	if _done:
		return
	_done = true
	if is_instance_valid(preview):
		preview.zoom = 1.0
	finished.emit()
	queue_free()


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	_apply()
	if _t >= total():
		finish()


func _apply() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("open", openness(_t))
	_mat.set_shader_parameter("dark", darkness(_t))
	_mat.set_shader_parameter("aspect", size.x / size.y if size.y > 0.0 else 1.78)
	if is_instance_valid(preview):
		var k := clampf(_t / total(), 0.0, 1.0)
		preview.zoom = 1.0 if reduce_motion else lerpf(preview.entrance_zoom, 1.0, 1.0 - pow(1.0 - k, 3.0))
