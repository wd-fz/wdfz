extends SceneTree
## Runs against the exported PCK, with this verifier supplied from outside the package.

const APP := preload("res://game/app/app.tscn")
var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failed = true
		printerr("EXPORT FAILURE: ", message)


func _run() -> void:
	var driver := RenderingServer.get_current_rendering_driver_name()
	var method := RenderingServer.get_current_rendering_method()
	_check(driver == "vulkan" and method == "forward_plus" and RenderingServer.get_rendering_device() != null,
		"exported project must render with Vulkan Forward+")
	print("EXPORT RENDERER: %s / %s" % [driver, method])
	for folder: String in ["tests", "tools", "docs", "pictures"]:
		_check(not DirAccess.dir_exists_absolute("res://" + folder), "development folder shipped: " + folder)
	var path := "user://framework-tests/export-%s/" % Time.get_ticks_usec()
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new(path + "slot.json")
	app.settings = GameSettings.new(path + "settings.json")
	root.add_child(app)
	await process_frame
	app.start_new_game()
	await process_frame
	_check(app.session != null and app.session.world_id == "teach1", "cannot start the campus")
	await RenderingServer.frame_post_draw
	_check(not root.get_texture().get_image().is_empty(), "exported campus did not render a frame")
	_check(CampusData.room_ids().size() == 42, "dynamic layout JSON or models missing")
	_check(CampusData.tiers_available().size() == 5, "quality tiers missing")
	_check(FileAccess.file_exists("res://assets/audio/index.json"), "audio index missing")
	_check(FileAccess.file_exists(MazeDeath.GEOMETRY) and DeathGeometry.mesh("hall",MazeDeath.GEOMETRY).get_surface_count()==1, "dynamic maze death geometry missing")
	for resource: String in ["res://assets/campus/crowd/full.png","res://assets/campus/exchange/exchange-sign.png","res://game/presentation/world/campus/dust_points.gdshader"]:
		_check(ResourceLoader.exists(resource), "presentation resource missing: " + resource)
	app.return_to_menu()
	for id: String in ["out", "lab3", "teach1"]:
		_check(app.router.switch_to(id).is_empty(), "cannot load " + id)
		await process_frame
	app.return_to_menu()
	app.queue_free()
	for _i in 3:
		await physics_frame
		await process_frame
	CampusData.clear_caches()
	if DirAccess.dir_exists_absolute(path):
		for filename: String in DirAccess.get_files_at(path):
			DirAccess.remove_absolute(path + filename)
		DirAccess.remove_absolute(path)
	print("EXPORT SMOKE: ", "failed" if _failed else "passed")
	quit(1 if _failed else 0)
