class_name UISkin
extends RefCounted
## Shared visual vocabulary for every menu, document and tool window.
const THEME: Theme = preload("res://content/ui/theme.tres")
const INK := Color("e9f0f4")
const MUTED := Color("a1b1bf")
const ACCENT := Color("8ce0cc")

static func panel(margin: int = 16) -> StyleBoxFlat:
	var style := THEME.get_stylebox("panel","PanelContainer").duplicate() as StyleBoxFlat
	style.set_content_margin_all(margin)
	return style

static func card(parent: Control) -> VBoxContainer:
	var panel_box := PanelContainer.new()
	panel_box.mouse_filter = Control.MOUSE_FILTER_PASS
	var style := panel(12)
	style.bg_color = Color("182631")
	style.shadow_size = 0
	style.set_corner_radius_all(12)
	panel_box.add_theme_stylebox_override("panel",style)
	parent.add_child(panel_box)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",8)
	panel_box.add_child(column)
	return column
