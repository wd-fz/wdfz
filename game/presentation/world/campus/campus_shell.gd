class_name CampusShell
extends RefCounted
## Partition the old outdoor facades into storeys. A storey is a cheap distant
## proxy, never an additional wall drawn over the occupied interior.

const ROOFLINE := "PermanentRooflines"
const CROSSES_BOUNDARY := "*"


static func partition(model: Node3D, space: CampusSpace) -> Dictionary:
	for opening in space.garage_openings():
		_carve_ground(model, opening)
	for opening: AABB in space.bridge_volumes() + space.bridge_openings(): carve_box(model, opening)
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
	var batches := {}
	var crown := Node3D.new()
	crown.name = ROOFLINE
	groups[ROOFLINE] = crown
	for node: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if node.mesh == null: continue
		var xf := _transform(node, model)
		var whole := _box_owner(xf*node.mesh.get_aabb(), footprints, space)
		if whole == "": continue
		var parts := _partition_faces(node.mesh, xf, footprints, space) if whole == CROSSES_BOUNDARY else {whole:node.mesh}
		for id: String in parts:
			if id != "": _place_parts(parts[id], xf, id, groups, storeys, space, batches)
		node.mesh = parts.get("")
	for node: MultiMeshInstance3D in model.find_children("*", "MultiMeshInstance3D", true, false):
		var xf := _transform(node, model)
		var bins := {}
		var colors: PackedFloat32Array = node.get_meta("campus_colors", PackedFloat32Array())
		for i in node.multimesh.instance_count:
			var it := CampusPreview.instance_transform(node, i)
			if it.origin.y < -9999: continue
			var box := (xf * it) * node.multimesh.mesh.get_aabb()
			var owner := _box_owner(box, footprints, space)
			var tint := Color(colors[i*3],colors[i*3+1],colors[i*3+2]) if colors.size() >= (i+1)*3 else Color.WHITE
			if owner == CROSSES_BOUNDARY:
				# A single instance can span a shaft, the main facade and open space.
				var split := _partition_faces(node.multimesh.mesh, xf*it, footprints, space)
				if split.size()==1: owner=split.keys()[0]
				else:
					for id: String in split:
						_place_parts(split[id], xf*it, id, groups, storeys, space, batches, tint, model)
					continue
			var id := owner
			if storeys.has(id):
				var band := _whole_band(box, id, storeys, space)
				if band == CROSSES_BOUNDARY:
					_place_parts(node.multimesh.mesh, xf*it, id, groups, storeys, space, batches, tint)
					continue
				id = band
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
	for parent: Node3D in batches:
		for cell: Dictionary in batches[parent].values():
			var merged:=ArrayMesh.new()
			for surface: SurfaceTool in cell.values(): surface.commit(merged)
			var node:=MeshInstance3D.new()
			node.mesh=merged
			parent.add_child(node)
	for id: String in groups.keys():
		var group: Node3D = groups[id]
		if group.get_child_count() == 0:
			group.free()
			groups.erase(id)
		else: model.add_child(group)
	groups.erase(ROOFLINE)
	return groups


## A footprint must contain the whole primitive before it may disappear with that
## room. Large facade triangles routinely extend far beyond the elevator or stair.
static func _box_owner(box: AABB, footprints: Array[Dictionary], space: CampusSpace) -> String:
	if box.end.y < .15: return ""
	var rect := Rect2(box.position.x,box.position.z,box.size.x,box.size.z)
	for f: Dictionary in footprints:
		var area: Rect2 = f.rect
		if not area.intersects(rect,true): continue
		return _storey(box.get_center().y,f.floors,space) if area.encloses(rect) else CROSSES_BOUNDARY
	return ""


static func _storey(y: float, floors: Array, space: CampusSpace) -> String:
	var chosen: String = floors[0]
	for id: String in floors:
		if space.frame(id).origin.y <= y + .005: chosen = id
	return chosen


static func _partition_faces(mesh: Mesh, xf: Transform3D, footprints: Array[Dictionary], space: CampusSpace) -> Dictionary:
	var parts := {}
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty(): indices = PackedInt32Array(range(v.size()))
		var bins := {}
		for i in range(0,indices.size(),3):
			var face := PackedInt32Array([indices[i],indices[i+1],indices[i+2]])
			var a := xf*v[face[0]]
			var bounds := AABB(a,Vector3.ZERO).expand(xf*v[face[1]]).expand(xf*v[face[2]])
			var id := _box_owner(bounds,footprints,space)
			if id == CROSSES_BOUNDARY: _cut_face(arrays,face,xf,footprints,0,bins,space)
			else:
				if not bins.has(id): bins[id]=PackedInt32Array()
				bins[id].append_array(face)
		for id: String in bins:
			if not parts.has(id): parts[id]=ArrayMesh.new()
			var part: ArrayMesh=parts[id]
			part.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,_compact(arrays,bins[id]))
			part.surface_set_material(part.get_surface_count()-1,mesh.surface_get_material(s))
	return parts


static func _emit_face(face: PackedInt32Array, id: String, bins: Dictionary) -> void:
	if not bins.has(id): bins[id]=PackedInt32Array()
	for j in range(1,face.size()-1):
		bins[id].append_array(PackedInt32Array([face[0],face[j],face[j+1]]))


static func _cut_face(arrays: Array, face: PackedInt32Array, xf: Transform3D, footprints: Array[Dictionary], start: int, bins: Dictionary, space: CampusSpace) -> void:
	var bounds:=AABB(xf*(arrays[Mesh.ARRAY_VERTEX][face[0]] as Vector3),Vector3.ZERO)
	for i in face: bounds=bounds.expand(xf*(arrays[Mesh.ARRAY_VERTEX][i] as Vector3))
	var rect:=Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z)
	for k in range(start,footprints.size()):
		var f:=footprints[k]
		var area: Rect2=f.rect
		if not area.intersects(rect,true): continue
		if not area.encloses(rect):
			for plane: Plane in [Plane(Vector3.RIGHT,area.position.x), Plane(Vector3.LEFT,-area.end.x),
					Plane(Vector3.BACK,area.position.y), Plane(Vector3.FORWARD,-area.end.y)]:
				var local:=xf.affine_inverse()*plane
				var sides := _split_polygon(face, arrays, local)
				var inside: PackedInt32Array = sides[0]
				var outside: PackedInt32Array = sides[1]
				if outside.size()>=3 and outside!=inside: _cut_face(arrays,outside,xf,footprints,k+1,bins,space)
				if inside.size()<3: return
				face=inside
		_emit_face(face,_storey(bounds.get_center().y,f.floors,space),bins)
		return
	_emit_face(face,"",bins)


## Vertices on the cut serve both halves. Each crossing creates one shared
## vertex with interpolated UVs, normal and colour.
static func _split_polygon(face: PackedInt32Array, arrays: Array, plane: Plane) -> Array[PackedInt32Array]:
	var inside := PackedInt32Array()
	var outside := PackedInt32Array()
	for j in face.size():
		var a := face[j]
		var b := face[(j+1) % face.size()]
		var da := plane.distance_to(arrays[Mesh.ARRAY_VERTEX][a])
		var db := plane.distance_to(arrays[Mesh.ARRAY_VERTEX][b])
		if absf(da) <= CampusPreview.EPS: da = 0
		if absf(db) <= CampusPreview.EPS: db = 0
		if da >= 0: inside.append(a)
		if da <= 0: outside.append(a)
		if da*db < 0:
			var edge := CampusPreview._intersection(arrays, a, b, da/(da-db))
			inside.append(edge)
			outside.append(edge)
	return [inside, outside]


static func _place_parts(mesh: Mesh, xf: Transform3D, id: String, groups: Dictionary, storeys: Dictionary, space: CampusSpace, batches: Dictionary, tint: Color = Color.WHITE, outdoor: Node3D = null) -> void:
	var parts := _floor_parts(mesh,xf,id,storeys,space)
	for part_id: String in parts:
		var section: Mesh = parts[part_id] if tint==Color.WHITE else CampusPreview.clip_mesh(parts[part_id],Plane(Vector3.UP,-10000),tint)
		var parent: Node3D = outdoor if part_id=="" else groups[part_id]
		# Keep alpha sorting and mirrored instances' winding in their local frame.
		var batch := xf.basis.determinant() > .000001
		for i in section.get_surface_count():
			var mat := section.surface_get_material(i) as BaseMaterial3D
			if mat == null or mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: batch=false
		if not batch:
			var node:=MeshInstance3D.new()
			node.mesh=section
			node.transform=xf
			parent.add_child(node)
			continue
		var center:=xf*section.get_aabb().get_center()
		var key:=Vector2i(floori(center.x/32),floori(center.z/32))
		if not batches.has(parent): batches[parent]={}
		if not batches[parent].has(key): batches[parent][key]={}
		var cell: Dictionary=batches[parent][key]
		for i in section.get_surface_count():
			var material:=section.surface_get_material(i)
			var group: String = "%d/%d" % [material.get_instance_id(),section.surface_get_format(i)]
			if not cell.has(group):
				var surface:=SurfaceTool.new()
				surface.begin(Mesh.PRIMITIVE_TRIANGLES)
				surface.set_material(material)
				cell[group]=surface
			(cell[group] as SurfaceTool).append_from(section,i,xf)


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


## Storeys can be taller than the exported interior wall (3 m). The band between
## floors and the original upper roof still belong to the exterior at close range.
static func _bands(id: String, storeys: Dictionary, space: CampusSpace) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	var floors: Array=storeys.get(id,[])
	for i in floors.size():
		var floor_id: String=floors[i]
		var base:=space.frame(floor_id).origin.y
		var low:=base if i>0 else -INF
		var high:=space.frame(floors[i+1]).origin.y if i+1<floors.size() else INF
		var ceiling:=high
		if floor_id not in ["garage1","teach6","link1","link2"]:
			ceiling=minf(high,base+(9.8 if floor_id=="bell1" else 3.0))
		result.append({"id":floor_id,"low":low,"high":ceiling})
		if ceiling < high: result.append({"id":ROOFLINE,"low":ceiling,"high":high})
	return result


static func _whole_band(bounds: AABB, id: String, storeys: Dictionary, space: CampusSpace) -> String:
	for band: Dictionary in _bands(id,storeys,space):
		if bounds.position.y >= band.low-CampusPreview.EPS and bounds.end.y < band.high-CampusPreview.EPS: return band.id
	return CROSSES_BOUNDARY


static func _floor_parts(mesh: Mesh, xf: Transform3D, id: String, storeys: Dictionary, space: CampusSpace) -> Dictionary:
	if not storeys.has(id): return {id:mesh}
	var bounds:=xf*mesh.get_aabb()
	var whole:=_whole_band(bounds,id,storeys,space)
	if whole!= CROSSES_BOUNDARY: return {whole:mesh}
	var result: Dictionary={}
	for band: Dictionary in _bands(id,storeys,space):
		if bounds.end.y<band.low or bounds.position.y>=band.high: continue
		var section:=mesh
		if bounds.position.y<band.low: section=CampusPreview.clip_mesh(section,xf.affine_inverse()*Plane(Vector3.UP,band.low))
		if bounds.end.y>band.high: section=CampusPreview.clip_mesh(section,xf.affine_inverse()*Plane(Vector3.DOWN,-band.high))
		if section.get_surface_count()==0: continue
		if not result.has(band.id): result[band.id]=ArrayMesh.new()
		var compact: ArrayMesh=result[band.id]
		for s in section.get_surface_count():
			var arrays:=section.surface_get_arrays(s)
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array(range(arrays[Mesh.ARRAY_VERTEX].size()))
			if is_finite(band.high) and bounds.end.y>=band.high-.00001:
				var top_plane:=xf.affine_inverse()*Plane(Vector3.UP,band.high)
				var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
				var lower:=PackedInt32Array()
				for i in range(0,indices.size(),3):
					# Horizontal faces on a split plane belong to the upper band once.
					if top_plane.has_point(vertices[indices[i]],.00001) and top_plane.has_point(vertices[indices[i+1]],.00001) and top_plane.has_point(vertices[indices[i+2]],.00001): continue
					lower.append_array(PackedInt32Array([indices[i],indices[i+1],indices[i+2]]))
				indices=lower
			if indices.is_empty(): continue
			compact.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,_compact(arrays,indices))
			compact.surface_set_material(compact.get_surface_count()-1,section.surface_get_material(s))
	for key: String in result.keys():
		if (result[key] as Mesh).get_surface_count()==0: result.erase(key)
	return result
