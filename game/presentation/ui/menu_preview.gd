class_name MenuPreview
extends SubViewportContainer
## The live game view behind the main menu: the real outdoor campus at dusk (19:10, windows lit), seen by a
## camera that circles the lawn in front of the teaching building slowly (the old menu photo's place). Rendered in its own SubViewport/World3D at
## reduced resolution; the outdoor model loads on a background thread (begin_load, usually during the boot
## animation) and the whole preview is freed when the menu is left, so it never costs anything in play.
## Headless runs and missing models keep the static menu photo underneath.

@export var clock := 1150.0             # 19:10 in minutes: last blue light, windows already lit
@export var orbit_seconds := 150.0      # one full circle
@export var radius := 17.0
@export var height := 6.5
@export var look_height := 4.5
@export var shrink := 2                 # render at 1/shrink resolution (the menu veils it anyway)

var viewport: SubViewport
var world: CampusWorld
var camera: Camera3D
var still := false                      # reduced motion: hold one angle
var angle := -0.6
var _path := ""
var _requested := false
var _center := Vector3.ZERO
var _fade := 0.0
var render_options: Dictionary = {}


func _init() -> void:
	name = "MenuPreview"
	stretch = true
	stretch_shrink = shrink
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


static func supported() -> bool:
	return DisplayServer.get_name() != "headless"


## Start loading the outdoor model in the background (safe to call more than once).
func begin_load() -> void:
	if _requested or not supported():
		return
	_path = CampusData.scene_path("out")
	_requested = ResourceLoader.load_threaded_request(_path, "PackedScene", true) == OK


func ready_to_show() -> bool:
	return is_instance_valid(world)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if not is_instance_valid(world):
		if not _requested:
			begin_load()
		if _requested and ResourceLoader.load_threaded_get_status(_path) == ResourceLoader.THREAD_LOAD_LOADED:
			_build()
		return
	if not still:
		angle += TAU * delta / maxf(10.0, orbit_seconds)
	_place_camera()
	world.update_lighting(delta, clock, camera)
	_fade = minf(1.0, _fade + delta * 0.6)
	modulate.a = _fade


func _build() -> void:
	ResourceLoader.load_threaded_get(_path)    # now cached; CampusWorld loads it from the cache
	viewport = SubViewport.new()
	viewport.name = "PreviewViewport"
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	world = (load("res://game/presentation/world/campus/campus_world.tscn") as PackedScene).instantiate() as CampusWorld
	world.scene_id = "out"
	world.render_options = render_options
	viewport.add_child(world)
	camera = Camera3D.new()
	camera.name = "OrbitCamera"
	camera.fov = 62.0
	camera.far = 600.0
	viewport.add_child(camera)
	camera.current = true
	# The heart of the campus: between the lab building and the teaching building (bounds of the layout).
	_center = orbit_center(CampusData.layout("out"))
	_place_camera()


static func orbit_center(layout: Dictionary) -> Vector3:
	var spot := DayBanner.spot(layout)
	return Vector3(spot.x, 0.0, spot.z + 19.0)


func _place_camera() -> void:
	var eye := _center + Vector3(cos(angle) * radius, height + sin(angle * 0.5) * 3.0, sin(angle) * radius)
	camera.position = eye
	# Look across the middle of the circle, a little past the centre, so the far side fills the frame.
	var across := _center - Vector3(cos(angle), 0.0, sin(angle)) * radius * 0.35
	camera.look_at(across + Vector3(0.0, look_height, 0.0), Vector3.UP)


## Leaving the menu: drop the whole world so play never pays for the preview.
func release() -> void:
	if is_instance_valid(viewport):
		remove_child(viewport)
		viewport.queue_free()
	viewport = null
	world = null
	camera = null
	_fade = 0.0
	modulate.a = 0.0
