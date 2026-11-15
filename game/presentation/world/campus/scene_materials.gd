class_name SceneMaterials
extends RefCounted
## The campus uses diffuse matte surfaces instead of quality-dependent PBR.
## Preserve imported albedo, transparency, emission, vertex colour and geometry.
const MATTE := 0.9


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
	var seen := {}
	var changed := 0
	for mesh: Mesh in meshes:
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i) as BaseMaterial3D
			if mat == null or seen.has(mat) or mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
				continue
			seen[mat] = true
			var different := mat.diffuse_mode != BaseMaterial3D.DIFFUSE_LAMBERT or mat.specular_mode != BaseMaterial3D.SPECULAR_DISABLED or not is_zero_approx(mat.metallic) or not is_equal_approx(mat.roughness, MATTE)
			if different:
				changed += 1
				mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
				mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				mat.metallic = 0.0
				mat.roughness = MATTE
	return changed
