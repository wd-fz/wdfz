extends SceneTree
## Real Vulkan screenshots: godot --path . --script res://tools/capture/capture_death.gd -- patrol garage ...
## No progression/save changes: isolated hard-mode game, simulation frozen, presentation-only stages.
## Output: build/previews/deathcg/<scene>-<1..4>.png at 25 / 58 / 81 / 87 percent (87: the closest moment before the veil).
## With "archive" as the first argument the isolated sets of the archive replay are shot instead of the live
## in-place deaths (same causes; output deathcg/archive-<scene>-<n>.png).
const APP := preload("res://game/app/app.tscn")

func _initialize() -> void:
	call_deferred("_run")

func _shot(name: String) -> void:
	for _i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/deathcg/%s.png" % name)

func _run() -> void:
	root.size=Vector2i(1280,720)
	var app: GameApp=APP.instantiate()
	app.saves=SaveStore.new("user://deathcg-preview/slot.json")
	app.settings=GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/previews/deathcg")
	app.start_new_game("hard","none")
	if app._opening_cut!=null and app._opening_cut.on: app._opening_cut.end(true)
	else: app.ui._end_opening(true)
	for _i in 8: await process_frame
	app._stand_up()
	app.set_process(false)
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app.player.enabled=false
	app.ui.cut_mode(true)
	app.player.set_pitch(0)
	var which: Array=OS.get_cmdline_user_args()
	var archive: bool = not which.is_empty() and which[0]=="archive"
	if archive: which=which.slice(1)
	if which.is_empty(): which=DeathCG.CAUSES
	for cause: String in which:
		if not DeathCG.has(cause):
			push_error("Unknown death scene: "+cause)
			quit(1)
			return
		if archive:
			app._stop_death_cg()
			app._death_cg=DeathCG.new()
			app.add_child(app._death_cg)
			app._death_cg.begin(cause,app.player,app._campus_world(),app.ui,DeathCG.duration(cause,4.8))
		else: app._start_death_cg(cause)
		var cg:=app._death_cg
		if cg==null:
			push_error("A real display is required for death captures")
			quit(1)
			return
		var n:=0
		for fraction: float in [.25,.58,.81,.87]:
			n+=1
			cg.k=cg.dur*fraction
			cg.update(cg.k)
			await _shot("%s%s-%d" % ["archive-" if archive else "",cause,n])
		app._stop_death_cg()
		for _i in 2: await process_frame
		print("CAPTURED: "+cause)
	app.return_to_menu()
	app.queue_free()
	for _i in 3: await process_frame
	quit()
