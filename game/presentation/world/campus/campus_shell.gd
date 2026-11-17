class_name CampusShell
extends RefCounted
## Partition the old outdoor facades into storeys. A storey is a cheap distant
## proxy, never an additional wall drawn over the occupied interior.

static func partition(model: Node3D, space: CampusSpace) -> Dictionary:
	_carve_ground(model, space.garage_hole())
	for bridge: AABB in space.bridge_volumes(): carve_box(model,bridge)
	var groups := {}
	var footprints: Array[Dictionary] = []
	var storeys := {}
	for object: Dictionary in space.outside.get("objects", []):
		var floors: Array[String] = []
		for id: String in space.frames:
			if id == "out" or id.begins_with("stair_") or id.begins_with("lift_"): continue
			if space.rooms[id].get("host") == object["id"]: floors.append(id)
		if floors.is_empty(): continue
		floors.sort_custom(func(a: String, b: String) -> bool: return space.frame(a).origin.y < space.frame(b).origin.y)
		var rect := Rect2(Vector2(object["x"], object["y"]), Vector2(object["w"], object["h"]))
		rect.position *= 2.0 / 9.0
		rect.size *= 2.0 / 9.0
		footprints.append({"rect": rect.grow(0.8), "floors": floors})
		for id: String in floors:
			storeys[id] = floors
			var group := Node3D.new()
			group.name = "Facade_" + id
			groups[id] = group
	for stair: Dictionary in space.campus.get("stair_layout", []):
		var id := String(stair.id)
		var group := Node3D.new()
		group.name = "Facade_" + id
		groups[id] = group
		footprints.push_front({"rect": space.stair_bounds(id).grow(.15), "floors": [id]})
	for id: String in ["lift_teach", "lift_lab"]:
		var group := Node3D.new()
		group.name = "Facade_" + id
		groups[id] = group
		footprints.push_front({"rect": space.lift_bounds(id).grow(.5), "floors": [id]})
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	for node: MeshInstance3D in meshes:
		if node.mesh == null: continue
		var xf := _transform(node, model)
		var split := {}
		for s in node.mesh.get_surface_count():
			var arrays := node.mesh.surface_get_arrays(s)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if indices.is_empty():
				for i in vertices.size(): indices.append(i)
			var bins := {}
			for i in range(0, indices.size(), 3):
				var a := xf * vertices[indices[i]]
				var b := xf * vertices[indices[i + 1]]
				var c := xf * vertices[indices[i + 2]]
				var id := _region((a + b + c) / 3.0, maxf(a.y, maxf(b.y, c.y)), footprints, space)
				if not bins.has(id): bins[id] = PackedInt32Array()
				bins[id].append_array(PackedInt32Array([indices[i], indices[i + 1], indices[i + 2]]))
			for id: String in bins:
				if not split.has(id): split[id] = ArrayMesh.new()
				var part: ArrayMesh = split[id]
				var copy := _compact(arrays, bins[id])
				part.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, copy)
				part.surface_set_material(part.get_surface_count() - 1, node.mesh.surface_get_material(s))
		for id: String in split:
			if id == "": continue
			var pieces := _floor_parts(split[id], xf, id, storeys, space)
			for floor_id: String in pieces:
				var copy := MeshInstance3D.new()
				copy.mesh = pieces[floor_id]
				copy.transform = xf
				groups[floor_id].add_child(copy)
		node.mesh = split.get("")
	for node: MultiMeshInstance3D in model.find_children("*", "MultiMeshInstance3D", true, false):
		var xf := _transform(node, model)
		var bins := {}
		var colors: PackedFloat32Array = node.get_meta("campus_colors", PackedFloat32Array())
		for i in node.multimesh.instance_count:
			var it := CampusPreview.instance_transform(node, i)
			if it.origin.y < -9999: continue
			var box := (xf * it) * node.multimesh.mesh.get_aabb()
			var id := _region(box.get_center(), box.end.y, footprints, space)
			if id != "" and storeys.has(id) and box.size.y > space.floor_height(id):
				var pieces := _floor_parts(node.multimesh.mesh, xf * it, id, storeys, space)
				for floor_id: String in pieces:
					var copy := MeshInstance3D.new()
					var mesh: Mesh = pieces[floor_id]
					if colors.size() >= (i+1)*3:
						mesh = CampusPreview.clip_mesh(mesh, Plane(Vector3.UP,-10000), Color(colors[i*3],colors[i*3+1],colors[i*3+2]))
					copy.mesh = mesh
					copy.transform = xf * it
					groups[floor_id].add_child(copy)
				continue
			if not bins.has(id): bins[id] = []
			bins[id].append(i)
		for id: String in bins:
			var part := MultiMeshInstance3D.new()
			part.transform = xf
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = node.multimesh.use_colors
			mm.mesh = node.multimesh.mesh
			mm.instance_count = bins[id].size()
			var transforms := PackedFloat32Array()
			var tints := PackedFloat32Array()
			for k in bins[id].size():
				var i: int = bins[id][k]
				var it := CampusPreview.instance_transform(node, i)
				mm.set_instance_transform(k, it)
				transforms.append_array(PackedFloat32Array([it.basis.x.x,it.basis.x.y,it.basis.x.z,it.basis.y.x,it.basis.y.y,it.basis.y.z,it.basis.z.x,it.basis.z.y,it.basis.z.z,it.origin.x,it.origin.y,it.origin.z]))
				if mm.use_colors:
					var tint := Color(colors[i * 3], colors[i * 3 + 1], colors[i * 3 + 2]) if colors.size() >= (i + 1) * 3 else Color.WHITE
					mm.set_instance_color(k, tint)
					tints.append_array(PackedFloat32Array([tint.r,tint.g,tint.b]))
			part.multimesh = mm
			part.set_meta("campus_transforms", transforms)
			part.set_meta("campus_colors", tints)
			(groups[id] if id != "" else model).add_child(part)
		for child: Node3D in node.get_children():
			child.reparent(model, false)
			child.transform = xf * child.transform
		node.get_parent().remove_child(node)
		node.free()
	for group: Node3D in groups.values(): model.add_child(group)
	return groups


static func _region(p: Vector3, top: float, footprints: Array[Dictionary], space: CampusSpace) -> String:
	if top < 0.15: return "" # Ground remains part of the outdoor world.
	for f: Dictionary in footprints:
		if not (f["rect"] as Rect2).has_point(Vector2(p.x, p.z)): continue
		var chosen: String = f["floors"][0]
		for id: String in f["floors"]:
			if space.frame(id).origin.y <= p.y + 0.05: chosen = id
		return chosen
	return ""


static func _transform(node: Node3D, root: Node3D) -> Transform3D:
	var xf := node.transform
	var parent := node.get_parent()
	while parent != root:
		if parent is Node3D: xf = parent.transform * xf
		parent = parent.get_parent()
	return xf


static func _carve_ground(model: Node3D, rect: Rect2) -> void:
	carve_box(model,AABB(Vector3(rect.position.x, -0.6, rect.position.y), Vector3(rect.size.x, 0.8, rect.size.y)))


static func carve_box(model: Node3D, hole: AABB) -> void:
	for node: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if node.mesh == null: continue
		var xf := _transform(node, model)
		if (xf * node.mesh.get_aabb()).intersects(hole): node.mesh = _subtract(node.mesh, xf, hole)
	for node: MultiMeshInstance3D in model.find_children("*", "MultiMeshInstance3D", true, false):
		var parent := _transform(node, model)
		var xf: PackedFloat32Array = node.get_meta("campus_transforms", PackedFloat32Array())
		var colors: PackedFloat32Array = node.get_meta("campus_colors", PackedFloat32Array())
		for i in node.multimesh.instance_count:
			var it := CampusPreview.instance_transform(node, i)
			if not ((parent * it) * node.multimesh.mesh.get_aabb()).intersects(hole): continue
			var copy := MeshInstance3D.new()
			copy.mesh = _subtract(node.multimesh.mesh, parent * it, hole)
			copy.transform = it
			if node.multimesh.use_colors and colors.size() >= (i + 1) * 3:
				copy.mesh = CampusPreview.clip_mesh(copy.mesh, Plane(Vector3.UP, -10000), Color(colors[i*3], colors[i*3+1], colors[i*3+2]))
			node.add_child(copy)
			var empty := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.000001), Vector3(0,-10000,0))
			node.multimesh.set_instance_transform(i, empty)
			if xf.size() >= (i+1)*12:
				for k in 12: xf[i*12+k] = 0.0
				xf[i*12] = 0.000001
				xf[i*12+4] = 0.000001
				xf[i*12+8] = 0.000001
				xf[i*12+10] = -10000
		node.set_meta("campus_transforms", xf)
		CampusPreview._clip_instances(node, Plane(Vector3.UP,-9999))


static func _subtract(mesh: Mesh, xf: Transform3D, box: AABB) -> ArrayMesh:
	var rest := mesh
	var result := ArrayMesh.new()
	for plane: Plane in [Plane(Vector3.LEFT,-box.position.x), Plane(Vector3.RIGHT,box.end.x),
		Plane(Vector3.DOWN,-box.position.y), Plane(Vector3.UP,box.end.y),
		Plane(Vector3.FORWARD,-box.position.z), Plane(Vector3.BACK,box.end.z)]:
		var local := xf.affine_inverse() * plane
		var part := CampusPreview.clip_mesh(rest, local)
		for s in part.get_surface_count():
			var arrays := part.surface_get_arrays(s)
			result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _compact(arrays, arrays[Mesh.ARRAY_INDEX]))
			result.surface_set_material(result.get_surface_count()-1, part.surface_get_material(s))
		rest = CampusPreview.clip_mesh(rest, Plane(-local.normal,-local.d))
		if rest.get_surface_count() == 0: break
	return result


static func _compact(arrays: Array, indices: PackedInt32Array) -> Array:
	var unique := PackedInt32Array()
	var mapped := PackedInt32Array()
	var remap := {}
	for i in indices:
		if not remap.has(i):
			remap[i] = unique.size()
			unique.append(i)
		mapped.append(remap[i])
	var result := []
	result.resize(Mesh.ARRAY_MAX)
	for slot: int in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2,Mesh.ARRAY_TANGENT]:
		if arrays[slot] == null: continue
		var data: Variant = arrays[slot].duplicate()
		data.resize(0)
		var stride := 4 if slot == Mesh.ARRAY_TANGENT else 1
		for i in unique:
			for k in stride: data.append(arrays[slot][i * stride + k])
		result[slot] = data
	result[Mesh.ARRAY_INDEX] = mapped
	return result


## Large facade triangles/prototypes span several storeys. Centroid assignment
## alone leaves a whole-building wall in front of a visible ground-floor room.
static func _floor_parts(mesh: Mesh, xf: Transform3D, id: String, storeys: Dictionary, space: CampusSpace) -> Dictionary:
	if not storeys.has(id) or storeys[id].size() < 2: return {id:mesh}
	var result := {}
	var floors: Array = storeys[id]
	var bounds := xf * mesh.get_aabb()
	for i in floors.size():
		var low := space.frame(floors[i]).origin.y if i > 0 else bounds.position.y - 1.0
		var high := space.frame(floors[i+1]).origin.y if i+1 < floors.size() else bounds.end.y + 1.0
		if bounds.end.y < low or bounds.position.y >= high: continue
		var part := CampusPreview.clip_mesh(mesh, xf.affine_inverse() * Plane(Vector3.UP,low))
		part = CampusPreview.clip_mesh(part, xf.affine_inverse() * Plane(Vector3.DOWN,-high))
		if part.get_surface_count() == 0: continue
		var compact := ArrayMesh.new()
		for surface in part.get_surface_count():
			var arrays := part.surface_get_arrays(surface)
			compact.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,_compact(arrays,arrays[Mesh.ARRAY_INDEX]))
			compact.surface_set_material(compact.get_surface_count()-1,part.surface_get_material(surface))
		result[floors[i]] = compact
	return result
