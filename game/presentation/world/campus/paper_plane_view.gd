class_name PaperPlaneView
extends Node3D
## Original folded paper, four fingers and follow camera. Never moves the player's physical body.

var plane: MeshInstance3D
var hand: Node3D
var camera: Camera3D
var _previous: Camera3D

func _material(color: String, emission: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color)
	mat.emission_enabled = true
	mat.emission = Color(emission)
	return mat

func build() -> void:
	name = "PaperPlane"
	plane = MeshInstance3D.new()
	plane.name = "Plane"
	var mesh := ArrayMesh.new()
	var points := PackedVector3Array([Vector3(0,0,.22),Vector3(-.11,0,-.12),Vector3(0,-.025,-.1),Vector3(0,0,.22),Vector3(0,-.025,-.1),Vector3(.11,0,-.12)])
	var normals := PackedVector3Array()
	for i in [0,3]:
		var normal := (points[i+1]-points[i]).cross(points[i+2]-points[i]).normalized()
		for _j in 3: normals.append(normal)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,2,1,3,5,4])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	plane.mesh = mesh
	var paper := _material("f1eee4","2a2924")
	paper.cull_mode = BaseMaterial3D.CULL_DISABLED
	plane.material_override = paper
	add_child(plane)
	hand = Node3D.new()
	hand.name = "Hand"
	add_child(hand)
	var skin := _material("cdbca6","1c1610")
	for i in 5:
		var part := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(.09,.11,.03) if i==0 else Vector3(.018,.08,.02)
		part.mesh = box
		part.material_override = skin
		if i>0: part.position = Vector3(-.033+(i-1)*.022,.09,0)
		hand.add_child(part)

func show_event(event: Dictionary, room: Dictionary, window: Dictionary, source_camera: Camera3D) -> void:
	var wp := CampusGeometry.to_scene(room,window["p"])
	var lp := CampusGeometry.to_scene(room,Vector2(event["lx"],event["ly"]))
	var phase := String(event["phase"])
	hand.visible = event["kind"]=="danger" and phase!="ground"
	hand.position = Vector3(wp.x+.3,1.55,wp.y+window["nz"]*.14)
	plane.visible = phase in ["fly","ground","wait","flight"]
	if phase=="fly":
		var k := minf(1,float(event["t"])/PaperPlaneModule.FLY_IN)
		plane.position = Vector3(lerpf(wp.x,lp.x,k),1.7-k*k+.3*sin(k*PI)-.67*k,lerpf(wp.y,lp.y,k))
		plane.rotation_order = EULER_ORDER_XYZ
		plane.rotation = Vector3(0,atan2(lp.x-wp.x,lp.y-wp.y),.3*sin(k*9))
	elif phase in ["ground","wait"]:
		plane.position = Vector3(lp.x,.03,lp.y)
		plane.rotation_order = EULER_ORDER_XYZ
		plane.rotation = Vector3(0,.6,.1)
	elif phase=="flight":
		var f: Dictionary = event["f"]
		var fp := CampusGeometry.to_scene(room,Vector2(f["x"],f["y"]))
		plane.position = Vector3(fp.x,f["h"],fp.y)
		plane.rotation_order = EULER_ORDER_YXZ
		plane.rotation = Vector3(-f["pitch"],atan2(cos(f["yaw"]),sin(f["yaw"])),0)
		if not is_instance_valid(camera):
			_previous = source_camera
			camera = Camera3D.new()
			camera.fov = source_camera.fov
			camera.near = source_camera.near
			camera.far = source_camera.far
			camera.keep_aspect = source_camera.keep_aspect
			add_child(camera)
		camera.make_current()
		var direction := Vector3(cos(f["yaw"]),0,sin(f["yaw"]))
		camera.position = plane.position-direction*.9+Vector3(0,.28,0)
		camera.look_at(plane.position+direction*2+Vector3(0,sin(f["pitch"])*2,0))
	if phase!="flight": cancel_camera()

func cancel_camera() -> void:
	if not is_instance_valid(camera): return
	if camera.is_current() and is_instance_valid(_previous): _previous.make_current()
	camera.queue_free()
	camera = null
	_previous = null

func _exit_tree() -> void:
	cancel_camera()
