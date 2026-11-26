class_name DayBanner
extends Node3D
## The anniversary banner (fx/day-decor.js, reference wd-fz.github.io@0bf508a): on the front of the teaching
## building, on the second floor, red with yellow letters. Only on the anniversary and only outdoors; a
## separate group, no collision. Hung between the floor edges that jut out about 0.75 m above and below,
## so looking up never hits the slab.

const TEXT := "热烈庆祝武大附中建校纪念日"
const SIZE := Vector2i(1024, 96)
const HANG_POSITION := Vector3(0.0, 5.55, 0.82)

static var _tex: Texture2D

var _banner: MeshInstance3D
var _ropes: Array[MeshInstance3D] = []
var _busy := false


## Centre of the teaching building's entrance facade. Local +Z points out onto the plaza.
static func facade(layout: Dictionary) -> Transform3D:
	for building: Dictionary in layout.get("objects", []):
		if building.id != "teach": continue
		var outward: Vector2 = CampusGeometry.NORMALS[building.door]
		var size := Vector2(building.w, building.h)
		var edge := Vector2(building.x, building.y) + (Vector2.ONE + outward) * size * 0.5
		edge *= float(layout.SC) * CampusGeometry.U2M
		return Transform3D(Basis(Vector3.UP, atan2(outward.x, outward.y)), Vector3(edge.x, 0, edge.y))
	return Transform3D.IDENTITY


func setup(layout: Dictionary) -> void:
	transform = facade(layout)
	if transform == Transform3D.IDENTITY: return
	_banner = MeshInstance3D.new()
	_banner.name = "Banner"
	var q := QuadMesh.new()
	q.size = Vector2(13.0, 1.1)
	_banner.mesh = q
	_banner.position = HANG_POSITION
	_banner.visible = false
	add_child(_banner)
	var rope := StandardMaterial3D.new()
	rope.albedo_color = Color("#6a5a48")
	for dx: float in [-6.6, 6.6]:
		var r := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.04, 2.6, 0.04)
		r.mesh = bm
		RenderMaterials.set_override(r, rope)
		r.position = HANG_POSITION + Vector3(dx, 0.0, -0.02)
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
		RenderMaterials.set_override(_banner, mat)
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
