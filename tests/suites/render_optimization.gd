extends "res://tests/support/test_suite.gd"
## Conservation checks, not just lower counters: original transforms/colours/triangles,
## dynamic-door independence, a real open doorway under occlusion and post mip switching.


func _instances(parent: Node3D, mesh: Mesh, places: Array[Transform3D]) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = places.size()
	var transforms := PackedFloat32Array()
	var colors := PackedFloat32Array()
	for i in places.size():
		var xf := places[i]
		mm.set_instance_transform(i,xf)
		transforms.append_array(PackedFloat32Array([xf.basis.x.x,xf.basis.x.y,xf.basis.x.z,xf.basis.y.x,xf.basis.y.y,xf.basis.y.z,xf.basis.z.x,xf.basis.z.y,xf.basis.z.z,xf.origin.x,xf.origin.y,xf.origin.z]))
		var color := Color(.2+i*.1,.4,.7)
		colors.append_array(PackedFloat32Array([color.r,color.g,color.b]))
		mm.set_instance_color(i,color)
	node.multimesh=mm
	node.set_meta("campus_transforms",transforms)
	node.set_meta("campus_colors",colors)
	parent.add_child(node)
	return node


func test_instances() -> void:
	var model:=Node3D.new()
	var box:=BoxMesh.new()
	var mat:=StandardMaterial3D.new()
	mat.resource_name="MeshPhongMaterial"
	box.material=mat
	var a:=Transform3D(Basis(Vector3.UP,.3).scaled(Vector3(-1,2,1)),Vector3(1,0,2))
	var b:=Transform3D(Basis.IDENTITY,Vector3(100,0,2))
	_instances(model,box,[a,b])
	var second:=box.duplicate() as BoxMesh
	second.material=mat.duplicate()
	_instances(model,second,[Transform3D(Basis.IDENTITY,Vector3(2,0,2))])
	var door:=Node3D.new()
	door.set_meta("extras",{"door_key":"test:door","state":"closed"})
	model.add_child(door)
	var moving:=_instances(door,box,[Transform3D.IDENTITY])
	var report:=CampusBatches.optimize(model)
	check(report.instances==3 and report.prototypes==1 and report.batches>=2,"exact clones share a prototype and are partitioned spatially without dropping instances: %s" % report)
	check(is_instance_valid(moving) and moving.get_parent()==door,"door geometry remains under its movable holder")
	var found:=false
	var tints_ok:=true
	var actual_count:=0
	var compact:=true
	for node: MultiMeshInstance3D in model.find_children("*","MultiMeshInstance3D",true,false):
		if node==moving: continue
		var bounds:=AABB(CampusPreview.instance_transform(node,0).origin,Vector3.ZERO)
		actual_count+=node.multimesh.instance_count
		for i in node.multimesh.instance_count:
			var xf:=CampusPreview.instance_transform(node,i)
			bounds=bounds.expand(xf.origin)
			if xf.origin.is_equal_approx(a.origin): found=xf.is_equal_approx(a)
			var colors: PackedFloat32Array=node.get_meta("campus_colors")
			tints_ok=tints_ok and absf(colors[i*3+1]-.4)<.00001 and absf(colors[i*3+2]-.7)<.00001
		compact=compact and maxf(bounds.size.x,maxf(bounds.size.y,bounds.size.z))<=CampusBatches.MAX_SPAN
	check(actual_count==3 and compact,"actual uploaded batches contain all three instances and no campus-wide bounds")
	check(found and tints_ok,"negative scale, nonuniform basis, original transforms and instance tints survive batching")
	var live:=mat.duplicate() as StandardMaterial3D
	live.resource_name="wdfz_live:emit"
	check(CampusBatches._material_key(live)!=CampusBatches._material_key(mat),"live emissive bindings are never canonicalized into an ordinary material")
	model.free()
	var classroom:=ClassmatesView.new()
	classroom.build(CampusData.layout("teach1"),[Vector2i(8,8),Vector2i(9,8)])
	var figures:=classroom.find_children("*","MeshInstance3D",true,false)
	check(figures.size()>1 and figures[0].material_override==figures[1].material_override,"classmates share a view-local material for automatic instancing")
	var other:=ClassmatesView.new()
	other.build(CampusData.layout("teach1"),[Vector2i(8,8)])
	var other_material:=other.find_children("*","MeshInstance3D",true,false)[0].material_override as StandardMaterial3D
	classroom.set_normal(true)
	check(other_material.shading_mode==BaseMaterial3D.SHADING_MODE_UNSHADED and classroom._material.shading_mode==BaseMaterial3D.SHADING_MODE_PER_PIXEL,"changing classroom lighting cannot recolour a different view or cinematic")
	classroom.free()
	other.free()


func test_mesh_cells() -> void:
	if DisplayServer.get_name()=="headless": return # Imported ArrayMesh readback needs a rendering server.
	var box:=BoxMesh.new()
	box.material=StandardMaterial3D.new()
	var builder:=SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	builder.append_from(box,0,Transform3D.IDENTITY)
	builder.append_from(box,0,Transform3D(Basis.IDENTITY,Vector3(40,0,0)))
	var source:=builder.commit()
	source.surface_set_material(0,box.material)
	var pieces:=CampusMeshCells._pieces(source)
	var faces:=source.get_faces()
	var recovered:=PackedVector3Array()
	for piece in pieces: recovered.append_array(piece.get_faces())
	check(pieces.size()>1 and recovered.size()==faces.size(),"spatial meshes keep every original full-detail triangle")
	var originals:={}
	for vertex: Vector3 in faces: originals[vertex]=int(originals.get(vertex,0))+1
	for vertex: Vector3 in recovered: originals[vertex]=int(originals.get(vertex,0))-1
	check(originals.values().all(func(count: int) -> bool: return count==0),"cell division does not move or lose triangle vertices")
	var has_attributes:=true
	for piece in pieces:
		var arrays:=piece.surface_get_arrays(0)
		var count: int=arrays[Mesh.ARRAY_VERTEX].size()
		has_attributes=has_attributes and arrays[Mesh.ARRAY_NORMAL].size()==count and arrays[Mesh.ARRAY_TEX_UV].size()==count and arrays[Mesh.ARRAY_TANGENT].size()==count*4
	check(has_attributes,"spatial cells preserve normals, UVs and tangent handedness")
	var alpha:=box.material.duplicate() as StandardMaterial3D
	alpha.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	source.surface_set_material(0,alpha)
	# Fresh resource: a cached source must never be edited after it has been optimized.
	var transparent:=source.duplicate() as ArrayMesh
	check(CampusMeshCells._pieces(transparent).is_empty(),"transparent meshes retain their original depth-sort grouping")


func _wall(parent: Node3D, position: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var node:=MeshInstance3D.new()
	var mesh:=BoxMesh.new()
	mesh.size=size
	var mat:=StandardMaterial3D.new()
	mat.albedo_color=color
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material=mat
	node.mesh=mesh
	node.position=position
	parent.add_child(node)
	return node


func test_occlusion() -> void:
	var vp:=SubViewport.new()
	vp.size=Vector2i(160,90)
	vp.own_world_3d=true
	vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var model:=Node3D.new()
	vp.add_child(model)
	_wall(model,Vector3(-1.4,1.5,0),Vector3(1.8,3,.2),Color.GRAY)
	_wall(model,Vector3(1.4,1.5,0),Vector3(1.8,3,.2),Color.GRAY)
	var door:=Node3D.new()
	door.set_meta("extras",{"door_key":"test:occlusion","state":"closed"})
	model.add_child(door)
	var leaf:=_wall(door,Vector3(0,1.5,0),Vector3(1,3,.2),Color.RED)
	var triangles:=CampusBatches.add_occluder(model)
	check(triangles>0,"actual opaque walls supply occluder triangles")
	var occluder:=model.get_node("OpaqueWallOccluder") as OccluderInstance3D
	var vertices:=occluder.occluder.get_vertices()
	var opening_clear:=true
	for p: Vector3 in vertices: opening_clear=opening_clear and absf(p.x)>=.5-.0001
	check(opening_clear,"a closed door is never baked across the permanent occluder's opening")
	if DisplayServer.get_name()!="headless":
		_wall(model,Vector3(0,1.5,-2),Vector3(3,3,.2),Color.GREEN)
		var camera:=Camera3D.new()
		vp.add_child(camera)
		camera.position=Vector3(0,1.5,3)
		camera.current=true
		for closed: bool in [true,false,true]:
			leaf.visible=closed
			vp.use_occlusion_culling=false
			await _frames(4)
			await RenderingServer.frame_post_draw
			var expected:=vp.get_texture().get_image().get_pixel(80,45)
			vp.use_occlusion_culling=true
			await _frames(6)
			await RenderingServer.frame_post_draw
			var actual:=vp.get_texture().get_image().get_pixel(80,45)
			check(actual.is_equal_approx(expected) and (actual.r>actual.g if closed else actual.g>actual.r),"real Vulkan occlusion preserves the %s doorway" % ("closed" if closed else "open"))
	vp.queue_free()
	await _frames(1)


func test_post_path() -> void:
	var post:=ScenePost.new()
	var mat:=post.material as ShaderMaterial
	check(mat.shader==ScenePost.GRADE_SHADER,"ordinary grading does not request a screen mip pyramid")
	post.parameter("brightness",1.2)
	post.sensory({"blur":.8,"warp":.5},.2,12)
	check(mat.shader==ScenePost.BLUR_SHADER and is_equal_approx(float(mat.get_shader_parameter("brightness")),1.2),"defocus switches to mip filtering without dropping grading uniforms")
	post.parameter("normal",1.0)
	check(mat.shader==ScenePost.GRADE_SHADER,"the normal world suppresses defocus and releases the mip-copy path")
	post.reset()
	check(mat.shader==ScenePost.GRADE_SHADER and float(mat.get_shader_parameter("blink"))==0,"reset clears mip use and effect state together")
	if DisplayServer.get_name()!="headless":
		var vp:=SubViewport.new()
		vp.size=Vector2i(64,64)
		vp.disable_3d=true
		vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		var image:=Image.create(64,64,false,Image.FORMAT_RGB8)
		image.fill(Color.BLACK)
		image.fill_rect(Rect2i(30,0,4,64),Color.WHITE)
		var source:=TextureRect.new()
		source.texture=ImageTexture.create_from_image(image)
		source.size=Vector2(64,64)
		vp.add_child(source)
		vp.add_child(post)
		post.parameter("grain",0.0)
		for blurred: bool in [false,true,false,true]:
			# Exaggerate defocus so this tiny viewport samples above mip level zero.
			post.sensory({"blur":1.0 if blurred else 0.0,"focus":10.0 if blurred else 0.0},0,0)
			await _frames(3)
			await RenderingServer.frame_post_draw
			var pixel:=vp.get_texture().get_image().get_pixel(32,32)
			check(pixel.r>.1 and (mat.shader==ScenePost.BLUR_SHADER)==blurred,"real Vulkan frame survives grading/defocus pipeline switch %s" % blurred)
		vp.queue_free()
		await _frames(1)
	else: post.free()


func test_lazy_portals() -> void:
	var world:=CampusWorld.new()
	world.scene_id="out"
	root.add_child(world)
	await _frames(1)
	check(world.door_previews.size()>2 and world.door_previews.all(func(n: Node3D)->bool:return n.get_child_count()==0),"distant portals do not instantiate all ground floors")
	world.apply_doors({"teach1:10:15":true})
	for i in mini(3,world.door_previews.size()):
		var portal:=world.door_previews[i]
		var threshold: Vector2=portal.get_meta("door_threshold")
		world.set_player_scene(Vector3(threshold.x,0,threshold.y))
		check(portal.get_child_count()>0 and portal.visible,"approaching portal %d loads its geometry before display" % i)
	check(world.door_previews.filter(func(n: Node3D)->bool:return n.get_child_count()>0).size()<=2,"portal geometry cache stays bounded after visiting multiple buildings")
	var first:=world.door_previews[0]
	world._ensure_door_preview(first)
	var entries: Array=world._preview_doors.get("teach1:10:15",[])
	check(entries.size()==2 and entries.all(func(e: Dictionary)->bool:return is_instance_valid(e.node) and e.node.visible==(e.state=="open")),"reloading an evicted portal restores the current open-door state")
	world.queue_free()
	await _frames(1)
