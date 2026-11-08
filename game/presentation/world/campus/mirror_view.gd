class_name MirrorView
extends Node3D
## The late mirror, seen (modules/campus-tales/mirror.js, reference wd-fz.github.io@0bf508a). Over every basin in the teaching building
## that stands against a wall hangs a mirror; in it, close up, a flat low silhouette of you — not a reflection, a figure laid on the
## glass that replays your recent position. By SAN: tier 0 (≥ 70) in step; tier 1 (40–70) half a second behind; tier 2 (20–40) you
## turn away and it still faces you; tier 3 (< 20) it moves first — it raises an arm. (The rule is in TalesModule; this is its
## picture, the only feedback the player gets: the HUD never shows SAN.)

const NEAR := 2.6
const LAG := 0.5
const BUFFER_SECONDS := 1.2

var _mirrors: Array = []            # {"g": Node3D, "fig": Node3D, "arm": Node3D, "w": Vector2, "n": Vector2}
var _buf: Array = []                # [t, lateral, facing]
var _t := 0.0


## 0 in step, 1 a beat behind, 2 turned away and still facing you, 3 it moves first.
static func tier_of(san: float) -> int:
	return TalesModule.tier_of(san)


static func lateral(me: Vector2, w: Vector2, n: Vector2) -> float:
	return ((me.x - w.x) * -n.y + (me.y - w.y) * n.x) * CampusGeometry.U2M


## 1 = squarely facing the mirror.
static func facing(ang: float, n: Vector2) -> float:
	return -(cos(ang) * n.x + sin(ang) * n.y)


## The sample from `lag` seconds ago.
static func lagged(buf: Array, t: float, lag: float) -> Array:
	var p: Array = buf[0]
	for i in range(buf.size() - 1, -1, -1):
		if float(buf[i][0]) <= t - lag:
			p = buf[i]
			break
	return p


func _mat(c: Color, emit: Color = Color.BLACK) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if emit != Color.BLACK:
		m.emission_enabled = true
		m.emission = emit
	return m


func count() -> int:
	return _mirrors.size()


func build(room: Dictionary, spots: Array) -> void:
	for c in get_children():
		c.queue_free()
	_mirrors = []
	_buf = []
	if room.is_empty():
		return
	for sp: Dictionary in spots:
		var n: Vector2 = sp["n"]
		var pos: Vector2 = (sp["w"] as Vector2) - n * 0.47 * float(room["tw"])
		var s := CampusGeometry.to_scene(room, pos)
		var g := Node3D.new()
		g.position = Vector3(s.x, 1.5, s.y)
		g.rotation.y = atan2(n.x, n.y)
		var frame := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(0.68, 0.88, 0.02)
		frame.mesh = fm
		frame.material_override = _mat(Color("#3a3f42"))
		frame.position.z = -0.012
		g.add_child(frame)
		var glass := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.62, 0.82)
		glass.mesh = qm
		glass.material_override = _mat(Color("#8d999b"), Color("#1b2224"))
		g.add_child(glass)
		var fig := Node3D.new()
		var body := FigureModel.make("person", Color("#1d2326"), true)
		body.rotation.y = PI          # the old figure fronts +z
		body.scale.z = 0.04
		fig.add_child(body)
		var arm := Node3D.new()
		var am := MeshInstance3D.new()
		var abm := BoxMesh.new()
		abm.size = Vector3(0.09, 0.62, 0.04)
		am.mesh = abm
		am.material_override = _mat(Color("#1d2326"))
		am.position.y = -0.31          # pivot at the shoulder
		arm.add_child(am)
		arm.position = Vector3(0.27, 1.61, 0.0)
		arm.visible = false
		fig.add_child(arm)
		fig.scale = Vector3.ONE * 0.42
		fig.position = Vector3(0.0, -0.62, 0.012)
		g.add_child(fig)
		add_child(g)
		_mirrors.append({"g": g, "fig": fig, "arm": arm, "w": sp["w"], "n": n})


## me: the player in old world units; ang the facing; raise 0..1 from TalesModule.
func update(delta: float, me: Vector2, ang: float, san: float, raise: float, active: bool) -> void:
	if _mirrors.is_empty():
		return
	_t += delta
	var best: Dictionary = {}
	var bd := INF
	for m: Dictionary in _mirrors:
		var d := me.distance_to(m["w"]) * CampusGeometry.U2M
		(m["fig"] as Node3D).visible = active and d < NEAR * 1.6
		if d < bd:
			bd = d
			best = m
	if best.is_empty() or not active or bd >= NEAR * 1.6:
		return
	var t := tier_of(san)
	_buf.append([_t, lateral(me, best["w"], best["n"]), facing(ang, best["n"])])
	while _buf.size() > 2 and float(_buf[1][0]) < _t - BUFFER_SECONDS:
		_buf.pop_front()
	var p := lagged(_buf, _t, LAG if t >= 1 else 0.0)
	var fig := best["fig"] as Node3D
	fig.position.x = -clampf(float(p[1]), -0.6, 0.6) * 0.42
	fig.rotation.y = 0.0 if (t >= 2 or float(p[2]) > 0.0) else PI
	var arm := best["arm"] as Node3D
	arm.visible = raise > 0.02
	arm.rotation.z = -2.6 * raise
