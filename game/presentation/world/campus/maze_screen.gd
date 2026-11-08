class_name MazeScreen
extends CanvasLayer
## World-only compositing. This layer precedes the HUD, captions and touch controls.

var material_fx: ShaderMaterial
var pane: ColorRect
var _copy: BackBufferCopy


func _ready() -> void:
	layer = -1
	# ScenePost has already graded the 3D scene. Explicitly refresh the screen
	# copy here; without it a second screen shader reads the ungraded buffer.
	_copy = BackBufferCopy.new()
	_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(_copy)
	_copy.hide()
	pane = ColorRect.new()
	pane.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float invert_k = 0.0;
uniform float invert_hole = -0.2;
uniform float glow_k = 0.0;
uniform float glow_hole = -0.22;
uniform float fade_k = 0.0;
uniform vec4 glow_color : source_color = vec4(0.93,0.96,1.0,1.0);
void fragment() {
    vec3 src = texture(screen_tex, SCREEN_UV).rgb;
    float radius = length((SCREEN_UV - vec2(0.5)) * 1.41421356);
    float ik = invert_k * smoothstep(invert_hole, invert_hole + 0.18, radius);
    vec3 c = mix(src, vec3(1.0) - src, ik);
    float gk = glow_k * smoothstep(glow_hole, glow_hole + 0.22, radius);
    c = vec3(1.0) - (vec3(1.0) - c) * (vec3(1.0) - glow_color.rgb * gk);
    COLOR = vec4(c * (1.0 - fade_k), 1.0);
}
"""
	material_fx = ShaderMaterial.new()
	material_fx.shader = shader
	pane.material = material_fx
	add_child(pane)
	pane.hide()


func show_effect(inversion: float = 0.0, hole: float = -0.2, glow: float = 0.0, glow_hole: float = -0.22, fade: float = 0.0) -> void:
	material_fx.set_shader_parameter("invert_k", inversion)
	material_fx.set_shader_parameter("invert_hole", hole)
	material_fx.set_shader_parameter("glow_k", glow)
	material_fx.set_shader_parameter("glow_hole", glow_hole)
	material_fx.set_shader_parameter("fade_k", fade)
	pane.visible = inversion > 0.001 or glow > 0.001 or fade > 0.001
	_copy.visible = pane.visible
