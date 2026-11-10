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


static func view(texture: Texture2D, size: Vector2) -> TextureRect:
	var image := TextureRect.new()
	image.texture = texture
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	image.custom_minimum_size = size
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image
