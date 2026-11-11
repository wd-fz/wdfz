extends "res://tests/support/test_suite.gd"
## Real touch gestures exercise the same controls used on Android. Never call
## button signals to pretend that a swipe or a confirmation reached the UI.


func _entries() -> Array:
	var entries := []
	for id: String in TalentModule.KEYS:
		var data: Dictionary = TalentModule.DEF[id]
		entries.append({"name":data.n,"role":data.role,"effect":data.does,"limit":data.limit,"art":UIArt.talent(id)})
	entries.append({"name":"随机天赋","role":"让命运替你选择。","effect":"确认时随机选择。","limit":"遵守抽中天赋的限制。","art":UIArt.talent("random")})
	return entries


func _finger(at: Vector2, down: bool, index: int = 0, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = root.get_final_transform() * at
	event.index = index
	event.pressed = down
	event.canceled = canceled
	Input.parse_input_event(event)
	await _frames(1)


func _swipe(at: Vector2, motion: Vector2) -> void:
	await _finger(at, true)
	for i in 6:
		var event := InputEventScreenDrag.new()
		event.position = root.get_final_transform() * (at + motion * float(i+1)/6.0)
		event.relative = root.get_final_transform().basis_xform(motion/6.0)
		Input.parse_input_event(event)
		await _frames(1)
	await _finger(at + motion, false)


func _key(code: Key, shift: bool = false) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.shift_pressed = shift
		event.pressed = down
		Input.parse_input_event(event)
		await _frames(1)


func _mouse(at: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = root.get_final_transform() * at
	Input.parse_input_event(motion)
	await _frames(1)
	for down: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = motion.position
		event.button_index = button
		event.pressed = down
		Input.parse_input_event(event)
		await _frames(1)


func test_selection() -> void:
	var previous_size := root.size
	var previous_scale := root.content_scale_size
	root.size = Vector2i(1280,720)
	var ui: GameUI = preload("res://game/presentation/ui/game_ui.tscn").instantiate()
	root.add_child(ui)
	await _frames(3)
	ui.set_touch_enabled(true)
	var committed: Array[int] = []
	ui.choice_selected.connect(func(index: int) -> void: committed.append(index); ui.hide_choice())
	ui.show_selection("选择天赋", "梦魇 · 每局一个", _entries())
	await _frames(5)
	var panel := ui.selection_panel
	check(panel.selected == -1 and panel.confirm_button.disabled, "selection requires an explicit pick before confirming")
	await _tap(panel.confirm_button)
	check(committed.is_empty(), "disabled confirmation cannot start a run")
	await _tap(panel.cards[0])
	check(panel.selected == 0 and committed.is_empty() and not panel.confirm_button.disabled, "a talent tap selects and previews without committing")
	check(panel._effect.text == TalentModule.DEF.tech.does and panel._limit.text == TalentModule.DEF.tech.limit, "the preview includes the actual effect and the full limitation")
	await _swipe(panel.cards[0].get_global_rect().get_center(), Vector2(0,-170))
	check(panel.list_scroll.scroll_vertical > 80 and panel.selected == 0 and committed.is_empty(), "a swipe starting on a talent card scrolls without selecting another or committing")
	check(root.get_visible_rect().encloses(panel.confirm_button.get_global_rect()) and root.get_visible_rect().encloses(panel.back_button.get_global_rect()), "navigation remains visible while the cards scroll")
	panel.list_scroll.stop_motion()
	panel.list_scroll.ensure_control_visible(panel.cards[-1])
	await _frames(3)
	await _tap(panel.cards[-1])
	check(panel.selected == 7 and committed.is_empty(), "random is selectable at the end of the list and also waits for confirmation")
	await _tap(panel.confirm_button)
	check(committed == [7] and not ui.choice_open(), "one explicit touch confirmation commits the selected card once")
	panel._confirm()
	check(committed == [7], "duplicate confirmation cannot start another run")
	for screen: Vector2i in [Vector2i(960,540),Vector2i(844,390),Vector2i(2340,1080)]:
		root.size = screen
		await _frames(3)
		for scale: int in [85,100,150]:
			ui.apply_text_scale(scale)
			ui.show_selection("选择天赋", "梦魇 · 速通", _entries())
			await _frames(6)
			check(root.get_visible_rect().encloses(panel.shell.get_global_rect()) and root.get_visible_rect().encloses(panel.confirm_button.get_global_rect()), "selection and fixed confirmation fit landscape %s / %d" % [screen,scale])
			check(panel.selected == -1 and panel.confirm_button.disabled and panel.list_scroll.scroll_vertical == 0, "reopening clears the previous pick and resets scrolling")
			await _key(KEY_3)
			check(panel.selected == 2 and panel._limit.text == TalentModule.DEF.drive.limit, "physical number keys preview the correct talent")
			ui.hide_choice()
	ui.apply_text_scale(100)
	ui.show_selection("选择天赋", "预知梦", _entries())
	await _frames(4)
	await _key(KEY_2)
	await _key(KEY_TAB, true)
	check(root.gui_get_focus_owner() == panel.confirm_button, "backward Tab wraps within the selection instead of reaching the menu behind it")
	await _key(KEY_ESCAPE)
	check(committed[-1] == -1 and not ui.choice_open(), "Escape cancels selection without confirming")
	ui.show_selection("选择天赋", "预知梦", _entries())
	await _frames(3)
	await _key(KEY_4)
	await _key(KEY_ENTER)
	check(committed[-1] == 3, "Enter explicitly confirms the talent chosen with a number key")
	ui.show_selection("选择天赋", "预知梦", _entries())
	await _frames(3)
	await _mouse(panel.cards[1].get_global_rect().get_center())
	check(panel.selected == 1, "desktop mouse clicks still select cards")
	panel.back_button.grab_focus()
	await _key(KEY_ENTER)
	check(committed[-1] == -1, "Enter on the focused Back button cancels instead of starting the run")
	ui.queue_free()
	await _frames(3)
	root.size = previous_size
	root.content_scale_size = previous_scale


func test_lists() -> void:
	var previous_size := root.size
	var previous_scale := root.content_scale_size
	root.size = Vector2i(960,540)
	var ui: GameUI = preload("res://game/presentation/ui/game_ui.tscn").instantiate()
	root.add_child(ui)
	await _frames(3)
	ui.set_mode("play")
	ui.set_touch_enabled(true)
	var actions: Array[String] = []
	ui.item_use_requested.connect(func(id: String) -> void: actions.append("use:" + id))
	ui.item_drop_requested.connect(func(id: String) -> void: actions.append("drop:" + id))
	var items := []
	# The two-pane bag scrolls when the selected item's description is long.
	for i in 8: items.append({"id":"torch","name":"手电筒 %d" % i,"text":"可以在黑暗中照亮前方。".repeat(40)})
	ui.show_bag(items)
	await _frames(5)
	var use := ui.bag_panel.find_child("Item_torch_-1",true,false) as Button
	ui._bag_scroll.ensure_control_visible(use)
	await _frames(3)
	await _swipe(use.get_global_rect().get_center(), Vector2(0,-90))
	check(ui._bag_scroll.scroll_vertical > 40 and actions.is_empty(), "swiping from the bag's use button scrolls without using or discarding an item")
	ui._bag_scroll.stop_motion()
	ui._bag_scroll.scroll_vertical = 0
	await _frames(3)
	ui._bag_scroll.ensure_control_visible(use)
	await _frames(3)
	await _tap(use)
	check(actions == ["use:torch"], "a normal tap after swiping still uses the intended item exactly once")
	var at := use.get_global_rect().get_center()
	await _finger(at,true)
	await _finger(at,false,0,true)
	check(actions.size() == 1, "a canceled finger never activates the pending item button")
	await _finger(at,true)
	await _finger(at+Vector2(8,0),true,1)
	await _finger(at+Vector2(8,0),false,1)
	await _finger(at,false)
	check(actions.size() == 1, "a second finger cancels the first pending button action")
	var drop := ui.bag_panel.find_child("Drop_torch",true,false) as Button
	ui._bag_scroll.ensure_control_visible(drop)
	await _frames(3)
	await _swipe(drop.get_global_rect().get_center(), Vector2(0,-80))
	check(not ui._bag_drop_row.visible and actions.size() == 1, "swiping from discard cannot even open its confirmation")
	ui._bag_scroll.stop_motion()
	ui._bag_scroll.ensure_control_visible(drop)
	await _frames(3)
	await _tap(drop)
	await _frames(4)
	check(ui._bag_drop_row.visible and actions.size() == 1 and root.get_visible_rect().encloses(ui.bag_panel.find_child("BagConfirmDrop",true,false).get_global_rect()), "discard waits for a separate fixed confirmation")
	await _tap(ui.bag_panel.find_child("BagKeep",true,false))
	check(not ui._bag_drop_row.visible and actions.size() == 1, "keeping an item cancels the pending discard")
	ui._bag_scroll.ensure_control_visible(drop)
	await _frames(3)
	await _tap(drop)
	await _frames(4)
	await _tap(ui.bag_panel.find_child("BagConfirmDrop",true,false))
	check(actions == ["use:torch","drop:torch"], "only the explicit discard confirmation emits the item action")
	ui.hide_bag()
	var rows := []
	for i in 20:
		rows.append({"id":"crowd","text":"已记录的异象 %d" % i,"on":true,"memo":"这是一段记忆。","action":func() -> void: actions.append("archive")})
	ui.show_list("档案馆",rows)
	await _frames(5)
	var replay := ui._ach_list.find_children("*","Button",true,false)[0] as Button
	await _swipe(replay.get_global_rect().get_center(), Vector2(0,-110))
	check((ui._ach_list.get_parent() as ScrollContainer).scroll_vertical > 50 and actions.size() == 2, "archive swipes do not start a CG replay")
	var archive_scroll := ui._ach_list.get_parent() as TouchScroll
	archive_scroll.stop_motion()
	archive_scroll.scroll_vertical = 0
	await _frames(3)
	await _mouse(archive_scroll.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_DOWN)
	check(archive_scroll.scroll_vertical > 0 and actions.size() == 2, "desktop wheel scrolling remains native and never starts a replay")
	ui.ach_panel.hide()
	ui.show_choice("选择行动",["一","二","三","四","五","六","七","八","九"])
	await _frames(5)
	ui._choice_scroll.scroll_vertical = 10000
	await _frames(3)
	check(root.get_visible_rect().encloses(ui._choice_cancel.get_global_rect()), "long gameplay choice lists keep their cancel button outside the scrolling content")
	var choices: Array[int] = []
	ui.choice_selected.connect(func(index: int) -> void: choices.append(index); ui.hide_choice())
	await _key(KEY_3)
	check(choices == [2], "gameplay choices still respond immediately to number keys")
	ui.show_choice("短选项",["回答"])
	await _frames(3)
	await _swipe(ui._choice_box.get_child(0).get_global_rect().get_center(),Vector2(35,0))
	check(choices == [2], "a swipe cancels a pending click even when a short list needs no scrolling")
	ui.show_choice("必须回应",["回答"],false)
	await _frames(3)
	await _key(KEY_ESCAPE)
	check(ui.choice_open() and not ui._choice_cancel.visible, "uncancellable timed decisions still reject Escape")
	ui.hide_choice()
	ui.show_settings(GameSettings.DEFAULTS)
	await _frames(5)
	var settings := ui.settings_panel
	settings.select_page("声音")
	await _frames(4)
	var slider := settings.controls["vol"] as HSlider
	var before := settings.scroll.scroll_vertical
	var start := slider.get_global_rect().get_center()
	await _swipe(start,Vector2(-slider.size.x*.3,0))
	check(slider.value < 100 and settings.scroll.scroll_vertical == before, "a slider owns its horizontal drag without scrolling its settings page")
	ui.settings_panel.hide()
	ui.apply_text_scale(150)
	var phone := PhonePanel.new()
	ui.get_node("Root").add_child(phone)
	phone.show()
	phone.select("home","","",true)
	await _frames(5)
	var pages: Array[String] = []
	phone.app_selected.connect(func(id: String) -> void: pages.append(id))
	await _swipe((phone.app_buttons.home as Button).get_global_rect().get_center(),Vector2(0,-120))
	check(phone._nav_scroll.scroll_vertical > 30 and pages.is_empty(), "the phone app list scrolls from its buttons without opening another app")
	ui.queue_free()
	await _frames(3)
	root.size = previous_size
	root.content_scale_size = previous_scale


func test_app() -> void:
	var app := APP.instantiate() as GameApp
	app.initial_world = "migration_lab"
	app.saves = SaveStore.new(_test_path.get_base_dir()+"/selection/slot.json")
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	await _frames(3)
	app.ui.set_touch_enabled(true)
	app._pick_talent("hard",true)
	await _frames(4)
	await _tap(app.ui.selection_panel.cards[0])
	check(app.session == null and not app.speedrun.active(), "previewing a speedrun talent neither creates a session nor arms the timer")
	await _tap(app.ui.selection_panel.back_button)
	check(app.session == null and not app.speedrun.active() and not app.ui.choice_open(), "back cancels a speedrun setup cleanly")
	app._pick_talent("easy")
	await _frames(3)
	check(app.ui.selection_panel.selected == -1, "a new difficulty cannot reuse the canceled selection")
	await _tap(app.ui.selection_panel.cards[1])
	await _tap(app.ui.selection_panel.confirm_button)
	var run := app.session
	check(run != null and app.talent().id == "code" and app.ui.opening_on() and not app.speedrun.active(), "confirmation installs the chosen talent and enters the actual opening")
	app.ui.selection_panel._confirm()
	check(app.session == run, "a late duplicate confirmation cannot replace the running session")
	app.return_to_menu()
	check(not app.ui.choice_open(), "returning to the menu closes all selection surfaces")
	app.queue_free()
	await _frames(3)
	CampusData.clear_caches()
