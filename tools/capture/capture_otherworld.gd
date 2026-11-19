extends SceneTree
## Capture the actual campus actors and saved event clock at fixed viewpoints.
## Set WDFZ_MOTION=1 to also capture the frame sequences for the animated comparison.
const OUT := "res://build/previews/otherworld/"
const STEP := .12
var app: GameApp
var cam: Camera3D
var motion := OS.get_environment("WDFZ_MOTION") == "1"


func _initialize() -> void: call_deferred("_run")


func shot(id: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+id+".png")


func angle(from: Vector3, toward: Vector3) -> void:
	cam.global_position = from
	cam.look_at(toward)


func classroom(room: Dictionary) -> void:
	var kids := app._mates_nodes
	var pupil: OtherworldFigure
	var teacher: OtherworldFigure
	for d: Dictionary in kids.figures:
		if d.teacher: teacher = d.actor
		elif d.node.get_meta("cls") == "teach1:3":
			var chair := CampusGeometry.to_world(room,d.home.x,d.home.y)
			var col := floori((chair.x-room.ox)/room.tw)
			var row := floori((chair.y-room.oy)/room.th)
			if pupil==null or (col==49 and row==10): pupil = d.actor
	var eye := pupil.face.global_position+Vector3.UP*.11
	var near := eye-pupil.global_basis.z*1.33+pupil.global_basis.x*.37+Vector3.UP*.12
	angle(near,eye-Vector3.UP*.07)
	var view := (kids.to_local(near))
	var at := CampusGeometry.to_world(room,view.x,view.z)
	for i in 37:
		kids.advance(STEP,at,0,null,false,false,null)
		if i==16: await shot("pupil")
		if motion: await shot("desk-%02d" % i)
	eye = teacher.face.global_position+Vector3.UP*.14
	angle(eye-teacher.global_basis.z*1.58+teacher.global_basis.x*.22-Vector3.UP*.34,eye-Vector3.UP*.21)
	await shot("teacher")


func corridor(world: CampusWorld, room: Dictionary, feet: Vector3) -> void:
	var at := Vector2(feet.x,feet.z)
	var forward := feet+Vector3.RIGHT
	world.show_patrol(true,at,0,forward,"search",0)
	var patrol := world._patrol_figure
	var eye := patrol.face.global_position+Vector3.UP*.16
	angle(eye-patrol.global_basis.z*2.25+patrol.global_basis.x*.49-Vector3.UP*.58,eye-Vector3.UP*.42)
	for i in 37:
		world.show_patrol(true,at,0,forward,"search" if i<27 else "chase",STEP)
		if i==9: await shot("patrol")
		if motion: await shot("search-%02d" % i)
	world.show_patrol(false,at,0,forward)
	for id: String in ["chalk","roster"]:
		var data := {"active":true,"id":id,"t":5.1,"data":{"scene":"teach1","until":832.0}}
		world.anomaly_fx.update(.1,data,room,"teach1",feet,Vector2.RIGHT,Vector3.INF,false,"xu")
		var props: AnomalyProps = world.anomaly_fx._extra.original
		var panel := props._writing
		var distance := 2.62 if id=="chalk" else 1.70
		angle(panel.global_position+panel.global_basis.z*distance+panel.global_basis.x*.11,panel.global_position)
		await shot(id)


func playing_field() -> void:
	var field: Dictionary = CampusData.layout("out").objects.filter(func(o: Dictionary) -> bool: return o.id=="field")[0]
	var at := CampusGeometry.to_scene(null,Vector2(field.x+field.w*.50,field.y+field.h*.55)*float(CampusData.campus().SC))
	var feet := Vector3(at.x,0,at.y)
	cam.reparent(root,true)
	app.travel("out",{"position":[feet.x,feet.y,feet.z],"yaw":0.0,"pitch":0.0},false)
	var world := app._campus_world()
	cam.reparent(world,true)
	cam.make_current()
	if is_instance_valid(app.router.resident): app.router.resident.update_view(feet)
	var spot := CampusGeometry.to_world(null,feet.x,feet.z)
	var event := {"active":true,"id":"exercise","t":0.0,"data":{"src":{"x":spot.x,"y":spot.y}}}
	var from := feet+Vector3(1.25,1.67,-7.55)
	angle(world.to_global(from),world.to_global(feet+Vector3.UP*1.27))
	for i in 37:
		event.t = float(i)*STEP
		world.anomaly_fx.update(STEP,event,null,"out",from-Vector3.UP*1.67,Vector2.DOWN)
		if i==13: await shot("exercise")
		if motion: await shot("drill-%02d" % i)
	world.anomaly_fx.update(.1,{"active":true,"id":"shadow","t":7.0,"data":{}},null,"out",feet,Vector2.LEFT)
	var st: AnomalyProps = world.anomaly_fx._extra.original
	angle(st.global_position+Vector3(1.6,2.25,-.9),st.global_position)
	await shot("shadow")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(960,540)
	app = load("res://game/app/app.tscn").instantiate()
	app.saves = SaveStore.new("user://otherworld-capture-%d/slot.json" % Time.get_ticks_usec())
	root.add_child(app)
	await process_frame
	app.start_new_game("easy","none","xu")
	app.set_physics_process(false)
	app.set_process(false)
	app.player.set_physics_process(false)
	app._play_opening()
	app._opening_cut.set_process(false)
	app._opening_cut._apply(.64)
	await shot("lesson")
	app._opening_cut.end(true)
	app._stand_up()
	app.school().tsec = 804
	app._classmates_step(0)
	var world := app._campus_world()
	app._update_campus_lighting(world,0.0)
	app.ui.hide()
	cam = Camera3D.new()
	world.add_child(cam)
	cam.make_current()
	cam.fov = 54
	var room := CampusData.layout("teach1")
	await classroom(room)
	var point := CampusGeometry.to_scene(room,CampusGeometry.tile_center(room,43,18))
	await corridor(world,room,Vector3(point.x,0,point.y))
	await playing_field()
	app.queue_free()
	await process_frame
	quit()
