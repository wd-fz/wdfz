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
var portrait := false
var key := -1
var _canvas: Control
var _n := 0                       # log lines shown
var _st := {"s": 0, "rows": 0, "marks": 0, "blink": 0}
var _bold: Font
var _mono: SystemFont
var _bold_mono: SystemFont


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
	_canvas.theme = preload("res://content/ui/theme.tres")
	_bold = _canvas.theme.default_font.duplicate()
	if _bold is SystemFont: _bold.font_weight = 700
	_mono = SystemFont.new()
	_mono.font_names = PackedStringArray(["Noto Sans Mono","monospace","Noto Sans CJK SC"])
	_bold_mono = _mono.duplicate()
	_bold_mono.font_weight = 700
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
			_text(_bold_mono, l, 24.0, 22.0 + float(i) * 44.0, 30, col)
		if _n < LOG.size():
			_canvas.draw_rect(Rect2(24.0, 22.0 + float(_n) * 44.0, 18.0, 30.0), Color("#5fbf86"))
		return
	_canvas.draw_rect(Rect2(0,0,w,h),Color("#0d1714"))
	var measure := func(text: String,fs: int) -> float: return font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
	for op: Dictionary in archive_ops(size,portrait,_st,measure):
		if op["kind"] == "text":
			var face: Font = _mono if op["mono"] else (_bold if op["bold"] else font)
			_text(face,op["text"],op["pos"].x,op["pos"].y,op["size"],op["color"])
		else:
			_canvas.draw_rect(op["rect"],op["color"],false,op["line"])


static func _add_text(ops: Array[Dictionary], text: String, pos: Vector2, fs: int, color: String, bold: bool = false, mono: bool = false) -> void:
	ops.append({"kind":"text","text":text,"pos":pos,"size":fs,"color":Color(color),"bold":bold,"mono":mono})


## The original canvas layout with injected font metrics; no gameplay state participates.
static func archive_ops(extent: Vector2i, vertical: bool, st: Dictionary, measure: Callable) -> Array[Dictionary]:
	var ops: Array[Dictionary] = []
	var w := float(extent.x)
	var h := float(extent.y)
	var pad := roundf(w*.035)
	var fs := roundi(w*(.042 if vertical else .024))
	var lh := fs*1.42
	var s := int(st["s"])
	if s>=1:
		_add_text(ops,"AnthroPrank AI · 安抄派智能　校园试点档案",Vector2(pad,pad),roundi(fs*1.05),"#9fd6b4",true)
		_add_text(ops,"控制系统：已终止",Vector2(pad,pad+lh*1.15),roundi(fs*.9),"#62d38c",false,true)
	var top := pad+lh*2.6
	var col_w := w-pad*2 if vertical else (w-pad*3)/2
	var row_h := lh*(4.6 if vertical else 2.9)
	if s>=2:
		_add_text(ops,"公司报告　↔　原始记录" if vertical else "公司报告",Vector2(pad,top),fs,"#c9e7d4",true)
		if not vertical: _add_text(ops,"原始记录（扫描件）",Vector2(pad*2+col_w,top),fs,"#e7d9a8",true)
	for r in int(st["rows"]):
		var a := Vector2(pad,top+lh*1.3+r*row_h)
		var b := Vector2(pad,a.y+lh*2.15) if vertical else Vector2(pad*2+col_w,a.y)
		var p: Array = PAIRS[r]
		_add_text(ops,p[0],a,fs,"#c9e7d4")
		_add_text(ops,p[1],a+Vector2(0,lh),fs,"#8fae9c")
		_add_text(ops,p[2],b,fs,"#e7d9a8")
		_add_text(ops,p[3],b+Vector2(0,lh),fs,"#bba978")
		if r<int(st["marks"]):
			var wa := minf(col_w,measure.call(p[0],fs))+fs*.6
			var wb := minf(col_w,maxf(measure.call(p[2],fs),measure.call(p[3],fs)))+fs*.6
			for spec: Array in [[a,wa],[b,wb]]:
				ops.append({"kind":"rect","rect":Rect2(spec[0]-Vector2(fs*.3,fs*.25),Vector2(spec[1],lh*1.95)),"color":Color("#e0473b"),"line":maxf(2,fs*.12)})
			var at := Vector2(w-pad-fs*1.2,a.y+lh*1.1) if vertical else Vector2(pad+col_w+pad*.5-fs*.45,a.y+lh*.15)
			_add_text(ops,"≠",at,roundi(fs*1.4),"#e0473b",true)
	if s>=9: _add_text(ops,"签发节点：未知"+("" if int(st["blink"])==1 else " ▌"),Vector2(pad,h-pad-lh*1.2),fs,"#e0473b",true)
	return ops
