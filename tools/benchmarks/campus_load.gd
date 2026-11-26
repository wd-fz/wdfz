extends SceneTree
## Start a separate process for each sample. New writes the dedicated save used by continue.
const APP := preload("res://game/app/app.tscn")
const SLOT := "user://campus-load-benchmark/slot.json"
## Both the original classroom spawn and the seated save preloaded these eight regions.
const DESK_REGIONS := ["lift_teach", "link1", "link2", "out", "stair_lab", "stair_teach_e", "teach1", "teach2"]
var app: GameApp
var started := 0
var previous_frame := 0
var worst_frame_ms := 0.0


func _initialize() -> void:
	call_deferred("_run")


func _frame() -> void:
	var now := Time.get_ticks_usec()
	worst_frame_ms = maxf(worst_frame_ms, (now - previous_frame) / 1000.0)
	previous_frame = now


func _elapsed() -> float:
	return (Time.get_ticks_usec() - started) / 1000.0


func _meshes(model: Node3D) -> int:
	if model == null: return 0
	var meshes := 0
	for node: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if node.mesh != null: meshes += 1
	for node: MultiMeshInstance3D in model.find_children("*", "MultiMeshInstance3D", true, false):
		if node.multimesh != null and node.multimesh.instance_count > 0: meshes += 1
	return meshes


func _shapes(world: CampusWorld) -> int:
	var collision := world.get_node_or_null("Collision") as StaticBody3D
	if collision == null or collision.collision_layer == 0: return 0
	var shapes := 0
	for owner_id in collision.get_shape_owners():
		if not collision.is_shape_owner_disabled(owner_id): shapes += collision.shape_owner_get_shape_count(owner_id)
	return shapes


func _model_counts() -> Dictionary:
	var world := app._campus_world()
	if world == null or not world.geometry_ready: return {}
	var model := world.get_node_or_null("Model") as Node3D
	if model == null or not model.is_visible_in_tree(): return {}
	var meshes := _meshes(model)
	var shapes := _shapes(world)
	return {"mesh_nodes": meshes, "collision_shapes": shapes} if meshes and shapes else {}


func _fail(reason: String) -> void:
	printerr("CAMPUS LOAD FAILED: ", reason)
	quit(1)


func _run() -> void:
	var scenario := "new"
	var quality := 2
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="): scenario = arg.trim_prefix("--case=")
		if arg.begins_with("--quality="): quality = arg.trim_prefix("--quality=").to_int()
	if scenario not in ["new", "continue"] or quality < 0 or quality > 4:
		_fail("expected --case=new|continue and --quality=0..4")
		return
	var headless := DisplayServer.get_name() == "headless"
	app = APP.instantiate()
	app.saves = SaveStore.new(SLOT)
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	await process_frame
	app._setting_changed("quality", quality)
	if not headless: await RenderingServer.frame_post_draw
	if scenario == "continue" and not app.saves.exists():
		_fail("run --case=new once in the same isolated user profile")
		return

	var settings := app.settings.graphics().duplicate(true)
	print("CAMPUS LOAD START ", scenario, " quality=", quality)
	var report := {"scenario": scenario, "quality": quality, "graphics": settings,
		"engine": Engine.get_version_info().string, "display": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(), "driver": RenderingServer.get_current_rendering_driver_name(),
		"device": RenderingServer.get_video_adapter_name(), "resolution": [root.size.x, root.size.y],
		"render_scale": root.scaling_3d_scale, "model_tier": CampusData.tier}
	started = Time.get_ticks_usec()
	previous_frame = started
	process_frame.connect(_frame)
	if scenario == "new":
		app._start_at_desk("easy", "none", StudentCast.DEFAULT, false)
	else:
		app._continue_with_loading()
	var curtain := app.ui.loading_screen
	while app.starting(): await process_frame
	if app.session == null or app.session.world_id != "teach1":
		_fail("classroom entry failed")
		return
	report["loading_complete_ms"] = _elapsed()
	print("CAMPUS LOAD READY ", report.loading_complete_ms, " ms")
	if is_instance_valid(curtain) and curtain.is_inside_tree(): await curtain.tree_exited
	if app.opening_busy():
		if app._opening_cut != null and app._opening_cut.on: app._opening_cut.end(true)
		else: app.ui._end_opening(true)
	if not headless: await RenderingServer.frame_post_draw
	report["playable_ms"] = _elapsed()
	print("CAMPUS LOAD PLAYABLE ", report.playable_ms, " ms")
	_frame()
	process_frame.disconnect(_frame)
	report["entry_worst_frame_ms"] = worst_frame_ms
	report["classroom"] = _model_counts()
	if report.classroom.is_empty() or not app.player.enabled or paused or not app.router.school_ready():
		_fail("classroom model, collision or player control missing")
		return
	report["entry_model_regions"] = []
	report["entry_collision_shapes"] = 0
	for region: CampusWorld in app.router.resident.regions.values():
		var shapes := _shapes(region)
		if shapes == 0:
			_fail("missing active campus collision in " + region.scene_id)
			return
		report.entry_collision_shapes += shapes
		if region.geometry_ready and _meshes(region.get_node_or_null("Model")) > 0:
			report.entry_model_regions.append(region.scene_id)
	report.entry_model_regions.sort()
	for id: String in DESK_REGIONS:
		if not report.entry_model_regions.has(id):
			_fail("missing preloaded model at the desk: " + id)
			return
	if scenario == "new":
		app.save_game(true)
		if not app.saves.exists():
			_fail("test save missing")
			return

	app._stand_up()
	var classroom := app._campus_world()
	var door: Dictionary = CampusData.campus()["campus_doors"]["doors"][0]
	var port := CampusGeometry.door_port(classroom.layout, door)
	var point := CampusGeometry.to_scene(classroom.layout, (port.p as Vector2) + (port.n as Vector2) * 2.0)
	var pose := {"position": [point.x, 0.05, point.y], "yaw": CampusGeometry.yaw_from_ang(PI * .5), "pitch": 0.0}
	started = Time.get_ticks_usec()
	app.player.place(pose)
	app._campus_step(1.0 / 60.0)
	while app.session.world_id != "out" and _elapsed() < 180000.0: await process_frame
	if not headless: await RenderingServer.frame_post_draw
	report["doorway_ms"] = _elapsed()
	report["outside"] = _model_counts()
	if app.session.world_id != "out" or report.outside.is_empty() or app.settings.graphics() != settings or app.settings.get_int("quality") != quality:
		_fail("outdoor crossing, model, collision or graphics mismatch")
		return
	print("CAMPUS LOAD RESULT ", JSON.stringify(report))
	app.return_to_menu()
	app.queue_free()
	await process_frame
	quit(0)
