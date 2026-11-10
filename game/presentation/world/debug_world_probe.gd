class_name DebugWorldProbe
extends Node3D
## A bounded, disposable view of actual physics shapes; never edits meshes or collision.
const MAX_SHAPES := 96
const MAX_VERTICES := 16384
const RADIUS := 12.0
const RAY_LENGTH := 30.0
var _world: Node3D
var _candidates: Array[Node] = []
var _wires: Dictionary = {}
var _meshes: Dictionary = {}
var _batches: Array[MeshInstance3D] = []
var _bounds: Dictionary = {}
var shown := 0
var nearby := 0
var _next_scan := 0
var _wall: StandardMaterial3D
var _door: StandardMaterial3D

func _init() -> void:
	name="DebugWorldProbe"
	_wall=_material(Color(.25,.9,.72,.65))
	_door=_material(Color(1,.65,.25,.8))
	for material: StandardMaterial3D in [_wall,_door]:
		var batch:=MeshInstance3D.new()
		batch.mesh=ArrayMesh.new()
		batch.material_override=material
		batch.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(batch)
		_batches.append(batch)

func _material(color: Color) -> StandardMaterial3D:
	var material:=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color=color
	material.no_depth_test=true
	material.disable_fog=true
	material.render_priority=110
	return material

func clear() -> void:
	for batch: MeshInstance3D in _batches:
		batch.hide()
		(batch.mesh as ArrayMesh).clear_surfaces()
	_wires.clear()
	_meshes.clear()
	_bounds.clear()
	_candidates.clear()
	_world=null
	shown=0
	nearby=0

func bind_world(world: Node3D) -> void:
	if is_instance_valid(_world) and _world==world:
		if Time.get_ticks_msec()<_next_scan: return
	else:
		clear()
		_world=world
	if is_instance_valid(world):
		_candidates=world.find_children("*","CollisionShape3D",true,false)
		_next_scan=Time.get_ticks_msec()+1000

func _lines(shape: Shape3D) -> ArrayMesh:
	var key:=shape.get_instance_id()
	if _meshes.has(key): return _meshes[key]
	var source:=shape.get_debug_mesh()
	var result:=ArrayMesh.new()
	for i in source.get_surface_count():
		if source.surface_get_primitive_type(i)==Mesh.PRIMITIVE_LINES:
			result.add_surface_from_arrays(Mesh.PRIMITIVE_LINES,source.surface_get_arrays(i))
	_meshes[key]=result
	return result

func draw_near(point: Vector3, enabled: bool) -> void:
	shown=0
	nearby=0
	_wires.clear()
	for batch: MeshInstance3D in _batches: batch.hide()
	if not enabled or not is_instance_valid(_world): return
	var choices: Array[Dictionary]=[]
	for candidate: CollisionShape3D in _candidates:
		if not is_instance_valid(candidate) or candidate.disabled or candidate.shape==null: continue
		var body:=candidate.get_parent() as CollisionObject3D
		if body==null or (body.collision_layer & 3)==0: continue
		var shape_id:=candidate.shape.get_instance_id()
		if not _bounds.has(shape_id): _bounds[shape_id]=candidate.shape.get_debug_mesh().get_aabb()
		var bounds: AABB=candidate.global_transform*_bounds[shape_id]
		var distance:=point.distance_squared_to(point.clamp(bounds.position,bounds.end))
		if distance<=RADIUS*RADIUS: choices.append({"shape":candidate,"distance":distance})
	choices.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.distance<b.distance)
	nearby=choices.size()
	var points: Array[PackedVector3Array]=[PackedVector3Array(),PackedVector3Array()]
	for i in mini(MAX_SHAPES,choices.size()):
		var shape: CollisionShape3D=choices[i].shape
		var outline:=_lines(shape.shape)
		var color:=1 if String(shape.get_parent().name)=="Doors" else 0
		var emitted:=false
		for surface in outline.get_surface_count():
			var arrays:=outline.surface_get_arrays(surface)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			var count:=indices.size() if not indices.is_empty() else vertices.size()
			if points[0].size()+points[1].size()+count>MAX_VERTICES: continue
			var group:=points[color]
			for j in count:
				var local:=vertices[indices[j] if not indices.is_empty() else j]
				group.append(to_local(shape.global_transform*local))
			points[color]=group
			emitted=emitted or count>0
		if emitted:
			_wires[shape.get_instance_id()]=true
			shown+=1
	# Two line batches instead of a draw call and node for every collision shape.
	for i in 2:
		var mesh:=_batches[i].mesh as ArrayMesh
		mesh.clear_surfaces()
		if points[i].is_empty(): continue
		var arrays:=[]
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=points[i]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES,arrays)
		_batches[i].show()
	if _meshes.size()>MAX_SHAPES*2: _meshes.clear()


func inspect(camera: Camera3D, player: PlayerController) -> Dictionary:
	if not is_instance_valid(_world): return {}
	var from:=camera.global_position
	var query:=PhysicsRayQueryParameters3D.create(from,from-camera.global_basis.z*RAY_LENGTH,3,[player.get_rid()])
	query.collide_with_areas=true
	var hit:=_world.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return {"hit":false,"range":RAY_LENGTH}
	var collider:=hit["collider"] as CollisionObject3D
	if collider==null:
		return {"hit":true,"distance":from.distance_to(hit["position"]),"point":DebugTrace.clean(hit["position"]),"normal":DebugTrace.clean(hit["normal"]),"collider":str(hit.get("rid","")),"shape":"无节点形状","class":"PhysicsServer","layer":-1}
	var shape_name:=""
	var owner:=collider.shape_find_owner(int(hit["shape"]))
	var shape:=collider.shape_owner_get_owner(owner) as Node
	if shape!=null: shape_name=String(shape.name)
	var point: Vector3=hit["position"]
	return {"hit":true,"distance":from.distance_to(point),"point":[point.x,point.y,point.z],
		"normal":DebugTrace.clean(hit["normal"]),"collider":String(_world.get_path_to(collider)),
		"shape":shape_name,"kind":String(shape.get_meta("kind","")) if shape!=null else "","class":collider.get_class(),"layer":collider.collision_layer}
