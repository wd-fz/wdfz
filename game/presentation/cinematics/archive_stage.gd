class_name ArchiveStage
extends Node3D
## Disposable presentation-only stage. No GameSession, profile, achievements or save callbacks.
signal finished
const PLAYER := preload("res://game/presentation/actors/player.tscn")
var router: WorldRouter
var player: PlayerController
var audio: AudioFx
var ui: GameUI
var settings: GameSettings
var cut: Node
var death: DeathCG
var on := false
var elapsed := 0.0
var duration := 0.0
var _lift: ElevatorModule
var _skip: CanvasLayer
var _stop: Button
var _clock := 700.0

func begin(entry: Dictionary, worlds: Array[WorldDefinition], view: GameUI, options: GameSettings, muted: bool = false) -> String:
	ui = view
	settings = options
	process_mode = Node.PROCESS_MODE_ALWAYS
	router = WorldRouter.new()
	router.worlds = worlds
	add_child(router)
	player = PLAYER.instantiate()
	add_child(player)
	player.enabled = false
	player.set_physics_process(false)
	player.camera.make_current()
	audio = AudioFx.new()
	add_child(audio)
	audio.volume = settings.get_int("vol") / 100.0
	audio.muted = muted
	audio.ambience = false
	_lift = ElevatorModule.new(CampusData.rooms())
	_lift.reset()
	var kind := String(entry.get("cut",""))
	var stage := String(entry["stage"])
	if kind == "face": stage = "out"
	_clock = float(entry.get("hour",700.0/60.0))*60.0
	var error := router.switch_to(stage)
	if not error.is_empty(): return error
	var pose: Dictionary
	if stage == "out":
		var at: Dictionary = CampusData.archive()["outdoor"]
		var p := CampusGeometry.to_scene(null,Vector2(at["x"],at["y"]))
		pose = {"position":[p.x,0,p.y],"yaw":CampusGeometry.yaw_from_ang(at["ang"]),"pitch":0.0}
	elif stage == MazeModule.ROOM:
		var rng := RandomNumberGenerator.new()
		rng.seed = 97
		pose = CampusData.maze_geometry().spawn(rng)
	elif entry.has("at"):
		var room: Dictionary = CampusData.rules().room(stage)
		var at: Dictionary = entry["at"]
		var p := CampusGeometry.to_scene(room,Vector2(room["ox"]+at["c"]*room["tw"],room["oy"]+at["r"]*room["th"]))
		pose = {"position":[p.x,0,p.y],"yaw":CampusGeometry.yaw_from_ang(at["ang"]),"pitch":0.0}
	else:
		pose = CampusData.rules().default_spawn(stage)
	player.restore_pose(pose)
	on = true
	ui.set_mode("replay")
	ui.cut_mode(true)
	_light()
	if kind == "opening":
		var opening := OpeningCut.new()
		cut = opening
		add_child(opening)
		opening.audio = audio
		opening.finished.connect(func(_skipped: bool) -> void: _done())
		opening.begin(router.world_instance(),CampusData.rules().room(stage),player,ui,false)
	elif kind in ["void_in","void_out"]:
		var maze := MazeCut.new()
		cut = maze
		add_child(maze)
		var context := MazeCutStage.new()
		context.player = player
		context.ui = ui
		context.audio = audio
		context.settings = settings
		context.geometry = CampusData.maze_geometry()
		context.elevator = _lift
		context.campus = CampusData.rules()
		context.scene = func() -> String: return String(router.current.world_id)
		context.can_stand = _can_stand
		maze.finished.connect(_done)
		var door: Dictionary = context.geometry.cfg["exits"][0] if kind == "void_out" else {}
		maze.begin_stage("in" if kind == "void_in" else "out",context,door,_exit_maze)
		maze._controls.hide()
	elif kind != "":
		var ending := EndingCut.new()
		cut = ending
		add_child(ending)
		ending.audio = audio
		ending.finished.connect(func(_skipped: bool) -> void: _done())
		if kind == "portal": (router.world_instance() as CampusWorld).show_portal(true)
		var opts := {"tsec":_clock}
		if kind == "car": opts["switch"] = _car_out
		ending.begin(kind,router.world_instance(),CampusData.campus(),player,ui,func() -> void: audio.play("ui.beep"),opts)
	else:
		death = DeathCG.new()
		add_child(death)
		death.audio = audio
		var fx := String(entry["fx"])
		duration = maxf(3.5,DeathCG.duration(fx,StoryModule.duration(fx))+.6)
		death.begin(fx,player,router.world_instance(),ui,duration,settings.get_int("reduce_flash") != 0)
		audio.death(fx)
	if is_instance_valid(cut):
		cut.set_process_input(false)
		cut.set_process_unhandled_input(false)
	_skip = CanvasLayer.new()
	_skip.layer = 20
	add_child(_skip)
	_stop = Button.new()
	_stop.text = "返回档案馆"
	_stop.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_stop.position = Vector2(-194,-74)
	_stop.size = Vector2(170,50)
	_stop.pressed.connect(_done)
	_skip.add_child(_stop)
	return ""

func _light() -> void:
	var world := router.world_instance() as CampusWorld
	if world != null and world.lighting != null:
		world.lighting.update(0,_clock,player.camera)
		ui.scene_post().parameter("exposure",world.lighting.post_exposure)

func _can_stand(w: Vector2, room: Dictionary, height: float) -> bool:
	var p := CampusGeometry.to_scene(room,w)
	var shape := SphereShape3D.new()
	shape.radius = CampusGeometry.PRAD*CampusGeometry.U2M
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	query.transform = Transform3D(Basis(),Vector3(p.x,height+.9,p.y))
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _exit_maze() -> void:
	var travel: Dictionary = _lift.leave_maze("exit1")["travel"]
	router.switch_to(travel["world"])
	player.restore_pose(travel["pose"])
	_light()

func _car_out() -> Node3D:
	router.switch_to("out")
	_light()
	return router.world_instance()

func _process(dt: float) -> void:
	if not on: return
	elapsed += dt
	if is_instance_valid(_stop): _stop.disabled = elapsed < .4
	audio.update(dt,{"dead":true})
	if death != null:
		death.update(elapsed)
		if elapsed >= duration: _done()

func _input(event: InputEvent) -> void:
	if not on: return
	var key: bool = event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_SPACE,KEY_ENTER,KEY_ESCAPE]
	var tap: bool = event is InputEventScreenTouch and event.pressed
	var click: bool = event is InputEventMouseButton and event.pressed
	if key or tap or click:
		get_viewport().set_input_as_handled()
		if elapsed >= .4: _done()

func _done() -> void:
	if not on: return
	cancel()
	finished.emit()

func cancel() -> void:
	on = false
	if is_instance_valid(cut): cut.cancel()
	if is_instance_valid(death): death.finish()
	if is_instance_valid(audio): audio.stop_all()
	if is_instance_valid(_skip): _skip.hide()
	if is_instance_valid(ui):
		ui.cut_mode(false)
		ui.cut_caption("")
		ui.cut_flash(0)
		ui.cut_fade(0)
		ui.hide_death()
		ui.set_normal_world(0)
