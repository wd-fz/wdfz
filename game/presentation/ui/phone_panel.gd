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
var _layout: HBoxContainer
var _body_scroll: ScrollContainer
var _nav_scroll: ScrollContainer


func _init() -> void:
	name = "PhonePanel"
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var back := UISkin.panel(16)
	add_theme_stylebox_override("panel", back)
	var wallpaper := UIArt.view(UIArt.wallpaper(), Vector2.ZERO)
	wallpaper.name = "PhoneWallpaper"
	wallpaper.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	wallpaper.modulate = Color(1, 1, 1, 0.32)
	add_child(wallpaper)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	var header := HBoxContainer.new()
	box.add_child(header)
	var top := Label.new()
	top.text = "校园手机"
	top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_theme_color_override("font_color",UISkin.ACCENT)
	header.add_child(top)
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 10)
	status_row.add_child(UIArt.view(UIArt.phone("battery"), Vector2(30, 24)))
	box.add_child(status_row)
	status = Label.new()
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color",UISkin.MUTED)
	status_row.add_child(status)
	_layout = HBoxContainer.new()
	_layout.add_theme_constant_override("separation",16)
	box.add_child(_layout)
	_nav_scroll = ScrollContainer.new()
	_nav_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_nav_scroll.follow_focus = true
	_layout.add_child(_nav_scroll)
	var nav := VBoxContainer.new()
	nav.add_theme_constant_override("separation", 4)
	nav.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_nav_scroll.add_child(nav)
	_body_scroll = ScrollContainer.new()
	_body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body_scroll.follow_focus = true
	_body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layout.add_child(_body_scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",12)
	_body_scroll.add_child(body)
	for a: Array in APPS:
		var b := Button.new()
		b.name = "App_" + String(a[0])
		b.text = String(a[1])
		b.icon = UIArt.phone(String(a[0]))
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_constant_override("icon_max_width", 32)
		b.add_theme_constant_override("h_separation", 10)
		b.toggle_mode = true
		b.custom_minimum_size.y = 52
		b.pressed.connect(func() -> void: app_selected.emit(String(a[0])))
		nav.add_child(b)
		app_buttons[a[0]] = b
	copy = Label.new()
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.custom_minimum_size = Vector2(0, 90)
	body.add_child(copy)
	action_button = Button.new()
	action_button.name = "PhoneAction"
	action_button.theme_type_variation = "PrimaryButton"
	action_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action_button.custom_minimum_size.y = 48
	action_button.pressed.connect(func() -> void: action_pressed.emit(String(action_button.get_meta("action", ""))))
	body.add_child(action_button)
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
	shelf.custom_minimum_size = Vector2(0, 150)
	shelf.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	album = VBoxContainer.new()
	album.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	album.add_theme_constant_override("separation", 6)
	shelf.add_child(album)
	extra.add_child(shelf)
	body.add_child(extra)
	screen = PlaneView.new()
	screen.pressed.connect(func() -> void: flap.emit())
	body.add_child(screen)
	hint = Label.new()
	hint.add_theme_color_override("font_color",UISkin.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(hint)
	var close := Button.new()
	close.text = "收起"
	close.name = "PhoneClose"
	close.custom_minimum_size.y = 44
	close.pressed.connect(func() -> void: closed.emit())
	header.add_child(close)
	add_child(box)
	minimum_size_changed.connect(func() -> void: _fit.call_deferred())
	visibility_changed.connect(func() -> void: _fit.call_deferred())


func _ready() -> void:
	get_viewport().size_changed.connect(_fit)
	_fit.call_deferred()


func _fit() -> void:
	if not is_inside_tree() or not visible: return
	_nav_scroll.custom_minimum_size.x = 184*get_theme_default_font_size()/16.0
	PanelLayout.fit(self,_layout,820,432)


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
	_fit.call_deferred()


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
		cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
