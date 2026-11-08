class_name InceptionFlow
extends Node
## Only this boundary changes worlds, applies the wake settlement or creates visual nodes.
var app: GameApp
var fx: InceptionFx
var fade: WorldFade
var _entering := false


func here() -> bool:
	return app.session!=null and app.session.world_id==InceptionModule.ROOM


func _world_position() -> Vector2:
	return CampusGeometry.to_world(CampusData.layout(app.session.world_id),app.player.position.x,app.player.position.z)


func _cell() -> Vector2i:
	var r:=CampusData.layout(InceptionModule.ROOM)
	var w:=_world_position()
	return Vector2i(floori((w.x-r["ox"])/r["tw"]),floori((w.y-r["oy"])/r["th"]))


func hint() -> String:
	if app.session==null: return ""
	if here(): return "那扇门" if InceptionModule.near_exit(_cell()) else ""
	if app.session.world_id==InceptionModule.TOP_ROOM and app.inception().near_top(app.session.world_id,CampusData.layout(app.session.world_id),_world_position()):
		return "桌上的陀螺"
	return ""


func interact() -> bool:
	if hint()=="": return false
	if here():
		app.inception().exit_door(true)
		flush()
	elif app._add_item("top"):
		app.inception().top=true
		changed_world()
		app.ui.show_notice("我：桌上有一个铜陀螺，底下磨得很亮。宿舍里没有人认它。")
	return true


func rest(key: String) -> bool:
	if key!="sleep": return false
	var day:=app.school()
	var p:=_world_position()
	var from: Dictionary={"room":app.session.world_id,"x":p.x,"y":p.y,"ang":CampusGeometry.ang_from_yaw(app.player.rotation.y),"floorY":app.player.position.y}
	var intercepted:=app.inception().rest(day.day,day.tsec,SchoolClock.need_where(day.tsec)=="教室" and not SchoolClock.is_night(day.tsec),app.items().has("top"),from)
	flush()
	return intercepted


func use(id: String) -> bool:
	if app.session==null or not app.items().has(id): return false
	if id=="top":
		app.inception().spin(here())
		flush()
		return true
	return false


func changed_world() -> void:
	if not _entering: _cancel_fade()
	clear()
	if app.session==null: return
	if here(): app.inception().ensure_dream(app.school().day)
	if here() or (app.session.world_id==InceptionModule.TOP_ROOM and not app.inception().top):
		fx=InceptionFx.new()
		app._campus_world().add_child(fx)
		fx.build(CampusData.layout(app.session.world_id))
		fx.present(0,app.inception().dream,app.player.position,app.player.rotation.y)


func clear() -> void:
	if is_instance_valid(fx):
		fx.hide()
		fx.queue_free()
	fx=null


func _cancel_fade() -> void:
	if is_instance_valid(fade): fade.cancel()
	fade=null


func cancel() -> void:
	_cancel_fade()
	clear()


func _enter() -> void:
	_cancel_fade()
	var run:=app.session
	var room:=run.world_id
	fade=WorldFade.new()
	add_child(fade)
	fade.begin(func() -> void:
		if app.session!=run or run.world_id!=room or app._dead(): return
		_entering=true
		app.travel(InceptionModule.ROOM,start_pose(),false)
		_entering=false
		app.save_game(true))


func _process(dt: float) -> void:
	# The original frame hook keeps the top turning while a menu pauses simulation.
	if is_instance_valid(fx) and app.session!=null and not app._dead():
		fx.present(dt,app.inception().dream,app.player.position,app.player.rotation.y)


func start_pose(keep_view: bool = false) -> Dictionary:
	var r:=CampusData.layout(InceptionModule.ROOM)
	var p:=CampusGeometry.to_scene(r,CampusGeometry.tile_center(r,InceptionModule.START.x,InceptionModule.START.y))
	return {"position":[p.x,0,p.y],"yaw":app.player.rotation.y if keep_view else CampusGeometry.yaw_from_ang(0),"pitch":app.player.capture_pose()["pitch"] if keep_view else 0.0}


func step(dt: float) -> void:
	if not here() or app._dead(): return
	app.inception().tick(dt,_cell())
	flush()
	if here() and not app._dead():
		app.player.update_view(0,app.body().eye_drop()+app.inception().eye_drop())


func flush() -> void:
	for event: Dictionary in app.inception().take_events():
		match event["kind"]:
			"notice": app.ui.show_notice(event["text"])
			"fact": app.fact(event["fact"])
			"save": app.save_game(true)
			"enter": _enter()
			"loop": app.player.restore_pose(start_pose(true))
			"ending":
				app.player.reset_view()
				clear()
				app._reach_ending(event["id"])
			"wake": _wake(event)


func _wake(event: Dictionary) -> void:
	var from: Dictionary=event["from"]
	var pose:=app.campus().default_spawn(from["room"])
	if from.get("x")!=null:
		var p:=CampusGeometry.to_scene(CampusData.layout(from["room"]),Vector2(from["x"],from["y"]))
		pose={"position":[p.x,float(from.get("floorY",0)),p.y],"yaw":CampusGeometry.yaw_from_ang(float(from.get("ang",0))),"pitch":app.player.capture_pose()["pitch"]}
	app.travel(from["room"],pose,false)
	app.player.reset_view(app.body().eye_drop())
	if event["settle"]:
		var day:=app.school()
		day.advance_game_time(90)
		day.san=minf(100,day.san+snappedf(26.0*float(day.pressure()["rest"]),.1)*2)
		day.add_violation(15)
		day.stam=minf(day.stamina_max(),day.stam+25)
		app.facilities().act_cool["sleep"]=day.game_clock()+200
		app.fact({"kind":"rest","key":"sleep"})
		app.fact({"kind":"inception","what":"wake","fell":event["fell"]})
		app.ui.show_notice("我：我猛地坐起来。还是宿舍的床。窗外的天色不对——我睡了很久。")
	app.save_game(true)
