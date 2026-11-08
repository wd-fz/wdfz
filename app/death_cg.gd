class_name DeathCG
extends Node
## The death scenes by cause (fx/death-cg.js, reference wd-fz.github.io@0bf508a). Each is "omen → contact /
## loss of control → the last view → closing", everything placed from the elapsed time only (the same at any frame
## rate). The props live in the "view frame": the origin at the player's feet, +z the way the player was looking at
## the moment of death, +y up (+x is on the left of the picture). The camera is the player's own: only its pitch,
## a turn and a lift change (and are put back at the end); a veil sphere on it closes the scene.
## Not every cause has a scene yet (CAUSES lists the ported ones); the others keep the screen-effect fade.

const CAUSES := ["trash", "liftdoor", "grip", "neck", "shadow", "twin"]

var on := false
var fx := ""
var k := 0.0
var dur := 3.0
var F: Node3D
var cam: Camera3D
var veil_mesh: MeshInstance3D
var shk := 1.0
var rand := RandomNumberGenerator.new()
var d: Dictionary = {}                 # per-scene state
var _player: PlayerController
var _world: Node3D
var _world_was_visible := true
var _sky: MeshInstance3D
var _base_pitch := 0.0
var _base_y := 0.0
var _cued := {}
var _flashed := {}
var _fx_cache := {}
var _ui: GameUI


static func has(cause: String) -> bool:
	return CAUSES.has(cause)


static func seg(kk: float, a: float, b: float) -> float:
	return 0.0 if kk <= a else (1.0 if kk >= b else (kk - a) / (b - a))


static func ss(kk: float, a: float, b: float) -> float:
	var x := seg(kk, a, b)
	return x * x * (3.0 - 2.0 * x)


func begin(cause: String, player: PlayerController, world: Node3D, ui: GameUI, duration: float, reduce_shake: bool = false) -> void:
	fx = cause
	dur = duration
	k = 0.0
	on = true
	_player = player
	_world = world
	_ui = ui
	cam = player.camera
	shk = 0.0 if reduce_shake else 1.0
	rand.seed = hash(cause)
	_base_pitch = cam.rotation.x
	_base_y = cam.position.y
	F = Node3D.new()
	F.name = "DeathFrame"
	F.rotation_order = EULER_ORDER_YXZ
	player.get_parent().add_child(F)
	F.global_position = Vector3(player.global_position.x, player.global_position.y, player.global_position.z)
	F.rotation.y = player.rotation.y + PI          # local +z = the gaze
	veil_mesh = null
	call("_build_" + cause)
	update(0.0)


func _exit_tree() -> void:
	_restore()


func _restore() -> void:
	if cam != null and is_instance_valid(cam):
		cam.rotation = Vector3(_base_pitch, 0.0, 0.0)
		cam.position.y = _base_y
		for c in cam.get_children():
			if c.name == "DeathVeil":
				c.queue_free()
	if _world != null and is_instance_valid(_world):
		_world.visible = _world_was_visible
	if F != null and is_instance_valid(F):
		F.queue_free()
	F = null
	if _sky != null and is_instance_valid(_sky):
		_sky.queue_free()


func tick(delta: float) -> void:
	if not on:
		return
	k += delta
	update(k)
	if k >= dur:
		finish()


func finish() -> void:
	if not on:
		return
	on = false
	_restore()


# ---- helpers (the old Ctx) ----

func _mat(col: Color, op: float = -1.0, double: bool = false, over: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col if op < 0.0 else Color(col.r, col.g, col.b, op)
	m.disable_fog = true
	if op >= 0.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if double:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if over:
		m.no_depth_test = true
		m.render_priority = 100
	return m


func put(n: Node3D, x: float, y: float, z: float, parent: Node3D = null) -> Node3D:
	n.position = Vector3(x, y, z)
	(parent if parent != null else F).add_child(n)
	return n


func mesh(m: Mesh, mat: Material, x: float, y: float, z: float, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	put(mi, x, y, z, parent)
	return mi


func box(w: float, h: float, dd: float, col: Color, op: float, x: float, y: float, z: float) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, dd)
	return mesh(bm, _mat(col, op), x, y, z)


func torus(radius: float, tube: float, mat: Material, x: float, y: float, z: float, parent: Node3D = null) -> MeshInstance3D:
	var tm := TorusMesh.new()
	tm.inner_radius = radius - tube
	tm.outer_radius = radius + tube
	return mesh(tm, mat, x, y, z, parent)


## A figure of the old build (front +z, the old rotations apply).
func fig(kind: String, col: Color, scale: float, x: float, z: float) -> Node3D:
	var g := Node3D.new()
	g.rotation_order = EULER_ORDER_YXZ
	var fm := FigureModel.make(kind, col, true, scale)
	fm.rotation.y = PI
	g.add_child(fm)
	put(g, x, 0.0, z)
	return g


## A "thing" of the old fxMesh (hand, head, bigface, smile, neckhead, bell), front +z.
func fxm(name: String, scale: float, x: float, y: float, z: float) -> Node3D:
	var g := Node3D.new()
	g.rotation_order = EULER_ORDER_YXZ
	var path := "res://assets/campus/fx/%s.glb" % name
	if ResourceLoader.exists(path):
		if not _fx_cache.has(name):
			_fx_cache[name] = load(path)
		var inst := (_fx_cache[name] as PackedScene).instantiate() as Node3D
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.disable_fog = true
		for mi: Node in inst.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = mat
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.add_child(inst)
	g.scale = Vector3.ONE * scale
	put(g, x, y, z)
	return g


## The closing: a sphere over the camera, drawn over everything.
func veil(col: Color) -> void:
	var sm := SphereMesh.new()
	sm.radius = 0.3
	sm.height = 0.6
	veil_mesh = MeshInstance3D.new()
	veil_mesh.name = "DeathVeil"
	veil_mesh.mesh = sm
	veil_mesh.material_override = _mat(col, 0.0, false, true)
	(veil_mesh.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_FRONT
	cam.add_child(veil_mesh)


func shade(v: float) -> void:
	if veil_mesh != null:
		var m := veil_mesh.material_override as StandardMaterial3D
		m.albedo_color.a = minf(0.94, v)


## Hide the scene itself; only the props of the scene are seen, against a dark sky.
func hide_world(sky: Color = Color(0.02, 0.025, 0.03)) -> void:
	_world_was_visible = _world.visible
	_world.visible = false
	_sky = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 60.0
	sm.height = 120.0
	_sky.mesh = sm
	var m := _mat(sky)
	m.cull_mode = BaseMaterial3D.CULL_FRONT
	_sky.material_override = m
	cam.add_child(_sky)


func cam_y() -> float:
	return _base_y + _lift


var _lift := 0.0


## The camera: relative to the gaze at death; the first 0.4 s goes over from the player's own pitch.
func view(kk: float, dang: float, pitch: float, lift: float) -> void:
	_lift = lift
	cam.rotation = Vector3(clampf(pitch + _base_pitch * (1.0 - ss(kk, 0.0, 0.4)), -1.45, 1.45), -dang, 0.0)
	cam.position.y = _base_y + lift


func cue(id: String, kk: float, at: float, fn: Callable) -> void:
	if kk >= at and not _cued.has(id):
		_cued[id] = true
		fn.call()


func update(kk: float) -> void:
	call("_update_" + fx, kk)


# ---- trash: the third bin. Looking up from inside: the lid shuts, a ring of light leaks round the rim, two knocks outside ----

func _build_trash() -> void:
	hide_world()
	var green := _mat(Color("#2e4a36"), -1.0, true)
	var rib := _mat(Color("#56684f"))
	var cm := CylinderMesh.new()
	cm.top_radius = 0.62
	cm.bottom_radius = 0.55
	cm.height = 1.25
	cm.cap_top = false
	cm.cap_bottom = false
	mesh(cm, green, 0.0, 0.625, 0.0)
	for i in 2:
		torus(0.6 - float(i) * 0.03, 0.018, rib, 0.0, 0.3 + float(i) * 0.7, 0.0)
	for i in 5:
		box(0.18 + float((i * 7) % 5) * 0.03, 0.04, 0.14, Color("#b8b2a6"), -1.0, float((i * 37) % 9 - 4) * 0.08, 0.03, float((i * 53) % 9 - 4) * 0.07)
	var hinge := Node3D.new()
	put(hinge, -0.62, 1.25, 0.0)
	var lm := CylinderMesh.new()
	lm.top_radius = 0.64
	lm.bottom_radius = 0.64
	lm.height = 0.05
	var lid := mesh(lm, _mat(Color("#24402c")), 0.62, 0.0, 0.0, hinge)
	lid.rotation = Vector3.ZERO
	hinge.rotation.z = 1.9
	d["hinge"] = hinge
	var lamp_m := CylinderMesh.new()
	lamp_m.top_radius = 0.45
	lamp_m.bottom_radius = 0.45
	lamp_m.height = 0.01
	d["lamp"] = mesh(lamp_m, _mat(Color("#e8e2cc")), 0.4, 3.0, 0.2)
	d["slit"] = torus(0.63, 0.008, _mat(Color("#f0e6c8"), 0.5), 0.0, 1.24, 0.0)
	veil(Color.BLACK)


func _update_trash(kk: float) -> void:
	var close := ss(kk, 0.6, 1.25)
	var kn := maxf(exp(-(kk - 1.9) * 8.0) if kk >= 1.9 else 0.0, exp(-(kk - 2.35) * 8.0) if kk >= 2.35 else 0.0)
	view(kk, 0.0, 0.95 * ss(kk, 0.0, 0.4) + 0.05 * sin(kk * 60.0) * kn * shk, -0.85 * ss(kk, 0.2, 1.0))
	(d["hinge"] as Node3D).rotation.z = 1.9 * (1.0 - close)
	(d["lamp"] as Node3D).visible = close < 0.97
	(d["slit"] as Node3D).visible = close > 0.9
	((d["slit"] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.a = (0.22 + 0.55 * kn) * (1.0 - ss(kk, 2.8, 3.4))
	cue("shut", kk, 1.2, func() -> void: _ui.cut_flash(0.0))
	shade(0.55 * ss(kk, 1.1, 1.3) * (1.0 - 0.5 * kn) + 0.4 * ss(kk, 3.0, 3.5))


# ---- liftdoor: the door that did not shut. Closed to a palm's width, quick steps outside; four fingers through the gap,
# the door pulled open bit by bit; the doorway filled; the light blinks to its rhythm and goes out; from the corner of the
# car roof: the floor lamp stays on this floor, the door shuts, nobody inside ----

const LIFT_SEG := {"a": [0.0, 0.045, 0.05, 0.01], "b": [0.025, 0.0225, 0.01, 0.045], "c": [0.025, -0.0225, 0.01, 0.045], "d": [0.0, -0.045, 0.05, 0.01],
	"e": [-0.025, -0.0225, 0.01, 0.045], "f": [-0.025, 0.0225, 0.01, 0.045], "g": [0.0, 0.0, 0.05, 0.01]}
const LIFT_DIGIT := {1: "bc", 2: "abged", 3: "abgcd", 4: "fgbc", 5: "afgcd"}


func _build_liftdoor() -> void:
	var dd := 1.15
	hide_world()
	d["D"] = dd
	var fl := mesh(QuadMesh.new(), _mat(Color("#0e1112")), 0.0, 0.002, dd - 0.8)
	(fl.mesh as QuadMesh).size = Vector2(1.6, 1.6)
	fl.rotation.x = -PI / 2.0
	box(0.04, 2.3, 1.6, Color("#5e6766"), -1.0, -0.8, 1.15, dd - 0.8)
	box(0.04, 2.3, 1.6, Color("#5e6766"), -1.0, 0.8, 1.15, dd - 0.8)
	box(1.6, 2.3, 0.04, Color("#545c5b"), -1.0, 0.0, 1.15, dd - 1.6)
	box(1.6, 0.04, 1.6, Color("#2c3231"), -1.0, 0.0, 2.32, dd - 0.8)
	box(0.35, 2.3, 0.05, Color("#5e6766"), -1.0, -0.625, 1.15, dd + 0.02)
	box(0.35, 2.3, 0.05, Color("#5e6766"), -1.0, 0.625, 1.15, dd + 0.02)
	box(0.9, 0.2, 0.05, Color("#5e6766"), -1.0, 0.0, 2.2, dd + 0.02)
	box(0.9, 0.02, 0.1, Color("#464c4b"), -1.0, 0.0, 0.01, dd + 0.04)
	d["lamp"] = box(0.6, 0.012, 0.4, Color("#d8ddd6"), -1.0, 0.0, 2.29, dd - 0.8)
	box(0.04, 0.82, 0.19, Color("#262c2e"), -1.0, -0.77, 1.42, dd - 0.4)
	box(0.16, 0.12, 0.008, Color("#070808"), -1.0, 0.0, 2.2, dd - 0.008)
	var digit: String = LIFT_DIGIT[2]
	for key: String in LIFT_SEG:
		if digit.find(key) < 0:
			continue
		var q: Array = LIFT_SEG[key]
		box(float(q[2]), float(q[3]), 0.004, Color("#ffb257"), -1.0, -float(q[0]), 2.2 + float(q[1]), dd - 0.013)
	d["leafL"] = box(0.45, 2.1, 0.03, Color("#737b7a"), -1.0, 0.225, 1.05, dd)
	d["leafR"] = box(0.45, 2.1, 0.03, Color("#737b7a"), -1.0, -0.225, 1.05, dd)
	d["out"] = box(1.6, 2.3, 0.01, Color("#a9ad9f"), -1.0, 0.0, 1.15, dd + 0.9)
	var it := fig("tall", Color("#020303"), 1.0, 0.0, dd + 0.55)
	it.rotation.y = PI
	d["it"] = it
	var fingers: Array = []
	for i in 4:
		fingers.append(box(0.13, 0.016, 0.022, Color("#6f6a63"), -1.0, 0.0, 1.27 + float(i) * 0.042, dd - 0.03))
	d["fingers"] = fingers
	veil(Color.BLACK)


func _update_liftdoor(kk: float) -> void:
	var dd := float(d["D"])
	var end := kk >= 3.55
	var gap: float
	if kk < 1.15:
		gap = 0.16 - 0.07 * ss(kk, 0.0, 1.15)
	elif kk < 1.7:
		gap = 0.09 + 0.004 * sin(kk * 47.0) * seg(kk, 1.2, 1.6)
	else:
		gap = 0.09 + 0.81 * (0.35 * ss(kk, 1.7, 1.95) + 0.65 * ss(kk, 2.15, 2.7))
	if end:
		gap = 0.9 * (1.0 - ss(kk, 3.6, 4.2))
	var half := gap / 2.0
	var reach := ss(kk, 1.15, 1.4)
	(d["leafL"] as Node3D).position.x = 0.225 + half
	(d["leafR"] as Node3D).position.x = -0.225 - half
	var i := 0
	for f: Node3D in d["fingers"]:
		f.visible = not end and kk > 1.15
		f.position = Vector3(half + 0.045 * reach - 0.004 * float(i), 1.27 + float(i) * 0.042, dd + 0.06 - 0.085 * reach)
		i += 1
	var it := d["it"] as Node3D
	it.visible = not end
	it.position.z = dd + 0.55 - 0.4 * ss(kk, 2.5, 3.2)
	it.rotation.x = -0.18 * ss(kk, 2.6, 3.2)
	var b := 1.0 - 0.85 * ss(kk, 2.0, 2.8)
	((d["out"] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = Color(0.66 * b, 0.68 * b, 0.62 * b)
	(d["out"] as Node3D).visible = not end or gap > 0.02
	(d["lamp"] as Node3D).visible = false if end else (kk < 2.9 or (kk >= 2.98 and kk < 3.06) or (kk >= 3.12 and kk < 3.3))
	if not end:
		var up := ss(kk, 2.3, 3.0)
		var jolt := seg(kk, 1.15, 1.3) * (1.0 - seg(kk, 1.3, 1.6))
		view(kk, 0.0, -0.1 + 0.48 * up + 0.03 * sin(kk * 37.0) * shk * jolt, 0.0)
		shade(0.2 + 0.72 * ss(kk, 3.25, 3.5))
	else:
		view(kk, -0.3, -0.6, 0.62)
		shade(0.94 - 0.45 * ss(kk, 3.6, 3.85) + 0.45 * ss(kk, 4.15, 4.4))


# ---- grip: hands reach up from the floor ----

func _build_grip() -> void:
	var cmesh := CylinderMesh.new()
	cmesh.top_radius = 1.0
	cmesh.bottom_radius = 1.0
	cmesh.height = 0.005
	d["stain"] = mesh(cmesh, _mat(Color("#030405"), 0.92), 0.0, 0.012, 0.0)
	var hands: Array = []
	for i in 12:
		var h := fxm("hand", 1.0, 0.0, -0.5, 0.0)
		h.set_meta("g", {"a": float(i) / 12.0 * TAU + (rand.randf() - 0.5) * 0.3, "r": 1.1 + rand.randf() * 0.9, "d": 0.55 + float((i * 5) % 12) * 0.07})
		hands.append(h)
	d["hands"] = hands
	veil(Color("#010101"))


func _update_grip(kk: float) -> void:
	var sink := ss(kk, 1.5, 3.0)
	view(kk, 0.0, -0.55 * ss(kk, 0.0, 0.6) * (1.0 - sink) + 0.3 * sink + 0.04 * sin(kk * 23.0) * shk * sink, -1.25 * sink)
	(d["stain"] as Node3D).scale = Vector3(1, 1, 1) * (0.15 + 2.4 * ss(kk, 0.0, 1.4))
	var reach := ss(kk, 1.5, 2.6)
	var end := ss(kk, 2.6, 3.2)
	var cy := cam_y()
	var i := 0
	for h: Node3D in d["hands"]:
		var g: Dictionary = h.get_meta("g")
		var up := ss(kk, float(g["d"]), float(g["d"]) + 0.5)
		var rad := float(g["r"]) * (1.0 - reach * 0.6)
		h.visible = kk > float(g["d"])
		h.position = Vector3(cos(float(g["a"])) * rad, -0.4 + up * 0.75 + reach * 0.7, sin(float(g["a"])) * rad)
		if i < 3 and end > 0.0:
			h.position = h.position.lerp(Vector3(float(i - 1) * 0.16, cy - 0.08, 0.32), end)
		h.rotation.y = atan2(-h.position.x, -h.position.z)
		h.rotation.x = -0.9 * (1.0 - up) - 0.6 * reach
		i += 1
	shade(0.9 * ss(kk, 2.8, 3.2))


# ---- neck: the passer-by beyond the wall, the neck longer and longer, bending over the wall top ----

func _build_neck() -> void:
	box(7, 2.3, 0.3, Color("#4a4540"), -1.0, 0.0, 1.15, 2.4)
	box(7.1, 0.1, 0.42, Color("#6a655d"), -1.0, 0.0, 2.33, 2.4)
	var flesh := _mat(Color("#7c302c"))
	var segs: Array = []
	for i in 12:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.07
		cm.bottom_radius = 0.08
		cm.height = 1.0
		cm.radial_segments = 7
		segs.append(mesh(cm, flesh, 0.0, 1.6, 2.8))
	d["segs"] = segs
	d["head"] = fxm("neckhead", 1.0, 0.0, 2.1, 2.8)
	veil(Color("#050101"))


func _update_neck(kk: float) -> void:
	var peek := ss(kk, 0.0, 0.5)
	var rise := ss(kk, 0.5, 1.6)
	var bend := ss(kk, 1.6, 2.6)
	var end := ss(kk, 2.6, 3.4)
	var lift := 1.3 * end
	var cy := _base_y + lift
	var top := Vector3(0.0, 2.1 + 0.35 * peek + 2.6 * rise, 2.8)
	var near := Vector3(0.0, cy + 0.02, 0.75 - 0.2 * end)
	var hp := top.lerp(near, bend)
	hp.y += sin(bend * PI) * 0.9
	var head := d["head"] as Node3D
	head.position = hp
	head.scale = Vector3.ONE * (1.0 + 0.3 * bend + 0.35 * end)
	head.rotation.y = atan2(-hp.x, -hp.z) * bend + PI * (1.0 - bend)
	head.rotation.x = 0.3 * bend
	var base := Vector3(0.0, 1.6, 2.8)
	var ctrl := Vector3(0.0, maxf(top.y, hp.y) + 0.6 * bend, 2.8 - 0.2 * bend)
	var prev := base
	var n: int = (d["segs"] as Array).size()
	var i := 0
	for s: MeshInstance3D in d["segs"]:
		var t := float(i + 1) / float(n)
		var a := (1.0 - t) * (1.0 - t)
		var b := 2.0 * (1.0 - t) * t
		var dd := t * t
		var pt := Vector3(base.x * a + ctrl.x * b + hp.x * dd, base.y * a + ctrl.y * b + hp.y * dd, base.z * a + ctrl.z * b + hp.z * dd)
		var dir := pt - prev
		var len := maxf(dir.length(), 0.001)
		var mid := prev + dir * 0.5
		var y_axis := dir / len
		var x_axis := y_axis.cross(Vector3.FORWARD if absf(y_axis.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT).normalized()
		var z_axis := x_axis.cross(y_axis).normalized()
		s.transform = Transform3D(Basis(x_axis, y_axis * len, z_axis), mid)
		s.visible = kk > 0.5
		prev = pt
		i += 1
	var look := atan2(hp.y - cy, maxf(0.3, hp.z))
	view(kk, 0.0, look * (1.0 - end), lift)
	shade(0.9 * ss(kk, 3.0, 3.4))


# ---- shadow: the shadow a beat behind, finally standing up off the floor, walking into you ----

func _build_shadow() -> void:
	var s := fig("person", Color("#020304"), 1.0, 0.0, 0.35)
	s.rotation.y = PI
	d["sh"] = s
	veil(Color.BLACK)


func _update_shadow(kk: float) -> void:
	var stretch := seg(kk, 0.0, 0.8)
	var stand := ss(kk, 0.8, 1.6)
	var walk := ss(kk, 1.6, 2.6)
	var end := ss(kk, 2.6, 3.2)
	var o := d["sh"] as Node3D
	o.rotation.x = -PI / 2.0 * (1.0 - stand)
	o.scale = Vector3(1.0, 1.0 + 0.6 * stretch * (1.0 - stand), 0.04 + 0.96 * stand) * (1.0 + 0.15 * end)
	o.position.x = 0.12 * sin(maxf(0.0, kk - 0.25) * 3.0) * (1.0 - stand)
	o.position.z = 0.35 + 1.6 * stand - 1.2 * walk - 0.6 * end
	view(kk, 0.0, -0.6 * ss(kk, 0.0, 0.5) * (1.0 - stand) - 0.05 * stand, 0.0)
	shade(0.92 * ss(kk, 2.8, 3.2))


# ---- twin: another you walks from far away, stops an arm's length off, bends to look, then walks into you ----

func _build_twin() -> void:
	var t := fig("person", Color("#0b0d10"), 1.0, 0.0, 5.5)
	t.rotation.y = PI
	d["tw"] = t
	veil(Color.BLACK)


func _update_twin(kk: float) -> void:
	var walk := ss(kk, 0.8, 2.0)
	var reach := ss(kk, 2.0, 2.6)
	var end := ss(kk, 2.6, 3.0)
	var z := 5.5 - 4.3 * walk - 0.3 * reach - 0.55 * end
	var t := d["tw"] as Node3D
	t.position = Vector3(0.0, 0.04 * absf(sin(kk * 7.0)) * seg(kk, 0.8, 2.0) * (1.0 - seg(kk, 1.9, 2.0)), z)
	t.rotation.z = 0.14 * ss(kk, 0.2, 0.8) * (1.0 - end)
	t.rotation.x = 0.22 * reach
	view(kk, 0.0, -0.04, 0.0)
	shade(0.92 * ss(kk, 2.7, 3.1))
