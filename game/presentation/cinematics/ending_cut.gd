class_name EndingCut
extends Node
## The live ending scenes (cutscene.js CUT_DEF, reference wd-fz.github.io@0bf508a): before an ending card the
## scene is played in the world (camera, a few temporary things, light and colour), then the card shows.
## The world stands still (the app pauses the tree), click / Space / Enter / Esc skip. Ported so far:
##   face (《白名单》) — the gate's lamp turns from red to white, a beep, black; outside the gate you turn and look
##   back: one by one the gate fills with people watching you leave.
##   dismissal (《放学》) — 18 s on four stages of its own: the broadcast room (the speakers light up one by one),
##   the classroom (dozens of chairs slide back at once), the stairwell seen from above (a stream of people and one
##   tall figure that does not move), the north gate and the teaching building behind it whose windows go dark.
##   car (《闸门》 opening, then the real driving) — 10 s: in the garage the headlights flicker on twice and for a
##   moment something stands in the light (then it is gone); black; outside the north gate, looking back: a row of
##   black figures pours out of the gate and chases, the camera backing away.
##   cyber (《网安仙人》) — 16 s on four stages: the server room (the racks' lights go out one by one, the console
##   prints the shutdown log, the wall speaker breaks off), the corridor (the tube lights flicker two short one long, then
##   settle; the tall figure drops its shoulders and stands still), the archive (the company report against the original
##   record, three contradictions circled, "签发节点：未知"), the campus at dawn (the camera rises, ordinary morning).
##   portal (《门》) — 10 s in front of the demonstration bench's device (a simplified model of the old one): it
##   charges, the three rails close one by one, the door opens; the camera steps back half a pace, then pushes in
##   and through the ring, white at the end.
##   international (《外国语学生》) — 20 s on four little stages of its own (the world is hidden): the visitors pass
##   the north gate, the guard checks the reception list while two searchers stop inside, outside the colours are
##   ordinary and a temporary reception pass is handed back, the pass names a school that sounds unfamiliar.
## The rest of the endings still go straight to their cards (docs/plan/结局分镜.md).

signal finished(skipped: bool)

const DEFS := {"knife":{"dur":16.0,"outdoor":false},"beast":{"dur":9.0,"outdoor":false}, "face": {"dur": 10.0, "outdoor": true}, "international": {"dur": 20.0, "outdoor": false}, "dismissal": {"dur": 18.0, "outdoor": false}, "portal": {"dur": 10.0, "outdoor": false}, "cyber": {"dur": 16.0, "outdoor": false}, "car": {"dur": 10.0, "outdoor": false}}
const STAGED := ["knife","international", "dismissal", "portal", "cyber", "car"]
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
var _campus: Dictionary = {}
var _lit := false                   # blocks are shaded by the stage's ambient light (the cyber interiors)
var _stage_env: Environment
var _dis_gate := Vector3.ZERO
var _dis_teach := Vector2.ZERO
var _campus_env: Environment
var _campus_light: CampusLighting
var _cy_base := Vector3.ZERO
var _car_switch: Callable          # the app's world switch for the car intro (garage -> outside the gate)
var _car_tsec := 0.0
var _car_live := false
var _car_switched := false
var _car_p := Vector3.ZERO
var _car_f := Vector3.FORWARD
var _car_gate := Vector3.ZERO
var _car_figs: Array = []
var _device: PortalDevice          # the portal rig in the real lab (the staged fallback has plain blocks instead)
var _device_at := Vector3.ZERO
var _last_kk := 0.0
var audio: AudioFx  ## set by the caller before begin(); the scenes' own sounds (engine, hum, the gate's second click, the cyber ending bed)
var _world: Node3D
var _world_was_visible := true
var _how := "exam"
var _st: Array = []
var _walk: Array = []
var _list: Node3D
var _pass: Node3D
var _pass2: Node3D
var _speakers: Array = []
var _students: Array = []
var _line: Array = []
var _walkers: Array = []
var _windows: Array = []
var _ledger: Label3D
var _dis_said := {}
var _rails: Array = []
var _leds: Array = []
var _beam: MeshInstance3D
var _thing: Node3D
var _log: CutScreen
var _arch: CutScreen
var _lamps: Node3D
var _tall: Node3D
var _sky: MeshInstance3D
var _sky_mat: StandardMaterial3D
var _log_n := -1
var _arch_n := -1
var _door: MeshInstance3D
var _flash: ColorRect
var _beast: BeastScene
var _knife: KnifeScene
var _normal_before := 0.0
var _cut_clock := 700.0
var _live_lighting: CampusLighting


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
	ui.cut_mode(true)
	_campus = campus
	_ui = ui
	_normal_before = ui.scene_post().world_normal
	_cut_clock = float(opts.get("tsec",700.0))
	_live_lighting = world.lighting if world is CampusWorld else null
	_player = player
	_on_beep = on_beep
	_dur = float(DEFS[id]["dur"])
	k = 0.0
	on = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Node3D.new()
	_root.name = "EndingProps"
	_world = world
	# 《门》 plays in the real lab with the real rig when the player is there (the ending only starts there).
	var live_portal := id == "portal" and String(world.get("scene_id")) == "lab1"
	# 《闸门》片头 starts in the real garage (the world stays) and switches to the real outside of the gate halfway.
	_car_live = id == "car" and opts.has("switch") and String(world.get("scene_id")) != "out"
	if _car_live:
		_car_switch = opts["switch"]
		_car_tsec = float(opts.get("tsec", 0.0))
		add_child(_root)
	elif STAGED.has(id) and not live_portal:
		# Its own stages far from the real scene: the world is hidden meanwhile.
		_how = String(opts.get("how", "exam"))
		_world_was_visible = world.visible
		world.visible = false
		add_child(_root)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color(0.23, 0.25, 0.27)
		_stage_env = env.environment
		if id == "cyber":
			# The interiors are lit by an ambient level the storyboard sets per stage (the old lightState hook), with fog.
			env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.environment.ambient_light_color = Color(0.9, 0.95, 0.95)
			env.environment.fog_enabled = true
			env.environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
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
	if id=="knife":
		_knife=KnifeScene.new()
		_root.add_child(_knife)
		_knife.begin()
		_apply(0)
		return
	if id == "beast":
		_beast = BeastScene.new()
		_root.add_child(_beast)
		_beast.begin(CampusData.layout("teach1"))
		_apply(0.0)
		return
	if id == "car":
		snd("scene.engine")
		if _car_live:
			_setup_live_car(world, player)
		else:
			_setup_car()
		_ui.cut_fade(0.0)
		_apply(0.0)
		return
	if id == "cyber":
		# Ambient out, the ending's own bed in (faded when the scene ends).
		if audio != null and is_instance_valid(audio):
			audio.duck(_dur)
		snd("scene.cyberEnd")
		_setup_cyber()
		_ui.cut_fade(0.0)
		_apply(0.0)
		return
	if id == "portal":
		snd("scene.hum")
		if live_portal:
			_setup_live_portal(world)
		else:
			_setup_portal()
		_ui.cut_fade(0.0)
		_apply(0.0)
		return
	if id == "dismissal":
		_setup_dis()
		_ui.cut_fade(0.0)
		_apply(0.0)
		return
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


## A sound of the scene; silent without audio attached (tests, headless).
func snd(sound_id: String, opts: Dictionary = {}) -> void:
	if audio != null and is_instance_valid(audio):
		audio.play(sound_id, opts)


func _look(from: Vector3, to: Vector3) -> void:
	if _sky != null:
		_sky.global_position = from
	cam.global_position = from
	if from.distance_to(to) > 0.01:
		cam.look_at(to, Vector3.UP)


func _apply(kk: float) -> void:
	if kind=="knife":
		var frame := _knife.apply(kk,cam)
		_ui.cut_fade(frame["fade"])
		if frame.has("caption"): _ui.cut_caption(frame["caption"])
		return
	var norm := _normal_before
	if kind=="beast":
		norm=phase(kk,.5,.95)
	elif kind=="portal":
		norm=phase(kk,.6,.95)
	elif kind=="cyber":
		norm=phase(kk*16.0,11.4,13.8)
	_ui.set_normal_world(norm)
	if kind in ["beast","portal"] and is_instance_valid(_live_lighting):
		_live_lighting.world_normal=norm
		_live_lighting.update(0,_cut_clock,cam)
		_ui.scene_post().parameter("exposure",_live_lighting.post_exposure)
	if kind == "beast":
		var state := _beast.apply(kk,cam,_player.view_motion.shake_enabled)
		_ui.cut_fade(state["fade"])
		return
	if kind == "international":
		_apply_intl(kk)
		return
	if kind == "dismissal":
		_apply_dis(kk)
		return
	if kind == "portal":
		_apply_portal(kk)
		return
	if kind == "cyber":
		_apply_cyber(kk)
		return
	if kind == "car":
		_apply_car(kk)
		return
	_ui.cut_fade(clampf(face_fade(kk), 0.0, 1.0))
	if kk < 0.3:
		(_lamp.material_override as StandardMaterial3D).albedo_color = face_lamp(kk)
		if kk > 0.16 and not _beeped:
			_beeped = true
			if _on_beep.is_valid():
				_on_beep.call()
			# The gate answers with two clicks, 120 ms apart (the first is the app's own).
			get_tree().create_timer(0.12, true).timeout.connect(func() -> void: snd("ui.click"))
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
	if not is_instance_valid(_root) or not _root.is_inside_tree() or not is_instance_valid(cam) or not cam.is_inside_tree():
		cancel()
		return
	k += delta / _dur
	if k >= 1.0:
		end(false)
		return
	_apply(k)


func end(skipped: bool) -> void:
	_finish(skipped, true)


## Leaving a run is not completing or skipping its ending. Do not call the old continuation.
func cancel() -> void:
	_finish(true, false)


func _finish(skipped: bool, notify: bool) -> void:
	if not on:
		return
	on = false
	if is_instance_valid(_ui):
		_ui.set_normal_world(_normal_before)
		if is_instance_valid(_live_lighting) and _live_lighting.is_inside_tree():
			_live_lighting.world_normal=_normal_before
			_live_lighting.update(0,_cut_clock,_player.camera if is_instance_valid(_player) else null)
			_ui.scene_post().parameter("exposure",_live_lighting.post_exposure)
		_ui.cut_mode(false)
		_ui.cut_caption("")
		_ui.cut_flash(0.0)
		_ui.cut_fade(0.0)
	if (kind == "cyber" or not notify) and audio != null and is_instance_valid(audio):
		audio.stop("scene")
	if STAGED.has(kind) and is_instance_valid(_world):
		_world.visible = _world_was_visible
	if is_instance_valid(_player) and is_instance_valid(_player.camera):
		_player.camera.current = true
	if is_instance_valid(_root):
		_root.queue_free()
	if notify:
		finished.emit(skipped)


# ---- 《外国语学生》 ----

func _box(g: Node3D, w: float, h: float, d: float, c: Color, x: float, y: float, z: float, glow: bool = false) -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, d)
	m.mesh = bm
	var mat := StandardMaterial3D.new()
	# The scenes lit by the stage's ambient (the cyber interiors) get shaded blocks; lamps and everything else stay flat.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if (glow or not _lit) else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.albedo_color = c
	mat.disable_fog = glow or not _lit
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


# ---- 《放学》 ----

## The four stages by time (seconds): broadcast room, classroom, stairwell, gate.
static func dis_stage(t: float) -> int:
	return 0 if t < 3.2 else (1 if t < 7.8 else (2 if t < 12.0 else 3))


static func dis_edge(t: float) -> float:
	var edge := 0.0
	for x: float in [3.2, 7.8, 12.0, 13.2, 15.6]:
		edge = maxf(edge, maxf(0.0, 1.0 - absf(t - x) / 0.12))
	return maxf(edge, (t - 17.4) / 0.6 if t > 17.4 else 0.0)


static func dis_caption(t: float) -> String:
	var s := dis_stage(t)
	if s == 0:
		return "广播：放学。全体同学，从北门离校。\n你的声音从走廊尽头传回来，慢了半拍。"
	if s == 1:
		return "几十把椅子同时往后挪。没有人说话。"
	if s == 2:
		return "走廊尽头的高个子没有动。人流从它身边经过。"
	return "登记簿翻到了新的一页：放学 · 全体。" if (t - 12.0) / 6.0 < 0.6 else "你回过头。教学楼的灯，一层一层熄灭。"


func _room(g: Node3D, w: float, d: float) -> void:
	_box(g, w, 0.08, d, Color("#414944"), 0, -0.04, 0)
	_box(g, w, 3.0, 0.08, Color("#65706a"), 0, 1.5, -d / 2.0)
	_box(g, 0.08, 3.0, d, Color("#4e5b58"), -w / 2.0, 1.5, 0)


## An exported piece of equipment (tools/export_scenes --only props): feet at the origin, placed as the old Kit.asset did.
func _prop(g: Node3D, prop_name: String, x: float, y: float, z: float, ry: float) -> Node3D:
	var packed := load(("res://assets/campus/%s.glb" % prop_name) if prop_name.contains("/") else ("res://assets/campus/props/%s.glb" % prop_name)) as PackedScene
	if packed == null:
		return null
	var n := packed.instantiate() as Node3D
	n.position = Vector3(x, y, z)
	n.rotation.y = ry
	g.add_child(n)
	return n


## A text screen on a quad (the old screen()): the canvas is redrawn only when its content changes.
func _screen(parent: Node3D, screen_mode: String, w: int, h: int, quad: Vector2, pos: Vector3) -> CutScreen:
	var vp := CutScreen.new()
	vp.setup(screen_mode, w, h)
	parent.add_child(vp)
	var q := QuadMesh.new()
	q.size = quad
	var mi := MeshInstance3D.new()
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = vp.get_texture()
	m.disable_fog = true
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return vp


func _label(text: String, size: float, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = size / 64.0 * 1.6
	l.modulate = color
	l.shaded = false
	l.double_sided = true
	return l


func _setup_dis() -> void:
	for i in 4:
		var g := Node3D.new()
		g.position.x = float(i) * 28.0 if i < 3 else 84.0
		_root.add_child(g)
		_st.append(g)
	var a: Node3D = _st[0]
	_room(a, 5, 5)
	_box(a, 2, 0.12, 0.7, Color("#564d3e"), 0, 0.88, 0)
	_box(a, 0.1, 0.42, 0.1, Color("#202c29"), -0.4, 1.15, 0)
	var rec := _label("放学通知\n第二天 · 全体离校", 0.2, Color("#e7e2ca"))
	rec.position = Vector3(0, 1.7, -2.35)
	a.add_child(rec)
	for i in 5:
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.35, 0.22, 0.12)
		m.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color("#313b34")
		m.material_override = mat
		m.position = Vector3(-1.6 + float(i) * 0.8, 2.55, -2.37)
		a.add_child(m)
		_speakers.append(m)
	var b: Node3D = _st[1]
	_room(b, 12, 10)
	var board := _label("放  学", 0.5, Color("#e7e2ca"))
	board.position = Vector3(0, 1.8, -4.93)
	b.add_child(board)
	for i in 24:
		var x := float(i % 6 - 2) * 1.6 - 0.8
		var z := float(i / 6) * 1.8 - 2.5
		_box(b, 0.9, 0.08, 0.55, Color("#655944"), x, 0.76, z + 0.4)
		_box(b, 0.42, 0.55, 0.08, Color("#605541"), x, 0.64, z - 0.3)
		var chair: MeshInstance3D = b.get_child(b.get_child_count() - 1)
		var stu := _fig(b, "sit", Color("#465353"), x, z, PI)
		_students.append({"fig": stu, "chair": chair, "z": z, "x": x, "stood": false})
	var c: Node3D = _st[2]
	_room(c, 7, 10)
	for i in 12:
		_box(c, 1.5, float(i + 1) * 0.17, 0.28, Color("#737c75"), -1, float(i + 1) * 0.17 / 2.0, 2.5 - float(i) * 0.28)
		_box(c, 1.5, 0.13, 0.28, Color("#626d69"), 1, 2.04 + float(i + 1) * 0.17 - 0.065, -0.58 + float(i) * 0.28)
	_box(c, 3.6, 0.12, 1.0, Color("#7e8780"), 0, 2.04, -1.1)
	for i in 10:
		_line.append(_fig(c, "person", Color("#465353"), -1.0, 1.5, 0.0))
	_fig(c, "tall", Color("#465353"), 2.6, 3.7, 0.0)
	# The last stage is the real campus: the north gate and the front of the teaching building (the world comes back for it).
	var d: Node3D = _st[3]
	_dis_gate = gate_scene(_campus, "n")
	var spot := DayBanner.spot(_world.get("layout") as Dictionary if _world != null else {})
	_dis_teach = Vector2(spot.x, spot.z - 0.82)   # x centre of the building, z of its front line
	for i in 16:
		_walkers.append(_fig(_root, "person", Color("#3b4847"), _dis_gate.x + 5.35, _dis_gate.z + 3.8 - float(i) * 0.65, PI))
	_ledger = _label("放学 · 全体\n准予离校", 0.12, Color("#e7e2ca"))
	_ledger.position = _dis_gate + Vector3(-1.3, 1.1, 1.0)
	_ledger.rotation.x = -0.4
	_root.add_child(_ledger)
	for i in 5:
		var w := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(20, 0.5, 0.03)
		w.mesh = wm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color("#aba17c")
		w.material_override = mat
		w.position = Vector3(_dis_teach.x, 2.7 + float(i) * 3.2, _dis_teach.y + 0.04)
		w.visible = false
		_root.add_child(w)
		_windows.append(w)
	d.visible = false
	# The camera environment of the real campus (the staged rooms sit in a flat grey one).
	var lit: Variant = _world.get("lighting")
	if lit is CampusLighting:
		_campus_env = (lit as CampusLighting).env
		# The last stage is at dusk (the old stage hour 17.4); the world's own lighting is paused with the tree.
		(lit as CampusLighting).update(0.0, 17.4 * 60.0, cam)


func _apply_dis(kk: float) -> void:
	var t := kk * 18.0
	var s := dis_stage(t)
	for i in _st.size():
		(_st[i] as Node3D).visible = i == s
	_ui.cut_caption(dis_caption(t))
	if s == 0:
		if not _dis_said.has("radio"):
			_dis_said["radio"] = true
			snd("dread.radio", {"k": 0.4})
		_look(Vector3(1.5, 1.55, 2.1), Vector3(0.0, 1.25, -1.4))
		for i in _speakers.size():
			var mat := (_speakers[i] as MeshInstance3D).material_override as StandardMaterial3D
			mat.albedo_color = Color("#8b9d83") if t > 0.25 + float(i) * 0.35 else Color("#313b34")
	elif s == 1:
		if not _dis_said.has("chairs"):
			_dis_said["chairs"] = true
			snd("dread.chair", {"k": 0.6})
		var p := phase(kk, 3.2 / 18.0, 7.8 / 18.0)
		_look(Vector3(28.0 + 5.0, 2.1, 3.9), Vector3(28.0 - 0.5, 1.2, -2.0))
		for i in _students.size():
			var o: Dictionary = _students[i]
			var u := maxf(0.0, minf(1.0, (p - float(i) * 0.012) * 3.0))
			(o["chair"] as Node3D).position.z = float(o["z"]) - 0.3 - u * 0.3
			var f: Node3D = o["fig"]
			f.position.z = float(o["z"]) + maxf(0.0, u - 0.65) * 0.8
			if u > 0.45 and not bool(o["stood"]):
				o["stood"] = true
				var pos := f.position
				var rot := f.rotation
				f.queue_free()
				var nf := _fig(_st[1] as Node3D, "person", Color("#465353"), float(o["x"]), float(o["z"]), PI)
				nf.position = pos
				nf.rotation = rot
				o["fig"] = nf
	elif s == 2:
		var u2 := (t - 7.8) / 4.2
		_look(Vector3(56.0 + 3.6, 6.2, 7.6), Vector3(56.0, 1.4, 0.4))
		for i in _line.size():
			var f2: Node3D = _line[i]
			var p2 := fmod(u2 * 0.7 + float(i) * 0.08, 1.0)
			if p2 < 0.5:
				f2.position = Vector3(-1.0, 2.04 * (1.0 - p2 * 2.0), -0.9 + p2 * 6.7)
				f2.rotation.y = PI
			else:
				f2.position = Vector3(1.0, 4.08 - (p2 - 0.5) * 4.08, 2.5 - (p2 - 0.5) * 6.7)
				f2.rotation.y = 0.0
	else:
		var v := (t - 12.0) / 6.0
		var g := _dis_gate
		for i in _walkers.size():
			(_walkers[i] as Node3D).position = g + Vector3(5.35, 0.0, 3.8 - float(i) * 0.65 - v * 8.0)
		_ledger.visible = true
		if v < 0.2:
			_look(g + Vector3(-1.3, 1.6, 2.1), g + Vector3(-1.3, 1.1, 1.0))
		elif v < 0.6:
			_look(g + Vector3(4.75, 1.9, -9.0 - (v - 0.2) * 10.0), g + Vector3(5.35, 1.4, 3.0))
		else:
			_look(Vector3(_dis_teach.x, 8.5, _dis_teach.y + 24.0), Vector3(_dis_teach.x, 8.0, _dis_teach.y))
		for i in _windows.size():
			var w := _windows[i] as MeshInstance3D
			w.visible = v >= 0.6
			(w.material_override as StandardMaterial3D).albedo_color = Color("#050909") if v > 0.68 + float(i) * 0.055 else Color("#aba17c")
	# Only the last stage is in the real campus.
	if is_instance_valid(_world):
		_world.visible = s == 3
	cam.environment = _campus_env if s == 3 else _stage_env
	for w2: MeshInstance3D in _windows:
		w2.visible = w2.visible and s == 3
	_ledger.visible = s == 3
	for f3: Node3D in _walkers:
		f3.visible = s == 3
	_ui.cut_fade(clampf(dis_edge(t), 0.0, 1.0))


# ---- 《门》 ----

## The device's state by progress: charge fraction (0..1), door open, entering (0..1).
static func portal_state(kk: float) -> Dictionary:
	return {"charge": clampf(kk / 0.45, 0.0, 1.0), "open": kk >= 0.45, "enter": phase(kk, 0.62, 1.0) if kk >= 0.62 else 0.0}


## The camera path: hesitates (steps back) between 0.5 and 0.7, pushes in from 0.62; the height follows the ring.
static func portal_camera(kk: float, p: Vector3, ring_y: float) -> Dictionary:
	var hes := phase(kk, 0.5, 0.6) * (1.0 - phase(kk, 0.62, 0.7))
	var push := phase(kk, 0.62, 0.98)
	var orbit := (1.0 - phase(kk, 0.0, 0.45)) * 0.9
	var z := lerpf(p.z + 3.4, p.z + 0.05, push) + 0.6 * hes
	var x := p.x + sin(orbit) * 1.2
	return {"from": Vector3(x, lerpf(1.45, ring_y, push), z), "to": Vector3(p.x, ring_y, p.z)}


## The real rig on the lab's bench (the first K tile), the world around it as it is.
func _setup_live_portal(world: Node3D) -> void:
	var spot := PortalDevice.bench_spot(CampusData.layout("lab1"))
	_device_at = Vector3(spot.x, 0.0, spot.y)
	_device = PortalDevice.new()
	_device.build()
	_device.position = _device_at
	_device.set_state("base", 0.0)
	_root.add_child(_device)
	_root.set_meta("ring_y", _device.ring_y)
	_device.self_tick = false                  # the cut drives it by progress
	if world.has_method("hide_portal"):
		world.call("hide_portal")                # the lab's own rig steps aside for the cut


func _setup_portal() -> void:
	var g := Node3D.new()
	_root.add_child(g)
	_st.append(g)
	_box(g, 30, 0.05, 30, Color("#2b2f31"), 0, 0, 0)
	_box(g, 30, 4, 0.2, Color("#3a4244"), 0, 2, -8)
	_box(g, 1.1, 0.05, 0.5, Color("#7d858d"), 0, 0.96, 0)           # the base on the bench top (0.935 m)
	_box(g, 1.6, 0.935, 0.7, Color("#4a4f52"), 0, 0.4675, 0)         # the bench
	var ring_y := 0.935 + 0.62 + 0.05
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("#7d858d")
	steel.emission_enabled = true
	steel.emission = Color("#1a1d21")
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.585
	tm.outer_radius = 0.655
	ring.mesh = tm
	ring.rotation.x = PI / 2.0
	ring.position = Vector3(0, ring_y, 0)
	ring.material_override = steel
	g.add_child(ring)
	for i in 3:
		var r := MeshInstance3D.new()
		var rm := TorusMesh.new()
		rm.inner_radius = 0.50 + 0.03 * float(i)
		rm.outer_radius = 0.515 + 0.03 * float(i)
		r.mesh = rm
		r.rotation = Vector3(PI / 2.0, 0.0, 0.0)
		r.position = Vector3(0, ring_y, 0.002 * float(i))
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color("#70d0ff")
		r.material_override = m
		r.visible = false
		g.add_child(r)
		_rails.append(r)
	_door = MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.52
	dm.bottom_radius = 0.52
	dm.height = 0.01
	_door.mesh = dm
	_door.rotation.x = PI / 2.0
	_door.position = Vector3(0, ring_y, 0)
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.albedo_color = Color(0.45, 0.78, 1.0, 0.0)
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_door.material_override = dmat
	g.add_child(_door)
	_root.set_meta("ring_y", ring_y)


func _apply_portal(kk: float) -> void:
	var st := portal_state(kk)
	var ring_y := float(_root.get_meta("ring_y"))
	if _device != null:
		if kk < 0.45:
			_device.set_state("charge", kk / 0.45)
		elif kk < 0.62:
			_device.set_state("open", 1.0)
		else:
			_device.set_state("enter", float(st["enter"]))
		_device.tick(clampf((kk - _last_kk) * _dur, 0.0, 0.1))
		_last_kk = kk
		var live := portal_camera(kk, _device_at, ring_y)
		_look(live["from"], live["to"])
		_ui.cut_fade(0.0)
		_ui.cut_flash((kk - 0.88) / 0.12 * 0.9 if kk > 0.88 else 0.0)
		return
	for i in _rails.size():
		(_rails[i] as MeshInstance3D).visible = float(st["charge"]) > float(i) / 3.0
	var dmat := _door.material_override as StandardMaterial3D
	var a := 0.0
	if bool(st["open"]):
		a = 0.55 + 0.4 * float(st["enter"])
	dmat.albedo_color = Color(0.45 + 0.4 * float(st["enter"]), 0.78 + 0.1 * float(st["enter"]), 1.0, a)
	var cam_path := portal_camera(kk, Vector3.ZERO, ring_y)
	_look(cam_path["from"], cam_path["to"])
	var flash := (kk - 0.88) / 0.12 * 0.9 if kk > 0.88 else 0.0
	_ui.cut_fade(0.0)
	_ui.cut_flash(flash)


# ---- 《网安仙人》 ----

const CY_LOG := [[0.25, "$ campusctl shutdown --confirm"], [0.75, "stop attendance ............ OK"], [1.35, "stop doors ................. OK"],
	[1.95, "broadcast: 全体同学请注——"], [2.25, "stop observation ........... OK"], [2.75, "stop control ............... OK"]]
const CY_PAIRS := [["首次部署：2026-09-01", "部署前：无任何异常记录", "纸质档案扫描：1987 年", "走廊里出现不在值班表上的人"],
	["巡察行为：全部由控制器产生", "断链即全部停止", "断链故障记录：控制链离线后", "仍收到回执（签发节点：——）"],
	["退出身份：已注销", "数据已删除", "「注销」字段原始定义：", "转交上层保管"]]
const CY_FLICKER := [0.10, 0.08, 0.10, 0.08, 0.10, 0.30, 0.55, 0.08, 0.10, 0.08, 0.10, 0.30]
const CY_B0 := 3.2


## The corridor tube lights: "two short one long" (on / off alternating, seconds), steady after the pattern.
static func cy_flicker_on(t: float) -> bool:
	var x := t - CY_B0
	var on := true
	for d: float in CY_FLICKER:
		if x < d:
			return on
		x -= d
		on = not on
	return true


static func cy_flicker_end() -> float:
	var e := CY_B0
	for d: float in CY_FLICKER:
		e += d
	return e


static func cy_stage(t: float) -> int:
	return 0 if t < 3.2 else (1 if t < 7.2 else (2 if t < 11.2 else 3))


## How many console lines are out at time t.
static func cy_log_lines(t: float) -> int:
	var n := 0
	for l: Array in CY_LOG:
		if t >= float(l[0]):
			n += 1
	return n


## The archive's state: header (7.35), columns (7.6), three rows (7.9 8.6 9.3), three circles (8.25 8.95 9.65), last line (10.25).
static func cy_archive_steps(t: float) -> int:
	var s := 0
	if t >= 7.35:
		s += 1
	if t >= 7.6:
		s += 1
	for r: float in [7.9, 8.6, 9.3, 8.25, 8.95, 9.65, 10.25]:
		if t >= r:
			s += 1
	return s


static func cy_fade(t: float) -> float:
	var f := 0.0
	for b: float in [3.2, 7.2, 11.2]:
		f = maxf(f, 1.0 - absf(t - b) / 0.22)
	if t > 11.2:
		f = maxf(f, 1.0 - clampf((t - 11.2) / 0.5, 0.0, 1.0))
	return clampf(maxf(f, clampf((t - 15.1) / 0.85, 0.0, 1.0)), 0.0, 1.0)


func _cy_archive_text(t: float) -> String:
	var steps := cy_archive_steps(t)
	var out := ""
	if steps >= 1:
		out += "AnthroPrank AI · 安抄派智能　校园试点档案\n控制系统：已终止\n\n"
	if steps >= 2:
		out += "公司报告　　　　　　↔　　　　　　原始记录（扫描件）\n\n"
	var rows := 0
	for r: float in [7.9, 8.6, 9.3]:
		if t >= r:
			rows += 1
	var marks := 0
	for r: float in [8.25, 8.95, 9.65]:
		if t >= r:
			marks += 1
	for i in rows:
		var p: Array = CY_PAIRS[i]
		out += "%s　%s　%s\n%s　　%s　　%s\n\n" % [p[0], "≠" if i < marks else "　", p[2], p[1], "　", p[3]]
	if t >= 10.25:
		out += "签发节点：未知" + ("" if int((t - 10.25) / 0.45) % 2 == 1 else " ▌")
	return out


func _setup_cyber() -> void:
	_lit = true
	for i in 4:
		var g := Node3D.new()
		g.position.x = float(i) * 40.0
		_root.add_child(g)
		_st.append(g)
	_sky = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 70.0
	sm.height = 140.0
	_sky.mesh = sm
	_sky_mat = StandardMaterial3D.new()
	_sky_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sky_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	_sky_mat.disable_fog = true
	_sky_mat.albedo_color = Color(0.02, 0.026, 0.03)
	_sky.material_override = _sky_mat
	_sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(_sky)
	var a: Node3D = _st[0]
	_box(a, 7, 0.1, 11, Color("#3d4446"), 0, -0.05, 0)
	_box(a, 0.12, 3.2, 11, Color("#3c4644"), -3.5, 1.6, 0)
	_box(a, 0.12, 3.2, 11, Color("#3c4644"), 3.5, 1.6, 0)
	_box(a, 7, 3.2, 0.12, Color("#36403e"), 0, 1.6, -5.5)
	_box(a, 7, 0.1, 11, Color("#2a3130"), 0, 3.2, 0)
	for i in 10:
		var side := 1.0 if i % 2 == 1 else -1.0
		var row := float(i / 2)
		_prop(a, "server_rack", side * 1.45, 0.0, -4.0 + row * 1.25, -PI / 2.0 if side > 0.0 else PI / 2.0)
		var rack_leds: Array = []
		for j in 10:
			var led := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.04, 0.035, 0.03)
			led.mesh = bm
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = Color("#6ff09a")
			led.material_override = mat
			led.position = Vector3(side * (1.45 - 0.42), 1.85 - float(j / 2) * 0.3, -4.0 + row * 1.25 - 0.25 + float(j % 2) * 0.1)
			a.add_child(led)
			rack_leds.append(led)
		_leds.append({"rack": i, "leds": rack_leds, "off": 0.55 + float((i / 2) * 2 + i % 2) * 0.22 * 0.5})
	_prop(a, "server_console", 0.0, 0.0, -4.75, 0.0)
	_prop(a, "speaker_box", 3.38, 2.65, -0.6, -PI / 2.0)       # on the wall, above the racks, where you can see it
	_box(a, 0.9, 0.04, 0.18, Color("#9fb8b8"), -1.2, 3.12, 1.5, true)    # the two emergency lights
	_box(a, 0.9, 0.04, 0.18, Color("#9fb8b8"), 1.2, 3.12, -2.5, true)
	_box(a, 0.25, 0.06, 8.0, Color("#2c3234"), 0, 3.05, -1.0)     # the cable trunking
	for i in range(-3, 4):
		_box(a, 0.02, 0.003, 11.0, Color("#2e3436"), float(i) * 0.6, 0.004, 0.0)   # the raised floor's seams
	for i in range(-9, 10):
		_box(a, 7.0, 0.003, 0.02, Color("#2e3436"), 0.0, 0.004, float(i) * 0.6)
	_log = _screen(a, "log", 1024, 320, Vector2(1.04, 0.325), Vector3(0, 1.45, -4.75 + 0.4))
	var b: Node3D = _st[1]
	_box(b, 3.2, 0.1, 24, Color("#8e9690"), 0, -0.05, -6)
	_box(b, 0.12, 2.3, 24, Color("#b3b8ad"), -1.66, 1.95, -6)
	_box(b, 0.12, 2.3, 24, Color("#b3b8ad"), 1.66, 1.95, -6)
	_box(b, 0.12, 1.2, 24, Color("#5d7267"), -1.65, 0.6, -6)
	_box(b, 0.12, 1.2, 24, Color("#5d7267"), 1.65, 0.6, -6)
	_box(b, 3.2, 0.1, 24, Color("#a9aea4"), 0, 3.12, -6)
	_box(b, 3.2, 3.1, 0.12, Color("#9fa59a"), 0, 1.55, -18)
	for i in 4:
		var dz := 3.0 - float(i) * 6.0
		# The classroom door: leaf, frame (the frame asset is half a metre deep, so it is built here) and the small window.
		_box(b, 0.05, 2.06, 0.92, Color("#6a4b33"), -1.58, 1.03, dz)
		_box(b, 0.07, 0.08, 1.06, Color("#4a3424"), -1.56, 2.1, dz)
		_box(b, 0.07, 2.1, 0.07, Color("#4a3424"), -1.56, 1.05, dz - 0.51)
		_box(b, 0.07, 2.1, 0.07, Color("#4a3424"), -1.56, 1.05, dz + 0.51)
		_box(b, 0.02, 0.36, 0.24, Color("#151a1c"), -1.55, 1.6, dz + 0.18)
		_prop(b, "locker_bank_4", -1.36, 0.0, dz - 2.6, PI / 2.0)
		for wz: float in [dz - 1.5, dz - 4.5]:
			_box(b, 0.02, 1.36, 1.62, Color("#0c1218"), 1.595, 1.64, wz)    # still night outside: a dark pane behind the glass
			_prop(b, "window_in_150", 1.58, 0.0, wz, -PI / 2.0)
	_box(b, 0.32, 0.13, 0.03, Color("#58c27a"), -1.5, 2.55, -17.4, true)           # the exit sign
	_lamps = Node3D.new()
	b.add_child(_lamps)
	for i in 6:
		_box(b, 1.3, 0.06, 0.26, Color("#7c8280"), 0, 3.05, 4.0 - float(i) * 4.0)
		_box(_lamps, 1.2, 0.03, 0.18, Color("#e8f0ea"), 0, 3.01, 4.0 - float(i) * 4.0, true)
	# The thing in the corridor: the patroller's own model, body and gear (its front is +z, towards the camera).
	_tall = _prop(b, "patrol/patrol_figure", 0.0, 0.0, -3.0, 0.0)
	if _tall != null:
		_tall.set_meta("patrol", true)
		for mi: MeshInstance3D in _tall.find_children("*", "MeshInstance3D", true, false):
			for si in mi.mesh.get_surface_count():
				var pm := mi.mesh.surface_get_material(si) as BaseMaterial3D
				if pm != null:
					pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		_tall = FigureModel.make("teacher", Color("#050607"), true, 1.12)
		_tall.position = Vector3(0, 0, -3)
		_tall.rotation.y = PI
		b.add_child(_tall)
	var c: Node3D = _st[2]
	_box(c, 6, 0.1, 6, Color("#4e5553"), 0, -0.05, 0)
	_box(c, 6, 3.2, 0.12, Color("#434b49"), 0, 1.6, -1.2)
	_box(c, 0.12, 3.2, 6, Color("#3e4544"), -3, 1.6, 1.8)
	_box(c, 0.12, 3.2, 6, Color("#3e4544"), 3, 1.6, 1.8)
	_box(c, 6, 0.1, 6, Color("#2f3534"), 0, 3.2, 1.8)
	_box(c, 1.3, 0.04, 0.7, Color("#6c5a46"), 0, 0.74, -0.62)               # the desk top and its legs
	for q: Vector2 in [Vector2(-0.6, -0.3), Vector2(0.6, -0.3), Vector2(-0.6, 0.3), Vector2(0.6, 0.3)]:
		_box(c, 0.04, 0.72, 0.04, Color("#3a3f42"), q.x, 0.37, -0.62 + q.y)
	_box(c, 0.44, 0.02, 0.14, Color("#22272a"), -0.05, 0.775, -0.38)       # the keyboard
	_prop(c, "desk_computer", -1.5, 0.0, -0.8, 0.0)
	_prop(c, "desk_computer", 1.5, 0.0, -0.8, 0.0)
	_prop(c, "chair_office", 0.95, 0.0, 0.15, PI * 0.8)
	_box(c, 0.682, 0.442, 0.035, Color("#14181a"), 0, 1.05, -0.75)         # the monitor and its stand
	_box(c, 0.06, 0.29, 0.04, Color("#1b2022"), 0, 0.4, -0.79)
	_box(c, 0.26, 0.02, 0.18, Color("#1b2022"), 0, 0.78, -0.77)
	_arch = _screen(c, "archive", 1280, 768, Vector2(0.62, 0.372), Vector3(0, 1.05, -0.75 + 0.019))
	# The last stage is the real campus at dawn, in front of the teaching building (the world comes back for it).
	var base := CampusGeometry.to_scene(null, Vector2(560.0, 1008.0) * SC)
	_cy_base = Vector3(base.x, 0.0, base.y)
	var lit: Variant = _world.get("lighting")
	if lit is CampusLighting:
		_campus_env = (lit as CampusLighting).env
		_campus_light = lit as CampusLighting

	_lit = false


## The old lightState hook of the ending: ambient, hemisphere and fog per interior stage (the dawn stage uses the world's own light).
func _cy_light(t: float, s: int) -> void:
	if _stage_env == null or s == 3:
		return
	var amb := 0.0
	var hemi := 0.0
	var fog := Color(0.02, 0.026, 0.03)
	var dens := 0.045
	if s == 0:
		var dim := clampf((t - 0.6) / 2.2, 0.0, 1.0)
		amb = 0.22 - 0.1 * dim
		hemi = 0.16 - 0.08 * dim
	elif s == 1:
		var lamp := 1.0 if t >= cy_flicker_end() else (0.95 if cy_flicker_on(t) else 0.22)
		amb = 0.17 * lamp
		hemi = 0.12 * lamp
		fog = Color(0.045, 0.05, 0.05)
	else:
		amb = 0.06
		hemi = 0.04
		fog = Color(0.01, 0.012, 0.014)
		dens = 0.07
	_stage_env.ambient_light_energy = (amb + hemi * 0.5) * CampusLighting.ENERGY_AMBIENT * 2.2
	_stage_env.fog_light_color = fog
	_stage_env.fog_density = dens


func _apply_cyber(kk: float) -> void:
	var t := kk * 16.0
	var s := cy_stage(t)
	var ox := float(s) * 40.0
	for i in _st.size():
		(_st[i] as Node3D).visible = i == s
	# Only the last stage is in the real campus; the first three are the lit interiors under a flat dark sky.
	if is_instance_valid(_world):
		_world.visible = s == 3
	cam.environment = _campus_env if s == 3 else _stage_env
	_sky.visible = s != 3
	_cy_light(t, s)
	_ui.cut_fade(cy_fade(t))
	if s == 0:
		for r: Dictionary in _leds:
			var off := float(r["off"])
			var blink := t > off - 0.09 and t < off - 0.05
			var on := t < off and not blink
			for led: MeshInstance3D in r["leds"]:
				(led.material_override as StandardMaterial3D).albedo_color = Color("#6ff09a") if on else Color("#0e1712")
		_log.show_log(CutScreen.log_lines(t))
		var dolly := phase(kk, 0.0, 0.2)
		_look(Vector3(ox + 0.18, 1.5, 1.6 - 1.7 * dolly), Vector3(ox, 1.3, -4.75))
		_sky_mat.albedo_color = Color(0.02, 0.026, 0.03)
	elif s == 1:
		var on2 := cy_flicker_on(t)
		var settled := t >= cy_flicker_end()
		_lamps.visible = on2
		var slump := phase(t, cy_flicker_end() + 0.1, cy_flicker_end() + 1.3)
		_tall.rotation = Vector3(0.12 * slump, 0.0 if _tall.get_meta("patrol", false) else PI, 0.0)
		_tall.position.y = -0.05 * slump
		var go := phase(t, 3.2, 7.2)
		_look(Vector3(ox + 0.35 - 0.15 * go, 1.6, 4.6 - 3.2 * go), Vector3(ox, 1.75 - 0.25 * slump, -3.0))
		var red := 0.32 * (1.0 - phase(t, cy_flicker_end() - 0.2, cy_flicker_end() + 0.6)) * (1.0 if on2 else 0.6)
		_sky_mat.albedo_color = Color(0.03 + red * 0.3, 0.035, 0.036)
		if settled:
			_lamps.visible = true
	elif s == 2:
		_arch.show_archive(t)
		var push := phase(t, 7.2, 10.4)
		_look(Vector3(ox + 0.12 * (1.0 - push), 1.12 * (1.0 - push) + 1.05 * push, -0.75 + lerpf(1.7, 0.62, push)), Vector3(ox, 1.05, -0.75))
		_sky_mat.albedo_color = Color(0.01, 0.012, 0.014)
	else:
		var rise := phase(t, 11.2, 16.0)
		# Day breaks: sunrise to seven in the morning, the colours come back with the normal light.
		if _campus_light != null:
			_campus_light.world_normal=_ui.scene_post().world_normal
			_campus_light.update(0.0, (6.0 + 1.1 * clampf((t - 11.2) / 4.8, 0.0, 1.0)) * 60.0, cam)
			_ui.scene_post().parameter("exposure",_campus_light.post_exposure)
		_look(_cy_base + Vector3(2.0 * rise, 1.5 + 8.5 * rise, 6.0 + 12.0 * rise), _cy_base + Vector3(0.0, 3.0 + 19.0 * rise, -28.0))


# ---- 《闸门》 opening ----

## The headlights: off, flicker twice, then steady; something shows only during the flicker.
static func car_lights(kk: float) -> float:
	if kk < 0.06:
		return 0.0
	if kk < 0.16:
		return 1.0 if sin(kk * 120.0) > 0.0 else 0.2
	return 1.0


static func car_thing_visible(kk: float) -> bool:
	return kk > 0.08 and kk < 0.16 and car_lights(kk) < 1.0


static func car_fade(kk: float) -> float:
	if kk < 0.3:
		return 0.0
	if kk < 0.36:
		return (kk - 0.3) / 0.06
	if kk < 0.42:
		return 1.0 - (kk - 0.36) / 0.06
	return (kk - 0.9) / 0.1 if kk > 0.9 else 0.0


## Headlights in the real garage: the player's spot and facing, the beam on the floor 4.4 m ahead, the thing 6.5 m ahead (cutscene.js car).
func _setup_live_car(world: Node3D, player: PlayerController) -> void:
	_car_p = Vector3(player.global_position.x, 0.0, player.global_position.z)
	var fwd := -player.global_transform.basis.z
	_car_f = Vector3(fwd.x, 0.0, fwd.z).normalized()
	_beam = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.01
	_beam.mesh = cm
	_beam.scale = Vector3(1.3, 1.0, 3.4)
	_beam.position = _car_p + _car_f * 4.4 + Vector3(0, 0.02, 0)
	_beam.rotation.y = atan2(_car_f.x, _car_f.z)
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color = Color(1.0, 0.9, 0.69, 0.0)
	_beam.material_override = bm
	_root.add_child(_beam)
	_thing = FigureModel.make("roam", Color("#05070a"), true)
	_thing.position = _car_p + _car_f * 6.5
	_thing.rotation.y = atan2(-_car_f.x, -_car_f.z) + PI    # faces the car
	_thing.visible = false
	_root.add_child(_thing)
	_car_gate = gate_scene(_campus, "n")
	for i in 12:
		var f := FigureModel.make("person", Color("#040506"), true, 1.0 + float((i * 7) % 3) * 0.05)
		f.visible = false
		_root.add_child(f)
		_car_figs.append(f)
	var lit: Variant = world.get("lighting")
	if lit is CampusLighting:
		_campus_env = (lit as CampusLighting).env
		_campus_light = lit as CampusLighting
	cam.environment = _campus_env


## Halfway: out through the gate. The app switches to the real outdoors; the black figures come out of the gate behind you.
func _car_go_outside() -> void:
	_car_switched = true
	_beam.visible = false
	_thing.visible = false
	var nw: Variant = _car_switch.call()
	if nw is Node3D:
		_world = nw as Node3D
		_world.visible = true
		var lit: Variant = _world.get("lighting")
		if lit is CampusLighting:
			_campus_light = lit as CampusLighting
			_campus_env = _campus_light.env
			_campus_light.update(0.0, _car_tsec, cam)
		cam.environment = _campus_env


func _apply_live_car(kk: float) -> void:
	_ui.cut_fade(clampf(car_fade(kk), 0.0, 1.0))
	if kk < 0.36:
		((_beam.material_override) as StandardMaterial3D).albedo_color = Color(1.0, 0.9, 0.69, 0.2 * car_lights(kk))
		_thing.visible = car_thing_visible(kk)
		var sh := sin(kk * 70.0) * 0.012 if kk > 0.16 else 0.0
		_look(_car_p + Vector3(0, 1.15 + sh, 0), _car_p + _car_f * 6.0 + Vector3(0, 1.0, 0))
		return
	if not _car_switched:
		_car_go_outside()
	var t := clampf((kk - 0.36) / 0.64, 0.0, 1.0)
	var g := _car_gate
	var z := lerpf(g.z - 2.0, g.z - 30.0, ease_k(t))
	var sway := sin(kk * 34.0) * 0.025
	var from := Vector3(g.x + sway, 1.25, z)
	_look(from, Vector3(g.x, 1.8, g.z + 24.0))
	for i in _car_figs.size():
		var f: Node3D = _car_figs[i]
		var side := 1.0 if i % 2 == 1 else -1.0
		var row := float(i / 2)
		var c := clampf((t - 0.12 - float(i) * 0.03) / 0.7, 0.0, 1.0)
		f.visible = c > 0.0
		f.position = Vector3(g.x + side * (0.5 + row * 0.28) * (1.0 - 0.4 * c), absf(sin(kk * 30.0 + float(i))) * 0.06, lerpf(g.z + 3.0, z + 5.0 + row * 1.5, c * 0.92))
		f.rotation.y = atan2(f.position.x - from.x, f.position.z - from.z)
	if _campus_env != null:
		_campus_env.fog_density = lerpf(0.012, 0.04, t)


func _setup_car() -> void:
	var a := Node3D.new()
	_root.add_child(a)
	_st.append(a)
	_box(a, 16, 0.05, 30, Color("#2e3234"), 0, 0, 10)
	_box(a, 16, 3.5, 0.2, Color("#3a4042"), 0, 1.75, 16)
	_box(a, 0.2, 3.5, 30, Color("#3a4042"), -8, 1.75, 10)
	_box(a, 0.2, 3.5, 30, Color("#3a4042"), 8, 1.75, 10)
	_beam = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.01
	_beam.mesh = cm
	_beam.scale = Vector3(1.3, 1.0, 3.4)
	_beam.position = Vector3(0, 0.02, 4.4)
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color = Color(1.0, 0.9, 0.69, 0.0)
	_beam.material_override = bm
	a.add_child(_beam)
	_thing = FigureModel.make("roam", Color("#05070a"), true)
	_thing.position = Vector3(0, 0, 6.5)
	_thing.rotation.y = 0.0          # faces -z, towards the car
	a.add_child(_thing)
	var b := Node3D.new()
	b.position.x = 60.0
	_root.add_child(b)
	_st.append(b)
	_box(b, 80, 0.05, 120, Color("#3b3e3a"), 0, 0, -20)
	_box(b, 0.6, 3.2, 0.6, Color("#6d6a62"), -2.4, 1.6, 0)
	_box(b, 0.6, 3.2, 0.6, Color("#6d6a62"), 2.4, 1.6, 0)
	_box(b, 5.4, 0.4, 0.6, Color("#6d6a62"), 0, 3.2, 0)
	for i in 12:
		var f := FigureModel.make("person", Color("#040506"), true, 1.0 + float((i * 7) % 3) * 0.05)
		f.visible = false
		b.add_child(f)
		_walk.append(f)
	_sky = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 70.0
	sm.height = 140.0
	_sky.mesh = sm
	_sky_mat = StandardMaterial3D.new()
	_sky_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sky_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	_sky_mat.disable_fog = true
	_sky_mat.albedo_color = Color(0.02, 0.025, 0.035)
	_sky.material_override = _sky_mat
	_root.add_child(_sky)


func _apply_car(kk: float) -> void:
	if _car_live:
		_apply_live_car(kk)
		return
	var out := kk >= 0.36
	(_st[0] as Node3D).visible = not out
	(_st[1] as Node3D).visible = out
	_ui.cut_fade(clampf(car_fade(kk), 0.0, 1.0))
	if not out:
		var on := car_lights(kk)
		((_beam.material_override) as StandardMaterial3D).albedo_color = Color(1.0, 0.9, 0.69, 0.2 * on)
		_thing.visible = car_thing_visible(kk)
		var sh := sin(kk * 70.0) * 0.012 if kk > 0.16 else 0.0
		_look(Vector3(0, 1.15 + sh, 0), Vector3(0, 1.0, 6))
		_sky_mat.albedo_color = Color(0.02, 0.025, 0.035)
		return
	var t := clampf((kk - 0.36) / 0.64, 0.0, 1.0)
	var gx := 60.0
	var z := lerpf(-2.0, -30.0, ease_k(t))
	var sway := sin(kk * 34.0) * 0.025
	var cam_pos := Vector3(gx + sway, 1.25, z)
	_look(cam_pos, Vector3(gx, 1.8, 24.0))
	var i := 0
	for f: Node3D in _walk:
		var side := 1.0 if i % 2 == 1 else -1.0
		var row := float(i / 2)
		var c := clampf((t - 0.12 - float(i) * 0.03) / 0.7, 0.0, 1.0)
		f.visible = c > 0.0
		f.position = Vector3(side * (0.5 + row * 0.28) * (1.0 - 0.4 * c), absf(sin(kk * 30.0 + float(i))) * 0.06, lerpf(3.0, z + 5.0 + row * 1.5, c * 0.92))
		f.rotation.y = atan2(f.position.x + gx - cam_pos.x, f.position.z - cam_pos.z)
		i += 1
	_sky_mat.albedo_color = Color(0.03, 0.035, 0.05)
