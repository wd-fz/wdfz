extends RefCounted
## The exporter runs the normal resident visual builder once per tier. Raw scenes
## remain available for previews, unoptimized rendering and Android recovery.

const PATH := "res://assets/campus/resident/out_%d.scn"
const FACADES := &"resident_facade_paths"


static func instantiate(tier: int) -> Node3D:
	var path := PATH % tier
	if not ResourceLoader.exists(path): return null
	var scene := ResourceLoader.load(path, "PackedScene") as PackedScene
	if scene == null or not scene.can_instantiate(): return null
	var model := scene.instantiate() as Node3D
	if model == null: return null
	var paths: Dictionary = model.get_meta(FACADES, {})
	var facades := {}
	for id: String in paths:
		var facade := model.get_node_or_null(paths[id]) as Node3D
		if facade == null: break
		facades[id] = facade
	if facades.is_empty() or facades.size() != paths.size() or not model.has_node(CampusShell.ROOFLINE):
		model.free()
		return null
	# Headless export has no GPU instance buffer. The partitioner retains the
	# original matrices and colours for every instance, including clipped batches.
	for node: MultiMeshInstance3D in model.find_children("*", "MultiMeshInstance3D", true, false):
		var mm := node.multimesh
		var transforms: PackedFloat32Array = node.get_meta("campus_transforms", PackedFloat32Array())
		var colors: PackedFloat32Array = node.get_meta("campus_colors", PackedFloat32Array())
		if mm == null or mm.mesh == null or transforms.size() != mm.instance_count * 12 or (mm.use_colors and colors.size() != mm.instance_count * 3):
			model.free()
			return null
		CampusPreview.upload_instances(mm, transforms, colors)
	model.set_meta("facades", facades)
	return model
