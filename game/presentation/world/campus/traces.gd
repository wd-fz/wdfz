class_name Traces
extends Node3D
## The traces that are always there (fx/traces.js TRACE_STATIC, reference wd-fz.github.io@0bf508a): marks of things that
## happened before you came — scratches by the toilet door, two drag marks in the garage, wet footprints at the dormitory
## stairs (only the way in), a chalk outline on the roof, a white sneaker by the sports ground, hand prints on the lab glass
## (pressed from outside). Dynamic leftovers keep their original global list index,
## stable hash and models across scene changes, quality changes and saved games.

const STATIC := [
	{"k": "scratch", "room": "teach1", "c": 56.98, "r": 17.2},
	{"k": "drag", "room": "garage1", "c": 40.0, "r": 13.5},
	{"k": "wetfeet", "room": "dorm1", "c": 38.0, "r": 7.5},
	{"k": "outline", "room": "teach6", "c": 20.0, "r": 6.0},
	{"k": "shoe", "room": "", "x": 288.0, "y": 428.0},
	{"k": "hands", "room": "lab1", "c": 24.0, "r": 16.01}]

var _count := 0
var ground_height: Callable


static func for_scene(scene_id: String) -> Array:
	var out: Array = []
	for t: Dictionary in STATIC:
		if String(t["room"]) == ("" if scene_id == "out" else scene_id):
			out.append(t)
	return out


func count() -> int:
	return _count


func _mat(col: Color, op: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, op)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if op < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.depth_draw_mode=BaseMaterial3D.DEPTH_DRAW_ALWAYS
	return m


func _box(m: Material, w: float, h: float, d: float, x: float, y: float, z: float, rot: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.rotation_order=EULER_ORDER_XYZ
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, d)
	mi.mesh = bm
	mi.material_override = m
	mi.position = Vector3(x, y, z)
	mi.rotation.y = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_count += 1
	return mi


func _flat(m: Material, w: float, d: float, x: float, z: float, rot: float, y: float = 0.016) -> void:
	_box(m, w, 0.004, d, x, y, z, rot)


func _footprints(m: Material, x: float, z: float, a: float, n: int, gap: float) -> void:
	for i in n:
		var fx := x + cos(a) * float(i) * gap
		var fz := z + sin(a) * float(i) * gap
		var side := (1.0 if i % 2 == 1 else -1.0) * 0.12
		_flat(m, 0.11, 0.26, fx - sin(a) * side, fz + cos(a) * side, -a + PI / 2.0)


## The ones an anomaly left (AnomalyModule.traces): the same builder, after the fixed ones.
static func dynamic_for(list: Array, scene_id: String) -> Array:
	var out: Array = []
	for t: Variant in list:
		if t is Dictionary and _room_id(t) == ("" if scene_id == "out" else scene_id):
			out.append(t)
	return out


static func _room_id(trace: Dictionary) -> String:
	return "" if trace.get("room")==null else String(trace["room"])


func _hash2(a: int, b: int) -> float:
	var h:=_int32(float(a)*374761393+float(b)*668265263)^0x5bf03635
	h=_int32(float(h^(h>>13))*1274126177)
	return ((h^(h>>16))&0xffffffff)/4294967295.0


func _int32(value: float) -> int:
	var n:=int(fmod(value,4294967296.0))&0xffffffff
	return n-4294967296 if n>=2147483648 else n


func _disc(m: Material, radius: float, x: float, z: float, y: float = 0.018) -> void:
	var cm:=_circle(radius,10)
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = m
	mi.position = Vector3(x, y, z)
	mi.rotation.x=-PI/2
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_count += 1


func _circle(radius: float, segments: int, inner: float = 0) -> ArrayMesh:
	var vertices:=PackedVector3Array()
	var indices:=PackedInt32Array()
	if inner==0:
		vertices.append(Vector3.ZERO)
		for i in segments+1: vertices.append(Vector3(cos(i*TAU/segments),sin(i*TAU/segments),0)*radius)
		for i in segments: indices.append_array([0,i+2,i+1])
	else:
		for i in segments+1:
			var p:=Vector3(cos(i*TAU/segments),sin(i*TAU/segments),0)
			vertices.append(p*inner)
			vertices.append(p*radius)
		for i in segments: indices.append_array([i*2,i*2+2,i*2+1,i*2+1,i*2+2,i*2+3])
	var arrays:=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh


func _leftover(t: Dictionary, idx: int, room: Variant, dark: Material, wet: Material, chalk: Material) -> void:
	var p := CampusGeometry.to_scene(room, Vector2(float(t.get("x", 0.0)), float(t.get("y", 0.0))))
	var pale := _mat(Color("#b8b2a0"), 0.85)
	match String(t["k"]):
		"puddle":
			for j in 6:
				_disc(wet, 0.5 + _hash2(j, idx) * 0.9, p.x + (_hash2(idx, j) - 0.5) * 7.0, p.y + (_hash2(j + 3, idx) - 0.5) * 7.0)
		"stain":
			for q: Dictionary in t.get("pts", []):
				var sp := CampusGeometry.to_scene(room, Vector2(float(q["x"]), float(q["y"])))
				_disc(wet, 0.7, sp.x, sp.y)
				_box(_mat(Color("#2a2420"), 0.6), 0.9, 0.01, 0.7, sp.x, 2.985, sp.y)
		"chalkring":
			for j in 30:
				if _hash2(idx, j) < 0.3:
					continue
				var ra := float(j) / 30.0 * 6.283
				_flat(chalk, 0.28, 0.05, p.x + cos(ra) * 2.1, p.y + sin(ra) * 2.1, -ra + PI / 2.0)
			for j in 4:
				var ca := float(j) / 4.0 * 6.283 + 0.6
				_box(pale, 0.12, 0.03, 0.12, p.x + cos(ca) * 1.6, 0.03, p.y + sin(ca) * 1.6)
		"moths":
			for j in 40:
				_flat(dark, 0.05, 0.03, p.x + (_hash2(idx, j) - 0.5) * 5.0, p.y + (_hash2(j, idx + 7) - 0.5) * 5.0, _hash2(j, 3) * 6.0)
		"rows":
			for j in 6:
				_footprints(dark, p.x - 5.0 + float(j) * 2.0, p.y - 2.0, PI / 2.0, 7, 0.62)
		"feet":
			_footprints(dark, p.x, p.y, float(t.get("a", 0.0)), 9, 0.6)
		"paper":
			for j in 7:
				_flat(pale, 0.18, 0.12, p.x + (_hash2(idx, j) - 0.5) * 1.6, p.y + (_hash2(j, idx) - 0.5) * 1.6, _hash2(j, idx + 1) * 6.0)
			_flat(_mat(Color("#3a1210"), 0.7), 0.16, 0.012, p.x, p.y, 0.4, 0.02)
		"handprint":
			for j in 3:
				_flat(wet, 0.14, 0.18, p.x + float(j) * 0.35, p.y + float(j % 2) * 0.2, 0.3 * float(j))
		"fence":
			for j in 6:
				_box(dark, 0.02, 0.18, 0.14, p.x + 0.02, 0.6 + _hash2(idx, j) * 0.7, p.y - 1.5 + float(j) * 0.6)
		"bowl":
			_box(_mat(Color("#e8e2d4"), 1.0), 0.16, 0.08, 0.16, p.x + 0.6, 0.04, p.y)
			_box(_mat(Color("#3a2a1a"), 1.0), 0.012, 0.2, 0.012, p.x + 0.6, 0.14, p.y)
		"dust":
			for j in 14:
				_flat(chalk, 0.08, 0.08, p.x + (_hash2(idx, j) - 0.5) * 1.4, p.y + (_hash2(j, idx) - 0.5) * 1.4, 0.0)
		"cup":
			var gy:=float(ground_height.call(p.x,p.y)) if ground_height.is_valid() else 0.0
			var mi:=Node3D.new()
			mi.add_child(FallingProps.model("cup",CampusData.tier))
			mi.rotation_order=EULER_ORDER_XYZ
			mi.position = Vector3(p.x, gy+.07, p.y)
			mi.rotation = Vector3(0.0, _hash2(idx, 7) * 6.28, PI / 2.0)
			mi.scale=Vector3(2.2,2.2,1.7)
			add_child(mi)
			var la := _hash2(idx, 11) * 6.28
			var lid:=Node3D.new()
			lid.add_child(FallingProps.model("lid",CampusData.tier))
			lid.rotation_order=EULER_ORDER_XYZ
			lid.scale=Vector3.ONE*2.2
			lid.rotation=Vector3(0,la,PI/2)
			lid.position=Vector3(p.x+cos(la+1.2)*.9,gy+.0462*2.2,p.y+sin(la+1.2)*.9)
			add_child(lid)
			_count += 2
			_flat(_mat(Color("#d8d4cc"), 0.5), 0.22, 0.18, p.x + 0.05, p.y - 0.02, _hash2(idx, 3) * 3.0, gy+.014)


func build(scene_id: String, room: Variant, dynamic: Array = []) -> void:
	for c in get_children():
		(c as Node3D).hide()
		c.queue_free()
	_count = 0
	var dark := _mat(Color("#101418"), 0.55)
	var wet := _mat(Color("#18242a"), 0.62)
	var chalk := _mat(Color("#d8d4cc"), 0.35)
	for t: Dictionary in for_scene(scene_id):
		var p: Vector2
		if t.has("c"):
			p = CampusGeometry.to_scene(room, Vector2(float(room["ox"]) + float(t["c"]) * float(room["tw"]), float(room["oy"]) + float(t["r"]) * float(room["th"])))
		else:
			p = CampusGeometry.to_scene(null, Vector2(float(t["x"]), float(t["y"])))
		var h := 0.0
		match String(t["k"]):
			"scratch":
				var sm := _mat(Color("#3a302c"), 0.85)
				for j in 5:
					_box(sm, 0.012, 0.9 - float(j) * 0.08, 0.02, p.x, 1.1 + float(j) * 0.03, p.y + float(j) * 0.07)
			"drag":
				for j in 26:
					_flat(dark, 0.12, 0.42, p.x + float(j) * 0.55, p.y - 0.2, PI / 2.0)
					_flat(dark, 0.12, 0.42, p.x + float(j) * 0.55, p.y + 0.2, PI / 2.0)
			"wetfeet":
				_footprints(dark, p.x, p.y, PI, 10, 0.58)
			"outline":
				var seg := [[0.0, 0.95, 0.5, 0.0], [0.0, 0.1, 0.06, 0.5], [-0.22, -0.4, 0.06, 0.9], [0.22, -0.4, 0.06, 0.9], [-0.42, 0.45, 0.06, 0.7], [0.42, 0.45, 0.06, 0.7]]
				for s: Array in seg:
					_flat(chalk, float(s[2]) if float(s[2]) != 0.0 else 0.06, float(s[3]) if float(s[3]) != 0.0 else 0.06, p.x + float(s[0]), p.y + float(s[1]), 0.0)
				var ring := MeshInstance3D.new()
				ring.mesh = _circle(.2,14,.16)
				ring.material_override = chalk
				ring.rotation.x=-PI/2
				ring.position = Vector3(p.x, 0.017, p.y + 1.25)
				add_child(ring)
				_count += 1
			"shoe":
				_box(_mat(Color("#e8e8e2"), 1.0), 0.11, 0.09, 0.27, p.x, 0.045, p.y, 0.7)
				_box(_mat(Color("#6a1a14"), 1.0), 0.11, 0.01, 0.27, p.x, 0.093, p.y, 0.7)
			"hands":
				var hm := _mat(Color("#8a9aa0"), 0.5)
				for j in 4:
					_box(hm, 0.14, 0.18, 0.01, p.x - 0.6 + float(j) * 0.38, 1.2 + float(j % 2) * 0.3, p.y)
		h += 0.0
	for idx in dynamic.size():
		var t: Dictionary=dynamic[idx]
		if _room_id(t) == ("" if scene_id=="out" else scene_id):
			_leftover(t,STATIC.size()+idx,room,dark,wet,chalk)
