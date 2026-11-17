class_name UISkin
extends RefCounted
## Shared visual vocabulary for every menu, document and tool window.
const THEME: Theme = preload("res://content/ui/theme.tres")
const INK := Color("eff4f8")
const MUTED := Color("afbecc")
const ACCENT := Color("a9dddf")
const WARM := Color("e6c492")
const DANGER := Color("eda9ad")
const CARD := Color("1b2734")
const CARD_EDGE := Color("2f4152")
const SHADE := Color("070e16")

static func panel(margin: int = 16) -> StyleBoxFlat:
	var style := THEME.get_stylebox("panel","PanelContainer").duplicate() as StyleBoxFlat
	style.set_content_margin_all(margin)
	return style

static func card(parent: Control) -> VBoxContainer:
	var panel_box := PanelContainer.new()
	panel_box.mouse_filter = Control.MOUSE_FILTER_PASS
	panel_box.theme_type_variation = "CardPanel"
	parent.add_child(panel_box)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",8)
	panel_box.add_child(column)
	return column


static func shade(parent: Control, opacity: float) -> void:
	var backdrop := ColorRect.new()
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.color = Color(SHADE, opacity)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(backdrop)
