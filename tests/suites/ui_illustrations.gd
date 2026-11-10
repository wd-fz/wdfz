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
