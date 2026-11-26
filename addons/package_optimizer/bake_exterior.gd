extends SceneTree
## Run as a game subprocess so the exporter uses the exact non-tool campus
## builder. All products stay in the editor cache until added to the package.

const Exterior := preload("res://game/presentation/world/campus/baked_exterior.gd")


func _initialize() -> void:
	call_deferred("_bake")


func _bake() -> void:
	var directories := OS.get_cmdline_user_args()
	if directories.size() != 1:
		quit(1)
		return
	var world := CampusWorld.new()
	world.scene_id = "out"
	world.resident = true
	world.layout = CampusData.layout(world.scene_id)
	world.space = CampusSpace.new(CampusData.rooms(), world.layout, CampusData.campus())
	for tier: int in CampusData.MODEL_TIERS:
		CampusData.tier = tier
		var started := Time.get_ticks_msec()
		# Supply the tier's original geometry explicitly, even if a previous
		# package happens to be mounted in this project.
		var source := CampusData.instantiate_model(world.scene_id, tier)
		var model := world._prepare_visual(tier, source) if source != null else null
		var result := _save(model, directories[0].path_join(Exterior.PATH.get_file() % tier))
		if model != null: model.free()
		if result != OK:
			printerr("Could not bake exterior tier ", tier, ": ", error_string(result))
			world.free()
			quit(1)
			return
		print("Prepared exterior tier %d in %d ms" % [tier, Time.get_ticks_msec() - started])
	world.free()
	quit()


func _save(model: Node3D, path: String) -> Error:
	if model == null or not model.has_node(CampusShell.ROOFLINE): return ERR_INVALID_DATA
	var facades: Dictionary = model.get_meta("facades", {})
	if facades.is_empty(): return ERR_INVALID_DATA
	var paths := {}
	for id: String in facades: paths[id] = model.get_path_to(facades[id])
	model.remove_meta("facades")
	model.set_meta(Exterior.FACADES, paths)
	# Flatten instance ownership so the native scene includes every runtime
	# edit (cuts, material overrides and reparented children of source scenes).
	model.scene_file_path = ""
	for child: Node in model.find_children("*", "", true, false):
		child.owner = model
		child.scene_file_path = ""
		if child is MultiMeshInstance3D:
			var mm: MultiMesh = child.multimesh
			var transforms: PackedFloat32Array = child.get_meta("campus_transforms", PackedFloat32Array())
			var colors: PackedFloat32Array = child.get_meta("campus_colors", PackedFloat32Array())
			if mm == null or mm.mesh == null or transforms.size() != mm.instance_count * 12 or (mm.use_colors and colors.size() != mm.instance_count * 3):
				return ERR_INVALID_DATA
	var packed := PackedScene.new()
	var result := packed.pack(model)
	if result != OK: return result
	return ResourceSaver.save(packed, path, ResourceSaver.FLAG_COMPRESS)
