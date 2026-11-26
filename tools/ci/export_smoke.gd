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


func _model_paths(directory: String) -> PackedStringArray:
	var result := PackedStringArray()
	for file in DirAccess.get_files_at(directory):
		if file.ends_with(".glb.remap"):
			result.append(directory.path_join(file.trim_suffix(".remap")))
		elif file.ends_with(".glb"):
			result.append(directory.path_join(file))
	for child in DirAccess.get_directories_at(directory):
		result.append_array(_model_paths(directory.path_join(child)))
	return result


func _check_outdoor_props(model: Node, path: String) -> void:
	var tint_by_mesh := {}
	var batches := 0
	for prop: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var extras: Dictionary = prop.get_meta("extras", {})
		if not extras.has("wdfz_instances"): continue
		var tinted := extras.has("wdfz_colors")
		_check(prop.mesh != null and tint_by_mesh.get(prop.mesh, tinted) == tinted, "outdoor prop colour binding: " + path)
		tint_by_mesh[prop.mesh] = tinted
		batches += 1
	_check(not tint_by_mesh.is_empty() and tint_by_mesh.size() < batches, "outdoor prop meshes were not shared at import: " + path)


func _check_mesh_preparation(model: Node, path: String) -> void:
	var prepared_props := 0
	var prepared_walls := 0
	for node: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if node.mesh == null: continue
		if node.mesh.has_meta(CampusBatches.GEOMETRY_KEY): prepared_props += 1
		var walls: Dictionary = node.mesh.get_meta(CampusBatches.OCCLUDER_FACES, {})
		for faces: PackedVector3Array in walls.values():
			if not faces.is_empty(): prepared_walls += 1
	_check(prepared_props > 0 and prepared_walls > 0, "missing precomputed prop/occluder geometry: " + path)


## The smoke runs with a real renderer. Read back the native instance matrices
## and tints, including orientation, for every repacked tier.
func _check_baked_exteriors() -> void:
	var world := CampusWorld.new()
	world.resident = true
	world.layout = CampusData.layout("out")
	world.space = CampusSpace.new(CampusData.rooms(), world.layout, CampusData.campus())
	for tier: int in CampusData.MODEL_TIERS:
		var model := world._prepare_visual(tier)
		_check(model != null and model.has_meta(CampusWorld.BakedExterior.FACADES), "resident exterior not loaded from package: %d" % tier)
		if model == null: continue
		var facades: Dictionary = model.get_meta("facades", {})
		_check(facades.has("teach1") and facades.has("lab1") and model.has_node(CampusShell.ROOFLINE), "exterior lost storey visibility groups: %d" % tier)
		var instances := 0
		var ok := true
		for node: MultiMeshInstance3D in model.find_children("*", "MultiMeshInstance3D", true, false):
			var mm := node.multimesh
			var colors: PackedFloat32Array = node.get_meta("campus_colors", PackedFloat32Array())
			for i in mm.instance_count:
				var intended := CampusPreview.instance_transform(node, i)
				ok = ok and intended.is_equal_approx(mm.get_instance_transform(i))
				if mm.use_colors:
					var color := mm.get_instance_color(i)
					ok = ok and color.is_equal_approx(Color(colors[i * 3], colors[i * 3 + 1], colors[i * 3 + 2]))
			instances += mm.instance_count
		_check(ok and instances > 0, "exterior instance buffer differs from partition metadata: %d" % tier)
		model.free()
	world.free()


func _run() -> void:
	var driver := RenderingServer.get_current_rendering_driver_name()
	var method := RenderingServer.get_current_rendering_method()
	var expected := "mobile" if "--expect-renderer=mobile" in OS.get_cmdline_user_args() else "forward_plus"
	_check(driver == "vulkan" and method == expected and RenderingServer.get_rendering_device() != null,
		"exported project must render with Vulkan " + expected)
	print("EXPORT RENDERER: %s / %s" % [driver, method])
	for folder: String in ["tests", "tools", "docs", "pictures", "addons", "assets/campus_q4"]:
		_check(not DirAccess.dir_exists_absolute("res://" + folder), "development folder shipped: " + folder)
	_check_baked_exteriors()
	var model_paths := _model_paths("res://assets")
	_check(model_paths.size() >= 172, "the four model tiers are not present in the export")
	for model_path in model_paths:
		var packed := load(model_path) as PackedScene
		_check(packed != null, "exported model/material dependency missing: " + model_path)
		if packed != null:
			var model := packed.instantiate()
			_check(model != null, "exported model cannot instantiate: " + model_path)
			if model != null:
				if model_path.get_file() in ["out.glb", "teach1.glb"]: _check_mesh_preparation(model, model_path)
				if model_path.get_file() == "out.glb": _check_outdoor_props(model, model_path)
				model.free()
		await process_frame
	print("EXPORTED MODELS: %d loaded with native typed material dependencies" % model_paths.size())
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
	_check(CampusData.tiers_available() == [0,1,2,3], "supported model tiers missing")
	_check(FileAccess.file_exists("res://assets/package_policy.json"), "lossless export plugin did not run")
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
	app._setting_changed("render_scale",85)
	app._setting_changed("render_budget",5)
	app._setting_changed("fps_limit",72)
	_check(app.settings.get_int("quality")==GraphicsProfile.CUSTOM and is_equal_approx(root.scaling_3d_scale,.85)
		and not app._campus_world().lighting.env.ssao_enabled and Engine.max_fps==72,"exported custom graphics/frame pacing did not apply")
	app._setting_changed("quality",2)
	_check(Engine.max_fps==72,"selecting an exported preset cleared the frame cap")
	app._setting_changed("fps_limit",0)
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
	for scene: String in ["patrol","garage","san","floor","swarm","window_gaze"]:
		var death := DeathCG.new()
		app.add_child(death)
		var camera_before := app.player.camera.transform
		death.begin_live(scene,app.player,app._campus_world(),app.ui,DeathCG.duration(scene,0),true)
		death.update(death.dur*.58)
		await RenderingServer.frame_post_draw
		_check(death.shots is DeathInPlace and app._campus_world().visible and death._sky==null,"exported live death replaces its actual surroundings: "+scene)
		_check(not root.get_texture().get_image().is_empty(),"exported live death did not render: "+scene)
		death.finish()
		_check(app.player.camera.transform.is_equal_approx(camera_before),"exported live death did not restore its camera: "+scene)
		death.queue_free()
		await process_frame
	app._toggle_debug()
	_check(app.debug_panel!=null and app.debug_panel._pages.has("诊断") and app.debug_panel._pages.has("日志"),"exported developer pages missing")
	app.debug_panel.select_page("诊断")
	app.debug_flow.command("collisions")
	await RenderingServer.frame_post_draw
	_check(app.debug_flow.probe.shown>0,"exported physics outlines cannot draw")
	app.debug_flow.command("export_report")
	_check(FileAccess.file_exists(app.saves.side_path("debug-report.json")),"exported diagnostic report cannot write")
	app.debug_panel.dismiss()
	_check(app.debug_flow.probe.shown==0 and not app.player.debug_frozen,"exported tool cleanup leaves hidden overlays or frozen input")
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
