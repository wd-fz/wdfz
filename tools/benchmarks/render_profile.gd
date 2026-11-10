extends SceneTree
## Real Vulkan, wall-time ablation benchmark. Never uses --fixed-fps for performance claims.
const APP:=preload("res://game/app/app.tscn")
var app: GameApp
var result: Dictionary={}
var output:="res://build/reports/render-profile/profile.json"
var samples:=8
var reference:=false
var scene_id:="teach1"

func _initialize() -> void: call_deferred("_run")

func _frames(count: int) -> void:
	for _i in count: await RenderingServer.frame_post_draw

func _stats(values: Array[float]) -> Dictionary:
	var ordered:=values.duplicate()
	ordered.sort()
	var sum:=0.0
	for value in values: sum+=value
	return {"mean":sum/maxi(1,values.size()),"median":ordered[ordered.size()/2],"p95":ordered[mini(ordered.size()-1,ceili(ordered.size()*.95)-1)]}


func _pipelines() -> int:
	var count:=0
	for monitor in [Performance.PIPELINE_COMPILATIONS_CANVAS,Performance.PIPELINE_COMPILATIONS_MESH,Performance.PIPELINE_COMPILATIONS_SURFACE,Performance.PIPELINE_COMPILATIONS_DRAW,Performance.PIPELINE_COMPILATIONS_SPECIALIZATION]:
		count+=int(Performance.get_monitor(monitor))
	return count

func _measure(id: String) -> void:
	await _frames(12)
	var warmup:=12
	var stable:=0
	var compiled:=_pipelines()
	while stable<4 and warmup<36:
		await _frames(1)
		var count:=_pipelines()
		stable=stable+1 if count==compiled else 0
		compiled=count
		warmup+=1
	var wall: Array[float]=[]
	var gpu: Array[float]=[]
	var cpu: Array[float]=[]
	var draw: Array[float]=[]
	var primitives: Array[float]=[]
	var start:=Time.get_ticks_usec()
	for _i in samples:
		await RenderingServer.frame_post_draw
		var now:=Time.get_ticks_usec()
		wall.append((now-start)/1000.0)
		start=now
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
		draw.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var entry:={"wall_ms":_stats(wall),"gpu_ms":_stats(gpu),"render_cpu_ms":_stats(cpu),"draw_calls":_stats(draw),"primitives":_stats(primitives)}
	entry["warmup_frames"]=warmup
	entry["pipeline_compilations_during_samples"]=_pipelines()-compiled
	result["cases"][id]=entry
	print("PROFILE ",id," ",JSON.stringify(entry))
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"  "))

func _inventory() -> Dictionary:
	var world:=app._campus_world()
	var groups:={}
	for child: Node in world.get_children():
		if child is Node3D:
			var meshes:=child.find_children("*","MeshInstance3D",true,false)
			var multi:=child.find_children("*","MultiMeshInstance3D",true,false)
			groups[String(child.name)]={"meshes":meshes.size(),"multimeshes":multi.size(),"visible":child.visible}
	return {"groups":groups,"lights":world.find_children("*","Light3D",true,false).size(),"room_lights":world.lighting.room_lights.size(),"window_lights":world.lighting.window_lights.size(),"nodes":world.find_children("*","Node",true,false).size()}

func _run() -> void:
	if DisplayServer.get_name()=="headless" or RenderingServer.get_current_rendering_driver_name()!="vulkan":
		printerr("Render profiling requires a real Vulkan window; headless cannot measure graphics performance.")
		quit(1)
		return
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty(): output=args[0]
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	reference="--reference" in args
	CampusBatches.enabled=not reference
	var quality:=2
	for arg in args:
		if arg.begins_with("--scene="): scene_id=arg.trim_prefix("--scene=")
		if arg.begins_with("--quality="): quality=clampi(int(arg.trim_prefix("--quality=")),0,4)
		if arg.begins_with("--samples="): samples=maxi(4,int(arg.trim_prefix("--samples=")))
	root.size=Vector2i(960,540)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=0
	app=APP.instantiate()
	app.saves=SaveStore.new("user://render-profile/%s/slot.json" % OS.get_process_id())
	app.settings=GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	await process_frame
	app.start_new_game("hard","none")
	if app._opening_cut!=null and app._opening_cut.on: app._opening_cut.end(true)
	else: app.ui._end_opening(true)
	app.set_process(false)
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app.debug_flow.set_process(false)
	app.debug_flow.collision_view=false
	app.debug_flow.probe.clear()
	app._setting_changed("quality",quality)
	app.classmates().set_seed("render-profile-v1")
	app.school().tsec=700
	app._stand_up()
	var pose: Dictionary={}
	if scene_id=="out":
		var point:=CampusGeometry.to_scene(null,Vector2(1077.5,2060))
		pose={"position":[point.x,.05,point.y],"yaw":CampusGeometry.yaw_from_ang(-PI*.5),"pitch":0.0}
	else:
		pose=app.campus().start_pose() if scene_id=="teach1" else app.campus().default_spawn(scene_id)
	app.travel(scene_id,pose,false)
	app.player.reset_view()
	app._school_step(0,app.campus())
	app.ui.scene_post().tick(0)
	if reference:
		root.use_occlusion_culling=false
		(app.ui.scene_post().material as ShaderMaterial).shader=ScenePost.BLUR_SHADER
	var world:=app._campus_world()
	var lighting:=world.lighting
	lighting.time=0
	lighting.update(0,700,app.player.camera)
	lighting._pick_shadow_lamps(app.player.camera)
	lighting._pick_shadow_windows(app.player.camera)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	result={"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),"device":RenderingServer.get_video_adapter_name(),"reference":reference,"scene":scene_id,"quality":quality,"resolution":[960,540],"samples":samples,"inventory":_inventory(),"batches":world.get_node("Model").get_meta("render_batches",{}),"cells":world.get_node("Model").get_meta("render_cells",0),"camera":{"position":str(app.player.camera.global_position),"rotation":str(app.player.camera.global_rotation)},"cases":{}}
	await _measure("baseline")
	root.get_texture().get_image().save_png(output.get_basename()+".png")
	if "--quick" in args:
		app.return_to_menu()
		app.queue_free()
		await _frames(3)
		quit()
		return
	var post:=app.ui.scene_post()
	post.hide()
	await _measure("post_off")
	post.show()
	lighting.env.ssao_enabled=false
	await _measure("ssao_off")
	lighting.apply_quality()
	lighting.env.glow_enabled=false
	await _measure("glow_off")
	lighting.apply_quality()
	lighting.update(0,700,app.player.camera)
	lighting._pick_shadow_lamps(app.player.camera)
	lighting._pick_shadow_windows(app.player.camera)
	var shadows: Array[Light3D]=[]
	for light: Light3D in app.find_children("*","Light3D",true,false):
		if light.shadow_enabled: shadows.append(light); light.shadow_enabled=false
	await _measure("shadows_off")
	for light: Light3D in shadows: light.shadow_enabled=true
	var previews: Array[Node3D]=[]
	for model: Node3D in world._visual_models():
		if model.name!="Model" and model.visible: previews.append(model); model.hide()
	await _measure("previews_off")
	for model: Node3D in previews: model.show()
	if is_instance_valid(app._mates_nodes): app._mates_nodes.hide()
	await _measure("people_off")
	if is_instance_valid(app._mates_nodes): app._mates_nodes.show()
	var lights: Array[Light3D]=[]
	for light: Light3D in world.find_children("*","Light3D",true,false):
		if light.visible: lights.append(light); light.hide()
	await _measure("lights_off")
	for light: Light3D in lights: light.show()
	var scale:=root.scaling_3d_scale
	root.scaling_3d_scale=scale*.5
	await _measure("half_3d_resolution")
	root.scaling_3d_scale=scale
	root.disable_3d=true
	await _measure("disable_3d")
	root.disable_3d=false
	app.return_to_menu()
	app.queue_free()
	await _frames(3)
	quit()
