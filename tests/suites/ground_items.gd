extends "res://tests/support/test_suite.gd"
## Dropped items lie on the floor and come back with the interact key (user change 2026-11-11).


func _bag() -> InventoryModule:
	var bag := InventoryModule.new(CampusData.rooms(), CampusData.campus())
	bag.reset()
	bag.set_seed(7)
	return bag


func test_rules() -> void:
	var bag := _bag()
	bag.add("torch")
	bag.add("chalk")
	bag.take_notices()
	check(bag.drop("torch"), "dropping still removes the item from the bag")
	bag.place_on_ground("torch", "teach1", Vector3(10.0, 0.0, 5.0))
	bag.place_on_ground("not-an-item", "teach1", Vector3.ZERO)
	check(bag.ground.size() == 1 and bag.ground_in("teach1").size() == 1 and bag.ground_in("teach2").is_empty(), "the ground keeps known items by scene only")
	var feet := Vector3(10.0, 0.0, 6.0)
	var eye := feet + Vector3(0, 1.65, 0)
	var down := Vector3(0, -1.65, -1.0)     # looking at the floor a metre ahead
	check(bag.ground_target("teach1", feet, eye, down) == 0, "an item in reach that is looked at is the pick target")
	check(bag.ground_target("teach1", feet, eye, Vector3(0, -1.65, 1.0)) == -1, "an item behind the view is not picked")
	check(bag.ground_target("teach1", feet, eye, Vector3(0, 0, -1)) == -1, "looking straight ahead over an item at the feet does not pick it")
	check(bag.ground_target("teach1", Vector3(10.0, 0.0, 8.0), Vector3(10.0, 1.65, 8.0), Vector3(0, -1.0, -1.0)) == -1, "an item out of reach is not picked")
	check(bag.ground_target("teach1", Vector3(10.0, 3.0, 6.0), Vector3(10.0, 4.65, 6.0), Vector3(0, -4.65, -1.0)) == -1, "an item on another floor height is not picked")
	check(bag.ground_target("teach2", feet, eye, down) == -1, "an item in another scene is not picked")
	bag.place_on_ground("torch", "teach1", Vector3(10.6, 0.0, 5.0))
	check(bag.ground_target("teach1", feet, eye, Vector3(0.6, -1.65, -1.0)) == 1 and bag.ground_target("teach1", feet, eye, down) == 0, "with two on the floor, the one looked at is taken")
	bag.ground.remove_at(1)
	var saved := bag.capture()
	check(bag.validate(JSON.parse_string(JSON.stringify(saved))).is_empty(), "a save with items on the ground validates through JSON")
	var old := saved.duplicate(true)
	old.erase("ground")
	check(bag.validate(old).is_empty(), "an older save without the ground list still validates")
	var broken := saved.duplicate(true)
	broken["ground"] = [{"id": "torch", "world": "teach1", "x": "a", "y": 0, "z": 0}]
	check(not bag.validate(broken).is_empty(), "a ground entry with a bad position is rejected")
	broken["ground"] = [{"id": "nothing", "world": "teach1", "x": 0, "y": 0, "z": 0}]
	check(not bag.validate(broken).is_empty(), "a ground entry with an unknown item is rejected")
	var other := _bag()
	other.restore(JSON.parse_string(JSON.stringify(saved)))
	check(other.ground.size() == 1 and String(other.ground[0]["id"]) == "torch" and is_equal_approx(float(other.ground[0]["x"]), 10.0), "the ground list restores")
	other.restore(old)
	check(other.ground.is_empty(), "restoring an older save leaves the ground empty")
	check(bag.pick_up(0) == "torch" and bag.has("torch") and bag.ground.is_empty() and bag.take_notices().has("我：拿到了「手电筒」。"), "picking up returns the item through the ordinary bag message")
	bag.place_on_ground("chalk", "teach1", Vector3.ZERO)
	check(bag.pick_up(0) == "" and bag.ground.size() == 1 and bag.take_notices()[0].contains("已经带着一份"), "a second copy stays on the ground")
	bag.ground.clear()
	var full := _bag()
	for id: String in ["torch", "chalk", "pen", "watch", "pill", "snack", "card", "notebook"]:
		full.add(id)
	full.take_notices()
	full.place_on_ground("coin", "teach1", Vector3.ZERO)
	check(full.pick_up(0) == "" and full.ground.size() == 1 and full.take_notices().has("我：装不下了。"), "a full bag leaves the item where it lies")
	for i in InventoryModule.GROUND_MAX + 3:
		full.place_on_ground("coin", "teach1", Vector3(i, 0, 0))
	check(full.ground.size() == InventoryModule.GROUND_MAX and is_equal_approx(float(full.ground[-1]["x"]), InventoryModule.GROUND_MAX + 2), "the ground list is bounded and keeps the newest")
	full.reset()
	check(full.ground.is_empty(), "a new run starts with nothing on the ground")


func _app() -> GameApp:
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new(_test_path.get_base_dir() + "/ground/slot.json")
	app.settings = GameSettings.new(_test_path.get_base_dir() + "/ground/settings.json")
	root.add_child(app)
	return app


func test_app() -> void:
	var app := _app()
	await _frames(2)
	app.start_new_game("easy", "none")
	await _frames(2)
	app._stand_up()
	app.patrol().pat["safety"] = 999.0
	app.patrol().pat["next"] = 10000.0
	app.anomaly().an["next"] = 10000.0
	app.school().tsec = 900
	var room := CampusData.layout("teach1")
	var stand := Vector2.ZERO
	for r in range(2, (room["grid"] as Array).size() - 2):
		var row := String(room["grid"][r])
		for c in range(2, row.length() - 2):
			if row.substr(c, 1) == "." and row.substr(c, 3) == "..." and String(room["grid"][r - 1]).substr(c, 3) == "..." and String(room["grid"][r + 1]).substr(c, 3) == "...":
				stand = CampusGeometry.tile_center(room, c + 1, r)
				break
		if stand != Vector2.ZERO:
			break
	app.travel("teach1", _campus_pose(room, stand, 0.0), false)
	await _frames(4)
	var bag := app.items()
	bag.add("torch")
	bag.take_notices()
	bag.set_hot(0, "torch")
	app._open_bag()
	await _frames(2)
	app._drop_item("torch")
	await _frames(3)
	var world := app._campus_world()
	check(not bag.has("torch") and bag.ground.size() == 1 and String(bag.ground[0]["world"]) == "teach1", "dropping in a classroom leaves the item on the floor")
	check(world.ground_items.count() == 1 and world.ground_items.find_child("Ground_0_torch", true, false) != null, "the scene shows the dropped item")
	var art := world.ground_items.find_child("Art", true, false) as Sprite3D
	check(art != null and art.texture == UIArt.item("torch") and art.axis == Vector3.AXIS_Y, "the dropped item lies flat with its own illustration")
	check(world.ground_items.get_children().all(func(n: Node) -> bool: return n.find_children("*", "CollisionObject3D", true, false).is_empty()), "dropped items carry no collision")
	app._close_bag()
	await _frames(2)
	check(app._ground_target == -1, "looking straight ahead does not target the item at the feet")
	var down_pose := app.player.capture_pose()
	down_pose["pitch"] = -1.3
	app.player.restore_pose(down_pose)
	await _frames(3)
	check(app._ground_target == 0 and world.ground_items.focus() == 0, "the item in front is targeted")
	check(String(app.ui.get_node("%Prompt").text).contains("拾取「手电筒」"), "the prompt offers to pick it up")
	app.save_game(true)
	app.load_game()
	app.set_physics_process(true)
	await _frames(4)
	bag = app.items()
	world = app._campus_world()
	check(bag.ground.size() == 1 and world.ground_items.count() == 1, "the item on the floor survives save and load")
	app.player.request_interaction()
	await _frames(3)
	check(bag.has("torch") and bag.ground.is_empty() and world.ground_items.count() == 0, "the interact key picks the item back up and it leaves the floor")
	check(String(app.ui.get_node("%Prompt").text).find("拾取") < 0, "the pick prompt goes with the item")
	# Another scene does not show it; coming back does.
	app._drop_item("torch")
	var here := app.player.capture_pose()
	app.travel("teach2", _campus_pose(CampusData.layout("teach2"), stand, 0.0), false)
	await _frames(3)
	check(app._campus_world().ground_items.count() == 0 and app._ground_target == -1, "items lie only in the scene they were dropped in")
	app.travel("teach1", here, false)
	await _frames(3)
	check(app._campus_world().ground_items.count() == 1 and app._ground_target == 0, "coming back finds the item where it was")
	# Portal materials: still retakable at the source, and carrying one again marks it taken.
	bag.add("coil")
	app.facilities().flags["coil"] = true
	app._drop_item("coil")
	check(app.facilities().flags["coil"] == false and bag.ground.size() == 2, "a dropped door part lies on the floor and can also be taken again at the source")
	app._pick_up_ground(1)
	check(bag.has("coil") and app.facilities().flags["coil"] == true, "picking the door part up marks it carried again")
	app.return_to_menu()
	await _frames(2)
	app.queue_free()
	await _frames(1)


## The redesigned bag: slot grid with capacity, a detail pane for the selected item, the same actions.
func test_bag_ui() -> void:
	var app := _app()
	await _frames(2)
	var ui := app.ui
	var entries := [
		{"id": "torch", "name": "手电筒 · 开着", "short": "手电筒", "text": "光很弱。", "hot": 0},
		{"id": "phone", "name": "手机", "short": "手机", "text": "可以查看网络工具。", "hot": -1},
		{"id": "chalk", "name": "粉笔", "short": "粉笔", "text": "白的。", "hot": 1}]
	ui.show_bag(entries, 8)
	await _frames(3)
	var grid := ui.bag_panel.find_child("BagSlots", true, false) as GridContainer
	check(ui.bag_open() and grid.get_child_count() == 8, "the bag draws one slot per capacity place")
	check((ui.bag_panel.find_child("BagCount", true, false) as Label).text == "3 / 8", "the bag shows how full it is")
	check(grid.find_child("SlotEmpty_3", false, false) != null and grid.find_child("SlotEmpty_7", false, false) != null, "the free places are drawn as empty slots")
	check(ui.bag_selected() == "torch" and (grid.get_node("Slot_torch") as Button).button_pressed, "the first item is selected when the bag opens")
	check(grid.get_node("Slot_torch").find_child("SlotHot", false, false).text == "1" and grid.get_node("Slot_chalk").find_child("SlotHot", false, false).text == "2" and grid.get_node("Slot_phone").find_child("SlotHot", false, false) == null, "hot slot badges mark the items on the hot bar")
	check((ui.bag_panel.find_child("BagDetailName", true, false) as Label).text == "手电筒 · 开着" and (ui.bag_panel.find_child("BagDetailTag", true, false) as Label).text.contains("快捷栏 1"), "the detail pane names the selected item and its hot slot")
	var picked := [""]
	ui.item_drop_requested.connect(func(id: String) -> void: picked[0] = "drop:" + id)
	ui.item_use_requested.connect(func(id: String) -> void: picked[0] = "use:" + id)
	ui.item_hot_requested.connect(func(i: int, id: String) -> void: picked[0] = "hot%d:%s" % [i, id])
	await _tap(grid.get_node("Slot_phone"))
	check(ui.bag_selected() == "phone" and not (grid.get_node("Slot_torch") as Button).button_pressed, "tapping another slot moves the selection")
	check(ui.bag_panel.find_child("Item_torch_-1", true, false) == null and ui.bag_panel.find_child("Item_phone_-1", true, false) != null, "the actions belong to the selected item only")
	await _tap(ui.bag_panel.find_child("Item_phone_-1", true, false))
	check(picked[0] == "use:phone", "使用 uses the selected item")
	await _tap(ui.bag_panel.find_child("Item_phone_1", true, false))
	check(picked[0] == "hot1:phone", "the hot slot buttons still assign the item")
	await _tap(ui.bag_panel.find_child("Drop_phone", true, false))
	check(picked[0] == "drop:phone", "丢弃 still drops the item")
	ui.show_bag(entries.slice(1), 8)
	await _frames(2)
	check(ui.bag_selected() == "phone", "the selection survives a refresh while the item is still there")
	ui.show_bag([], 8)
	await _frames(2)
	check(ui.bag_panel.find_child("BagEmpty", true, false) != null and (ui.bag_panel.find_child("BagCount", true, false) as Label).text == "0 / 8", "an empty bag says so")
	for size: Vector2i in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(800, 450)]:
		root.size = size
		ui.show_bag(entries, 8)
		await _frames(4)
		var visible := root.get_visible_rect()
		var close := ui.bag_panel.find_child("BagClose", true, false) as Control
		check(visible.encloses(ui.bag_panel.get_global_rect()) and visible.encloses(close.get_global_rect()), "the bag and its close button fit a %dx%d landscape window" % [size.x, size.y])
	root.size = Vector2i(960, 540)
	ui.hide_bag()
	ui.show_hot("1 · 手电筒    2 · 空", ["torch", null], ["手电筒", "空"])
	check((ui.hud.find_child("HotName1", true, false) as Label).text == "手电筒" and (ui.hud.find_child("HotName2", true, false) as Label).text == "空", "the hot bar cards carry the item names")
	ui.show_notice("我：拿到了「手电筒」。")
	await _frames(2)
	var toast := ui.get_node("%Toast") as Label
	check(toast.visible and toast.size.x < root.get_visible_rect().size.x * 0.63 and toast.theme_type_variation == "HudPill", "notices sit on a pill sized to their text")
	app.queue_free()
	await _frames(1)
