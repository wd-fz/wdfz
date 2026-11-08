class_name OpeningCut
extends Node
## The new-game opening, played live in the first classroom (opening.js and CUT_DEF.opening, reference
## wd-fz.github.io@0bf508a), then the camera is handed to the player exactly where the game starts (seat,
## facing, sitting posture like a normal start). Storyboard (full, about 26 s):
##   1 an ordinary fourth period: from the back row, slowly towards the podium, chalk dust in the light;
##   2 something is off: the teacher beside the podium reads half a line, stops, starts again;
##   3 time stops: the chalk dust hangs in the air; the camera turns from the dust to "you";
##   4 falling: you slump onto the desk, eyes close, black;
##   5 first person: the head comes up from the desk, a full room where nobody breathes;
##   6 handover.
## Old players (the opening was seen before) get only 4–6 (about 11 s). The world does not move
## (the app keeps the game paused), no SAN is spent, nothing appears, no saving. Click, Space, Enter or Esc skip;
## skipping and finishing hand over the same way. Captions are the prologue's text.
## Layout (domain/classroom-layout.js v4, in cells; one cell = one tile of the room): the player's class starts at
## column 45, the desk rows are 7,8,10,11,13,14, the midline is row 11.0, the board is on the west wall.

signal finished(skipped: bool)

const DUR_FULL := 26.0
const DUR_SHORT := 11.0
const SHORT_FROM := 0.58
const C0 := 45.0
const R0 := 7.0
const MID := 11.0
const AISLE_N := 9.5
const AISLE_S := 12.5
const LINES := [
	[0.03, 0.21, "你是这学期转来的。高二（二）班，第四节，语文。"],
	[0.24, 0.40, "老师在念一篇课文，念到一半，又从头念了一遍。"],
	[0.42, 0.57, "粉笔灰在光里飘。你开始数秒：一，二，三……数到第七秒，它们停在了半空。"],
	[0.59, 0.71, "眼皮很重。黑板上的字开始往下淌。你把脸埋进胳膊里。"],
	[0.79, 0.92, "你睁开眼。教室里还是坐满了人。只是没有一个人在呼吸。"],
	[0.93, 1.01, "下课铃没有响。它，已经知道你醒了。"]]

var on := false
var short := false
var audio: AudioFx  ## set by the caller; the opening's beat sounds (crackle, blink, wake)
var _sounded := {}
var k := 0.0
var cam: Camera3D
var _ui: GameUI
var _lighting: CampusLighting
var _normal_before := 0.0
var _room: Dictionary = {}
var _player: PlayerController
var _root: Node3D
var _teacher: Node3D
var _me: Node3D
var _dust: MultiMeshInstance3D
var _dust_data: Array = []
var _flow := 0.0
var _seat_eye := Vector3.ZERO
var _seat_yaw := 0.0
var _board := Vector3.ZERO
var _dust3 := Vector3.ZERO
var _cams: Array = []
var _caption := ""
var _classroom: ClassmatesView
var _teacher_shadow := false
var _mates: Array = []          # {node, base_y, kind, amp, f, ph}


static func duration(is_short: bool) -> float:
	return DUR_SHORT if is_short else DUR_FULL


## The caption line at the storyboard time K (0..1 of the full version), "" between lines.
static func line_at(kk: float) -> String:
	for l: Array in LINES:
		if kk >= float(l[0]) and kk < float(l[1]):
			return String(l[2])
	return ""


static func ease_k(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


static func phase(kk: float, a: float, b: float) -> float:
	return ease_k((kk - a) / (b - a))


## Storyboard time of the version: short plays from SHORT_FROM to the end.
static func story_time(progress: float, is_short: bool) -> float:
	return SHORT_FROM + (1.0 - SHORT_FROM) * progress if is_short else progress


func _cell(gx: float, gy: float, y: float) -> Vector3:
	var w := Vector2(float(_room["ox"]) + gx * float(_room["tw"]), float(_room["oy"]) + gy * float(_room["th"]))
	var s := CampusGeometry.to_scene(_room, w)
	return Vector3(s.x, y, s.y)


func begin(world: Node3D, room: Dictionary, player: PlayerController, ui: GameUI, is_short: bool) -> void:
	_room = room
	_player = player
	_ui = ui
	_lighting = world.lighting if world is CampusWorld else null
	_normal_before = ui.scene_post().world_normal
	short = is_short
	ui.cut_mode(true)
	k = 0.0
	on = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Node3D.new()
	_root.name = "OpeningProps"
	world.add_child(_root)
	cam = Camera3D.new()
	cam.name = "OpeningCamera"
	cam.fov = player.camera.fov
	cam.near = player.camera.near
	cam.far = player.camera.far
	_root.add_child(cam)
	cam.current = true
	# The final view = where the player is looking at the start.
	_seat_eye = player.camera.global_position
	_seat_yaw = player.rotation.y
	_board = _cell(C0 + 0.05, MID, 1.45)
	_dust3 = _cell(C0 + 5.5, R0 + 0.7, 1.75)
	_cams = [[_cell(C0 + 10.0, AISLE_N, 1.62), _cell(C0 + 6.8, AISLE_N, 1.5)], [_cell(C0 + 1.75, R0 + 1.0, 1.55), _cell(C0 + 1.55, R0 + 1.45, 1.5)],
		[_cell(C0 + 6.1, AISLE_N - 0.05, 1.55), _cell(C0 + 5.3, AISLE_N + 0.05, 1.45)], [_cell(C0 + 4.6, AISLE_S + 0.25, 1.35), _cell(C0 + 4.05, AISLE_S + 0.1, 1.2)]]
	# The teacher beside the board (facing the class, east), and "you" in your own chair (facing the board, west).
	_teacher = FigureModel.make("teacher", Color("5d6873"))
	_teacher.position = _cell(C0 + 0.62, MID, 0.0)
	_teacher.position.y = 0.0
	_teacher.rotation.y = -PI / 2.0
	_root.add_child(_teacher)
	_me = Node3D.new()
	_me.position = _cell(C0 + 3.8, MID + 0.39, 0.0)
	_me.rotation.y = PI / 2.0
	_me.add_child(FigureModel.make("sit", Color(0.455, 0.502, 0.549)))
	_root.add_child(_me)
	_build_dust()
	# The classmates' small movements: some write (nodding forward again and again), some turn a page (a little turn), some stay.
	var crowd := world.get_node_or_null("Classmates")
	_classroom = crowd as ClassmatesView
	if _classroom != null and is_instance_valid(_classroom.teacher): _classroom.teacher.hide()
	if crowd != null:
		var mr := RandomNumberGenerator.new()
		mr.seed = 4141
		for n: Node in crowd.get_children():
			if n.get_meta("teacher",false): continue
			var node := n as Node3D
			if node == null:
				continue
			var r := mr.randf()
			var kind := "write" if r < 0.5 else ("turn" if r < 0.78 else "still")
			node.rotation_order = EULER_ORDER_YXZ
			_mates.append({"node": node, "base_y": node.rotation.y, "kind": kind, "amp": 0.0 if kind == "still" else (0.05 if kind == "write" else 0.06) + 0.05 * mr.randf(), "f": 0.35 + 0.55 * mr.randf(), "ph": mr.randf() * TAU})
	_ui.cut_fade(0.0)
	_apply(0.0)


func _build_dust() -> void:
	var n := 160
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.03)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.953, 0.863, 0.7)
	var grad := GradientTexture2D.new()
	grad.fill = GradientTexture2D.FILL_RADIAL
	grad.fill_from = Vector2(0.5, 0.5)
	grad.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	grad.gradient = g
	mat.albedo_texture = grad
	quad.material = mat
	mm.mesh = quad
	mm.instance_count = n
	var boxes := [[C0 + 0.9, C0 + 2.9, R0 + 0.35, R0 + 1.6, 1.05, 2.35], [C0 + 4.5, C0 + 6.5, R0 + 0.35, R0 + 1.6, 1.05, 2.35],
		[C0 + 8.1, C0 + 10.1, R0 + 0.35, R0 + 1.6, 1.05, 2.35], [C0 + 0.35, C0 + 1.0, MID - 1.6, MID + 1.6, 1.3, 2.2]]
	var rng := RandomNumberGenerator.new()
	rng.seed = 26
	for i in n:
		var m := i % 10
		var bx: Array = boxes[0 if m < 3 else (1 if m < 6 else (2 if m < 8 else 3))]
		var p := _cell(lerpf(float(bx[0]), float(bx[1]), rng.randf()), lerpf(float(bx[2]), float(bx[3]), rng.randf()), lerpf(float(bx[4]), float(bx[5]), rng.randf()))
		_dust_data.append({"p": p, "ph": rng.randf() * TAU, "sp": 0.25 + rng.randf() * 0.5})
	_dust = MultiMeshInstance3D.new()
	_dust.multimesh = mm
	_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(_dust)


func _look(from: Vector3, to: Vector3) -> void:
	cam.global_position = from
	if from.distance_to(to) > 0.01:
		cam.look_at(to, Vector3.UP)


## The mates at storyboard time K: still after 0.70 (they sit up straight again), frozen with the dust from 0.455.
static func mate_pose(kind: String, amp: float, f: float, ph: float, kk: float) -> Vector2:
	var t := minf(kk, 0.455) * DUR_FULL
	if kk >= 0.70 or amp == 0.0:
		return Vector2.ZERO
	var w := sin(t * f * TAU + ph)
	if kind == "write":
		return Vector2(amp * (0.55 + 0.45 * w), 0.0)          # (lean forward, turn)
	return Vector2(0.02, amp * w)


func _beats(kk: float) -> void:
	if audio == null or not is_instance_valid(audio):
		return
	if kk > 0.37 and not _sounded.has("hum"):
		_sounded["hum"] = true
		audio.play("world.crackle", {"k": 0.6, "pan": 0.5})
	if kk >= 0.72 and not _sounded.has("flip"):
		_sounded["flip"] = true
		audio.play("ui.blink")
	if kk > 0.78 and not _sounded.has("wake"):
		_sounded["wake"] = true
		audio.play("foley.wake")


func _apply(kk: float) -> void:
	var norm := 1.0-.45*phase(kk,.46,.58) if kk<.58 else .55*(1.0-phase(kk,.6,.7))
	_ui.set_normal_world(norm)
	if is_instance_valid(_lighting):
		_lighting.world_normal=norm
		_lighting.update(0,700.0,cam)
	_beats(kk)
	if is_instance_valid(_classroom): _classroom.set_normal(kk<.72)
	if _teacher_shadow != (kk>=.72):
		_teacher_shadow = kk>=.72
		for mesh: Node in _teacher.find_children("*","MeshInstance3D",true,false):
			var mat := (mesh as MeshInstance3D).material_override as StandardMaterial3D
			mat.albedo_color = Color("080b0d") if _teacher_shadow else Color("5d6873")
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if _teacher_shadow else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	for m: Dictionary in _mates:
		if is_instance_valid(m["node"]):
			var pz := mate_pose(String(m["kind"]), float(m["amp"]), float(m["f"]), float(m["ph"]), kk)
			(m["node"] as Node3D).rotation = Vector3(pz.x, float(m["base_y"]) + pz.y, 0.0)
	var line := line_at(kk)
	if line != _caption:
		_caption = line
		_ui.cut_caption(line)
	# Chalk dust drifts until 0.46, then hangs.
	var moving := 1.0 if kk < 0.46 else maxf(0.0, 1.0 - (kk - 0.46) / 0.02)
	_flow += moving * 0.016
	for i in _dust_data.size():
		var d: Dictionary = _dust_data[i]
		var p: Vector3 = d["p"]
		var sp := float(d["sp"])
		var ph := float(d["ph"])
		_dust.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, p + Vector3(sin(_flow * sp + ph) * 0.12, sin(_flow * sp * 0.7 + ph * 2.0) * 0.08 - _flow * 0.02 * sp, cos(_flow * sp * 0.8 + ph) * 0.1)))
	_dust.visible = kk < 0.74
	var th := _teacher.position
	th.y = 1.5
	if kk < 0.24:
		var t1 := ease_k(kk / 0.24)
		var a1: Vector3 = _cams[0][0]
		var b1: Vector3 = _cams[0][1]
		_look(a1.lerp(b1, t1), _board.lerp(th, t1))
		_ui.cut_fade(1.0 - kk / 0.03 if kk < 0.03 else 0.0)
	elif kk < 0.42:
		var t2 := ease_k((kk - 0.24) / 0.18)
		var nod := sin(kk * 90.0) * 0.05
		if kk > 0.34 and kk < 0.36:
			nod = 0.0
		_teacher.rotation.x = nod
		_teacher.rotation.y = -PI / 2.0 + (-0.16 if kk > 0.36 else 0.12) * (1.0 - t2 * 0.4)
		var a2: Vector3 = _cams[1][0]
		var b2: Vector3 = _cams[1][1]
		_look(a2.lerp(b2, t2), th)
	elif kk < 0.58:
		_teacher.rotation.x = 0.0
		_teacher.rotation.y = -PI / 2.0
		var t3 := ease_k((kk - 0.42) / 0.16)
		var a3: Vector3 = _cams[2][0]
		var b3: Vector3 = _cams[2][1]
		var m3 := _me.position
		m3.y = 1.0
		_look(a3.lerp(b3, t3), _dust3.lerp(m3, t3))
	elif kk < 0.76:
		var t4 := ease_k((kk - 0.58) / 0.18)
		var a4: Vector3 = _cams[3][0]
		var b4: Vector3 = _cams[3][1]
		_me.visible = kk < 0.735
		_me.rotation.x = -0.42 * phase(kk, 0.6, 0.68)
		var m4 := _me.position
		var fl := 0.04 * maxf(0.0, sin(kk * 160.0)) if kk < 0.7 else 0.0
		var from4 := a4.lerp(b4, t4)
		from4.y -= fl
		_look(from4, Vector3(m4.x - 0.15, 0.95, m4.z))
		_ui.cut_fade(phase(kk, 0.69, 0.73))
	else:
		_me.visible = false
		var t5 := ease_k((kk - 0.78) / 0.14)
		var fwd := Vector3(-sin(_seat_yaw), 0.0, -cos(_seat_yaw))
		var pos := _seat_eye + fwd * 0.28 * (1.0 - t5)
		pos.y = _seat_eye.y + lerpf(-0.19, 0.0, t5)
		var pitch := lerpf(-0.62, 0.0, t5)
		cam.global_position = pos
		cam.global_rotation = Vector3(pitch, _seat_yaw, 0.0)
		_ui.cut_fade(1.0 - (kk - 0.76) / 0.06 if kk < 0.82 else 0.0)


func _process(delta: float) -> void:
	tick(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not on:
		return
	if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
		end(true)
		get_viewport().set_input_as_handled()


## Real seconds (the game is paused; the app calls this from a process that always runs).
func tick(delta: float) -> void:
	if not on:
		return
	if not is_instance_valid(_root) or not _root.is_inside_tree() or not is_instance_valid(_dust) or not is_instance_valid(cam) or not cam.is_inside_tree():
		cancel()
		return
	k += delta / duration(short)
	if k >= 1.0:
		end(false)
		return
	_apply(story_time(k, short))
	if short and k < 0.04:
		_ui.cut_fade(1.0 - k / 0.04)


func end(skipped: bool) -> void:
	_finish(skipped, true)


func cancel() -> void:
	_finish(true, false)


func _finish(skipped: bool, notify: bool) -> void:
	if not on:
		return
	on = false
	if is_instance_valid(_ui):
		_ui.set_normal_world(_normal_before)
	if is_instance_valid(_lighting) and _lighting.is_inside_tree():
		_lighting.world_normal=_normal_before
		_lighting.update(0,700.0,_player.camera if is_instance_valid(_player) else null)
	if is_instance_valid(_ui):
		_ui.cut_mode(false)
		_ui.cut_fade(0.0)
		_ui.cut_caption("")
	for m: Dictionary in _mates:
		if is_instance_valid(m["node"]):
			(m["node"] as Node3D).rotation = Vector3(0.0, float(m["base_y"]), 0.0)
	_mates = []
	if is_instance_valid(_classroom):
		_classroom.set_normal(false)
		if is_instance_valid(_classroom.teacher): _classroom.teacher.show()
	_classroom = null
	if is_instance_valid(_player) and is_instance_valid(_player.camera):
		_player.camera.current = true
	if is_instance_valid(_root):
		_root.queue_free()
	if notify:
		finished.emit(skipped)
