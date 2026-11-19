class_name StudentStudio
extends SubViewportContainer
## A single isolated mobile-sized portrait stage, allocated only while picking.
var actor: StudentAvatar
var viewport_3d: SubViewport
var cam: Camera3D
var action := "idle"
var _drag := -2
var _elapsed := 0.0
var _angle := -0.22
var _close_up := false


func _ready() -> void:
	stretch = true
	mouse_filter = MOUSE_FILTER_STOP
	viewport_3d = SubViewport.new()
	viewport_3d.own_world_3d = true
	viewport_3d.transparent_bg = true
	viewport_3d.msaa_3d = Viewport.MSAA_2X
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport_3d.gui_disable_input = true
	add_child(viewport_3d)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("162632")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("ece5dd")
	environment.ambient_light_energy = .67
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport_3d.add_child(world)
	_lamp(Vector3(-2, 3, -3), Color("fff1e4"), 0.95)
	_lamp(Vector3(2, 2, 1), Color("c8e1ff"), 0.86)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	viewport_3d.add_child(cam)
	actor = StudentAvatar.new()
	viewport_3d.add_child(actor)
	set_close_up(false)
	resized.connect(_resolution)
	visibility_changed.connect(_visibility)
	_resolution()
	_visibility()


func _lamp(at: Vector3, tint: Color, energy: float) -> void:
	var lamp := DirectionalLight3D.new()
	lamp.light_color = tint
	lamp.light_energy = energy
	lamp.shadow_enabled = false
	viewport_3d.add_child(lamp)
	lamp.position = at
	lamp.look_at(Vector3(0, 1, 0))


func select_character(character: String) -> void:
	actor.dress(character)
	actor.rotation.y = _angle
	action = "idle"
	actor.advance(action, 0.0)
	set_close_up(_close_up)


func set_close_up(value: bool) -> void:
	_close_up = value
	var height := float(StudentCast.PEOPLE[StudentCast.resolve(actor.character)]["height"])
	var focus := Vector3(0, (1.526 if value else .93) * height, 0)
	cam.size = (.56 if value else 1.99) * height
	cam.position = focus + Vector3(0, .03, -3)
	cam.look_at(focus)


func _resolution() -> void:
	stretch_shrink = maxi(1, ceili(maxf(size.x, size.y) / 640.0))


func _visibility() -> void:
	var live := is_visible_in_tree()
	set_process(live)
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE if live else SubViewport.UPDATE_DISABLED
	_drag = -2


func _process(dt: float) -> void:
	_elapsed += dt
	if _elapsed < 1.0/30.0: return
	actor.advance(action, minf(_elapsed, .1))
	actor.rotation.y = _angle
	_elapsed = 0
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _drag == -2: _drag = event.index
		elif not event.pressed and _drag == event.index: _drag = -2
	elif event is InputEventScreenDrag and event.index == _drag: _angle += event.relative.x * .012
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != -1:
		_drag = -1 if event.pressed else -2
	elif event is InputEventMouseMotion and _drag == -1: _angle += event.relative.x * .012
	else: return
	accept_event()
