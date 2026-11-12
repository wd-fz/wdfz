class_name ApplicationExit
extends Node
## Stop audio while the main loop can still retire the mixer's pending playbacks.
var closing := false
var _previous_auto_quit := true

func _ready() -> void:
	_previous_auto_quit = get_tree().auto_accept_quit
	get_tree().auto_accept_quit = false
	get_window().close_requested.connect(request)
	if "--startup-smoke" in OS.get_cmdline_user_args():
		_smoke.call_deferred()

func _smoke() -> void:
	for _i in 5: await get_tree().process_frame
	var display := DisplayServer.get_name().to_lower()
	print("STARTUP DISPLAY: ", display)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--expect-display=") and display != arg.trim_prefix("--expect-display="):
			printerr("STARTUP FAILURE: unexpected display driver")
			get_tree().quit(1)
			return
	if "--expect-windowed" in OS.get_cmdline_user_args() and DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		printerr("STARTUP FAILURE: fresh desktop profile must be windowed")
		get_tree().quit(1)
		return
	# Exercise the same path as the window's close button, including audio shutdown.
	get_window().close_requested.emit()

func request() -> void:
	if closing: return
	closing = true
	var tree := get_tree()
	var app := get_parent() as GameApp
	app._cancel_cinematics()
	app.audio.stop_all()
	if is_instance_valid(app.lan):
		app.lan.stop()
		var deadline := Time.get_ticks_msec() + 18000
		while app.lan.remote.phase != "idle" and Time.get_ticks_msec() < deadline:
			await tree.process_frame
	app.process_mode = Node.PROCESS_MODE_DISABLED
	# stop() fades the playback on the mixer thread; freeing the tree immediately can
	# strand an Ogg playback in Godot's audio server. Keep real frames running to drain it.
	await tree.create_timer(.1,true,false,true).timeout
	await tree.process_frame
	await tree.process_frame
	if "--startup-smoke" in OS.get_cmdline_user_args(): print("STARTUP SMOKE: passed")
	tree.quit()

func _exit_tree() -> void:
	if get_tree() != null: get_tree().auto_accept_quit = _previous_auto_quit
