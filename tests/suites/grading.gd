extends "res://tests/support/test_suite.gd"

func _fixture() -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes("res://tests/fixtures/grading-reference.json.gz")
	return JSON.parse_string(bytes.decompress_dynamic(8*1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8())

func test_lifecycle() -> void:
	var post := ScenePost.new()
	root.add_child(post)
	post.sensory({"tunnel":.8,"drain":.6,"warp":.7},.5,31)
	post.step(1,true,10)
	post.world_normal=.5
	check(post.normal()==1 and post.sensory_active,"fake normal and the cinematic normal blend share the original maximum")
	post.reset()
	var mat := post.material as ShaderMaterial
	check(post.normal()==0 and not post.sensory_active and float(mat.get_shader_parameter("blink"))==0 and float(mat.get_shader_parameter("warp"))==0,"a lifecycle reset clears grading and low-SAN carry-over")
	post.step(.1,true,100)
	check(absf(post.fake_normal-.16)<.00001,"fake-normal colour approaches with the old dt * 1.6 coefficient")
	post.grain=false
	post.tick(0)
	check(float(mat.get_shader_parameter("grain"))==0,"grain setting reaches the same pass as the picture")
	post.queue_free()

func test_original_lighting() -> void:
	var lights := {}
	for s: Dictionary in _fixture()["light"]:
		if not lights.has(s["room"]):
			var light := CampusLighting.new()
			root.add_child(light)
			light.setup(s["room"],null if s["room"]=="out" else CampusData.layout(s["room"]),null,0)
			lights[s["room"]]=light
		var light: CampusLighting = lights[s["room"]]
		light.world_normal=s["normal"]
		light.fake_normal=s["fake"]
		light.update(0,s["t"],null)
		var equal := true
		for key: String in ["day","amb","hemi","dir","pt"]:
			equal=equal and absf(light.terms[key]-s[key])<.00001
		check(equal,"lightState matches original %s t=%s normal=%s fake=%s (%s)" % [s["room"],s["t"],s["normal"],s["fake"],light.terms])
		check(light.env.tonemap_mode==Environment.TONE_MAPPER_LINEAR and not light.env.adjustment_enabled,"world lighting leaves tone mapping to the post pass")
	for light: CampusLighting in lights.values():
		light.queue_free()
	CampusData.clear_caches()

func test_original_pixels() -> void:
	if DisplayServer.get_name()=="headless":
		return
	var f := _fixture()
	var viewport := SubViewport.new()
	viewport.size=Vector2i(f["size"],f["size"])
	viewport.disable_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var input := TextureRect.new()
	var source := Image.create_from_data(f["size"],f["size"],false,Image.FORMAT_RGBA8,PackedByteArray(f["source"]))
	input.texture=ImageTexture.create_from_image(source)
	input.size=viewport.size
	input.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	viewport.add_child(input)
	var post := ScenePost.new()
	viewport.add_child(post)
	post.parameter("grain",0.0)
	for sample: Dictionary in f["cases"]:
		for key: String in ["normal","gaze","red","hurt","drain","tunnel","blink"]:
			post.parameter(key,0.0)
		post.parameter("brightness",1.0)
		post.parameter("exposure",1.0)
		for key: String in sample["config"]:
			post.parameter(key,sample["config"][key])
		await _frames(2)
		await RenderingServer.frame_post_draw
		var result := viewport.get_texture().get_image()
		result.convert(Image.FORMAT_RGBA8)
		var data := result.get_data()
		var worst := 0
		var sum := 0.0
		for i in data.size():
			if i%4==3:
				continue
			var error := absi(int(data[i])-int(sample["pixels"][i]))
			worst=maxi(worst,error)
			sum+=error
		check(worst<=3,"original WebGL vs native post pixels %s: max=%d, mean=%.3f / 255" % [sample["config"],worst,sum/(f["size"]*f["size"]*3)])
		print("POST PIXELS: ",sample["config"]," max=",worst," /255")
	var before := viewport.get_texture().get_image()
	var screen := MazeScreen.new()
	viewport.add_child(screen)
	screen.layer=1
	screen.show_effect(1.0)
	await _frames(2)

	await RenderingServer.frame_post_draw
	var after := viewport.get_texture().get_image()
	var invert_ok := true
	for y in range(0,64,8):
		for x in range(0,64,8):
			var want := Color.WHITE-before.get_pixel(x,y)
			var got := after.get_pixel(x,y)
			invert_ok=invert_ok and absf(want.r-got.r)<.01 and absf(want.g-got.g)<.01 and absf(want.b-got.b)<.01
	check(invert_ok,"maze inversion reads the graded screen through a fresh back-buffer copy")
	viewport.queue_free()
	await _frames(2)


func test_app_transitions() -> void:
	var app: GameApp=APP.instantiate()
	app.saves=SaveStore.new(_test_path.get_base_dir()+"/grading/slot.json")
	app.settings=GameSettings.new(_test_path.get_base_dir()+"/grading/settings.json")
	root.add_child(app)
	await _frames(2)
	check(not app.ui.scene_post().visible,"menu does not run a world post pass")
	app.start_new_game("hard")
	app.set_physics_process(false)
	check(app.ui.scene_post().visible and not app.ui.sensory_on(),"healthy SAN retains base grading without low-SAN feedback")
	app.fake_normal().fn["on"]=true
	app.fake_normal().fn["v"]=71
	app._sensory_step(.5)
	check(absf(app.ui.scene_post().fake_normal-.8)<.0001,"fake-normal gameplay drives the smooth colour transition")
	app.fake_normal().fn["v"]=72
	app._sensory_step(.25)
	check(absf(app.ui.scene_post().fake_normal-.48)<.0001,"laugh threshold fades back instead of jumping abruptly")
	app._blink_plan=[1,2,3]
	app._ghost_t=.2
	app.start_new_game("hard")
	app.set_physics_process(false)
	check(app.ui.scene_post().normal()==0 and app._blink_plan.is_empty() and app._ghost_t==9.0,"new game clears prior grading and scheduled sensory transients")
	if DisplayServer.get_name()!="headless":
		app._play_opening()
		var cut := app._opening_cut
		cut.set_process(false)
		cut._apply(.3)
		check(app.ui.scene_post().world_normal==1 and app._campus_world().lighting.world_normal==1,"opening starts in the coloured normal world")
		cut._apply(.72)
		check(app.ui.scene_post().world_normal==0,"waking removes the normal-world colour before control returns")
		cut._apply(.3)
		app.return_to_menu()
		check(app.ui.scene_post().world_normal==0 and not app.ui.scene_post().visible,"abandoning the opening restores colour and stops the pass")
	app.return_to_menu()
	app.queue_free()
	await _frames(3)
	CampusData.clear_caches()
