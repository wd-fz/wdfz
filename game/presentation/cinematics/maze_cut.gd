class_name MazeCut
extends Node3D
## Live 7 s entry / 6 s exit, ported from void-maze/maze-cut.js. The transfer callback is
## consumed exactly once; cancelling a session never consumes it. Props survive a scene swap.

signal finished

var on := false
var kind := "in"
var k := 0.0
var stage: MazeCutStage
var cam: Camera3D
var screen: MazeScreen
var props: Node3D
var cabin: Node3D
var lights: Array[MeshInstance3D] = []
var walls: Array[MeshInstance3D] = []
var doors: Array[MeshInstance3D] = []
var digit: Dictionary = {}
var exit: Dictionary = {}
var panel: MeshInstance3D
var door_light: MeshInstance3D
var leds: Array[MeshInstance3D] = []
var base := Vector3.ZERO
var forward := Vector3.FORWARD
var ang := 0.0
var floor_num := 1
var _move := Callable()
var moved := false
var _hall_pose := {}
var _hall_end := Vector3.ZERO
var _sounds := {}
var _controls: CanvasLayer


static func phase(value: float, a: float, b: float) -> float:
	return smoothstep(a, b, value)


func begin(cut_kind: String, owner_app: GameApp, door: Dictionary, transfer: Callable) -> void:
	var context := MazeCutStage.new()
	context.player = owner_app.player
	context.ui = owner_app.ui
	context.audio = owner_app.audio
	context.settings = owner_app.settings
	context.geometry = owner_app.maze().geometry
	context.elevator = owner_app.elevator()
	context.campus = owner_app.campus()
	context.scene = func() -> String: return owner_app.session.world_id
	context.can_stand = owner_app._can_stand
	begin_stage(cut_kind, context, door, transfer)


func begin_stage(cut_kind: String, context: MazeCutStage, door: Dictionary, transfer: Callable) -> void:
	stage = context
	kind = cut_kind
	exit = door
	_move = transfer
	process_mode = Node.PROCESS_MODE_ALWAYS
	props = Node3D.new()
	add_child(props)
	cam = Camera3D.new()
	cam.fov = stage.player.camera.fov
	cam.near = stage.player.camera.near
	cam.far = stage.player.camera.far
	add_child(cam)
	cam.make_current()
	screen = MazeScreen.new()
	add_child(screen)
	stage.ui.cut_mode(true)
	_controls = CanvasLayer.new()
	_controls.layer = 5
	add_child(_controls)
	var skip := Button.new()
	skip.text = "跳过"
	skip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	skip.position = Vector2(-130, -76)
	skip.size = Vector2(104, 52)
	skip.pressed.connect(finish)
	_controls.add_child(skip)
	if kind == "in":
		floor_num = int(stage.elevator.ride.get("origin", 1))
		_pick_entry()
		_build_cabin()
	else:
		_build_exit()
	on = true
	apply_frame(0.0)


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_fog = true
	mat.albedo_color = color
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position = pos
	node.set_meta("base_color", color)
	parent.add_child(node)
	return node


func _pick_entry() -> void:
	var shape := stage.geometry
	base = stage.player.position
	base.y = shape.ground_at(base.x, base.z, base.y + 0.42)
	ang = CampusGeometry.ang_from_yaw(stage.player.rotation.y)
	var score := -INF
	var index := 0
	for p: Vector3 in [base, Vector3(0, base.y, 0)]:
		for i in 8:
			var a := i * PI / 4.0
			var dir := Vector3(cos(a), 0, sin(a))
			var clear := shape.depth_at(p.x, p.z, 1.0 / 3.0 + 0.05, p.y) == 0.0
			for j in 8:
				var q := p - dir * (0.4 + j * 0.3)
				clear = clear and shape.depth_at(q.x, q.z, 0.8, p.y) == 0.0
			if not clear:
				continue
			var reach := 0.0
			for j in range(1, 21):
				var q := p + dir * j * 0.5
				if shape.depth_at(q.x, q.z, 0.3, p.y) > 0.0:
					break
				reach = j * 0.5
			if reach - index * 1.5 > score:
				score = reach - index * 1.5
				base = p
				ang = a
		index += 1
	forward = Vector3(cos(ang), 0, sin(ang))
	stage.player.restore_pose({"position": [base.x, base.y + 0.01, base.z], "yaw": CampusGeometry.yaw_from_ang(ang), "pitch": 0.0})


func _build_cabin() -> void:
	cabin = Node3D.new()
	props.add_child(cabin)
	cabin.position = base - forward * 0.6
	cabin.rotation.y = atan2(forward.x, forward.z)
	var boxes := [[Vector3(1.5,0.04,2.05),Vector3(0,0,-1.025),"#3b4144"], [Vector3(1.5,0.04,2.05),Vector3(0,2.4,-1.025),"#9aa4a6"],
		[Vector3(0.04,2.4,2.05),Vector3(-0.75,1.2,-1.025),"#8a9599"], [Vector3(0.04,2.4,2.05),Vector3(0.75,1.2,-1.025),"#8a9599"],
		[Vector3(1.5,2.4,0.04),Vector3(0,1.2,-2.05),"#7f898c"], [Vector3(0.30,2.4,0.06),Vector3(-0.61,1.2,0),"#6d777a"],
		[Vector3(0.30,2.4,0.06),Vector3(0.61,1.2,0),"#6d777a"], [Vector3(0.94,0.3,0.06),Vector3(0,2.25,0),"#6d777a"],
		[Vector3(0.05,0.9,0.5),Vector3(0.72,1.2,-0.45),"#5a6366"]]
	for b: Array in boxes:
		walls.append(_box(cabin, b[0], b[1], Color(b[2])))
	for i in 3:
		lights.append(_box(cabin, Vector3(0.9,0.02,0.32), Vector3(0,2.37,-0.35-i*0.62), Color("#f4f1e6")))
	for side in [-1, 1]:
		var leaf := _box(cabin, Vector3(0.47,2.1,0.03), Vector3(side*0.235,1.05,0.02), Color("#8e979a"))
		doors.append(leaf)
		walls.append(leaf)
	var display := Node3D.new()
	display.position = Vector3(0,2.22,-0.04)
	display.rotation.y = PI
	display.scale = Vector3.ONE * 0.12
	cabin.add_child(display)
	var segments := {"a":[0,.5,.8,.12],"b":[.36,.25,.12,.5],"c":[.36,-.25,.12,.5],"d":[0,-.5,.8,.12],"e":[-.36,-.25,.12,.5],"f":[-.36,.25,.12,.5],"g":[0,0,.8,.12],"h":[0,0,1.15,.1],"i":[0,0,1.15,.1]}
	for id: String in segments:
		var s: Array = segments[id]
		var part := _box(display, Vector3(s[2],s[3],0.02), Vector3(s[0],s[1],0), Color("#2a0806"))
		if id in ["h", "i"]:
			part.rotation.z = 1.05 if id == "h" else -1.05
		digit[id] = part


func _build_exit() -> void:
	cabin = Node3D.new()
	props.add_child(cabin)
	var n := Vector3(exit["n"][0],0,exit["n"][1])
	cabin.position = Vector3(exit["x"],exit["h"],exit["z"]) - n * 0.02
	cabin.rotation.y = atan2(n.x,n.z)
	door_light = _box(cabin, Vector3(.98,2.08,.01), Vector3(0,1.04,-.024), Color("#0b0d10"))
	panel = _box(cabin, Vector3(.98,2.08,.03), Vector3(0,1.04,0), Color("#15181c"))


func _process(dt: float) -> void:
	if on:
		apply_frame(minf(1.0, k + dt / (7.0 if kind == "in" else 6.0)))
		if k >= 1.0:
			finish()


func _input(ev: InputEvent) -> void:
	if on and ev is InputEventKey and ev.pressed and not ev.echo and ev.physical_keycode in [KEY_SPACE, KEY_ENTER, KEY_ESCAPE]:
		get_viewport().set_input_as_handled()
		finish()


func _sound(key: String, id: String) -> void:
	if not _sounds.has(key):
		_sounds[key] = true
		stage.audio.play(id)


func apply_frame(value: float) -> void:
	k = value
	if kind == "in":
		_entry_frame()
	else:
		_exit_frame()


func _entry_frame() -> void:
	var glyph: String = {"1":"bc", "2":"abged", "3":"abgcd", "4":"fgbc", "5":"afgcd"}.get(str(floor_num), "bc") if k < 0.06 else "abcdefhi"
	for id: String in digit:
		digit[id].material_override.albedo_color = Color("#ff3a20") if glyph.contains(id) and not (k > .06 and k < .09) else Color("#2a0806")
	var lit := 0
	for i in 3:
		var enabled := k < 0.14 + i * 0.08
		lights[i].material_override.albedo_color = Color("#f4f1e6") if enabled else Color("#2b2d2e")
		lit += 1 if enabled else 0
	var opacity := 1.0 - phase(k,.86,.92)
	for mesh: Node in cabin.find_children("*", "MeshInstance3D", true, false):
		var mat: BaseMaterial3D = mesh.material_override
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if opacity < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
		mat.albedo_color.a = opacity
	for wall: MeshInstance3D in walls:
		var col: Color = wall.get_meta("base_color")
		wall.material_override.albedo_color = Color(col.r, col.g, col.b) * (0.06 + 0.94 * (0.25 + 0.75 * lit / 3.0))
		wall.material_override.albedo_color.a = opacity
	cabin.visible = opacity > .01
	var opened := phase(k,.46,.56) * (1.0-phase(k,.8,.86))
	doors[0].position.x = -.235 - opened * .47 * .98
	doors[1].position.x = .235 + opened * .47 * .98
	var walk := phase(k,.58,.72)
	var look := phase(k,.72,.8) * (1.0-phase(k,.92,1.0))
	var pos := base + forward * lerpf(-2.15,0.0,walk)
	var a := ang + PI * look
	var sway := sin(k*9.0)*.012 if stage.settings.get_int("shake") != 0 and k > .16 and k < .46 else 0.0
	var look_y := base.y + 1.65 - (.05 if k < .5 else .18+.12*(1-walk))
	if k < .12:
		look_y = base.y + 1.65 + .42*(1.0-phase(k,.08,.12))
	cam.look_at_from_position(pos+Vector3(0,1.65+sway,0), Vector3(pos.x+cos(a)*3,look_y,pos.z+sin(a)*3))
	var inversion := phase(k,.18,.46) * (1.0-phase(k,.5,.66))
	screen.show_effect(0.9 * inversion, 1.0 - 0.62 * phase(k,.18,.46), 0, -.22, 1-k/.03 if k < .03 else 0.0)
	if k > .16:
		_sound("fall", "void.fall")
	if k > .5:
		_sound("ping", "void.ping")


func _transfer_once() -> void:
	if moved:
		return
	moved = true
	_move.call()
	cabin.hide()
	_hall_pose = stage.player.capture_pose()
	_hall_end = stage.player.position
	ang = CampusGeometry.ang_from_yaw(stage.player.rotation.y)
	var room: Dictionary = stage.campus.room(String(stage.scene.call()))
	var lift := stage.elevator
	var frame := lift.frame(String(stage.scene.call()))
	for distance in [1.9,1.6,1.3,1.0]:
		var w := lift.world(String(stage.scene.call()), distance, 0.0)
		if distance == 1.0 or bool(stage.can_stand.call(w, room, 0.0)):
			var p := CampusGeometry.to_scene(room, w)
			_hall_end = Vector3(p.x,stage.player.position.y,p.y)
			break
	var dc := CampusGeometry.to_scene(room, lift.world(String(stage.scene.call()), ElevatorModule.GEO["landing"]+.05,0))
	var strip := Node3D.new()
	props.add_child(strip)
	var dir: Vector2 = frame["out"]
	strip.position = Vector3(dc.x+dir.x*.1,2.42,dc.y+dir.y*.1)
	strip.rotation.y = atan2(dir.x,dir.y)
	for i in 5:
		leds.append(_box(strip,Vector3(.05,.05,.015),Vector3((i-2)*.1,0,0),Color("#ffb04a")))
	cam.make_current()


func _exit_frame() -> void:
	var flash := .55 if stage.settings.get_int("reduce_flash") != 0 else 1.0
	if k < .44:
		var push := phase(k,.06,.3)
		var sw := cos(1.2*push)
		panel.scale.x = maxf(.02,sw)
		panel.position.x = -.49*(1.0-sw)
		door_light.material_override.albedo_color = Color("#0b0d10").lerp(Color("#bfe4ff"),minf(1.0,push*1.4))
		var n := Vector3(exit["n"][0],0,exit["n"][1])
		var at := Vector3(exit["x"],exit["h"],exit["z"])
		cam.look_at_from_position(at+n*lerpf(1.9,.55,phase(k,0,.4))+Vector3.UP*1.65,at+Vector3.UP*1.45)
		screen.show_effect(0,-.2,.85*phase(k,.12,.4)*flash)
		if k > .06:
			_sound("door", "foley.door")
		return
	_transfer_once()
	var recede := phase(k,.44,.66)
	var turn := phase(k,.62,.8)
	var p: Array = _hall_pose["position"]
	var pos := Vector3(p[0],p[1],p[2]).lerp(_hall_end,turn)
	var a := ang+PI*turn
	cam.look_at_from_position(pos+Vector3.UP*1.65,pos+Vector3(cos(a)*3,1.65+.3*turn,sin(a)*3))
	var gone := floori(phase(k,.78,.96)*5.999)
	for i in 5:
		leds[i].material_override.albedo_color = Color("#ffb04a") if i < 5-gone else Color("#6a5a46")
	screen.show_effect(0,-.2,(1-recede)*flash,recede*.75,(k-.97)/.03*.6 if k > .97 else 0.0)
	if k > .78:
		_sound("tick", "ui.blink")


func finish() -> void:
	if not on:
		return
	if kind == "out":
		_transfer_once()
		if phase(k,.62,.8) > .5:
			stage.player.restore_pose({"position":[_hall_end.x,_hall_end.y,_hall_end.z],"yaw":CampusGeometry.yaw_from_ang(ang+PI),"pitch":0.0})
	cancel()
	finished.emit()


func cancel() -> void:
	on = false
	_move = Callable()
	if is_instance_valid(screen):
		screen.show_effect()
	if stage != null and is_instance_valid(stage.player):
		stage.ui.cut_mode(false)
		stage.player.reset_view()
		stage.player.camera.make_current()
	if is_instance_valid(props):
		props.hide()
	if is_instance_valid(_controls):
		_controls.hide()

	stage = null
