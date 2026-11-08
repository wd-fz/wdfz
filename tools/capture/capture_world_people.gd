extends SceneTree
## Controlled scenes through real presentation adapters, landscape, in a fresh test profile.
const APP := preload("res://game/app/app.tscn")
var app: GameApp
func _initialize() -> void: call_deferred("_run")
func _frames(n: int = 4) -> void:
	for _i in n: await process_frame
func _shot(label: String) -> void:
	var world := app._campus_world()
	app.ui.show_notice("")
	var school := app.school()
	app.ui.show_status(school.place_name(app.session.world_id,app.player.position.y),school.period_text(false),school.period_class(false),school.clock_text(false))
	world.lighting.update(0,app.school().tsec,app.player.camera)
	app.ui.scene_post().parameter("exposure",world.lighting.post_exposure)
	await _frames()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/world-people/"+label+".png")
func _pose(room: Variant, p: Vector2, ang: float = -PI/2) -> Dictionary:
	var at := CampusGeometry.to_scene(room,p)
	return {"position":[at.x,0,at.y],"yaw":CampusGeometry.yaw_from_ang(ang),"pitch":0.0}
func _run() -> void:
	root.size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute("res://build/previews/world-people")
	app = APP.instantiate()
	app.saves = SaveStore.new("user://world-people-capture-%d/slot.json" % Time.get_ticks_usec())
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	await _frames()
	app.wuda_roll = func() -> float: return 1
	app.start_new_game("hard","none")
	app.set_process(false)
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app.school().day = 2
	app.school().tsec = 600
	var visit := app.exchange()
	visit.s["phase"] = "waiting"
	var leader: Vector2 = visit.members()[0]
	# Stay on the north walkway; the old +45 Y pose was inside the administration building.
	var stand := leader+Vector2(-40,-32)
	var look := leader+Vector2(10,-5)-stand
	app.travel("out",_pose(null,stand,look.angle()),false)
	app._show_visit(visit)
	await _shot("交流团登记")
	# Controlled close inspection of the original canvas; this is not a walking route.
	var sign: MeshInstance3D = app._visit_nodes.get_node("ExchangeSign/Panel")
	app.player.global_position = sign.global_position+Vector3(0,-1.2,2)
	app.player.rotation.y = 0
	app.player.camera.position.y = CameraMotion.EYE
	app.player.camera.rotation = Vector3(atan2(1.2-CameraMotion.EYE,2),0,0)
	await _shot("接待登记牌")
	visit.s["phase"] = "escort"
	visit.s["prog"] = 250
	visit.s["search"] = [{"x":1000,"y":800},{"x":1040,"y":700},{"x":900,"y":500}]
	app.player.restore_pose(_pose(null,Vector2(1000,840)))
	app._show_visit(visit)
	await _shot("高个搜查员")
	# The shared fixture searches a standing tile with an unobstructed line to a real window.
	var helper := preload("res://tests/support/test_suite.gd").new(self)
	var spot: Dictionary = helper._paper_spot("danger")
	var room: Dictionary = CampusData.rules().room(spot["room"])
	var win: Dictionary = spot["w"]
	app.travel(spot["room"],_pose(room,spot["stand"],spot["look"]),false)
	app.gaze().s["ev"] = {"room":spot["room"],"c":win["c"],"r":win["r"]}
	app.gaze().set_context(app._gaze_context())
	app._show_gaze(app.gaze())
	await _shot("窗内眼睛与人影")
	app.gaze().s["ev"] = null
	app._show_gaze(app.gaze())
	room = CampusData.rules().room("admin1")
	var p := Vector2(room["ox"]+2.9*room["tw"],room["oy"]+21.0*room["th"])
	app.travel("admin1",_pose(room,p),false)
	app._campus_world().show_checkup(true,true,app.tales().chart_line())
	await _shot("体检队伍")
	room = CampusData.rules().room("teach1")
	p = Vector2(room["ox"]+48.8*room["tw"],room["oy"]+11.39*room["th"])
	app.travel("teach1",_pose(room,p,PI/2),false)
	app.fake_normal().fn["on"] = true
	app.fake_normal().fn["v"] = 10
	app._fake_people_random.seed = 42
	app._fake_people_step(app.fake_normal(),room)
	app.ui.scene_post().fake_normal = 1
	app._campus_world().lighting.fake_normal = 1
	await _shot("假正常人群")
	app.fake_normal().fn["on"] = false
	app._fake_people_step(app.fake_normal(),room)
	app.ui.scene_post().fake_normal = 0
	app._campus_world().lighting.fake_normal = 0
	var world := app._campus_world()
	world.set_player_scene(app.player.position)
	world.show_silhouettes([[p.x-12,p.y+30],[p.x+12,p.y+30]],room,0)
	await _shot("检查黑影")
	app.return_to_menu()
	app.queue_free()
	await _frames()
	quit()
