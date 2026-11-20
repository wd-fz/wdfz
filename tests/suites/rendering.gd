extends "res://tests/support/test_suite.gd"
## A headless run uses Godot's dummy device; it is never GPU verification.


func test_backend() -> void:
	if DisplayServer.get_name() == "headless":
		print("RENDERER: headless / dummy (no GPU verification)")
		return
	var driver := RenderingServer.get_current_rendering_driver_name()
	var method := RenderingServer.get_current_rendering_method()
	var device := RenderingServer.get_rendering_device()
	var expected_driver := "metal" if OS.get_name() == "iOS" else "vulkan"
	check(driver == expected_driver, "Native rendering uses the target platform's graphics API")
	check(method in ["forward_plus", "mobile"], "Native renderer uses a RenderingDevice pipeline")
	check(device != null, "Native run owns a real rendering device")
	if driver == expected_driver and method in ["forward_plus", "mobile"] and device != null:
		print("RENDERER VERIFIED: %s / %s" % [driver, method])
