extends SceneTree
## Controlled original atmosphere poses, using formal scene lighting and landscape viewports.
const APP := preload("res://game/app/app.tscn")
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	root.size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute("res://build/previews/atmos-props")
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://atmos-props-capture-%d/slot.json" % Time.get_ticks_usec())
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	await process_frame
	app.wuda_roll = func() -> float: return 1
	app.start_new_game("hard","none")
	app.set_process(false)
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app._stand_up()
	app.ui.show_notice("")
	app.player.camera.position.y = CameraMotion.EYE
	var world := app._campus_world()
	world.lighting.update(0,app.school().tsec,app.player.camera)
	app.ui.scene_post().parameter("exposure",world.lighting.post_exposure)
	var fx := world.atmos_fx
	app.player.restore_pose({"position":[-21,0,-2.8],"yaw":0,"pitch":0})
	var record := {"room":"teach1","cls":"teach1:0","seed":.4,"gone":false,"seen":0,"anchor":app.atmos()._window_anchor.duplicate()}
	fx.show_window(record,app.player.camera)
	app.player.position = Vector3(fx._win_pos.x,0,fx._win_pos.z+1.7)
	app.player.camera.look_at(fx._win_pos+Vector3(0,.1,0))
	world.lighting.update(0,app.school().tsec,app.player.camera)
	for _i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/atmos-props/window.png")
	fx.show_window({},app.player.camera)
	root.size = Vector2i(1600,720)
	var sign := fx.signs[0].position
	app.player.restore_pose({"position":[sign.x,0,sign.z+2.4],"yaw":0,"pitch":.3})
	world.lighting.update(0,app.school().tsec,app.player.camera)
	for _i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/atmos-props/exit.png")
	var prop := fx.props.position
	app.player.restore_pose({"position":[prop.x+.7,0,prop.z+2.4],"yaw":0,"pitch":-.35})
	world.lighting.update(0,app.school().tsec,app.player.camera)
	for _i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/atmos-props/mop.png")
	app.return_to_menu()
	app.queue_free()
	for _i in 3: await process_frame
	quit()
