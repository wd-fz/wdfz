class_name WeatherFx
extends Node3D
## The rain and the moth swarm of the anomalies (fx/weather.js, reference wd-fz.github.io@0bf508a), replacing the particle stand-ins.
##  Rain: a set of line segments (900) falling slantwise with a wind that sways, in a 18 m square round the player; where they land
##  small rings spread; a few puddles slowly fill round you (ten seconds to full) with ripples in them always. (The lightning and the
##  thunder are the app's: AudioFx.thunder.)
##  Moths: each one a body and two flapping wings (instanced). They circle the point where the anomaly appeared; the longer you stay
##  (threat 0..1) the more the whole swarm is pulled onto you and the tighter the circle; one that gets within 0.55 m of your face bounces
##  off, so the picture is never wholly covered; the dust of the wings falls all the time.
## Presentation only. The random numbers are the old "presentation random" (a fixed seed here).

const RAIN_COUNTS := [500, 900, 1500, 2200, 3000]
const AREA := 18.0
const HEIGHT := 9.0
const MOTH_COUNTS := [50, 80, 120, 180, 220]
const DUST := 140

var kind := ""                       # "rain" | "moth"
var _rng := RandomNumberGenerator.new()
var _t := 0.0
# rain
var _mesh: ImmediateMesh
var _seeds: Array = []               # Vector3 per drop (offset from the camera, y = height)
var _rings: Array[MeshInstance3D] = []
var _ring_i := 0
var _puddles: Array[MeshInstance3D] = []
var _rip_t := 0.0
# moths
var _wings: MultiMeshInstance3D
var _bodies: MultiMeshInstance3D
var _moths: Array = []
var _dust: MultiMeshInstance3D
var _dust_p: Array = []
var _dust_life: Array = []
var _dust_i := 0
var _dust_count := DUST
var _moth_random := 909
var _center := Vector3.ZERO
var distance := 99.0                 # the swarm's mean distance from the camera, for the sound


static func wind(t: float) -> Vector2:
	return Vector2(1.8 + 1.3 * sin(t * 0.37), 0.7 + 0.5 * sin(t * 0.23 + 1.0))


## How wet the ground is after t seconds of rain.
static func wetness(t: float) -> float:
	return minf(1.0, t / 10.0)


## Threat uses accumulated exposure, which recedes when the player escapes the swarm.
static func threat(t: float, hard: bool) -> float:
	return clampf(t / (4.5 if hard else 6.5), 0.0, 1.0)


func _mat(c: Color, op: float = 1.0, double: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c.r, c.g, c.b, op)
	if op < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if double:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func setup_rain(feet: Vector3, quality: int = -1) -> void:
	kind = "rain"
	_rng.seed = 2024
	_mesh = ImmediateMesh.new()
	var lines := MeshInstance3D.new()
	lines.mesh = _mesh
	lines.material_override = _mat(Color("#aebfcc"), 0.36)
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lines.custom_aabb = AABB(Vector3(-40, -5, -40), Vector3(80, 30, 80))
	add_child(lines)
	for i in int(RAIN_COUNTS[CampusData.tier if quality < 0 else clampi(quality, 0, 4)]):
		_seeds.append(Vector3((_rng.randf() - 0.5) * AREA, _rng.randf() * HEIGHT, (_rng.randf() - 0.5) * AREA))
	var ring := TorusMesh.new()
	ring.inner_radius = 0.035
	ring.outer_radius = 0.06
	for i in 36:
		var mi := MeshInstance3D.new()
		mi.mesh = ring
		mi.material_override = _mat(Color("#c8d6de"), 0.0)
		mi.visible = false
		mi.set_meta("life", 0.0)
		mi.set_meta("big", 1.0)
		add_child(mi)
		_rings.append(mi)
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.004
	disc.radial_segments = 20
	disc.rings = 1
	for i in 9:
		var a := _rng.randf() * TAU
		var r := 1.2 + _rng.randf() * 6.0
		var pm := MeshInstance3D.new()
		pm.mesh = disc
		pm.material_override = _mat(Color("#1a242c"), 0.0)
		pm.scale = Vector3(0.5 + _rng.randf() * 1.1, 1.0, 0.35 + _rng.randf() * 0.7)
		pm.rotation.y = _rng.randf() * PI
		pm.position = Vector3(feet.x + cos(a) * r, feet.y + 0.012 + float(i) * 0.0005, feet.z + sin(a) * r)
		add_child(pm)
		_puddles.append(pm)


func _splash(x: float, y: float, z: float, big: bool) -> void:
	var m := _rings[_ring_i]
	_ring_i = (_ring_i + 1) % _rings.size()
	m.visible = true
	m.position = Vector3(x, y + 0.03, z)
	m.set_meta("life", 1.0)
	m.set_meta("big", 1.8 if big else 1.0)


## cam: the camera's position; floor_y the ground level.
func update_rain(dt: float, cam: Vector3, floor_y: float) -> void:
	_t += dt
	var w := wind(_t)
	var sp := 13.0
	var length := 0.55
	var lx := w.x / sp * length
	var lz := w.y / sp * length
	var half := AREA / 2.0
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in _seeds.size():
		var s: Vector3 = _seeds[i]
		s.y -= sp * dt
		s.x += w.x * dt
		s.z += w.y * dt
		if s.y < 0.0:
			if _rng.randf() < 0.12:
				_splash(cam.x + s.x, floor_y, cam.z + s.z, false)
			s.y += HEIGHT
			s.x = (_rng.randf() - 0.5) * AREA
			s.z = (_rng.randf() - 0.5) * AREA
		if s.x > half:
			s.x -= AREA
		elif s.x < -half:
			s.x += AREA
		if s.z > half:
			s.z -= AREA
		elif s.z < -half:
			s.z += AREA
		_seeds[i] = s
		var p := Vector3(cam.x + s.x, floor_y + s.y, cam.z + s.z)
		_mesh.surface_add_vertex(p)
		_mesh.surface_add_vertex(p + Vector3(-lx, length, -lz))
	_mesh.surface_end()
	for m in _rings:
		if not m.visible:
			continue
		var life := float(m.get_meta("life")) - dt * 2.8
		m.set_meta("life", life)
		if life <= 0.0:
			m.visible = false
			continue
		var sc := (1.6 - life) * float(m.get_meta("big"))
		m.scale = Vector3(sc, 1.0, sc)
		(m.material_override as StandardMaterial3D).albedo_color.a = 0.55 * life
	var wet := wetness(_t)
	_rip_t -= dt
	for p in _puddles:
		(p.material_override as StandardMaterial3D).albedo_color.a = 0.5 * wet
	if _rip_t <= 0.0 and not _puddles.is_empty():
		_rip_t = 0.05 + _rng.randf() * 0.08
		var pp: MeshInstance3D = _puddles[_rng.randi() % _puddles.size()]
		var ra := _rng.randf() * TAU
		var rr := _rng.randf() * 0.7
		_splash(pp.position.x + cos(ra) * rr * pp.scale.x, pp.position.y, pp.position.z + sin(ra) * rr * pp.scale.z, true)


func setup_moths(source: Vector3, quality: int = -1) -> void:
	kind = "moth"
	_moth_random = 909
	var wing := MothShape.wing()
	var body := BoxMesh.new()
	body.size = Vector3(0.016, 0.016, 0.06)
	var tier := CampusData.tier if quality<0 else clampi(quality,0,4)
	var count := int(MOTH_COUNTS[tier])
	_dust_count = 60 if tier==0 else DUST
	_wings = _multi(wing, _mat(Color("#111111"), 1.0, true), count * 2)
	_bodies = _multi(body, _mat(Color("#080808")), count)
	_center = Vector3(source.x, 1.9, source.z)
	for i in count:
		_moths.append({"p": Vector3(source.x + (_moth_rand() - 0.5) * 2.4, 1.2 + _moth_rand() * 1.6, source.z + (_moth_rand() - 0.5) * 2.4), "v": Vector3.ZERO, "a": _moth_rand() * TAU,
			"r": 0.35 + _moth_rand() * 1.5, "sp": (-1.0 if _moth_rand() < 0.5 else 1.0) * (1.0 + _moth_rand() * 2.2), "ph": _moth_rand() * TAU, "fl": 26.0 + _moth_rand() * 16.0, "h": 1.3 + _moth_rand() * 1.4})
	var dm := BoxMesh.new()
	dm.size = Vector3(0.012, 0.012, 0.012)
	_dust = _multi(dm, _mat(Color("#303030"), 0.65), _dust_count)
	for i in _dust_count:
		_dust_p.append(Vector3(0, -9, 0))
		_dust_life.append(0.0)


func _moth_rand() -> float:
	_moth_random = (_moth_random*1664525+1013904223)&0xffffffff
	return _moth_random/4294967296.0


func _multi(m: Mesh, mat: Material, n: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = m
	mm.instance_count = n
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-100, -10, -100), Vector3(200, 40, 200))
	add_child(mi)
	return mi


## t: seconds the anomaly has run; hard: the nightmare difficulty; cam the camera position.
func update_moths(dt: float, cam: Vector3, t: float, hard: bool) -> void:
	_t += dt
	var thr := threat(t, hard)
	var pull := (0.2 + 0.35 * thr) if thr > 0.0 else 0.0
	var c := Vector3(_center.x + (cam.x - _center.x) * pull, _center.y + (cam.y - 0.1 - _center.y) * pull, _center.z + (cam.z - _center.z) * pull)
	var shrink := 1.0 - 0.6 * thr
	var sum := 0.0
	var i := 0
	for m: Dictionary in _moths:
		m["a"] = float(m["a"]) + float(m["sp"]) * dt
		var a := float(m["a"])
		var tg := Vector3(c.x + cos(a) * float(m["r"]) * shrink, c.y + (float(m["h"]) - 1.9) * shrink * 0.6 + sin(a * 1.7 + float(m["ph"])) * 0.3, c.z + sin(a) * float(m["r"]) * shrink)
		var p: Vector3 = m["p"]
		var v: Vector3 = m["v"]
		v.x += ((tg.x - p.x) * 5.0 - v.x * 1.9 + (_moth_rand() - 0.5) * 9.0) * dt
		v.y += ((tg.y - p.y) * 5.0 - v.y * 1.9 + (_moth_rand() - 0.5) * 9.0) * dt
		v.z += ((tg.z - p.z) * 5.0 - v.z * 1.9 + (_moth_rand() - 0.5) * 9.0) * dt
		var vl := v.length()
		if vl > 4.5:
			v *= 4.5 / vl
		p += v * dt
		var cd := p.distance_to(cam)
		var rmin := 0.55 - 0.2 * thr
		if cd < rmin:
			p = cam + (p - cam) * (rmin / maxf(cd, 0.0001))
			v *= -0.4
		m["p"] = p
		m["v"] = v
		var head := atan2(v.x, v.z)
		var flap := sin(_t * float(m["fl"]) + float(m["ph"])) * 1.1 + 0.25
		_bodies.multimesh.set_instance_transform(i,MothShape.pose(p,head,0,Vector3.ONE))
		_wings.multimesh.set_instance_transform(i*2,MothShape.pose(p,head,flap,Vector3.ONE))
		_wings.multimesh.set_instance_transform(i*2+1,MothShape.pose(p,head,-flap,Vector3(-1,1,1)))
		sum += p.distance_to(cam)
		i += 1
	distance = sum / float(_moths.size())
	var emit := int(floor(dt * 60.0 * (1.0 + thr))) + 1
	for _k in emit:
		var src: Dictionary = _moths[floori(_moth_rand()*_moths.size())]
		_dust_p[_dust_i] = src["p"]
		_dust_life[_dust_i] = 2.5 + _moth_rand() * 1.5
		_dust_i = (_dust_i + 1) % _dust_count
	for j in _dust_count:
		var life := float(_dust_life[j])
		if life > 0.0:
			life -= dt
			var dp: Vector3 = _dust_p[j]
			dp.y -= dt * (0.18 + 0.1 * sin(float(j)))
			dp.x += sin(_t * 1.3 + float(j)) * dt * 0.08
			if life <= 0.0 or dp.y < 0.01:
				dp.y = -9.0
			_dust_p[j] = dp
			_dust_life[j] = life
		_dust.multimesh.set_instance_transform(j, Transform3D(Basis.IDENTITY, _dust_p[j]))
