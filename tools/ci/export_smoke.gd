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
	_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "fresh desktop profile must remain windowed")
	_check(app.ui.menu_screen.find_child("FullscreenMenu",true,false).visible, "desktop fullscreen control missing")
	app.ui.fullscreen_requested.emit()
	for _i in 5: await process_frame
	_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "desktop fullscreen toggle failed")
	app.ui.fullscreen_requested.emit()
	for _i in 5: await process_frame
	_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "desktop return to window failed")
	app.start_new_game()
	await process_frame
	_check(app.session != null and app.session.world_id == "teach1", "cannot start the campus")
	await RenderingServer.frame_post_draw
	_check(not root.get_texture().get_image().is_empty(), "exported campus did not render a frame")
	_check(CampusData.room_ids().size() == 42, "dynamic layout JSON or models missing")
	_check(CampusData.tiers_available().size() == 5, "quality tiers missing")
	_check(FileAccess.file_exists("res://assets/audio/index.json"), "audio index missing")
	for id: String in CampusData.campus()["items"]:
		_check(UIArt.item(id) != null, "exported item illustration missing: " + id)
	for id: String in TalentModule.KEYS:
		_check(UIArt.talent(id) != null, "exported talent illustration missing: " + id)
	for spec: Array in PhonePanel.APPS:
		_check(UIArt.phone(spec[0]) != null, "exported phone illustration missing: " + String(spec[0]))
	_check(UIArt.talent("random") != null and UIArt.phone("battery") != null, "exported supporting illustrations missing")
	_check(UIArt.wallpaper() != null, "exported phone wallpaper missing")
	var art_catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(UIArt.ROOT + "catalog.json"))
	_check(art_catalog is Dictionary and art_catalog.size() == 9, "exported illustration catalog missing")
	if art_catalog is Dictionary:
		for group: String in art_catalog:
			for id: String in art_catalog[group]:
				var path_to_art := String(art_catalog[group][id])
				var texture := load(path_to_art) as AtlasTexture
				_check(texture != null and texture.atlas != null, "exported illustration cannot load: " + group + "/" + id)
	_check(ResourceLoader.exists(UIArt.ROOT + "atlases/stationery.png"), "exported document backdrop missing")
	var window_shadow := FigureModel.make("person", Color.BLACK, true, 1.0, Color.BLACK, false, true)
	_check(not window_shadow.find_children("*", "MeshInstance3D", true, false).is_empty(), "exported original window silhouette missing")
	window_shadow.free()
	_check(FileAccess.file_exists(MazeDeath.GEOMETRY) and DeathGeometry.mesh("hall",MazeDeath.GEOMETRY).get_surface_count()==1, "dynamic maze death geometry missing")
	for resource: String in ["res://assets/campus/crowd/full.png","res://assets/campus/exchange/exchange-sign.png","res://game/presentation/world/campus/dust_points.gdshader"]:
		_check(ResourceLoader.exists(resource), "presentation resource missing: " + resource)
	if app._opening_cut!=null and app._opening_cut.on: app._opening_cut.end(true)
	else: app.ui._end_opening(true)
	app.set_process(false)
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	for source: String in ["patrol","garage","car_entry","an:moth","an:exercise","an:cup","rules_knock","bell","window_gaze"]:
		var scene:=DeathCG.resolve(source,"vignette")
		_check(DeathCG.has(scene),"exported source catalog missing: "+source)
		var death:=DeathCG.new()
		app.add_child(death)
		death.begin(scene,app.player,app._campus_world(),app.ui,DeathCG.duration(scene,0),true)
		death.update(death.dur*.58)
		await RenderingServer.frame_post_draw
		_check(death.shots!=null and death.shots.focus!=null,"exported cinematic cannot build: "+source)
		if scene=="bell":
			_check(not death.shots.p["bell_model"].find_children("*","MeshInstance3D",true,false).is_empty(),"exported bell geometry missing")
		death.finish()
		death.queue_free()
		await process_frame
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
