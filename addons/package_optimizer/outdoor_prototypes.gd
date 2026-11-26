@tool
extends EditorScenePostImport
## The campus exporter writes one mesh per prop batch, even for identical props.
## Share their native resources at import, before a Vulkan streaming worker uploads them.

func _post_import(scene: Node) -> Object:
	var prototypes := {}
	var material_keys := {}
	for node: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var extras: Dictionary = node.get_meta("extras", {})
		var mesh := node.mesh as ArrayMesh
		if mesh == null or not extras.has("wdfz_instances"): continue
		var key := _mesh_key(mesh, material_keys)
		if key.is_empty(): continue
		# The runtime enables vertex colour on materials used by tinted batches.
		key += ":tinted" if extras.has("wdfz_colors") else ":plain"
		if prototypes.has(key):
			node.mesh = prototypes[key]
		else:
			prototypes[key] = mesh
	return scene


func _mesh_key(mesh: ArrayMesh, materials: Dictionary) -> String:
	if mesh.resource_local_to_scene or mesh.get_script() != null or mesh.get_blend_shape_count() != 0 or not mesh.get_meta_list().is_empty():
		return ""
	# Godot's serialized surfaces include the original packed attributes, indices,
	# LODs, names and bounds. Compare these before discarding a duplicate resource.
	var surfaces: Array = mesh.get("_surfaces")
	if surfaces.is_empty() or surfaces.size() != mesh.get_surface_count(): return ""
	for surface: Dictionary in surfaces:
		if not surface.has("material"): continue
		var mat := surface["material"] as BaseMaterial3D
		if mat == null or mat.resource_local_to_scene or mat.get_script() != null: return ""
		if not materials.has(mat):
			materials[mat] = CampusBatches._digest(CampusBatches._material_key(mat))
		surface["material"] = [mat.resource_name, materials[mat]]
	var shadow_key := ""
	if mesh.shadow_mesh != null:
		shadow_key = _mesh_key(mesh.shadow_mesh, materials)
		if shadow_key.is_empty(): return ""
	return CampusBatches._digest(var_to_bytes([surfaces, mesh.custom_aabb, mesh.lightmap_size_hint, mesh.blend_shape_mode, shadow_key]))
