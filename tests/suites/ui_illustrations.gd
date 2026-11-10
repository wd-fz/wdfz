extends "res://tests/support/test_suite.gd"
## Asset coverage follows the live catalogs, and real UI buttons keep their actions.


func _illustration(texture: Texture2D, label: String, seen: Dictionary) -> void:
	check(texture is AtlasTexture, "illustration resource exists: " + label)
	if not texture is AtlasTexture:
		return
	var atlas := texture as AtlasTexture
	check(atlas.atlas != null and atlas.region.size.x > 32 and atlas.region.size.y > 32 and Rect2(Vector2.ZERO, atlas.atlas.get_size()).encloses(atlas.region), "illustration stays inside its source sheet: " + label)
	var key := "%s:%s" % [atlas.atlas.resource_path, atlas.region]
	check(not seen.has(key), "every ID has its own illustration: " + label)
	seen[key] = true


func test_catalog() -> void:
	var seen := {}
	for id: String in CampusData.campus()["items"]:
		_illustration(UIArt.item(id), "item " + id, seen)
	for id: String in TalentModule.KEYS:
		_illustration(UIArt.talent(id), "talent " + id, seen)
	_illustration(UIArt.talent("random"), "random talent", seen)
	for spec: Array in PhonePanel.APPS:
		_illustration(UIArt.phone(spec[0]), "phone " + String(spec[0]), seen)
	_illustration(UIArt.phone("battery"), "phone battery", seen)
	check(UIArt.wallpaper() != null and UIArt.wallpaper().get_width() > 1000, "the phone wallpaper loads as a real texture")
	check(UIArt.item("not_an_item") == null and UIArt.talent("") == null, "unknown or empty IDs remain usable without a broken resource")
	check(UIArt.item("torch") == UIArt.item("torch"), "repeated HUD updates reuse the same texture resource")
	for id: String in AchievementsModule.LIST:
		_illustration(UIArt.achievement(id), "achievement " + id, seen)
	for entry: Dictionary in CampusData.rules_dlc()["achievements"]:
		_illustration(UIArt.achievement(String(entry["id"])), "DLC achievement " + String(entry["id"]), seen)
	for group: String in ["deaths", "cuts"]:
		for entry: Dictionary in CampusData.archive()[group]:
			_illustration(UIArt.memory(String(entry["id"])), "archive " + String(entry["id"]), seen)
	_illustration(UIArt.memory("x.rules.knock"), "DLC death", seen)
	for grade: Dictionary in ScoreRules.GRADES:
		_illustration(UIArt.grade(String(grade["g"])), "grade " + String(grade["g"]), seen)
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(UIArt.ROOT + "catalog.json"))
	for group: String in ["nav", "surface", "landmarks"]:
		for id: String in catalog[group]:
			var texture: Texture2D = UIArt.nav(id) if group == "nav" else (UIArt.surface(id) if group == "surface" else UIArt.landmark(id))
			_illustration(texture, group + " " + id, seen)
	check(UIArt.entry("end:inception", false) == UIArt.surface("locked") and UIArt.entry("crowd", false) == UIArt.surface("locked"), "undiscovered secret memories never expose their image")
	check(UIArt.entry("x.grade.SSS", true) == UIArt.grade("SSS") and UIArt.entry("x.rules.n.ticket", true) == UIArt.achievement("rules.n.ticket"), "archive extensions resolve the correct grade and DLC illustration")
	check(UIArt.memory("rules_knock") == UIArt.memory("x.rules.knock"), "the live DLC death source and its archive entry share the same image")
	check(UIArt.memory("../../outside") == null and UIArt.achievement("n.unknown") == null, "invalid art IDs cannot escape the resource namespace")
	CampusData.clear_caches()


func test_interface() -> void:
	var previous_size := root.size
	var app := APP.instantiate() as GameApp
	app.saves = SaveStore.new(_test_path.get_base_dir() + "/art-save.json")
	app.settings = GameSettings.new(_test_path.get_base_dir() + "/art-settings.json")
	root.add_child(app)
	await _frames(3)
	app._setting_changed("quality", 0)
	app.ui.set_touch_enabled(true)
	for view: Vector2i in [Vector2i(1280, 720), Vector2i(844, 390)]:
		root.size = view
		app.ui.apply_text_scale(125)
		app._pick_talent("easy")
		await _frames(5)
		check(root.get_visible_rect().encloses(app.ui.choice_panel.get_global_rect()), "illustrated talent choices fit landscape " + str(view))
		check(app.ui._choice_scroll.scroll_vertical == 0, "opening talent selection starts at the first illustrated talent")
		for i in TalentModule.KEYS.size():
			var button := app.ui._choice_box.get_child(i) as Button
			check(button.icon == UIArt.talent(TalentModule.KEYS[i]) and button.text.contains("限制："), "talent artwork keeps the effect and limitation: " + String(TalentModule.KEYS[i]))
		app.ui._choice_scroll.scroll_vertical = 10000
		app.ui.hide_choice()
	root.size = Vector2i(960, 540)
	app._pick_talent("easy")
	await _frames(4)
	await _tap(app.ui._choice_box.get_child(0))
	check(app.session != null and app.talent().id == "tech" and app.items().has("phone"), "tapping an illustrated talent still starts the selected talent")
	if app._opening_cut != null and app._opening_cut.on:
		app._opening_cut.end(true)
	else:
		app.ui._end_opening(true)
	app.items().add("torch")
	app._open_bag()
	await _frames(3)
	var illustration := app.ui.bag_panel.find_child("ItemArt_torch", true, false) as TextureRect
	check(illustration != null and illustration.texture == UIArt.item("torch") and illustration.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the bag displays the actual item's illustration without taking input")
	var use := app.ui.bag_panel.find_child("Item_torch_-1", true, false) as Button
	app.ui._bag_scroll.ensure_control_visible(use)
	await _frames(3)
	await _tap(use)
	check(app.items().torch_on, "the illustrated item card still uses the real item")
	if app.ui.bag_open(): app._close_bag()
	app.items().set_hot(0, "torch")
	app.items().set_hot(1, "phone")
	await _frames(3)
	check(app.ui._hot_art[0].texture == UIArt.item("torch") and (app.ui.touch_control("hot2") as Button).icon == UIArt.item("phone"), "desktop and touch hot slots use the same item art")
	app.ui.show_hot("1 · 空    2 · 空", [null, null])
	check(app.ui._hot_art[0].texture == null and (app.ui.touch_control("hot2") as Button).icon == null, "cleared hot slots cannot keep a discarded item's art")
	app._open_phone()
	await _frames(4)
	var panel := app._phone_panel
	check(panel.visible and panel.find_child("PhoneWallpaper", true, false) != null and root.get_visible_rect().encloses(panel.get_global_rect()), "the illustrated phone fits landscape with its wallpaper")
	for spec: Array in PhonePanel.APPS:
		var button := panel.app_buttons[spec[0]] as Button
		check(button.icon == UIArt.phone(spec[0]), "phone app has its own art: " + String(spec[0]))
		panel._nav_scroll.ensure_control_visible(button)
		await _frames(2)
		await _tap(button)
		check(button.button_pressed, "illustrated phone app selection still reaches the app: " + String(spec[0]))
	app.return_to_menu()
	check(not panel.visible and app.session == null, "returning to menu closes the illustrated phone")
	app.queue_free()
	await _frames(3)
	root.size = previous_size
	CampusData.clear_caches()


func test_expanded_interface() -> void:
	var previous_size := root.size
	var app := APP.instantiate() as GameApp
	app.saves = SaveStore.new(_test_path.get_base_dir() + "/expanded-art/slot.json")
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	await _frames(3)
	app._setting_changed("quality", 0)
	app.ui.set_touch_enabled(true)
	app.archive_flow.rules.grant(["patrol", "cut:opening"])
	for extent: Vector2i in [Vector2i(1280, 720), Vector2i(844, 390), Vector2i(640, 360)]:
		root.size = extent
		app.ui.apply_text_scale(125)
		await _frames(5)
		var bounds := root.get_visible_rect()
		var menu := app.ui.menu_screen
		check(menu.find_child("NewGame", true, false).icon == UIArt.nav("new_game") and bounds.encloses(menu._card.get_global_rect()), "illustrated menu preserves landscape bounds: " + str(extent))
		app.archive_flow.open("死亡")
		await _frames(5)
		check(bounds.encloses(app.ui.ach_panel.get_global_rect()), "archive art stays scrollable in landscape: " + str(extent))
		var unlocked := app.ui.ach_panel.find_child("EntryArt_patrol", true, false) as TextureRect
		var locked := app.ui.ach_panel.find_child("EntryArt_an_rain", true, false) as TextureRect
		check(unlocked != null and unlocked.texture == UIArt.memory("patrol") and unlocked.mouse_filter == Control.MOUSE_FILTER_IGNORE, "unlocked archive entry uses its own input-transparent memory")
		check(locked != null and locked.texture == UIArt.surface("locked") and app.ui.ach_panel.find_child("EntryArt_void_lost", true, false) == null, "locked public and undiscovered secret archive entries preserve secrecy")
		app.ui.ach_panel.hide()
		app.ui.show_settings(app.settings.values)
		await _frames(5)
		var settings := app.ui.settings_panel
		check(bounds.encloses(settings.shell.get_global_rect()) and settings._nav_buttons["画面"].icon == UIArt.nav("picture"), "illustrated settings stay reachable: " + str(extent))
		check(settings.controls["quality"][4].icon == UIArt.surface("quality_real"), "each quality option displays the matching level")
		settings.dismiss()
		var meta := ScoreRules.sample_meta("S", "car")
		app.ui.show_results(meta, {"silent": true, "reduce": true})
		await _frames(5)
		var results := app.ui.results_panel
		check(bounds.encloses(results.get_global_rect()) and results._grade_art.texture == UIArt.grade("S") and results._route_art.texture == UIArt.memory("end:car"), "result artwork retains the animated grade and reachable controls: " + str(extent))
		meta["source"] = "archive"
		results.open(meta, {"silent": true, "reduce": true})
		check(not results._route_art.visible and results._route_art.texture == null, "a directly granted grade does not reveal an unseen ending")
		app.ui.hide_results()
		app.ui.show_death_card("测试死亡记录", "", "", PackedStringArray(), PackedStringArray(), "", "patrol")
		await _frames(4)
		check(bounds.encloses(app.ui.death_panel.get_global_rect()) and app.ui._death_art.texture == UIArt.memory("patrol"), "death image and menu control fit: " + str(extent))
		app.ui.death_panel.hide()
		app.ui.show_ending("闸门", "真结局", ["车开出了学校。"], "第 1 天", PackedStringArray(), "", "car")
		await _frames(4)
		check(bounds.encloses(app.ui.ending_panel.get_global_rect()) and app.ui._ending_art.texture == UIArt.memory("end:car"), "ending image stays inside the scrolling card: " + str(extent))
		app.ui.ending_panel.hide()
	app.start_new_game("easy", "watch")
	if app._opening_cut != null and app._opening_cut.on: app._opening_cut.end(true)
	else: app.ui._end_opening(true)
	await _frames(5)
	app._show_map("teach1")
	await _frames(5)
	var selector := app.ui._map_select
	check(selector.get_item_icon(selector.selected) == UIArt.landmark("teach") and selector.get_popup().get_item_icon_max_width(selector.selected) == 28, "map selector uses a bounded landmark icon in both button and popup")
	check(not app.ui.map_view.room.is_empty() and app.ui.map_view.seen == app.exploration().seen("teach1"), "illustrated map keeps the actual floor and exploration mask")
	app.ui.map_panel.hide()
	app.ui.show_prompt("站起身")
	check(app.ui._prompt_art == "stand", "touch action art follows the real stand-up prompt")
	for id: String in ["sprint", "interact", "manual", "torch"]:
		var target := app.ui.touch_control(id) as Button
		check(target.get_combined_minimum_size().x <= target.size.x + 1, "compact touch icon cannot enlarge its movement target: " + id)
	app.return_to_menu()
	app.queue_free()
	await _frames(3)
	root.size = previous_size
	CampusData.clear_caches()
