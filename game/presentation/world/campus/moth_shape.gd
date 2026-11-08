class_name MothShape
extends RefCounted
## The original pointed forewing and round hindwing, sampled at ShapeGeometry's three segments.

static func wing() -> ArrayMesh:
	var outline := PackedVector2Array([Vector2(0,.012),Vector2(.05,.03),Vector2(.072,.018)])
	for curve: Array in [[Vector2(.072,.018),Vector2(.06,-.012),Vector2(.04,-.016)],[Vector2(.04,-.016),Vector2(.03,-.04),Vector2(.008,-.03)]]:
		for i in range(1,4):
			var t := i/3.0
			outline.append(curve[0]*(1-t)*(1-t)+curve[1]*2*t*(1-t)+curve[2]*t*t)
	outline.append(Vector2(0,-.014))
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	for p in outline:
		points.append(Vector3(p.x,0,-p.y))
		normals.append(Vector3.UP)
	var triangles := Geometry2D.triangulate_polygon(outline)
	for i in range(0,triangles.size(),3):
		var tmp := triangles[i+1]
		triangles[i+1] = triangles[i+2]
		triangles[i+2] = tmp
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = triangles
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

static func pose(position: Vector3, heading: float, flap: float, scale: Vector3) -> Transform3D:
	# Local mirrored X scale, followed by YZX rotation; global scaling would flip the heading too.
	return Transform3D(Basis.from_euler(Vector3(0,heading,flap),EULER_ORDER_YZX)*Basis.from_scale(scale),position)
