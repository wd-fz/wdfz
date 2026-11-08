class_name CutScreen
extends SubViewport
## The text screens of the 网安仙人 ending (modules/cyber-route/ending.js screen/drawLog/drawArchive): a canvas that is
## redrawn only when its content changes, shown on a quad in the scene. Modes: "log" (the console's shutdown log) and
## "archive" (company report against the original record, three contradictions circled, the last line blinking).

const LOG := [[0.25, "$ campusctl shutdown --confirm"], [0.75, "stop attendance ............ OK"], [1.35, "stop doors ................. OK"],
	[1.95, "broadcast: 全体同学请注——"], [2.25, "stop observation ........... OK"], [2.75, "stop control ............... OK"]]
const PAIRS := [["首次部署：2026-09-01", "部署前：无任何异常记录", "纸质档案扫描：1987 年", "走廊里出现不在值班表上的人"],
	["巡察行为：全部由控制器产生", "断链即全部停止", "断链故障记录：控制链离线后", "仍收到回执（签发节点：——）"],
	["退出身份：已注销", "数据已删除", "「注销」字段原始定义：", "转交上层保管"]]
const HEAD := 7.35
const COLS := 7.6
const ROWS := [7.9, 8.6, 9.3]
const MARKS := [8.25, 8.95, 9.65]
const LAST := 10.25

var mode := "log"
var key := -1
var _canvas: Control
var _n := 0                       # log lines shown
var _st := {"s": 0, "rows": 0, "marks": 0, "blink": 0}


static func log_lines(t: float) -> int:
	var n := 0
	for l: Array in LOG:
		if t >= float(l[0]):
			n += 1
	return n


## archState: how much of the archive is drawn at time t.
static func arch_state(t: float) -> Dictionary:
	var s := 0
	if t >= HEAD:
		s = 1
	if t >= COLS:
		s = 2
	var rows := 0
	var marks := 0
	for r: float in ROWS:
		if t >= r:
			s += 1
			rows += 1
	for r: float in MARKS:
		if t >= r:
			s += 1
			marks += 1
	if t >= LAST:
		s += 1
	var blink := int((t - LAST) / 0.45) % 2 if t >= LAST else 0
	return {"s": s, "rows": rows, "marks": marks, "blink": blink, "key": s * 10 + blink}


func setup(screen_mode: String, w: int, h: int) -> void:
	mode = screen_mode
	size = Vector2i(w, h)
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	disable_3d = true
	transparent_bg = false
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_canvas)
	add_child(_canvas)


func show_log(n: int) -> void:
	if n != key:
		key = n
		_n = n
		_canvas.queue_redraw()


func show_archive(t: float) -> void:
	var st := arch_state(t)
	if int(st["key"]) != key:
		key = int(st["key"])
		_st = st
		_canvas.queue_redraw()


func _text(font: Font, s: String, x: float, y_top: float, fs: int, color: Color) -> void:
	_canvas.draw_string(font, Vector2(x, y_top + font.get_ascent(fs)), s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, color)


func _draw_canvas() -> void:
	var font := _canvas.get_theme_default_font()
	var w := float(size.x)
	var h := float(size.y)
	if mode == "log":
		_canvas.draw_rect(Rect2(0, 0, w, h), Color("#07130e"))
		for i in _n:
			var l := String(LOG[i][1])
			var col := Color("#d7c27a") if l.begins_with("broadcast") else (Color("#b9f2c8") if i == _n - 1 else Color("#5fbf86"))
			_text(font, l, 24.0, 22.0 + float(i) * 44.0, 30, col)
		if _n < LOG.size():
			_canvas.draw_rect(Rect2(24.0, 22.0 + float(_n) * 44.0, 18.0, 30.0), Color("#5fbf86"))
		return
	_canvas.draw_rect(Rect2(0, 0, w, h), Color("#0d1714"))
	var pad := roundf(w * 0.035)
	var fs := int(roundf(w * 0.024))
	var lh := float(fs) * 1.42
	var s := int(_st["s"])
	if s >= 1:
		_text(font, "AnthroPrank AI · 安抄派智能　校园试点档案", pad, pad, int(roundf(float(fs) * 1.05)), Color("#9fd6b4"))
		_text(font, "控制系统：已终止", pad, pad + lh * 1.15, int(roundf(float(fs) * 0.9)), Color("#62d38c"))
	var top := pad + lh * 2.6
	var col_w := (w - pad * 3.0) / 2.0
	var row_h := lh * 2.9
	if s >= 2:
		_text(font, "公司报告", pad, top, fs, Color("#c9e7d4"))
		_text(font, "原始记录（扫描件）", pad * 2.0 + col_w, top, fs, Color("#e7d9a8"))
	for r in int(_st["rows"]):
		var a := Vector2(pad, top + lh * 1.3 + float(r) * row_h)
		var b := Vector2(pad * 2.0 + col_w, a.y)
		var p: Array = PAIRS[r]
		_text(font, String(p[0]), a.x, a.y, fs, Color("#c9e7d4"))
		_text(font, String(p[1]), a.x, a.y + lh, fs, Color("#8fae9c"))
		_text(font, String(p[2]), b.x, b.y, fs, Color("#e7d9a8"))
		_text(font, String(p[3]), b.x, b.y + lh, fs, Color("#bba978"))
		if r < int(_st["marks"]):
			# Circle the contradiction on both sides, a "≠" between.
			var red := Color("#e0473b")
			var lw := maxf(2.0, float(fs) * 0.12)
			var wa := minf(col_w, font.get_string_size(String(p[0]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x) + float(fs) * 0.6
			var wb := minf(col_w, maxf(font.get_string_size(String(p[2]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x, font.get_string_size(String(p[3]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x)) + float(fs) * 0.6
			_canvas.draw_rect(Rect2(a.x - float(fs) * 0.3, a.y - float(fs) * 0.25, wa, lh * 1.95), red, false, lw)
			_canvas.draw_rect(Rect2(b.x - float(fs) * 0.3, b.y - float(fs) * 0.25, wb, lh * 1.95), red, false, lw)
			_text(font, "≠", pad + col_w + pad * 0.5 - float(fs) * 0.45, a.y + lh * 0.15, int(roundf(float(fs) * 1.4)), red)
	if s >= 9:
		_text(font, "签发节点：未知" + ("" if int(_st["blink"]) == 1 else " ▌"), pad, h - pad - lh * 1.2, fs, Color("#e0473b"))
