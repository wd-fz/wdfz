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
