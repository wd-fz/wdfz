class_name AtmosFx
extends Node3D
## The pictures of the global atmosphere (fx/atmos-fx.js), read-only over AtmosModule's state:
## · A2 emergency signs above the stair mouths of a teaching / lab floor (green, self-lit);
## · A6 a mop and a bucket against the west corridor wall that move when not looked at;
## · A4 a still silhouette on a classroom's frosted north window.
## Original sign canvas, prop dimensions and person silhouette. No colliders: nothing blocks a door,
## a stair mouth or a lift.

const SHIFT_MIN := 8.0

var room: Dictionary = {}
var props: Node3D
var shifted: Variant = null   # null | "push" | "face"
var _home := Vector2.ZERO
var _face := false
var _fig: Node3D
var _win_pos := Vector3.ZERO
var _win_record: Dictionary = {}
var signs: Array[MeshInstance3D] = []


static func dark_floor(r: Dictionary) -> bool:
	return not r.is_empty() and ["teach", "admin", "lab"].has(String(r.get("host", ""))) and r.get("floor") != null \
		and int(r["floor"]) >= 1 and int(r["floor"]) <= 5 and not r.get("flags", {}).get("stairwell", false)


static func last_door_row(r: Dictionary) -> int:
	var d := -1
	var grid: Array = r["grid"]
	for y in grid.size():
		if String(grid[y]).contains("="):
			d = y
	return d


func clear() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	room = {}
	props = null
	_fig = null
	_win_record = {}
	signs.clear()
	shifted = null
	_face = false


func setup(r: Dictionary) -> void:
	clear()
	room = r
	# The original frame hook is gated by Atmos.floorRoom (teaching / laboratory only).
	if r.is_empty() or r.get("host") not in ["teach", "lab"] or not dark_floor(r):
		return
	var grid: Array = r["grid"]
	var door := last_door_row(r)
	var tex: Texture2D = load("res://assets/campus/atmos/exit-sign.png")
	for y in range(door + 1, grid.size()):
		var row := String(grid[y])
		for x in row.length():
			if row.substr(x, 1) != "S" or (x > 0 and row.substr(x - 1, 1) == "S"):
				continue
			var p := CampusGeometry.to_scene(r, Vector2(float(r["ox"]) + (x + 1) * float(r["tw"]), float(r["oy"]) + y * float(r["th"])))
			var sign_mesh := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(0.36, 0.135)
			sign_mesh.mesh = q
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.disable_fog = true
			m.albedo_texture = tex
			sign_mesh.material_override = m
			sign_mesh.position = Vector3(p.x, 2.55, p.y - 0.06)
			sign_mesh.name = "ExitSign"
			add_child(sign_mesh)
			signs.append(sign_mesh)
			var glow := MeshInstance3D.new()
			var plane := QuadMesh.new()
			plane.size = Vector2(1.1,0.6)
			glow.mesh = plane
			var light := StandardMaterial3D.new()
			light.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			light.albedo_color = Color("1fd16a")
			light.albedo_color.a = .12
			light.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			light.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			light.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			light.disable_fog = true
			glow.material_override = light
			glow.position = Vector3(p.x,2.5,p.y-.05)
			glow.name = "ExitGlow"
			add_child(glow)
	_build_props(r, door)


func _build_props(r: Dictionary, door: int) -> void:
	var grid: Array = r["grid"]
	var cols := int(r["cols"])
	var spot := Vector2i(-1, -1)
	var x := 4
	while x < cols - 4 and spot.x < 0:
		var y := door + 1
		if y < grid.size() and y > 0:
			var row := String(grid[y])
			var north := String(grid[y - 1])
			if row.substr(x, 1) == "." and row.substr(x + 1, 1) == "." and north.substr(x, 1) == "#" and north.substr(x + 1, 1) == "#" and x > cols * 0.3:
				spot = Vector2i(x, y)
		x += 1
	if spot.x < 0:
		return
	_home = CampusGeometry.to_scene(r, Vector2(float(r["ox"]) + (spot.x + 0.5) * float(r["tw"]), float(r["oy"]) + (spot.y + 0.18) * float(r["th"])))
	props = Node3D.new()
	props.name = "MopAndBucket"
	props.position = Vector3(_home.x, 0.0, _home.y)
	var stick := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.012
	cyl.bottom_radius = 0.012
	cyl.height = 1.3
	cyl.radial_segments = 6
	cyl.rings = 1
	stick.mesh = cyl
	stick.material_override = _lit(Color("#9a7a55"))
	stick.position = Vector3(0, 0.72, 0)
	stick.rotation.z = 0.18
	var head := MeshInstance3D.new()
	var hc := CylinderMesh.new()
	hc.top_radius = 0.12
	hc.bottom_radius = 0.16
	hc.height = 0.18
	hc.radial_segments = 8
	hc.rings = 1
	head.mesh = hc
	head.material_override = _lit(Color("#8d8a80"))
	head.position = Vector3(-0.11, 0.09, 0)
	var bucket := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = 0.16
	bc.bottom_radius = 0.13
	bc.height = 0.28
	bc.radial_segments = 10
	bc.rings = 1
	bucket.mesh = bc
	bucket.material_override = _lit(Color("#3d6c9a"))
	bucket.position = Vector3(0.32, 0.14, 0.02)
	props.add_child(stick)
	props.add_child(head)
	props.add_child(bucket)
	add_child(props)


static func _lit(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


## The mop's world position (campus units), or null when this floor has none.
func prop_world() -> Variant:
	if props == null:
		return null
	return CampusGeometry.to_world(room, props.position.x, props.position.z)


## Put the props where the day's record says (read on load too).
func apply_shift(kind: Variant, pose: Dictionary) -> void:
	if props == null:
		return
	shifted = kind if (kind == "push" or kind == "face") else null
	props.rotation = Vector3.ZERO
	props.position = Vector3(_home.x, 0.0, _home.y)
	(props.get_child(0) as Node3D).rotation.z = 0.18
	_face = false
	if kind == "push":
		var dx := float(pose.get("dx", 1.0))
		var dz := float(pose.get("dy", 0.0))
		props.position.x = _home.x + dx * 0.55
		props.position.z = _home.y + dz * 0.55
		props.rotation.y = float(pose.get("angle", 0.7))
		(props.get_child(0) as Node3D).rotation.z = 1.2
	elif kind == "face":
		props.position.z = _home.y + 0.4
		if pose.has("angle"):
			props.rotation.y = float(pose["angle"])
		else:
			_face = true


static func in_view(cam: Camera3D, px: float, pz: float, cone: float) -> bool:
	var f := -cam.global_basis.z
	var vx := px - cam.global_position.x
	var vz := pz - cam.global_position.z
	var l := maxf(0.0001, Vector2(vx, vz).length())
	return (vx * f.x + vz * f.z) / l > cos(cone)


## Far enough and out of sight (so the move is not seen).
func can_shift(cam: Camera3D) -> bool:
	if props == null or cam == null:
		return false
	var p := props.position
	return Vector2(p.x - cam.global_position.x, p.z - cam.global_position.z).length() > SHIFT_MIN and not in_view(cam, p.x, p.z, 0.9)


func sees_shifted(cam: Camera3D) -> bool:
	if props == null or shifted == null or cam == null:
		return false
	var p := props.position
	return Vector2(p.x - cam.global_position.x, p.z - cam.global_position.z).length() < 9.0 and in_view(cam, p.x, p.z, 0.35)


## Per frame: a "face" shift turns the mop towards the camera once.
func face_camera(cam: Camera3D) -> void:
	if props != null and _face and cam != null:
		props.rotation.y = atan2(cam.global_position.x - props.position.x, cam.global_position.z - props.position.z)
		_face = false


## A4: the figure on the frosted north window of the player's classroom. Returns whether it is looked at.
func show_window(w: Dictionary, cam: Camera3D) -> bool:
	if w.is_empty() or room.is_empty() or w["room"] != room.get("id") or bool(w["gone"]) or cam == null:
		if _fig != null:
			_fig.visible = false
		return false
	if _fig == null:
		_fig = Node3D.new()
		var person := FigureModel.make("person",Color("101315"),true,1,Color.BLACK,false,true)
		person.rotation.y = PI # imported model faces -z; original silhouette faces +z
		person.scale.z = .05
		_fig.add_child(person)
		for child: Node in person.find_children("*","MeshInstance3D",true,false):
			var material := (child as MeshInstance3D).material_override as BaseMaterial3D
			material.albedo_color.a = .82
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_fig.scale = Vector3.ONE*.12
		_fig.name = "WindowFigure"
		add_child(_fig)
	if not is_same(w,_win_record):
		_win_record = w
		var ci := int(String(w["cls"]).split(":")[1])
		var c0 := int(room["cols"])
		var c1 := 0
		var r0 := int(room["rows"])
		var grid: Array = room["grid"]
		for y in range(1,grid.size()):
			for x in range(1,int(room["cols"])):
				var cell := String(grid[y]).substr(x,1)
				if cell!="#" and cell!="=" and AtmosModule.class_index(x,y)==ci:
					c0 = mini(c0,x)
					c1 = maxi(c1,x)
					r0 = mini(r0,y)
		var cx := float(room["ox"]) + (c0 + (c1 - c0 + 1) * (0.25 + 0.5 * float(w["seed"]))) * float(room["tw"])
		var face := CampusGeometry.to_scene(room, Vector2(cx, float(room["oy"]) + r0 * float(room["th"])))
		_win_pos = Vector3(face.x, 1.18, face.y + 0.035)
		if w.has("anchor"):
			var anchor: Dictionary = w["anchor"]
			var far := CampusGeometry.to_scene(room,Vector2(anchor["x"],anchor["y"]))
			var eye := cam.global_position
			var dz := far.y-eye.z
			var t := (face.y-eye.z)/(dz if not is_zero_approx(dz) else -1.0)
			if t>0 and t<1:
				_win_pos.x = clampf(eye.x+(far.x-eye.x)*t,c0-float(room["cols"])/2+.7,c1-float(room["cols"])/2+.3)
				_win_pos.y = clampf(eye.y+(float(anchor["height"])-(int(room["floor"])-1)*3.2-eye.y)*t,1.18,2.3)
	_fig.visible = true
	_fig.position = _win_pos
	return in_view(cam, _win_pos.x, _win_pos.z, 0.22)
