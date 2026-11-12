class_name MenuPreview
extends SubViewportContainer
## The live game view behind the main menu: the real outdoor campus at dusk (19:10, windows lit), seen by a
## camera that circles the lawn in front of the teaching building slowly (the old menu photo's place). Rendered in its own SubViewport/World3D at
## reduced resolution; the outdoor model loads on a background thread (begin_load, usually during the boot
## animation) and the whole preview is freed when the menu is left, so it never costs anything in play.
## Headless runs and missing models keep the static menu photo underneath.
##
## Off by default (user request 2026-11-11, power): the setting 主菜单实景环绕 (menu_orbit) turns it on; off,
## nothing 3D is loaded or rendered and the menu shows the still picture.

@export var clock := 1150.0             # 19:10 in minutes: last blue light, windows already lit
@export var orbit_seconds := 150.0      # one full circle
@export var radius := 17.0
@export var height := 6.5
@export var look_height := 4.5
@export var shrink := 2                 # render at 1/shrink resolution (the menu veils it anyway)
@export var render_fps := 20.0          # the 3D view redraws at most this often (a slow orbit needs little)

var viewport: SubViewport
var world: CampusWorld
var camera: Camera3D
var still := false                      # reduced motion: hold one angle
## Only the launched app turns the live view on (GameApp, together with the boot animation); embedded apps in
## tests and tools keep the static photo, so no background load ever races their own scene loads.
var enabled := false
## The player's setting (menu_orbit). Both this and enabled are needed before anything loads.
var orbit := false
var angle := -0.6
var _path := ""
var _requested := false                # a threaded load is outstanding (not yet taken with load_threaded_get)
var _center := Vector3.ZERO
var _fade := 0.0
var render_options: Dictionary = {}
var _since_render := 0.0


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
	if _requested or not enabled or not orbit or not supported() or is_instance_valid(world):
		return
	_path = CampusData.scene_path("out")
	_requested = ResourceLoader.load_threaded_request(_path, "PackedScene", true) == OK


## Turn the live view on or off (settings); off releases everything at once.
func set_orbit(on: bool) -> void:
	orbit = on
	if not on:
		release()
	elif is_visible_in_tree():
		begin_load()


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
	_since_render += delta
	if _since_render < 1.0 / maxf(1.0, render_fps):
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	var step := _since_render
	_since_render = 0.0
	if not still:
		angle += TAU * step / maxf(10.0, orbit_seconds)
	_place_camera()
	world.update_lighting(step, clock, camera)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_fade = minf(1.0, _fade + step * 0.6)
	modulate.a = _fade


func _build() -> void:
	_finish_load()    # take the result: the scene is cached and CampusWorld loads it from the cache
	viewport = SubViewport.new()
	viewport.name = "PreviewViewport"
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
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
	# The lawn in front of the teaching building (the old menu photo's place).
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


## Every threaded request is collected exactly once; a request left open while the game loads the same
## scene synchronously makes the worker pool wait on a finished task ("Invalid Task ID").
func _finish_load() -> void:
	if _requested:
		ResourceLoader.load_threaded_get(_path)
		_requested = false


## Leaving the menu: drop the whole world so play never pays for the preview. An outstanding background
## load is collected first (it usually finished during the boot animation; otherwise this waits for it).
func release() -> void:
	_finish_load()
	if is_instance_valid(viewport):
		remove_child(viewport)
		viewport.queue_free()
	viewport = null
	world = null
	camera = null
	_fade = 0.0
	modulate.a = 0.0
