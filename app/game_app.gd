class_name GameApp
extends Node
## Composition root: creates rules and connects input, worlds, UI and storage.

## Web version start: teach1, the player's own seat (ClassroomLayout.ownSeat).
@export var initial_world := "teach1"
@onready var router: WorldRouter = %WorldRouter
@onready var player: PlayerController = %Player
@onready var ui: GameUI = %UI

var session: GameSession
var saves := SaveStore.new()
var _hint_cooldown := 0.0


func _ready() -> void:
	ui.new_requested.connect(start_new_game)
	ui.load_requested.connect(load_game)
	ui.save_requested.connect(save_game)
	ui.menu_requested.connect(return_to_menu)
	ui.pause_requested.connect(pause_game)
	ui.resume_requested.connect(resume_game)
	ui.touch_move.connect(player.set_touch_move)
	ui.touch_look.connect(player.look_from_touch)
	ui.touch_sprint.connect(player.set_touch_sprint)
	ui.interact_requested.connect(player.request_interaction)
	player.focus_changed.connect(ui.show_prompt)
	player.interaction_requested.connect(_interact)
	player.free_interaction_requested.connect(_campus_interact)
	return_to_menu()


func _make_session() -> GameSession:
	var candidate := GameSession.new()
	for feature: FeatureModule in [DemoModule.new(), CampusData.make_module()]:
		var error := candidate.modules.register(feature)
		if not error.is_empty():
			push_error(error)
			return null
	return candidate


func campus() -> CampusModule:
	return session.modules.get_module(&"campus.world") as CampusModule if session != null else null


func start_new_game() -> void:
	var candidate := _make_session()
	if candidate == null:
		return
	var error := router.switch_to(initial_world)
	if not error.is_empty():
		ui.show_notice(error)
		return
	candidate.start(initial_world)
	var rules := candidate.modules.get_module(&"campus.world") as CampusModule
	var pose := rules.start_pose() if rules != null and initial_world == rules.start_world() else router.current.spawn_pose()
	_install_session(candidate, pose)
	if rules != null and rules.knows(initial_world):
		ui.show_notice(String(rules.room(initial_world)["name"]) if rules.room(initial_world) != null else "武大附中 · 校园")
	else:
		ui.show_notice("走到前方告示牌，按 E 或触屏交互。这里用于验证移植接口。")


func _install_session(candidate: GameSession, pose: Dictionary) -> void:
	if session != null:
		session.stop()
	session = candidate
	session.notice_requested.connect(ui.show_notice)
	var rules := campus()
	if rules != null:
		rules.door_changed.connect(_door_changed)
	_sync_world()
	player.restore_pose(pose)
	player.show()
	ui.set_save_available(saves.exists())
	resume_game()


func save_game() -> void:
	if session == null or not session.running:
		return
	var snapshot := session.capture(player.capture_pose())
	var error := session.validate(snapshot, router.known_ids())
	if error.is_empty():
		error = saves.write(snapshot)
	ui.show_notice("已保存测试进度。" if error.is_empty() else error)
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
	ui.show_notice("已恢复测试进度；读档不会再次触发交互奖励。")


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
	if session != null:
		session.stop()
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
		ui.show_location(_location_name())
		ui.show_runtime(session.clock.active_seconds)
		_campus_step(delta)


# ---- formal campus (features/campus) ----

func _campus_world() -> CampusWorld:
	return router.get_child(0) as CampusWorld if router.get_child_count() > 0 else null


func _sync_world() -> void:
	var world := _campus_world()
	var rules := campus()
	if world != null and rules != null:
		world.apply_doors(rules.open_doors())


func _door_changed(key: String, open: bool) -> void:
	var world := _campus_world()
	if world != null:
		world.set_door_open(key, open)


func _campus_step(delta: float) -> void:
	var rules := campus()
	if rules == null or not rules.knows(session.world_id) or not player.enabled:
		return
	var crossing := rules.crossing(session.world_id, player.capture_pose())
	if not crossing.is_empty():
		travel(crossing["world"], crossing["pose"], true)
	_hint_cooldown -= delta
	if _hint_cooldown <= 0.0 and not player.has_focus():
		_hint_cooldown = 0.1
		ui.show_prompt(rules.hint(session.world_id, player.capture_pose()))


func _campus_interact() -> void:
	var rules := campus()
	if session == null or get_tree().paused or rules == null or not rules.knows(session.world_id):
		return
	var result := rules.interact_at(session.world_id, player.capture_pose())
	var text := String(result.get("notice", ""))
	if result.has("toast"):
		text = text + "\n" + String(result["toast"])
	if result.has("travel"):
		travel(result["travel"]["world"], result["travel"]["pose"], false)
	if not text.is_empty():
		ui.show_notice(text)


## Switch scene inside the running session (old doEnterRoom / doExitRoom). Seamless moves keep input.
func travel(world_id: String, pose: Dictionary, seamless: bool) -> String:
	var error := router.switch_to(world_id)
	if not error.is_empty():
		ui.show_notice(error)
		return error
	session.world_id = world_id
	if seamless:
		player.place(pose)
	else:
		player.restore_pose(pose)
	_sync_world()
	_hint_cooldown = 0.0
	return ""


func _location_name() -> String:
	var rules := campus()
	if rules == null or session == null or not rules.knows(session.world_id):
		return "移植测试场景"
	return "武大附中 · 校园" if session.world_id == "out" else String(rules.room(session.world_id)["name"])


func _interact(id: StringName) -> void:
	if session != null and not get_tree().paused:
		session.interact(id)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not event.is_echo() and session != null:
		if get_tree().paused:
			resume_game()
		else:
			pause_game()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED] and is_node_ready():
		pause_game()


func _exit_tree() -> void:
	if session != null:
		session.stop()
	if get_tree() != null:
		get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
