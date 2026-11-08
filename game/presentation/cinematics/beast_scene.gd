class_name BeastScene
extends Node3D
## Live nine-second path from cutscene.js CUT_DEF.beast. The player state is never
## used as an animation target; all motion belongs to the ending camera and props.

var room: Dictionary
var figure: Node3D
var light: MeshInstance3D
var _environment: Environment
var _old_adjust := false
var _old_saturation := 1.0
var _restored := false


static func cell(r: Dictionary, c: float, row: float) -> Vector3:
	var p := CampusGeometry.to_scene(r,Vector2(float(r["ox"])+(c+.5)*float(r["tw"]),float(r["oy"])+(row+.5)*float(r["th"])))
	return Vector3(p.x,0,p.y)


static func frame(k: float, r: Dictionary, shake: bool) -> Dictionary:
	var a := cell(r,59.5,16.6)
	var s := cell(r,59,18.6)
	var door := cell(r,57,19.3)
	var end := cell(r,30,19.3)
	var cam0 := cell(r,60.6,19.4)
	var f: Vector3
	if k < .36:
		f = a.lerp(s,OpeningCut.phase(k,.16,.3))
	elif k < .5:
		f = s.lerp(door,OpeningCut.phase(k,.36,.5))
	else:
		f = door.lerp(end,OpeningCut.phase(k,.5,.88))
	f.y = absf(sin(k*40))*.05 if k>.36 and k<.88 else 0.0
	var from := cam0.lerp(door+Vector3(.6,0,0),OpeningCut.phase(k,.42,.58)) if k<.58 else Vector3(lerpf(door.x+.6,minf(door.x+.6,f.x+3.2),OpeningCut.phase(k,.58,1)),0,door.z)
	from.y = 1.6+(sin(k*44)*.04 if shake and k>.42 and k<.9 else 0.0)
	return {"figure":f,"from":from,"to":Vector3(f.x,1.4,f.z),"walk_to":Vector3(end.x,0,door.z if k<.5 else end.z),
		"visible":k>.16,"light":.45*OpeningCut.phase(k,0,.18)*(1-OpeningCut.phase(k,.3,.42)),
		"normal":OpeningCut.phase(k,.5,.95),"fade":(k-.92)/.08 if k>.92 else 0.0}


func begin(r: Dictionary, environment: Environment) -> void:
	room = r
	_environment = environment
	if _environment != null:
		_old_adjust = _environment.adjustment_enabled
		_old_saturation = _environment.adjustment_saturation
	figure = FigureModel.make("person",Color("#2a3a5a"),true)
	add_child(figure)
	light = MeshInstance3D.new()
	var plane := QuadMesh.new()
	plane.size = Vector2(.9,2.1)
	light.mesh = plane
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color("#f2ead2")
	light.material_override = material
	light.position = cell(room,59.5,16.6)+Vector3(0,1.05,.42)
	add_child(light)


func apply(k: float, camera: Camera3D, shake: bool) -> Dictionary:
	var state := frame(k,room,shake)
	figure.position = state["figure"]
	figure.visible = state["visible"]
	var facing: Vector3 = state["from"] if k<.36 else state["walk_to"]
	facing.y = figure.global_position.y
	if facing.distance_to(figure.global_position)>.001:
		figure.look_at(facing,Vector3.UP)
	light.visible = k<.42
	var material := light.material_override as StandardMaterial3D
	material.albedo_color.a = state["light"]
	camera.global_position = state["from"]
	camera.look_at(state["to"],Vector3.UP)
	if _environment != null:
		_environment.adjustment_enabled = true
		_environment.adjustment_saturation = lerpf(.46,1.0,state["normal"])
	return state


func cancel() -> void:
	if _restored:
		return
	_restored = true
	if _environment != null:
		_environment.adjustment_enabled = _old_adjust
		_environment.adjustment_saturation = _old_saturation


func _exit_tree() -> void:
	cancel()
