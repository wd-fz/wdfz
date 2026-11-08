class_name SnakePanel
extends PanelContainer
## The snake game's screen (pcgame.js): the board, a touch pad and the way out.

signal turned(dir: Vector2i)
signal closed

var game: SnakeGame
var board: Board
var hint: Label
const CELL := 18


func _init() -> void:
	name = "SnakePanel"
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var back := UISkin.panel(16)
	add_theme_stylebox_override("panel", back)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation",20)
	board = Board.new()
	board.swiped.connect(func(d: Vector2i) -> void: turned.emit(d))
	box.add_child(board)
	var controls := VBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override("separation",12)
	box.add_child(controls)
	var title := Label.new()
	title.text = "机房 · 贪吃蛇"
	title.add_theme_color_override("font_color",UISkin.ACCENT)
	controls.add_child(title)
	var pad := GridContainer.new()
	pad.columns = 3
	pad.name = "Pad"
	var spec := [["", Vector2i.ZERO], ["↑", Vector2i(0, -1)], ["", Vector2i.ZERO], ["←", Vector2i(-1, 0)], ["", Vector2i.ZERO], ["→", Vector2i(1, 0)], ["", Vector2i.ZERO], ["↓", Vector2i(0, 1)]]
	for sp: Array in spec:
		if sp[0] == "":
			pad.add_child(Control.new())
			continue
		var b := Button.new()
		b.text = String(sp[0])
		b.custom_minimum_size = Vector2(52, 48)
		b.button_down.connect(func() -> void: turned.emit(sp[1]))
		pad.add_child(b)
	controls.add_child(pad)
	hint = Label.new()
	hint.add_theme_color_override("font_color",UISkin.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_child(hint)
	var out := Button.new()
	out.text = "离开"
	out.name = "SnakeClose"
	out.custom_minimum_size.y = 44
	out.pressed.connect(func() -> void: closed.emit())
	controls.add_child(out)
	add_child(box)
	minimum_size_changed.connect(func() -> void: _fit.call_deferred())
	visibility_changed.connect(func() -> void: _fit.call_deferred())


func _ready() -> void:
	get_viewport().size_changed.connect(_fit)
	_fit.call_deferred()


func _fit() -> void:
	if not is_inside_tree() or not visible: return
	custom_minimum_size.x = minf(680,get_viewport_rect().size.x-24)
	reset_size()
	position = (get_viewport_rect().size-size)*.5


class Board extends Control:
	signal swiped(dir: Vector2i)
	var game: SnakeGame
	var _from := Vector2.ZERO
	var _down := false

	func _init() -> void:
		custom_minimum_size = Vector2(SnakeGame.N * CELL, SnakeGame.N * CELL)

	func _gui_input(event: InputEvent) -> void:
		var pos := Vector2.ZERO
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_down = event.pressed
			_from = event.position
		elif event is InputEventMouseMotion and _down:
			var d: Vector2 = event.position - _from
			if maxf(absf(d.x), absf(d.y)) >= 18.0:
				swiped.emit(Vector2i(signi(int(d.x)), 0) if absf(d.x) > absf(d.y) else Vector2i(0, signi(int(d.y))))
				_from = event.position

	func _draw() -> void:
		if game == null:
			return
		var n := SnakeGame.N
		draw_rect(Rect2(0, 0, n * CELL, n * CELL), Color("#0a1210"))
		for g in n + 1:
			draw_line(Vector2(g * CELL, 0), Vector2(g * CELL, n * CELL), Color(0.47, 0.78, 0.67, 0.1))
			draw_line(Vector2(0, g * CELL), Vector2(n * CELL, g * CELL), Color(0.47, 0.78, 0.67, 0.1))
		draw_rect(Rect2(game.food.x * CELL + 3, game.food.y * CELL + 3, CELL - 6, CELL - 6), Color("#c8554a"))
		for i in game.body.size():
			var b: Vector2i = game.body[i]
			draw_rect(Rect2(b.x * CELL + 1, b.y * CELL + 1, CELL - 2, CELL - 2), Color("#5a9a7a") if i > 0 else Color("#79c8a4"))
		var font := get_theme_default_font()
		if game.cd > 0.0:
			draw_rect(Rect2(0, 0, n * CELL, n * CELL), Color(0, 0, 0, 0.6))
			draw_string(font, Vector2(0, n * CELL / 2.0 + 22), str(ceili(game.cd)), HORIZONTAL_ALIGNMENT_CENTER, n * CELL, 64, Color("#dff5ea"))
			draw_string(font, Vector2(0, n * CELL / 2.0 + 50), "准备", HORIZONTAL_ALIGNMENT_CENTER, n * CELL, 11, Color("#9fe3c2"))
		if game.dead:
			draw_rect(Rect2(0, 0, n * CELL, n * CELL), Color(0, 0, 0, 0.72))
			draw_string(font, Vector2(0, n * CELL / 2.0 - 4), "结束 · 得分 %d" % game.score, HORIZONTAL_ALIGNMENT_CENTER, n * CELL, 15, Color("#e8f4ec"))
