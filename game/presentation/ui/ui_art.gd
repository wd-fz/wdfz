class_name UIArt
extends RefCounted
## Generated illustrations stay in presentation. Stable IDs and saves are unchanged.
## AtlasTexture resources share the source PNG instead of duplicating it per button.
const ROOT := "res://assets/ui/illustrations/"
static var _textures: Dictionary = {}


static func _texture(path: String) -> Texture2D:
	if not _textures.has(path):
		if not ResourceLoader.exists(ROOT + path):
			return null
		_textures[path] = load(ROOT + path) as Texture2D
	return _textures[path] as Texture2D


static func item(id: String) -> Texture2D:
	return _texture("items/%s.tres" % id) if id.is_valid_identifier() else null


static func talent(id: String) -> Texture2D:
	return _texture("talents/%s.tres" % id) if id.is_valid_identifier() else null


static func phone(app: String) -> Texture2D:
	return _texture("phone/%s.tres" % app) if app.is_valid_identifier() else null


static func wallpaper() -> Texture2D:
	return _texture("atlases/phone_wallpaper.png")


static func _named(group: String, id: String) -> Texture2D:
	var filename := id.replace(":", "_").replace(".", "_")
	return _texture("%s/%s.tres" % [group, filename]) if filename.is_valid_identifier() else null


static func achievement(id: String) -> Texture2D:
	return _named("achievements", id)


static func memory(id: String) -> Texture2D:
	if id == "rules_knock": id = "x.rules.knock"
	return _named("memories", id)


static func grade(id: String) -> Texture2D:
	return _named("grades", id)


static func nav(id: String) -> Texture2D:
	return _named("nav", id)


static func surface(id: String) -> Texture2D:
	return _named("surface", id)


static func landmark(id: String) -> Texture2D:
	if id == "garw": id = "garage"
	if id in ["c1", "c2"]: id = "link"
	if id.begins_with("bad"): id = "court"
	if id == "track": id = "field"
	if id == "trash": return memory("trash")
	for building: String in ["teach", "lab", "admin", "dorm", "garage", "guard", "canteen", "bell", "garden", "field", "court", "gear", "shed", "link", "stairs", "elevator"]:
		if id.begins_with(building): return _named("landmarks", building)
	return nav("map")


## Locked entries deliberately share one image; no secret thumbnail before discovery.
static func entry(id: String, unlocked: bool) -> Texture2D:
	if not unlocked: return surface("locked")
	if id.begins_with("x.grade."): return grade(id.trim_prefix("x.grade."))
	if id == "x.rules.knock": return memory(id)
	if id.begins_with("x.rules."): return achievement(id.trim_prefix("x."))
	var texture := memory(id)
	if texture == null: texture = achievement(id)
	return texture if texture != null else nav("archive")


## Route hints use already-known tools rather than revealing ending scenes.
static func route_hint(id: String) -> Texture2D:
	return item(String({"car": "key", "face": "usb", "portal": "coil", "cyber": "phone", "dismissal": "broadcastkey", "international": "memo"}.get(id, "notebook")))


static func button(button: Button, texture: Texture2D, width: int = 24) -> void:
	button.icon = texture
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", width)
	button.add_theme_constant_override("h_separation", 8)


## Small movable touch targets keep their original bounds and readable action text.
static func compact_button(target: Button, texture: Texture2D, width: int = 18) -> void:
	var text_width := target.get_theme_font("font").get_string_size(target.text, HORIZONTAL_ALIGNMENT_LEFT, -1, target.get_theme_font_size("font_size")).x
	var padding := target.get_theme_stylebox("normal").get_minimum_size().x
	button(target, texture if target.size.x >= text_width + padding + width + 8 else null, width)


static func heading(parent: Control, text: String, texture: Texture2D, color: Color = Color.WHITE) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(view(texture, Vector2(36, 36)))
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", color)
	row.add_child(label)
	parent.add_child(row)
	return row


## Container-managed backdrop has no minimum size and never receives input.
static func decorate(panel: PanelContainer) -> void:
	if panel.has_node("StationeryBackdrop"): return
	var background := view(_texture("atlases/stationery.png"), Vector2.ZERO)
	background.name = "StationeryBackdrop"
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.modulate.a = 0.14
	panel.add_child(background)
	panel.move_child(background, 0)


static func view(texture: Texture2D, size: Vector2) -> TextureRect:
	var image := TextureRect.new()
	image.texture = texture
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	image.custom_minimum_size = size
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image
