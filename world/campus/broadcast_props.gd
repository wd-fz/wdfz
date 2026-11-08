class_name BroadcastProps
extends Node3D
## The broadcast station's props and signs (modules/broadcast/broadcast-view.js, reference wd-fz.github.io@0bf508a). Presentation only: the
## collision comes from the room recipe. In the broadcast room (admin2): the door signs ("广播站 钥匙：夜间保安岗"), the amplifier
## and the microphone on its stand, the note book, the sign over the desk (the fuse blown / mended); in the rooms that hold a source
## of a notice, the key to the archive and the spare fuse: a small tag. All text on dark plates, unlit.

const ROOM := "admin2"
const DOORS := [[5, 16], [7, 16]]
const STATION := [5, 3]
const TAGS := [{"room": "admin1", "at": [46, 2], "text": "教导处文件柜", "w": 0.85, "h": 0.26, "y": 1.8, "dz": 0.45},
	{"room": "lab5", "at": [5, 1], "text": "琴凳", "w": 0.85, "h": 0.26, "y": 1.8, "dz": 0.45},
	{"room": "guard1", "at": [2, 4], "text": "保安岗登记簿", "w": 0.85, "h": 0.26, "y": 1.8, "dz": 0.45},
	{"room": "teach6", "at": [20, 2], "text": "天台喇叭箱", "w": 0.85, "h": 0.26, "y": 1.8, "dz": 0.45},
	{"room": "admin5", "at": [6, 2], "text": "钥匙：教导处通知档案", "w": 1.1, "h": 0.24, "y": 1.25, "dz": 0.35},
	{"room": "gear1", "at": [3, 1], "text": "广播功放 · 备用保险丝", "w": 1.1, "h": 0.26, "y": 1.65, "dz": 0.4}]

var _room: Dictionary = {}
var _fuse := false
var _count := 0


static func tags_for(room_id: String) -> Array:
	var out: Array = []
	for t: Dictionary in TAGS:
		if String(t["room"]) == room_id:
			out.append(t)
	return out


func count() -> int:
	return _count


func _point(at: Array) -> Vector2:
	return CampusGeometry.to_scene(_room, Vector2(float(_room["ox"]) + (float(at[0]) + 0.5) * float(_room["tw"]), float(_room["oy"]) + (float(at[1]) + 0.5) * float(_room["th"])))


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _box(w: float, h: float, d: float, c: Color, x: float, y: float, z: float) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, d)
	mi.mesh = bm
	mi.material_override = _mat(c)
	mi.position = Vector3(x, y, z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_count += 1


## A dark plate with centred text, w × h metres.
func _label(text: String, w: float, h: float, pos: Vector3, color: Color = Color("#e4dfc7")) -> Node3D:
	var n := Node3D.new()
	var plate := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	plate.mesh = q
	plate.material_override = _mat(Color("#171f1e"))
	n.add_child(plate)
	var l := Label3D.new()
	l.text = text
	l.font_size = 48
	l.pixel_size = minf(h / 2.4 / 48.0, w / 11.0 / 48.0) * 1.0
	l.modulate = color
	l.shaded = false
	l.double_sided = true
	l.position = Vector3(0, 0, 0.002)
	n.add_child(l)
	n.position = pos
	add_child(n)
	_count += 1
	return n


func set_fuse(on: bool) -> void:
	if on != _fuse:
		_fuse = on
		build(_room)


func build(room: Dictionary) -> void:
	for c in get_children():
		c.queue_free()
	_count = 0
	_room = room
	if room.is_empty():
		return
	var rid := String(room.get("id", ""))
	if rid == ROOM:
		for at: Array in DOORS:
			var p := _point(at)
			_label("广播站\n钥匙：夜间保安岗", 1.1, 0.45, Vector3(p.x, 2.35, p.y + 0.54))
		var s := _point(STATION)
		_box(0.30, 0.20, 0.24, Color("#253731"), s.x + 0.3, 1.08, s.y - 0.1)
		_box(0.29, 0.035, 0.012, Color("#b75538"), s.x + 0.3, 1.12, s.y + 0.027)
		_box(0.1, 0.025, 0.1, Color("#161b1c"), s.x - 0.2, 0.98, s.y)
		var neck := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.013
		cm.bottom_radius = 0.013
		cm.height = 0.32
		cm.radial_segments = 8
		neck.mesh = cm
		neck.material_override = _mat(Color("#77847f"))
		neck.position = Vector3(s.x - 0.2, 1.15, s.y)
		add_child(neck)
		_count += 1
		_box(0.07, 0.16, 0.07, Color("#1b2928"), s.x - 0.2, 1.36, s.y)
		for i in 4:
			_box(0.073, 0.008, 0.008, Color("#8d9b95"), s.x - 0.2, 1.31 + float(i) * 0.025, s.y + 0.038)
		var book := _label("播音记录本\n第二天 · 第八节后", 0.43, 0.22, Vector3(s.x + 0.02, 0.98, s.y + 0.2))
		book.rotation.x = -PI / 2.0
		_label("功放已修复\n话筒：整理通知稿" if _fuse else "功放保险丝已烧\n备用件：体育器材室", 1.6, 0.45, Vector3(s.x, 1.85, s.y - 0.6))
	for t: Dictionary in tags_for(rid):
		var q := _point(t["at"])
		_label(String(t["text"]), float(t["w"]), float(t["h"]), Vector3(q.x, float(t["y"]), q.y + float(t["dz"])))
