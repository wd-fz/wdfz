extends SceneTree
## The six human figures side by side (needs a display): godot --path . --script res://tools/capture/capture_figures.gd
## Output: build/previews/figures/figures.png.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.12, 0.13, 0.15)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	world.add_child(sun)
	var x := -5.0
	for k: String in FigureModel.KINDS:
		var f := FigureModel.make(k, Color(0.55, 0.6, 0.7))
		f.position = Vector3(x, 0, 0)
		world.add_child(f)
		var box := AABB()
		for mi: Node in f.find_children("*", "MeshInstance3D", true, false):
			box = box.merge((mi as MeshInstance3D).get_aabb()) if box.size != Vector3.ZERO else (mi as MeshInstance3D).get_aabb()
		print(k, " aabb ", box)
		x += 2.0
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.4, 9.5)
	cam.fov = 40
	world.add_child(cam)
	for _i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/previews/figures")
	root.get_texture().get_image().save_png("res://build/previews/figures/figures.png")
	quit()
