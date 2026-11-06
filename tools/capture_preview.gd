extends SceneTree
## Run with a display: godot --path . --script res://tools/capture_preview.gd
## Output is disposable and excluded from Git. Never touches the gameplay save.

const APP := preload("res://scenes/app.tscn")
var _output := "res://build/previews"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Preview capture needs a rendering display, not --headless.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_output)
	var ignore := FileAccess.open(_output.get_base_dir().path_join(".gdignore"), FileAccess.WRITE)
	if ignore != null:
		ignore.close()
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://framework-preview/unused.json")
	root.add_child(app)
	await _save_frame("menu.png")
	app.start_new_game()
	await _save_frame("migration-lab.png")
	app.ui.set_touch_enabled(true)
	root.size = Vector2i(390, 844)
	await _save_frame("touch-portrait.png")
	app.pause_game()
	await _save_frame("pause-portrait.png")
	app.queue_free()
	paused = false
	await process_frame
	print("Previews saved to ", ProjectSettings.globalize_path(_output))
	quit()


func _save_frame(filename: String) -> void:
	for _i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(_output.path_join(filename))
	if error != OK:
		printerr("Could not capture ", filename, ": ", error_string(error))
		quit(1)
