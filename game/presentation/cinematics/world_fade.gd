class_name WorldFade
extends CanvasLayer
## world.js fadeTo: .16 s CSS ease to black, change at .17 s, .30 s ease back.
## Owned by the current application flow; cancellation cannot run a delayed room change.
signal finished
var elapsed := 0.0
var committed := false
var active := false
var _change := Callable()
var _black: ColorRect


static func css_ease(value: float) -> float:
	# CSS ease is cubic-bezier(.25,.1,.25,1); solve x to obtain the matching y.
	var x:=clampf(value,0,1)
	var lo:=0.0
	var hi:=1.0
	for i in 24:
		var t: float=(lo+hi)/2
		var px:=3*(1-t)*(1-t)*t*.25+3*(1-t)*t*t*.25+t*t*t
		if px<x: lo=t
		else: hi=t
	var t: float=(lo+hi)/2
	return 3*(1-t)*(1-t)*t*.1+3*(1-t)*t*t+t*t*t


func begin(change: Callable) -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	layer=20
	_black=ColorRect.new()
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_black.color=Color(0,0,0,0)
	add_child(_black)
	_change=change
	active=true
	set_process(true)


func _process(dt: float) -> void:
	advance(dt)


func advance(dt: float) -> void:
	if not active: return
	elapsed+=maxf(0,dt)
	_black.color.a=css_ease(elapsed/.16) if elapsed<.17 else 1-css_ease((elapsed-.17)/.30)
	if not committed and elapsed>=.17:
		committed=true
		if _change.is_valid(): _change.call()
		_change=Callable()
	if active and elapsed>=.47:
		cancel()


func cancel() -> void:
	if not active: return
	active=false
	_change=Callable()
	hide()
	set_process(false)
	finished.emit()
	queue_free()
