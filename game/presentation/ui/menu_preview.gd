class_name MenuPreview
extends TextureRect
signal load_failed
## The campus behind the main menu: a 360° panorama of the real outdoor campus in the 18:00 evening fog,
## from the courtyard between the teaching and lab buildings, panned slowly round (re-baked 2026-11-13).
##
## User request 2026-11-12: the orbit is a picture panned round, not a live render. The panorama is baked once
## from the real scene by tools/capture/capture_menu_panorama.gd (assets/ui/menu_panorama.jpg); at run time
## nothing 3D is loaded or drawn, only this one textured rectangle.
##
## 主菜单实景环绕 (menu_orbit) selects this view. The rainy campus cover is used when it is off.

const PANORAMA := "res://assets/ui/menu_panorama.jpg"
const CLOCK := 1080.0                   # 18:00 in minutes: the time the panorama was baked at
## Where it was baked from (outdoor scene metres): the middle of the courtyard between the lab building
## (north) and the teaching building (south), a little above eye height.
const EYE := Vector3(118.0, 2.2, 181.0)
const SHADER := """
shader_type canvas_item;
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
	vec3 c = texture(TEXTURE, vec2(fract(yaw + uv.x * span), centre + uv.y * tall)).rgb;
	c = pow(clamp((c - black) / max(0.01, white - black), 0.0, 1.0), vec3(gamma));
	// The stretch widens the JPEG's sky steps into bands; a little ordered noise hides them.
	float n = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	vec3 grade = c * vec3(0.74, 0.89, 1.04) + vec3(0.014, 0.024, 0.044);
	COLOR = vec4(grade + n * 3.0 / 255.0, COLOR.a);
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

var still := false                      # reduced motion: hold one angle
## The panorama follows the player’s setting even when the startup animation is skipped.
var orbit := false
var angle := 0.25                       # turns: looking west down the courtyard into the fog at the start
var _attempted := false
var render_options: Dictionary = {}     # kept for callers; the baked picture does not depend on them
var _fade := 0.0


func _init() -> void:
	name = "MenuPreview"
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## A display is not needed any more (a picture works everywhere); kept for callers and tests.
static func supported() -> bool:
	return FileAccess.file_exists(PANORAMA + ".source") or ResourceLoader.exists(PANORAMA)


## Load the panorama (small and synchronous; safe to call more than once).
func begin_load() -> void:
	if not orbit or _attempted:
		return
	_attempted = true
	if FileAccess.file_exists(PANORAMA + ".source"):
		var picture := Image.new()
		if picture.load_jpg_from_buffer(FileAccess.get_file_as_bytes(PANORAMA + ".source")) == OK:
			texture = ImageTexture.create_from_image(picture)
	if texture == null:
		texture = load(PANORAMA) as Texture2D
	if texture == null:
		set_orbit(false)
		CampusEntryLog.resource_issue("校园全景图读取失败 · " + PANORAMA)
		load_failed.emit()
		return
	var shader := Shader.new()
	shader.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("yaw", angle)
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
		return
	if not still:
		angle = fposmod(angle + delta / maxf(10.0, orbit_seconds), 1.0)
	(material as ShaderMaterial).set_shader_parameter("yaw", angle)
	(material as ShaderMaterial).set_shader_parameter("zoom", zoom)
	_fade = minf(1.0, _fade + delta * 0.6)
	modulate.a = _fade


## Leaving the menu or switching off: drop the picture so play never holds it.
func release() -> void:
	_attempted = false
	material = null
	texture = null
	_fade = 0.0
	modulate.a = 0.0
