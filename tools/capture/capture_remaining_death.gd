extends SceneTree
## Controlled elapsed-time samples in the real campus. Not a natural playthrough.
const APP:=preload("res://game/app/app.tscn")
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	root.size=Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute("res://build/previews/remaining-death")
	var app: GameApp=APP.instantiate()
	app.saves=SaveStore.new("user://capture-remaining-death/save.json")
	app.settings=GameSettings.new("user://capture-remaining-death/settings.json")
	root.add_child(app)
	await process_frame
	app.wuda_roll=func() -> float: return 1
	app.start_new_game("hard","none")
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app.debug_flow.set_process(false)
	app._stand_up()
	app.school().tsec=720
	app.travel("out",{"position":[1200/9.0,0,400/9.0],"yaw":0,"pitch":0},false)
	app._school_step(0,app.campus())
	app.ui.show_prompt("")
	app.ui.show_notice("")
	for spec: Array in [["face",2.4,"转身的人"],["slit",.6,"门缝"],["squeeze",2.8,"挤压"],["hand",1.8,"递手"]]:
		app.player.set_pitch(-.45 if spec[0]=="hand" else 0)
		app.debug_flow.preview_death(spec[0])
		app.debug_flow.preview.update(spec[1])
		for _i in 4: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/previews/remaining-death/"+spec[2]+".png")
		app.debug_flow.clear_preview()
		await process_frame
	app.return_to_menu()
	app.queue_free()
	await process_frame
	quit()
