extends "res://tests/support/test_suite.gd"

func original_data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_bytes("res://tests/fixtures/scene_audio-reference.json.gz").decompress_dynamic(1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8())

func compare_frame(mood: AtmosModule, expected: Dictionary, played: Array, faded: Array, label: String) -> void:
	for event: Dictionary in mood.take_events():
		if event["kind"]=="dread":
			check(event.get("owner")=="atmos.scene",label+" only scene sounds receive the scene owner")
			played.append(event["cue"])
		elif event["kind"]=="scene_stop": faded.assign(played)
	var state := {"event":mood.scene_event().get("kind",""),"plays":played,"fades":faded,"lamp":mood.lamp_mul().get(0,1.0)}
	check(same_json(state,expected),label+" original scene lifetime: "+str(state))

func test_reference() -> void:
	var rooms := CampusData.rooms()
	var room := CampusData.layout("teach1")
	for sample: Dictionary in original_data()["cases"]:
		var mood := AtmosModule.new(rooms)
		var ctx := _atmos_ctx(20,18,{"age":100,"dread":DreadModule.new(rooms),"lamps":[CampusGeometry.tile_center(room,30,18)]})
		mood.set_context(ctx)
		var action: String = sample["action"]
		if action.begins_with("door_"):
			for seed in 100:
				mood._rng.seed = seed
				mood.door_action("teach1",10,15,false)
				if not mood.scene_event().is_empty(): break
			check(not mood.scene_event().is_empty(),"door fixture reaches the original chance-gated reply")
		else: check(mood._scene_lamp(),"lamp fixture starts through the actual eligible rule")
		var played := []
		var faded := []
		compare_frame(mood,sample["frames"][0],played,faded,action+" start")
		match action:
			"complete":
				for _i in 12: mood._scene_tick(.25)
				compare_frame(mood,sample["frames"][1],played,faded,action+" move")
				for _i in 16: mood._scene_tick(.25)
				compare_frame(mood,sample["frames"][2],played,faded,action+" end")
			"door_answer":
				for _i in 6: mood._scene_tick(.25)
				compare_frame(mood,sample["frames"][1],played,faded,action+" answer")
				ctx["busy"] = true
				mood._scene_tick(.1)
				compare_frame(mood,sample["frames"][2],played,faded,action+" cancel after event ended")
			"door_reopen":
				mood.door_action("teach1",10,15,true)
				compare_frame(mood,sample["frames"][1],played,faded,action)
			_:
				if action=="busy":
					ctx["busy"] = true
					mood._scene_tick(.1)
				elif action=="leave": mood.enter("lab1")
				else: mood.cancel_scene()
				compare_frame(mood,sample["frames"][1],played,faded,action)
		mood.cancel_scene()
		check(mood.take_events().is_empty(),"scene cancellation is idempotent")

func test_voices() -> void:
	var audio := AudioFx.new()
	root.add_child(audio)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	for spatial in [false,true]:
		audio.play("dread.hum",{"owner":"atmos.scene","pan":.4 if spatial else 0.0})
		var index := posmod((audio._next3 if spatial else audio._next)-1,AudioFx.POOL_3D if spatial else AudioFx.POOL)
		var voice: Node = audio._pool3[index] if spatial else audio._pool[index]
		var volume: float = voice.volume_db
		audio.play("scene.engine")
		var other := audio._pool[posmod(audio._next-1,AudioFx.POOL)]
		var other_volume := other.volume_db
		audio.fade_owned("atmos.scene")
		check(audio._voice_fades.size()==1 and audio._voice_fades.has(voice),"cancellation owns only the scene voice, including spatial playback")
		(audio._voice_fades[voice] as Tween).custom_step(.04)
		check(absf(voice.volume_db-volume+20.0/log(10))<.001 and other.volume_db==other_volume,"one original fade time constant attenuates only its own voice by 8.686 dB")
		paused = true
		await _frames(24)
		paused = false
		check(not voice.playing and other.playing and audio._voice_fades.is_empty(),"scene sound finishes fading while the game is paused; unrelated sound survives")
		audio.stop_all()
		audio.play("dread.hum",{"owner":"atmos.scene","pan":.4 if spatial else 0.0})
		index = posmod((audio._next3 if spatial else audio._next)-1,AudioFx.POOL_3D if spatial else AudioFx.POOL)
		voice = audio._pool3[index] if spatial else audio._pool[index]
		audio.fade_owned("atmos.scene")
		if spatial: audio._next3 = index
		else: audio._next = index
		audio.play("event.bellStart",{"pan":.4 if spatial else 0.0})
		volume = voice.volume_db
		await _frames(24)
		check(voice.playing and voice.volume_db==volume and audio._voice_fades.is_empty(),"pool reuse revokes the old fade before a new sound starts")
		audio.stop_all()
	audio.play("dread.hum",{"owner":"atmos.scene","at":1})
	audio.play("event.bellStart",{"at":1})
	audio.fade_owned("atmos.scene")
	check(audio._delayed.size()==1 and audio._delayed[0][1]=="event.bellStart","cancellation removes only the owner's scheduled sounds")
	audio.play("dread.hum",{"owner":"atmos.scene"})
	audio.fade_owned("atmos.scene")
	audio.stop_all()
	check(audio._voice_fades.is_empty() and audio._delayed.is_empty(),"session cleanup revokes fades and delayed plays")
	audio.queue_free()
	camera.queue_free()
	await _frames(2)

func test_app() -> void:
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new(_test_path.get_base_dir()+"/scene-audio/slot.json")
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	await _frames(2)
	app.wuda_roll = func() -> float: return 1
	app.start_new_game("hard","none")
	app.set_process(false)
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app._stand_up()
	for boundary in ["pause","travel"]:
		app.atmos().reset()
		app.atmos().set_context(_atmos_ctx(20,18,{"age":100,"dread":DreadModule.new(CampusData.rooms()),"lamps":[CampusGeometry.tile_center(CampusData.layout("teach1"),30,18)]}))
		check(app.atmos()._scene_lamp(),"formal app can start a lamp scene")
		app._apply_atmos_events()
		check(app.audio.played.back()=="dread.hum","formal app routes the scene sound")
		if boundary=="pause": app.pause_game()
		else: app.travel("lab1",_campus_pose(CampusData.layout("lab1"),CampusGeometry.tile_center(CampusData.layout("lab1"),20,18),0),false)
		check(app.atmos().scene_event().is_empty() and not app.audio._voice_fades.is_empty(),boundary+" cancels the rule and starts its audio fade immediately")
		await _frames(24)
		check(app.audio._voice_fades.is_empty(),boundary+" completes the owned fade")
		if boundary=="pause":
			check(app._campus_world().lighting.lamp_mul.is_empty(),"pause restores the lamp multiplier")
			app.resume_game()
	app.return_to_menu()
	app.queue_free()
	await _frames(2)
