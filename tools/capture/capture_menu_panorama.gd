extends SceneTree
## Bakes the main menu's panorama (assets/ui/menu_panorama.jpg): the real outdoor campus at 18:00, when the
## evening fog is thick and warm, seen from the courtyard between the teaching building and the lab
## building (both façades close on either side, the fog swallowing the open ends), rendered from one eye
## point in eight overlapping 90° views and resampled into a 360° cylindrical strip.
## 2026-11-13 (user: the old picture was too dark and not good-looking): replaced the 19:10 view from 11 m
## above the lawn in front of the teaching building, a flat grey curve of one façade.
## The menu then only pans across this picture (MenuPreview); nothing 3D runs behind the menu.
## xvfb-run -a godot --windowed --path . --rendering-driver vulkan --script res://tools/capture/capture_menu_panorama.gd
## Output: assets/ui/menu_panorama.jpg (re-import afterwards) and build/previews/panorama/view-<k>.png.

const VIEWS := 8                 # yaw steps; each view is 90° wide, the nearest one serves a column
const VIEW_SIZE := 1280
const WIDTH := 4096              # the full circle
const TOP := 0.85                # tan of the highest elevation kept (the façades are close: keep their tops)
const BOTTOM := -0.42            # tan of the lowest
const QUALITY := 4               # the top preset: the picture is baked once, its cost is not paid at run time

var viewport: SubViewport
var camera: Camera3D
var world: CampusWorld


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(640, 360)
	DirAccess.make_dir_recursive_absolute("res://build/previews/panorama")
	CampusData.tier = QUALITY
	viewport = SubViewport.new()
	viewport.size = Vector2i(VIEW_SIZE, VIEW_SIZE)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	world = (load("res://game/presentation/world/campus/campus_world.tscn") as PackedScene).instantiate() as CampusWorld
	world.scene_id = "out"
	world.render_options = GraphicsProfile.preset(QUALITY)
	viewport.add_child(world)
	camera = Camera3D.new()
	camera.fov = 90.0
	camera.far = 800.0
	viewport.add_child(camera)
	camera.current = true
	var eye := MenuPreview.EYE
	var shots: Array[Image] = []
	for k in VIEWS:
		_aim(eye, _yaw(k))
		# Let the lights, fog and shadow cascades settle on this view before keeping it.
		for _i in 24:
			world.update_lighting(1.0 / 60.0, MenuPreview.CLOCK, camera)
			await process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		image.convert(Image.FORMAT_RGB8)
		image.save_png("res://build/previews/panorama/view-%d.png" % k)
		shots.append(image)
		print("VIEW: %d" % k)
	var height := int(round(WIDTH / TAU * (TOP - BOTTOM)))
	var pano := Image.create(WIDTH, height, false, Image.FORMAT_RGB8)
	for x in WIDTH:
		var phi := TAU * (x + .5) / WIDTH
		var k := posmod(int(round(phi / (TAU / VIEWS))), VIEWS)
		_aim(eye, _yaw(k))
		var dir := _dir(phi)
		# Along one column the view's x is fixed and its y moves linearly with the cylinder's height.
		var a := camera.unproject_position(eye + dir)
		var b := camera.unproject_position(eye + dir + Vector3.UP)
		for y in height:
			var t := lerpf(TOP, BOTTOM, (y + .5) / height)
			var at := a.lerp(b, t)
			pano.set_pixel(x, y, _sample(shots[k], at))
	pano.save_jpg("res://assets/ui/menu_panorama.jpg", .9)
	print("PANORAMA: %dx%d" % [WIDTH, height])
	world.queue_free()
	await process_frame
	quit()


func _yaw(k: int) -> float:
	return k * TAU / VIEWS


## The horizontal direction at angle a. Facing +z, a camera's right is -x, so the angle grows towards -x:
## the panorama then runs to the viewer's right as its x grows (not mirrored).
static func _dir(a: float) -> Vector3:
	return Vector3(-sin(a), 0, cos(a))


func _aim(eye: Vector3, yaw: float) -> void:
	camera.position = eye
	camera.look_at(eye + _dir(yaw), Vector3.UP)


## Bilinear sample in view pixels (the viewport's size is the image's).
func _sample(image: Image, at: Vector2) -> Color:
	var x := clampf(at.x - .5, 0, image.get_width() - 1.001)
	var y := clampf(at.y - .5, 0, image.get_height() - 1.001)
	var x0 := int(x)
	var y0 := int(y)
	var fx := x - x0
	var fy := y - y0
	var top := image.get_pixel(x0, y0).lerp(image.get_pixel(x0 + 1, y0), fx)
	var low := image.get_pixel(x0, y0 + 1).lerp(image.get_pixel(x0 + 1, y0 + 1), fx)
	return top.lerp(low, fy)
