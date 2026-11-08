class_name KnifeFlow
extends Node
## Scene/input boundary for the one-second capture and the fake ending's wake button.
var app: GameApp


func captured() -> bool:
	return app.session!=null and app.knife()!=null and app.knife().captured()


func hint() -> String:
	if app.session==null or app.session.world_id!=KnifeModule.ROOM: return ""
	var room := CampusData.layout(KnifeModule.ROOM)
	var p := app.player.position
	return "旧工具抽屉" if app.knife().near(app.session.world_id,room,CampusGeometry.to_world(room,p.x,p.z)) else ""


func interact() -> bool:
	if hint()=="": return false
	if app.items().add("small_knife"):
		app.knife().took=true
		app.ui.show_notice("我：抽屉里压着一把折叠小刀，刃口有点钝。")
	else:
		app.ui.show_notice("我：抽屉里有一把折叠小刀。背包满了。")
	return true


func catch_player(message: String) -> bool:
	if not app.knife().catch_player(app.items().has("small_knife"),message): return false
	app.player.enabled=false
	app.player.clear_input()
	app.ui.clear_touch()
	flush()
	return true


func use(id: String, source: String = "bag") -> bool:
	if id!="small_knife" or app.session==null or app._dead(): return false
	if not app.knife().use(app.items().has(id),source): return false
	flush()
	return true


func step(dt: float) -> void:
	app.knife().tick(dt,app._dead())
	if captured():
		app.player.enabled=false
		app.player.clear_input()
	flush()


func flush() -> void:
	for event: Dictionary in app.knife().take_events():
		match event["kind"]:
			"notice": app.ui.show_notice(event["text"])
			"fact": app.fact(event["fact"])
			"remove": app.items().remove(event["id"])
			"kill":
				app.ui.hide_bag()
				app.ui.hide_choice()
				app.kill(event["text"],event["fx"],event["source"])
				if not app._dead(): app.resume_game()
			"ending": app._reach_ending(event["id"])


func wake() -> void:
	if app.session==null or app.story().ended!="knife": return
	app._cancel_cinematics()
	app.story().ended=""
	app.story().dead=false
	app.school().day=maxi(2,app.school().day+1)
	app.school().tsec=441.0
	app.school()._observe_pressure()
	app.patrol().reset()
	var seated := app.school().start_seated("teach1")
	app.travel("teach1",seated,false)
	app.player.seated=true
	app.player.restore_pose(seated)
	app.ui.set_normal_world(0)
	app.ui.hide_ending()
	app.resume_game()
	app.ui.show_notice("我：……我在座位上醒过来。早读。课本底下压着一张登记单，姓名那一栏后面写着：留校。")
	app.save_game(true)
