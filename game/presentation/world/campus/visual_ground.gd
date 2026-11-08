class_name VisualGround
extends RefCounted
## Read-only equivalent of cupGroundY: the first rendered surface between y=1.5
## and y=-0.5. Physics has a flat floor, while paving/curbs sit slightly above it.
## Mesh BVHs are lazy and owned by this world; no global scene resource retention.
var _nodes: Array[GeometryInstance3D]=[]
var _trees: Dictionary={}
var _instances: Dictionary={}


func set_model(model: Node3D) -> void:
	_nodes.clear()
	_trees.clear()
	_instances.clear()
	for n: Node in model.find_children("*","GeometryInstance3D",true,false):
		if n is MeshInstance3D or n is MultiMeshInstance3D: _nodes.append(n)


func _hit(mesh: Mesh, transform: Transform3D, begin: Vector3, end: Vector3) -> float:
	if mesh==null: return -INF
	var inverse:=transform.affine_inverse()
	var a:=inverse*begin
	var b:=inverse*end
	if mesh.get_aabb().intersects_segment(a,b)==null: return -INF
	if not _trees.has(mesh): _trees[mesh]=mesh.generate_triangle_mesh()
	var tree: TriangleMesh=_trees[mesh]
	var hit:=tree.intersect_segment(a,b)
	return (transform*(hit["position"] as Vector3)).y if not hit.is_empty() else -INF


func height(x: float, z: float) -> float:
	var begin:=Vector3(x,1.5,z)
	var end:=Vector3(x,-.5,z)
	var highest:=-INF
	for n: GeometryInstance3D in _nodes:
		if not is_instance_valid(n) or not n.is_visible_in_tree(): continue
		if n is MeshInstance3D:
			highest=maxf(highest,_hit(n.mesh,n.global_transform,begin,end))
		else:
			var mm: MultiMesh=n.multimesh
			var inverse:=n.global_transform.affine_inverse()
			if mm==null: continue
			if not _instances.has(n):
				var transforms: Array[Transform3D]=[]
				var box:=AABB()
				var xf: PackedFloat32Array=n.get_meta("campus_transforms",PackedFloat32Array())
				for i in mm.instance_count:
					var o:=i*12
					var transform:=Transform3D(Basis(Vector3(xf[o],xf[o+1],xf[o+2]),Vector3(xf[o+3],xf[o+4],xf[o+5]),Vector3(xf[o+6],xf[o+7],xf[o+8])),Vector3(xf[o+9],xf[o+10],xf[o+11])) if xf.size()>=o+12 else mm.get_instance_transform(i)
					transforms.append(transform)
					var bounds: AABB=transform*mm.mesh.get_aabb()
					box=bounds if i==0 else box.merge(bounds)
				_instances[n]={"xf":transforms,"box":box}
			var entry: Dictionary=_instances[n]
			if (entry["box"] as AABB).intersects_segment(inverse*begin,inverse*end)==null: continue
			var count:=mm.instance_count if mm.visible_instance_count<0 else mm.visible_instance_count
			for i in count: highest=maxf(highest,_hit(mm.mesh,n.global_transform*entry["xf"][i],begin,end))
	return highest if is_finite(highest) else 0.0
