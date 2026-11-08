class_name MazeFlow
extends Node
## Application boundary for the elevator maze. Rules never own scene nodes or timers.

var app: GameApp
var cut: MazeCut
var fx: MazeFx
var fade: WorldFade
var _fall_speed := 0.0


func setup(owner_app: GameApp) -> void:
	app = owner_app


func here() -> bool:
	return app.session != null and app.session.world_id == MazeModule.ROOM


func changed_world(restoring: bool = false) -> void:
	_cancel_respawn()
	var maze := app.maze()
	if here():
		var pose := app.player.capture_pose()
		# Entry has already selected its spawn. Loading validates saved height before physics resumes.
		if restoring or not maze.active:
			pose = maze.enter(pose, restoring and maze.active)
			app.player.restore_pose(pose)
		app.player.gravity_override = float(maze.geometry.cfg["gravity"])
		app.player.max_fall_speed = float(maze.geometry.cfg["maxFall"])
		app.player.floor_snap_length = float(maze.geometry.cfg["snap"])
		if not is_instance_valid(fx):
			fx = MazeFx.new()
			add_child(fx)
			fx.setup(app.player, app.audio)
	else:
		if maze != null:
			maze.leave()
		clear_fx()
		app.player.gravity_override = 0.0
		app.player.max_fall_speed = INF
		app.player.floor_snap_length = 0.25
	_fall_speed = 0.0


func begin_entry() -> void:
	# The entry's five SAN are settled before changing rooms, like VoidMaze.enter.
	app.school()._settle_san()
	app._handle_deaths()
	if app._dead():
		return
	var pose := app.maze().enter()
	app.travel(MazeModule.ROOM, pose, false)
	_start_cut("in", {})
	app.save_game(true) # The cinematic has chosen its clear cabin orientation; loading never replays it.


func step(dt: float) -> void:
	if not here() or app._dead():
		return
	var player := app.player
	var pose := player.capture_pose()
	app.maze().step(dt, {"feet": player.position, "dead": false, "moving": player.moving,
		"airborne": not player.is_on_floor(), "pitch": pose["pitch"], "ang": CampusGeometry.ang_from_yaw(float(pose["yaw"])), "eye": player.camera.position.y})
	for event: Dictionary in app.maze().take_events():
		if app._dead():
			break
		match event["kind"]:
			"san":
				app.school().change_san(float(event["amount"]), 0.0)
			"settle":
				if app.school().san <= 0.0:
					app.kill(String(event["text"]), String(event["fx"]), String(event["source"]))
					if not app._dead() and app.school().san <= 0.0:
						app.school().change_san(1.0, 0.0)
			"notice":
				app.ui.show_notice(event["text"])
			"sound":
				app.audio.play(event["cue"], event["options"])
			"respawn":
				_begin_respawn()
			_:
				if is_instance_valid(fx):
					fx.event(event)
	if app._dead():
		_cancel_respawn()
		clear_fx()
		return
	if player.is_on_floor() and _fall_speed < -7.0:
		app.audio.step_on("void")
		app.audio.step_on("void", 1.0, {"at": 0.05})
		app.ui.show_notice("我：重重摔在下面的平台上。还好，没掉下去。")
	_fall_speed = player.velocity.y
	if is_instance_valid(fx):
		fx.advance(dt, app.settings.get_int("shake") == 0 or app.settings.get_int("reduce_flash") != 0)


func _begin_respawn() -> void:
	if is_instance_valid(fade):
		fade.cancel()
	var run:=app.session
	var maze:=app.maze()
	app.audio.play("threat.deep")
	fade=WorldFade.new()
	add_child(fade)
	fade.begin(func() -> void:
		if app.session!=run or not here() or app._dead():
			maze.respawning=false
			return
		var result:=maze.finish_respawn()
		if result.is_empty(): return
		app.player.restore_pose(result["pose"])
		app.ui.clear_touch()
		_fall_speed=0.0
		app.ui.show_notice(result["text"])
		app.save_game(true))


func _cancel_respawn() -> void:
	if is_instance_valid(fade): fade.cancel()
	fade=null
	if app.maze()!=null: app.maze().respawning=false


func hint() -> String:
	return app.maze().hint(app.player.position, not app.player.is_on_floor(), app.items().has("chalk"))


func interact() -> void:
	var maze := app.maze()
	var exit := maze.nearby_exit(app.player.position, not app.player.is_on_floor())
	if not exit.is_empty():
		_start_cut("out", exit)
	elif maze.near_chalk(app.player.position, not app.player.is_on_floor()):
		if app.items().has("chalk"):
			app.ui.show_notice("我：地上还有半截粉笔。我身上已经有一支了。")
		elif app.items().add("chalk"):
			app.ui.show_notice("我：半截粉笔，断口很新。也许能在墙上留个记号。")
		else:
			app.ui.show_notice("背包满了。")


func intercept_item(id: String) -> bool:
	if not here() or not app.items().has(id):
		return false
	if id == "watch":
		app.ui.show_notice("我：表盘上的指针一圈一圈地转，停不下来。现在是几点？\n???")
		return true
	if id in ["map", "atlas"]:
		app.ui.show_notice("我：图上找不到这里。纸是白的。")
		return true
	return false


func _start_cut(kind: String, exit: Dictionary) -> void:
	if is_instance_valid(cut):
		return
	app.player.clear_input()
	app.player.enabled = false
	app.ui.hide_choice()
	app.ui.hide_bag()
	app.ui.clear_touch()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	cut = MazeCut.new()
	add_child(cut)
	cut.finished.connect(_cut_done.bind(kind, String(exit.get("id", ""))))
	var move := func() -> void:
		app._apply_result(app.elevator().leave_maze(String(exit.get("id", "exit1"))))
		app.save_game(true)
	cut.begin(kind, app, exit, move)


func _cut_done(kind: String, exit_id: String) -> void:
	app.archive_flow.mark_seen("cut:void_" + kind)
	if is_instance_valid(cut):
		cut.queue_free()
	cut = null
	app.resume_game()
	app.ui.show_notice("我：门外不是走廊。很黑，四周是一块块方方正正的白色墙面。身后的电梯门合上了，然后就不见了。" if kind == "in" else (
		"我：推开门，外面是另一栋楼的电梯厅。回头看，只有一扇普通的电梯门。" if exit_id == "exit2" else "我：门后是刚才的电梯厅。回过头，那只是一扇普通的电梯门。"))


func clear_fx() -> void:
	if is_instance_valid(fx):
		fx.clear_effects()
		fx.queue_free()
	fx = null


func chalk_presets() -> Array:
	var out: Array = []
	var room: Dictionary = app.campus().room(MazeModule.ROOM)
	# Old visitors' marks: tower dead end, broken bridge, western hall, looping arrows, pillar tallies.
	var spots := [[13,1.97,1.5,8,-PI/2,"x","wall"], [2.6,-32,4,0,PI,"x","floor"],[-20.6,-5,0,0,-PI/2,"q","floor"],
		[-10,28,-8,0,PI,"up","floor"],[-20,28,-8,0,PI/2,"up","floor"],[-20,36,-8,0,0,"up","floor"],[-10,36,-8,0,-PI/2,"up","floor"],
		[9.98,13.5,1.35,0,PI,"bar","wall"],[9.98,19.5,1.35,0,PI,"bar","wall"],[12.98,22.5,1.35,0,PI,"bar","wall"],[19,-36.6,4,0,-PI/2,"q","floor"]]
	for p: Array in spots:
		var w := CampusGeometry.to_world(room, p[0], p[1])
		out.append({"x":w.x,"y":w.y,"h":p[2],"f":p[3],"a":p[4],"s":p[5],"face":p[6],"old":true})
	return out


func cancel() -> void:
	_cancel_respawn()
	if is_instance_valid(cut):
		cut.cancel() # Cancellation must never perform a pending exit.
		cut.queue_free()
	cut = null
	clear_fx()
