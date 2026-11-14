extends SceneTree
## 开机动画与侧边主菜单: boot animation frames, the panel tearing open on entry, the open panel with the peephole,
## an expanded group, the green pulse, reduced motion, 21:9, and the optional panorama orbit (setting 主菜单实景环绕).
## xvfb-run -a godot --windowed --path . --rendering-driver vulkan --script res://tools/capture/capture_side_menu.gd
## 2026-11-14: the boot animation was redesigned (tube light, wall clock to 18:00); its frames are pinned.
## 2026-11-13: the re-baked panorama behind the open menu, the menu's waking entrance and the loading screen.
## Output: build/previews/side_menu/. SHOTS=boot,menu,wide,reduced,orbit,wake,loading (default: all).
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
		# 2026-11-14 redesign: fixed timeline frames (the software renderer is too slow for real time).
		var splash := ui.boot_splash
		splash.set_process(false)
		for at: float in [0.27, 0.5, 1.2, 1.9, 2.4, 2.75, 3.05, 3.4]:
			splash._t = at
			splash._apply()
			await shot("boot-%.2f" % at, 3)
		splash.set_process(true)
		splash.skip()
		while is_instance_valid(ui.boot_splash):
			await process_frame
	var side := ui.menu_screen
	if want("orbit"):
		_app._setting_changed("menu_orbit", 1)
		var pv := ui.menu_preview
		pv.enabled = true
		pv.set_orbit(true)
		for _i in 120:
			await process_frame
		pv.still = true
		for a: float in [0.0, 0.25, 0.5, 0.75]:
			pv.angle = a
			pv._process(0.0)
			await shot("orbit-%.2f" % a, 6)
		pv.still = false
		_app._setting_changed("menu_orbit", 0)
	if want("wake"):
		_app._setting_changed("menu_orbit", 1)
		var pv2 := ui.menu_preview
		pv2.enabled = true
		pv2.set_orbit(true)
		for _i in 120:
			await process_frame
		pv2.still = true
		pv2.angle = 0.25
		side.open_now()
		await shot("menu-open-panorama", 20)
		ui.menu_entrance = true
		ui._enter_menu()
		var wake := ui.menu_wake
		wake.set_process(false)
		side.open_now()
		for at: float in [0.6, 1.3, 1.8, 2.2]:
			wake._t = at
			wake._apply()
			pv2._process(0.0)
			await shot("menu-wake-%.1f" % at, 3)
		wake.finish()
		pv2.still = false
	if want("loading"):
		var screen := ui.show_loading("读取校园")
		screen.set_process(false)
		screen.modulate.a = 1.0
		for spec: Array in [[1.3, 0.3, "读取校园"], [6.1, 0.85, "布置教室"]]:
			screen._t = spec[0]
			screen.shown_progress = spec[1]
			screen.set_progress(spec[1], spec[2])
			await shot("loading-screen-%d" % roundi(spec[1] * 100.0), 6)
		ui.hide_loading()
		screen.queue_free()
		await process_frame
	if want("menu"):
		# The timeline is fixed by hand for the in-between frames (the software renderer is too slow for real time).
		side.set_process(false)
		for spec: Array in [["menu-entry-tearing", 0.35], ["menu-entry-stretching", 0.75]]:
			side.state = "opening"
			side.open_amount = float(spec[1])
			side._apply_state()
			side._draw_params()
			await shot(String(spec[0]), 3)
		side.set_process(true)
		side.enter()
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
		await shot("menu-pulse", 0)
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
