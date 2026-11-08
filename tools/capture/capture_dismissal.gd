extends SceneTree
## 《放学》 in the real campus for its last stage (needs a display):
## godot --path . --rendering-driver opengl3 --script res://tools/capture/capture_dismissal.gd
## Output: build/previews/dismissal/.

const APP := preload("res://game/app/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _shot(name: String) -> void:
	for _i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/dismissal/%s.png" % name)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://dismissal-preview/save.json")
	app.settings = GameSettings.new("user://dismissal-preview/settings.json")
	root.add_child(app)
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/previews/dismissal")
	app.start_new_game("easy")
	for _i in 10:
		await process_frame
	app.player.enabled = false
	app._reach_ending("dismissal")
	for _i in 30:
		await process_frame
	var cut: EndingCut = app._ending_cut
	print("cut ", cut, " world ", app.session.world_id)
	cut.set_process(false)
	for spec: Array in [["dismissal-1-speakers", 0.08], ["dismissal-2-chairs", 0.3], ["dismissal-3-stairs", 0.55], ["dismissal-4-gate", 0.72], ["dismissal-5-outside", 0.86], ["dismissal-6-windows", 0.97]]:
		cut.k = float(spec[1])
		cut._apply(cut.k)
		print(spec[0], " world visible=", cut._world.visible, " env=", cut.cam.environment, " cam=", cut.cam.global_position, " gate=", cut._dis_gate, " campusfog=", (cut._campus_env.fog_density if cut._campus_env != null else -1.0), " exp=", (cut._campus_env.tonemap_exposure if cut._campus_env != null else -1.0))
		await _shot(String(spec[0]))
	quit()
