extends "res://tests/support/test_suite.gd"


func _fixture() -> Dictionary:
	var bytes:=FileAccess.get_file_as_bytes("res://tests/fixtures/traces-reference.json.gz")
	return JSON.parse_string(bytes.decompress_dynamic(16*1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8())


func _triangles(n: Node3D) -> int:
	var count:=0
	if n is MeshInstance3D: count=n.mesh.get_faces().size()/3
	for child in n.get_children():
		if child is Node3D: count+=_triangles(child)
	return count


func test_reference() -> void:
	var fixture:=_fixture()
	var traces:=Traces.new()
	for sample: Array in fixture["hashes"]:
		check(absf(traces._hash2(int(sample[0]),int(sample[1]))-sample[2])<.000000001,"original spatial hash for %s,%s" % [sample[0],sample[1]])
	traces.free()
	for spec: Dictionary in fixture["cases"]:
		traces=Traces.new()
		root.add_child(traces)
		traces.ground_height=func(_x: float,_z: float) -> float: return spec["gy"]
		traces.build(spec["scene"],null if spec["scene"]=="out" else CampusData.layout(spec["scene"]),spec["dynamic"])
		var errors:=[]
		if traces.get_child_count()!=spec["children"].size(): errors.append("count %d != %d" % [traces.get_child_count(),spec["children"].size()])
		else:
			for i in traces.get_child_count():
				var n: Node3D=traces.get_child(i)
				var s: Dictionary=spec["children"][i]
				if n.position.distance_to(Vector3(s["p"][0],s["p"][1],s["p"][2]))>.0001: errors.append("position %d: %s != %s" % [i,n.position,s["p"]])
				if n.scale.distance_to(Vector3(s["s"][0],s["s"][1],s["s"][2]))>.0001: errors.append("scale %d" % i)
				var q: Array=s["q"]
				var actual:=Basis.from_euler(n.rotation,n.rotation_order).get_rotation_quaternion()
				if absf(actual.dot(Quaternion(q[0],q[1],q[2],q[3])))<.99999: errors.append("rotation %d" % i)
				if s.get("alpha")!=null:
					var mesh: MeshInstance3D=n if n is MeshInstance3D else n.find_children("*","MeshInstance3D",true,false)[0]
					var material:=mesh.get_active_material(0) as BaseMaterial3D
					if absf(material.albedo_color.a-s["alpha"])>.00001 or material.albedo_color.to_html(false)!=s["color"]: errors.append("material %d" % i)
				if s["triangles"]!=null and _triangles(n)!=int(s["triangles"]): errors.append("triangles %d: %d != %d" % [i,_triangles(n),s["triangles"]])
		check(errors.is_empty(),"original persistent traces %s %s: %s" % [spec["scene"],spec["dynamic"].map(func(t: Dictionary) -> String: return t["k"]),errors.slice(0,5)])
		traces.free()
	CampusData.clear_caches()
