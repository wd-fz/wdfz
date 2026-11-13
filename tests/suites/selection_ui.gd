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
	# How far the list can scroll depends on the platform's font metrics (9 px with Linux fallback fonts,
	# more elsewhere): require a real overflow, then a swipe that goes as far as it can (at most 30 px).
	var nav_bar := phone._nav_scroll.get_v_scroll_bar()
	var nav_range := nav_bar.max_value - nav_bar.page
	check(nav_range >= 1.0, "the phone app list overflows at 150% text, so it must scroll")
	await _swipe((phone.app_buttons.home as Button).get_global_rect().get_center(),Vector2(0,-120))
	check(phone._nav_scroll.scroll_vertical >= minf(30.0, nav_range) - 0.5 and pages.is_empty(), "the phone app list scrolls from its buttons without opening another app")
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
	check(app.starting() and app.session == null and app.ui.loading() and app.ui.loading_screen.is_visible_in_tree(), "confirming a talent shows the loading screen before the run is built")
	app.ui.selection_panel._confirm()
	await _until_started(app)
	check(not app.starting() and not app.ui.loading(), "the loading screen closes once the run has started")
	var run := app.session
	check(run != null and app.talent().id == "code" and app.ui.opening_on() and not app.speedrun.active(), "confirmation installs the chosen talent and enters the actual opening")
	app.ui.selection_panel._confirm()
	check(app.session == run, "a late duplicate confirmation cannot replace the running session")
	app.return_to_menu()
	check(not app.ui.choice_open(), "returning to the menu closes all selection surfaces")
	app.queue_free()
	await _frames(3)
	CampusData.clear_caches()


func test_scaled_tools() -> void:
	var old_size := root.size
	var old_scale := root.content_scale_size
	root.size = Vector2i(960,540)
	root.content_scale_size = Vector2i(960,540)
	var panel := FloatingPanel.new()
	panel.theme = GameUI.BASE_THEME
	var body := VBoxContainer.new()
	var clicks: Array[int] = []
	for i in 18:
		var button := Button.new()
		button.text = "测试操作 %d" % i
		button.custom_minimum_size.y = 64
		button.pressed.connect(func() -> void: clicks.append(i))
		body.add_child(button)
	panel.set_body(body)
	root.add_child(panel)
	await _frames(5)
	var window_before := panel.position
	var at := (body.get_child(0) as Control).get_global_rect().get_center()
	await _finger(at,true)
	var drag := InputEventScreenDrag.new()
	drag.position = root.get_final_transform() * (at - Vector2(0,86))
	drag.relative = root.get_final_transform().basis_xform(Vector2(0,-86))
	Input.parse_input_event(drag)
	await _frames(1)
	check(absf(panel._scroll.scroll_vertical - 86/panel.scale.y) <= 2, "a finger drag in a scaled tool window moves its content by the matching local distance")
	await _finger(at-Vector2(0,86),false)
	check(clicks.is_empty() and panel.position == window_before, "tool content swipes neither run an action nor drag the window")
	var dropdown := OptionButton.new()
	dropdown.add_item("第一项")
	dropdown.add_item("第二项")
	dropdown.custom_minimum_size.y = 48
	body.add_child(dropdown)
	await _frames(3)
	panel._scroll.stop_motion()
	panel._scroll.ensure_control_visible(dropdown)
	await _frames(4)
	await _tap(dropdown)
	check(dropdown.get_popup().visible, "a dropdown inside a scrollable tool keeps its native popup interaction")
	dropdown.get_popup().hide()
	panel.set_collapsed(true)
	await _frames(2)
	panel.set_collapsed(false)
	await _frames(3)
	check(panel._scroll.get_v_scroll_bar().value == panel._scroll.scroll_vertical, "collapsing and restoring a scrolled tool keeps a valid scrollbar")
	panel.queue_free()
	await _frames(3)
	var dev := DebugPanel.new()
	dev.theme = GameUI.BASE_THEME
	root.add_child(dev)
	dev.show()
	dev.select_page("工具")
	await _frames(5)
	await _swipe((dev._pages["工具"].get_child(0) as Control).get_global_rect().get_center(), Vector2(0,-86))
	check(dev._scroll.scroll_vertical > 0, "the developer tools page scrolls from its text as well as its controls")
	await _tap(dev._tabs["状态"])
	await _frames(3)
	check(dev._active_page == "状态" and dev._scroll.scroll_vertical == 0, "switching developer pages stops the previous page's touch inertia")
	dev.queue_free()
	await _frames(3)
	root.size = old_size
	root.content_scale_size = old_scale


func test_ending_navigation() -> void:
	var old_size := root.size
	var old_scale := root.content_scale_size
	var ui: GameUI = preload("res://game/presentation/ui/game_ui.tscn").instantiate()
	root.add_child(ui)
	await _frames(3)
	var actions := {"menu":0,"results":0,"wake":0}
	ui.death_menu_requested.connect(func() -> void: actions.menu += 1)
	ui.results_requested.connect(func() -> void: actions.results += 1)
	ui.ending_wake_requested.connect(func() -> void: actions.wake += 1)
	for screen: Vector2i in [Vector2i(960,540),Vector2i(844,390)]:
		root.size = screen
		await _frames(3)
		for scale: int in [100,150]:
			ui.apply_text_scale(scale)
			ui.show_ending("闸门","真结局",["车窗外的道路终于有了颜色。".repeat(70)],"第 1 天",PackedStringArray(),"rated","car")
			ui.set_ending_wake(true)
			await _frames(8)
			var back: Button
			for child in ui.ending_panel.find_children("*","Button",true,false):
				if child.text == "回到主菜单": back = child
			var bounds := root.get_visible_rect()
			check(bounds.encloses(ui.ending_panel.get_global_rect()), "long ending text fits the landscape panel at %s / %d" % [screen,scale])
			for button: Button in [back,ui._ending_results,ui._ending_wake]:
				check(bounds.encloses(button.get_global_rect()) and not ui._ending_scroll.is_ancestor_of(button), "ending navigation stays outside long scrolling text: %s / %s / %d" % [button.text,screen,scale])
			var footer_before := back.get_global_rect()
			ui._ending_scroll.scroll_vertical = 100000
			await _frames(3)
			check(ui._ending_scroll.scroll_vertical > 0 and back.get_global_rect() == footer_before, "scrolling an ending never moves its navigation")
			var before: Dictionary = actions.duplicate()
			for button: Button in [back,ui._ending_results,ui._ending_wake]:
				await _tap(button)
			check(actions.menu == before.menu+1 and actions.results == before.results+1 and actions.wake == before.wake+1, "every fixed ending action responds to a real touch")
			ui.hide_ending()
	ui.queue_free()
	await _frames(3)
	root.size = old_size
	root.content_scale_size = old_scale


func test_cancel_focus() -> void:
	var app := APP.instantiate() as GameApp
	app.initial_world = "migration_lab"
	app.saves = SaveStore.new(_test_path.get_base_dir()+"/selection-focus/slot.json")
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	await _frames(4)
	app._speedrun_menu()
	await _frames(4)
	await _tap(app.ui._choice_box.get_child(0))
	await _frames(3)
	await _tap(app.ui.selection_panel.back_button)
	await _frames(3)
	var focus := root.gui_get_focus_owner()
	check(focus != null and focus.is_visible_in_tree() and app.ui.menu.is_ancestor_of(focus), "canceling a nested speedrun talent picker restores a visible menu focus")
	check(app.session == null and not app.speedrun.active() and not app.ui.choice_open(), "canceling the nested picker does not arm or start a run")
	app.queue_free()
	await _frames(3)
	CampusData.clear_caches()
