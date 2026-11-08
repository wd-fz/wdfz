class_name TopModel
extends RefCounted
## The original brass top, with the separate dimensions used by the ending's close-up.


static func make(cinematic: bool = false) -> Node3D:
	var root:=Node3D.new()
	root.name="BrassTop"
	var material:=StandardMaterial3D.new()
	material.albedo_color=Color("#b48d4c" if cinematic else "#b08a4a")
	material.roughness=1
	if cinematic:
		material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.disable_fog=true
	else:
		material.emission_enabled=true
		material.emission=Color("#2a1d0a")
	var specs: Array=[[0,.06,.085,.043,20],[.06,.06,.014,.092,20],[.01,.01,.05,.123,8]] if cinematic else [[0,.05,.07,.035,16],[.05,.05,.012,.075,16],[.008,.008,.04,.1,8]]
	for i in specs.size():
		var s: Array=specs[i]
		var mesh:=CylinderMesh.new()
		mesh.bottom_radius=s[0]
		mesh.top_radius=s[1]
		mesh.height=s[2]
		mesh.radial_segments=s[4]
		var node:=MeshInstance3D.new()
		node.mesh=mesh
		node.position.y=s[3]
		node.material_override=material
		if cinematic and i==1:
			var cap: StandardMaterial3D=material.duplicate()
			cap.albedo_color=Color("#6e5528")
			node.material_override=cap
		root.add_child(node)
	return root
