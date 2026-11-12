class_name MenuPreview
extends ColorRect
## The campus behind the main menu: a 360° panorama of the real outdoor campus at dusk (19:10, windows lit,
## from the lawn in front of the teaching building, the old menu photo's place), panned slowly round.
##
## User request 2026-11-12: the orbit is a picture panned round, not a live render. The panorama is baked once
## from the real scene by tools/capture/capture_menu_panorama.gd (assets/ui/menu_panorama.jpg); at run time
## nothing 3D is loaded or drawn, only this one textured rectangle.
##
## Off by default (user request 2026-11-11, power): the setting 主菜单实景环绕 (menu_orbit) turns it on; off,
## the menu shows the still picture underneath and this panel holds no texture.

const PANORAMA := "res://assets/ui/menu_panorama.jpg"
const CLOCK := 1150.0                   # 19:10 in minutes: the time the panorama was baked at
## The 2026-11-11 live orbit's spot: the lawn in front of the teaching building (the panorama's eye point).
const SHADER := """
shader_type canvas_item;
uniform sampler2D pano : source_color, filter_linear, repeat_enable;
uniform float yaw = 0.0;      // the view's centre, as a fraction of the full circle
uniform float span = 0.28;    // how much of the circle the width shows
uniform float tall = 0.85;    // how much of the panorama's height the height shows
uniform float centre = 0.5;   // where the view sits vertically in the panorama
void fragment() {
	COLOR = vec4(texture(pano, vec2(yaw + (UV.x - .5) * span, centre + (UV.y - .5) * tall)).rgb, 1.0);
}
"""

@export var orbit_seconds := 150.0      # one full turn
@export var tall := 0.85                # fraction of the panorama's height on screen; the width follows the aspect
@export var centre := 0.52              # a little below the middle: more campus, less sky

var still := false                      # reduced motion: hold one angle
## Only the launched app turns the panorama on (GameApp, together with the boot animation); embedded apps in
## tests and tools keep the static photo.
var enabled := false
## The player's setting (menu_orbit). Both this and enabled are needed before anything is shown.
var orbit := false
var angle := 0.5                        # turns: the teaching building in the middle of the view at the start
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
	_fade = minf(1.0, _fade + delta * 0.6)
	modulate.a = _fade


## Kept for callers: the panorama's eye point, the lawn in front of the teaching building.
static func orbit_center(layout: Dictionary) -> Vector3:
	var spot := DayBanner.spot(layout)
	return Vector3(spot.x, 0.0, spot.z + 19.0)


## Leaving the menu or switching off: drop the picture so play never holds it.
func release() -> void:
	material = null
	texture = null
	_fade = 0.0
	modulate.a = 0.0
