extends SceneTree
## Diagnostic captures of actual campus props. Positions, event state and elapsed
## animation are injected; this is not a natural playthrough or a probability test.
const APP:=preload("res://game/app/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _shot(name: String) -> void:
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/anomaly-props/"+name+".png")


func _run() -> void:
	root.size=Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute("res://build/previews/anomaly-props")
	var app: GameApp=APP.instantiate()
	app.saves=SaveStore.new("user://capture-anomaly-props/save.json")
	app.settings=GameSettings.new("user://capture-anomaly-props/settings.json")
	root.add_child(app)
	await process_frame
	app.wuda_roll=func() -> float: return 1
	app.start_new_game("hard","none")
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app._stand_up()
	app.school().tsec=720
	var bytes:=FileAccess.get_file_as_bytes("res://tests/fixtures/anomaly_fx-reference.json.gz")
	var fixture: Dictionary=JSON.parse_string(bytes.decompress_dynamic(16*1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8())
	var names:={"exercise":"做操","hand":"隔间递手","leak":"渗水","rite":"仪式","feast":"盛宴","chalk":"黑板","roster":"名单","raindots":"雨点成字","stare":"目光"}
	for spec: Dictionary in fixture["scenarios"]:
		if not names.has(spec["kind"]) or int(spec["tier"])!=2: continue
		var room: Variant=null if spec["scene"]=="out" else CampusData.layout(spec["scene"])
		var at:=CampusGeometry.to_scene(room,Vector2(spec["me"]["x"],spec["me"]["y"]))
		var data: Dictionary=spec["data"].duplicate(true)
		if spec["kind"]=="hand": data["src"]=spec["source"]
		data["scene"]=spec["scene"]
		app.travel(spec["scene"],{"position":[at.x,0,at.y],"yaw":CampusGeometry.yaw_from_ang(spec["ang"]),"pitch":-.3},false)
		data["chosen"]=null
		var seconds:=8 if spec["kind"]=="raindots" else 2
		app.anomaly().an.merge({"id":spec["kind"],"active":true,"t":float(seconds),"acc":1.7,"data":data},true)
		var cw:=app._campus_world()
		cw.anomaly_fx.visual_seed=42
		for frame in seconds*60:
			cw.anomaly_fx.update(1.0/60,app.anomaly().an,room,spec["scene"],app.player.position,Vector2.from_angle(spec["ang"]))
		match spec["kind"]:
			"exercise":
				app.player.restore_pose({"position":[at.x,0,at.y+6],"yaw":0.0,"pitch":-.12})
			"feast":
				app.player.restore_pose({"position":[at.x,0,at.y-3],"yaw":PI,"pitch":-.2})
			"rite": app.player.restore_pose({"position":[at.x,0,at.y],"yaw":CampusGeometry.yaw_from_ang(0),"pitch":-.45})
			"chalk","roster":
				var face:=AnomalyProps.wall_face(room,app.player.position)
				var pos: Vector3=face["p"]+face["n"]*3
				var look: Vector3=-face["n"]
				app.player.restore_pose({"position":[pos.x,0,pos.z],"yaw":CampusGeometry.yaw_from_ang(atan2(look.z,look.x)),"pitch":0})
			"hand": app.player.set_pitch(-1.0)
			"raindots": app.player.set_pitch(-.55)
		cw.lighting.update(0,app.school().tsec,app.player.camera)
		app._school_step(0,app.campus())
		app.ui.show_runtime(app.session.clock.active_seconds)
		app.ui.show_notice("")
		app.ui.show_prompt("")
		await _shot("异象-"+names[spec["kind"]])
		app.anomaly().end_now()
	app.return_to_menu()
	app.queue_free()
	await process_frame
	quit()
