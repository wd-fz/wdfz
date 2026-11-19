class_name ClassmatesView
extends Node3D
## classroom.js ncBuild/ncUpdate and broadcast-view.js classmateScene.
## Presentation state only: no occupancy, violations, random draws or save writes.
var figures: Array[Dictionary] = []
var room: Dictionary
var normal := false
var teacher: Node3D
signal room_sound(cue: String, point: Vector3)
static var _uniforms: Array[Mesh] = []
var _gaze_time := 0.0
var _face_step := 0.0
var _sound_wait := 3.0
var _listening := false
var _lesson_material: StandardMaterial3D

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
	var data := {"node":figure,"home":home,"ty":PI/2,"teacher":is_teacher,"standing":1.0 if is_teacher else 0.0,"stood":false,"stare_stood":false,"broadcast":false,"path":null,"index":0,"kind":"","actor":null,"civilian":null,"seat":figures.size()}
	figures.append(data)
	_pose(data,"teacher" if is_teacher else "sit")
	if is_teacher: teacher = figure

func _pose(data: Dictionary, kind: String) -> void:
	if data.kind == kind: return
	var figure: Node3D = data.node
	for child in figure.get_children():
		figure.remove_child(child)
		child.queue_free()
	data.kind = kind
	data.civilian = null
	var actor := OtherworldFigure.make(kind, null, int(data.seat)*7 + int(data.seat)/4)
	data.actor = actor
	if data.teacher: actor.rotation.y = PI
	figure.add_child(actor)
	_show_mode(data)


func _show_mode(data: Dictionary) -> void:
	(data.actor as Node3D).visible = not normal
	if normal and data.civilian == null:
		var civilian: Node3D
		if data.kind == "sit":
			if _uniforms.is_empty():
				var extras := (load("res://assets/characters/classmates.glb") as PackedScene).instantiate()
				for mesh: MeshInstance3D in extras.find_children("*","MeshInstance3D",true,false): _uniforms.append(mesh.mesh)
				extras.free()
			var pupil := MeshInstance3D.new()
			pupil.mesh = _uniforms[int(data.seat) % _uniforms.size()]
			pupil.scale = Vector3.ONE * (.96 + .016 * float(int(data.seat)*7 % 6))
			civilian = pupil
		elif data.teacher:
			var staff := StudentAvatar.new()
			staff.dress_teacher()
			staff.rotation.y = PI
			civilian = staff
		else:
			if _lesson_material == null: _lesson_material = FigureModel.material(Color("5d6873"))
			civilian = FigureModel.make("person", Color.WHITE, false, 1.0, Color.BLACK, true, false, _lesson_material, true)
		(data.node as Node3D).add_child(civilian)
		data.civilian = civilian
	if data.civilian != null: (data.civilian as Node3D).visible = normal


func set_normal(on: bool) -> void:
	if normal == on: return
	normal = on
	_gaze_time = 0.0
	_face_step = 0.0
	_listening = false
	_sound_wait = 3.0
	for data: Dictionary in figures:
		(data.actor as OtherworldFigure).face.rotation = Vector3.ZERO
		_show_mode(data)


func _step_gait(data: Dictionary, distance: float, dt: float) -> void:
	var actor: Node3D = data.civilian if normal else data.actor
	if actor != null: FigureGait.step(actor,distance,dt)


## Only the occupied classroom listens. A quiet desk turns its head before the
## torso; at high violation the whole row holds the stare. Roots still obey the rules.
func _faces(dt: float, me: Vector2, player: Vector2, viol: float, staring: bool, bell: bool) -> void:
	if normal: return
	_gaze_time += dt
	_face_step += dt
	_sound_wait = maxf(0.0, _sound_wait-dt)
	if _face_step < .08: return
	var step := minf(_face_step,.25)
	_face_step = 0.0
	var c := floori((me.x-room.ox)/room.tw)
	var r := floori((me.y-room.oy)/room.th)
	var classroom := AtmosModule.class_index(c,r)
	var active_class := "%s:%d" % [room.id,classroom]
	var nearest := INF
	var source := Vector3.ZERO
	var cue := "dread.chair"
	for data: Dictionary in figures:
		var n: Node3D = data.node
		if not n.visible: continue
		var actor: OtherworldFigure = data.actor
		if data.teacher:
			# At the lectern the teacher faces the class. When the body takes over
			# the rule's turn towards the player, look along that new heading.
			actor.rotation.y = lerp_angle(actor.rotation.y,0.0 if staring or viol>=35 else PI,1.0-exp(-step*3.4))
		var local := Vector2(n.position.x,n.position.z) - player
		var dist := local.length_squared()
		var same: bool = classroom>=0 and (classroom==int(ClassmatesModule.OWN["class"]) if data.teacher else n.get_meta("cls")==active_class)
		if bell or not same or dist>100:
			if not actor.face.rotation.is_zero_approx(): actor.turn_face(0,0,0,step)
			continue
		var phase := fposmod(_gaze_time+float(int(data.seat)%7)*.62,8.0)
		var attention := 1.0 if staring or viol>=35 else smoothstep(.7,1.5,phase)*(1.0-smoothstep(4.4,5.4,phase))
		if not staring and viol<35: attention *= 1.0-smoothstep(12.25,49.0,dist)
		var target_yaw := atan2(local.x,local.y) - n.rotation.y - actor.rotation.y
		var angle := clampf(wrapf(target_yaw,-PI,PI),-1.38,1.38)*attention
		var tilt := -.24 if data.teacher else -.13
		actor.turn_face(angle,lerpf(tilt,.055,attention),sin(float(data.seat)*1.9+.6)*.19*attention,step)
		if attention>.8 and dist<14.0 and dist<nearest:
			nearest = dist
			source = n.position + Vector3.UP
			cue = "foley.chalk" if data.teacher else "dread.chair"
	var listening := is_finite(nearest)
	if listening and not _listening and _sound_wait<=0:
		room_sound.emit(cue,source)
		_sound_wait = 14.0
	_listening = listening


func advance(dt: float, me: Vector2, viol: float, door: Variant, staring: bool, bell: bool, nav: PatrolNav) -> void:
	var player := CampusGeometry.to_scene(room,me)
	_faces(dt,me,player,viol,staring,bell)
	var exit_point := Vector2.ZERO
	if door is Dictionary: exit_point = CampusGeometry.to_scene(room,Vector2(door["x"],door["y"]))
	for i in figures.size():
		var d: Dictionary = figures[i]
		var f: Node3D = d["node"]
		var previous := f.position
		if _depart(d,dt,bell,nav):
			_step_gait(d, f.position.distance_to(previous), dt)
			continue
		if viol < 70: _step_gait(d, 0, dt)
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
		_step_gait(d, f.position.distance_to(previous), dt)

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
