extends "res://tests/suites/touch_ui.gd"


func test_seated_prompt() -> void:
	var app := APP.instantiate() as GameApp
	app.saves = SaveStore.new(_test_path.get_base_dir()+"/seat-prompt.json")
	app.settings = GameSettings.new(_test_path.get_base_dir()+"/seat-prompt-settings.json")
	app.settings.set_value("quality", 0)
	root.add_child(app)
	await _frames(3)
	app.ui.set_touch_enabled(true)
	app.start_new_game("hard")
	await _frames(3)
	var prompt := app.ui.get_node("%Prompt") as Label
	var wrong: Array[String] = []
	for i in 30:
		await _frames(1)
		if prompt.text != "交互 · 站起来": wrong.append(prompt.text)
	check(wrong.is_empty(), "seated prompt stays stand-up across every nearby-search refresh: %s" % str(wrong))
	check(app.school().seated, "observing the prompt never leaves the chair")
	await _tap(app.ui.get_node("%TouchInteract"))
	check(not app.school().seated and not app.player.seated, "the displayed stand-up action actually leaves the seat")
	await _frames(10)
	check(prompt.text != "交互 · 站起来", "standing restores the nearby action instead of leaving a stale seat prompt")
	app.return_to_menu()
	app.queue_free()
	await _frames(3)


func test_touch_sprint() -> void:
	var old_size := root.size
	var old_scale := root.content_scale_size
	root.size = Vector2i(1280, 720)
	var ui: GameUI = preload("res://game/presentation/ui/game_ui.tscn").instantiate()
	var player: PlayerController = preload("res://game/presentation/actors/player.tscn").instantiate()
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100, 1, 100)
	collision.shape = shape
	collision.position.y = -0.5
	floor_body.add_child(collision)
	root.add_child(floor_body)
	root.add_child(player)
	root.add_child(ui)
	await _frames(3)
	ui.touch_move.connect(player.set_touch_move)
	ui.touch_sprint.connect(player.set_touch_sprint)
	player.touch_sprint_changed.connect(ui.show_touch_sprint)
	ui.touch_look.connect(player.look_from_touch)
	player.enabled = true
	ui.set_mode("play")
	ui.set_touch_enabled(true)
	await _frames(3)
	var sprint := ui.get_node("%TouchSprint") as Button
	var stick_point := ui.stick.get_global_rect().get_center() + Vector2(0, -ui.stick.size.y * 0.4)
	await _finger(0, stick_point, true)
	await _frames(4)
	var walk_velocity := Vector2(player.velocity.x, player.velocity.z).length()
	check(player.moving and not player.sprinting and absf(walk_velocity-player.walk_speed) < 0.01,
		"full touch stick walks with sprint off (speed %.3f)" % walk_velocity)
	var button_point := sprint.get_global_rect().get_center()
	await _finger(1, button_point, true)
	await _finger(1, button_point, false)
	await _frames(3)
	var run_velocity := Vector2(player.velocity.x, player.velocity.z).length()
	check(sprint.button_pressed and player.sprinting and absf(run_velocity-player.sprint_speed) < 0.01,
		"second finger enables real sprint while first holds the stick (speed %.3f)" % run_velocity)
	check(ui.stick._finger == 0 and ui.movement_touch().length() > 0.96,
		"tapping sprint does not release or hijack the movement finger")
	await _finger(1, button_point, true)
	await _finger(1, button_point, false)
	await _frames(3)
	check(not sprint.button_pressed and not player.sprinting and absf(Vector2(player.velocity.x,player.velocity.z).length()-player.walk_speed) < 0.01,
		"second tap returns to walking even with the stick fully pushed")
	await _finger(0, stick_point, false)
	# Primary taps must still toggle exactly once (never twice through mouse emulation).
	await _tap(sprint)
	check(sprint.button_pressed and player._touch_sprint, "a primary-finger sprint tap toggles exactly once")
	await _tap(sprint)
	check(not sprint.button_pressed and not player._touch_sprint, "a primary-finger second tap turns sprint off")
	# The view, stick and run button each retain their own finger.
	var look_point := Vector2(540,240)
	await _finger(0, stick_point, true)
	await _finger(2, look_point, true)
	await _drag(2, look_point+Vector2(20,0), Vector2(20,0))
	var yaw := player.rotation.y
	await _finger(1, button_point, true)
	await _finger(1, button_point, false)
	check(sprint.button_pressed and ui.look_pad._finger == 2 and ui.stick._finger == 0,
		"three fingers can move, look and toggle sprint without stealing ownership")
	await _drag(2, button_point, Vector2(20,0))
	check(player.rotation.y != yaw and sprint.button_pressed, "dragging the look finger over sprint still looks instead of toggling it")
	await _finger(2,button_point,false)
	player.can_sprint = false
	ui.show_sprint_available(false)
	await _frames(3)
	check(not player.sprinting and sprint.text == "暂不能跑" and sprint.button_pressed,
		"exhaustion/injury blocks running and explains the still-enabled toggle")
	player.can_sprint = true
	ui.show_sprint_available(true)
	await _frames(3)
	check(player.sprinting and sprint.text == "奔跑：开", "running resumes when the player's stamina or injury permits it")
	ui.set_mode("pause")
	check(not sprint.button_pressed and not player._touch_sprint and player._touch_move == Vector2.ZERO,
		"pausing clears held movement and the run toggle together")
	await _finger(0,stick_point,false)
	ui.set_mode("play")
	await _finger(1,button_point,true)
	await _finger(1,button_point+Vector2(-200,0),false)
	check(not sprint.button_pressed, "releasing a button finger outside cancels the tap")
	await _tap(sprint)
	player.restore_pose(player.capture_pose())
	check(not sprint.button_pressed and not player._touch_sprint,
		"restoring a pose or changing scenes cannot leave a lit sprint toggle with no running input")
	player.enabled = false
	await _tap(sprint)
	check(not sprint.button_pressed and not player._touch_sprint, "a rejected tap while gameplay is disabled cannot light the run toggle")
	player.enabled = true
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _frames(3)
	check(player.sprinting, "desktop Shift still enables running")
	Input.action_release("sprint")
	await _frames(3)
	check(not player.sprinting and player.moving, "releasing Shift restores walking")
	Input.action_release("move_forward")
	ui.queue_free()
	player.queue_free()
	floor_body.queue_free()
	await _frames(3)
	root.size = old_size
	root.content_scale_size = old_scale
