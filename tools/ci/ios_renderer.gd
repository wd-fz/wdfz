extends SceneTree
## Run with --main-pack on the game data extracted from the finished device IPA.


func _initialize() -> void:
	var expected := {
		"rendering/rendering_device/driver.ios": "metal",
		"rendering/renderer/rendering_method.mobile": "mobile",
		"rendering/rendering_device/fallback_to_vulkan.ios": false,
		"rendering/rendering_device/fallback_to_opengl3": false,
	}
	for key: String in expected:
		if ProjectSettings.get_setting(key) != expected[key]:
			printerr("Unexpected packed iOS setting: ", key, " = ", ProjectSettings.get_setting(key))
			quit(1)
			return
	print("IPA RENDERER SETTINGS: metal / mobile")
	if "--verify-metal-frame" in OS.get_cmdline_user_args():
		_render_frame.call_deferred()
	else:
		quit(0)


func _render_frame() -> void:
	if RenderingServer.get_current_rendering_driver_name() != "metal" or RenderingServer.get_current_rendering_method() != "mobile" or RenderingServer.get_rendering_device() == null:
		printerr("No active native Metal Mobile rendering device")
		quit(1)
		return
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position.z = 3
	camera.make_current()
	var surface := StandardMaterial3D.new()
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	surface.albedo_color = Color.RED
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	box.material_override = surface
	root.add_child(box)
	await process_frame
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	if frame == null or frame.is_empty():
		printerr("Native Metal returned no frame")
		quit(1)
		return
	var pixel := frame.get_pixel(frame.get_width() >> 1, frame.get_height() >> 1)
	if pixel.r < 0.4 or pixel.r < 2.0 * maxf(pixel.g, pixel.b):
		printerr("Native Metal failed the color readback: ", pixel)
		quit(1)
		return
	print("IPA METAL FRAME: passed")
	quit(0)
