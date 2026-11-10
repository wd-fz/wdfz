class_name SceneMaterials
extends RefCounted
## Surface response of the exported campus materials, by picture quality. Geometry and textures are untouched.
##
## The exporter turned the old build's Phong materials (tiers 流畅 … 超精细) into roughness as 1 − shininess / 100, and
## wrote shininess 0 as 30 — so walls, ceilings, blackboards and curtains, which have no highlight at all in the old
## build, came out half glossy (0.70). The old build's own 真实 tier uses physical materials instead:
## roughness = clamp(1 − sqrt(shininess / 90), 0.22, 0.96), metal 0.7 for metal, glass 0.05 (model/materials.js matPBR).
##   every tier   the matte surfaces are matte again (0.96, as in the old 真实 tier)
##   精细, 超精细  the old physical mapping for the rest: floors, desk tops, plastic, metal and glass answer the lamps and
##               the window light; metal only slightly metallic (0.15): with nothing bright to mirror, a strongly metallic locker just turns black
##   真实          already exported with the old physical materials: left as it is

const MATTE := 0.96
const METAL_SHININESS := 40
const GLASS_SHININESS := 60
const MID_TIER_METALLIC := 0.15


## The old shininess behind an exported roughness (−1: not one of the Phong conversions).
static func shininess_of(mat: BaseMaterial3D, exported_roughness: float) -> int:
	if not String(mat.resource_name).begins_with("MeshPhongMaterial"):
		return -1
	if is_equal_approx(exported_roughness, 0.7):
		return 0            # shininess 0 written as 30
	return roundi((1.0 - exported_roughness) * 100.0)


## The old build's physical roughness for a shininess (matPBR).
static func physical_roughness(shininess: int) -> float:
	return clampf(1.0 - sqrt(float(shininess) / 90.0), 0.22, 0.96)


## {"roughness", "metallic"} of a material at a quality, from its exported roughness.
static func response(mat: BaseMaterial3D, exported_roughness: float, quality: int) -> Dictionary:
	var s := shininess_of(mat, exported_roughness)
	if s < 0:
		return {"roughness": exported_roughness, "metallic": mat.metallic}
	if s == 0:
		return {"roughness": MATTE, "metallic": 0.0}
	if quality < 2:
		return {"roughness": exported_roughness, "metallic": 0.0}
	if s == GLASS_SHININESS and mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return {"roughness": 0.05, "metallic": 0.0}
	return {"roughness": physical_roughness(s), "metallic": MID_TIER_METALLIC if s == METAL_SHININESS else 0.0}


## Apply to every material of a model. The imported materials are shared resources: the exported roughness is kept in
## a meta entry, so applying twice, or at another quality, always starts from the file's own value.
static func apply(model: Node, quality: int) -> int:
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
			if not mat.has_meta("wdfz_rough"):
				mat.set_meta("wdfz_rough", mat.roughness)
			var r := response(mat, float(mat.get_meta("wdfz_rough")), quality)
			if not is_equal_approx(mat.roughness, float(r["roughness"])) or not is_equal_approx(mat.metallic, float(r["metallic"])):
				changed += 1
			mat.roughness = float(r["roughness"])
			mat.metallic = float(r["metallic"])
	return changed
