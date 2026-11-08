class_name DeathCG
extends Node
## The death scenes by cause (fx/death-cg.js, reference wd-fz.github.io@0bf508a). Each is "omen → contact /
## loss of control → the last view → closing", everything placed from the elapsed time only (the same at any frame
## rate). The props live in the "view frame": the origin at the player's feet, +z the way the player was looking at
## the moment of death, +y up (+x is on the left of the picture). The camera is the player's own: only its pitch,
## a turn and a lift change (and are put back at the end); a veil sphere on it closes the scene.
## Not every cause has a scene yet (CAUSES lists the ported ones); the others keep the screen-effect fade.

const CAUSES := ["trash", "liftdoor", "crowd", "grip", "neck", "shadow", "twin", "shatter", "drown", "water", "freeze", "stare", "voice", "bell", "follow", "deep", "floor", "ring", "loop", "lamps", "laugh", "swarm", "gaze", "window_gaze", "paper_sender", "misread", "campus_fall", "void", "abyss"]
## Scenes that carry their own length (seconds) when the cause is not one of StoryModule.DURATIONS.
const LENGTH := {"window_gaze": 7.0, "paper_sender": 8.0, "misread": 4.1, "campus_fall": 6.0}

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
var _restored := true
var sound_output: Callable
var audio: AudioFx  ## set by the caller; the beat sounds of the scenes (SFX.door, sting, ...) go through it


static func has(cause: String) -> bool:
	return CAUSES.has(cause)


static func duration(cause: String, fallback: float) -> float:
	return float(LENGTH.get(cause, fallback))


static func seg(kk: float, a: float, b: float) -> float:
	return 0.0 if kk <= a else (1.0 if kk >= b else (kk - a) / (b - a))


static func ss(kk: float, a: float, b: float) -> float:
	var x := seg(kk, a, b)
	return x * x * (3.0 - 2.0 * x)


func begin(cause: String, player: PlayerController, world: Node3D, ui: GameUI, duration: float, reduce_shake: bool = false, camera_override: Camera3D = null) -> void:
	_restored = false
	fx = cause
	dur = duration
	k = 0.0
	on = true
	_player = player
	_world = world
	_ui = ui
	cam = player.camera if camera_override == null else camera_override
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
	if _restored:
		return
	_restored = true
	if cam != null and is_instance_valid(cam):
		cam.rotation = Vector3(_base_pitch, 0.0, 0.0)
		cam.position.y = _base_y
		if is_instance_valid(veil_mesh):
			veil_mesh.queue_free()
	veil_mesh = null
	if _world != null and is_instance_valid(_world):
		_world.visible = _world_was_visible
	if F != null and is_instance_valid(F):
		F.queue_free()
	F = null
	if _sky != null and is_instance_valid(_sky):
		_sky.queue_free()
	_sky = null


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
func fig(kind: String, col: Color, scale: float, x: float, z: float, over: bool = false) -> Node3D:
	var g := Node3D.new()
	g.rotation_order = EULER_ORDER_YXZ
	var fm := FigureModel.make(kind, col, true, scale)
	fm.rotation.y = PI
	g.add_child(fm)
	if over:
		for mi: Node in fm.find_children("*", "MeshInstance3D", true, false):
			var m := (mi as MeshInstance3D).material_override as StandardMaterial3D
			if m != null:
				m.no_depth_test = true
				m.render_priority = 101
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


## Many small things drawn at once: a MultiMesh of count instances, placed each frame with set_i.
func inst(m: Mesh, mat: Material, count: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = m
	mm.instance_count = count
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-50, -50, -50), Vector3(100, 100, 100))
	put(mi, 0.0, 0.0, 0.0)
	return mi


## Place instance i; a scale of 0 hides it.
func set_i(im: MultiMeshInstance3D, i: int, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> void:
	im.multimesh.set_instance_transform(i, Transform3D(Basis.from_euler(rot, EULER_ORDER_XYZ).scaled(scl), pos))


func disc(radius: float, col: Color, op: float, x: float, y: float, z: float, sides: int = 24) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 0.004
	cm.radial_segments = sides
	cm.rings = 1
	return mesh(cm, _mat(col, op, true), x, y, z)


func cam_y() -> float:
	return _base_y + _lift


var _lift := 0.0


## The camera: relative to the gaze at death; the first 0.4 s goes over from the player's own pitch.
func view(kk: float, dang: float, pitch: float, lift: float) -> void:
	_lift = lift
	cam.rotation = Vector3(clampf(pitch + _base_pitch * (1.0 - ss(kk, 0.0, 0.4)), -1.45, 1.45), -dang, 0.0)
	cam.position.y = _base_y + lift


## One beat sound (the old SFX.* calls inside the scenes). Silent when no audio is attached (tests).
func snd(sound_id: String, opts: Dictionary = {}) -> void:
	if sound_output.is_valid():
		sound_output.call(sound_id, opts)
	elif audio != null and is_instance_valid(audio):
		audio.play(sound_id, opts)


func cue(id: String, kk: float, at: float, fn: Callable) -> void:
	if kk >= at and not _cued.has(id):
		_cued[id] = true
		fn.call()


func update(kk: float) -> void:
	call("_update_" + fx, kk)


func _build_crowd() -> void:
	CrowdDeath.build(self)


func _update_crowd(kk: float) -> void:
	CrowdDeath.update(self,kk)


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
	cue("k1", kk, 1.9, func() -> void: snd("foley.door"))
	cue("k2", kk, 2.35, func() -> void: snd("foley.door"))
	var close := ss(kk, 0.6, 1.25)
	var kn := maxf(exp(-(kk - 1.9) * 8.0) if kk >= 1.9 else 0.0, exp(-(kk - 2.35) * 8.0) if kk >= 2.35 else 0.0)
	view(kk, 0.0, 0.95 * ss(kk, 0.0, 0.4) + 0.05 * sin(kk * 60.0) * kn * shk, -0.85 * ss(kk, 0.2, 1.0))
	(d["hinge"] as Node3D).rotation.z = 1.9 * (1.0 - close)
	(d["lamp"] as Node3D).visible = close < 0.97
	(d["slit"] as Node3D).visible = close > 0.9
	((d["slit"] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.a = (0.22 + 0.55 * kn) * (1.0 - ss(kk, 2.8, 3.4))
	cue("shut", kk, 1.2, func() -> void:
		_ui.cut_flash(0.0)
		snd("foley.door"))
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
	cue("grab", kk, 1.5, func() -> void: snd("threat.sting"))
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
	cue("in", kk, 2.6, func() -> void: snd("foley.vanish"))
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


# ---- shatter: the bike-shed bells ring together and burst one by one; the shards hang round you, then drive in ----

func _build_shatter() -> void:
	var metal := _mat(Color("#9a9890"))
	var dome := SphereMesh.new()
	dome.radius = 0.08
	dome.height = 0.08
	dome.is_hemisphere = true
	var bells: Array = []
	var shards: Array = []
	for q in 8:
		box(0.5, 0.03, 0.03, Color("#0b0c0d"), -1.0, -2.1 + float(q) * 0.6, 0.98, 2.0 + absf(float(q) - 3.5) * 0.25)
	var sg := SphereMesh.new()
	sg.radius = 0.04
	sg.height = 0.08
	sg.radial_segments = 4
	sg.rings = 2
	d["shardIM"] = inst(sg, _mat(Color("#c8c8c0")), 40)
	for i in 8:
		var x := -2.1 + float(i) * 0.6
		var z := 2.0 + absf(float(i) - 3.5) * 0.25
		var bl := mesh(dome, metal, x + 0.18, 1.0, z)
		bl.set_meta("b", {"x": x + 0.18, "z": z, "t": 1.0 + float((i * 3) % 8) * 0.07})
		bells.append(bl)
		for j in 5:
			shards.append({"b": i, "az": (rand.randf() - 0.5) * 2.4, "el": (rand.randf() - 0.5) * 1.2, "rad": 0.55 + rand.randf() * 0.25, "spin": 2.0 + rand.randf() * 5.0,
				"ox": (rand.randf() - 0.5) * 0.3, "oy": rand.randf() * 0.3})
	d["bells"] = bells
	d["shards"] = shards
	veil(Color("#050505"))


func _update_shatter(kk: float) -> void:
	view(kk, 0.0, -0.1 * ss(kk, 0.0, 0.4) + 0.03 * sin(kk * 40.0) * shk * seg(kk, 1.0, 1.8) * (1.0 - seg(kk, 1.8, 2.2)), 0.0)
	var cy := cam_y()
	var cl := ss(kk, 2.6, 3.2)
	var i := 0
	for bl: MeshInstance3D in d["bells"]:
		var b: Dictionary = bl.get_meta("b")
		var ring := 0.3 + seg(kk, 0.0, 1.0)
		bl.position.x = float(b["x"]) + 0.015 * sin(kk * 60.0 + float(i)) * ring
		bl.visible = kk < float(b["t"])
		i += 1
	i = 0
	for u: Dictionary in d["shards"]:
		var bl: Dictionary = (d["bells"][int(u["b"])] as Node3D).get_meta("b")
		var f := ss(kk, float(bl["t"]), float(bl["t"]) + 0.9)
		var rad := float(u["rad"]) * (1.0 - 0.78 * cl)
		var tx := sin(float(u["az"])) * cos(float(u["el"])) * rad
		var ty := cy + sin(float(u["el"])) * rad
		var tz := cos(float(u["az"])) * cos(float(u["el"])) * rad
		var hx := float(bl["x"]) + float(u["ox"])
		var hy := 1.0 + float(u["oy"])
		var hz := float(bl["z"])
		var spin := float(u["spin"])
		set_i(d["shardIM"], i, Vector3(hx + (tx - hx) * f, hy + (ty - hy) * f + sin(f * PI) * 0.3, hz + (tz - hz) * f),
			Vector3(kk * spin * (1.0 - f * 0.8), kk * spin * 0.7 * (1.0 - f * 0.8), 0.0), Vector3.ONE if kk >= float(bl["t"]) else Vector3.ZERO)
		i += 1
	if kk >= 1.0 and not _flashed.has("crack"):
		_flashed["crack"] = true
		_ui.cut_flash(0.25)
	elif kk >= 1.1:
		_ui.cut_flash(0.0)
	shade(0.9 * ss(kk, 2.95, 3.2))


# ---- drown: the rain does not stop, water rises from the feet, over the head, down ----

func _build_drown() -> void:
	var rain: Array = []
	var bm := BoxMesh.new()
	bm.size = Vector3(0.012, 0.5, 0.012)
	d["rainIM"] = inst(bm, _mat(Color("#9fb6c4"), 0.5), 80)
	for i in 80:
		var a := rand.randf() * TAU
		var dd := 0.6 + rand.randf() * 4.0
		rain.append({"x": cos(a) * dd, "z": absf(sin(a)) * dd + 0.4, "off": rand.randf() * 5.0})
	d["rain"] = rain
	var pm := PlaneMesh.new()
	pm.size = Vector2(16, 16)
	d["water"] = mesh(pm, _mat(Color("#1d2c35"), 0.8, true), 0.0, 0.0, 0.0)
	var sm := SphereMesh.new()
	sm.radius = 0.025
	sm.height = 0.05
	sm.radial_segments = 6
	sm.rings = 4
	d["bubIM"] = inst(sm, _mat(Color("#a8c8d8"), 0.6), 24)
	var bub: Array = []
	for i in 24:
		bub.append({"x": (rand.randf() - 0.5) * 0.8, "z": 0.4 + rand.randf() * 0.8, "off": rand.randf() * 1.4})
	d["bub"] = bub
	veil(Color("#081218"))


func _update_drown(kk: float) -> void:
	var sink_t := ss(kk, 2.4, 3.4)
	view(kk, 0.0, -0.35 * ss(kk, 0.2, 1.4) * (1.0 - ss(kk, 1.8, 2.3)) + 0.75 * ss(kk, 1.9, 2.8), -0.9 * sink_t)
	var cy := cam_y()
	var lv := 0.5 * ss(kk, 0.3, 1.0) + 0.9 * ss(kk, 1.0, 1.8) + (_base_y + 0.45 - 1.4) * ss(kk, 1.8, 2.4) + 0.6 * sink_t
	(d["water"] as Node3D).position.y = lv
	var i := 0
	for o: Dictionary in d["rain"]:
		var y := 4.5 - fmod(kk * 9.0 + float(o["off"]), 5.0)
		set_i(d["rainIM"], i, Vector3(float(o["x"]), y, float(o["z"])), Vector3.ZERO, Vector3.ONE if y > lv else Vector3.ZERO)
		i += 1
	i = 0
	for b: Dictionary in d["bub"]:
		set_i(d["bubIM"], i, Vector3(float(b["x"]), cy - 0.3 + fmod((kk - 2.2) * 1.3 + float(b["off"]), 1.4), float(b["z"])), Vector3.ZERO, Vector3.ONE if kk > 2.2 else Vector3.ZERO)
		i += 1
	shade(0.6 * ss(kk, 2.2, 2.6) + 0.3 * ss(kk, 3.0, 3.4))


# ---- water: the ceiling seeps; the stain spreads, the drips come faster, a blister bulges down onto the face ----

func _build_water() -> void:
	d["stain"] = disc(1.0, Color("#4a5a52"), 0.85, 0.0, 2.88, 1.0)
	var drips: Array = []
	var bm := BoxMesh.new()
	bm.size = Vector3(0.025, 0.08, 0.025)
	var dm := _mat(Color("#a8c8d4"), 0.95)
	for i in 16:
		var n := mesh(bm, dm, (rand.randf() - 0.5) * 1.6, 2.8, 0.4 + rand.randf() * 1.4)
		n.set_meta("off", rand.randf())
		drips.append(n)
	d["drips"] = drips
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.is_hemisphere = true
	var bulge := mesh(sm, _mat(Color("#3a5560"), 0.85, true), 0.0, 2.9, 1.0)
	bulge.rotation.x = PI           # the lower half
	d["bulge"] = bulge
	veil(Color("#0b1820"))


func _update_water(kk: float) -> void:
	var spread := ss(kk, 0.0, 1.0)
	var sag := ss(kk, 1.0, 2.2)
	var wrap := ss(kk, 2.2, 3.0)
	view(kk, 0.0, 0.7 * ss(kk, 0.1, 0.9), -0.15 * wrap)
	(d["stain"] as Node3D).scale = Vector3(1, 1, 1) * (0.3 + 1.6 * spread)
	for n: MeshInstance3D in d["drips"]:
		var rate := 1.4 + 1.6 * seg(kk, 0.4, 2.2)
		n.position.y = 2.85 - fmod(kk * rate + float(n.get_meta("off")), 1.0) * 2.8
		n.visible = kk > 0.2
	var b := d["bulge"] as Node3D
	b.position.z = 1.0 - 0.95 * sag
	b.scale = Vector3(0.3 + 0.9 * sag + 0.4 * wrap, 0.05 + 0.8 * sag + 0.6 * wrap, 0.3 + 0.9 * sag + 0.4 * wrap)
	shade(0.88 * ss(kk, 2.8, 3.4))


# ---- freeze: the cold store. White breath, frost on the floor, icicles growing in from the sides, frost over the view ----

func _build_freeze() -> void:
	d["frost"] = disc(4.0, Color("#dfeef5"), 0.0, 0.0, 0.015, 0.0, 32)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.07
	cone.height = 1.0
	cone.radial_segments = 5
	d["spikeIM"] = inst(cone, _mat(Color("#cfe4ee"), 0.85), 30)
	var spikes: Array = []
	for i in 30:
		spikes.append({"a": float(i) / 30.0 * TAU + (rand.randf() - 0.5) * 0.2, "r": 2.4 + rand.randf() * 1.2, "h": 0.6 + rand.randf() * 1.4, "d": rand.randf() * 0.6})
	d["spikes"] = spikes
	var puffs: Array = []
	var pm := SphereMesh.new()
	pm.radius = 1.0
	pm.height = 2.0
	pm.radial_segments = 10
	pm.rings = 6
	for i in 3:
		puffs.append(mesh(pm, _mat(Color("#eef4f6"), 0.0), 0.0, 0.0, 0.0))
	d["puffs"] = puffs
	var panes: Array = []
	for i in 8:
		var pn := disc(0.2 + rand.randf() * 0.12, Color("#d8eaf2"), 0.45, 0.0, 0.0, 0.0, 7)
		pn.set_meta("a", float(i) / 8.0 * TAU + rand.randf() * 0.3)
		panes.append(pn)
	d["panes"] = panes
	veil(Color("#c8dce4"))


func _update_freeze(kk: float) -> void:
	var kneel := ss(kk, 1.8, 3.0)
	view(kk, 0.0, -0.12 - 0.2 * kneel + 0.015 * sin(kk * 31.0) * shk * seg(kk, 0.5, 1.8) * (1.0 - seg(kk, 2.2, 2.8)), -0.5 * kneel)
	var cy := cam_y()
	var grow := ss(kk, 0.8, 2.4)
	var cover := ss(kk, 2.0, 3.3)
	((d["frost"] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.a = 0.22 * ss(kk, 0.0, 1.2)
	var i := 0
	for u: Dictionary in d["spikes"]:
		var g := ss(kk, 0.8 + float(u["d"]), 1.8 + float(u["d"]))
		var rad := float(u["r"]) * (1.0 - 0.6 * grow)
		var a := float(u["a"])
		set_i(d["spikeIM"], i, Vector3(cos(a) * rad, float(u["h"]) * g * 0.5, sin(a) * rad), Vector3(0.25 * sin(a), 0.0, -0.25 * cos(a)), Vector3(1.0, maxf(0.02, float(u["h"]) * g), 1.0))
		i += 1
	i = 0
	for p: MeshInstance3D in d["puffs"]:
		var ph := fmod(kk + float(i) * 0.37, 1.1) / 1.1
		p.position = Vector3(0.05 * sin(float(i) * 2.0), cy - 0.2 + ph * 0.08, 0.4 + ph * 0.35)
		p.scale = Vector3.ONE * (0.012 + 0.04 * ph)
		(p.material_override as StandardMaterial3D).albedo_color.a = 0.22 * (1.0 - ph) * (1.0 - seg(kk, 2.2, 2.8))
		i += 1
	for pn: MeshInstance3D in d["panes"]:
		var rr := 0.62 - 0.38 * cover
		var a2 := float(pn.get_meta("a"))
		pn.position = Vector3(cos(a2) * rr, cy + sin(a2) * rr * 0.6, 0.32)
		pn.rotation = Vector3(PI / 2.0, 0.0, 0.0)
		pn.visible = cover > 0.0
	shade(0.85 * ss(kk, 2.9, 3.4))


# ---- stare: everyone turns round. Rows of classmates sit with their backs to you; the heads turn one by one, the necks stretch, they lean into your face ----

func _build_stare() -> void:
	var spots: Array = []
	for i in 3:
		for j in 5:
			spots.append({"x": -1.6 + float(j) * 0.8 + (rand.randf() - 0.5) * 0.1, "z": 1.5 + float(i), "i": i, "j": j})
	var heads: Array = []
	for p: Dictionary in spots:
		box(0.44, 0.5, 0.26, Color("#090a0b"), -1.0, float(p["x"]), 0.95, float(p["z"]))
		box(0.42, 0.04, 0.4, Color("#1a140e"), -1.0, float(p["x"]), 0.46, float(p["z"]) - 0.05)
		var h := fxm("head", 1.25, float(p["x"]), 1.38, float(p["z"]))
		h.set_meta("h", {"x": p["x"], "z": p["z"], "d": float(int(p["i"]) * 5 + (int(p["j"]) * 3) % 5) * 0.045, "row": p["i"]})
		heads.append(h)
	d["heads"] = heads
	veil(Color("#020203"))


func _update_stare(kk: float) -> void:
	view(kk, 0.0, -0.14 + 0.1 * ss(kk, 1.8, 2.6), 0.0)
	var rise := ss(kk, 1.8, 2.6)
	var end := ss(kk, 2.6, 3.2)
	var cy := cam_y()
	var i := 0
	for h: Node3D in d["heads"]:
		var u: Dictionary = h.get_meta("h")
		var t := ss(kk, 0.6 + float(u["d"]), 1.1 + float(u["d"]))
		var px := float(u["x"])
		var py := 1.38 + rise * (0.35 + float(u["row"]) * 0.2)
		var pz := float(u["z"]) - rise * 0.4
		if (i % 5 == 2 and int(u["row"]) < 2) or i == 6:
			px += (0.0 - px) * end * 0.8
			py += (cy - py) * end
			pz += (0.55 + float(u["row"]) * 0.15 - pz) * end
		h.position = Vector3(px, py, pz)
		h.rotation.y = atan2(-px, -pz) * t
		h.rotation.x = 0.2 * rise
		i += 1
	shade(0.9 * ss(kk, 2.9, 3.2))


# ---- voice: the roll call on the speakers. The speaker says your name, rings of sound come, you crouch with hands over your ears, the speaker comes up to your face ----

func _build_voice() -> void:
	var spk := Node3D.new()
	put(spk, 0.0, 2.55, 2.6)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.55, 0.38, 0.22)
	mesh(bm, _mat(Color("#3a3f42")), 0.0, 0.0, 0.0, spk)
	var gr := disc(0.15, Color("#0a0c0e"), -1.0, 0.0, 0.0, -0.115, 16)
	gr.get_parent().remove_child(gr)
	spk.add_child(gr)
	gr.rotation.x = PI / 2.0
	d["spk"] = spk
	var rings: Array = []
	for i in 8:
		rings.append(torus(0.3, 0.012, _mat(Color("#9aa4ac"), 0.5), 0.0, 2.55, 2.5))
		(rings[i] as Node3D).rotation.x = PI / 2.0
	d["rings"] = rings
	veil(Color("#060606"))


func _update_voice(kk: float) -> void:
	var cover := ss(kk, 1.6, 2.6)
	var end := ss(kk, 2.6, 3.2)
	view(kk, 0.0, 0.3 * ss(kk, 0.0, 0.6) * (1.0 - cover) - 0.3 * cover * (1.0 - end) + 0.03 * sin(kk * 40.0) * shk * cover * (1.0 - end), -0.35 * cover)
	var cy := cam_y()
	var from := Vector3(0.0, 2.55, 2.5)
	var to := Vector3(0.0, cy, 0.15)
	var spk := d["spk"] as Node3D
	spk.position = Vector3(0.01 * sin(kk * 50.0) * seg(kk, 0.4, 3.0), 2.55 + (cy + 0.05 - 2.55) * end, 2.6 - 2.15 * end)
	spk.scale = Vector3.ONE * (1.0 + 0.5 * end)
	var i := 0
	for rr: MeshInstance3D in d["rings"]:
		var ph := kk * 1.1 + pow(maxf(0.0, kk - 1.6), 2.0) * 1.2 - 0.4 - float(i) * 0.28
		rr.visible = ph > 0.0 and ph < 1.0 and end < 0.6
		var t := clampf(ph, 0.0, 1.0)
		rr.position = from.lerp(to, t)
		rr.scale = Vector3.ONE * (1.0 + t * 4.0)
		(rr.material_override as StandardMaterial3D).albedo_color.a = 0.55 * (1.0 - t * 0.6)
		i += 1
	shade(0.9 * ss(kk, 2.95, 3.2))


# ---- bell: thirteen strokes. The bell overhead swings; on the thirteenth it unhooks and comes down over you, humming ----

func _build_bell() -> void:
	d["bell"] = fxm("bell", 1.0, 0.0, 1.4, 0.0)
	d["spot"] = disc(1.0, Color("#050608"), 0.6, 0.0, 0.012, 0.0)
	veil(Color("#020202"))


func _update_bell(kk: float) -> void:
	cue("hit", kk, 1.45, func() -> void: snd("event.bigBell"))
	var drop := pow(seg(kk, 1.0, 1.45), 2.0)
	var ring := exp(-maxf(0.0, kk - 1.45) * 1.6) if kk > 1.45 else 0.0
	var sink_t := ss(kk, 2.6, 3.4)
	var pitch := 0.95 * ss(kk, 0.0, 0.6) * (1.0 - ss(kk, 1.2, 1.6)) + 0.04 * sin(kk * 45.0) * ring * shk
	view(kk, 0.6 * sin(maxf(0.0, kk - 1.7) * 1.2) * seg(kk, 1.7, 2.6), pitch, -0.45 * sink_t)
	var b := d["bell"] as Node3D
	b.position.y = 1.4 * (1.0 - drop) - 0.25 * sink_t
	b.rotation.z = 0.22 * sin(kk * 4.0) * (1.0 - drop) + 0.03 * sin(kk * 50.0) * ring
	(d["spot"] as Node3D).scale = Vector3.ONE * (0.3 + 0.8 * seg(kk, 0.0, 1.45))
	(d["spot"] as Node3D).visible = kk < 1.5
	if kk >= 1.45 and not _flashed.has("hit"):
		_flashed["hit"] = true
		_ui.cut_flash(0.3)
	elif kk >= 1.55:
		_ui.cut_flash(0.0)
	shade(0.4 * ss(kk, 1.5, 1.7) + 0.5 * ss(kk, 3.0, 3.4))


# ---- follow: the exercise on the playground. They do it in step with their backs to you, stop and turn at once, close in on the beat, lean over ----

func _build_follow() -> void:
	var ppl: Array = []
	for i in 3:
		for j in 5:
			var x := -2.4 + float(j) * 1.2
			var z := 3.2 + float(i) * 1.3
			var f := fig("person", Color("#2e333a"), 1.0, x, z)
			f.set_meta("f", {"x": x, "z": z})
			ppl.append(f)
	d["ppl"] = ppl
	veil(Color("#030303"))


func _update_follow(kk: float) -> void:
	var beat := sin(kk * 4.4)
	var turn := ss(kk, 1.0, 1.3)
	var march := ss(kk, 1.3, 2.6)
	var lean := ss(kk, 2.6, 3.2)
	var nod := 0.18 * sin(kk * 4.4) * seg(kk, 1.3, 2.0) * (1.0 if shk > 0.0 else 0.3) * (1.0 - lean)
	view(kk, 0.0, -0.04 + nod + 0.25 * lean, -0.1 * march)
	for p: Node3D in d["ppl"]:
		var u: Dictionary = p.get_meta("f")
		var z := float(u["z"]) + (0.9 + (float(u["z"]) - 3.2) * 0.35 - float(u["z"])) * march
		var x := float(u["x"]) * (1.0 - 0.6 * march)
		p.position = Vector3(x, 0.05 * absf(beat) * (1.0 - turn * (1.0 - march)), z)
		p.rotation.y = PI * turn
		p.rotation.x = (1.0 - turn) * 0.3 * maxf(0.0, beat) + 0.35 * lean
	shade(0.9 * ss(kk, 3.0, 3.4))


# ---- deep: the canteen feast. The dishes tremble, the floor under the table splits into a black pit that runs to your feet, you fall, the light overhead gets smaller ----

func _ring_mesh(inner: float, outer: float, segs: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segs:
		var a0 := float(i) / float(segs) * TAU
		var a1 := float(i + 1) / float(segs) * TAU
		var p0 := Vector3(cos(a0) * inner, 0.0, sin(a0) * inner)
		var p1 := Vector3(cos(a0) * outer, 0.0, sin(a0) * outer)
		var p2 := Vector3(cos(a1) * outer, 0.0, sin(a1) * outer)
		var p3 := Vector3(cos(a1) * inner, 0.0, sin(a1) * inner)
		for v: Vector3 in [p0, p1, p2, p0, p2, p3]:
			st.add_vertex(v)
	return st.commit()


func _build_deep() -> void:
	var table := Node3D.new()
	put(table, 0.0, 0.0, 1.5)
	d["table"] = table
	var wood := _mat(Color("#4a3626"))
	var tm := BoxMesh.new()
	tm.size = Vector3(2.4, 0.08, 0.9)
	mesh(tm, wood, 0.0, 0.78, 0.0, table)
	var lm := BoxMesh.new()
	lm.size = Vector3(0.06, 0.76, 0.06)
	for l: Array in [[-1.1, -0.38], [1.1, -0.38], [-1.1, 0.38], [1.1, 0.38]]:
		mesh(lm, wood, float(l[0]), 0.38, float(l[1]), table)
	var dishes: Array = []
	var pm := CylinderMesh.new()
	pm.top_radius = 0.16
	pm.bottom_radius = 0.13
	pm.height = 0.03
	var fm := SphereMesh.new()
	fm.radius = 0.1
	fm.height = 0.1
	fm.is_hemisphere = true
	for i in 6:
		var g := Node3D.new()
		mesh(pm, _mat(Color("#d8d0c0")), 0.0, 0.0, 0.0, g)
		mesh(fm, _mat(Color("#8a2a1e")), 0.0, 0.015, 0.0, g)
		put(g, -0.9 + float(i) * 0.36, 0.83, 0.18 if i % 2 == 1 else -0.15, table)
		g.set_meta("ph", rand.randf() * 6.0)
		dishes.append(g)
	d["dishes"] = dishes
	d["pit"] = disc(1.0, Color("#010203"), -1.0, 0.0, 0.014, 1.4, 32)
	var shaft := CylinderMesh.new()
	shaft.top_radius = 1.2
	shaft.bottom_radius = 1.2
	shaft.height = 14.0
	shaft.cap_top = false
	shaft.cap_bottom = false
	d["shaft"] = mesh(shaft, _mat(Color("#0a0c0e"), -1.0, true), 0.0, -7.0, 0.0)
	d["mouth"] = mesh(_ring_mesh(1.2, 9.0, 32), _mat(Color("#6c7176"), -1.0, true), 0.0, 0.0, 0.0)
	veil(Color.BLACK)


func _update_deep(kk: float) -> void:
	var open := ss(kk, 0.8, 1.6)
	var fall := seg(kk, 1.6, 2.9)
	view(kk, 0.0, -0.38 * (1.0 - ss(kk, 1.6, 1.9)) - 0.7 * ss(kk, 1.6, 1.9) * (1.0 - ss(kk, 1.95, 2.5)) + 1.25 * ss(kk, 2.0, 2.6), -9.0 * fall * fall)
	for g: Node3D in d["dishes"]:
		g.position.y = 0.83 + 0.012 * absf(sin(kk * 20.0 + float(g.get_meta("ph")))) * seg(kk, 0.0, 1.0)
	var pit := d["pit"] as Node3D
	pit.position.z = 1.4 - 1.4 * open
	pit.scale = Vector3.ONE * (0.05 + 1.15 * open)
	pit.visible = kk < 1.6
	var tip := ss(kk, 1.0, 1.6)
	var table := d["table"] as Node3D
	table.position.y = -2.4 * tip * tip
	table.rotation.x = 0.6 * tip
	table.visible = kk < 1.9
	(d["shaft"] as Node3D).visible = kk >= 1.6
	(d["mouth"] as Node3D).visible = kk >= 1.6
	shade(0.92 * ss(kk, 2.9, 3.4))


# ---- floor: the water cup. A whistle overhead, you look up and see it fall, it hits, you lie on the floor watching it roll away ----
# (a plain white cup with a pale-purple lid here; the old one also carries the picture of the second gate)

func _build_floor() -> void:
	var cup := Node3D.new()
	put(cup, 0.0, _base_y + 9.0, 0.15)
	var body := CylinderMesh.new()
	body.top_radius = 0.045
	body.bottom_radius = 0.04
	body.height = 0.22
	mesh(body, _mat(Color("#ece8e0")), 0.0, 0.0, 0.0, cup)
	d["cup"] = cup
	var lid_m := CylinderMesh.new()
	lid_m.top_radius = 0.045
	lid_m.bottom_radius = 0.045
	lid_m.height = 0.03
	var lid := mesh(lid_m, _mat(Color("#b8a8d8")), 0.0, 0.0, 0.0)
	d["lid"] = lid
	veil(Color("#050000"))


func _update_floor(kk: float) -> void:
	var hit := ss(kk, 1.15, 1.55)
	var lie := seg(kk, 1.6, 2.6)
	view(kk, 0.35 * hit, 1.1 * ss(kk, 0.1, 0.7) * (1.0 - hit) - 0.3 * hit, -1.45 * hit)
	var f := pow(seg(kk, 0.2, 1.15), 2.0)
	var h := 9.0 * (1.0 - f)
	var cup := d["cup"] as Node3D
	var lid := d["lid"] as Node3D
	if kk < 1.15:
		cup.position = Vector3(0.0, _base_y + h, 0.15 + h * 0.5)
		cup.rotation = Vector3(kk * 14.0, 0.0, 0.3)
		lid.position = cup.position + cup.basis * Vector3(0.0, 0.125, 0.0)
		lid.basis = cup.basis
	else:
		cup.position = Vector3(-0.22 - 0.15 * lie, 0.045, 0.75 + 0.3 * lie)
		cup.rotation = Vector3(lie * 9.0, 0.0, PI / 2.0)
		lid.position = Vector3(0.25 + 0.6 * lie, 0.045, 0.75 + 0.1 * lie)
		lid.rotation = Vector3(PI / 2.0, lie * 12.0, 0.0)
	if kk >= 1.15 and not _flashed.has("hit"):
		_flashed["hit"] = true
		_ui.cut_flash(0.4)
	elif kk >= 1.25:
		_ui.cut_flash(0.0)
	shade(0.3 * ss(kk, 1.15, 1.3) * (1.0 - ss(kk, 1.3, 1.8)) + 0.9 * ss(kk, 2.5, 3.0))


# ---- ring: a circle of candles and stones; robed figures rise round it, the stones lengthen into the bars of a cage ----

func _build_ring() -> void:
	var cm := _mat(Color("#d8d4cc"), 0.85, true)
	mesh(_ring_mesh(2.0, 2.06, 48), cm, 0.0, 0.012, 0.0)
	var flames: Array = []
	var fm := SphereMesh.new()
	fm.radius = 0.03
	fm.height = 0.06
	fm.radial_segments = 6
	fm.rings = 4
	for i in 5:
		var a := float(i) / 5.0 * TAU + 0.3
		var x := cos(a) * 1.7
		var z := sin(a) * 1.7
		box(0.05, 0.2, 0.05, Color("#e8e0cc"), -1.0, x, 0.1, z)
		var fl := mesh(fm, _mat(Color("#ffc860")), x, 0.24, z)
		fl.set_meta("f", {"x": x, "z": z, "i": i})
		flames.append(fl)
	d["flames"] = flames
	var stones: Array = []
	for i in 16:
		var st := box(0.08, 0.08, 0.08, Color("#d8d4cc"), -1.0, 0.0, 0.0, 0.0)
		st.set_meta("s", {"a": float(i) / 16.0 * TAU, "d": rand.randf() * 0.5, "h": 0.4 + float(i % 4) * 0.45})
		stones.append(st)
	d["stones"] = stones
	var robes: Array = []
	for i in 6:
		var ra := float(i) / 6.0 * TAU + 0.5
		var f := fig("tall", Color("#050607"), 1.0, cos(ra) * 3.3, sin(ra) * 3.3)
		f.rotation.y = atan2(-f.position.x, -f.position.z)
		robes.append(f)
	d["robes"] = robes
	veil(Color.BLACK)


func _update_ring(kk: float) -> void:
	view(kk, 0.9 * ss(kk, 1.8, 3.2), -0.45 * ss(kk, 0.0, 0.6) * (1.0 - ss(kk, 1.6, 2.2)) + 0.05, 0.0)
	var lean := ss(kk, 0.2, 0.8)
	var cage := ss(kk, 1.8, 2.6)
	for fl: MeshInstance3D in d["flames"]:
		var u: Dictionary = fl.get_meta("f")
		fl.position = Vector3(float(u["x"]) * (1.0 - 0.06 * lean), 0.24, float(u["z"]) * (1.0 - 0.06 * lean))
		fl.scale = Vector3(1.0, 1.8 + 0.3 * sin(kk * 13.0 + float(u["i"])), 1.0)
		fl.visible = kk < 2.7 + float(u["i"]) * 0.12
	for st: MeshInstance3D in d["stones"]:
		var u: Dictionary = st.get_meta("s")
		var up := ss(kk, 0.8 + float(u["d"]), 1.4 + float(u["d"]))
		var ang := float(u["a"]) + maxf(0.0, kk - 0.8) * 1.4 * up + cage * 1.2
		var rad := 2.2 - 1.3 * cage
		st.position = Vector3(cos(ang) * rad, 0.05 + up * float(u["h"]), sin(ang) * rad)
		st.scale = Vector3(1.0, 1.0 + 10.0 * cage, 1.0)
	var stand := ss(kk, 1.6, 2.4)
	var bow := ss(kk, 2.7, 3.3)
	for f: Node3D in d["robes"]:
		f.position.y = -1.9 * (1.0 - stand)
		f.rotation.x = 0.3 * bow
	shade(0.92 * ss(kk, 3.0, 3.4))


# ---- loop: the endless corridor. Door frames slide at you without end, the corridor narrows, the lights go out from far to near, a man in the nearest frame ----

func _build_loop() -> void:
	var wall := _mat(Color("#4a4f55"))
	var wm := BoxMesh.new()
	wm.size = Vector3(0.1, 2.8, 26.0)
	d["walls"] = [mesh(wm, wall, -1.3, 1.4, 13.0), mesh(wm, wall, 1.3, 1.4, 13.0)]
	var frames: Array = []
	var dark := Color("#24180f")
	for i in 10:
		var g := Node3D.new()
		for b: Array in [[-0.62, 1.1, 0.1, 2.2], [0.62, 1.1, 0.1, 2.2], [0.0, 2.25, 1.34, 0.1]]:
			var bm := BoxMesh.new()
			bm.size = Vector3(float(b[2]), float(b[3]), 0.12)
			mesh(bm, _mat(dark), float(b[0]), float(b[1]), 0.0, g)
		var lm := BoxMesh.new()
		lm.size = Vector3(0.5, 0.04, 0.12)
		var lamp := mesh(lm, _mat(Color("#fff4dc")), 0.0, 2.72, 1.2, g)
		g.set_meta("lamp", lamp)
		put(g, 0.0, 0.0, 2.0 + float(i) * 2.4)
		frames.append(g)
	d["frames"] = frames
	var man := fig("person", Color("#07090b"), 1.0, 0.0, 1.6)
	man.rotation.y = PI
	man.visible = false
	d["man"] = man
	veil(Color.BLACK)


func _update_loop(kk: float) -> void:
	cue("man", kk, 2.95, func() -> void: snd("threat.sting"))
	view(kk, 0.0, -0.04, 0.0)
	var scroll := maxf(0.0, kk - 0.8) * 3.0 - maxf(0.0, kk - 2.8) * 3.0
	var narrow := ss(kk, 2.2, 2.8)
	var len := 24.0
	var i := 0
	for g: Node3D in d["frames"]:
		var z := fposmod(fposmod(float(i) * 2.4 - scroll, len), len) * (1.0 - 0.45 * narrow) + 0.8
		g.position.z = z
		g.scale.x = 1.0 - 0.35 * narrow
		(g.get_meta("lamp") as Node3D).visible = not (kk > 2.2 and z > len * (1.0 - seg(kk, 2.2, 2.8)) * 0.6)
		i += 1
	(d["walls"][0] as Node3D).position.x = -1.3 + 0.5 * narrow
	(d["walls"][1] as Node3D).position.x = 1.3 - 0.5 * narrow
	(d["man"] as Node3D).visible = kk > 2.95
	if kk >= 2.95 and not _flashed.has("man"):
		_flashed["man"] = true
		_ui.cut_flash(0.2)
	elif kk >= 3.05:
		_ui.cut_flash(0.0)
	shade(0.9 * ss(kk, 3.1, 3.4))


# ---- lamps: lights out. The row overhead flickers, goes out from far to near; in the dark the last one lights twice more, each time the figure is closer ----

func _build_lamps() -> void:
	var lamps: Array = []
	var lm := BoxMesh.new()
	lm.size = Vector3(0.9, 0.05, 0.16)
	for i in 8:
		lamps.append(mesh(lm, _mat(Color("#fff2d0"), -1.0, false, true), 0.0, 2.75, 0.5 + float(i) * 1.2))
	d["lamps"] = lamps
	var pale := fig("tall", Color("#a8aeb0"), 1.0, 0.0, 2.2, true)
	pale.rotation.y = PI
	pale.visible = false
	d["pale"] = pale
	veil(Color.BLACK)


func _update_lamps(kk: float) -> void:
	for i in 8:
		var lamp_i := i
		cue("off%d" % i, kk, 1.0 + float(7 - i) * 0.15, func() -> void: snd("world.crackle", {"k": 0.5 + 0.06 * float(7 - lamp_i)}))
	cue("last", kk, 3.05, func() -> void: snd("threat.sting"))
	view(kk, 0.0, 0.12 * ss(kk, 0.0, 0.5) - 0.12 * ss(kk, 1.0, 2.0), 0.0)
	var i := 0
	for l: Node3D in d["lamps"]:
		var lit := not (kk >= 0.35 and kk < 0.42 and i % 2 == 1) and not (kk >= 0.7 and kk < 0.78) and kk < 1.0 + float(7 - i) * 0.15
		if i == 0:
			lit = lit or (kk >= 2.35 and kk < 2.45) or (kk >= 2.6 and kk < 2.66) or kk >= 3.05
		l.visible = lit
		i += 1
	var blink := 1 if (kk >= 2.35 and kk < 2.45) else (2 if (kk >= 2.6 and kk < 2.66) else (3 if kk >= 3.05 else 0))
	var pale := d["pale"] as Node3D
	pale.visible = blink > 0
	pale.position.z = [2.2, 2.2, 1.3, 0.55][blink]
	if kk >= 3.05 and not _flashed.has("last"):
		_flashed["last"] = true
		_ui.cut_flash(0.25)
	elif kk >= 3.15:
		_ui.cut_flash(0.0)
	shade(0.9 * ss(kk, 1.4, 2.3))


# ---- laugh: the faces round you start to laugh one by one, closer, circling; you shake with them; a huge laughing face at last ----

func _build_laugh() -> void:
	var faces: Array = []
	for i in 7:
		var a := -1.2 + float(i) * 0.4 + (rand.randf() - 0.5) * 0.15
		var dd := 2.2 + rand.randf() * 1.0
		var f := fxm("smile", 0.35, sin(a) * dd, 0.0, cos(a) * dd)
		f.set_meta("l", {"a": a, "d": dd, "t": float(i) * 0.1 + rand.randf() * 0.1})
		faces.append(f)
	d["faces"] = faces
	var big := fxm("smile", 0.8, 0.0, 0.0, 0.9)
	big.visible = false
	d["big"] = big
	veil(Color("#0a0505"))


func _face_me(o: Node3D) -> void:
	o.rotation.y = atan2(-o.position.x, -o.position.z)


func _update_laugh(kk: float) -> void:
	cue("big", kk, 2.6, func() -> void: snd("threat.smileJump"))
	var near := ss(kk, 0.8, 1.8)
	var swirl := ss(kk, 1.8, 2.6)
	var end := ss(kk, 2.6, 3.2)
	view(kk, 0.0, -0.02 + 0.06 * sin(kk * 16.0) * shk * seg(kk, 1.0, 2.6) * (1.0 - end), -0.15 * absf(sin(kk * 8.0)) * seg(kk, 1.0, 2.6) * (1.0 if shk > 0.0 else 0.3))
	var cy := cam_y()
	for f: Node3D in d["faces"]:
		var u: Dictionary = f.get_meta("l")
		var sc := 0.35 + 0.35 * near
		var dd := float(u["d"]) * (1.0 - 0.4 * near) - (float(u["d"]) * 0.6 - 0.9) * swirl
		var a := float(u["a"]) + (kk - 1.8) * 0.8 * swirl
		f.visible = kk > float(u["t"]) and end < 0.5
		f.scale = Vector3.ONE * sc
		f.position = Vector3(sin(a) * dd, cy - 1.7 * sc + 0.02 * sin(kk * 14.0 + float(u["a"]) * 5.0), cos(a) * dd)
		_face_me(f)
	var big := d["big"] as Node3D
	big.visible = end > 0.0
	var bs := 0.8 + 0.6 * end
	big.scale = Vector3.ONE * bs
	big.position = Vector3(0.0, cy - 1.7 * bs, 0.9 - 0.2 * end)
	_face_me(big)
	shade(0.85 * ss(kk, 2.95, 3.2))


# ---- swarm: the moths. A black cloud under the lamp winds into a column round you and finally fills the view ----

func _build_swarm() -> void:
	var n := 70
	var wing := QuadMesh.new()
	wing.size = Vector2(0.07, 0.04)
	var body := BoxMesh.new()
	body.size = Vector3(0.016, 0.016, 0.06)
	d["wingIM"] = inst(wing, _mat(Color("#111111"), -1.0, true), n * 2)
	d["bodyIM"] = inst(body, _mat(Color("#080808")), n)
	var moths: Array = []
	for i in n:
		moths.append({"a": rand.randf() * TAU, "r": 0.35 + rand.randf() * 1.3, "h": rand.randf() * 0.9, "sp": (-1.0 if rand.randf() < 0.5 else 1.0) * (1.6 + rand.randf() * 1.8), "ph": rand.randf() * TAU, "fl": 26.0 + rand.randf() * 16.0})
	d["moths"] = moths
	box(0.008, 0.5, 0.008, Color("#111111"), -1.0, 0.0, 2.55, 4.5)
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	sm.radial_segments = 10
	sm.rings = 8
	mesh(sm, _mat(Color("#ffe9c0")), 0.0, 2.26, 4.5)
	d["glow"] = disc(0.75, Color("#ffd9a0"), 0.7, 0.0, 2.26, 4.5)
	((d["glow"] as Node3D) as MeshInstance3D).rotation.x = PI / 2.0
	veil(Color("#0c0905"))


func _update_swarm(kk: float) -> void:
	var gather := ss(kk, 0.4, 1.4)
	var close := ss(kk, 1.4, 2.5)
	var cover := ss(kk, 2.5, 3.2)
	view(kk, 0.0, 0.22 * gather * (1.0 - close) - 0.1 * close + 0.05 * sin(kk * 17.0) * close * shk, -0.35 * cover)
	var cy := cam_y()
	var sc := 1.5 + 1.0 * cover
	var i := 0
	for m: Dictionary in d["moths"]:
		var ang := float(m["a"]) + kk * float(m["sp"])
		var a := Vector3(cos(ang) * float(m["r"]) * 0.6, 2.2 + (float(m["h"]) - 0.45) * 0.9 + sin(ang * 1.7 + float(m["ph"])) * 0.12, 4.5 + sin(ang) * float(m["r"]) * 0.6)
		var rr := 2.2 * (1.0 - close) + 0.3 + 0.15 * float(m["r"])
		var ang2 := float(m["a"]) + kk * float(m["sp"]) * 1.6
		var b := Vector3(cos(ang2) * rr, 0.6 + float(m["h"]) * 2.0 + (cy - 0.6 - float(m["h"]) * 2.0) * close * 0.7, sin(ang2) * rr)
		var q := a.lerp(b, gather)
		if cover > 0.0:
			q = q.lerp(Vector3(cos(ang2) * 0.18, cy + sin(ang2 * 1.3) * 0.1, 0.16 + 0.08 * sin(ang2)), cover * 0.9)
		var head := -ang2 if float(m["sp"]) > 0.0 else PI - ang2
		var flap := sin(kk * float(m["fl"]) + float(m["ph"])) * 1.1 + 0.25
		set_i(d["bodyIM"], i, q, Vector3(0.0, head, 0.0), Vector3.ONE * sc)
		set_i(d["wingIM"], i * 2, q, Vector3(-PI / 2.0, head, flap), Vector3.ONE * sc)
		set_i(d["wingIM"], i * 2 + 1, q, Vector3(-PI / 2.0, head, -flap), Vector3(-sc, sc, sc))
		i += 1
	var fl := 0.8 + 0.2 * sin(kk * 23.0) * sin(kk * 7.3)
	((d["glow"] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.a = 0.7 * fl * (1.0 - 0.4 * close) * (1.0 - 0.6 * cover)
	shade(0.85 * ss(kk, 2.9, 3.2))


# ---- gaze: someone taps your shoulder. A glance, then your head is slowly turned: behind you a smiling face, eyes opening one by one in the dark ----

func _build_gaze() -> void:
	d["smile"] = fxm("smile", 1.0, 0.0, _base_y - 1.7, -1.0)
	var eyes: Array = []
	var em := CylinderMesh.new()
	em.top_radius = 0.5
	em.bottom_radius = 0.5
	em.height = 0.003
	em.radial_segments = 12
	em.rings = 1
	for i in 18:
		var col := Color("#d23a2e") if rand.randf() < 0.4 else Color("#e8bd4a")
		var mat := _mat(col, 0.0)
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		var a := PI * (0.25 + rand.randf() * 0.5) + PI
		var dd := 1.8 + rand.randf() * 2.4
		var e := mesh(em, mat, cos(a) * dd, 0.5 + rand.randf() * 2.1, sin(a) * dd)
		e.rotation.x = PI / 2.0
		e.set_meta("e", {"x": e.position.x, "z": e.position.z, "y": e.position.y, "s": 0.4 + rand.randf() * 0.6, "d": rand.randf() * 0.5})
		eyes.append(e)
	d["eyes"] = eyes
	veil(Color("#050203"))


func _update_gaze(kk: float) -> void:
	cue("giggle", kk, 1.75, func() -> void: snd("threat.smileBack", {"pan": 0.3}))
	var turn := 0.22 * ss(kk, 0.15, 0.5) * (1.0 - ss(kk, 0.5, 0.8)) + PI * ss(kk, 0.8, 1.7)
	view(kk, turn, -0.04, 0.0)
	var close := ss(kk, 2.0, 2.9)
	var sm := d["smile"] as Node3D
	sm.position.z = -1.0 + 0.55 * close
	sm.scale = Vector3.ONE * (1.0 + 0.5 * close)
	sm.position.y = _base_y - 1.7 * (1.0 + 0.5 * close)
	for e: MeshInstance3D in d["eyes"]:
		var u: Dictionary = e.get_meta("e")
		var o := ss(kk, 1.5 + float(u["d"]), 1.9 + float(u["d"]))
		var sh := 1.0 - 0.5 * close
		e.position = Vector3(float(u["x"]) * sh, float(u["y"]) + (_base_y - float(u["y"])) * 0.3 * close, float(u["z"]) * sh)
		(e.material_override as StandardMaterial3D).albedo_color.a = o
		var sc := float(u["s"]) * (0.3 + 0.7 * o) * (1.0 + 0.4 * close)
		e.scale = Vector3(sc * 0.3, 1.0, sc * 0.3 * 0.6875)
	shade(0.9 * ss(kk, 3.0, 3.4))


# ---- window_gaze: the eyes in the window (7 s). Omen: a window ahead, a pair of eyes in the pane that never blink. Contact: your
# reflection turns to face you. The last view, from inside the window looking out: someone with their back to you — you. Closing: that
# one looks up, the glass shows the same eyes; dark. ----

func _build_window_gaze() -> void:
	hide_world()
	var dd := 2.2
	var fl := mesh(QuadMesh.new(), _mat(Color("#1a1d1f")), 0.0, 0.002, 1.0)
	(fl.mesh as QuadMesh).size = Vector2(4, 5)
	fl.rotation.x = -PI / 2.0
	var wall: Array = [box(4, 1.0, 0.12, Color("#4a5052"), -1.0, 0.0, 0.5, dd), box(4, 0.6, 0.12, Color("#4a5052"), -1.0, 0.0, 2.55, dd),
		box(1.25, 1.25, 0.12, Color("#4a5052"), -1.0, -1.375, 1.625, dd), box(1.25, 1.25, 0.12, Color("#4a5052"), -1.0, 1.375, 1.625, dd)]
	wall.append(box(1.5, 1.25, 0.01, Color("#0b1013"), -1.0, 0.0, 1.625, dd + 0.02))
	wall.append(box(0.04, 1.25, 0.05, Color("#8b9192"), -1.0, 0.0, 1.625, dd - 0.02))
	wall.append(box(1.5, 0.04, 0.05, Color("#8b9192"), -1.0, 0.0, 1.625, dd - 0.02))
	wall.append(box(0.045, 0.022, 0.01, Color("#e8e4d4"), -1.0, -0.05, 1.86, dd - 0.012))
	wall.append(box(0.045, 0.022, 0.01, Color("#e8e4d4"), -1.0, 0.05, 1.86, dd - 0.012))
	d["wall"] = wall
	var refl := fig("person", Color("#3a4246"), 1.0, 0.12, dd - 0.03)
	refl.scale = Vector3(0.98, 0.98, 0.05)
	d["refl"] = refl
	d["frameB"] = [box(0.08, 2.4, 0.06, Color("#8b9192"), -1.0, -0.5, 1.2, 0.42), box(0.08, 2.4, 0.06, Color("#8b9192"), -1.0, 0.5, 1.2, 0.42),
		box(1.1, 0.08, 0.06, Color("#8b9192"), -1.0, 0.0, 0.95, 0.42), box(1.1, 0.08, 0.06, Color("#8b9192"), -1.0, 0.0, 2.3, 0.42)]
	var myself := fig("person", Color("#2c3337"), 1.0, 0.0, 2.4)
	myself.rotation.y = 0.0
	d["self"] = myself
	d["selfEyes"] = [box(0.04, 0.02, 0.01, Color("#e8e4d4"), -1.0, -0.045, 1.66, 2.25), box(0.04, 0.02, 0.01, Color("#e8e4d4"), -1.0, 0.045, 1.66, 2.25)]
	veil(Color.BLACK)


func _update_window_gaze(kk: float) -> void:
	var rev := kk >= 3.6
	for m: Node3D in d["wall"]:
		m.visible = not rev
	(d["refl"] as Node3D).visible = not rev and kk > 1.2
	for m: Node3D in d["frameB"]:
		m.visible = rev
	(d["self"] as Node3D).visible = rev
	for m: Node3D in d["selfEyes"]:
		m.visible = rev and kk > 6.0
	if not rev:
		(d["refl"] as Node3D).rotation.y = PI * (1.0 - ss(kk, 2.0, 3.2))
		view(kk, 0.0, 0.02 * ss(kk, 0.0, 2.0), 0.0)
		shade(0.1 + 0.25 * ss(kk, 2.6, 3.5))
	else:
		view(kk, 0.0, 0.03, 0.0)
		(d["self"] as Node3D).rotation.x = -0.25 * ss(kk, 5.6, 6.3)
		shade(0.55 - 0.4 * ss(kk, 3.6, 4.1) + 0.6 * ss(kk, 6.3, 7.0))
	cue("line", kk, 5.8, func() -> void: _ui.show_notice("原来里面那个，一直是我。"))


# ---- paper_sender: the one who flies paper planes (8 s). Footsteps stop outside the door; a flattened paper plane slides in under it to
# your feet; the door opens a crack, a hand comes in and unfolds it — the one you just read; the picture is folded into the page; dark. ----

func _build_paper_sender() -> void:
	hide_world()
	var dd := 1.6
	var fl := mesh(QuadMesh.new(), _mat(Color("#1b1e1f")), 0.0, 0.002, 0.8)
	(fl.mesh as QuadMesh).size = Vector2(4, 4)
	fl.rotation.x = -PI / 2.0
	box(4, 3, 0.1, Color("#3d4446"), -1.0, 0.0, 1.5, dd + 0.05)
	d["gap"] = box(0.9, 0.02, 0.01, Color("#d8d2b8"), -1.0, 0.0, 0.01, dd - 0.02)
	var door := Node3D.new()
	put(door, 0.45, 0.0, dd - 0.03)
	d["door"] = door
	var lm := BoxMesh.new()
	lm.size = Vector3(0.9, 2.05, 0.04)
	mesh(lm, _mat(Color("#5b4a38")), -0.45, 1.035, 0.0, door)
	d["plane"] = box(0.24, 0.006, 0.16, Color("#e9e5d8"), -1.0, 0.0, 0.005, dd - 0.05)
	d["sheet"] = box(0.34, 0.46, 0.004, Color("#efebde"), -1.0, 0.0, 1.25, dd - 0.6)
	d["hand"] = box(0.09, 0.12, 0.03, Color("#cdbca6"), -1.0, 0.12, 1.2, dd - 0.55)
	var lines: Array = []
	for i in 5:
		lines.append(box(0.24, 0.008, 0.002, Color("#3a3530"), -1.0, 0.0, 1.38 - float(i) * 0.06, dd - 0.602))
	d["lines"] = lines
	for n: String in ["plane", "sheet", "hand"]:
		(d[n] as Node3D).visible = false
	for l: Node3D in lines:
		l.visible = false
	veil(Color.BLACK)


func _update_paper_sender(kk: float) -> void:
	var dd := 1.6
	cue("steps", kk, 0.2, func() -> void: _ui.show_notice("（门外的脚步声停了。）"))
	var plane := d["plane"] as Node3D
	plane.visible = kk > 2.0 and kk < 4.4
	plane.position.z = dd - 0.05 - 0.6 * ss(kk, 2.0, 3.6)
	plane.rotation.y = 0.4 * ss(kk, 2.0, 3.6)
	var open := ss(kk, 4.2, 4.8)
	(d["door"] as Node3D).rotation.y = -0.35 * open
	(d["gap"] as Node3D).visible = kk < 4.2
	(d["hand"] as Node3D).visible = kk > 4.4
	var sheet := d["sheet"] as Node3D
	sheet.visible = kk > 4.4
	for l: Node3D in d["lines"]:
		l.visible = kk > 4.9
	sheet.scale.y = 0.2 + 0.8 * ss(kk, 4.4, 5.2)
	var fold := 0.55 * ss(kk, 5.4, 8.0)
	sheet.position.z = dd - 0.6 - fold
	(d["hand"] as Node3D).position.z = dd - 0.55 - fold
	for l: Node3D in d["lines"]:
		l.position.z = dd - 0.602 - fold
	view(kk, 0.0, -0.35 + 0.35 * ss(kk, 1.6, 2.2) - 0.62 * ss(kk, 2.2, 3.6) + 0.62 * ss(kk, 4.0, 4.6), 0.0)
	shade(0.15 + 0.75 * ss(kk, 6.6, 8.0))
	cue("knock", kk, 7.2, func() -> void: _ui.show_notice("他来取回没有送到的东西。"))


# ---- misread: the notice you read was meant for you (4.1 s). The broadcast room: the doors close, the speakers swell, "高二（二）班 请留在原地". ----

func _build_misread() -> void:
	hide_world()
	box(3.6, 0.05, 4.5, Color("#272e2b"), -1.0, 0.0, -0.025, 1.2)
	box(3.6, 2.8, 0.08, Color("#3c4843"), -1.0, 0.0, 1.4, 3.4)
	box(0.08, 2.8, 4.5, Color("#34403c"), -1.0, -1.8, 1.4, 1.2)
	box(1.3, 0.12, 0.6, Color("#4b4438"), -1.0, 0.0, 0.88, 1.15)
	box(0.08, 0.35, 0.08, Color("#151f1d"), -1.0, 0.0, 1.1, 1.2)
	var doors: Array = []
	for i in 4:
		doors.append(box(0.72, 2.0, 0.06, Color("#26322e"), -1.0, -1.3 + float(i) * 0.86, 1.0, 3.28))
	d["doors"] = doors
	var sign_l := _label("播 音 中", 0.3, Color("#d86b51"))
	put(sign_l, 0.0, 2.22, 3.2)
	sign_l.rotation.y = PI
	d["sign"] = sign_l
	var demand := _label("高二（二）班\n请留在原地", 0.4, Color("#dddcc8"))
	put(demand, 0.0, 1.6, 3.18)
	demand.rotation.y = PI
	d["demand"] = demand
	var speakers: Array = []
	for i in 6:
		speakers.append(box(0.24, 0.2, 0.12, Color("#54625b"), -1.0, -1.35 + float(i % 3) * 1.35, 2.35, 1.0 + (1.4 if i >= 3 else 0.0)))
	d["speakers"] = speakers
	veil(Color("#020707"))


func _label(text: String, size: float, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = size / 64.0 * 0.45
	l.modulate = color
	l.shaded = false
	l.double_sided = true
	return l


func _update_misread(kk: float) -> void:
	var close := ss(kk, 0.35, 1.8)
	var i := 0
	for m: Node3D in d["doors"]:
		m.position.x = -1.3 + float(i) * 0.86 + (1.0 if i % 2 == 1 else -1.0) * 0.3 * (1.0 - close)
		i += 1
	(d["demand"] as Node3D).visible = kk > 0.8
	(d["sign"] as Node3D).visible = kk < 3.3
	i = 0
	for m: Node3D in d["speakers"]:
		m.scale = Vector3.ONE * (1.0 + 0.04 * sin(kk * 5.0 + float(i)))
		i += 1
	view(kk, 0.0, 0.03 * shk * sin(kk * 5.0), -0.02 * close)
	shade(minf(0.92, (kk - 3.3) * 1.4) if kk > 3.3 else 0.08)


# ---- campus_fall: "Chinese people can fly" (6 s). The hand leaves the rail; the rail and the floor edge slide up out of the picture; rows of
# window frames sweep past upward, the camera slowly turns down; the ground's shadow rises to meet you; black before contact; a muted thud. ----

func _build_campus_fall() -> void:
	hide_world()
	var w := Node3D.new()
	put(w, 0.0, 0.0, 0.0)
	d["world"] = w
	var add_box := func(bw: float, bh: float, bd: float, col: Color, x: float, y: float, z: float) -> void:
		var bm := BoxMesh.new()
		bm.size = Vector3(bw, bh, bd)
		mesh(bm, _mat(col), x, y, z, w)
	add_box.call(3.0, 0.12, 0.06, Color("#8a8f8c"), 0.0, 1.05, 0.35)
	add_box.call(3.0, 0.1, 0.6, Color("#5c605e"), 0.0, 0.9, 0.05)
	for i in 6:
		var y := -3.2 * float(i) - 1.6
		add_box.call(0.08, 3.2, 4.0, Color("#6c6e66"), -1.25, y, 1.2)
		add_box.call(0.06, 1.3, 1.4, Color("#1d2326"), -1.2, y + 0.2, 0.7)
		add_box.call(0.06, 1.3, 1.4, Color("#1d2326"), -1.2, y + 0.2, 2.3)
		add_box.call(0.1, 0.12, 4.0, Color("#9a9c94"), -1.18, y - 1.3, 1.2)
	var gm := QuadMesh.new()
	gm.size = Vector2(8, 8)
	var ground := mesh(gm, _mat(Color("#2b2a26")), 0.0, -19.5, 1.5, w)
	ground.rotation.x = -PI / 2.0
	var shadow := disc(0.5, Color("#080808"), -1.0, 0.0, -19.48, 1.5, 20)
	shadow.get_parent().remove_child(shadow)
	w.add_child(shadow)
	shadow.position = Vector3(0.0, -19.48, 1.5)
	d["shadow"] = shadow
	veil(Color.BLACK)


func _update_campus_fall(kk: float) -> void:
	var fall := 0.6 * ss(kk, 0.3, 1.6) if kk < 1.6 else 0.6 + (kk - 1.6) * (kk - 1.6) * 2.6 + (kk - 1.6) * 2.0
	(d["world"] as Node3D).position.y = minf(18.2, fall)
	(d["shadow"] as Node3D).scale = Vector3.ONE * (0.5 + 2.5 * ss(kk, 3.6, 4.6))
	view(kk, 0.04 * shk * sin(kk * 7.0) * ss(kk, 1.6, 3.0), -0.2 * ss(kk, 0.0, 1.6) - 1.0 * ss(kk, 1.6, 4.0), 0.0)
	shade(0.05 + 0.9 * ss(kk, 4.3, 4.9))
	cue("wind", kk, 1.7, func() -> void: _ui.show_notice("（风声。校园里的声音一下子远了。）"))
	cue("hit", kk, 4.9, func() -> void: _ui.show_notice("（一声闷响。）"))


# The maze owns its two scenes without growing the public scene implementation.
func _build_void() -> void:
	MazeDeath.build_lost(self)


func _update_void(t: float) -> void:
	MazeDeath.update_lost(self, t)


func _build_abyss() -> void:
	MazeDeath.build_fall(self)


func _update_abyss(t: float) -> void:
	MazeDeath.update_fall(self, t)
