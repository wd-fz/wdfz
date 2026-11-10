class_name ClassmatesView
extends Node3D
## classroom.js ncBuild/ncUpdate and broadcast-view.js classmateScene.
## Presentation state only: no occupancy, violations, random draws or save writes.
var figures: Array[Dictionary] = []
var room: Dictionary
var normal := false
var teacher: Node3D
## A classroom has one tint/lighting state. Sharing its material lets Vulkan's automatic
## instancing batch identical figures; mutations stay local to this ClassmatesView.
var _material: StandardMaterial3D

func build(layout: Dictionary, seats: Array) -> void:
	name = "Classmates"
	room = layout
	for tile: Vector2i in seats:
		var k := ClassmatesModule.DESK_ROWS.find(tile.y)
		var shift := (.11 if k % 2 == 0 else -.11) if k >= 0 else 0.0
		var w := Vector2(room["ox"]+(tile.x+.82)*room["tw"],room["oy"]+(tile.y+.5+shift)*room["th"])
		_add(CampusGeometry.to_scene(room,w),false,"%s:%d" % [room["id"],AtmosModule.class_index(tile.x,tile.y)])
	if room["id"] == ClassmatesModule.OWN["room"]:
		var w := Vector2(room["ox"]+45.62*room["tw"],room["oy"]+11*room["th"])
		_add(CampusGeometry.to_scene(room,w),true,"")

func _add(home: Vector2, is_teacher: bool, classroom: String) -> void:
	var figure := Node3D.new()
	figure.position = Vector3(home.x,0,home.y)
	figure.rotation.y = PI/2
	figure.set_meta("teacher",is_teacher)
	figure.set_meta("cls",classroom)
	add_child(figure)
	var data := {"node":figure,"home":home,"ty":PI/2,"teacher":is_teacher,"standing":1.0 if is_teacher else 0.0,"stood":false,"stare_stood":false,"broadcast":false,"path":null,"index":0,"kind":""}
	figures.append(data)
	_pose(data,"teacher" if is_teacher else "sit")
	if is_teacher: teacher = figure

func _pose(data: Dictionary, kind: String) -> void:
	if data["kind"] == kind: return
	data["kind"] = kind
	var figure: Node3D = data["node"]
	for child in figure.get_children():
		figure.remove_child(child)
		child.queue_free()
	var model := FigureModel.make(kind,Color("5d6873") if normal else Color("080b0d"),not normal)
	if CampusBatches.enabled:
		for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
			if _material==null: _material=mesh.material_override
			else: mesh.material_override=_material
	# FigureModel already turns students' meshes around; the teacher faces the class.
	if data["teacher"]: model.rotation.y = PI
	figure.add_child(model)

func set_normal(on: bool) -> void:
	if normal == on: return
	normal = on
	for data: Dictionary in figures:
		for mesh: Node in (data["node"] as Node3D).find_children("*","MeshInstance3D",true,false):
			var mat := (mesh as MeshInstance3D).material_override as StandardMaterial3D
			if mat != null:
				mat.albedo_color = Color("5d6873") if normal else Color("080b0d")
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL if normal else BaseMaterial3D.SHADING_MODE_UNSHADED
				(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if normal else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func advance(dt: float, me: Vector2, viol: float, door: Variant, staring: bool, bell: bool, nav: PatrolNav) -> void:
	var player := CampusGeometry.to_scene(room,me)
	var exit_point := Vector2.ZERO
	if door is Dictionary: exit_point = CampusGeometry.to_scene(room,Vector2(door["x"],door["y"]))
	for i in figures.size():
		var d: Dictionary = figures[i]
		var f: Node3D = d["node"]
		if _depart(d,dt,bell,nav): continue
		var home: Vector2 = d["home"]
		if staring and viol < 70:
			var want := atan2(f.position.x-player.x,f.position.z-player.y)
			var diff := wrapf(want-f.rotation.y,-PI,PI)
			f.rotation.y += diff*minf(1,dt*6)
			if not d["teacher"] and not d["stood"] and absf(diff)<.35:
				d["stood"] = true
				d["stare_stood"] = true
				_pose(d,"person")
			continue
		if d["stare_stood"] and not staring:
			d["stare_stood"] = false
			if viol < 35 and not d["teacher"]:
				d["stood"] = false
				d["standing"] = 0.0
				_pose(d,"sit")
		if viol >= 35 and viol < 70:
			f.rotation.y += wrapf(atan2(home.x-player.x,home.y-player.y)-f.rotation.y,-PI,PI)*minf(1,dt*2.2)
			continue
		if viol < 35: continue
		var angle := float(i)/maxi(1,figures.size())*TAU
		var target: Vector2
		if viol >= 92 and door is Dictionary:
			target = exit_point+Vector2(cos(angle),sin(angle))*.55
		else:
			angle += .4
			target = player+Vector2(cos(angle),sin(angle))*(1.9+(i%3)*.28)
		d["standing"] = minf(1,float(d["standing"])+dt*.8)
		if not d["teacher"] and d["standing"]>.5 and not d["stood"]:
			d["stood"] = true
			_pose(d,"person")
		var offset := target-Vector2(f.position.x,f.position.z)
		if offset.length()>.08:
			offset = offset.normalized()*minf(offset.length(),dt*(1.9 if viol>=92 else 1.2))
			f.position += Vector3(offset.x,0,offset.y)
		f.rotation.y += wrapf(atan2(f.position.x-player.x,f.position.z-player.y)-f.rotation.y,-PI,PI)*minf(1,dt*2.5)

func _depart(d: Dictionary, dt: float, bell: bool, nav: PatrolNav) -> bool:
	if d["teacher"]: return false
	var f: Node3D = d["node"]
	var home: Vector2 = d["home"]
	if not bell:
		if d["broadcast"]:
			d["broadcast"] = false
			f.visible = true
			d["path"] = null
			d["index"] = 0
			f.position = Vector3(home.x,0,home.y)
			f.rotation.y = d["ty"]
			d["standing"] = 0.0
			d["stood"] = false
			_pose(d,"sit")
		return false
	if not d["broadcast"]:
		d["broadcast"] = true
		_pose(d,"person")
	if d["path"] == null:
		if nav == null: return true
		var target: Dictionary = nav.nodes.get(String(room["id"])+":stairs",{})
		if target.is_empty(): return true
		var w := CampusGeometry.to_world(room,home.x,home.y)
		var start := nav.snap(room["id"],PatrolNav.point(room["id"],w.x,w.y))
		d["path"] = nav.path(start,target) if not start.is_empty() else []
		d["index"] = 0
	var path: Array = d["path"]
	if path.is_empty(): return true
	var step := mini(path.size()-1,int(d["index"]))
	var p: Dictionary = path[step]
	var q := CampusGeometry.to_scene(room,Vector2(p["x"],p["y"]))
	var offset := q-Vector2(f.position.x,f.position.z)
	var distance := offset.length()
	if distance<.1:
		d["index"] = step+1
		if d["index"]>=path.size(): f.visible = false
	else:
		var move := offset*minf(1,dt*1.4/distance)
		f.position += Vector3(move.x,0,move.y)
		f.rotation.y = atan2(-offset.x,-offset.y)
	return true
