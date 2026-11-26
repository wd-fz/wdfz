class_name CampusShell
extends RefCounted
## Partition the old outdoor facades into storeys. A storey is a cheap distant
## proxy, never an additional wall drawn over the occupied interior.

const ROOFLINE := "PermanentRooflines"
const CROSSES_BOUNDARY := "*"
const FOOTPRINT_CELL := 32.0


static func partition(model: Node3D, space: CampusSpace) -> Dictionary:
	for opening in space.garage_openings():
		_carve_ground(model, opening)
	for opening: AABB in space.bridge_volumes() + space.bridge_openings(): carve_box(model, opening)
	var groups := {}
	var footprints: Array[Dictionary] = []
	var bands_by_floor := {}
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
		var bands := _bands(floors, space)
		for id: String in floors:
			bands_by_floor[id] = bands
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
	var footprint_grid := _index_footprints(footprints)
	var batches := {}
	var crown := Node3D.new()
	crown.name = ROOFLINE
	groups[ROOFLINE] = crown
	for node: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if node.mesh == null: continue
		var xf := _transform(node, model)
		var bounds := xf * node.mesh.get_aabb()
		var whole := _box_owner(bounds, _candidates(bounds, footprints, footprint_grid), space)
		if whole == "": continue
		var parts := _partition_faces(node.mesh, xf, footprints, space, footprint_grid) if whole == CROSSES_BOUNDARY else {whole:node.mesh}
		for id: String in parts:
			if id != "": _place_parts(parts[id], xf, id, groups, bands_by_floor, batches)
		node.mesh = parts.get("")
	for node: MultiMeshInstance3D in model.find_children("*", "MultiMeshInstance3D", true, false):
		var xf := _transform(node, model)
		var bins := {}
		var colors: PackedFloat32Array = node.get_meta("campus_colors", PackedFloat32Array())
		for i in node.multimesh.instance_count:
			var it := CampusPreview.instance_transform(node, i)
			if it.origin.y < -9999: continue
			var box := (xf * it) * node.multimesh.mesh.get_aabb()
			var owner := _box_owner(box, _candidates(box, footprints, footprint_grid), space)
			var tint := Color(colors[i*3],colors[i*3+1],colors[i*3+2]) if colors.size() >= (i+1)*3 else Color.WHITE
			if owner == CROSSES_BOUNDARY:
				# A single instance can span a shaft, the main facade and open space.
				var split := _partition_faces(node.multimesh.mesh, xf*it, footprints, space, footprint_grid)
				if split.size()==1: owner=split.keys()[0]
				else:
					for id: String in split:
						_place_parts(split[id], xf*it, id, groups, bands_by_floor, batches, tint, model)
					continue
			var id := owner
			if bands_by_floor.has(id):
				var band := _whole_band(box, bands_by_floor[id])
				if band == CROSSES_BOUNDARY:
					_place_parts(node.multimesh.mesh, xf*it, id, groups, bands_by_floor, batches, tint)
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


## A triangle or prop inside a single grid cell can only touch the footprints
## indexed there. Keep their original order: lift and stair apertures take priority.
static func _index_footprints(footprints: Array[Dictionary]) -> Dictionary:
	var grid := {}
	for footprint in footprints:
		var rect: Rect2 = footprint.rect
		for z in range(floori(rect.position.y / FOOTPRINT_CELL), floori(rect.end.y / FOOTPRINT_CELL) + 1):
			for x in range(floori(rect.position.x / FOOTPRINT_CELL), floori(rect.end.x / FOOTPRINT_CELL) + 1):
				var cell := Vector2i(x, z)
				if not grid.has(cell):
					var occupants: Array[Dictionary] = []
					grid[cell] = occupants
				grid[cell].append(footprint)
	return grid


static func _candidates(bounds: AABB, footprints: Array[Dictionary], grid: Dictionary) -> Array[Dictionary]:
	var start := Vector2i(floori(bounds.position.x / FOOTPRINT_CELL), floori(bounds.position.z / FOOTPRINT_CELL))
	var end := Vector2i(floori(bounds.end.x / FOOTPRINT_CELL), floori(bounds.end.z / FOOTPRINT_CELL))
	if start != end: return footprints
	if grid.has(start): return grid[start]
	return []


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


static func _partition_faces(mesh: Mesh, xf: Transform3D, footprints: Array[Dictionary], space: CampusSpace, grid: Dictionary = {}) -> Dictionary:
	if grid.is_empty(): grid = _index_footprints(footprints)
	var parts := {}
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = xf * (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty(): indices = PackedInt32Array(range(vertices.size()))
		var bins := {}
		for i in range(0,indices.size(),3):
			var a := indices[i]
			var b := indices[i+1]
			var c := indices[i+2]
			var bounds := AABB(vertices[a],Vector3.ZERO).expand(vertices[b]).expand(vertices[c])
			var candidates := _candidates(bounds, footprints, grid)
			var id := _box_owner(bounds, candidates, space)
			if id == CROSSES_BOUNDARY:
				_cut_face(arrays,PackedInt32Array([a,b,c]),xf,candidates,0,bins,space)
			else:
				if not bins.has(id): bins[id]=PackedInt32Array()
				bins[id].append(a)
				bins[id].append(b)
				bins[id].append(c)
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


static func _place_parts(mesh: Mesh, xf: Transform3D, id: String, groups: Dictionary, bands_by_floor: Dictionary, batches: Dictionary, tint: Color = Color.WHITE, outdoor: Node3D = null) -> void:
	var parts := _floor_parts(mesh, xf, id, bands_by_floor.get(id, []))
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
		var source := node.multimesh
		var colors: PackedFloat32Array = node.get_meta("campus_colors", PackedFloat32Array())
		var removed := PackedInt32Array()
		var bounds := source.mesh.get_aabb()
		for i in source.instance_count:
			var it := CampusPreview.instance_transform(node, i)
			if not ((parent * it) * bounds).intersects(hole): continue
			removed.append(i)
			var copy := MeshInstance3D.new()
			copy.mesh = _subtract(source.mesh, parent * it, hole)
			copy.transform = it
			if source.use_colors and colors.size() >= (i + 1) * 3:
				copy.mesh = CampusPreview.clip_mesh(copy.mesh, Plane(Vector3.UP, -10000), Color(colors[i*3], colors[i*3+1], colors[i*3+2]))
			node.add_child(copy)
		if removed.is_empty(): continue
		var kept: Array[Transform3D] = []
		var tints: Array[Color] = []
		var next_removed := 0
		for i in source.instance_count:
			if next_removed < removed.size() and i == removed[next_removed]:
				next_removed += 1
				continue
			kept.append(CampusPreview.instance_transform(node, i))
			if source.use_colors:
				tints.append(Color(colors[i*3],colors[i*3+1],colors[i*3+2]) if colors.size() >= (i+1)*3 else source.get_instance_color(i))
		CampusPreview.set_instances(node, kept, tints)


static func _subtract(mesh: Mesh, xf: Transform3D, box: AABB) -> ArrayMesh:
	var result := ArrayMesh.new()
	var surfaces: Array[Array] = []
	var remaining: Array[PackedInt32Array] = []
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		surfaces.append(arrays)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty(): indices = PackedInt32Array(range(arrays[Mesh.ARRAY_VERTEX].size()))
		remaining.append(indices)
	var inverse := xf.affine_inverse()
	for plane: Plane in [Plane(Vector3.LEFT,-box.position.x), Plane(Vector3.RIGHT,box.end.x),
		Plane(Vector3.DOWN,-box.position.y), Plane(Vector3.UP,box.end.y),
		Plane(Vector3.FORWARD,-box.position.z), Plane(Vector3.BACK,box.end.z)]:
		var local := inverse * plane
		for s in surfaces.size():
			var indices := remaining[s]
			if indices.is_empty(): continue
			var arrays := surfaces[s]
			var outside := CampusPreview.clip_triangles(arrays, indices, local)
			if not outside.is_empty():
				result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _compact(arrays, outside))
				result.surface_set_material(result.get_surface_count() - 1, mesh.surface_get_material(s))
			remaining[s] = CampusPreview.clip_triangles(arrays, indices, Plane(-local.normal,-local.d))
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
		var source: Variant = arrays[slot]
		var data: Variant = source.slice(0, 0)
		if slot == Mesh.ARRAY_TANGENT:
			for i in unique:
				var offset := i * 4
				for k in 4: data.append(source[offset + k])
		else:
			for i in unique: data.append(source[i])
		result[slot] = data
	result[Mesh.ARRAY_INDEX] = mapped
	return result


## Storeys can be taller than the exported interior wall (3 m). The band between
## floors and the original upper roof still belong to the exterior at close range.
static func _bands(floors: Array, space: CampusSpace) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
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


static func _whole_band(bounds: AABB, bands: Array) -> String:
	for band: Dictionary in bands:
		if bounds.position.y >= band.low-CampusPreview.EPS and bounds.end.y < band.high-CampusPreview.EPS: return band.id
	return CROSSES_BOUNDARY


static func _floor_parts(mesh: Mesh, xf: Transform3D, id: String, bands: Array) -> Dictionary:
	if bands.is_empty(): return {id:mesh}
	var bounds:=xf*mesh.get_aabb()
	var whole:=_whole_band(bounds, bands)
	if whole!= CROSSES_BOUNDARY: return {whole:mesh}
	var result := {}
	var surfaces: Array[Array] = []
	for s in mesh.get_surface_count():
		surfaces.append(mesh.surface_get_arrays(s))
	var inverse := xf.affine_inverse()
	for band: Dictionary in bands:
		if bounds.end.y < band.low or bounds.position.y >= band.high: continue
		var cut_bottom: bool = bounds.position.y < band.low
		var cut_top: bool = bounds.end.y > band.high
		var touches_top: bool = is_finite(band.high) and bounds.end.y >= band.high - CampusPreview.EPS
		var bottom_plane := Plane()
		var top_plane := Plane()
		if cut_bottom: bottom_plane = inverse * Plane(Vector3.UP, band.low)
		if cut_top or touches_top: top_plane = inverse * Plane(Vector3.UP, band.high)
		for s in surfaces.size():
			# Cuts append interpolated vertices. Each band owns its arrays while
			# fully retained attributes share the source's packed buffers.
			var arrays := surfaces[s].duplicate()
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if indices.is_empty(): indices = PackedInt32Array(range(arrays[Mesh.ARRAY_VERTEX].size()))
			if cut_bottom: indices = CampusPreview.clip_triangles(arrays, indices, bottom_plane)
			if cut_top: indices = CampusPreview.clip_triangles(arrays, indices, Plane(-top_plane.normal, -top_plane.d))
			if touches_top:
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var lower := PackedInt32Array()
				for i in range(0, indices.size(), 3):
					# Horizontal faces on a split plane belong to the upper band once.
					if top_plane.has_point(vertices[indices[i]], CampusPreview.EPS) and top_plane.has_point(vertices[indices[i+1]], CampusPreview.EPS) and top_plane.has_point(vertices[indices[i+2]], CampusPreview.EPS): continue
					lower.append(indices[i])
					lower.append(indices[i+1])
					lower.append(indices[i+2])
				indices = lower
			if indices.is_empty(): continue
			if not result.has(band.id): result[band.id] = ArrayMesh.new()
			var section: ArrayMesh = result[band.id]
			section.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _compact(arrays, indices))
			section.surface_set_material(section.get_surface_count() - 1, mesh.surface_get_material(s))
	return result
