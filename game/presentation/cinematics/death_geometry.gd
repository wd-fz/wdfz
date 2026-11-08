class_name DeathGeometry
extends RefCounted
## Small original primitive meshes whose partial spheres / tetrahedron differ from Godot primitives.
## Exported directly from death-cg.js by tools/export_reference.py --death-timelines-only.
static var _cache: Dictionary = {}
static var _source: Dictionary = {}

static func mesh(key: String) -> ArrayMesh:
	if _cache.has(key): return _cache[key]
	if _source.is_empty(): _source = JSON.parse_string(FileAccess.get_file_as_string("res://assets/campus/death_geometry.json"))
	var data: Dictionary = _source[key]
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	for i in range(0,data["vertices"].size(),3):
		points.append(Vector3(data["vertices"][i],data["vertices"][i+1],data["vertices"][i+2]))
		normals.append(Vector3(data["normals"][i],data["normals"][i+1],data["normals"][i+2]))
	var indices := PackedInt32Array(data["indices"] if data["indices"]!=null else range(points.size()))
	# Three.js front faces wind counterclockwise; Godot uses clockwise winding.
	for i in range(0,indices.size(),3):
		var second := indices[i+1]
		indices[i+1] = indices[i+2]
		indices[i+2] = second
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_cache[key] = result
	return result
