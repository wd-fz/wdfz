extends SceneTree
## Render portrait cards from the playable actors using their actual lobby lighting.
func _initialize() -> void:
	call_deferred("capture")


func capture() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(560, 600)
	var stage := StudentStudio.new()
	root.add_child(stage)
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for id: String in StudentCast.IDS:
		stage.select_character(id)
		stage.set_close_up(true)
		for i in 5: await process_frame
		await RenderingServer.frame_post_draw
		var img := stage.viewport_3d.get_texture().get_image()
		var path := "res://assets/characters/%s.webp" % id
		img.resize(280, 300, Image.INTERPOLATE_LANCZOS)
		if img.save_webp(path, false, .93) != OK:
			push_error("Could not render portrait " + id)
			quit(1)
			return
	stage.queue_free()
	await process_frame
	quit()
