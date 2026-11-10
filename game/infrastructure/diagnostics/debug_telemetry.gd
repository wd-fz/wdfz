class_name DebugTelemetry
extends RefCounted
## Bounded real-frame measurements. Never modifies engine time or gameplay settings.
const MAX_SAMPLES := 180
var intervals: Array[float] = []
var _cursor := 0
var _total := 0.0

func sample(delta: float) -> void:
	if not is_finite(delta) or delta<=0: return
	if intervals.size()<MAX_SAMPLES:
		intervals.append(delta)
	else:
		_total-=intervals[_cursor]
		intervals[_cursor]=delta
		_cursor=(_cursor+1)%MAX_SAMPLES
	_total+=delta

func reset() -> void:
	intervals.clear()
	_cursor=0
	_total=0

func capture(rendered: bool = true) -> Dictionary:
	var sorted:=intervals.duplicate()
	sorted.sort()
	var p95:=0.0 if sorted.is_empty() else float(sorted[clampi(ceili(sorted.size()*.95)-1,0,sorted.size()-1)])*1000
	return {"samples":intervals.size(),"average_ms":_total/maxi(1,intervals.size())*1000,"p95_ms":p95,
		"fps":Engine.get_frames_per_second(),"rendered":rendered,
		"draw_calls":int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)) if rendered else -1,
		"primitives":int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)) if rendered else -1,
		"render_objects":int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)) if rendered else -1,
		"nodes":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"resources":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"static_mib":float(Performance.get_monitor(Performance.MEMORY_STATIC))/1048576.0}
