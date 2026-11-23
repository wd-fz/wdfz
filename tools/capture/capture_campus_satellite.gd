extends SceneTree
## Bake the north-up campus map from the same geometry used in exploration.
## xvfb-run -a godot --windowed --rendering-driver vulkan --script res://tools/capture/capture_campus_satellite.gd

const HEIGHT := 2048
const OUTPUT := "res://assets/ui/campus_satellite.jpg"


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	root.size = Vector2i(640, 360)
	var plan := CampusData.campus_map()
	var scale := float(CampusData.layout("out")["SC"]) * CampusGeometry.U2M
	var bounds: Dictionary = plan["bound"]
	var origin := Vector2(bounds["x0"], bounds["y0"]) * scale
	var far_corner := Vector2(bounds["x1"], bounds["y1"]) * scale
	var dimensions := far_corner - origin
	var centre := (origin + far_corner) * 0.5
	var view := SubViewport.new()
	view.size = Vector2i(roundi(HEIGHT * dimensions.x / dimensions.y), HEIGHT)
	view.own_world_3d = true
	view.msaa_3d = Viewport.MSAA_4X
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	CampusData.tier = 4
	var model := CampusWorld.build_visual("out", 4)
	if model == null:
		quit(1)
		return
	view.add_child(model)
	var world := WorldEnvironment.new()
	var sky := Environment.new()
	sky.background_mode = Environment.BG_COLOR
	sky.background_color = Color("283735")
	sky.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	sky.ambient_light_color = Color("d2e3ef")
	sky.ambient_light_energy = 0.58
	sky.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = sky
	view.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -42.0, 0.0)
	sun.light_color = Color("fff1d8")
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 350.0
	view.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = dimensions.y
	camera.far = 360.0
	view.add_child(camera)
	camera.position = Vector3(centre.x, 160.0, centre.y)
	camera.look_at(Vector3(centre.x, 0.0, centre.y), Vector3.FORWARD)
	camera.current = true
	for frame in 18: await process_frame
	await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	var result := image.save_jpg(OUTPUT, 0.92)
	if result == OK:
		print("Campus aerial map: %s px, %s" % [image.get_size(), OUTPUT])
	view.queue_free()
	await process_frame
	quit(0 if result == OK else 1)
