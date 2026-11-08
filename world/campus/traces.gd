class_name Traces
extends Node3D
## The traces that are always there (fx/traces.js TRACE_STATIC, reference wd-fz.github.io@0bf508a): marks of things that
## happened before you came — scratches by the toilet door, two drag marks in the garage, wet footprints at the dormitory
## stairs (only the way in), a chalk outline on the roof, a white sneaker by the sports ground, hand prints on the lab glass
## (pressed from outside). Flat, unlit, no collision. (The ones an anomaly leaves behind are not ported: docs/plan/笑脸与幻觉.md.)

const STATIC := [
	{"k": "scratch", "room": "teach1", "c": 56.98, "r": 17.2},
	{"k": "drag", "room": "garage1", "c": 40.0, "r": 13.5},
	{"k": "wetfeet", "room": "dorm1", "c": 38.0, "r": 7.5},
	{"k": "outline", "room": "teach6", "c": 20.0, "r": 6.0},
	{"k": "shoe", "room": "", "x": 288.0, "y": 428.0},
	{"k": "hands", "room": "lab1", "c": 24.0, "r": 16.01}]

var _count := 0


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
	return m


func _box(m: Material, w: float, h: float, d: float, x: float, y: float, z: float, rot: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
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


func build(scene_id: String, room: Variant) -> void:
	for c in get_children():
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
				_footprints(wet, p.x, p.y, PI, 10, 0.58)
			"outline":
				var seg := [[0.0, 0.95, 0.5, 0.0], [0.0, 0.1, 0.06, 0.5], [-0.22, -0.4, 0.06, 0.9], [0.22, -0.4, 0.06, 0.9], [-0.42, 0.45, 0.06, 0.7], [0.42, 0.45, 0.06, 0.7]]
				for s: Array in seg:
					_flat(chalk, float(s[2]) if float(s[2]) != 0.0 else 0.06, float(s[3]) if float(s[3]) != 0.0 else 0.06, p.x + float(s[0]), p.y + float(s[1]), 0.0)
				var ring := MeshInstance3D.new()
				var tm := TorusMesh.new()
				tm.inner_radius = 0.16
				tm.outer_radius = 0.2
				ring.mesh = tm
				ring.material_override = chalk
				ring.scale = Vector3(1, 0.02, 1)
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
