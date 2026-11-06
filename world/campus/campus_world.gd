class_name CampusWorld
extends Node3D
## Presentation + physics adapter for one Web-version scene (a room or the campus outside).
## Geometry is the glb exported from the old game's own builders; collision boxes are the old
## game's own static collision rectangles (tools/export_scenes). No geometry is redrawn here.

const WALL_TOP := 3.5
const WALL_BOTTOM := -0.5
const BOUNDARY := 1.0

@export var scene_id := "out"

var layout: Dictionary = {}
var _door_bodies: Dictionary = {}   # key -> CollisionShape3D
var _door_leaves: Dictionary = {}   # key -> {"closed": Node3D, "open": Node3D}


func _ready() -> void:
	layout = CampusData.layout(scene_id)
	_build_model()
	_build_collision()
	_build_lighting()


func is_room() -> bool:
	return scene_id != "out"


# ---- model ----

func _build_model() -> void:
	var packed := load(CampusData.SCENE_DIR + scene_id + ".glb") as PackedScene
	if packed == null:
		push_error("校园模型缺失：%s" % scene_id)
		return
	var model := packed.instantiate() as Node3D
	model.name = "Model"
	add_child(model)
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.has_meta("extras") and (mesh.get_meta("extras") as Dictionary).has("wdfz_instances"):
			_to_multimesh(mesh)
	for holder: Node in model.get_children():
		var extras: Variant = holder.get_meta("extras") if holder.has_meta("extras") else null
		if extras is Dictionary and extras.has("door_key"):
			var key := String(extras["door_key"])
			if not _door_leaves.has(key):
				_door_leaves[key] = {}
			_door_leaves[key][String(extras["state"])] = holder
	for key: String in _door_leaves:
		set_door_open(key, false)


## Instances were kept as one prototype + per-instance transforms/colours in glTF extras.
func _to_multimesh(source: MeshInstance3D) -> void:
	var extras: Dictionary = source.get_meta("extras")
	var xf := Marshalls.base64_to_raw(String(extras["wdfz_instances"])).to_float32_array()
	var count := xf.size() / 12
	var colors := PackedFloat32Array()
	if extras.has("wdfz_colors"):
		colors = Marshalls.base64_to_raw(String(extras["wdfz_colors"])).to_float32_array()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors.size() >= count * 3
	mm.mesh = source.mesh
	mm.instance_count = count
	for i in count:
		var o := i * 12
		var basis := Basis(Vector3(xf[o], xf[o + 1], xf[o + 2]), Vector3(xf[o + 3], xf[o + 4], xf[o + 5]), Vector3(xf[o + 6], xf[o + 7], xf[o + 8]))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(xf[o + 9], xf[o + 10], xf[o + 11])))
		if mm.use_colors:
			mm.set_instance_color(i, Color(colors[i * 3], colors[i * 3 + 1], colors[i * 3 + 2]))
	if mm.use_colors and source.mesh != null:
		for s in source.mesh.get_surface_count():
			var mat := source.mesh.surface_get_material(s) as BaseMaterial3D
			if mat != null:
				mat.vertex_color_use_as_albedo = true
	var node := MultiMeshInstance3D.new()
	node.name = source.name
	node.multimesh = mm
	node.transform = source.transform
	source.get_parent().add_child(node)
	source.get_parent().remove_child(source)
	source.free()


func set_door_open(key: String, open: bool) -> void:
	if _door_leaves.has(key):
		var leaves: Dictionary = _door_leaves[key]
		if leaves.has("closed"):
			(leaves["closed"] as Node3D).visible = not open
		if leaves.has("open"):
			(leaves["open"] as Node3D).visible = open
	if _door_bodies.has(key):
		(_door_bodies[key] as CollisionShape3D).set_deferred("disabled", open)


func apply_doors(open_doors: Dictionary) -> void:
	for key: String in _door_bodies:
		set_door_open(key, open_doors.has(key))
	for key: String in _door_leaves:
		if not _door_bodies.has(key):
			set_door_open(key, open_doors.has(key))


func door_keys() -> PackedStringArray:
	return PackedStringArray(_door_bodies.keys())


# ---- collision ----

func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var extent := _extent()
	_add_box(body, Rect2(extent.position - Vector2.ONE * 2, extent.size + Vector2.ONE * 4), -1.0, 0.0, "floor")
	if is_room():
		for b: Dictionary in layout["walls"] + layout["boxes"] + layout["stairs"]:
			_add_rect(body, b)
		_room_boundary(body, extent)
		var doors := StaticBody3D.new()
		doors.name = "Doors"
		doors.collision_layer = 1
		doors.collision_mask = 0
		add_child(doors)
		for d: Dictionary in layout["doors"]:
			_door_bodies[String(d["key"])] = _add_rect(doors, d)
	else:
		for b: Dictionary in layout["boxes"]:
			_add_rect(body, b)
		var bd: Dictionary = layout["bound"]
		var inner := Rect2(Vector2(bd["x0"], bd["z0"]), Vector2(float(bd["x1"]) - float(bd["x0"]), float(bd["z1"]) - float(bd["z0"])))
		_ring(body, inner, [])


func _extent() -> Rect2:
	if is_room():
		var w := int(layout["cols"]) * float(layout["tw"]) * CampusGeometry.U2M
		var h := int(layout["rows"]) * float(layout["th"]) * CampusGeometry.U2M
		return Rect2(-w * 0.5, -h * 0.5, w, h)
	var bd: Dictionary = layout["bound"]
	return Rect2(Vector2(bd["x0"], bd["z0"]), Vector2(float(bd["x1"]) - float(bd["x0"]), float(bd["z1"]) - float(bd["z0"])))


func _add_rect(parent: Node3D, b: Dictionary) -> CollisionShape3D:
	var r := Rect2(Vector2(b["x0"], b["z0"]), Vector2(float(b["x1"]) - float(b["x0"]), float(b["z1"]) - float(b["z0"])))
	return _add_box(parent, r, WALL_BOTTOM, WALL_TOP, String(b["k"]))


func _add_box(parent: Node3D, r: Rect2, y0: float, y1: float, kind: String) -> CollisionShape3D:
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(r.size.x, 0.001), y1 - y0, maxf(r.size.y, 0.001))
	var node := CollisionShape3D.new()
	node.shape = shape
	node.position = Vector3(r.position.x + r.size.x * 0.5, (y0 + y1) * 0.5, r.position.y + r.size.y * 0.5)
	node.set_meta("kind", kind)
	parent.add_child(node)
	return node


## Old rule (collision.js): outside the room grid is wall, except the annex of a seamless door,
## which lets the body centre reach the threshold line where the scene switches.
func _room_boundary(body: StaticBody3D, extent: Rect2) -> void:
	var gaps: Array = []
	var campus := CampusData.campus()
	var cfg: Dictionary = campus.get("campus_doors", {})
	for d: Dictionary in cfg.get("doors", []):
		if d["room"] != scene_id:
			continue
		var port := CampusGeometry.door_port(layout, d)
		var p := CampusGeometry.to_scene(layout, port["p"])
		var n: Vector2 = port["n"]
		var half := CampusGeometry.door_half(d, float(cfg.get("width", 3))) * CampusGeometry.U2M
		var depth := float(cfg.get("annex", 1.5)) * CampusGeometry.TTILE * CampusGeometry.U2M + CampusGeometry.PRAD * CampusGeometry.U2M
		var lateral := Vector2(-n.y, n.x)
		gaps.append({"edge": d["edge"], "center": p, "half": half})
		# Annex side walls and end wall, outside the grid.
		for side: float in [-1.0, 1.0]:
			var a := p + lateral * side * half
			var b := a + n * depth + lateral * side * BOUNDARY
			_add_box(body, Rect2(a, Vector2.ZERO).expand(b), WALL_BOTTOM, WALL_TOP, "annex")
		var e0 := p + n * depth - lateral * half
		var e1 := p + n * (depth + BOUNDARY) + lateral * half
		_add_box(body, Rect2(e0, Vector2.ZERO).expand(e1), WALL_BOTTOM, WALL_TOP, "annex")
	_ring(body, extent, gaps)


func _ring(body: StaticBody3D, r: Rect2, gaps: Array) -> void:
	var t := BOUNDARY
	var x0 := r.position.x
	var z0 := r.position.y
	var x1 := r.end.x
	var z1 := r.end.y
	_edge(body, "n", Vector2(x0 - t, z0 - t), Vector2(x1 + t, z0), gaps)
	_edge(body, "s", Vector2(x0 - t, z1), Vector2(x1 + t, z1 + t), gaps)
	_edge(body, "w", Vector2(x0 - t, z0), Vector2(x0, z1), gaps)
	_edge(body, "e", Vector2(x1, z0), Vector2(x1 + t, z1), gaps)


func _edge(body: StaticBody3D, edge: String, a: Vector2, b: Vector2, gaps: Array) -> void:
	var horizontal := edge in ["n", "s"]
	var spans: Array = [[a.x, b.x] if horizontal else [a.y, b.y]]
	for g: Dictionary in gaps:
		if g["edge"] != edge:
			continue
		var c: Vector2 = g["center"]
		var lo := (c.x if horizontal else c.y) - float(g["half"])
		var hi := (c.x if horizontal else c.y) + float(g["half"])
		var next: Array = []
		for s: Array in spans:
			if hi <= s[0] or lo >= s[1]:
				next.append(s)
				continue
			if lo > s[0]:
				next.append([s[0], lo])
			if hi < s[1]:
				next.append([hi, s[1]])
		spans = next
	for s: Array in spans:
		var rect := Rect2(Vector2(s[0], a.y), Vector2(s[1] - s[0], b.y - a.y)) if horizontal \
			else Rect2(Vector2(a.x, s[0]), Vector2(b.x - a.x, s[1] - s[0]))
		_add_box(body, rect, WALL_BOTTOM, WALL_TOP, "boundary")


# ---- lighting (placeholder until lighting.js is ported) ----

func _build_lighting() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.6, 0.65) if not is_room() else Color(0.05, 0.06, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.86, 0.88)
	env.ambient_light_energy = 0.55 if is_room() else 0.7
	var world_env := WorldEnvironment.new()
	world_env.name = "PlaceholderEnvironment"
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.name = "PlaceholderSun" if not is_room() else "PlaceholderCeiling"
	sun.rotation_degrees = Vector3(-55, 30, 0) if not is_room() else Vector3(-90, 0, 0)
	sun.light_energy = 0.9 if not is_room() else 0.45
	add_child(sun)
