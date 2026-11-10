class_name DebugTrace
extends RefCounted
## In-memory debugging facts and commands; no profile writes, timers or object references.
const LIMIT := 120
var entries: Array[Dictionary] = []
var recording := true
var revision := 0
var discarded := 0
var _sequence := 0

func add(kind: String, title: String, detail: Variant = {}, context: Dictionary = {}) -> void:
	if not recording: return
	_sequence+=1
	var entry:={"seq":_sequence,"kind":kind.substr(0,24),"title":title.substr(0,100),"detail":clean(detail),"context":clean(context)}
	if entries.size()>=LIMIT:
		entries.pop_front()
		discarded+=1
	entries.append(entry)
	revision+=1

func clear() -> void:
	entries.clear()
	discarded=0
	revision+=1

func capture() -> Dictionary:
	return {"recording":recording,"revision":revision,"discarded":discarded,"entries":entries.duplicate(true)}

static func clean(value: Variant, depth: int = 0) -> Variant:
	return _clean(value,depth,[128])

static func _clean(value: Variant, depth: int, budget: Array[int]) -> Variant:
	if budget[0]<=0: return "…"
	budget[0]-=1
	if depth>5: return "…"
	if value==null or value is bool or value is int: return value
	if value is float: return value if is_finite(value) else null
	if value is String or value is StringName: return String(value).substr(0,300)
	if value is Vector2: return [value.x,value.y]
	if value is Vector3: return [value.x,value.y,value.z]
	if value is Array or value is PackedStringArray:
		var result:=[]
		for i in mini(value.size(),24):
			if budget[0]<=0: break
			result.append(_clean(value[i],depth+1,budget))
		return result
	if value is Dictionary:
		var result:={}
		for key: Variant in value:
			if result.size()>=24 or budget[0]<=0: break
			result[String(key).substr(0,64)]= _clean(value[key],depth+1,budget)
		return result
	return "<%s>" % type_string(typeof(value))
