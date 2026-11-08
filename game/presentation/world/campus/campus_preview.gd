class_name CampusPreview
extends RefCounted
## A neighbouring scene is visible only beyond its connecting threshold. Its building shell
## must never cover walkable space in the current scene. Keep the original materials/UVs and
## trim a private mesh instance; neither the exported assets nor gameplay collision changes.

const EPS := 0.00001


static func clip(model: Node3D, plane: Plane) -> void:
	_clip_node(model, Transform3D.IDENTITY, plane)


static func _clip_node(node: Node3D, parent: Transform3D, plane: Plane) -> void:
	var transform := parent * node.transform
	var children := node.get_children()
	if node is MeshInstance3D and node.mesh != null:
		var local := transform.affine_inverse() * plane
		var side := _side(node.mesh.get_aabb(), local)
		if side < 0:
			node.mesh = null # Door-state updates may show this node again; discarded geometry stays gone.
			node.hide()
		elif side == 0:
			node.mesh = clip_mesh(node.mesh, local)
	elif node is MultiMeshInstance3D and node.multimesh != null:
		_clip_instances(node, transform.affine_inverse() * plane)
	for child: Node in children:
		if child is Node3D:
			_clip_node(child, transform, plane)


static func _side(bounds: AABB, plane: Plane) -> int:
	var front := false
	var back := false
	for i in 8:
		var d := plane.distance_to(bounds.get_endpoint(i))
		front = front or d >= -EPS
		back = back or d < -EPS
	return 0 if front and back else (1 if front else -1)


## Use the exported transforms as well as MultiMesh: the headless dummy rendering server
## does not retain instance transforms, while geometry verification must use the same data.
static func instance_transform(node: MultiMeshInstance3D, index: int) -> Transform3D:
	var xf: PackedFloat32Array = node.get_meta("campus_transforms", PackedFloat32Array())
	if xf.size() < (index + 1) * 12:
		return node.multimesh.get_instance_transform(index)
	var o := index * 12
	return Transform3D(Basis(Vector3(xf[o], xf[o + 1], xf[o + 2]), Vector3(xf[o + 3], xf[o + 4], xf[o + 5]),
		Vector3(xf[o + 6], xf[o + 7], xf[o + 8])), Vector3(xf[o + 9], xf[o + 10], xf[o + 11]))


static func _clip_instances(node: MultiMeshInstance3D, plane: Plane) -> void:
	var source := node.multimesh
	var colors: PackedFloat32Array = node.get_meta("campus_colors", PackedFloat32Array())
	var kept: Array[Transform3D] = []
	var kept_colors: Array[Color] = []
	for i in source.instance_count:
		var xf := instance_transform(node, i)
		var local := xf.affine_inverse() * plane
		var side := _side(source.mesh.get_aabb(), local)
		if side < 0:
			continue
		var tint := Color.WHITE
		if colors.size() >= (i + 1) * 3:
			tint = Color(colors[i * 3], colors[i * 3 + 1], colors[i * 3 + 2])
		elif source.use_colors:
			tint = source.get_instance_color(i)
		if side > 0:
			kept.append(xf)
			kept_colors.append(tint)
		else:
			var edge := MeshInstance3D.new()
			edge.name = "Threshold_%d" % i
			edge.mesh = clip_mesh(source.mesh, local, tint)
			edge.transform = xf
			node.add_child(edge)
	if kept.size() == source.instance_count:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = source.use_colors
	mm.mesh = source.mesh
	mm.instance_count = kept.size()
	var transforms := PackedFloat32Array()
	var next_colors := PackedFloat32Array()
	for i in kept.size():
		var xf := kept[i]
		mm.set_instance_transform(i, xf)
		transforms.append_array(PackedFloat32Array([xf.basis.x.x, xf.basis.x.y, xf.basis.x.z,
			xf.basis.y.x, xf.basis.y.y, xf.basis.y.z, xf.basis.z.x, xf.basis.z.y, xf.basis.z.z,
			xf.origin.x, xf.origin.y, xf.origin.z]))
		if mm.use_colors:
			var color := kept_colors[i]
			mm.set_instance_color(i, color)
			next_colors.append_array(PackedFloat32Array([color.r, color.g, color.b]))
	node.multimesh = mm
	node.set_meta("campus_transforms", transforms)
	node.set_meta("campus_colors", next_colors)


static func clip_mesh(source: Mesh, plane: Plane, tint: Color = Color.WHITE) -> ArrayMesh:
	var result := ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			for i in positions.size():
				indices.append(i)
		if tint != Color.WHITE:
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			if colors.is_empty():
				colors.resize(positions.size())
				colors.fill(Color.WHITE)
			for i in colors.size():
				colors[i] *= tint
			arrays[Mesh.ARRAY_COLOR] = colors
		var output := PackedInt32Array()
		var edges := {}
		for i in range(0, indices.size(), 3):
			var polygon: Array[int] = []
			for j in 3:
				var a := indices[i + j]
				var b := indices[i + (j + 1) % 3]
				var da := plane.distance_to(positions[a])
				var db := plane.distance_to(positions[b])
				if da >= -EPS:
					polygon.append(a)
				if (da >= -EPS) != (db >= -EPS):
					var key := Vector2i(mini(a, b), maxi(a, b))
					if not edges.has(key):
						edges[key] = _intersection(arrays, a, b, clampf(da / (da - db), 0.0, 1.0))
					polygon.append(int(edges[key]))
			for j in range(1, polygon.size() - 1):
				output.append_array(PackedInt32Array([polygon[0], polygon[j], polygon[j + 1]]))
		if output.is_empty():
			continue
		arrays[Mesh.ARRAY_INDEX] = output
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result.surface_set_material(result.get_surface_count() - 1, source.surface_get_material(surface))
	return result


static func _intersection(arrays: Array, a: int, b: int, t: float) -> int:
	var index := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	for slot: int in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
		if arrays[slot] == null or arrays[slot].is_empty():
			continue
		var value: Variant = arrays[slot][a].lerp(arrays[slot][b], t)
		if slot == Mesh.ARRAY_NORMAL:
			value = value.normalized()
		arrays[slot].append(value)
	if arrays[Mesh.ARRAY_TANGENT] != null and not arrays[Mesh.ARRAY_TANGENT].is_empty():
		var tangent: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		var v := Vector3(tangent[a * 4], tangent[a * 4 + 1], tangent[a * 4 + 2]).lerp(
			Vector3(tangent[b * 4], tangent[b * 4 + 1], tangent[b * 4 + 2]), t).normalized()
		tangent.append_array(PackedFloat32Array([v.x, v.y, v.z, tangent[a * 4 + 3]]))
		arrays[Mesh.ARRAY_TANGENT] = tangent
	return index
