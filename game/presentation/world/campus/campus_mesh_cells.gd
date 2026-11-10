class_name CampusMeshCells
extends RefCounted
## Split material-merged floor-wide meshes by triangle centroid, without moving vertices
## or changing attributes. Culling/shadow passes can then reject individual spatial cells.
## A bounded cache avoids rebuilding the same floor for each visual portal.

const CELL := 16.0
const MIN_TRIANGLES := 4096
const CACHE_LIMIT := 48
static var _cache: Dictionary = {}


static func _pieces(mesh: Mesh) -> Array[ArrayMesh]:
	if mesh is ArrayMesh and mesh.get_blend_shape_count()>0: return []
	var id := mesh.get_instance_id()
	if _cache.has(id) and _cache[id].source.get_ref() == mesh: return _cache[id].pieces
	var buckets := {}
	for s in mesh.get_surface_count():
		if CampusBatches._primitive(mesh,s) != Mesh.PRIMITIVE_TRIANGLES: return []
		var mat := mesh.surface_get_material(s) as BaseMaterial3D
		# Splitting alpha-blended objects changes their depth-sort order.
		if mat == null or mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: return []
		var arrays := mesh.surface_get_arrays(s)
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null: return []
		# Exported static campus meshes have no skinning, blend shapes or custom streams.
		for unsupported in [Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS, Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
			if arrays[unsupported] != null: return []
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		for i in range(0, indices.size() if not indices.is_empty() else vertices.size(), 3):
			var a := indices[i] if not indices.is_empty() else i
			var b := indices[i+1] if not indices.is_empty() else i+1
			var c := indices[i+2] if not indices.is_empty() else i+2
			var center := (vertices[a]+vertices[b]+vertices[c])/3.0
			var cell := Vector3i(floori(center.x/CELL),floori(center.y/CELL),floori(center.z/CELL))
			if not buckets.has(cell): buckets[cell] = {}
			var surfaces: Dictionary = buckets[cell]
			if not surfaces.has(s): surfaces[s] = {"map": {}, "vertices": PackedInt32Array(), "indices": PackedInt32Array()}
			var buffer: Dictionary = surfaces[s]
			for original: int in [a,b,c]:
				if not buffer.map.has(original):
					buffer.map[original] = buffer.vertices.size()
					buffer.vertices.append(original)
				buffer.indices.append(buffer.map[original])
	if buckets.size() <= 1: return []
	var pieces: Array[ArrayMesh] = []
	for surfaces: Dictionary in buckets.values():
		var builder := ImporterMesh.new()
		for s: int in surfaces:
			var arrays := mesh.surface_get_arrays(s)
			var buffer: Dictionary = surfaces[s]
			var output := []
			output.resize(Mesh.ARRAY_MAX)
			for attribute in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TANGENT,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2]:
				if arrays[attribute] == null: continue
				var data: Variant = arrays[attribute].duplicate()
				data.resize(0)
				var stride := 4 if attribute == Mesh.ARRAY_TANGENT else 1
				for original: int in buffer.vertices:
					for component in stride: data.append(arrays[attribute][original*stride+component])
				output[attribute] = data
			output[Mesh.ARRAY_INDEX] = buffer.indices
			builder.add_surface(Mesh.PRIMITIVE_TRIANGLES,output,[],{},mesh.surface_get_material(s))
		# Keep imported-style LODs instead of forcing full detail on every distant cell.
		builder.generate_lods(60,25,[])
		pieces.append(builder.get_mesh())
	while _cache.size() >= CACHE_LIMIT: _cache.erase(_cache.keys()[0])
	_cache[id] = {"source": weakref(mesh), "pieces": pieces}
	return pieces


static func apply(model: Node3D) -> int:
	if not CampusBatches.enabled: return 0
	var count := 0
	for source: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if source.mesh == null or CampusBatches._dynamic(source,model) or not source.visible or source.get_child_count() != 0: continue
		if source.material_override != null or source.material_overlay != null or source.skin != null: continue
		var overrides:=false
		for s in source.mesh.get_surface_count(): overrides=overrides or source.get_surface_override_material(s)!=null
		if overrides: continue
		var bounds := source.mesh.get_aabb().size
		if maxf(bounds.x,bounds.z) <= CELL*1.5: continue
		var triangles:=0
		for s in source.mesh.get_surface_count():
			var arrays:=source.mesh.surface_get_arrays(s)
			if not arrays.is_empty() and arrays[Mesh.ARRAY_VERTEX]!=null:
				triangles+=(arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX]!=null and not arrays[Mesh.ARRAY_INDEX].is_empty() else arrays[Mesh.ARRAY_VERTEX].size())/3
		# Small wall/floor batches cost less to submit than many additional draws. In
		# open spaces (e.g. the garage) splitting them creates work without occlusion.
		if triangles<MIN_TRIANGLES: continue
		var pieces := _pieces(source.mesh)
		if pieces.is_empty(): continue
		for piece in pieces:
			var node := MeshInstance3D.new()
			node.name = "Cell_%s_%d" % [source.name,count]
			node.mesh = piece
			node.transform = source.transform
			node.layers = source.layers
			node.cast_shadow = source.cast_shadow
			source.get_parent().add_child(node)
			count += 1
		source.free()
	model.set_meta("render_cells",count)
	return count
