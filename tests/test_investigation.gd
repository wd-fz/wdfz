extends RefCounted

const APP := preload("res://scenes/app.tscn")
const CATALOG: ItemCatalog = preload("res://content/items/base_items.tres")
const WORLDS := ["investigation_slice", "migration_lab"]
var _assert: Callable
var _same_json: Callable
var _tree: SceneTree


func run(tree: SceneTree, assertion: Callable, same_json: Callable) -> void:
	_tree = tree
	_assert = assertion
	_same_json = same_json
	_test_rules()
	await _test_scene()


func check(condition: bool, text: String) -> void:
	_assert.call(condition, "M1: " + text)


func _inventory() -> InventoryModule:
	return InventoryModule.new(CATALOG.to_data(), PackedStringArray(WORLDS))


func _test_rules() -> void:
	check(CATALOG.validate().is_empty(), "item catalog valid")
	var inventory := _inventory()
	check(inventory.items() == ["card"], "new player carries a student card")
	check(inventory.try_add("card") == InventoryModule.AddResult.DUPLICATE, "duplicate does not use a slot")
	check(inventory.try_add("undefined") == InventoryModule.AddResult.INVALID, "unknown item refused")
	var quest := InvestigationModule.new(inventory)
	quest.interact(&"investigation.door")
	check(not quest.door_open() and quest.notes().size() == 1, "locked door records a useful clue")
	quest.interact(&"investigation.desk")
	quest.interact(&"investigation.desk")
	quest.interact(&"investigation.notice")
	check(quest.notes().size() == 3, "rereading clues does not duplicate them")
	var notes := quest.notes()
	notes[0]["text"] = "mutated view"
	check(quest.notes()[0]["text"] != "mutated view", "notes are isolated view data")
	for id: String in ["chalk", "pen", "notebook", "torch", "key", "coin", "map"]:
		check(inventory.try_add(id) == InventoryModule.AddResult.ADDED, "fill a real slot with " + id)
	var before := quest.capture()
	quest.interact(&"investigation.cabinet")
	check(quest.capture() == before and quest.key_available(), "full bag does not consume the key source")
	check(inventory.items().size() == 8, "capacity remains eight")
	check(not inventory.set_quick(0, "roomkey") and not inventory.select(8), "invalid selection and unowned quick slots rejected")
	check(inventory.set_quick(0, "map") and inventory.set_quick(1, "map"), "two quick slots may refer to the same held item")
	inventory.drop("map", "investigation_slice", [0.0, 0.0, 0.0])
	check(inventory.quick_slots() == ["", ""] and not inventory.has("map"), "drop clears both quick references")
	check(inventory.owns("map") and inventory.dropped_in("investigation_slice").has("map"), "dropped item remains owned and located")
	quest.interact(&"investigation.cabinet")
	check(inventory.has("roomkey") and not quest.key_available(), "retry after freeing a slot gives the key once")
	quest.interact(&"investigation.cabinet")
	check(inventory.items().count("roomkey") == 1, "repeated cabinet interaction cannot duplicate key")
	inventory.pickup("map")
	check(not inventory.has("map") and inventory.owns("map"), "full pickup preserves ground item")
	inventory.drop("coin", "investigation_slice", [1.0, 0.0, 0.0])
	inventory.pickup("map")
	check(inventory.has("map") and not inventory.dropped_in("investigation_slice").has("map"), "ground pickup after freeing space succeeds")
	var items := inventory.items()
	items.clear()
	check(inventory.items().size() == 8, "bag views cannot mutate rule state")
	quest.interact(&"investigation.door")
	check(quest.door_open() and inventory.has("roomkey"), "door opens without consuming key")
	quest.interact(&"investigation.door")
	check(not quest.door_open(), "door can close again")
	inventory.drop("roomkey", "investigation_slice", [0.0, 0.0, 1.0])
	quest.interact(&"investigation.door")
	check(not quest.door_open(), "key on ground cannot operate the lock")
	check(not quest.key_available(), "dropped key does not respawn in cabinet")
	var host := ModuleHost.new()
	host.register(inventory)
	host.register(quest)
	var state := host.capture()
	check(host.validate(state).is_empty(), "key on ground is valid persistent progress")
	var invalid := state.duplicate(true)
	invalid[String(InventoryModule.ID)]["data"]["ground"].erase("roomkey")
	check(not host.validate(invalid).is_empty(), "cross-module validation refuses a disappeared critical key")
	check(host.capture() == state, "validation does not mutate live progress")
	var restored_inventory := _inventory()
	var restored_quest := InvestigationModule.new(restored_inventory)
	var restored_host := ModuleHost.new()
	restored_host.register(restored_inventory)
	restored_host.register(restored_quest)
	restored_host.restore(state)
	check(restored_host.capture() == state, "full module state restores without rewards")
	restored_inventory.pickup("roomkey")
	check(restored_inventory.has("roomkey"), "critical key can be recovered after reload")
	var bad := inventory.capture()
	bad["items"].append("map")
	check(not inventory.validate(bad).is_empty(), "over-capacity or duplicate bag rejected")
	bad = inventory.capture()
	bad["quick"][0] = "unowned"
	check(not inventory.validate(bad).is_empty(), "dangling quick slot rejected")
	bad = inventory.capture()
	bad["ground"]["coin"]["world_id"] = "res://forged.tscn"
	check(not inventory.validate(bad).is_empty(), "ground pickup world is registered by ID")
	bad = inventory.capture()
	bad["ground"]["coin"]["position"][0] = INF
	check(not inventory.validate(bad).is_empty(), "non-finite ground coordinate rejected")
	var previous := inventory.capture()
	inventory.drop("map", "unknown", [0, 0, 0])
	check(inventory.capture() == previous, "failed drop leaves bag unchanged")
	check(restored_host.validate({}).is_empty(), "old framework saves may lack new modules")
	restored_host.restore({})
	check(restored_inventory.items() == ["card"] and restored_quest.notes().is_empty(), "missing modules start from defaults")
	_test_player_state()


func _test_player_state() -> void:
	var stats := PlayerStateModule.new()
	check(stats.capture() == {"san": 100.0, "violation": 0.0, "assimilation": 0.0, "stamina": 100.0}, "legacy initial player values")
	stats.change_san(-50)
	check(stats.stamina_max() == 70 and stats.capture()["stamina"] == 70, "SAN-derived stamina cap matches old formula")
	stats.change_stamina(-1000)
	stats.change_stamina(1000)
	check(stats.capture()["stamina"] == 70, "stamina spending and recovery bounded by current cap")
	stats.change_san(-1000)
	check(stats.capture()["san"] == 0 and stats.stamina_max() == 40, "SAN lower bound and minimum stamina cap")
	stats.change_violation(20, true)
	check(stats.capture()["violation"] == 0, "ordinary violation respects exemption")
	stats.change_violation(20, true, true)
	check(stats.capture()["violation"] == 20, "inspection bypasses exemption")
	stats.change_violation(-1000)
	stats.change_assimilation(1000)
	check(stats.capture()["violation"] == 0 and stats.capture()["assimilation"] == 100, "violation and assimilation clamp")
	var state := stats.capture()
	stats.change_san(NAN)
	check(stats.capture() == state, "invalid numeric mutation ignored")
	var invalid := state.duplicate()
	invalid["stamina"] = 100
	check(not stats.validate(invalid).is_empty(), "incompatible saved stamina rejected")
	var restored := PlayerStateModule.new()
	restored.restore(state)
	check(restored.capture() == state, "player values restored without reapplying effects")


func _frames(count: int = 2) -> void:
	for _i in count:
		await _tree.physics_frame
		await _tree.process_frame


func _aim(player: PlayerController, point: Vector3) -> void:
	var direction := point - player.camera.global_position
	var yaw := atan2(-direction.x, -direction.z)
	var pitch := atan2(direction.y, Vector2(direction.x, direction.z).length())
	player.apply_look(Vector2(wrapf(player.rotation.y - yaw, -PI, PI), player.camera.rotation.x - pitch))


func _walk(app: GameApp, target: Vector3) -> void:
	for _i in 240:
		var direction := Vector3(target.x - app.player.position.x, 0, target.z - app.player.position.z)
		if direction.length() < 0.13:
			break
		_aim(app.player, app.player.camera.global_position + direction)
		Input.action_press("move_forward")
		await _frames(1)
	Input.action_release("move_forward")
	await _frames()
	check(Vector2(app.player.position.x - target.x, app.player.position.z - target.z).length() < 0.2, "walk to %s through actual physics" % target)


func _interact(app: GameApp, point: Vector3, expected_id: String) -> void:
	_aim(app.player, point)
	app.player.ray.force_raycast_update()
	var target := app.player.ray.get_collider() as WorldInteractable
	check(target != null and String(target.interaction_id) == expected_id, "line of sight targets " + expected_id)
	var event := InputEventAction.new()
	event.action = &"interact"
	event.pressed = true
	Input.parse_input_event(event)
	await _frames()
	event = InputEventAction.new()
	event.action = &"interact"
	event.pressed = false
	Input.parse_input_event(event)
	await _frames()


func _tap(control: Control) -> void:
	await _frames()
	var where := _tree.root.get_final_transform() * control.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.pressed = pressed
		event.position = where
		Input.parse_input_event(event)
		await _frames()


func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames()


func _test_scene() -> void:
	var path := "user://framework-tests/m1-%s/slot.json" % Time.get_ticks_usec()
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new(path)
	_tree.root.size = Vector2i(1280, 720)
	_tree.root.add_child(app)
	await _frames()
	await _tap(app.ui.get_node("%NewGame"))
	check(app.session != null and app.session.world_id == "investigation_slice", "default menu starts first investigation")
	await _interact(app, Vector3(0, 0.89, 1), "investigation.desk")
	await _walk(app, Vector3(-4, 0, -0.6))
	await _interact(app, Vector3(-4, 1.42, -2.04), "investigation.notice")
	await _walk(app, Vector3(0, 0, -2.5))
	_aim(app.player, app.player.camera.global_position + Vector3(0, 0, -1))
	Input.action_press("move_forward")
	await _frames(35)
	Input.action_release("move_forward")
	check(app.player.position.z > -3.75, "closed door physically blocks the player")
	await _walk(app, Vector3(1.6, 0, -2.0))
	await _interact(app, Vector3(1.6, 1.35, -3.7), "investigation.door")
	check(not app.investigation().door_open(), "actual door stays locked without key")
	await _walk(app, Vector3(4, 0, -0.7))
	await _interact(app, Vector3(4, 1.25, -2.1), "investigation.cabinet")
	check(app.inventory().has("roomkey"), "walking and interacting acquires key")
	await _frames()
	check(app.saves.exists(), "progress automatically saved")
	await _walk(app, Vector3(1.6, 0, -2.0))
	await _interact(app, Vector3(1.6, 1.35, -3.7), "investigation.door")
	check(app.investigation().door_open() and app.inventory().has("roomkey"), "actual door opens and retains key")
	await _walk(app, Vector3(0, 0, -4))
	await _interact(app, Vector3(1.6, 1.35, -3.7), "investigation.door")
	check(app.investigation().door_open(), "physics guard prevents closing on player in doorway")
	await _walk(app, Vector3(0, 0, -5.5))
	check(app.player.position.z < -5, "player passes through opened door into room")
	app.pause_game()
	app.save_game()
	var saved: Dictionary = app.saves.read()["data"]
	var old_session := app.session
	app.load_game()
	app.pause_game()
	check(app.session != old_session and _same_json.call(app.session.capture(app.player.capture_pose()), saved), "complete first-flow save restores state and pose")
	await _frames()
	check(app.router.world_instance().get_node("%DoorCollision").disabled and not app.router.world_instance().get_node("%CabinetKey").visible, "loaded visual and collision state matches rules")
	var missing_key := saved.duplicate(true)
	missing_key["modules"][String(InventoryModule.ID)]["data"]["items"].erase("roomkey")
	var current_session := app.session
	var current_world := app.router.world_instance()
	app.saves.write(missing_key)
	app.load_game()
	check(app.session == current_session and app.router.world_instance() == current_world and _tree.paused, "lost-key save is rejected before live state changes")
	app.save_game()
	await _tap(app.ui.get_node("%PauseInventory"))
	check(app.ui.inventory_panel.visible and _tree.paused, "backpack opened from pause remains paused")
	await _tap(app.ui.inventory_panel.get_node("%Close"))
	check(app.ui.pause_panel.visible and _tree.paused, "closing backpack returns to original pause")
	app.resume_game()
	await _tap(app.ui.get_node("%InventoryButton"))
	check(app.ui.inventory_panel.visible and not app.player.enabled, "touch HUD opens backpack and disables world input")
	var inventory_scroll: ScrollContainer = app.ui.inventory_panel.get_node("Margin/Page/Scroll")
	inventory_scroll.scroll_vertical = 0
	await _frames()
	await _tap(app.ui.inventory_panel.get_node("%Slots").get_child(1))
	check(app.inventory().selected_id() == "roomkey", "touch slot selects the key")
	inventory_scroll.ensure_control_visible(app.ui.inventory_panel.get_node("%Quick1"))
	await _frames()
	await _tap(app.ui.inventory_panel.get_node("%Quick1"))
	check(app.inventory().quick_slots()[0] == "roomkey", "touch quick-slot button assigns selected key")
	inventory_scroll.ensure_control_visible(app.ui.inventory_panel.get_node("%Drop"))
	await _frames()
	await _tap(app.ui.inventory_panel.get_node("%Drop"))
	check(not app.inventory().has("roomkey") and app.inventory().owns("roomkey"), "UI drops critical item into persistent world state")
	check(app.inventory().quick_slots()[0] == "", "dropping clears the selected quick slot")
	check(app.ground_items.get_child_count() == 1, "dropped key is represented in the world")
	await _tap(app.ui.inventory_panel.get_node("%Close"))
	app.pause_game()
	app.save_game()
	app.load_game()
	await _frames()
	check(app.ground_items.get_child_count() == 1 and not app.investigation().key_available(), "reload rebuilds drop without respawning source key")
	await _walk(app, Vector3(0, 0, -6.4))
	if app.ground_items.get_child_count() > 0:
		var ground: Node3D = app.ground_items.get_child(0)
		await _interact(app, ground.global_position, "inventory.pickup.roomkey")
	check(app.inventory().has("roomkey") and app.ground_items.get_child_count() == 0, "physical raycast recovers dropped key after reload")
	await _key(KEY_TAB)
	check(app.ui.inventory_panel.visible and _tree.paused, "physical Tab opens inventory before GUI focus consumes it")
	var elapsed := app.session.clock.active_seconds
	await _frames(4)
	check(app.session.clock.active_seconds == elapsed, "inventory freezes world time")
	await _key(KEY_TAB)
	check(not _tree.paused and not app.ui.inventory_panel.visible, "second Tab closes inventory")
	await _key(KEY_ESCAPE)
	await _key(KEY_TAB)
	check(app.ui.inventory_panel.visible and _tree.paused, "keyboard opens inventory from pause menu")
	await _key(KEY_ESCAPE)
	check(app.ui.pause_panel.visible and _tree.paused, "Escape returns from inventory to preexisting pause")
	await _key(KEY_ESCAPE)
	check(not _tree.paused and app.player.enabled, "Escape then resumes normally")
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(390, 844), Vector2i(844, 390)]:
		_tree.root.size = size
		await _frames()
		await _tap(app.ui.get_node("%InventoryButton"))
		var panel := app.ui.inventory_panel
		var scroll: ScrollContainer = panel.get_node("Margin/Page/Scroll")
		check(scroll.get_child(0).get_combined_minimum_size().x <= scroll.size.x + 1, "inventory has no horizontal overflow %s" % size)
		check(_tree.root.get_visible_rect().encloses(panel.get_node("%Close").get_global_rect()), "inventory close reachable %s" % size)
		await _tap(panel.get_node("%Close"))
		check(not _tree.paused and app.player.enabled, "inventory restores play after close %s" % size)
	var last_saved: Dictionary = app.saves.read()["data"]
	var previous_inventory := app.inventory()
	app.inventory().select(0) # Queue an old-session autosave, then replace the run.
	app.return_to_menu()
	app.start_new_game()
	previous_inventory.try_add("coin") # A stale owner must also be disconnected.
	await _frames()
	check(_same_json.call(app.saves.read()["data"], last_saved), "pending saves and stale module signals cannot write into a new run")
	check(app.inventory().items() == ["card"] and app.investigation().notes().is_empty() and app.investigation().key_available(), "new game clears clues, drops and old progress")
	check(app.ground_items.get_child_count() == 0, "new run does not inherit ground models")
	app.return_to_menu()
	app.queue_free()
	await _frames()
	for suffix: String in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
	DirAccess.remove_absolute(path.get_base_dir())
