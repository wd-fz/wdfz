class_name CampusMinimap
extends Button
## A clipped campus photo outdoors and a local window onto the explored floor indoors.

const FLOOR_BG := Color("111d26")
const FLOOR_OPEN := Color("435864")
const FLOOR_WALL := Color("71848c")
const FLOOR_DOOR := Color("a2b6bb")
const PHOTO_SPAN := 190.0

var _room: Dictionary = {}
var _seen: PackedByteArray
var _bounds := Rect2()
var _at := Vector2.ZERO
var _angle := 0.0
var _floor_turn := 0
var _target := Vector2.INF
var _caption := ""
var _frame: StyleBoxFlat


func _ready() -> void:
	name = "CampusMinimap"
	focus_mode = FOCUS_NONE
	accessibility_name = "打开地图"
	tooltip_text = "打开地图"
	mouse_default_cursor_shape = CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_frame = UISkin.panel(5)
	_frame.set_corner_radius_all(10)
	_frame.bg_color = Color(0.055, 0.09, 0.12, .93)
	_frame.border_color = Color("496474")
	resized.connect(queue_redraw)
	hide()


func show_air(at: Vector2, angle: float, target: Vector2) -> void:
	_room = {}
	_floor_turn = 0
	_bounds = MapView.aerial_bounds(CampusData.campus_map())
	_at = at
	_angle = angle
	_target = target
	_caption = "校园卫星图"
	show()
	queue_redraw()


func show_floor(room: Dictionary, seen: PackedByteArray, at: Vector2, angle: float, floor_turn: int) -> void:
	_room = room
	_floor_turn = floor_turn
	_seen = seen
	_at = at
	_angle = angle
	_caption = String(room["name"])
	show()
	queue_redraw()


func _draw() -> void:
	if _frame == null or size.x < 40.0 or size.y < 48.0: return
	draw_style_box(_frame, Rect2(Vector2.ZERO, size))
	var plot := Rect2(Vector2(5, 5), size - Vector2(10, 26))
	draw_rect(plot, FLOOR_BG)
	if _room.is_empty(): _draw_aerial(plot)
	else: _draw_floor(plot)
	draw_rect(plot, Color("425960"), false, 1.0)
	var centre := plot.get_center()
	draw_circle(centre, 9.0, Color(0.035, 0.065, 0.08, .93))
	draw_colored_polygon(MapView.pointer(centre, _angle, 8.0), MapView.PLAYER_PIN)
	var compass := plot.position + Vector2(12, 12)
	draw_circle(compass, 8.0, Color(0.035, 0.065, 0.08, .93))
	var north := -PI * .5 + _floor_turn * PI * .5
	draw_colored_polygon(MapView.pointer(compass, north, 6.0), UISkin.INK)
	draw_string(get_theme_default_font(), Vector2(8, size.y - 6), _caption, HORIZONTAL_ALIGNMENT_LEFT, size.x - 16, 12, UISkin.INK)


func _draw_aerial(plot: Rect2) -> void:
	var span := Vector2(PHOTO_SPAN * plot.size.x / plot.size.y, PHOTO_SPAN)
	var area := Rect2(_at - span * .5, span)
	var visible_part := area.intersection(_bounds)
	if not visible_part.has_area(): return
	var image_size := MapView.AERIAL.get_size()
	var texture_region := Rect2((visible_part.position - _bounds.position) / _bounds.size * image_size,
		visible_part.size / _bounds.size * image_size)
	var screen := Rect2(plot.position + (visible_part.position - area.position) / span * plot.size,
		visible_part.size / span * plot.size)
	draw_texture_rect_region(MapView.AERIAL, screen, texture_region, Color("a9c3be"))
	var pin := plot.position + (_target - area.position) / span * plot.size
	if _target.is_finite() and plot.grow(-5.0).has_point(pin):
		draw_circle(pin, 6.0, FLOOR_BG)
		draw_arc(pin, 4.0, 0.0, TAU, 16, MapView.TARGET_PIN, 2.0, true)


func _draw_floor(plot: Rect2) -> void:
	var cols := int(_room["cols"])
	var rows := int(_room["rows"])
	if _seen.size() != cols * rows: return
	var tile := (_at - Vector2(_room["ox"], _room["oy"])) / Vector2(_room["tw"], _room["th"])
	var cell := plot.size.y / 11.0
	var origin := plot.get_center() - tile * cell
	var start := ((plot.position - origin) / cell).floor().max(Vector2.ZERO)
	var end := ((plot.end - origin) / cell).ceil().min(Vector2(cols, rows))
	var grid: Array = _room["grid"]
	for r in range(int(start.y), int(end.y)):
		for c in range(int(start.x), int(end.x)):
			if _seen[r * cols + c] == 0: continue
			var ch := String(grid[r]).substr(c, 1)
			var tint := FLOOR_WALL if ch == "#" else FLOOR_DOOR if ch in ["=", "S", "J", "O"] else FLOOR_OPEN
			var shape := Rect2(origin + Vector2(c, r) * cell, Vector2.ONE * cell).intersection(plot)
			draw_rect(shape, tint)
