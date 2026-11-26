@tool
extends EditorScenePostImport
## Record immutable geometry while the imported arrays are available. Runtime
## clipping creates new meshes and automatically uses the uncached path.

func _post_import(scene: Node) -> Object:
	var nodes := scene.find_children("*", "MeshInstance3D", true, false)
	var source := get_source_file().get_file()
	if source == "out.glb": _share_outdoor_props(nodes)
	for node: MeshInstance3D in nodes:
		var mesh := node.mesh as ArrayMesh
		if mesh == null or mesh.resource_local_to_scene or mesh.get_script() != null: continue
		# Preserve glTF COLOR_0 in the native models shipped inside the APK.
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface) as BaseMaterial3D
			if material != null and not material.vertex_color_use_as_albedo and SceneMaterials.has_vertex_palette(mesh, surface):
				material.vertex_color_use_as_albedo = true
		if source == "furnishings.glb" or node.get_meta("extras", {}).has("wdfz_instances"):
			if not mesh.has_meta(CampusBatches.GEOMETRY_KEY):
				mesh.set_meta(CampusBatches.GEOMETRY_KEY, CampusBatches.geometry_key(mesh))
		elif not mesh.has_meta(CampusBatches.OCCLUDER_FACES) and not CampusBatches._dynamic(node, scene):
			var faces := {}
			for s in mesh.get_surface_count():
				var mat := mesh.surface_get_material(s) as BaseMaterial3D
				if mat == null or mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: continue
				if mesh.surface_get_primitive_type(s) == Mesh.PRIMITIVE_TRIANGLES:
					faces[s] = CampusBatches.occluding_faces(mesh, s, Transform3D.IDENTITY)
			if not faces.is_empty(): mesh.set_meta(CampusBatches.OCCLUDER_FACES, faces)
	return scene


## The original outdoor exporter emitted a separate mesh even for identical props.
func _share_outdoor_props(nodes: Array[Node]) -> void:
	var prototypes := {}
	var material_keys := {}
	for node: MeshInstance3D in nodes:
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
