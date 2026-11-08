class_name PortalDevice
extends Node3D
## The portal rig on the physics bench (legacy model/portal.js, portalBuild/portalApply/portalAnimate).
## A steel base with legs, two posts and clamps, a steel ring with an inner rail ring, three energy rails that close
## while charging, a copper coil, a lens in a brass mount, a vial and a battery (or empty sockets), and three layers
## inside the ring. Scene height 0.935 m is the bench top. States: base -> ready -> charge (k 0..1) -> open -> enter (k 0..1).
## Only visuals: no collision, nothing the player can touch.

const R := 0.62
const TUBE := 0.035
const RAIL := 0.53
const BASE := Vector3(1.10, 0.05, 0.50)
const TOP := 0.935

var state := "base"
var k := 0.0
var t := 0.0
var ring_y := 0.0
var self_tick := true    ## ticks itself every frame (a cutscene that drives it by progress turns this off)
var shake := true      ## the ring trembles a little while charging (off with the camera-shake setting)

var _ring: Node3D
var _rails: Array[MeshInstance3D] = []
var _rail_base: Array[float] = []
var _layers: Array[MeshInstance3D] = []
var _layer_op: Array[float] = []
var _layer_spin: Array[float] = []
var _inner: Node3D
var _glow: OmniLight3D      # a lamp 3 m inside the doorway so the far end is not black (kept from the first ring)
var _coil_mat: StandardMaterial3D
var _liquid_mat: StandardMaterial3D
var _parts := {}
var _sockets := {}
var _leds := {}
static var _tex: ImageTexture


static func lam(c: Color, e: Color = Color("#101214")) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = e
	m.roughness = 0.8
	return m


static func bas(c: Color, a: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c.r, c.g, c.b, a)
	if a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


## The swirl texture of the layers inside the door: a radial gradient with nine spiral bands.
static func swirl_texture() -> ImageTexture:
	if _tex != null:
		return _tex
	var w := 128
	var img := Image.create(w, w, false, Image.FORMAT_RGBA8)
	var c := float(w) / 2.0
	for y in w:
		for x in w:
			var d := Vector2(float(x) - c + 0.5, float(y) - c + 0.5).length() / c
			var col := Color(0.0, 0.0, 0.0, 0.0)
			if d <= 1.0:
				if d < 0.25:
					col = Color(1.0, 0.94, 0.82, 1.0).lerp(Color(0.47, 0.86, 1.0, 0.9), d / 0.25)
				elif d < 0.6:
					col = Color(0.47, 0.86, 1.0, 0.9).lerp(Color(0.35, 0.24, 0.78, 0.7), (d - 0.25) / 0.35)
				else:
					col = Color(0.35, 0.24, 0.78, 0.7).lerp(Color(0.08, 0.04, 0.16, 0.0), (d - 0.6) / 0.4)
				var a := atan2(float(y) - c + 0.5, float(x) - c + 0.5)
				var band := fposmod(a - d * 4.2 / 0.95, TAU / 9.0) / (TAU / 9.0)
				if band < 0.08 or band > 0.92:
					col = col.lerp(Color(0.7, 0.94, 1.0, minf(1.0, col.a + 0.18)), 0.5)
			img.set_pixel(x, y, col)
	_tex = ImageTexture.create_from_image(img)
	return _tex


## A tube of the given radius along a polyline.
static func tube(points: PackedVector3Array, radius: float, sides: int, closed: bool = false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := points.size()
	var rings: Array = []
	for i in n:
		var a := points[(i - 1 + n) % n] if closed else points[maxi(i - 1, 0)]
		var b := points[(i + 1) % n] if closed else points[mini(i + 1, n - 1)]
		var tn := (b - a).normalized()
		var ref := Vector3(0, 0, 1) if absf(tn.z) < 0.9 else Vector3(0, 1, 0)
		var nrm := (ref - tn * ref.dot(tn)).normalized()
		var bin := tn.cross(nrm)
		var ring: Array = []
		for s in sides:
			var ang := TAU * float(s) / float(sides)
			ring.append(points[i] + (nrm * cos(ang) + bin * sin(ang)) * radius)
		rings.append(ring)
	var last := n if closed else n - 1
	for i in last:
		var r0: Array = rings[i]
		var r1: Array = rings[(i + 1) % n]
		for s in sides:
			var s2 := (s + 1) % sides
			var v0: Vector3 = r0[s]
			var v1: Vector3 = r0[s2]
			var v2: Vector3 = r1[s2]
			var v3: Vector3 = r1[s]
			for v: Vector3 in [v0, v1, v2, v0, v2, v3]:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


static func arc_points(radius: float, a0: float, a1: float, seg: int) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in seg + 1:
		var a := lerpf(a0, a1, float(i) / float(seg))
		pts.append(Vector3(cos(a) * radius, sin(a) * radius, 0.0))
	return pts


## A flat disc in the XY plane facing +z, with polar UVs.
static func disc(radius: float, seg: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		for p: Array in [[Vector2.ZERO, Vector2(0.5, 0.5)], [Vector2(cos(a0), sin(a0)), Vector2(0.5 + 0.5 * cos(a0), 0.5 - 0.5 * sin(a0))], [Vector2(cos(a1), sin(a1)), Vector2(0.5 + 0.5 * cos(a1), 0.5 - 0.5 * sin(a1))]]:
			var q: Vector2 = p[0]
			st.set_uv(p[1])
			st.set_normal(Vector3(0, 0, 1))
			st.add_vertex(Vector3(q.x * radius, q.y * radius, 0.0))
	return st.commit()


func _mesh(parent: Node3D, m: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mesh(parent, b, mat, pos)


func _cyl(parent: Node3D, r0: float, r1: float, h: float, mat: Material, pos: Vector3, sides: int = 8) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r0
	c.bottom_radius = r1
	c.height = h
	c.radial_segments = sides
	c.rings = 1
	return _mesh(parent, c, mat, pos)


func build(seg: int = 40) -> void:
	name = "PortalDevice"
	var steel := lam(Color("#7d858d"), Color("#1a1d21"))
	var dark := lam(Color("#3e444a"))
	var copper := lam(Color("#b4703a"), Color("#24140a"))
	var brass := lam(Color("#b39246"), Color("#241c0a"))
	var rubber := lam(Color("#1b1d1f"), Color("#050505"))
	var red := lam(Color("#9a2a24"))
	var black := lam(Color("#161616"))
	var glass := bas(Color("#cfe8ef"), 0.35)
	var lens := bas(Color("#bfe7ff"), 0.55)
	var by := TOP
	_box(self, Vector3(BASE.x, BASE.y, BASE.z), steel, Vector3(0, by + BASE.y / 2.0, 0))
	_box(self, Vector3(BASE.x - 0.08, 0.012, BASE.z - 0.08), dark, Vector3(0, by + BASE.y + 0.006, 0))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_cyl(self, 0.03, 0.035, 0.02, rubber, Vector3(sx * (BASE.x / 2.0 - 0.06), by + 0.005, sz * (BASE.z / 2.0 - 0.06)))
	ring_y = by + BASE.y + 0.06 + R
	for s: float in [-1.0, 1.0]:
		_box(self, Vector3(0.05, ring_y - by - 0.05, 0.05), steel, Vector3(s * (R + 0.04), by + BASE.y + (ring_y - by - BASE.y) / 2.0, 0))
		_box(self, Vector3(0.09, 0.07, 0.08), dark, Vector3(s * (R + 0.02), ring_y, 0))
		var pin := _cyl(self, 0.012, 0.012, 0.1, brass, Vector3(s * (R + 0.02), ring_y, 0), 6)
		pin.rotation.x = PI / 2.0
	# The cable drops off the back edge of the base to the edge of the bench.
	var cab := PackedVector3Array()
	for i in 13:
		var f := float(i) / 12.0
		cab.append(Vector3(lerpf(-0.3, -0.6, f), lerpf(by + 0.05, by - 0.5, f * f), lerpf(-0.2, -0.36, minf(1.0, f * 2.0))))
	_mesh(self, tube(cab, 0.012, 5), rubber)
	# The forming ring: outer steel ring, inner guide ring.
	_ring = Node3D.new()
	_ring.name = "Ring"
	_ring.position = Vector3(0, ring_y, 0)
	add_child(_ring)
	_mesh(_ring, tube(arc_points(R, 0.0, TAU, seg * 2), TUBE, 8, true), steel)
	_mesh(_ring, tube(arc_points(R + 0.045, 0.0, TAU, seg * 2), 0.01, 4, true), dark, Vector3(0, 0, -0.03))
	for i in 8:
		var a := float(i) / 8.0 * TAU
		var f := _box(_ring, Vector3(0.05, 0.03, 0.09), dark, Vector3(cos(a) * R, sin(a) * R, 0))
		f.rotation.z = a
	# Three energy rails that close while charging.
	for i in 3:
		var rm := bas(Color("#7fe8ff"), 0.9)
		var rail := _mesh(_ring, tube(arc_points(RAIL, 0.0, TAU / 3.0 * 0.92, seg), 0.012, 4), rm, Vector3(0, 0, 0.01))
		rail.rotation.z = float(i) * TAU / 3.0 + 0.05
		rail.visible = false
		_rails.append(rail)
		_rail_base.append(rail.rotation.z)
	# The copper coil: a helix round the lower three quarters of the ring (the top is left for the lens).
	_coil_mat = lam(Color("#b4703a"), Color(0, 0, 0))
	var coil_pts := PackedVector3Array()
	var cr := R - 0.005
	var rr := 0.05
	var turns := 36.0
	for i in 261:
		var tt := float(i) / 260.0
		var a := PI * 0.18 + tt * PI * 1.64
		var b := tt * turns * TAU
		coil_pts.append(Vector3((cr + rr * cos(b)) * cos(a), (cr + rr * cos(b)) * sin(a), rr * sin(b)))
	var coil := _mesh(_ring, tube(coil_pts, 0.0065, 4), _coil_mat)
	_parts["coil"] = coil
	var lens_g := Node3D.new()
	lens_g.position = Vector3(0, R + 0.07, 0)
	_ring.add_child(lens_g)
	_mesh(lens_g, tube(arc_points(0.1, 0.0, TAU, 24), 0.018, 6, true), brass)
	var disc_lens := _cyl(lens_g, 0.095, 0.095, 0.03, lens, Vector3.ZERO, 24)
	disc_lens.rotation.x = PI / 2.0
	_parts["lens"] = lens_g
	var vial := Node3D.new()
	vial.position = Vector3(-(R + 0.12), ring_y - 0.18, 0.06)
	add_child(vial)
	_cyl(vial, 0.032, 0.032, 0.18, glass, Vector3.ZERO, 12)
	_liquid_mat = bas(Color("#6dffb0"))
	_cyl(vial, 0.027, 0.027, 0.11, _liquid_mat, Vector3(0, -0.03, 0), 12)
	_cyl(vial, 0.036, 0.036, 0.03, black, Vector3(0, 0.1, 0), 12)
	_box(vial, Vector3(0.05, 0.03, 0.06), dark, Vector3(0.03, 0, 0))
	_parts["vial"] = vial
	var bat := Node3D.new()
	bat.position = Vector3(R + 0.02, by + BASE.y + 0.09, 0.12)
	add_child(bat)
	_box(bat, Vector3(0.16, 0.18, 0.09), black, Vector3.ZERO)
	_box(bat, Vector3(0.16, 0.03, 0.092), red, Vector3(0, 0.06, 0))
	_cyl(bat, 0.012, 0.012, 0.03, red, Vector3(-0.04, 0.105, 0), 6)
	_cyl(bat, 0.012, 0.012, 0.03, black, Vector3(0.04, 0.105, 0), 6)
	for w: Array in [[-0.04, red], [0.04, black]]:
		var x0: float = w[0]
		var wp := PackedVector3Array()
		for i in 9:
			var f := float(i) / 8.0
			wp.append(Vector3(lerpf(x0, -0.17, f), lerpf(0.12, 0.36, f), lerpf(0.0, -0.03, sin(f * PI))))
		_mesh(bat, tube(wp, 0.007, 4), w[1] as Material)
	_parts["battery"] = bat
	# Empty sockets: a dark cradle where a material has not been fitted yet, a small lamp lit once the plans are complete.
	_socket("coil", _ring, Vector3(0, -R - 0.02, 0.07), dark)
	_socket("lens", _ring, Vector3(0, R + 0.02, 0.07), dark)
	_socket("vial", self, Vector3(-(R + 0.12), ring_y - 0.28, 0.06), dark)
	_socket("battery", self, Vector3(R + 0.02, by + BASE.y + 0.015, 0.12), dark)
	# Inside the door: a deep dark layer (opaque), a swirl, a pale swirl on top.
	_inner = Node3D.new()
	_inner.visible = false
	_ring.add_child(_inner)
	var specs := [[-0.10, Color("#150829"), 0.95, false], [-0.05, Color.WHITE, 0.75, true], [0.0, Color("#9fe9ff"), 0.35, true]]
	for j in specs.size():
		var sp: Array = specs[j]
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.disable_fog = true
		var c: Color = sp[1]
		if j == 0:
			m.albedo_color = c
		else:
			m.albedo_color = Color(c.r, c.g, c.b, 0.0)
			m.albedo_texture = swirl_texture()
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		var d := _mesh(_inner, disc(RAIL - 0.01, seg), m, Vector3(0, 0, float(sp[0])))
		_layers.append(d)
		_layer_op.append(float(sp[2]))
		_layer_spin.append((-1.0 if j % 2 == 1 else 1.0) * (0.3 + float(j) * 0.25))
	_glow = OmniLight3D.new()
	_glow.light_color = Color(0.7, 0.9, 1.0)
	_glow.light_energy = 1.2
	_glow.omni_range = 5.0
	_glow.position = Vector3(0, ring_y, 0.6)
	_glow.visible = false
	add_child(_glow)
	_apply()


func _socket(id: String, parent: Node3D, pos: Vector3, mat: Material) -> void:
	var s := Node3D.new()
	s.position = pos
	parent.add_child(s)
	_box(s, Vector3(0.1, 0.025, 0.08), mat, Vector3.ZERO)
	var sp := SphereMesh.new()
	sp.radius = 0.012
	sp.height = 0.024
	sp.radial_segments = 6
	sp.rings = 3
	var led := _mesh(s, sp, bas(Color("#332211")), Vector3(0.035, 0.02, 0.035))
	_leds[id] = led
	_sockets[id] = s


func _process(delta: float) -> void:
	if self_tick and visible:
		tick(delta)


func set_state(new_state: String, kk: float = 1.0) -> void:
	state = new_state
	k = clampf(kk, 0.0, 1.0)
	_apply()


func is_installed() -> bool:
	return state == "charge" or state == "open" or state == "enter"


## Which parts are in place and how bright the rails and the inside are (portalApply).
func _apply() -> void:
	var installed := is_installed()
	for id: String in ["coil", "lens", "vial", "battery"]:
		(_parts[id] as Node3D).visible = installed
		(_sockets[id] as Node3D).visible = not installed
		((_leds[id] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = Color("#ffb347") if state == "ready" else Color("#332211")
	var rail_k := clampf(k / 0.7, 0.0, 1.0) if state == "charge" else (1.0 if installed else 0.0)
	for i in _rails.size():
		var on := clampf(rail_k * 3.0 - float(i), 0.0, 1.0)
		_rails[i].visible = on > 0.02
		var mat := _rails[i].material_override as StandardMaterial3D
		mat.albedo_color = Color(0.5, 0.91, 1.0, 0.35 + 0.6 * on)
	var open_k := clampf((k - 0.6) / 0.4, 0.0, 1.0) if state == "charge" else (1.0 if (state == "open" or state == "enter") else 0.0)
	_inner.visible = open_k > 0.01
	if _glow != null:
		_glow.visible = open_k > 0.5
	_inner.scale = Vector3.ONE * (0.2 + 0.8 * open_k)
	for j in range(1, _layers.size()):
		var lm := _layers[j].material_override as StandardMaterial3D
		var base := lm.albedo_color
		lm.albedo_color = Color(base.r, base.g, base.b, minf(1.0, _layer_op[j] * open_k * (1.0 + k * 0.3 if state == "enter" else 1.0)))
	_liquid_mat.albedo_color = Color("#7dffb8") if installed else Color("#2e6a4c")


## Coil pulse, rails turning, the swirl turning, the ring trembling (portalAnimate).
func tick(dt: float) -> void:
	t += dt
	if not is_installed():
		_ring.position.x = 0.0
		return
	var pulse := 0.5 + 0.5 * sin(t * (5.0 if state == "charge" else 2.2))
	_coil_mat.emission = Color(0.45 * pulse, 0.18 * pulse, 0.05 * pulse)
	for i in _rails.size():
		if _rails[i].visible:
			_rails[i].rotation.z = _rail_base[i] + t * 0.4 * (-1.0 if i % 2 == 1 else 1.0) * (0.3 if state == "open" else 1.0)
	for i in _layers.size():
		_layers[i].rotation.z += dt * _layer_spin[i]
		if i == 2:
			var s := 1.0 + 0.03 * sin(t * 3.0)
			_layers[i].scale = Vector3(s, s, 1.0)
	_ring.position.x = (0.002 if shake else 0.0) * sin(t * 37.0) * (1.0 if state == "charge" else 0.4)


## The cell of the bench the rig stands on: the first K tile of the lab (PortalDevice.where), scene coordinates.
static func bench_spot(room: Dictionary) -> Vector2:
	var grid: Array = room["grid"]
	for r in grid.size():
		var row := String(grid[r])
		for c in row.length():
			if row.substr(c, 1) == "K":
				return CampusGeometry.to_scene(room, CampusGeometry.tile_center(room, c, r))
	return Vector2.ZERO
