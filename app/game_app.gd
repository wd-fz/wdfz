class_name GameApp
extends Node
## Composition root: creates rules and connects input, worlds, UI and storage.

@export var initial_world := "investigation_slice"
@export var item_catalog: ItemCatalog = preload("res://content/items/base_items.tres")
@onready var router: WorldRouter = %WorldRouter
@onready var player: PlayerController = %Player
@onready var ui: GameUI = %UI
@onready var ground_items: GroundItemView = %GroundItems

var session: GameSession
var saves := SaveStore.new()
var _inventory_return_mode := "play"
var _pending_save: GameSession


func _ready() -> void:
	ui.new_requested.connect(start_new_game)
	ui.load_requested.connect(load_game)
	ui.save_requested.connect(save_game)
	ui.menu_requested.connect(return_to_menu)
	ui.pause_requested.connect(pause_game)
	ui.resume_requested.connect(resume_game)
	ui.inventory_requested.connect(open_inventory)
	ui.inventory_closed.connect(close_inventory)
	ui.drop_requested.connect(drop_item)
	ui.touch_move.connect(player.set_touch_move)
	ui.touch_look.connect(player.look_from_touch)
	ui.touch_sprint.connect(player.set_touch_sprint)
	ui.interact_requested.connect(player.request_interaction)
	player.focus_changed.connect(ui.show_prompt)
	player.interaction_requested.connect(_interact)
	player.interaction_rejected.connect(ui.show_notice)
	return_to_menu()


func _make_session() -> GameSession:
	if item_catalog == null or not item_catalog.validate().is_empty():
		ui.show_notice("物品目录配置错误，无法开始。")
		return null
	var definitions := item_catalog.to_data()
	if not definitions.has("card") or not definitions.has("roomkey"):
		ui.show_notice("物品目录缺少学生证或机房钥匙，无法开始。")
		return null
	var candidate := GameSession.new()
	var inventory := InventoryModule.new(definitions, router.known_ids())
	var features: Array[FeatureModule] = [DemoModule.new(), inventory, PlayerStateModule.new(), InvestigationModule.new(inventory)]
	for feature: FeatureModule in features:
		var error := candidate.modules.register(feature)
		if not error.is_empty():
			push_error(error)
			return null
	return candidate


func start_new_game() -> void:
	var candidate := _make_session()
	if candidate == null:
		return
	var error := router.switch_to(initial_world)
	if not error.is_empty():
		ui.show_notice(error)
		return
	candidate.start(initial_world)
	_install_session(candidate, router.current.spawn_pose())
	ui.show_notice("查看课桌、讲台和校长室抽屉，找到机房钥匙。Tab 或右上角「背包」重读记录。" if initial_world == "investigation_slice" else "走到前方告示牌，按 E 或触屏交互。这里用于验证移植接口。")


func _install_session(candidate: GameSession, pose: Dictionary) -> void:
	_detach_session()
	session = candidate
	_pending_save = null
	session.notice_requested.connect(ui.show_notice)
	inventory().changed.connect(_on_progress_changed)
	investigation().changed.connect(_on_progress_changed)
	player.restore_pose(pose)
	player.show()
	ground_items.bind_rules(inventory(), session.world_id)
	var view := router.world_instance() as InvestigationView
	if view != null:
		view.bind_rules(inventory(), investigation())
	_refresh_progress()
	ui.set_save_available(saves.exists())
	resume_game()


func save_game(silent: bool = false) -> void:
	if session == null or not session.running:
		return
	var snapshot := session.capture(player.capture_pose())
	var error := session.validate(snapshot, router.known_ids())
	if error.is_empty():
		error = saves.write(snapshot)
	if not silent or not error.is_empty():
		ui.show_notice("已保存进度。" if error.is_empty() else error)
	ui.set_save_available(saves.exists())


func load_game() -> void:
	var result := saves.read()
	if result.has("error"):
		ui.show_notice(result["error"])
		return
	var candidate := _make_session()
	if candidate == null:
		return
	var data: Dictionary = result["data"]
	var error := candidate.validate(data, router.known_ids())
	if not error.is_empty():
		ui.show_notice(error)
		return
	error = router.switch_to(data["world_id"])
	if not error.is_empty():
		ui.show_notice(error)
		return
	candidate.restore(data)
	_install_session(candidate, data["player"])
	ui.show_notice("已恢复进度。")


func pause_game() -> void:
	if session == null or not session.running:
		return
	player.enabled = false
	player.clear_input()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.set_mode("pause")


func resume_game() -> void:
	if session == null or not session.running:
		return
	get_tree().paused = false
	player.enabled = true
	player.clear_input()
	ui.set_mode("play")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if ui.touch_enabled() else Input.MOUSE_MODE_CAPTURED


func return_to_menu() -> void:
	_pending_save = null
	ground_items.clear()
	_detach_session()
	session = null
	player.enabled = false
	player.clear_input()
	player.hide()
	router.clear()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.set_mode("menu")
	ui.set_save_available(saves.exists())
	ui.show_notice("")


func _physics_process(delta: float) -> void:
	if session != null and session.running and not get_tree().paused:
		session.advance(delta, router.current.advances_calendar)
		ui.show_runtime(session.clock.active_seconds)


func _interact(id: StringName) -> void:
	if session != null and not get_tree().paused:
		session.interact(id)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory") and not event.is_echo() and session != null:
		if ui.inventory_panel.visible:
			close_inventory()
		else:
			open_inventory()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause") and not event.is_echo() and session != null:
		if ui.inventory_panel.visible:
			close_inventory()
		elif get_tree().paused:
			resume_game()
		else:
			pause_game()
		get_viewport().set_input_as_handled()
	if session != null and not get_tree().paused:
		for index in 2:
			if event.is_action_pressed("quick_%d" % (index + 1)) and not event.is_echo():
				var id: String = inventory().quick_slots()[index]
				var details := inventory().details(id)
				ui.show_notice("快捷栏为空，可以在背包中设置。" if details.is_empty() else details["name"] + "：" + details["description"])
				get_viewport().set_input_as_handled()


func inventory() -> InventoryModule:
	return session.modules.feature(InventoryModule.ID) as InventoryModule if session != null else null


func investigation() -> InvestigationModule:
	return session.modules.feature(InvestigationModule.ID) as InvestigationModule if session != null else null


func open_inventory() -> void:
	if session == null or not session.running or ui.inventory_panel.visible:
		return
	_inventory_return_mode = "pause" if get_tree().paused else "play"
	player.enabled = false
	player.clear_input()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.set_mode("inventory")
	ui.inventory_panel.present(inventory(), investigation())


func close_inventory() -> void:
	if not ui.inventory_panel.visible:
		return
	if _inventory_return_mode == "pause":
		pause_game()
	else:
		resume_game()


func drop_item(id: String) -> void:
	if session == null or not ui.inventory_panel.visible:
		return
	ui.show_notice(inventory().drop(id, session.world_id, player.capture_pose()["position"]))


func _refresh_progress() -> void:
	if session != null:
		ui.show_objective(investigation().objective() if session.world_id == "investigation_slice" else "查看前方告示牌；Tab 可打开背包和记录。")


func _on_progress_changed() -> void:
	_refresh_progress()
	_pending_save = session


func _process(_delta: float) -> void:
	if _pending_save != null:
		var owner := _pending_save
		_pending_save = null
		if owner == session and session.running:
			save_game(true)


func _detach_session() -> void:
	if session == null:
		return
	var bag := inventory()
	var story := investigation()
	if bag != null and bag.changed.is_connected(_on_progress_changed):
		bag.changed.disconnect(_on_progress_changed)
	if story != null and story.changed.is_connected(_on_progress_changed):
		story.changed.disconnect(_on_progress_changed)
	session.stop()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED] and is_node_ready():
		pause_game()


func _exit_tree() -> void:
	_detach_session()
	if get_tree() != null:
		get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
