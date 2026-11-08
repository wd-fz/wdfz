class_name DeathGeometry
extends RefCounted
## Original primitive and merged meshes, exported by tools/export_reference.py.
const MAIN := "res://assets/campus/death_geometry.json"
static var _cache: Dictionary = {}
static var _source: Dictionary = {}

static func mesh(key: String, source_path: String = MAIN) -> ArrayMesh:
	var cache_key := source_path+":"+key
	if _cache.has(cache_key): return _cache[cache_key]
	if not _source.has(source_path): _source[source_path] = JSON.parse_string(FileAccess.get_file_as_string(source_path))
	var data: Dictionary = _source[source_path][key]
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
	if data.has("colors"):
		var colors := PackedColorArray()
		for i in range(0,data["colors"].size(),3):
			colors.append(Color(data["colors"][i],data["colors"][i+1],data["colors"][i+2]))
		arrays[Mesh.ARRAY_COLOR] = colors
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_cache[cache_key] = result
	return result
