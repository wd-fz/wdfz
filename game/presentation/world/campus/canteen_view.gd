class_name CanteenView
extends Node3D
## The midnight canteen, seen (modules/campus-tales/canteen.js, reference wd-fz.github.io@0bf508a). After lights out (22:20) over the
## serving counter in the middle of the canteen one lamp is lit, and the server stands behind the counter — whichever side you go round
## to, it has its back to you. A warm pool of light on the floor, a faint cone, one bowl on the counter (gone once eaten tonight), and
## the only light of the whole room (OmniLight). The rule (hint, the meal, the cost) is TalesModule; this is its picture.

const ROOM := "canteen1"

var _fig: Node3D
var _bowl: Node3D
var _room: Dictionary = {}
var _built := false


## The counter's cells ('k') and the spots from them: the lamp, the server, the dish. Null when the room has no counter.
static func layout(room: Dictionary) -> Dictionary:
	var xs: Array = []
	var ys: Array = []
	var grid: Array = room["grid"]
	for y in grid.size():
		for x in String(grid[y]).length():
			if String(grid[y]).substr(x, 1) == "k":
				xs.append(float(room["ox"]) + (x + 0.5) * float(room["tw"]))
				ys.append(float(room["oy"]) + (y + 0.5) * float(room["th"]))
	if xs.is_empty():
		return {}
	var cx := 0.0
	var cy := 0.0
	for i in xs.size():
		cx += float(xs[i])
		cy += float(ys[i])
	cx /= float(xs.size())
	cy /= float(ys.size())
	var tw := float(room["tw"])
	var head: float = (xs.min() as float) - tw * 0.95
	return {"lamp": Vector2(head + tw * 0.9, cy), "server": Vector2(head, cy), "dish": Vector2(head + tw * 0.75, ys.max())}


func _unlit(c: Color, op: float = 1.0, add: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c.r, c.g, c.b, op)
	if op < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if add:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _mesh(m: Mesh, mat: Material, p: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = p
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func build(room: Dictionary) -> void:
	for c in get_children():
		c.queue_free()
	_fig = null
	_bowl = null
	_room = room
	_built = false
	if room.is_empty() or String(room.get("id", "")) != ROOM:
		return
	var ly := layout(room)
	if ly.is_empty():
		return
	var p := CampusGeometry.to_scene(room, ly["lamp"])
	var back := CampusGeometry.to_scene(room, ly["server"])
	var dish := CampusGeometry.to_scene(room, ly["dish"])
	var shade := CylinderMesh.new()
	shade.top_radius = 0.12
	shade.bottom_radius = 0.42
	shade.height = 0.28
	shade.cap_top = false
	shade.cap_bottom = false
	_mesh(shade, _unlit(Color("#2b2620")), Vector3(p.x, 2.55, p.y))
	var bulb := SphereMesh.new()
	bulb.radius = 0.1
	bulb.height = 0.2
	_mesh(bulb, _unlit(Color("#ffe2a8")), Vector3(p.x, 2.42, p.y))
	var pool := CylinderMesh.new()
	pool.top_radius = 2.2
	pool.bottom_radius = 2.2
	pool.height = 0.004
	_mesh(pool, _unlit(Color("#ffc070"), 0.16, true), Vector3(p.x, 0.02, p.y))
	var cone := CylinderMesh.new()
	cone.top_radius = 0.4
	cone.bottom_radius = 1.6
	cone.height = 2.35
	cone.cap_top = false
	cone.cap_bottom = false
	_mesh(cone, _unlit(Color("#ffd290"), 0.03, true), Vector3(p.x, 1.24, p.y))
	_bowl = Node3D.new()
	var cup := CylinderMesh.new()
	cup.top_radius = 0.11
	cup.bottom_radius = 0.07
	cup.height = 0.08
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color("#e9e3d6")
	bm.emission_enabled = true
	bm.emission = Color("#4a3a26")
	var cm := MeshInstance3D.new()
	cm.mesh = cup
	cm.material_override = bm
	_bowl.add_child(cm)
	var rice := SphereMesh.new()
	rice.radius = 0.1
	rice.height = 0.1
	rice.is_hemisphere = true
	var rm := MeshInstance3D.new()
	rm.mesh = rice
	rm.material_override = bm
	rm.position.y = 0.03
	rm.scale.y = 0.5
	_bowl.add_child(rm)
	_bowl.position = Vector3(dish.x, 0.98, dish.y)
	add_child(_bowl)
	_fig = FigureModel.make("person", Color("#2a2a2c"), false,1,Color("0d0b08"))
	_fig.position = Vector3(back.x, 0.0, back.y)
	add_child(_fig)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color("#ffc27a")
	lamp.omni_range = 7.5
	lamp.light_energy = 1.6
	lamp.position = Vector3(p.x, 2.3, p.y)
	add_child(lamp)
	_built = true


func built() -> bool:
	return _built


## active: the room is the canteen and the lights are out; me: the player in scene metres; ate: tonight's bowl is gone.
func update(active: bool, me: Vector2, ate: bool) -> void:
	visible = active
	if not active or _fig == null:
		return
	# Its back to you: the face away from you.
	var fp := _fig.position
	_fig.rotation.y = atan2(fp.x - me.x, fp.z - me.y) + PI
	_bowl.visible = not ate
