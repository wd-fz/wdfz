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


static func cinematic_panel(margin: int = 16) -> StyleBoxFlat:
	var style := panel(margin)
	style.bg_color = Color("101922f7")
	style.border_color = Color("4a6071")
	style.set_corner_radius_all(3)
	return style


## Fade the surface in place. Its focus, scroll position and input bounds stay live.
static func reveal(surface: Control, reduced: bool, duration: float = 0.22) -> void:
	if surface.has_meta(&"ui_reveal"):
		var previous := surface.get_meta(&"ui_reveal") as Tween
		if previous != null: previous.kill()
		surface.remove_meta(&"ui_reveal")
	surface.modulate.a = 1.0
	if reduced or not surface.is_visible_in_tree(): return
	surface.modulate.a = 0.58
	var tween := surface.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	surface.set_meta(&"ui_reveal", tween)
	tween.tween_property(surface, "modulate:a", 1.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_callback(surface.remove_meta.bind(&"ui_reveal"))

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
