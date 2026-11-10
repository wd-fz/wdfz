class_name CampusBatches
extends RefCounted
## The exporter batches by Three.js object identity, not geometry/material value. Recover
## shared prototypes, then put instances in small spatial batches so the renderer can cull
## a classroom without submitting every desk on the floor. Never touches physics or doors.

const LOCAL_SPAN := 12.0
const MAX_SPAN := 64.0
const TRIANGLES_PER_BATCH := 2048
## The profiling runner can compare the original submission path in a separate process.
static var enabled := true


static func _digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


static func _primitive(mesh: Mesh, surface: int) -> int:
	return mesh.surface_get_primitive_type(surface) if mesh is ArrayMesh else Mesh.PRIMITIVE_TRIANGLES


static func _relative(node: Node3D, root: Node3D) -> Transform3D:
	var xf := node.transform
	var parent := node.get_parent()
	while parent != root and parent is Node3D:
		xf = parent.transform * xf
		parent = parent.get_parent()
	return xf


static func _dynamic(node: Node, root: Node) -> bool:
	while node != root:
		var extras: Dictionary = node.get_meta("extras", {})
		if extras.has("door_key") or extras.get("liftLeaf", false): return true
		node = node.get_parent()
	return false


static func _material_key(mat: Material) -> PackedByteArray:
	if not mat is BaseMaterial3D: return var_to_bytes(mat.get_instance_id() if mat != null else 0)
	var values: Array = [mat.get_class()]
	# Retain the names used by the live-light binding and Phong conversion.
	values.append(String(mat.resource_name).split(":")[0] if not String(mat.resource_name).begins_with("wdfz_live:") else mat.resource_name)
	for property: Dictionary in mat.get_property_list():
		var key: String = property.name
		if not int(property.usage) & PROPERTY_USAGE_STORAGE or key in ["resource_name", "resource_path", "resource_local_to_scene", "script"]: continue
		var value: Variant = mat.get(key)
		if value is Resource: value = value.get_instance_id()
		values.append([key, value])
	return var_to_bytes(values)


## A fixed tiny grid creates thousands of almost-empty draws outdoors. Split a spatial
## tree only when a batch has enough vertex work to justify another draw, or spans too
## much of the campus. Cheap isolated props can share a larger batch.
static func _split(group: Dictionary, batches: Array[Dictionary]) -> void:
	var places: Array = group.places
	var bounds := AABB((places[0] as Transform3D).origin,Vector3.ZERO)
	for place: Transform3D in places: bounds = bounds.expand(place.origin)
	var span := maxf(bounds.size.x,maxf(bounds.size.y,bounds.size.z))
	if places.size()<2 or span<=LOCAL_SPAN or (span<=MAX_SPAN and places.size()*int(group.triangles)<=TRIANGLES_PER_BATCH):
		batches.append(group)
		return
	var axis := bounds.get_longest_axis_index()
	var order := range(places.size())
	order.sort_custom(func(a: int,b: int)->bool:return (places[a] as Transform3D).origin[axis]<(places[b] as Transform3D).origin[axis])
	var left := group.duplicate()
	var right := group.duplicate()
	for part in [left,right]:
		part.places=[]
		part.colors=[]
	for i in order.size():
		var part := left if i<order.size()/2 else right
		part.places.append(places[order[i]])
		if group.colored: part.colors.append(group.colors[order[i]])
	_split(left,batches)
	_split(right,batches)


static func optimize(model: Node3D) -> Dictionary:
	if not enabled: return {}
	var meshes := {}
	var materials := {}
	var signatures := {}
	var groups := {}
	var removed: Array[MultiMeshInstance3D] = []
	var instances := 0
	for node: MultiMeshInstance3D in model.find_children("*", "MultiMeshInstance3D", true, false):
		var mm := node.multimesh
		if mm == null or mm.mesh == null or mm.instance_count==0 or _dynamic(node, model) or not node.visible or node.get_child_count() != 0: continue
		if node.material_override != null or node.material_overlay != null or mm.use_custom_data or mm.visible_instance_count >= 0: continue
		var mesh := mm.mesh
		if not signatures.has(mesh):
			var bytes := PackedByteArray()
			for s in mesh.get_surface_count():
				var mat := mesh.surface_get_material(s)
				var material_key := _digest(_material_key(mat))
				if not materials.has(material_key): materials[material_key] = mat
				# Resource substitution is limited to byte-identical stored material properties.
				if mesh is ArrayMesh: mesh.surface_set_material(s, materials[material_key])
				bytes.append_array(var_to_bytes([_primitive(mesh,s), material_key, mesh.surface_get_arrays(s)]))
			signatures[mesh] = _digest(bytes)
		var signature: String = signatures[mesh]
		if not meshes.has(signature): meshes[signature] = mesh
		var xf := _relative(node, model)
		var colors: PackedFloat32Array = node.get_meta("campus_colors", PackedFloat32Array())
		var key := "%s:%s:%s:%s" % [signature, node.layers, node.cast_shadow, mm.use_colors]
		if not groups.has(key):
			var triangles := 0
			for s in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(s)
				if not arrays.is_empty() and arrays[Mesh.ARRAY_VERTEX] != null:
					triangles += (arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX] != null and not arrays[Mesh.ARRAY_INDEX].is_empty() else arrays[Mesh.ARRAY_VERTEX].size())/3
			groups[key] = {"mesh": meshes[signature], "places": [], "colors": [], "layers": node.layers, "shadow": node.cast_shadow, "colored": mm.use_colors,"triangles":triangles}
		for i in mm.instance_count:
			var place := xf * CampusPreview.instance_transform(node, i)
			var group: Dictionary = groups[key]
			group.places.append(place)
			if mm.use_colors:
				group.colors.append(Color(colors[i*3], colors[i*3+1], colors[i*3+2]) if colors.size() >= (i+1)*3 else mm.get_instance_color(i))
			instances += 1
		removed.append(node)
	for node in removed: node.free()
	var batches: Array[Dictionary] = []
	for group: Dictionary in groups.values(): _split(group,batches)
	var index := 0
	for group: Dictionary in batches:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = group.colored
		mm.mesh = group.mesh
		mm.instance_count = group.places.size()
		var xf := PackedFloat32Array()
		var colors := PackedFloat32Array()
		for i in mm.instance_count:
			var place: Transform3D = group.places[i]
			mm.set_instance_transform(i, place)
			xf.append_array(PackedFloat32Array([place.basis.x.x, place.basis.x.y, place.basis.x.z, place.basis.y.x, place.basis.y.y, place.basis.y.z, place.basis.z.x, place.basis.z.y, place.basis.z.z, place.origin.x, place.origin.y, place.origin.z]))
			if mm.use_colors:
				var tint: Color = group.colors[i]
				mm.set_instance_color(i, tint)
				colors.append_array(PackedFloat32Array([tint.r, tint.g, tint.b]))
		var batch := MultiMeshInstance3D.new()
		batch.name = "SpatialBatch_%d" % index
		batch.layers = group.layers
		batch.cast_shadow = group.shadow
		batch.multimesh = mm
		batch.set_meta("campus_transforms", xf)
		batch.set_meta("campus_colors", colors)
		model.add_child(batch)
		index += 1
	var report := {"source_batches": removed.size(), "batches": batches.size(), "prototypes": meshes.size(), "instances": instances}
	model.set_meta("render_batches", report)
	return report


## Use only the actual opaque, stationary vertical triangles. Physics walls extend above
## windows and doors, so using their boxes as occluders would hide valid views. Movable leaves
## and all transparent/cutout materials are excluded. No inferred or oversized wall boxes.
static func add_occluder(model: Node3D) -> int:
	if not enabled: return 0
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for node: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if node.mesh == null or _dynamic(node, model) or not node.visible: continue
		var xf := _relative(node, model)
		for s in node.mesh.get_surface_count():
			var mat := node.mesh.surface_get_material(s) as BaseMaterial3D
			if mat == null or mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or mat.no_depth_test: continue
			if mat.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED or mat.proximity_fade_enabled or mat.distance_fade_mode != BaseMaterial3D.DISTANCE_FADE_DISABLED: continue
			if _primitive(node.mesh,s) != Mesh.PRIMITIVE_TRIANGLES: continue
			var arrays := node.mesh.surface_get_arrays(s)
			if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null: continue
			var source: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var faces: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			for i in range(0, faces.size() if not faces.is_empty() else source.size(), 3):
				var a := xf * source[faces[i] if not faces.is_empty() else i]
				var b := xf * source[faces[i+1] if not faces.is_empty() else i+1]
				var c := xf * source[faces[i+2] if not faces.is_empty() else i+2]
				var normal := (b-a).cross(c-a)
				if normal.length_squared() < 1.0 or absf(normal.y) > normal.length() * .02: continue
				var start := vertices.size()
				vertices.append_array(PackedVector3Array([a,b,c]))
				indices.append_array(PackedInt32Array([start,start+1,start+2]))
	if indices.is_empty(): return 0
	var resource := ArrayOccluder3D.new()
	resource.set_arrays(vertices, indices)
	var occluder := OccluderInstance3D.new()
	model.add_child(occluder)
	occluder.name = "OpaqueWallOccluder"
	occluder.occluder = resource
	return indices.size()/3
