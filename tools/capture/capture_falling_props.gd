extends SceneTree
## Controlled native captures: inject event phase/landing position and camera,
## advance the real presentation at 60 Hz. Not a natural random playthrough.
const APP:=preload("res://game/app/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _shot(label: String) -> void:
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/falling-props/"+label+".png")


func _look(app: GameApp, feet: Vector3, target: Vector3) -> void:
	var direction:=target-(feet+Vector3.UP*1.65)
	app.player.restore_pose({"position":[feet.x,feet.y,feet.z],"yaw":atan2(-direction.x,-direction.z),"pitch":atan2(direction.y,Vector2(direction.x,direction.z).length())})


func _run() -> void:
	root.size=Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute("res://build/previews/falling-props")
	var app: GameApp=APP.instantiate()
	app.saves=SaveStore.new("user://capture-falling-props/save.json")
	app.settings=GameSettings.new("user://capture-falling-props/settings.json")
	root.add_child(app)
	await process_frame
	app.wuda_roll=func() -> float: return 1
	app.start_new_game("hard","none")
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app._stand_up()
	app.school().tsec=720
	var bytes:=FileAccess.get_file_as_bytes("res://tests/fixtures/falling_props-reference.json.gz")
	var fixture: Dictionary=JSON.parse_string(bytes.decompress_dynamic(16*1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8())
	app.travel("out",{"position":[1200/9.0,0,400/9.0],"yaw":0,"pitch":0},false)
	var cw:=app._campus_world()
	var wall: Dictionary={}
	var normal:=Vector3.ZERO
	var land:=Vector3.ZERO
	var feet:=Vector3.ZERO
	# Keep the landing and observation points on walkable paving, outside planters.
	for candidate: Dictionary in fixture["walls"]:
		var source: Dictionary=candidate["result"]
		if absf(source["nx"]*source["ny"])>.01: continue
		var p:=CampusGeometry.to_scene(null,Vector2(source["x"],source["y"])*AnomalyModule.SC)
		normal=Vector3(source["nx"],0,source["ny"])
		for side in [0,-2,2,-4,4,-6,6]:
			land=Vector3(p.x,0,p.y)+normal*2.2+Vector3(-normal.z,0,normal.x)*side
			feet=land+normal*1.5
			var point:=CampusGeometry.to_world(null,land.x,land.z)
			app.anomaly().set_context({"scene":"out","x":point.x,"y":point.y})
			var nearest:=app.anomaly()._cup_wall()
			if nearest.is_empty() or nearest["m"]>=2.4: continue
			if not app._can_stand(point,null,0) or not app._can_stand(CampusGeometry.to_world(null,feet.x,feet.z),null,0): continue
			if cw.visual_ground.height(land.x,land.z)>.2 or cw.visual_ground.height(feet.x,feet.z)>.2: continue
			wall=nearest
			break
		if not wall.is_empty(): break
	if wall.is_empty():
		push_error("No walkable falling-prop capture location")
		quit(1)
		return
	cw.anomaly_fx.visual_seed=42
	for kind: String in ["cup","cola"]:
		var tf:=1.2 if kind=="cup" else 1.6
		var tl:=tf+sqrt(2*(AnomalyModule.CUP_H if kind=="cup" else AnomalyModule.COLA_H)/9.8)
		var data:={"scene":"out","wall":wall,"phase":0,"wob":tf,"warn":tf,"tf":tf,"tl":tl,"lx":land.x/CampusGeometry.U2M,"ly":land.z/CampusGeometry.U2M}
		app.anomaly().an.merge({"id":kind,"active":true,"t":0.0,"data":data},true)
		var elapsed:=0.0
		for stage in 3:
			var goal: float=[.6,tf+(tl-tf)*.94,tl+.7][stage]
			while elapsed<goal:
				var dt:=minf(1.0/60,goal-elapsed)
				elapsed+=dt
				data["phase"]=0 if elapsed<tf else (1 if elapsed<tl else 2)
				app.anomaly().an["t"]=elapsed
				cw.anomaly_fx.update(dt,app.anomaly().an,null,"out",feet,Vector2(normal.x,normal.z))
			var props: FallingProps=cw.anomaly_fx._extra["falling"]
			var target: Vector3=props.ring.position+normal*.5 if kind=="cola" and stage==0 else props.body.position
			_look(app,feet,target)
			app._school_step(0,app.campus())
			app.ui.show_runtime(app.session.clock.active_seconds)
			app.ui.show_prompt("")
			app.ui.show_notice("")
			await _shot(("水杯" if kind=="cup" else "可乐")+"-"+["预警","坠落","落地"][stage])
		app.anomaly().end_now()
	app.return_to_menu()
	app.queue_free()
	await process_frame
	quit()
