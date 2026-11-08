extends SceneTree
## The portal rig and the 《门》 ending in the real lab (needs a display):
## godot --path . --rendering-driver opengl3 --script res://tools/capture/capture_portal_device.gd
## Output: build/previews/portal/.

const APP := preload("res://game/app/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _shot(name: String) -> void:
	for _i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/portal/%s.png" % name)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://portal-preview/save.json")
	app.settings = GameSettings.new("user://portal-preview/settings.json")
	root.add_child(app)
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/previews/portal")
	app.start_new_game("easy")
	for _i in 10:
		await process_frame
	var spot := PortalDevice.bench_spot(CampusData.layout("lab1"))
	app.travel("lab1", {"position": [spot.x, 0.05, spot.y + 3.0], "yaw": 0.0, "pitch": 0.0}, false)
	for _i in 30:
		await process_frame
	var fac := app.facilities()
	for spec: Array in [["live-1-base", false, false], ["live-2-ready", true, false], ["live-3-open", true, true]]:
		fac.portal["sketch"] = bool(spec[1])
		fac.portal["open"] = bool(spec[2])
		app._facility_step()
		await _shot(String(spec[0]))
	app.player.enabled = false
	app._reach_ending("portal")
	var cut: EndingCut = app._ending_cut
	cut.set_process(false)
	for spec: Array in [["portal-1-charge", 0.2], ["portal-2-open", 0.5], ["portal-3-enter", 0.8], ["portal-4-through", 0.96]]:
		cut.k = float(spec[1])
		cut._apply(cut.k)
		await _shot(String(spec[0]))
	quit()
