class_name UISkin
extends RefCounted
## Shared visual vocabulary for every menu, document and tool window.
const THEME: Theme = preload("res://content/ui/theme.tres")
const INK := Color("ece6da")
const MUTED := Color("9aa4a6")
const ACCENT := Color("8fd6c0")
## Lamp amber for warnings and the focus ring; a dried-rust red for danger.
const WARM := Color("e6c27a")
const DANGER := Color("c56a5f")
const CARD := Color("10181d")
const CARD_EDGE := Color("1f2b31")

static func panel(margin: int = 16) -> StyleBoxFlat:
	var style := THEME.get_stylebox("panel","PanelContainer").duplicate() as StyleBoxFlat
	style.set_content_margin_all(margin)
	return style

static func card(parent: Control) -> VBoxContainer:
	var panel_box := PanelContainer.new()
	panel_box.mouse_filter = Control.MOUSE_FILTER_PASS
	var style := panel(12)
	style.bg_color = CARD
	style.border_color = CARD_EDGE
	style.shadow_size = 0
	style.set_corner_radius_all(12)
	panel_box.add_theme_stylebox_override("panel",style)
	parent.add_child(panel_box)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",8)
	panel_box.add_child(column)
	return column
