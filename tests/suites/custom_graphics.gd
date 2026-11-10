extends "res://tests/support/test_suite.gd"


func test_storage() -> void:
	for q in 5:
		var migrated:=GameSettings.normalize({"quality":q})
		check(migrated.quality==q and GraphicsProfile.from_values(migrated)==GraphicsProfile.preset(q),"legacy preset %d expands into its original independent parameters" % q)
	check(GameSettings.normalize({})==GameSettings.DEFAULTS,"new defaults match the original 精细 preset")
	var path:=_test_path.get_base_dir()+"/custom-graphics/settings.json"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify({"version":1,"values":{"quality":3,"mouse":125}}))
	var settings:=GameSettings.new(path)
	settings.load_file()
	check(settings.get_int("model_detail")==3 and settings.get_int("msaa")==2 and settings.get_int("mouse")==125,"v1 file migration preserves quality and comfort")
	settings.set_value("fps_limit",93)
	settings.set_value("vsync",0)
	settings.set_value("render_scale",85)
	settings.set_value("model_detail",0)
	settings.set_value("lighting_detail",4)
	check(settings.get_int("quality")==GraphicsProfile.CUSTOM and settings.get_int("model_detail")==0 and settings.get_int("lighting_detail")==4,"custom graphics separate models from lighting")
	settings.save_file()
	var loaded:=GameSettings.new(path)
	loaded.load_file()
	check(same_json(loaded.values,settings.values),"all custom values and frame pacing survive reload")
	settings.set_value("quality",1)
	check(settings.graphics()==GraphicsProfile.preset(1) and settings.get_int("fps_limit")==93 and settings.get_int("vsync")==0,"preset selection replaces graphics while retaining the frame cap and VSync")
	settings.set_value("quality",GraphicsProfile.CUSTOM)
	check(settings.graphics()==GraphicsProfile.preset(1),"selecting custom preserves the current graphics values")
	var invalid:=GameSettings.normalize({"quality":5,"render_scale":999,"fps_limit":1,"msaa":9,"model_detail":-1,"ssao":INF,"glow":NAN,"bogus":12})
	check(invalid.render_scale==150 and invalid.fps_limit==20 and invalid.msaa==0 and invalid.model_detail==2 and invalid.ssao==1 and invalid.glow==1 and not invalid.has("bogus"),"graphics values reject nonfinite numbers and clamp unsafe or invalid input")
	check(GameSettings.normalize({"fps_limit":0}).fps_limit==0,"zero remains an unlimited frame cap")
	var touch:=GameSettings.new(path+"-fresh","Android")
	touch.load_file(true)
	check(touch.graphics()==GraphicsProfile.preset(0) and touch.get_int("full_screen")==1,"fresh touch profiles expand 流畅 and retain Android fullscreen")


func test_render_controls() -> void:
	var vp:=SubViewport.new()
	root.add_child(vp)
	var options:=GraphicsProfile.preset(0)
	options.render_scale=85
	options.msaa=1
	options.shadow_resolution=1
	options.lod_detail=3
	options.fxaa=1
	RenderQuality.apply(vp,0,false,options)
	check(is_equal_approx(vp.scaling_3d_scale,.85) and vp.msaa_3d==Viewport.MSAA_2X and vp.positional_shadow_atlas_size==1024 and vp.mesh_lod_threshold==.5,"resolution, AA, shadow atlas and LOD are independent of the preset")
	check(vp.scaling_3d_mode==Viewport.SCALING_3D_MODE_FSR and vp.screen_space_aa==Viewport.SCREEN_SPACE_AA_DISABLED,"FSR works below native resolution and FXAA does not stack with MSAA")
	options.msaa=0
	RenderQuality.apply(vp,0,true,options)
	check(vp.scaling_3d_mode==Viewport.SCALING_3D_MODE_BILINEAR and vp.screen_space_aa==Viewport.SCREEN_SPACE_AA_DISABLED,"Mobile keeps supported scaling and the FXAA workaround")
	var light:=CampusLighting.new()
	root.add_child(light)
	light.options=options
	light.setup("teach1",CampusData.layout("teach1"),null,0)
	var camera:=Camera3D.new()
	root.add_child(camera)
	options.sun_shadows=1
	options.lamp_shadows=2
	options.ssao=3
	options.glow=1
	options.volumetric_fog=1
	light.options=options
	var old_mobile:=CampusLighting.mobile_renderer
	var actual_mobile:=RenderingServer.get_current_rendering_method()=="mobile"
	CampusLighting.mobile_renderer=actual_mobile
	light.apply_quality(camera)
	light.update(0,700,camera)
	light._pick_shadow_lamps(camera)
	check(light.sun_light.shadow_enabled and light.shadow_lamps()==2 and light.env.ssao_enabled==not actual_mobile and light.env.glow_enabled==not actual_mobile and light.env.volumetric_fog_enabled==not actual_mobile,"lighting detail zero can independently enable supported shadows and post effects")
	CampusLighting.mobile_renderer=true
	light.apply_quality(camera)
	check(not light.env.ssao_enabled and not light.env.glow_enabled and not light.env.volumetric_fog_enabled and light.options.ssao==3,"unavailable Mobile effects stay disabled without losing stored preferences")
	options.shadow_resolution=0
	light.options=options
	light.apply_quality(camera)
	check(light.shadow_lamps()==0 and light.sun_light.shadow_enabled,"disabling positional shadows does not disable the independently selected sun shadow")
	CampusLighting.mobile_renderer=old_mobile
	var post:=ScenePost.new()
	post.quality=0
	post.render_options=options.merged({"post_detail":1,"bloom":23,"grain_strength":35},true)
	post.tick(0)
	var mat:=post.material as ShaderMaterial
	check(not mat.get_shader_parameter("lite") and is_equal_approx(mat.get_shader_parameter("bloom"),.23) and is_equal_approx(mat.get_shader_parameter("grain"),.35),"post precision, halo and grain strength do not follow model detail")
	post.free()
	light.queue_free()
	camera.queue_free()
	vp.queue_free()
	await _frames(1)


func test_app() -> void:
	var old_cap:=Engine.max_fps
	var physics_rate:=Engine.physics_ticks_per_second
	var time_scale:=Engine.time_scale
	var app: GameApp=APP.instantiate()
	app.saves=SaveStore.new(_test_path.get_base_dir()+"/custom-graphics-app/slot.json")
	app.settings=GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	app.start_new_game("hard","none")
	if app._opening_cut!=null and app._opening_cut.on: app._opening_cut.end(true)
	else: app.ui._end_opening(true)
	app.set_process(false)
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app.debug_flow.set_process(false)
	var saved:=app.session.capture(app.player.capture_pose()).duplicate(true)
	var world:=app._campus_world()
	var collision:=world.get_node("Collision").get_instance_id()
	app._setting_changed("model_detail",0)
	var model:=world.get_node("Model").get_instance_id()
	app._setting_changed("lighting_detail",3)
	app._setting_changed("ssao",0)
	app._setting_changed("render_scale",80)
	app._setting_changed("lamp_shadows",0)
	app._setting_changed("torch_shadows",0)
	check(world.visual_tier==0 and world.material_quality()==3 and world.get_node("Model").get_instance_id()==model,"lighting, post and resolution edits retain the independently chosen model")
	check(world.get_node("Collision").get_instance_id()==collision and same_json(saved,app.session.capture(app.player.capture_pose())),"graphics editing preserves physics, player pose and the complete gameplay snapshot")
	check(not world.lighting.env.ssao_enabled and not app.player.camera.get_node("Torch").shadow_enabled and is_equal_approx(root.scaling_3d_scale,.8),"custom preferences reach the live environment, torch and viewport")
	app._setting_changed("fps_limit",93)
	app._setting_changed("vsync",0)
	check(Engine.max_fps==93 and Engine.physics_ticks_per_second==physics_rate and Engine.time_scale==time_scale and world.get_node("Model").get_instance_id()==model and same_json(saved,app.session.capture(app.player.capture_pose())),"a frame-cap change preserves simulation rate, graphics and gameplay")
	app.travel("lab1",app.campus().default_spawn("lab1"),false)
	world=app._campus_world()
	check(world.visual_tier==0 and world.render_options.lighting_detail==3 and not world.lighting.env.ssao_enabled and world.anomaly_fx.particle_quality==2,"new worlds inherit the complete custom configuration before building")
	var live:=app.anomaly().capture().duplicate(true)
	var fake:={"active":true,"id":"rain","data":{},"t":1.0}
	world.anomaly_fx.update(0,fake,world.layout,"lab1",Vector3.ZERO,Vector2.RIGHT)
	app._setting_changed("particle_detail",0)
	world.anomaly_fx.update(0,fake,world.layout,"lab1",Vector3.ZERO,Vector2.RIGHT)
	check(world.anomaly_fx._extra.rain._seeds.size()==WeatherFx.RAIN_COUNTS[0] and same_json(live,app.anomaly().capture()),"live particle changes rebuild presentation without changing the anomaly module")
	app.return_to_menu()
	var stage:=ArchiveStage.new()
	app.add_child(stage)
	var replay_error:=stage.begin({"stage":"lab1","fx":"vignette"},app.router.worlds,app.ui,app.settings,true)
	var replay_world:=stage.router.world_instance() as CampusWorld
	check(replay_error.is_empty() and replay_world.render_options==app.settings.graphics() and not replay_world.lighting.env.ssao_enabled and not stage.player.camera.get_node("Torch").shadow_enabled,"isolated archive replay inherits custom rendering and torch preferences")
	stage.cancel()
	stage.queue_free()
	app.ui.set_mode("menu")
	app._setting_changed("quality",2)
	check(app.settings.graphics()==GraphicsProfile.preset(2) and Engine.max_fps==93,"returning to a preset preserves the user's frame cap")
	app._setting_changed("fps_limit",0)
	app._setting_changed("vsync",1)
	app.queue_free()
	await _frames(2)
	Engine.max_fps=old_cap


func test_panel() -> void:
	var old_size:=root.size
	var old_cap:=Engine.max_fps
	var app: GameApp=APP.instantiate()
	app.saves=SaveStore.new(_test_path.get_base_dir()+"/custom-graphics-ui/slot.json")
	app.settings=GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	app.ui.settings_requested.emit()
	var panel:=app.ui.settings_panel
	for section in ["显示","细节","光影","后期"]:
		panel.select_graphics_section(section)
		check(panel._graphics_boxes[section].visible,"graphics section %s is available" % section)
	panel.select_graphics_section("显示")
	var spin: SpinBox=panel.controls.fps_limit
	var spin_id:=spin.get_instance_id()
	spin.value=77
	check(app.settings.get_int("fps_limit")==77 and Engine.max_fps==77 and panel.controls.fps_limit.get_instance_id()==spin_id,"numeric FPS entry applies and preserves its editing widget")
	panel.find_child("Fps_0",true,false).pressed.emit()
	check(Engine.max_fps==0 and app.settings.get_int("fps_limit")==0,"the unlimited shortcut clears the cap")
	panel.select_graphics_section("细节")
	panel.controls.render_scale.value=85
	check(app.settings.get_int("quality")==5 and panel.controls.quality[5].button_pressed,"an individual control selects the custom indicator")
	panel.mobile_renderer=true
	panel.set_values(app.settings.values)
	check(panel.controls.glow.disabled and panel.controls.ssao[3].disabled and panel.controls.upscaler[1].disabled,"Mobile UI explains and disables unavailable effects")
	panel.mobile_renderer=RenderingServer.get_current_rendering_method()=="mobile"
	for size in [Vector2i(960,540),Vector2i(1280,800),Vector2i(2340,1080)]:
		root.size=size
		app._setting_changed("text",150)
		await _frames(3)
		for section: String in panel._graphics_buttons:
			check(panel.scroll.get_global_rect().size.x>=panel._graphics_buttons[section].get_global_rect().size.x,"graphics tabs fit landscape %s with enlarged text" % size)
		check(root.get_visible_rect().encloses(panel.shell.get_global_rect()) and root.get_visible_rect().encloses(panel._close.get_global_rect()),"settings and Done remain reachable at %s" % size)
	app._setting_changed("text",100)
	app._setting_changed("quality",2)
	app.queue_free()
	await _frames(2)
	root.size=old_size
	Engine.max_fps=old_cap
