extends "res://tests/support/test_suite.gd"
## Key bindings (KeyBindings, GameSettings.apply_bindings, the 键位 settings page).


func test_bindings() -> void:
	var b := KeyBindings.defaults()
	check(b["interact"] == [KEY_E, 0] and b["move_forward"] == [KEY_W, KEY_UP] and not b.has("pause"), "defaults match the project's keys; pause stays fixed on Esc")
	check(KeyBindings.normalize({"interact": [KEY_ESCAPE, "x"], "bogus": [KEY_Q]})["interact"] == [KEY_E, 0]
		and KeyBindings.normalize({"torch": [KEY_G, KEY_J]})["torch"] == [KEY_G, KEY_J] and KeyBindings.normalize({"torch": [KEY_E, KEY_G]})["torch"] == [0, KEY_G],
		"reserved and malformed keys are dropped; an action left without keys gets its default back when it is free")
	var dup := KeyBindings.normalize({"move_forward": [KEY_Q, 0], "interact": [KEY_Q, 0]})
	check(dup["move_forward"] == [KEY_Q, 0] and dup["interact"] == [KEY_E, 0], "a key used twice keeps its first owner")
	var r := KeyBindings.assign(b, "interact", 0, KEY_F)
	check(bool(r["ok"]) and String(r["swapped"]) == "torch" and b["interact"][0] == KEY_F and b["torch"][0] == KEY_E, "taking another action's key swaps the two")
	check(not bool(KeyBindings.assign(b, "interact", 0, KEY_ESCAPE)["ok"]), "Esc cannot be bound")
	check(not KeyBindings.clear(b, "interact", 0) and KeyBindings.clear(b, "move_forward", 1) and b["move_forward"] == [KEY_W, 0], "a slot clears only while another key remains")
	KeyBindings.reset(b, "interact")
	check(b["interact"] == [KEY_E, 0] and b["torch"][0] == KEY_F, "resetting an action gives the action that held its default its old key back")
	KeyBindings.reset(b, "")
	check(same_json(b, KeyBindings.defaults()), "reset all restores every default")
	check(KeyBindings.key_name(KEY_UP) == "↑" and KeyBindings.key_name(KEY_E) == "E", "key names are short and readable")
	# Persistence and the InputMap.
	var s := GameSettings.new(_test_path.get_base_dir() + "/bindings-settings.json")
	s.load_file()
	KeyBindings.assign(s.bindings, "interact", 0, KEY_G)
	check(s.save_file(), "bindings save with the settings")
	var back := GameSettings.new(s.path)
	back.load_file()
	check(back.bindings["interact"] == [KEY_G, 0], "bindings load back")
	back.apply_bindings()
	var g := InputEventKey.new()
	g.physical_keycode = KEY_G
	g.pressed = true
	var e := InputEventKey.new()
	e.physical_keycode = KEY_E
	e.pressed = true
	check(g.is_action("interact") and not e.is_action("interact") and InputMap.has_action("notes"), "the InputMap follows the bindings")
	back.bindings = KeyBindings.defaults()
	back.apply_bindings()
	check(e.is_action("interact"), "restoring defaults restores the InputMap")


func test_bindings_page() -> void:
	var app := APP.instantiate() as GameApp
	app.saves = SaveStore.new(_test_path.get_base_dir() + "/bindings-ui-save.json")
	app.settings = GameSettings.new(_test_path.get_base_dir() + "/bindings-ui.json")
	root.add_child(app)
	await _frames(3)
	app.ui.settings_requested.emit()
	await _frames(4)
	var panel := app.ui.settings_panel
	panel.select_page("键位")
	await _frames(2)
	check(panel._key_buttons.size() == KeyBindings.ACTIONS.size() and (panel._key_buttons["interact"][0] as Button).text == "E", "the 键位 page lists every action with its keys")
	(panel._key_buttons["interact"][1] as Button).pressed.emit()
	check(panel.capturing() == ["interact", 1] and (panel._key_buttons["interact"][1] as Button).text == "按下新键…", "pressing a key cell waits for a key")
	var q := InputEventKey.new()
	q.physical_keycode = KEY_Q
	q.keycode = KEY_Q
	q.pressed = true
	panel._input(q)
	await _frames(2)
	check(app.settings.bindings["interact"] == [KEY_E, KEY_Q] and (panel._key_buttons["interact"][1] as Button).text == "Q" and q.is_action("interact"), "a key press binds, saves and applies")
	(panel._key_buttons["torch"][0] as Button).pressed.emit()
	panel._input(q)
	await _frames(2)
	check(app.settings.bindings["torch"][0] == KEY_Q and app.settings.bindings["interact"][1] == KEY_F and panel._bind_note.text.contains("互换"), "a taken key swaps and says so")
	(panel._key_buttons["torch"][0] as Button).pressed.emit()
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	panel._input(esc)
	check(panel.capturing().is_empty() and app.settings.bindings["torch"][0] == KEY_Q and panel.visible, "Esc cancels the capture without closing the settings")
	app.ui.bindings_reset.emit("")
	await _frames(1)
	var stored := GameSettings.new(app.settings.path)
	stored.load_file()
	check(same_json(stored.bindings, KeyBindings.defaults()), "reset all is saved")
	panel.dismiss()
	app.queue_free()
	await _frames(2)


func test_touch_layout_v2() -> void:
	var v1 := TouchLayout.normalize({"stick": {"x": 30, "y": 70}, "actions": {"x": 80, "y": 60}, "tools": {"x": 50, "y": 15}})
	check(v1.has("sprint") and is_equal_approx(float(v1.sprint.y), 55.1) and is_equal_approx(float(v1.interact.y), 64.9) and is_equal_approx(float(v1.hot2.x), 58.2) and not v1.has("actions"),
		"version-1 group places are split into single controls")
	var raw := {"interact": {"x": 50, "y": 50, "s": 300}, "opacity": 10}
	var n := TouchLayout.normalize(raw)
	check(int(n.interact.s) == 150 and int(n.opacity) == 35, "sizes and opacity are clamped (70–150 %, 35–100 %)")
	var view := Vector2(1280, 720)
	var big := TouchLayout.resolve(view, {"interact": {"x": 50, "y": 50, "s": 150}}, 100)
	var small := TouchLayout.resolve(view, {"interact": {"x": 50, "y": 50, "s": 70}}, 100)
	check((big.interact as Rect2).size.x > (small.interact as Rect2).size.x * 1.8 and (small.interact as Rect2).size.y >= 44, "each control has its own size and keeps a 44 px target")
	var c := TouchLayout.centres(big, view, {"interact": {"x": 50, "y": 50, "s": 150}, "opacity": 60})
	check(int(c.interact.s) == 150 and int(c.opacity) == 60 and c.has("hot1"), "writing back the places keeps sizes and opacity")
	check(TouchLayout.snap(Vector2(51.2, 48.8)) == Vector2(50, 50), "the grid snaps centres to 2.5 %")
	var ui: GameUI = preload("res://game/presentation/ui/game_ui.tscn").instantiate()
	root.add_child(ui)
	await _frames(3)
	ui.set_mode("play")
	ui.set_touch_enabled(true)
	ui.apply_touch_scale(100, {"hot1": {"x": 40, "y": 60, "s": 120}, "opacity": 50})
	await _frames(2)
	var hot1 := ui.touch_control("hot1")
	check(absf(hot1.get_global_rect().get_center().x / root.get_visible_rect().size.x * 100.0 - 40.0) < 1.5 and is_equal_approx(hot1.modulate.a, 0.5) and is_equal_approx(ui.touch_control("stick").modulate.a, 0.5),
		"a single tool button moves on its own and every control takes the opacity")
	ui.show_touch_layout_editor()
	await _frames(3)
	var edit := ui._layout_editor
	edit.select("torch")
	edit._size_slider.value = 140
	check(int(edit.layout.torch.s) == 140 and (edit._rects.torch as Rect2).size.x > 60 * 1.3, "the editor sizes the selected control")
	edit._alpha_slider.value = 70
	var saved := [{}]
	edit.saved.connect(func(l: Dictionary) -> void: saved[0] = l)
	edit._buttons.get_node("done").pressed.emit()
	await _frames(2)
	check(int(saved[0].get("opacity", 0)) == 70 and int(saved[0].torch.s) == 140, "done saves sizes and opacity")
	ui.queue_free()
	await _frames(2)


func test_touch_defaults_spaced() -> void:
	var ok := true
	for view: Vector2 in [Vector2(960, 540), Vector2(1280, 720), Vector2(1920, 1080), Vector2(2340, 1080)]:
		for pct in [85, 100, 125]:
			var r := TouchLayout.resolve(view, {}, pct, [Rect2(0, 0, view.x, 68)])
			var row := [r.manual, r.torch, r.hot1, r.hot2]
			for i in range(1, 4):
				ok = ok and is_equal_approx((row[i] as Rect2).position.y, (row[0] as Rect2).position.y) and (row[i] as Rect2).position.x > (row[i - 1] as Rect2).position.x
			ok = ok and is_equal_approx((r.sprint as Rect2).position.x, (r.interact as Rect2).position.x) and (r.sprint as Rect2).position.y < (r.interact as Rect2).position.y
	check(ok, "default tool buttons form one evenly ordered row and the action buttons one column on landscape screens")
