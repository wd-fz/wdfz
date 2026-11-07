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
var _choice_handler: Callable


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
	ui.choice_selected.connect(_choice_made)
	ui.lift_close_requested.connect(_lift_close)
	return_to_menu()


func _make_session() -> GameSession:
	var candidate := GameSession.new()
	for feature: FeatureModule in [DemoModule.new(), CampusData.make_module(), ElevatorModule.new(CampusData.rooms()),
			SchoolModule.new(CampusData.rooms(), CampusData.layout("out"), CampusData.campus())]:
		var error := candidate.modules.register(feature)
		if not error.is_empty():
			push_error(error)
			return null
	return candidate


func campus() -> CampusModule:
	return session.modules.get_module(&"campus.world") as CampusModule if session != null else null


func school() -> SchoolModule:
	return session.modules.get_module(&"school.day") as SchoolModule if session != null else null


func elevator() -> ElevatorModule:
	return session.modules.get_module(&"campus.elevator") as ElevatorModule if session != null else null


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
	# Game.start: the run begins seated on the player's own seat in teach1.
	var day_rules := candidate.modules.get_module(&"school.day") as SchoolModule
	if day_rules != null and rules != null and initial_world == rules.start_world():
		var seated := day_rules.start_seated(initial_world)
		if not seated.is_empty():
			pose = seated
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
	var day_rules := school()
	player.seated = day_rules != null and day_rules.seated
	var lift_rules := elevator()
	if lift_rules != null and day_rules != null:
		lift_rules.unsafe_check = day_rules.inspection_pending
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
	ui.hide_choice()
	ui.reset_status()
	player.seated = false
	_choice_handler = Callable()
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
		if school() == null or campus() == null or not campus().knows(session.world_id):
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
	var lift := elevator()
	if world != null and lift != null:
		world.set_lift_doors(lift.door_amount_in(session.world_id))


func _door_changed(key: String, open: bool) -> void:
	var world := _campus_world()
	if world != null:
		world.set_door_open(key, open)


func _campus_step(delta: float) -> void:
	var rules := campus()
	if rules == null or not rules.knows(session.world_id):
		return
	_school_step(delta, rules)
	var lift := elevator()
	if lift != null:
		var stepped := lift.step(delta, session.world_id, player.capture_pose())
		_apply_result(stepped)
		for text: String in lift.take_notices():
			ui.show_notice(text)
		var world := _campus_world()
		if world != null:
			world.set_lift_doors(lift.door_amount_in(session.world_id))
		ui.set_lift_close(lift.show_close_button(session.world_id, player.capture_pose()) and not ui.choice_open())
		if player.enabled and Input.is_action_just_pressed("lift_close"):
			_lift_close()
	if not player.enabled:
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
	var pose := player.capture_pose()
	var day_rules := school()
	# tryInteract: a seated player stands up first.
	if day_rules != null and day_rules.seated:
		_stand_up("我站了起来。")
		return
	var lift := elevator()
	var result: Dictionary
	var room: Variant = rules.room(session.world_id)
	var here := CampusGeometry.to_world(room, float(pose["position"][0]), float(pose["position"][2])) if room != null else Vector2.ZERO
	# elevator.js 'interact' hook first: inside a cabin (or a ride room) the panel answers.
	if lift != null and room != null and (session.world_id in ElevatorModule.RIDE_ROOMS or lift.in_cabin(session.world_id, here)):
		result = lift.use_at(session.world_id, here)
	else:
		result = rules.interact_at(session.world_id, pose)
		if result.get("elevator", false) and lift != null:
			result = lift.use_at(session.world_id, here)
	_apply_result(result)


func _apply_result(result: Dictionary) -> void:
	if result.is_empty():
		return
	if result.has("choice"):
		_open_choice(result["choice"])
	if result.has("seat") and school() != null:
		var sat := school().sit(session.world_id, int(result["seat"][0]), int(result["seat"][1]))
		if not sat.is_empty():
			player.restore_pose(sat["pose"])
			player.seated = true
			ui.show_notice(sat["notice"])
		return
	var text := String(result.get("notice", ""))
	if result.has("toast"):
		text = text + "\n" + String(result["toast"])
	if result.has("travel"):
		travel(result["travel"]["world"], result["travel"]["pose"], bool(result["travel"].get("seamless", false)))
	if not text.is_empty():
		ui.show_notice(text)


func _stand_up(text: String = "") -> void:
	var day_rules := school()
	if day_rules == null:
		return
	var stood := day_rules.stand_up()
	player.seated = false
	if stood.has("pose"):
		var pose: Dictionary = stood["pose"]
		pose["yaw"] = player.capture_pose()["yaw"]
		pose["pitch"] = player.capture_pose()["pitch"]
		player.place(pose)
	if not text.is_empty():
		ui.show_notice(text)


func _school_step(delta: float, rules: CampusModule) -> void:
	var day_rules := school()
	if day_rules == null:
		return
	if day_rules.seated and player.wants_move():
		_stand_up()
	var pose := player.capture_pose()
	var room: Variant = rules.room(session.world_id)
	var p: Array = pose["position"]
	day_rules.step(delta, {"world_id": session.world_id, "w": CampusGeometry.to_world(room, float(p[0]), float(p[2])),
		"height": float(p[1]), "moving": player.moving, "running": player.sprinting, "calendar": router.current.advances_calendar,
		"ang": CampusGeometry.ang_from_yaw(float(pose["yaw"])), "pitch": float(pose["pitch"]),
		"can_stand": _can_stand.bind(room, float(p[1])), "line_clear": _line_clear.bind(room)})
	var world := _campus_world()
	if world != null:
		world.show_silhouettes(day_rules.inspection_points(), room, float(p[1]))
	player.can_sprint = day_rules.can_run()
	for text: String in day_rules.take_notices():
		ui.show_notice(text)
	var frozen := not router.current.advances_calendar
	ui.show_status(day_rules.place_name(session.world_id, float(p[1])), day_rules.period_text(frozen), day_rules.period_class(frozen), day_rules.clock_text(false))
	ui.show_stamina(day_rules.stam, day_rules.stamina_max(), day_rules.tired)


## canStand (world.js): is there room for the body (radius 3 units) at this old world point?
func _can_stand(w: Vector2, room: Variant, height: float) -> bool:
	var world := _campus_world()
	if world == null:
		return false
	var s := CampusGeometry.to_scene(room, w)
	var shape := SphereShape3D.new()
	shape.radius = CampusGeometry.PRAD * CampusGeometry.U2M
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	query.transform = Transform3D(Basis(), Vector3(s.x, height + 0.9, s.y))
	return world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


## inspection.js lineClear: indoors walls and closed doors on the tile grid; outdoors solid obstacles.
func _line_clear(a: Vector2, b: Vector2, room: Variant) -> bool:
	var n := int(ceil(a.distance_to(b) / 3.0))
	var rules := campus()
	for i in range(1, n):
		var p := a.lerp(b, float(i) / n)
		if room != null:
			var ch := CampusGeometry.tile_at(room, p)
			if ch == "#":
				return false
			if ch == "=":
				var c := int(floor((p.x - float(room["ox"])) / float(room["tw"])))
				var r := int(floor((p.y - float(room["oy"])) / float(room["th"])))
				if not rules.is_open(CampusGeometry.door_key(room, c, r)):
					return false
		elif not _can_stand_point(p):
			return false
	return true


func _can_stand_point(w: Vector2) -> bool:
	var world := _campus_world()
	if world == null:
		return true
	var s := CampusGeometry.to_scene(null, w)
	var query := PhysicsPointQueryParameters3D.new()
	query.position = Vector3(s.x, 1.0, s.y)
	query.collision_mask = 1
	return world.get_world_3d().direct_space_state.intersect_point(query, 1).is_empty()


func _open_choice(choice: Dictionary) -> void:
	var values: Array = choice["values"]
	_choice_handler = func(index: int) -> void:
		var lift := elevator()
		if index >= 0 and index < values.size() and lift != null:
			_apply_result(lift.press(values[index], session.world_id, player.capture_pose()))
	player.enabled = false
	player.clear_input()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.show_choice(String(choice["text"]), choice["labels"])


func _choice_made(index: int) -> void:
	ui.hide_choice()
	var handler := _choice_handler
	_choice_handler = Callable()
	if session != null and session.running and not get_tree().paused:
		player.enabled = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if ui.touch_enabled() else Input.MOUSE_MODE_CAPTURED
	if handler.is_valid():
		handler.call(index)


func _lift_close() -> void:
	var lift := elevator()
	var room: Variant = campus().room(session.world_id) if campus() != null and session != null else null
	if lift == null or room == null:
		return
	var p: Array = player.capture_pose()["position"]
	lift.close_door(session.world_id, CampusGeometry.to_world(room, float(p[0]), float(p[2])))


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
