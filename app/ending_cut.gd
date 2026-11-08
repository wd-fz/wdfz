class_name EndingCut
extends Node
## The live ending scenes (cutscene.js CUT_DEF, reference wd-fz.github.io@0bf508a): before an ending card the
## scene is played in the world (camera, a few temporary things, light and colour), then the card shows.
## The world stands still (the app pauses the tree), click / Space / Enter / Esc skip. Ported so far:
##   face (《白名单》) — the gate's lamp turns from red to white, a beep, black; outside the gate you turn and look
##   back: one by one the gate fills with people watching you leave.
##   international (《外国语学生》) — 20 s on four little stages of its own (the world is hidden): the visitors pass
##   the north gate, the guard checks the reception list while two searchers stop inside, outside the colours are
##   ordinary and a temporary reception pass is handed back, the pass names a school that sounds unfamiliar.
## The rest of the endings still go straight to their cards (docs/plan/结局分镜.md).

signal finished(skipped: bool)

const DEFS := {"face": {"dur": 10.0, "outdoor": true}, "international": {"dur": 20.0, "outdoor": false}}
const COAT := [Color("#3a4a6a"), Color("#7a5a3a"), Color("#5a6a4a"), Color("#8a6a6a")]
const SC := 2.0

var on := false
var kind := ""
var k := 0.0
var cam: Camera3D
var _ui: GameUI
var _player: PlayerController
var _root: Node3D
var _dur := 10.0
var _g := Vector3.ZERO
var _lamp: MeshInstance3D
var _figs: Array = []
var _beeped := false
var _on_beep: Callable
var _world: Node3D
var _world_was_visible := true
var _how := "exam"
var _st: Array = []
var _walk: Array = []
var _list: Node3D
var _pass: Node3D
var _pass2: Node3D


static func has(id: String) -> bool:
	return DEFS.has(id)


## Whether the scene needs the player to be in the campus outdoors (a gate of the real world).
static func needs_outdoor(id: String) -> bool:
	return bool(DEFS.get(id, {}).get("outdoor", true))


## The four stages of 《外国语学生》 by time: 0–4, 4–9, 9–15, 15–20 s.
static func intl_stage(t: float) -> int:
	return 0 if t < 4.0 else (1 if t < 9.0 else (2 if t < 15.0 else 3))


static func intl_edge(t: float) -> float:
	var edge := 0.0
	for x: float in [4.0, 9.0, 15.0]:
		edge = maxf(edge, maxf(0.0, 1.0 - absf(t - x) / 0.25))
	return maxf(edge, (t - 19.2) / 0.8 if t > 19.2 else 0.0)


static func intl_caption(stage: int, how: String) -> String:
	match stage:
		0:
			return "「Alle da?」——「On est tous là.」队尾的人回头看了我一眼。" if how == "multilingual" else "队尾的人回头看了我一眼，确认我还在。"
		1:
			return "门卫对着名单点了点头。门里的两个搜查员停住了，没有再往前走。"
		2:
			return "门外的声音很平常。有人把临时接待证递还给我：「Danke.」「Merci.」"
	return "接待证上的学校名字，好像和我记得的不太一样。队伍在前面轻声叫我。"


static func ease_k(x: float) -> float:
	return OpeningCut.ease_k(x)


static func phase(kk: float, a: float, b: float) -> float:
	return OpeningCut.phase(kk, a, b)


## A gate of the campus plan in scene coordinates (cutW2S).
static func gate_scene(campus: Dictionary, key: String) -> Vector3:
	var g: Dictionary = campus.get("gates", {}).get(key, {})
	var s := CampusGeometry.to_scene(null, Vector2(float(g.get("x", 0)) * SC, float(g.get("y", 0)) * SC))
	return Vector3(s.x, 0.0, s.y)


## Lamp colour at the progress (face): red until 0.16, then white.
static func face_lamp(kk: float) -> Color:
	return Color("#e8e4d2") if kk > 0.16 else Color("#d23a2e")


## Black fade at the progress (face).
static func face_fade(kk: float) -> float:
	if kk < 0.3:
		return (kk - 0.24) / 0.06 if kk > 0.24 else 0.0
	if kk < 0.36:
		return 1.0 - (kk - 0.3) / 0.06
	return (kk - 0.9) / 0.1 if kk > 0.9 else 0.0


func begin(id: String, world: Node3D, campus: Dictionary, player: PlayerController, ui: GameUI, on_beep: Callable = Callable(), opts: Dictionary = {}) -> void:
	kind = id
	_ui = ui
	_player = player
	_on_beep = on_beep
	_dur = float(DEFS[id]["dur"])
	k = 0.0
	on = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Node3D.new()
	_root.name = "EndingProps"
	_world = world
	if id == "international":
		# Its own stages far from the real scene: the world is hidden meanwhile.
		_how = String(opts.get("how", "exam"))
		_world_was_visible = world.visible
		world.visible = false
		add_child(_root)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color(0.23, 0.25, 0.27)
		_root.add_child(env)
	else:
		world.add_child(_root)
	cam = Camera3D.new()
	cam.name = "EndingCamera"
	cam.fov = player.camera.fov
	cam.near = player.camera.near
	cam.far = player.camera.far
	_root.add_child(cam)
	cam.current = true
	if id == "international":
		_setup_intl()
		_ui.cut_fade(0.0)
		_apply(0.0)
		return
	_g = gate_scene(campus, "w")
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.12
	_lamp = MeshInstance3D.new()
	_lamp.mesh = box
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = face_lamp(0.0)
	_lamp.material_override = m
	_lamp.position = _g + Vector3(0.4, 1.15, 0.9)
	_root.add_child(_lamp)
	for i in 15:
		var f := FigureModel.make("person", Color("#050607"), true, 0.96 + float((i * 5) % 4) * 0.03)
		f.position = _g + Vector3(2.0 + floorf(float(i) / 5.0) * 1.25, 0.0, float(i % 5 - 2) * 1.15 + float(int(floorf(float(i) / 5.0)) % 2) * 0.5)
		f.visible = false
		_root.add_child(f)
		_figs.append(f)
	_ui.cut_fade(0.0)
	_apply(0.0)


func _look(from: Vector3, to: Vector3) -> void:
	cam.global_position = from
	if from.distance_to(to) > 0.01:
		cam.look_at(to, Vector3.UP)


func _apply(kk: float) -> void:
	if kind == "international":
		_apply_intl(kk)
		return
	_ui.cut_fade(clampf(face_fade(kk), 0.0, 1.0))
	if kk < 0.3:
		(_lamp.material_override as StandardMaterial3D).albedo_color = face_lamp(kk)
		if kk > 0.16 and not _beeped:
			_beeped = true
			if _on_beep.is_valid():
				_on_beep.call()
		_look(_g + Vector3(3.4, 1.6, 0.6), _g + Vector3(0.0, 1.3, 0.6))
		for f: Node3D in _figs:
			f.visible = false
		return
	var turn := phase(kk, 0.36, 0.5)
	var back := phase(kk, 0.5, 1.0)
	var cx := lerpf(_g.x - 2.4, _g.x - 6.0, back)
	var ang := lerpf(PI, 0.0, turn)
	var from := Vector3(cx, 1.6, _g.z + sin(kk * 3.0) * 0.08)
	_look(from, Vector3(cx + cos(ang) * 5.0, 1.5, _g.z + sin(ang) * 5.0))
	var i := 0
	for f: Node3D in _figs:
		f.visible = kk > 0.5 + float(i) * 0.028
		# Facing the camera (the figure's front is -z), the head tilted a little.
		f.rotation = Vector3(0.0, atan2(f.position.x - from.x, f.position.z - from.z), 0.06 * sin(float(i) * 1.7))
		i += 1


func _process(delta: float) -> void:
	tick(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not on:
		return
	if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
		end(true)
		get_viewport().set_input_as_handled()


func tick(delta: float) -> void:
	if not on:
		return
	if not is_instance_valid(_root):
		end(true)
		return
	k += delta / _dur
	if k >= 1.0:
		end(false)
		return
	_apply(k)


func end(skipped: bool) -> void:
	if not on:
		return
	on = false
	if kind == "international" and is_instance_valid(_world):
		_world.visible = _world_was_visible
	_ui.cut_caption("")
	_ui.cut_fade(0.0)
	if is_instance_valid(_player) and _player.camera != null:
		_player.camera.current = true
	if is_instance_valid(_root):
		_root.queue_free()
	finished.emit(skipped)


# ---- 《外国语学生》 ----

func _box(g: Node3D, w: float, h: float, d: float, c: Color, x: float, y: float, z: float) -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, d)
	m.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = c
	m.material_override = mat
	m.position = Vector3(x, y, z)
	g.add_child(m)


func _fig(g: Node3D, fkind: String, c: Color, x: float, z: float, ry: float) -> Node3D:
	var f := FigureModel.make(fkind, c, true)
	f.position = Vector3(x, 0.0, z)
	f.rotation.y = ry + PI          # the old figures front +z, ours -z
	g.add_child(f)
	return f


## A small paper card: a coloured head strip with the title and lines under it.
func _card(lines: Array) -> Node3D:
	var n := Node3D.new()
	var back := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.34, 0.21)
	back.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color("#f4f1e6")
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	back.material_override = m
	n.add_child(back)
	var strip := MeshInstance3D.new()
	var sq := QuadMesh.new()
	sq.size = Vector2(0.34, 0.04)
	strip.mesh = sq
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color("#2a3a52")
	strip.material_override = sm
	strip.position = Vector3(0.0, 0.085, 0.001)
	n.add_child(strip)
	for i in lines.size():
		var l := Label3D.new()
		l.text = String(lines[i])
		l.font_size = 26 if i == 0 else 22
		l.pixel_size = 0.0007
		l.modulate = Color.WHITE if i == 0 else Color("#222222")
		l.shaded = false
		l.double_sided = true
		l.position = Vector3(-0.15 + (0.0), 0.085 - float(i) * 0.042 if i == 0 else 0.04 - float(i - 1) * 0.045, 0.002)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		n.add_child(l)
	return n


func _setup_intl() -> void:
	for i in 4:
		var g := Node3D.new()
		g.position.x = float(i) * 60.0
		_root.add_child(g)
		_st.append(g)
	for k2 in [0, 1]:
		var g: Node3D = _st[k2]
		_box(g, 30, 0.05, 30, Color("#3b3e3a"), 0, 0, 0)
		_box(g, 0.6, 3.2, 0.6, Color("#6d6a62"), -2.4, 1.6, 0)
		_box(g, 0.6, 3.2, 0.6, Color("#6d6a62"), 2.4, 1.6, 0)
		_box(g, 5.4, 0.4, 0.6, Color("#6d6a62"), 0, 3.2, 0)
		_box(g, 30, 0.04, 14, Color("#8a8d7c"), 0, 0.01, -8)
	var a: Node3D = _st[0]
	for i in 4:
		_walk.append(_fig(a, "person", COAT[i], 0.5 - float(i % 2), 2.0 + float(i) * 1.2, PI))
	var b: Node3D = _st[1]
	_fig(b, "person", Color("#2e3b4a"), 3.0, -0.6, -PI / 2.0)
	_fig(b, "tall", Color("#1e2226"), -1.2, 4.5, PI)
	_fig(b, "tall", Color("#1e2226"), 1.4, 5.2, PI)
	_list = _card(["接待名单", "国际交流团 · 4 人", "接待学生 · 1 人"])
	_list.position = Vector3(2.6, 1.2, -0.5)
	_list.rotation.y = -0.4
	b.add_child(_list)
	var c: Node3D = _st[2]
	_box(c, 30, 0.05, 30, Color("#7a776c"), 0, 0, 0)
	_box(c, 30, 6, 0.2, Color("#b8c4c8"), 0, 3, -10)
	for i in 4:
		_fig(c, "person", COAT[i], -1.6 + float(i), -2.0 - float(i % 2) * 0.6, PI * (0.8 if i % 2 == 1 else 1.2))
	_pass = _card(["临时接待证", "高二（二）班", "有效期：今天"])
	_pass.position = Vector3(0.1, 1.25, -0.9)
	c.add_child(_pass)
	var e: Node3D = _st[3]
	_box(e, 30, 0.05, 30, Color("#7a776c"), 0, 0, 0)
	_box(e, 30, 6, 0.2, Color("#b8c4c8"), 0, 3, -10)
	_pass2 = _card(["临时接待证", "武大附属外国语学校", "高二（二）班"])
	_pass2.position = Vector3(0.0, 1.3, -0.5)
	_pass2.scale = Vector3.ONE * 1.6
	e.add_child(_pass2)


func _apply_intl(kk: float) -> void:
	var t := kk * 20.0
	var s := intl_stage(t)
	for i in _st.size():
		(_st[i] as Node3D).visible = i == s
	var cap := intl_caption(s, _how)
	_ui.cut_caption(cap)
	if s == 0:
		var u := t / 4.0
		for i in _walk.size():
			(_walk[i] as Node3D).position.z = 2.0 + float(i) * 1.2 - u * 6.0
		(_walk[3] as Node3D).rotation.y = PI + (PI if t > 1.0 and t < 2.4 else 0.0) + PI
		_look(Vector3(0.6, 1.6, 7.5 - u * 3.0), Vector3(0.0, 1.2, -3.0))
	elif s == 1:
		_look(Vector3(60.0 - 0.8, 1.5, -3.2), Vector3(60.2, 1.3, 3.0))
		_list.rotation.y = -0.4 + 0.1 * sin(t * 2.0)
	elif s == 2:
		var v := (t - 9.0) / 6.0
		_look(Vector3(120.3, 1.5, 1.4 - v * 0.6), Vector3(120.0, 1.2, -1.5))
		_pass.position.z = -0.9 + 0.5 * minf(1.0, v * 1.5)
	else:
		_look(Vector3(180.0, 1.45, 0.3), Vector3(180.0, 1.3, -0.5))
	_ui.cut_fade(clampf(intl_edge(t), 0.0, 1.0))
