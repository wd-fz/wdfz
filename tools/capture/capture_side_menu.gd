extends SceneTree
## 开机动画与侧边主菜单: boot animation frames, the folded tag, tearing open, the open panel with the peephole,
## an expanded group, the green pulse while folding, reduced motion, and 21:9.
## xvfb-run -a godot --windowed --path . --rendering-driver vulkan --script res://tools/capture/capture_side_menu.gd
## Output: build/previews/side_menu/. SHOTS=boot,menu,wide,reduced (default: all).
const APP := preload("res://game/app/app.tscn")
var _want: PackedStringArray = []
var _app: GameApp


func _initialize() -> void:
	call_deferred("_run")


func shot(label: String, settle: int = 6) -> void:
	for _i in settle:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/side_menu/" + label + ".png")


func want(id: String) -> bool:
	return _want.is_empty() or _want.has(id)



func _run() -> void:
	var env := OS.get_environment("SHOTS")
	if env != "":
		_want = env.split(",")
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute("res://build/previews/side_menu")
	_app = APP.instantiate()
	_app.saves = SaveStore.new("user://capture-side-%d/slot.json" % Time.get_ticks_usec())
	_app.settings = GameSettings.new(_app.saves.side_path("settings.json"))
	_app.play_boot = want("boot")
	root.add_child(_app)
	await process_frame
	var ui := _app.ui
	if want("boot") and is_instance_valid(ui.boot_splash):
		for at: float in [0.5, 1.4, 2.4, 3.3]:
			while ui.boot_splash != null and is_instance_valid(ui.boot_splash) and ui.boot_splash.elapsed() < at:
				await process_frame
			await shot("boot-%.1f" % at, 1)
		while is_instance_valid(ui.boot_splash):
			await process_frame
	var side := ui.menu_screen
	if want("debug"):
		for c: Control in ui.find_children("*", "Control", true, false):
			if c.is_visible_in_tree() and c.get_global_rect().has_point(Vector2(480, 159)) and c.get_global_rect().size.x < 200:
				print("AT POINT: ", c.get_path(), " ", c.get_global_rect())
	if want("orbit"):
		var pv := ui.menu_preview
		for _i in 200:
			await process_frame
		pv.still = true
		for a: float in [0.0, 1.6, 3.2, 4.8]:
			pv.angle = a
			await shot("orbit-%.1f" % a, 20)
		pv.still = false
	if want("raw"):
		var pv2 := ui.menu_preview
		side.visible = false
		pv2.still = true
		pv2.angle = 1.6
		for c: float in [1110.0, 1150.0, 1338.0]:
			pv2.clock = c
			await shot("raw-%d" % int(c), 40)
		side.visible = true
	if want("menu"):
		# Let the orbiting campus come in.
		for _i in 120:
			await process_frame
		Input.warp_mouse(Vector2(28, 360) * 1280.0 / 960.0)
		await shot("menu-folded-hover", 30)
		# The timeline is fixed by hand for the in-between frames (the software renderer is too slow for real time).
		side.set_process(false)
		for spec: Array in [["menu-tearing", 0.5], ["menu-stretching", 0.82]]:
			side.state = "opening"
			side.open_amount = float(spec[1])
			side._apply_state()
			side._draw_params(0.0)
			await shot(String(spec[0]), 3)
		side.set_process(true)
		side.state = "folded"
		side.open()
		for _i in 90:
			await process_frame
		var rebirth := side.find_child("Rebirth", true, false) as Button
		rebirth.grab_focus()
		await shot("menu-open-peephole", 40)
		rebirth.pressed.emit()
		var new_game := side.find_child("NewGame", true, false) as Button
		new_game.grab_focus()
		await shot("menu-group-rebirth", 50)
		var gallery := side.find_child("Gallery", true, false) as Button
		gallery.pressed.emit()
		var ach := side.find_child("Achievements", true, false) as Button
		side._acted(ach)
		for _i in 10:
			await process_frame
		await shot("menu-pulse-folding", 0)
		for _i in 50:
			await process_frame
		await shot("menu-pulse-absorbed", 0)
		for _i in 200:
			await process_frame
		await shot("menu-faded-back", 0)
	if want("wide"):
		root.size = Vector2i(2520, 1080)
		side.open_now()
		await shot("menu-21x9", 40)
		root.size = Vector2i(1280, 720)
	if want("reduced"):
		_app._setting_changed("reduce_flash", 1)
		side.enter()
		await shot("menu-reduced-motion", 30)
		_app._setting_changed("reduce_flash", 0)
	_app.queue_free()
	await process_frame
	quit()
