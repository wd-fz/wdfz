class_name ObservationProps
extends Node3D
## Fixed local geometry. The only moving part is the one-shot paper punch.
static var _cube: BoxMesh
static var _disk: CylinderMesh
static var _materials: Dictionary = {}
static var _paper_meshes: Dictionary = {}
var _samples: Array[MeshInstance3D] = []
var _selected := ""

const IRON := Color("#344341")
const WOOD := Color("#715139")
const SHEET := Color("#ede1b8")
const RED := Color("#9e4639")
const INK := Color("#27302e")
const SCALE := Color("#d4bb83")


func build(world: String, sites_here: Array, ground: Callable) -> void:
	for site: Dictionary in sites_here:
		var mount := Node3D.new()
		mount.name = String(site.id).replace(".", "_")
		var at: Vector2 = site.anchor
		var base := float(site.base)
		if world == "out": base = float(ground.call(at.x, at.y))
		mount.position = Vector3(at.x, base + (0.89 if world in ["link1", "link2"] else 1.50), at.y)
		var normal: Vector2 = site.normal
		mount.rotation.y = atan2(normal.x, normal.y)
		add_child(mount)
		if world == "out":
			_box(mount, Vector3(0.055, 1.46, 0.055), Vector3(0, -0.77, 0), IRON)
			_box(mount, Vector3(0.36, 0.04, 0.24), Vector3(0, -1.48, 0), IRON)
		match String(site.form):
			"tray": _tray(mount)
			"clock": _clock(mount)
			"tape": _tape(mount)
			"ruler": _ruler(mount)
			"height":
				var scale_marks := Node3D.new()
				mount.add_child(scale_marks)
				scale_marks.rotation.z = PI / 2
				_ruler(scale_marks)
			"chalk":
				_landing(mount, world)
				continue
			_:
				_sheet(mount, site.title, site.form == "drawing")
				continue
		var offset := -0.306 if site.form == "height" else (-0.126 if site.form == "tape" else -0.236)
		_box(mount, Vector3(0.47, 0.072, 0.016), Vector3(0, offset, 0.038), IRON)
		_label(mount, site.title, Vector3(0, offset, 0.049), 0.00083)


static func _material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.85
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[color] = material
	return _materials[color]


func _piece(parent: Node3D, mesh: Mesh, at: Vector3, color: Color) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.material_override = _material(color)
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part


func _box(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	if _cube == null: _cube = BoxMesh.new()
	var part := _piece(parent, _cube, at, color)
	part.scale = size
	return part


func _round(parent: Node3D, radius: float, at: Vector3, color: Color) -> void:
	if _disk == null:
		_disk = CylinderMesh.new()
		_disk.radial_segments = 24
		_disk.rings = 0
	var part := _piece(parent, _disk, at, color)
	part.rotation.x = PI / 2
	part.scale = Vector3(radius * 2, 0.012, radius * 2)


func _label(parent: Node3D, caption: String, at: Vector3, pixel: float, color: Color = SHEET) -> void:
	var label := Label3D.new()
	label.text = caption
	label.font_size = 48
	label.pixel_size = pixel
	label.outline_size = 0
	label.modulate = color
	label.position = at
	label.double_sided = false
	parent.add_child(label)


func _sheet(mount: Node3D, title: String, drawing: bool) -> void:
	_box(mount, Vector3(0.38, 0.43, 0.034), Vector3(0, 0.035, 0.02), WOOD)
	_box(mount, Vector3(0.31, 0.35, 0.009), Vector3(0.006, 0.03, 0.045), SHEET)
	_box(mount, Vector3(0.13, 0.039, 0.018), Vector3(0, 0.207, 0.047), IRON)
	_label(mount, title, Vector3(0, 0.149, 0.052), 0.00065, INK)
	if drawing:
		_round(mount, 0.046, Vector3(-0.014, 0.034, 0.057), INK)
		_round(mount, 0.038, Vector3(-0.013, 0.028, 0.073), SHEET)
		for side: float in [-1, 1]:
			_box(mount, Vector3(0.014, 0.049, 0.005), Vector3(-0.014 + 0.051 * side, 0.004, 0.066), INK).rotation.z = side * 0.33
			_box(mount, Vector3(0.006, 0.075, 0.004), Vector3(-0.014 + 0.031 * side, -0.049, 0.058), INK).rotation.z = side * 0.47
	else:
		for i in 4:
			_box(mount, Vector3(0.22 - (i % 2) * 0.047, 0.006, 0.004), Vector3(-0.02, 0.091 - i * 0.043, 0.052), INK)
	_round(mount, 0.028, Vector3(0.092, -0.096, 0.057), RED)


func _landing(mount: Node3D, world: String) -> void:
	if world == "stair_teach_w":
		_box(mount, Vector3(0.23, 0.013, 0.006), Vector3(-0.05, 0.04, 0.012), SHEET).rotation.z = 0.13
		_box(mount, Vector3(0.19, 0.014, 0.006), Vector3(-0.035, -0.012, 0.012), SHEET).rotation.z = 0.22
		_label(mount, "又是二楼", Vector3(0.045, -0.090, 0.016), 0.00072)
		return
	var markings := {"stair_teach_e": "东梯", "stair_admin": "柜宽", "stair_lab": "箱顶", "stair_dormN": "↑ 巡房", "stair_dormS": "二楼补拍", "stair_garage": "积水"}
	_box(mount, Vector3(0.32, 0.009, 0.006), Vector3(0, -0.015, 0.012), SCALE)
	_label(mount, markings[world], Vector3(-0.025, 0.046, 0.016), 0.00073)


func _clock(mount: Node3D) -> void:
	_round(mount, 0.213, Vector3(0, 0.04, 0.022), IRON)
	_round(mount, 0.191, Vector3(0, 0.04, 0.049), SHEET)
	for i in 12:
		var angle := i * TAU / 12.0
		_box(mount, Vector3(0.011, 0.026, 0.005), Vector3(sin(angle) * 0.166, 0.04 + cos(angle) * 0.166, 0.064), INK).rotation.z = -angle
	for data: Vector2 in [Vector2(8.0 / 12 * TAU, 0.138), Vector2((11.0 + 2.0 / 3) / 12 * TAU, 0.089)]:
		_box(mount, Vector3(0.014, data.y, 0.007), Vector3(sin(data.x) * data.y / 2, 0.04 + cos(data.x) * data.y / 2, 0.073), INK).rotation.z = -data.x


func _tape(mount: Node3D) -> void:
	_box(mount, Vector3(0.45, 0.255, 0.064), Vector3(0, 0.03, 0.04), IRON)
	_box(mount, Vector3(0.37, 0.15, 0.012), Vector3(0, 0.052, 0.078), SCALE)
	for side: float in [-1.0, 1.0]:
		_round(mount, 0.052, Vector3(0.102 * side, 0.053, 0.09), INK)
		_round(mount, 0.017, Vector3(0.102 * side, 0.053, 0.107), SHEET)
	_box(mount, Vector3(0.12, 0.015, 0.008), Vector3(0, -0.054, 0.078), RED)


func _ruler(mount: Node3D) -> void:
	_box(mount, Vector3(0.54, 0.095, 0.024), Vector3(0, 0.01, 0.023), SCALE)
	for i in 13:
		var height := 0.049 if i % 3 == 0 else 0.026
		_box(mount, Vector3(0.006, height, 0.004), Vector3(-0.24 + i * 0.040, 0.054 - height / 2, 0.038), RED if i == 6 else INK)


func _tray(mount: Node3D) -> void:
	_box(mount, Vector3(0.63, 0.42, 0.07), Vector3(0, 0.03, 0.038), WOOD)
	_box(mount, Vector3(0.58, 0.36, 0.010), Vector3(0, 0.04, 0.078), IRON)
	for side: int in 2:
		var x := -0.145 if side == 0 else 0.145
		_samples.append(_piece(mount, paper_mesh(false), Vector3(x, 0.072, 0.09), SHEET))
		_label(mount, "甲" if side == 0 else "乙", Vector3(x, -0.104, 0.095), 0.0007)
	_box(mount, Vector3(0.052, 0.27, 0.05), Vector3(0, 0.06, 0.11), RED)


## The half-round cut removes geometry so the dark tray shows through at any angle.
static func paper_mesh(notched: bool) -> ArrayMesh:
	if _paper_meshes.has(notched): return _paper_meshes[notched]
	var points := PackedVector2Array([Vector2(-0.105, -0.13), Vector2(0.105, -0.13), Vector2(0.105, 0.13)])
	if notched:
		for i in 11:
			var angle := i * PI / 10.0
			points.append(Vector2(0.040 * cos(angle), 0.13 - 0.040 * sin(angle)))
	points.append(Vector2(-0.105, 0.13))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var indices := Geometry2D.triangulate_polygon(points)
	indices.reverse() # Godot renders clockwise triangle faces toward the reader.
	for i: int in indices:
		surface.set_normal(Vector3.BACK)
		surface.add_vertex(Vector3(points[i].x, points[i].y, 0))
	var mesh := surface.commit()
	_paper_meshes[notched] = mesh
	return mesh


func set_sample(selected: String) -> void:
	if selected == _selected or _samples.size() != 2: return
	_selected = selected
	_samples[0].mesh = paper_mesh(selected == "甲")
	_samples[1].mesh = paper_mesh(selected == "乙")
