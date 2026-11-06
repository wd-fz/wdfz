class_name GameApp
extends Node
## Composition root: creates rules and connects input, worlds, UI and storage.

@export var initial_world := "migration_lab"
@onready var router: WorldRouter = %WorldRouter
@onready var player: PlayerController = %Player
@onready var ui: GameUI = %UI

var session: GameSession
var saves := SaveStore.new()


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
	return_to_menu()


func _make_session() -> GameSession:
	var candidate := GameSession.new()
	var error := candidate.modules.register(DemoModule.new())
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
	ui.show_notice("走到前方告示牌，按 E 或触屏交互。这里用于验证移植接口。")


func _install_session(candidate: GameSession, pose: Dictionary) -> void:
	if session != null:
		session.stop()
	session = candidate
	session.notice_requested.connect(ui.show_notice)
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
		ui.show_runtime(session.clock.active_seconds)


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
