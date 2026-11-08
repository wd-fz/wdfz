extends SceneTree
## Controlled poses/times through actual classroom and broadcast presentation; isolated profile.
const APP := preload("res://game/app/app.tscn")
var app: GameApp
func _initialize() -> void: call_deferred("_run")
func shot(label: String) -> void:
	for _i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/classmates/"+label+".png")
func pose(room: Dictionary, col: float, row: float, ang: float) -> Dictionary:
	var p := CampusGeometry.to_scene(room,Vector2(room["ox"]+col*room["tw"],room["oy"]+row*room["th"]))
	return {"position":[p.x,0,p.y],"yaw":CampusGeometry.yaw_from_ang(ang),"pitch":-.04}
func light() -> void:
	var world := app._campus_world()
	world.lighting.update(0,app.school().tsec,app.player.camera)
	app.ui.scene_post().parameter("exposure",world.lighting.post_exposure)
func _run() -> void:
	root.size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute("res://build/previews/classmates")
	app = APP.instantiate()
	app.saves = SaveStore.new("user://capture-classmates-%d/slot.json" % Time.get_ticks_usec())
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	await process_frame
	app.wuda_roll = func() -> float: return 1
	app.start_new_game("hard","none")
	app.set_physics_process(false)
	app.set_process(false)
	app.player.set_physics_process(false)
	app._play_opening()
	app._opening_cut.set_process(false)
	app._opening_cut.tick(26*.12)
	await shot("开场正常教室")
	app._opening_cut.end(true)
	app.player.set_physics_process(false)
	var room: Dictionary = CampusData.rules().room("teach1")
	app._stand_up()
	app.player.restore_pose(pose(room,46.5,9.5,0))
	light()
	app._classmates_step(0)
	await shot("里世界教室")
	app.school().viol = 75
	for _i in 120: app._classmates_step(1.0/60)
	await shot("起身围拢")
	app.school().viol = 95
	for _i in 120: app._classmates_step(1.0/60)
	await shot("站到门前")
	app.travel("teach2",CampusData.rules().default_spawn("teach2"),false)
	app.travel("teach1",pose(room,38,16.5,PI),false)
	app.school().viol = 0
	app.broadcast().b["phase"] = "bell"
	app.broadcast().b["bell"] = 50.0
	for _i in 600: app._classmates_step(1.0/60)
	light()
	await shot("长铃后走向楼梯")
	app.broadcast().b["bell"] = 55.0
	var point := app.broadcast().crowd()
	var out := CampusGeometry.to_scene(null,Vector2(point["x"],point["y"]+50))
	app.travel("out",{"position":[out.x,0,out.y],"yaw":CampusGeometry.yaw_from_ang(-PI/2),"pitch":-.06},false)
	for _i in 3: await physics_frame
	app._show_crowd(app.broadcast())
	light()
	await shot("两列离校队伍")
	app.return_to_menu()
	app.queue_free()
	await process_frame
	quit()
