class_name PhonePanel
extends PanelContainer
## The phone shell (phone.js phoneEl): status line, the apps, the tool of the open app, and the paper-plane
## screen. The world keeps running while it is open; the app drives the content every frame.

signal app_selected(app: String)
signal action_pressed(action: String)
signal flap
signal closed
signal shoot_pressed
signal flash_pressed

const APPS := [["home", "主页"], ["wireless", "无线接入"], ["location", "巡察查询"], ["sync", "门禁同步"], ["container", "容器状态"], ["camera", "相机"], ["plane", "纸飞机"]]

var status: Label
var copy: Label
var hint: Label
var tool_box: VBoxContainer
var screen: PlaneView
var app_buttons: Dictionary = {}
var action_button: Button
var extra: VBoxContainer     # the camera page: shoot, flash, the album
var flash_button: Button
var album: VBoxContainer


func _init() -> void:
	name = "PhonePanel"
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.04, 0.07, 0.09, 0.99)
	back.set_content_margin_all(12)
	back.set_corner_radius_all(14)
	back.border_color = Color(0.3, 0.45, 0.5)
	back.set_border_width_all(2)
	add_theme_stylebox_override("panel", back)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var top := Label.new()
	top.text = "校园手机"
	box.add_child(top)
	status = Label.new()
	status.modulate = Color(0.7, 0.9, 0.8)
	box.add_child(status)
	var nav := HFlowContainer.new()
	for a: Array in APPS:
		var b := Button.new()
		b.name = "App_" + String(a[0])
		b.text = String(a[1])
		b.toggle_mode = true
		b.pressed.connect(func() -> void: app_selected.emit(String(a[0])))
		nav.add_child(b)
		app_buttons[a[0]] = b
	box.add_child(nav)
	copy = Label.new()
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.custom_minimum_size = Vector2(300, 90)
	box.add_child(copy)
	action_button = Button.new()
	action_button.name = "PhoneAction"
	action_button.pressed.connect(func() -> void: action_pressed.emit(String(action_button.get_meta("action", ""))))
	box.add_child(action_button)
	extra = VBoxContainer.new()
	extra.name = "PhoneExtra"
	var shoot := Button.new()
	shoot.name = "Shoot"
	shoot.text = "拍照"
	shoot.pressed.connect(func() -> void: shoot_pressed.emit())
	extra.add_child(shoot)
	flash_button = Button.new()
	flash_button.name = "Flash"
	flash_button.toggle_mode = true
	flash_button.pressed.connect(func() -> void: flash_pressed.emit())
	extra.add_child(flash_button)
	var shelf := ScrollContainer.new()
	shelf.custom_minimum_size = Vector2(300, 150)
	album = VBoxContainer.new()
	album.add_theme_constant_override("separation", 6)
	shelf.add_child(album)
	extra.add_child(shelf)
	box.add_child(extra)
	screen = PlaneView.new()
	screen.pressed.connect(func() -> void: flap.emit())
	box.add_child(screen)
	hint = Label.new()
	hint.modulate = Color(1, 1, 1, 0.55)
	box.add_child(hint)
	var close := Button.new()
	close.text = "✕ 收起"
	close.pressed.connect(func() -> void: closed.emit())
	box.add_child(close)
	add_child(box)


## Select the app visually. action: "" hides the button; label its text.
func select(app: String, action: String, label: String, disabled: bool) -> void:
	for k: String in app_buttons:
		(app_buttons[k] as Button).button_pressed = k == app
	screen.visible = app == "plane"
	copy.visible = app != "plane"
	hint.visible = app == "plane"
	extra.visible = app == "camera"
	action_button.visible = action != ""
	action_button.set_meta("action", action)
	action_button.text = label
	action_button.disabled = disabled


## The album: newest first; each a thumbnail and its line.
func show_album(photos: Array, flash_on: bool) -> void:
	flash_button.text = "闪光：" + ("开" if flash_on else "关")
	flash_button.button_pressed = flash_on
	var key := "|".join(PackedStringArray(photos.map(func(p: Dictionary) -> String: return "%d:%d" % [int(p["t"]), int(p["day"])])))
	if album.has_meta("key") and album.get_meta("key") == key:
		return
	album.set_meta("key", key)
	for c in album.get_children():
		c.queue_free()
	for p: Dictionary in photos:
		var row := HBoxContainer.new()
		var tex := TextureRect.new()
		tex.custom_minimum_size = Vector2(96, 54)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		var img := Image.new()
		if img.load_jpg_from_buffer(Marshalls.base64_to_raw(String(p["img"]))) == OK:
			tex.texture = ImageTexture.create_from_image(img)
		row.add_child(tex)
		var cap := Label.new()
		cap.text = "第 %d 天 · %s · %s" % [int(p["day"]), p["place"], p["cap"]]
		cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cap.custom_minimum_size = Vector2(190, 0)
		cap.add_theme_font_size_override("font_size", 12)
		row.add_child(cap)
		album.add_child(row)


class PlaneView extends Control:
	signal pressed
	var game: PlaneGame
	const FIT := 0.78    # the screen is drawn smaller so the phone fits a 720-high window

	func _init() -> void:
		custom_minimum_size = Vector2(PlaneGame.W, PlaneGame.H) * FIT
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
			pressed.emit()
			accept_event()

	func _draw() -> void:
		if game == null:
			return
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(FIT, FIT))
		draw_rect(Rect2(Vector2.ZERO, Vector2(PlaneGame.W, PlaneGame.H)), Color("#0b1a24"))
		for k in 12:
			draw_rect(Rect2(fposmod(k * 37.0 - game.t * 20.0, PlaneGame.W + 40.0) - 20.0, 40.0 + fposmod(k * 53.0, 250.0), 2, 2), Color(0.55, 0.75, 0.82, 0.08))
		for p: Dictionary in game.pipes:
			var px := float(p["x"])
			var gy := float(p["gy"])
			draw_rect(Rect2(px, 0, 26, gy), Color("#4a3a2a"))
			draw_rect(Rect2(px, gy + PlaneGame.GAP, 26, PlaneGame.H - gy - PlaneGame.GAP), Color("#4a3a2a"))
			var y := 8.0
			while y < gy:
				draw_rect(Rect2(px + 2, y, 22, 3), Color("#7a5f40"))
				y += 16.0
			y = gy + PlaneGame.GAP + 8.0
			while y < PlaneGame.H:
				draw_rect(Rect2(px + 2, y, 22, 3), Color("#7a5f40"))
				y += 16.0
		var a := clampf(game.vy / 400.0, -0.5, 0.9)
		draw_set_transform(Vector2(40, game.y) * FIT, a, Vector2(FIT, FIT))
		draw_colored_polygon(PackedVector2Array([Vector2(12, 0), Vector2(-10, -7), Vector2(-5, 0), Vector2(-10, 7)]), Color("#e8eef0"))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(FIT, FIT))
		var font := get_theme_default_font()
		draw_string(font, Vector2(PlaneGame.W / 2.0 - 8.0, 36), str(game.score), HORIZONTAL_ALIGNMENT_CENTER, -1, 22, Color("#dfeff2"))
		if game.st != "fly":
			draw_rect(Rect2(0, PlaneGame.H / 2.0 - 44.0, PlaneGame.W, 88), Color(0, 0, 0, 0.55))
			draw_string(font, Vector2(0, PlaneGame.H / 2.0 - 10.0), "点一下开始" if game.st == "ready" else "结束 · 得分 %d" % game.score, HORIZONTAL_ALIGNMENT_CENTER, PlaneGame.W, 14, Color("#e8f4ec"))
			var sub := (game.msg if game.msg != "" else "再点一下重来") if game.st == "over" else ("手机还烫着，静不下心" if game.cool > 0.0 else "玩一会儿，缓口气")
			draw_string(font, Vector2(0, PlaneGame.H / 2.0 + 16.0), sub, HORIZONTAL_ALIGNMENT_CENTER, PlaneGame.W, 11, Color("#9fe3c2"))
