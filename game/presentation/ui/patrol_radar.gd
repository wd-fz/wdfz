class_name PatrolRadar
extends Control
## The top of the radar is the direction the player faces.

const RADIUS := 44.0
const GRID := Color(0.78, 0.85, 0.85, 0.43)
const CONTACT := Color("#ff7966")
var _offset := Vector3.ZERO


func track(offset: Vector3) -> void:
	if _offset == offset: return
	_offset = offset
	queue_redraw()


func _draw() -> void:
	var centre := Vector2(size.x * 0.5, RADIUS + 4.0)
	var contact := centre + Vector2(_offset.x, _offset.z) * ((RADIUS - 5.0) / TalentModule.PATROL_SENSE_METRES)
	draw_circle(centre, RADIUS, Color(0.035, 0.055, 0.06, 0.82), true, -1.0, true)
	draw_circle(centre, RADIUS, GRID, false, 1.5, true)
	draw_circle(centre, RADIUS * 0.5, GRID, false, 1.0, true)
	draw_line(centre - Vector2(RADIUS, 0), centre + Vector2(RADIUS, 0), GRID, 1.0, true)
	draw_line(centre - Vector2(0, RADIUS), centre + Vector2(0, RADIUS), GRID, 1.0, true)
	draw_colored_polygon(PackedVector2Array([centre + Vector2(0, -5), centre + Vector2(-4, 4), centre + Vector2(4, 4)]), Color.WHITE)
	draw_circle(contact, 5.0, CONTACT, true, -1.0, true)
	var font := get_theme_default_font()
	var elevation := " ↑" if _offset.y > 1.3 else (" ↓" if _offset.y < -1.3 else "")
	var distance := "%.1f m%s" % [_offset.length(), elevation]
	draw_string(font, Vector2(0, 112), distance, HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, CONTACT)
