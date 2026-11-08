extends "res://tests/support/test_suite.gd"


func _fixture() -> Dictionary:
	var bytes:=FileAccess.get_file_as_bytes("res://tests/fixtures/falling_props-reference.json.gz")
	return JSON.parse_string(bytes.decompress_dynamic(16*1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8())


func _v(a: Array) -> Vector3:
	return Vector3(a[0],a[1],a[2])


func _compare(n: Node3D, spec: Dictionary, label: String, errors: Array) -> void:
	if n.position.distance_to(_v(spec["p"]))>.0001: errors.append(label+" position")
	if n.scale.distance_to(_v(spec["s"]))>.0001: errors.append(label+" scale")
	if n.visible!=spec["v"]: errors.append(label+" visible")
	var q: Array=spec["q"]
	var actual:=Basis.from_euler(n.rotation,n.rotation_order).get_rotation_quaternion()
	if absf(actual.dot(Quaternion(q[0],q[1],q[2],q[3])))<.99999: errors.append(label+" orientation")
	if spec.has("alpha"):
		var mesh: MeshInstance3D=n if n is MeshInstance3D else n.find_children("*","MeshInstance3D",true,false)[0]
		var mat:=mesh.get_active_material(0) as BaseMaterial3D
		if absf(mat.albedo_color.a-spec["alpha"])>.00001: errors.append(label+" opacity")
		if mat.albedo_color.to_html(false)!=spec["color"]: errors.append(label+" colour: "+mat.albedo_color.to_html(false))
	if spec.has("velocity") and not same_json(n.get_meta("velocity"),spec["velocity"]): errors.append(label+" velocity")


func _differences(props: FallingProps, state: Dictionary) -> Array:
	var errors:=[]
	var nodes:={"cup":props.body,"can":props.body,"ring":props.ring,"core":props.core,"lidWrap":props.lid_wrap,"lid":props.lid,"pool":props.pool}
	for key: String in nodes:
		if state.has(key): _compare(nodes[key],state[key],key,errors)
	if props.particles.size()!=state["particles"].size(): errors.append("particle count")
	else:
		for i in props.particles.size(): _compare(props.particles[i],state["particles"][i],"particle %d" % i,errors)
	if state.has("attached_lid") and props.attached_lid.visible!=state["attached_lid"]: errors.append("attached lid")
	return errors


func test_reference() -> void:
	var fixture:=_fixture()
	var rules:=CampusData.make_anomaly()
	for wall: Dictionary in fixture["walls"]:
		rules.set_context({"scene":"out","x":wall["x"],"y":wall["y"]})
		check(same_json(rules._cup_wall(),wall["result"]),"cup window source retains the original outward normal and nearest wall")
		var saved: Dictionary=wall["result"].duplicate(true)
		saved.erase("nx")
		saved.erase("ny")
		var props:=FallingProps.new()
		var p:=CampusGeometry.to_scene(null,Vector2(wall["x"],wall["y"]))
		props.build("cup",{"wall":saved,"phase":0},null,Vector3(p.x,0,p.y),0,2)
		var expected: Dictionary=wall["result"]
		var sill:=CampusGeometry.to_scene(null,Vector2(expected["x"],expected["y"])*AnomalyModule.SC)+Vector2(expected["nx"],expected["ny"])*.2
		check(Vector2(props.body.position.x,props.body.position.z).distance_to(sill)<.0001 and not saved.has("nx"),"early native saves regain a visible window offset without changing their saved data")
		props.free()
	check(fixture["scenarios"].size()==18,"original cup/cola fixtures cover three ground heights and every loaded phase")
	for spec: Dictionary in fixture["scenarios"]:
		var props:=FallingProps.new()
		root.add_child(props)
		props.ground_height=func(_x: float,_z: float) -> float: return spec["gy"]
		var data: Dictionary=spec["data"].duplicate(true)
		var at:=CampusGeometry.to_scene(null,Vector2(spec["me"]["x"],spec["me"]["y"]))
		props.build(spec["kind"],data,null,Vector3(at.x,0,at.y),spec["t"],2)
		var errors:=_differences(props,spec["before"])
		check(errors.is_empty(),"original %s spawn phase%s ground%s: %s" % [spec["kind"],spec["initial"],spec["gy"],errors.slice(0,4)])
		for f: Dictionary in spec["frames"]:
			data=f["data"].duplicate(true)
			props.advance(f["dt"],f["t"],data,null,_v(f["feet"]))
			errors=_differences(props,f["state"])
			check(errors.is_empty(),"original %s phase%s at %.4f ground%s: %s" % [spec["kind"],data["phase"],f["t"],spec["gy"],errors.slice(0,4)])
			check(same_json(data,f["data"]),"fall animation does not modify the shared anomaly state")
		props.free()


func _bounds(n: Node3D, transform: Transform3D, result: Dictionary) -> void:
	var current:=transform*n.transform
	if n is MeshInstance3D:
		var box: AABB=current*n.mesh.get_aabb()
		result["box"]=box if not result.has("box") else (result["box"] as AABB).merge(box)
		for s in n.mesh.get_surface_count():
			var arrays: Array=n.mesh.surface_get_arrays(s)
			var indices: Variant=arrays[Mesh.ARRAY_INDEX]
			result["triangles"]+=indices.size()/3 if indices!=null and indices.size()>0 else arrays[Mesh.ARRAY_VERTEX].size()/3
			var mat:=n.mesh.surface_get_material(s) as BaseMaterial3D
			if mat!=null and mat.albedo_texture!=null: result["texture"]=maxi(result["texture"],mat.albedo_texture.get_width())
	for child in n.get_children():
		if child is Node3D: _bounds(child,current,result)


func test_models() -> void:
	for spec: Dictionary in _fixture()["models"]:
		var object:=FallingProps.model(spec["kind"],spec["tier"])
		var actual:={"triangles":0,"texture":0}
		_bounds(object,Transform3D.IDENTITY,actual)
		var expected_triangles:=0
		var expected_texture:=0
		for m: Dictionary in spec["mesh"]:
			expected_triangles+=m["triangles"]
			expected_texture=maxi(expected_texture,m["texture"])
		var box: AABB=actual["box"]
		check(box.position.distance_to(_v(spec["min"]))<.00001 and box.end.distance_to(_v(spec["max"]))<.00001,"original %s q%s model dimensions survive GLB export" % [spec["kind"],spec["tier"]])
		check(actual["triangles"]==expected_triangles and actual["texture"]==expected_texture,"original %s q%s retains tessellation and painted texture resolution" % [spec["kind"],spec["tier"]])
		check(object.find_children("*","MeshInstance3D",true,false).all(func(n: MeshInstance3D) -> bool: return n.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF),"falling props retain the original non-shadow-casting model")
		object.free()


func test_world() -> void:
	CampusData.tier=2
	var world:=CampusWorld.new()
	world.scene_id="out"
	root.add_child(world)
	await _frames()
	for p: Dictionary in _fixture()["ground"]:
		var actual:=world.visual_ground.height(p["x"],p["z"])
		# Captured mesh/ray arithmetic differs by up to 0.2 mm on planar surfaces;
		# the smallest authored overlay offset is 11 mm.
		check(absf(actual-p["y"])<.0005,"rendered campus surface at %.3f,%.3f: %.5f matches original %.5f" % [p["x"],p["z"],actual,p["y"]])
	var point:=Vector3(1200/9.0,0,400/9.0)
	var an: Dictionary={"id":"cola","active":true,"t":0.0,"data":{"phase":0,"scene":"out"}}
	var fx:=world.anomaly_fx
	fx.visual_seed=42
	fx.update(0,an,null,"out",point,Vector2.RIGHT)
	var falling: FallingProps=fx._extra["falling"]
	check(absf(falling.ring.position.y-world.visual_ground.height(point.x,point.z)-.035)<.0001,"anomaly adapter samples the rendered world surface for its warning ring")
	an["t"]=.5
	fx.update(.5,an,null,"out",point+Vector3(1,0,1),Vector2.RIGHT)
	check(Vector2(falling.ring.position.x,falling.ring.position.z).distance_to(Vector2(point.x+1,point.z+1))<.0001,"cola warning follows the player until the rule locks its landing point")
	var snapshot:=an.duplicate(true)
	CampusData.tier=0
	world.reload_models(point)
	fx.update(0,an,null,"out",point,Vector2.RIGHT)
	check(fx._extra["falling"]!=falling and not falling.is_visible_in_tree() and same_json(an,snapshot),"quality changes rebuild only the visual prop, preserving the active event")
	an["data"]["scene"]="teach1"
	fx.update(0,an,null,"out",point,Vector2.RIGHT)
	check(fx.shown_count()==0,"an event from a departed scene cannot leave falling objects in this world")
	world.sync_traces([{"k":"cup","x":1200.0,"y":400.0,"room":""}])
	var old: Node3D=world.traces.get_child(world.traces.get_child_count()-3)
	var old_at:=old.position
	world.sync_traces([{"k":"cup","x":1209.0,"y":400.0,"room":""}])
	var replacement: Node3D=world.traces.get_child(world.traces.get_child_count()-3)
	check(not old.is_visible_in_tree() and absf(replacement.position.x-old_at.x-1)<.0001,"a same-length trace replacement rebuilds its location without a ghost frame")
	CampusData.tier=2
	world.reload_models(point)
	var refreshed: Node3D=world.traces.get_child(world.traces.get_child_count()-3)
	check(refreshed!=replacement and not replacement.is_visible_in_tree() and refreshed.position.distance_to(old_at+Vector3.RIGHT)<.0005,"quality reload rebuilds the persistent cup while preserving its location")
	world.queue_free()
	await _frames()
	CampusData.tier=2
	CampusData.clear_caches()


func test_app() -> void:
	var app: GameApp=APP.instantiate()
	app.saves=SaveStore.new(_test_path)
	app.settings=GameSettings.new(_test_path.get_base_dir()+"/falling-settings.json")
	root.add_child(app)
	await _frames(2)
	app.wuda_roll=func() -> float: return 1
	app.start_new_game("hard","none")
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app._stand_up()
	var p:=Vector3(1200/9.0,0,400/9.0)
	app.travel("out",{"position":[p.x,0,p.z],"yaw":0,"pitch":0},false)
	for kind: String in ["cup","cola"]:
		for phase in [1,2]:
			var data:={"scene":"out","phase":phase,"tf":1.2,"tl":3.7,"lx":1200.0,"ly":400.0,"wall":{"x":595.0,"y":195.0,"nx":1.0,"ny":0.0}}
			app.anomaly().an.merge({"id":kind,"active":true,"t":1.7 if phase==1 else 4.0,"data":data},true)
			app._school_step(0,app.campus())
			app.save_game()
			app.load_game()
			app.set_physics_process(false)
			app.player.set_physics_process(false)
			await _frames(2)
			app._school_step(0,app.campus())
			var fx:=app._campus_world().anomaly_fx
			check(fx.current()==kind and same_json(app.anomaly().an["data"],data),"live save/load resumes %s phase%d without resetting the locked landing or times" % [kind,phase])
			var props: FallingProps=fx._extra["falling"]
			check(props.body.position.y>1 if phase==1 else props.body.position.y<.5,"saved %s appears at the correct falling/landed height" % kind)
			if kind=="cup": check(props.attached_lid.visible==(phase==1),"saved cup lid is attached only before impact")
			else: check(props.pool.visible==(phase==2),"saved cola pool appears only after impact")
	app.anomaly().end_now()
	app._school_step(0,app.campus())
	check(app._campus_world().anomaly_fx.shown_count()==0,"ending the restored event releases every prop")
	app.return_to_menu()
	app.queue_free()
	await _frames(2)
	CampusData.clear_caches()
