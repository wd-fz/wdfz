class_name DayBanner
extends Node3D
## The anniversary banner (fx/day-decor.js, reference wd-fz.github.io@0bf508a): on the front of the teaching
## building, on the second floor, red with yellow letters. Only on the anniversary and only outdoors; a
## separate group, no collision. Hung between the floor edges that jut out about 0.75 m above and below,
## so looking up never hits the slab.

const TEXT := "热烈庆祝武大附中建校纪念日"
const SIZE := Vector2i(1024, 96)
const SC := 2.0

static var _tex: Texture2D

var _banner: MeshInstance3D
var _ropes: Array[MeshInstance3D] = []
var _busy := false


## The banner's centre and the building's front line in scene coordinates, from the outdoor plan.
static func spot(layout: Dictionary) -> Vector3:
	for o: Dictionary in layout.get("objects", []):
		if String(o["id"]) == "teach":
			var cx := (float(o["x"]) + float(o["w"]) / 2.0) * SC * CampusGeometry.U2M
			var fz := (float(o["y"]) + float(o["h"])) * SC * CampusGeometry.U2M
			return Vector3(cx, 5.55, fz + 0.82)
	return Vector3.ZERO


func setup(layout: Dictionary) -> void:
	var at := spot(layout)
	if at == Vector3.ZERO:
		return
	_banner = MeshInstance3D.new()
	_banner.name = "Banner"
	var q := QuadMesh.new()
	q.size = Vector2(13.0, 1.1)
	_banner.mesh = q
	_banner.position = at
	_banner.visible = false
	add_child(_banner)
	var rope := StandardMaterial3D.new()
	rope.albedo_color = Color("#6a5a48")
	for dx: float in [-6.6, 6.6]:
		var r := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.04, 2.6, 0.04)
		r.mesh = bm
		r.material_override = rope
		r.position = at + Vector3(dx, 0.0, -0.02)
		r.visible = false
		add_child(r)
		_ropes.append(r)


func set_on(on: bool) -> void:
	if _banner == null:
		return
	_banner.visible = on
	for r in _ropes:
		r.visible = on
	if on and _banner.material_override == null and not _busy:
		_busy = true
		var tex := await texture()
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 1.0
		_banner.material_override = mat
		_busy = false


func is_on() -> bool:
	return _banner != null and _banner.visible


func texture() -> Texture2D:
	if _tex != null:
		return _tex
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var sheet := Sheet.new()
	sheet.size = Vector2(SIZE)
	vp.add_child(sheet)
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	_tex = ImageTexture.create_from_image(img)
	return _tex


class Sheet extends Control:
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1024, 96), Color("#b3121b"))
		draw_rect(Rect2(0, 0, 1024, 6), Color("#8a0d14"))
		draw_rect(Rect2(0, 90, 1024, 6), Color("#8a0d14"))
		var font := get_theme_default_font()
		draw_string(font, Vector2(0, 68), DayBanner.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 1024.0, 58, Color("#f6d36b"))
