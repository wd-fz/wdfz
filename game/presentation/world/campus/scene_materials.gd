class_name SceneMaterials
extends RefCounted
## The campus uses diffuse matte surfaces instead of quality-dependent PBR.
## Preserve imported albedo, transparency, emission, vertex colour and geometry.
const MATTE := 0.9


static func has_vertex_palette(mesh: ArrayMesh, surface: int) -> bool:
	return mesh != null and (mesh.surface_get_format(surface) & Mesh.ARRAY_FORMAT_COLOR) != 0


## Imported resources are shared with streaming previews. All tiers use the same
## response, and repeat applications never rewrite a live material.
static func apply(model: Node, _quality: int) -> int:
	if model == null:
		return 0
	var meshes: Array[Mesh] = []
	for n: Node in model.find_children("*", "MeshInstance3D", true, false):
		if (n as MeshInstance3D).mesh != null:
			meshes.append((n as MeshInstance3D).mesh)
	for n: Node in model.find_children("*", "MultiMeshInstance3D", true, false):
		var mm := (n as MultiMeshInstance3D).multimesh
		if mm != null and mm.mesh != null:
			meshes.append(mm.mesh)
	# A glTF material may be shared by surfaces with and without COLOR_0.
	# Include the authored colour whenever any surface supplies it. This also
	# repairs imports where the colours survived but their material flag did not.
	var palettes: Dictionary[BaseMaterial3D, bool] = {}
	for mesh: Mesh in meshes:
		var array_mesh := mesh as ArrayMesh
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i) as BaseMaterial3D
			if mat != null and not palettes.get(mat, false):
				palettes[mat] = mat.vertex_color_use_as_albedo or has_vertex_palette(array_mesh, i)
	var changed := 0
	for mat: BaseMaterial3D in palettes:
		var restore_color := palettes[mat] and not mat.vertex_color_use_as_albedo
		var matte := mat.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED and (
			mat.diffuse_mode != BaseMaterial3D.DIFFUSE_LAMBERT or mat.specular_mode != BaseMaterial3D.SPECULAR_DISABLED
			or not is_zero_approx(mat.metallic) or not is_equal_approx(mat.roughness, MATTE))
		if restore_color: mat.vertex_color_use_as_albedo = true
		if matte:
			mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			mat.metallic = 0.0
			mat.roughness = MATTE
		if restore_color or matte: changed += 1
	return changed
