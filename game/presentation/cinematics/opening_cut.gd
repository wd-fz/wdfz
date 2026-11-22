class_name OpeningCut
extends Node
## The new-game opening, played live in the first classroom (opening.js and CUT_DEF.opening, reference
## wd-fz.github.io@0bf508a), then the camera is handed to the player exactly where the game starts (seat,
## facing, sitting posture like a normal start). Storyboard (full, about 26 s):
##   1 an ordinary fourth period: from the back row, slowly towards the podium, chalk dust in the light;
##   2 something is off: the teacher beside the podium reads half a line, stops, starts again;
##   3 time stops: the chalk dust hangs in the air; the camera turns from the dust to "you";
##   4 falling: you slump onto the desk, eyes close, black;
##   5 first person: the head comes up from the desk and turns toward the still deskmate;
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
const CAPTION_TIMES := [[0.03, 0.21], [0.24, 0.41], [0.42, 0.58], [0.59, 0.76], [0.78, 0.925], [0.93, 1.01]]

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
var _other_teacher: OtherworldFigure
var _teacher: StudentAvatar
var _me: StudentAvatar
var _deskmate: OtherworldFigure
var _dust: MultiMeshInstance3D
var _dust_data: Array = []
var _flow := 0.0
var _seat_eye := Vector3.ZERO
var _seat_yaw := 0.0
var _board := Vector3.ZERO
var _dust3 := Vector3.ZERO
var _cams: Array = []
var _caption := ""
var _lines: PackedStringArray
var _classroom: ClassmatesView
var _mates: Array = []          # {node, base_y, kind, amp, f, ph}


static func duration(is_short: bool) -> float:
	return DUR_SHORT if is_short else DUR_FULL


## The caption line at the storyboard time K (0..1 of the full version), "" between lines.
static func line_at(kk: float, lines: PackedStringArray) -> String:
	for i in CAPTION_TIMES.size():
		var interval: Array = CAPTION_TIMES[i]
		if kk >= float(interval[0]) and kk < float(interval[1]): return lines[i]
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


func begin(world: Node3D, room: Dictionary, player: PlayerController, ui: GameUI, is_short: bool, character: String = StudentCast.DEFAULT) -> void:
	_room = room
	_player = player
	_ui = ui
	_lighting = world.lighting if world is CampusWorld else null
	_normal_before = ui.scene_post().world_normal
	short = is_short
	_lines = OpeningStory.captions(character, is_short)
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
	_seat_eye = world.to_local(player.camera.global_position)
	_seat_yaw = player.rotation.y
	_board = _cell(C0 + 0.05, MID, 1.45)
	_dust3 = _cell(C0 + 5.5, R0 + 0.7, 1.75)
	_cams = [[_cell(C0 + 10.0, AISLE_N, 1.62), _cell(C0 + 6.8, AISLE_N, 1.5)], [_cell(C0 + 2.0, MID - 1.65, 1.57), _cell(C0 + 1.8, MID - 1.25, 1.51)],
		[_cell(C0 + 6.1, AISLE_N - 0.05, 1.55), _cell(C0 + 5.3, AISLE_N + 0.05, 1.45)], [_cell(C0 + 4.6, AISLE_S + 0.25, 1.35), _cell(C0 + 4.05, AISLE_S + 0.1, 1.2)]]
	# The teacher beside the board (facing the class, east), and "you" in your own chair (facing the board, west).
	_teacher = StudentAvatar.new()
	_teacher.name = "ClassTeacher"
	_root.add_child(_teacher)
	_teacher.dress_teacher()
	_teacher.position = _cell(C0 + 0.62, MID, 0.0)
	_teacher.rotation.y = -PI / 2.0
	_other_teacher = OtherworldFigure.make("teacher")
	_root.add_child(_other_teacher)
	_other_teacher.transform = _teacher.transform
	_other_teacher.hide()
	_me = StudentAvatar.new()
	_me.name = "SeatedProtagonist"
	_root.add_child(_me)
	_me.dress(character)
	_me.position = _cell(C0 + 3.8, MID + 0.39, 0.0)
	_me.rotation.y = PI / 2.0
	_me.advance("sit", 0.0)
	# The seat across the shared desktop is empty in the procedural classroom layout.
	_deskmate = OtherworldFigure.make("sit")
	_deskmate.name = "StillDeskmate"
	_root.add_child(_deskmate)
	_deskmate.position = _cell(C0 + 3.82, MID - 0.39, 0.0)
	_deskmate.rotation.y = PI / 2.0
	_build_dust()
	# The classmates' small movements: some write (nodding forward again and again), some turn a page (a little turn), some stay.
	_classroom = world.get_node_or_null("Classmates") as ClassmatesView
	if _classroom != null:
		if is_instance_valid(_classroom.teacher): _classroom.teacher.hide()
		var mr := RandomNumberGenerator.new()
		mr.seed = 4141
		for figure: Dictionary in _classroom.figures:
			if figure.teacher: continue
			var node: Node3D = figure.node
			var r := mr.randf()
			var kind := "write" if r < 0.5 else ("turn" if r < 0.78 else "still")
			node.rotation_order = EULER_ORDER_YXZ
			_mates.append({"node": node, "base_y": node.rotation.y, "kind": kind, "amp": 0.0 if kind == "still" else (0.05 if kind == "write" else 0.06) + 0.05 * mr.randf(), "f": 0.35 + 0.55 * mr.randf(), "ph": mr.randf() * TAU})
	_ui.cut_fade(0.0)
	_apply(story_time(0.0, short))


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
	cam.position = from
	if from.distance_to(to) > 0.01:
		cam.look_at(_root.to_global(to), Vector3.UP)


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
	var read_until := minf(kk, .455)
	var book := _teacher.animation
	if book != null and book.has_animation("read") and book.current_animation != "read": book.play("read")
	# The reading stops, repeats, then freezes along with the chalk.
	var read_time := read_until if read_until < .34 else maxf(0.0,read_until-.36)+.24
	if book != null and book.is_playing() and book.current_animation_length > 0:
		book.seek(fmod(read_time*DUR_FULL,book.current_animation_length),true)
	_teacher.visible = kk < .72
	_other_teacher.visible = kk >= .72
	_deskmate.visible = kk >= .76
	_other_teacher.face.rotation = Vector3(-.18, .7*phase(kk,.72,.79), -.11)
	_me.visible = kk < .735
	if _me.animation != null and _me.animation.is_playing() and _me.animation.current_animation_length > 0:
		_me.animation.seek(fmod(minf(kk,.455)*DUR_FULL,_me.animation.current_animation_length),true)
	var spine := _me.skeleton.find_bone("Spine") if _me.skeleton != null else -1
	if spine >= 0: _me.skeleton.set_bone_pose_rotation(spine,_me.skeleton.get_bone_pose_rotation(spine)*Quaternion(Vector3.RIGHT,-.55*phase(kk,.60,.68)))
	_ui.cut_fade(0.0)
	for m: Dictionary in _mates:
		if is_instance_valid(m["node"]):
			var pz := mate_pose(String(m["kind"]), float(m["amp"]), float(m["f"]), float(m["ph"]), kk)
			(m["node"] as Node3D).rotation = Vector3(pz.x, float(m["base_y"]) + pz.y, 0.0)
	var line := line_at(kk, _lines)
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
		var glance := phase(kk, 0.80, 0.85) * (1.0 - phase(kk, 0.90, 0.95))
		var toward := _deskmate.position + Vector3.UP * 1.13 - pos
		var yaw := lerp_angle(_seat_yaw, atan2(-toward.x, -toward.z), glance)
		pitch = lerpf(pitch, atan2(toward.y, Vector2(toward.x, toward.z).length()), glance)
		cam.position = pos
		cam.rotation = Vector3(pitch, yaw, 0.0)
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
