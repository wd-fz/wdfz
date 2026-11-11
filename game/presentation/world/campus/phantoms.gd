class_name Phantoms
extends Node3D
## The things that are seen but are not threats (fx/traces.js, fx/smile.js; reference wd-fz.github.io@0bf508a):
##  · the hallucination (hallucTick): with SAN below 32, at the edge of the view 8–14 m away a black figure stands; as soon as
##    you turn to it (within 0.22 rad) or after 2.5–5 s it is gone; next in 10–26 s × (0.5 + SAN/64);
##  · the distant apparition (apparTick): every minute or two, in the dark, a black figure stands at the far end of the
##    corridor or road in front of you, quite still, facing you; it is gone when you come within 6.5 m, when the torch
##    shines on it, when you stare at it for 1.3 s, or after 3–6 s. It costs no SAN and is not an anomaly;
##  · the smile (smileShow): the other kind of shoulder tap — "behind": you turned, a smiling face 1.7 m away nods once and fades
##    (2 s); "jump": you did not turn, it is in your face (1.3 s, 1 m, fills the view within 0.18 s).
## Presentation only: the rules (what an anomaly is, SAN) are not touched. The old build's random numbers here are
## "presentation random" — they never decide a rule.

var _hallu: Node3D
var _hallu_life := 0.0
var _hallu_next := 12.0
var _appar: Node3D
var _appar_life := 0.0
var _appar_next := 40.0
var _appar_stare := 0.0
var _smile: Node3D
var _smile_face: Node3D
var _smile_head: Node3D
var reduce_flash := false  ## the reduce-flash setting: the turn-back face is then shown steadily, never blinking
var _smile_t := 0.0
var _smile_dur := 0.0
var _smile_mode := ""
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	name = "Phantoms"
	_rng.seed = 777


func _figure(kind: String) -> Node3D:
	var f := FigureModel.make(kind, Color(0.012, 0.016, 0.02), true, 1.05 if kind == "tall" else 1.0)
	f.visible = false
	add_child(f)
	return f


func hallu_visible() -> bool:
	return _hallu != null and is_instance_valid(_hallu) and _hallu.visible


func appar_visible() -> bool:
	return _appar != null and is_instance_valid(_appar) and _appar.visible


func smile_mode() -> String:
	return _smile_mode


## stand: Callable(world Vector2) -> bool, whether a point can be stood on. cam is the eye in scene metres;
## ang the facing in old world angle; room the room dict or null outdoors; h the floor height.
func hallucinate(delta: float, on: bool, san: float, cam: Vector3, ang: float, room: Variant, h: float, stand: Callable) -> void:
	if _hallu == null or not is_instance_valid(_hallu):
		_hallu = _figure("tall")
	if not on or san >= 32.0:
		_hallu.visible = false
		return
	if _hallu.visible:
		_hallu_life -= delta
		var a_to := atan2(_hallu.position.z - cam.z, _hallu.position.x - cam.x)
		if CampusGeometry.ang_diff(a_to, ang) < 0.22 or _hallu_life <= 0.0:
			_hallu.visible = false
			_hallu_next = _rng.randf_range(10.0, 26.0) * (0.5 + san / 64.0)
		return
	_hallu_next -= delta
	if _hallu_next > 0.0:
		return
	var side := -1.0 if _rng.randf() < 0.5 else 1.0
	for _k in 6:
		var a := ang + side * _rng.randf_range(0.85, 1.15)
		var dist := _rng.randf_range(70.0, 125.0)
		var me := CampusGeometry.to_world(room, cam.x, cam.z)
		var w := me + Vector2(cos(a), sin(a)) * dist
		if not stand.call(w):
			continue
		var s := CampusGeometry.to_scene(room, w)
		_hallu.position = Vector3(s.x, h, s.y)
		_hallu.rotation.y = atan2(_hallu.position.x - cam.x, _hallu.position.z - cam.z)
		_hallu.visible = true
		_hallu_life = _rng.randf_range(2.5, 5.0)
		break
	_hallu_next = 4.0


## on: playing, nothing else going on. dark: indoors or night. torch: the torch is lit. line_clear(a, b) -> bool in old units.
func apparition(delta: float, on: bool, dark: bool, torch: bool, san: float, cam: Vector3, ang: float, room: Variant, h: float, stand: Callable, line_clear: Callable) -> void:
	if _appar == null or not is_instance_valid(_appar):
		_appar = _figure("person")
	if not on:
		_appar.visible = false
		return
	if _appar.visible:
		_appar_life -= delta
		var dx := _appar.position.x - cam.x
		var dz := _appar.position.z - cam.z
		var dist := sqrt(dx * dx + dz * dz)
		var look := CampusGeometry.ang_diff(atan2(dz, dx), ang)
		if look < 0.10:
			_appar_stare += delta
		else:
			_appar_stare = maxf(0.0, _appar_stare - delta * 0.5)
		var lit := torch and look < 0.16
		if dist < 6.5 or lit or _appar_stare > 1.3 or _appar_life <= 0.0:
			_appar.visible = false
			_appar_next = _rng.randf_range(50.0, 120.0) * (0.6 + 0.4 * clampf(san, 0.0, 100.0) / 100.0)
		return
	_appar_next -= delta
	if _appar_next > 0.0:
		return
	_appar_next = 6.0
	if not dark:
		return
	var me := CampusGeometry.to_world(room, cam.x, cam.z)
	for _k in 10:
		var a := ang + (_rng.randf() - 0.5) * 0.5
		var d := 145.0
		while d >= 90.0:
			var dir := Vector2(cos(a), sin(a))
			if line_clear.call(me, me + dir * d):
				var w := me + dir * d
				if stand.call(w) and stand.call(w + Vector2(4, 0)) and stand.call(w - Vector2(4, 0)) and stand.call(w + Vector2(0, 4)) and stand.call(w - Vector2(0, 4)):
					var s := CampusGeometry.to_scene(room, w)
					_appar.position = Vector3(s.x, h, s.y)
					_appar.rotation.y = atan2(_appar.position.x - cam.x, _appar.position.z - cam.z)
					_appar.visible = true
					_appar_life = _rng.randf_range(3.0, 6.0)
					_appar_stare = 0.0
					return
			d -= 11.0


func show_smile(mode: String, cam: Vector3, ang: float) -> void:
	clear_smile()
	var dist := 1.0 if mode == "jump" else 1.7
	_smile = Node3D.new()
	_smile.name = "Smile"
	add_child(_smile)
	_smile_face = Node3D.new()
	# A schoolmate in uniform with the wrong face: a real head, the mouth too wide, the sockets too deep, lit from under the chin.
	var jump := mode == "jump"
	var uniform := Color("2a3445")
	# Hollow sockets and a shut, too-wide mouth: no hair, no collar, dark clothes. Brighter or busier reads as a mask.
	var bust := HorrorKit.bust({"mouth": "wide", "open": 0.0, "skew": .2, "eyes": "hollow", "tone": Color(.2, .19, .18), "glow": .0, "body": .7, "cloth": Color("14161a")})
	bust.rotation.y = PI
	bust.position = Vector3(0, 1.68, .58) if jump else Vector3(0, 1.66, 0)
	bust.scale = Vector3.ONE * (1.8 if jump else 1.0)
	HorrorKit.dress(bust.get_meta("horror_bust")["torso"], HorrorKit._cloth(Color("14161a")))
	(bust.get_meta("horror_bust")["torso"] as Node3D).scale.x = 1.2  # broader shoulders: a person in a blazer, not a bell
	_smile_head = bust.get_meta("horror_bust")["head"]
	_smile_head.rotation.z = .22 if jump else .12
	# A soft fill from in front and below, well away from the face, so the torch does not bleach it.
	var under := OmniLight3D.new()
	under.name = "UnderLight"
	under.light_color = Color("d8d0c0")
	under.light_energy = .22 if jump else .15
	under.omni_range = 1.8
	under.shadow_enabled = false
	under.position = Vector3(0, -.45, -.65)
	bust.add_child(under)
	_smile_face.add_child(bust)
	_smile.add_child(_smile_face)
	_smile.position = Vector3(cam.x + cos(ang) * dist, cam.y - 1.72, cam.z + sin(ang) * dist)
	# The face's front is +z (the old build); turn it to the camera.
	_smile.rotation.y = atan2(cam.x - _smile.position.x, cam.z - _smile.position.z)
	_smile_t = 0.0
	_smile_mode = mode
	_smile_dur = 1.3 if mode == "jump" else 2.0


func clear_smile() -> void:
	if _smile != null and is_instance_valid(_smile):
		_smile.queue_free()
	_smile = null
	_smile_head = null
	_smile_mode = ""


func tick_smile(delta: float, cam: Vector3) -> void:
	if _smile == null or not is_instance_valid(_smile):
		return
	_smile_t += delta
	var k := _smile_t / _smile_dur
	if _smile_mode == "jump":
		var s := minf(1.0, _smile_t / 0.18)
		_smile.scale = Vector3.ONE * (0.3 + 0.62 * s)
		_smile.position.y = cam.y - 1.72 * _smile.scale.y + (_rng.randf() - 0.5) * 0.03
		if _smile_head != null:
			HorrorKit.pose_head(_smile_head, clampf((_smile_t - .35) / 0.6, 0.0, 1.0) * .1)
			_smile_head.rotation.z = .22 + .08 * minf(1.0, _smile_t / 0.6)
	else:
		_smile.scale = Vector3.ONE
		_smile_face.rotation.x = sin(minf(1.0, _smile_t / 0.9) * PI) * 0.12
		if _smile_head != null:
			HorrorKit.pose_head(_smile_head, .05 * minf(1.0, _smile_t / 1.2))
		# It stutters out in two short gaps before it is gone; with reduce-flash it simply stays, then vanishes.
		if reduce_flash:
			_smile_face.visible = k < 0.86
		else:
			_smile_face.visible = not ((k >= .62 and k < .66) or (k >= .74 and k < .78) or k >= .86)
	if k >= 1.0:
		clear_smile()
