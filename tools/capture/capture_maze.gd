extends SceneTree
## Native maze / transition / death evidence. Requires a real or virtual display.
const APP := preload("res://game/app/app.tscn")
var app: GameApp

func _initialize() -> void:
	call_deferred("_run")

func _shot(id: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/maze/%s.png" % id)

func _run() -> void:
	root.size = Vector2i(1280,720)
	app = APP.instantiate()
	app.saves = SaveStore.new("user://maze-preview/save.json")
	app.settings = GameSettings.new("user://maze-preview/settings.json")
	root.add_child(app)
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/previews/maze")
	app.start_new_game("hard")
	app.set_physics_process(false)
	app._stand_up()
	app.elevator().ride = {"host":"teach","origin":2,"target":2,"phase":"cabin","rare":true,"remaining":0.0,"pending":null}
	app._apply_result(app.elevator()._enter_dream("67"))
	var cut := app.maze_flow.cut
	cut.set_process(false)
	for value in [.04,.3,.55,.76,.9]:
		cut.apply_frame(value)
		await _shot("entry-%02d" % roundi(value*100))
	cut.finish()
	app.player.enabled = false
	app.ui.show_notice("")
	app.ui.hud.hide()
	for pose: Array in [["spawn",0,0,0,PI/2,0],["exit1",-3,-8,35,PI/2,0],["bridge",0,4,-31.5,0,0],["exit2",-7,4,-35,-PI/2,0]]:
		app.player.restore_pose({"position":[pose[1],pose[2]+.01,pose[3]],"yaw":CampusGeometry.yaw_from_ang(pose[4]),"pitch":pose[5]})
		app._campus_world().lighting.update(0,app.school().tsec,app.player.camera)
		app._show_marks()
		await _shot(pose[0])
	for id in ["void","abyss"]:
		app._start_death_cg(id)
		for t in [.5,1.5,2.5,3.0]:
			app._death_cg.update(t)
			await _shot("death-%s-%02d" % [id,roundi(t*10)])
		app._stop_death_cg()
	app.maze_flow._start_cut("out", app.maze().geometry.cfg["exits"][1])
	cut = app.maze_flow.cut
	cut.set_process(false)
	for value in [.12,.35,.5,.8]:
		cut.apply_frame(value)
		await _shot("exit-cut-%02d" % roundi(value*100))
	cut.finish()
	app.return_to_menu()
	app.queue_free()
	await process_frame
	CampusData.clear_caches()
	quit()
