class_name MenuPreview
extends ColorRect
## The campus behind the main menu: a 360° panorama of the real outdoor campus in the 18:00 evening fog,
## from the courtyard between the teaching and lab buildings, panned slowly round (re-baked 2026-11-13).
##
## User request 2026-11-12: the orbit is a picture panned round, not a live render. The panorama is baked once
## from the real scene by tools/capture/capture_menu_panorama.gd (assets/ui/menu_panorama.jpg); at run time
## nothing 3D is loaded or drawn, only this one textured rectangle.
##
## Off by default (user request 2026-11-11, power): the setting 主菜单实景环绕 (menu_orbit) turns it on; off,
## the menu shows the still picture underneath and this panel holds no texture.

const PANORAMA := "res://assets/ui/menu_panorama.jpg"
const CLOCK := 1080.0                   # 18:00 in minutes: the time the panorama was baked at
## Where it was baked from (outdoor scene metres): the middle of the courtyard between the lab building
## (north) and the teaching building (south), a little above eye height.
const EYE := Vector3(118.0, 2.2, 181.0)
const SHADER := """
shader_type canvas_item;
uniform sampler2D pano : source_color, filter_linear, repeat_enable;
uniform float yaw = 0.0;      // the view's centre, as a fraction of the full circle
uniform float span = 0.28;    // how much of the circle the width shows
uniform float tall = 0.85;    // how much of the panorama's height the height shows
uniform float centre = 0.5;   // where the view sits vertically in the panorama
uniform float black = 0.12;   // levels: the baked fog is a low-contrast grey (median ~28%), stretched here
uniform float white = 0.52;
uniform float gamma = 1.3;
uniform float zoom = 1.0;     // > 1 during the menu's entrance push-in
void fragment() {
	vec2 uv = (UV - .5) / zoom;
	vec3 c = texture(pano, vec2(yaw + uv.x * span, centre + uv.y * tall)).rgb;
	c = pow(clamp((c - black) / max(0.01, white - black), 0.0, 1.0), vec3(gamma));
	// The stretch widens the JPEG's sky steps into bands; a little ordered noise hides them.
	float n = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	COLOR = vec4(c + n * 3.0 / 255.0, 1.0);
}
"""

@export var orbit_seconds := 150.0      # one full turn
@export var tall := 0.85                # fraction of the panorama's height on screen; the width follows the aspect
@export var centre := 0.52              # a little below the middle: more campus, less sky
## Levels (user request 2026-11-13: the panorama was too dark to see). The baked fog sits between ~22% and
## ~35% grey; this stretches it to readable brick, glass and track while the fog stays heavy.
@export var black_level := 0.12
@export var white_level := 0.52
@export var gamma := 1.3
## The menu's entrance (MenuWake) pushes the view in from this scale to 1.
@export var entrance_zoom := 1.18
var zoom := 1.0

## Emitted when how much of the panorama shows changes (0 = none, 1 = fully faded in): the side menu
## lightens its veil over a visible panorama.
signal shown_changed(amount: float)

var still := false                      # reduced motion: hold one angle
## Only the launched app turns the panorama on (GameApp, together with the boot animation); embedded apps in
## tests and tools keep the static photo.
var enabled := false
## The player's setting (menu_orbit). Both this and enabled are needed before anything is shown.
var orbit := false
var angle := 0.25                       # turns: looking west down the courtyard into the fog at the start
var texture: Texture2D
var render_options: Dictionary = {}     # kept for callers; the baked picture does not depend on them
var _fade := 0.0


func _init() -> void:
	name = "MenuPreview"
	color = Color.BLACK
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## A display is not needed any more (a picture works everywhere); kept for callers and tests.
static func supported() -> bool:
	return ResourceLoader.exists(PANORAMA)


## Load the panorama (small and synchronous; safe to call more than once).
func begin_load() -> void:
	if not enabled or not orbit or texture != null or not supported():
		return
	texture = load(PANORAMA)
	var shader := Shader.new()
	shader.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("pano", texture)
	material = mat
	_layout()


## Turn the panorama on or off (settings); off releases the picture at once.
func set_orbit(on: bool) -> void:
	orbit = on
	if not on:
		release()
	elif is_visible_in_tree():
		begin_load()


func ready_to_show() -> bool:
	return texture != null


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED: _layout()


## The width shows as much of the circle as the screen's aspect allows at the chosen height.
func _layout() -> void:
	if material == null or texture == null or size.y <= 0: return
	var m := material as ShaderMaterial
	m.set_shader_parameter("tall", tall)
	m.set_shader_parameter("centre", centre)
	m.set_shader_parameter("black", black_level)
	m.set_shader_parameter("white", white_level)
	m.set_shader_parameter("gamma", gamma)
	m.set_shader_parameter("span", tall * texture.get_height() * size.x / (size.y * texture.get_width()))


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if texture == null:
		begin_load()
		return
	if not still:
		angle = fposmod(angle + delta / maxf(10.0, orbit_seconds), 1.0)
	(material as ShaderMaterial).set_shader_parameter("yaw", angle)
	(material as ShaderMaterial).set_shader_parameter("zoom", zoom)
	var was := _fade
	_fade = minf(1.0, _fade + delta * 0.6)
	modulate.a = _fade
	if _fade != was:
		shown_changed.emit(_fade)


## How much of the panorama shows now (0–1).
func shown() -> float:
	return _fade if texture != null else 0.0


## Leaving the menu or switching off: drop the picture so play never holds it.
func release() -> void:
	var was := _fade
	material = null
	texture = null
	_fade = 0.0
	modulate.a = 0.0
	if was > 0.0:
		shown_changed.emit(0.0)
