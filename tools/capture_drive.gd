extends SceneTree
## The driving view with its dashboard (needs a display): godot --path . --script res://tools/capture_drive.gd
## Output: build/previews/drive/. The road, a barrier and a fork ahead; the mirror with shadows when the pursuit is close.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var view := CarChaseView.new()
	root.add_child(view)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	DirAccess.make_dir_recursive_absolute("res://build/previews/drive")
	for spec: Array in [["far", 0.1], ["near", 0.9]]:
		var d := {"x": 0.5, "distance": 30.0, "pursuit": float(spec[1]) * CarChaseRules.PURSUIT_LIMIT, "speed": 12.0, "hp": 3}
		view.update(d)
		var eye := view.position + CarChaseView.eye(d)
		cam.global_position = eye
		cam.rotation = Vector3(-0.04, 0.0, 0.0)
		for _i in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/previews/drive/dash-%s.png" % String(spec[0]))
	quit()
