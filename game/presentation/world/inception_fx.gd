class_name InceptionFx
extends Node3D
## Read-only dream props. The black pits use the original outlined floor planes;
## the 1.4-second fall belongs to the camera, never to saved player coordinates.
var spinner: Node3D
var pickup: Node3D


func _material(color: Color, unlit: bool = true) -> StandardMaterial3D:
	var material:=StandardMaterial3D.new()
	material.albedo_color=color
	material.roughness=1
	if unlit:
		material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.disable_fog=true
	return material


func _flat(size: Vector2, at: Vector3, material: Material) -> void:
	var plane:=QuadMesh.new()
	plane.size=size
	var mesh:=MeshInstance3D.new()
	mesh.mesh=plane
	mesh.material_override=material
	mesh.rotation.x=-PI/2
	mesh.position=at
	add_child(mesh)


func build(room: Dictionary) -> void:
	if room["id"]==InceptionModule.TOP_ROOM:
		pickup=TopModel.make()
		var w:=CampusGeometry.tile_center(room,InceptionModule.TOP_CELL.x,InceptionModule.TOP_CELL.y)
		var at:=CampusGeometry.to_scene(room,w)
		pickup.position=Vector3(at.x+.1,.76,at.y)
		add_child(pickup)
		return
	var black:=_material(Color.BLACK)
	var rim:=_material(Color("#d8dde2"))
	for r in InceptionModule.GRID.size():
		for c in InceptionModule.GRID[r].length():
			if not InceptionModule.pit(Vector2i(c,r)): continue
			var p:=CampusGeometry.to_scene(room,CampusGeometry.tile_center(room,c,r))
			_flat(Vector2.ONE,Vector3(p.x,.012,p.y),black)
			for edge: Array in [[0,-.5,1,.03,0,-1],[0,.5,1,.03,0,1],[-.5,0,.03,1,-1,0],[.5,0,.03,1,1,0]]:
				if not InceptionModule.pit(Vector2i(c+int(edge[4]),r+int(edge[5]))):
					_flat(Vector2(edge[2],edge[3]),Vector3(p.x+edge[0],.014,p.y+edge[1]),rim)
	var p:=CampusGeometry.to_scene(room,CampusGeometry.tile_center(room,InceptionModule.EXIT.x,InceptionModule.EXIT.y))
	var door:=MeshInstance3D.new()
	var box:=BoxMesh.new()
	box.size=Vector3(.9,2.05,.06)
	door.mesh=box
	door.material_override=_material(Color("#6b5a44"),false)
	door.material_override.emission_enabled=true
	door.material_override.emission=Color("#1a140c")
	door.position=Vector3(p.x,1.03,p.y+.47)
	add_child(door)
	var knob:=MeshInstance3D.new()
	var sphere:=SphereMesh.new()
	sphere.radius=.035
	sphere.height=.07
	sphere.radial_segments=10
	sphere.rings=8
	knob.mesh=sphere
	knob.material_override=_material(Color("#c9b27a"),false)
	knob.position=Vector3(p.x+.32,1,p.y+.43)
	add_child(knob)
	spinner=TopModel.make()
	spinner.visible=false
	add_child(spinner)


func present(dt: float, state: Dictionary, feet: Vector3, yaw: float) -> void:
	if not is_instance_valid(spinner): return
	spinner.visible=not state.is_empty() and state.get("spin","")!=""
	if not spinner.visible: return
	spinner.position=Vector3(feet.x-sin(yaw),0,feet.z-cos(yaw))
	if state["spin"]=="stand": spinner.rotation=Vector3(0,spinner.rotation.y+dt*22,0)
	else: spinner.rotation=Vector3(0,0,1.25)
