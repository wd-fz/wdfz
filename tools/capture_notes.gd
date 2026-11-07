extends SceneTree
## The notes page (needs a display): godot --path . --script res://tools/capture_notes.gd
## Output: build/previews/notes/. After the parking ticket, the handover note and the guard's register.

const APP := preload("res://scenes/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://notes-preview/unused.json")
	app.settings = GameSettings.new("user://notes-preview/settings.json")
	root.add_child(app)
	await process_frame
	app.start_new_game()
	for _i in 5:
		await process_frame
	app.patrol().pat["safety"] = 999.0
	app._lesson_press()
	app._invest_do(func(inv: InvestigationModule) -> void: inv.notice())
	app.ui.hide_choice()
	app._record({"id": "parking", "text": "停车登记：可用车辆在车库靠西侧，第 3 排。记录的签名与教室停车单相同，离校栏却始终空着。", "kind": "事实", "source": "保安岗 · 停车登记"})
	app._record({"id": "checkupForm", "text": "体检表：身高「—」，心率「0」，医生意见「合格」。", "kind": "线索", "source": "行政楼一楼医务室"})
	app._show_notes("")
	DirAccess.make_dir_recursive_absolute("res://build/previews/notes")
	for _i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/notes/notes.png")
	quit()
