extends "res://tests/support/test_suite.gd"
## The rebuilt figures (tools/remodel): same heights and stance as the old build's models, one continuous surface.

## Bounding boxes of the old exported figures (height, width, depth in metres), measured before the rebuild.
const OLD := {"tall": [2.560, 0.544, 0.319], "roam": [2.600, 0.518, 0.306], "person": [1.859, 0.526, 0.318],
	"teacher": [2.500, 0.532, 0.319], "neck": [2.970, 0.537, 0.313], "sit": [1.403, 0.457, 0.732]}


func _box(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var b := mi.transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func test_figures() -> void:
	for kind: String in FigureModel.KINDS:
		var packed := load("res://assets/campus/figures/%s.glb" % kind) as PackedScene
		var node := packed.instantiate() as Node3D
		var meshes := node.find_children("*", "MeshInstance3D", true, false)
		var box := _box(node)
		var old: Array = OLD[kind]
		check(meshes.size() == 1 and absf(box.end.y - float(old[0])) <= 0.02 and absf(box.position.y) <= 0.02,
			"%s stands on the ground and keeps the old height within 2 cm (%.3f, was %.3f)" % [kind, box.end.y, old[0]])
		check(absf(box.size.x - float(old[1])) <= 0.05 and absf(box.size.z - float(old[2])) <= 0.06 and absf(box.get_center().x) < 0.01,
			"%s keeps the old width and depth within a few centimetres and stays symmetric (%.3f × %.3f)" % [kind, box.size.x, box.size.z])
		var mesh := (meshes[0] as MeshInstance3D).mesh
		var fmt: int = mesh.surface_get_format(0)
		check(mesh.get_surface_count() == 1 and fmt & Mesh.ARRAY_FORMAT_NORMAL != 0 and fmt & Mesh.ARRAY_FORMAT_COLOR != 0, "%s is one surface with normals and the baked shade" % kind)
		node.free()
	# Seated: the hands still rest above the desk top (0.74 m) in front of the body.
	var sit := FigureModel.make("sit", Color.WHITE)
	var sbox := _box(sit.get_child(0) as Node3D)
	check(sbox.size.z > 0.7 and sbox.end.y < 1.42, "the seated figure reaches forward over the desk and stays under 1.42 m")
	sit.free()
	# FigureModel still tints the whole person and turns it to face Godot's forward.
	var made := FigureModel.make("person", Color("#465353"), true)
	var mi := made.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var mat := mi.material_override as StandardMaterial3D
	check(mat.albedo_color == Color("#465353") and mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and not mat.vertex_color_use_as_albedo and is_equal_approx((made.get_child(0) as Node3D).rotation.y, PI),
		"the dark silhouettes are still a single unlit tint")
	made.free()
	# The patroller: the teacher's build at 1.12 with the old coat and cap.
	var patrol := (load("res://assets/campus/patrol/patrol_figure.glb") as PackedScene).instantiate() as Node3D
	var parts := patrol.find_children("*", "MeshInstance3D", true, false)
	var body := (parts[0] as MeshInstance3D).get_aabb()
	check(parts.size() == 2 and absf(body.end.y - 2.5 * 1.12) <= 0.03, "the patroller is the teacher's build at 1.12 (%.3f m) and keeps its coat and cap" % body.end.y)
	var body_mat := (parts[0] as MeshInstance3D).mesh.surface_get_material(0) as BaseMaterial3D
	check(body_mat.albedo_color.r < 0.05 and body_mat.albedo_color.g < 0.05, "its body stays near black")
	patrol.free()
