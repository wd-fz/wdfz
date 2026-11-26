extends RefCounted
## The exporter runs the normal resident visual builder once per tier. Raw scenes
## remain available for previews, unoptimized rendering and Android recovery.

const PATH := "res://assets/campus/resident/out_%d.scn"
const FACADES := &"resident_facade_paths"
const GEOMETRY := &"resident_geometry_counts"


static func instantiate(tier: int) -> Node3D:
	var path := PATH % tier
	if not ResourceLoader.exists(path): return null
	return restore(ResourceLoader.load(path, "PackedScene") as PackedScene)


static func restore(scene: PackedScene) -> Node3D:
	if scene == null or not scene.can_instantiate(): return null
	var instance := scene.instantiate()
	if not instance is Node3D:
		if instance != null: instance.free()
		return null
	var model := instance as Node3D
	var paths: Variant = model.get_meta(FACADES, {})
	if not paths is Dictionary:
		model.free()
		return null
	var facades := {}
	for id: Variant in paths:
		if not id is String or not paths[id] is NodePath: break
		var facade := model.get_node_or_null(paths[id]) as Node3D
		if facade == null: break
		facades[id] = facade
	if facades.size() != paths.size() or not facades.has("teach1") or not facades.has("lab1") or not model.has_node(CampusShell.ROOFLINE):
		model.free()
		return null
	# Some Android failures leave a valid node tree with missing mesh resources.
	# Count actual drawable surfaces and instances against the export-time result.
	var expected: Variant = model.get_meta(GEOMETRY, Vector2i.ZERO)
	if not expected is Vector2i or expected.x <= 0 or expected.y <= 0 or static_surface_count(model) != expected.x:
		model.free()
		return null
	var instances := 0
	# Headless export has no GPU instance buffer. The partitioner retains the
	# original matrices and colours for every instance, including clipped batches.
	for node: MultiMeshInstance3D in model.find_children("*", "MultiMeshInstance3D", true, false):
		if not valid_batch(node):
			model.free()
			return null
		instances += node.multimesh.instance_count
		CampusPreview.upload_instances(node.multimesh, node.get_meta("campus_transforms"), node.get_meta("campus_colors", PackedFloat32Array()))
	if instances != expected.y:
		model.free()
		return null
	model.set_meta("facades", facades)
	return model


static func static_surface_count(model: Node3D) -> int:
	var count := 0
	for node: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if node.mesh != null: count += node.mesh.get_surface_count()
	return count


static func valid_batch(node: MultiMeshInstance3D) -> bool:
	var mm := node.multimesh
	if mm == null or mm.mesh == null or mm.mesh.get_surface_count() == 0 or mm.instance_count <= 0: return false
	var transforms: Variant = node.get_meta("campus_transforms", PackedFloat32Array())
	var colors: Variant = node.get_meta("campus_colors", PackedFloat32Array())
	return transforms is PackedFloat32Array and transforms.size() == mm.instance_count * 12 and colors is PackedFloat32Array and (not mm.use_colors or colors.size() == mm.instance_count * 3)
