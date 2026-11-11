class_name GroundItems
extends Node3D
## Items the player dropped (InventoryModule.ground) lying on the floor of this scene. Each one is the item's
## own illustration laid flat with a soft contact shadow, lit by the scene (it is as dark as the floor at night)
## plus a faint self-light so it never vanishes into the floor; the one in reach is lifted a little and brightened.
## No collision: a dropped item never blocks a door, a desk or the patrol path.

const SIZE := 0.34          # metres across the illustration
const LIFT := 0.012         # above the floor, clear of z-fighting
const BASE_TINT := Color(0.86, 0.84, 0.8)
const FOCUS_TINT := Color(1.35, 1.3, 1.18)

var ground_height: Callable
var _data: Array = []
var _sprites: Array[Sprite3D] = []
var _focus := -1
var _t := 0.0
static var _shadow_texture: Texture2D


func _init() -> void:
	name = "GroundItems"


func count() -> int:
	return _sprites.size()


## Rebuild only when the list for this scene actually changed (positions and ids).
func sync(list: Array) -> void:
	if list == _data:
		return
	_data = list.duplicate(true)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_sprites.clear()
	_focus = -1
	for i in _data.size():
		_build(i, _data[i])


func _floor_y(x: float, y: float, z: float) -> float:
	if ground_height.is_valid() and y > -0.6 and y < 1.6:
		var gy := float(ground_height.call(x, z))
		if is_finite(gy) and absf(gy - y) < 0.35:
			return gy
	return y


func _build(i: int, entry: Dictionary) -> void:
	var holder := Node3D.new()
	holder.name = "Ground_%d_%s" % [i, String(entry["id"])]
	var x := float(entry["x"])
	var z := float(entry["z"])
	holder.position = Vector3(x, _floor_y(x, float(entry["y"]), z), z)
	# A stable small turn per item so a pile does not look stamped.
	holder.rotation.y = float(hash("%s:%d" % [entry["id"], i]) % 628) / 100.0
	add_child(holder)
	var shadow := Sprite3D.new()
	shadow.name = "Shadow"
	shadow.texture = _shadow()
	shadow.axis = Vector3.AXIS_Y
	shadow.pixel_size = SIZE * 1.25 / 64.0
	shadow.modulate = Color(0, 0, 0, 0.55)
	shadow.position.y = LIFT * 0.5
	shadow.shaded = false
	shadow.transparent = true
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(shadow)
	var art := Sprite3D.new()
	art.name = "Art"
	var texture := UIArt.item(String(entry["id"]))
	art.texture = texture
	art.axis = Vector3.AXIS_Y
	art.pixel_size = SIZE / maxf(1.0, float(texture.get_width()) if texture != null else 64.0)
	art.shaded = true
	art.double_sided = true
	art.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	art.modulate = BASE_TINT
	art.position.y = LIFT
	art.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(art)
	# The faint self-light: an unshaded copy at low alpha keeps the outline legible in the dark.
	var glow := Sprite3D.new()
	glow.name = "Glow"
	glow.texture = texture
	glow.axis = Vector3.AXIS_Y
	glow.pixel_size = art.pixel_size
	glow.shaded = false
	glow.transparent = true
	glow.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	glow.modulate = Color(0.75, 0.78, 0.74, 0.14)
	glow.position.y = LIFT * 1.5
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(glow)
	_sprites.append(art)


## index is the position in this scene's list (InventoryModule.ground_in order), -1 for none.
func set_focus(index: int) -> void:
	_focus = index


func focus() -> int:
	return _focus


func _process(delta: float) -> void:
	_t += delta
	for i in _sprites.size():
		var art := _sprites[i]
		if not is_instance_valid(art):
			continue
		var on := i == _focus
		var pulse := 0.5 + 0.5 * sin(_t * 3.2)
		art.modulate = BASE_TINT.lerp(FOCUS_TINT, 0.65 + 0.35 * pulse) if on else BASE_TINT
		art.position.y = LIFT + (0.02 if on else 0.0)
		var glow := art.get_parent().get_node_or_null("Glow") as Sprite3D
		if glow != null:
			glow.position.y = art.position.y + LIFT * 0.5
			glow.modulate.a = (0.26 + 0.12 * pulse) if on else 0.14


static func _shadow() -> Texture2D:
	if _shadow_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(0.5, 0.0)
		texture.width = 64
		texture.height = 64
		_shadow_texture = texture
	return _shadow_texture
