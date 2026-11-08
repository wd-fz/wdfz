class_name PanelLayout
extends RefCounted
## Keep document content scrollable while the surrounding controls remain reachable.

static func fit(panel: PanelContainer, body: Control, width: float, body_height: float, bottom_margin: float = -1) -> void:
	if not is_instance_valid(panel) or not panel.visible or not panel.is_inside_tree(): return
	var screen := panel.get_viewport().get_visible_rect().size
	var column := body.get_parent() as BoxContainer
	var style := panel.get_theme_stylebox("panel")
	width = minf(width, screen.x-24)
	panel.custom_minimum_size.x = width
	column.size.x = width-style.get_minimum_size().x
	var fixed := style.get_minimum_size().y
	var count := 0
	for child in column.get_children():
		if child is Control and child.visible:
			count += 1
			if child != body: fixed += child.get_combined_minimum_size().y
	fixed += maxi(0,count-1)*column.get_theme_constant("separation")
	var available := maxf(64, screen.y-fixed-24-maxf(0,bottom_margin))
	body.custom_minimum_size = Vector2(0, clampf(body_height,64,available))
	panel.reset_size()
	panel.position = (screen-panel.size)*.5
	if bottom_margin >= 0: panel.position.y = screen.y-panel.size.y-bottom_margin
