class_name InceptionModule
extends FeatureModule
## modules/inception/dream.js: daily sleep draws, persistent top result and one wake settlement.
const ROOM := "dream_top"
const TOP_ROOM := "dorm2"
const TOP_CELL := Vector2i(5,3)
const START := Vector2i(1,1)
const EXIT := Vector2i(21,15)
const FALL_TIME := 1.4
const GRID := [
	"#######################",
	"#S....#.......#.......#",
	"#.###.#.#####.#.#####.#",
	"#.#...#.#ppp#...#...#.#",
	"#.#.###.#.p.#####.#.#.#",
	"#.#.....#.p.......#.#.#",
	"#.#######.#########.#.#",
	"#.....pp..#.......#...#",
	"#####.#####.#####.#####",
	"#.....#ppppp#...#.....#",
	"#.###.#.....#.#.#####.#",
	"#.#...#.###.#.#.......#",
	"#.#.###.#.#...#######.#",
	"#.#.....#.#ppp#.......#",
	"#.#######.#####.#####.#",
	"#.........#.........#E#",
	"#######################"]
var top := false
var class_day: Dictionary = {}
var entered: Dictionary = {}
var dream: Dictionary = {}
var settled: Dictionary = {}
var events: Array[Dictionary] = []
var roll := Callable()
var _rng := RandomNumberGenerator.new()
var _rooms: Dictionary


func _init(rooms: Dictionary = {}) -> void:
	_rooms=rooms


func module_id() -> StringName:
	return &"story.inception"


func reset() -> void:
	top=false
	class_day={}
	entered={}
	dream={}
	settled={}
	events=[]
	_rng.randomize()


func set_seed(value: int) -> void:
	_rng.seed=value


func capture() -> Dictionary:
	return {"top":top,"class_day":class_day.duplicate(),"entered":entered.duplicate(),"dream":dream.duplicate(true),"settled":settled.duplicate(),"random":RandomState.capture(_rng)}


func validate(data: Dictionary) -> String:
	if not data.get("top") is bool: return "陀螺状态无效"
	for key in ["class_day","entered","settled"]:
		if not data.get(key) is Dictionary: return "梦境记录无效"
		for id: Variant in data[key]:
			if not id is String or not data[key][id] is bool: return "梦境记录键值无效"
			if key!="settled" and (not id.is_valid_int() or int(id)<1): return "梦境日期无效"
	if not data.get("dream") is Dictionary: return "梦境进度无效"
	var d: Dictionary=data["dream"]
	if d.is_empty(): return ""
	if not SaveSchema.is_integer(d.get("day"),1,1000000) or not d.get("spin") in ["","stand","fall"] or not d.get("id") is String or not SaveSchema.number_in(d.get("falling"),0,FALL_TIME):
		return "梦境进度无效"
	var from: Variant=d.get("from")
	if not from is Dictionary or not from.get("room") is String or (not _rooms.is_empty() and not _rooms.has(from["room"])):
		return "梦境返回房间无效"
	if from.get("x")==null and from.get("y")==null: return ""
	for key in ["x","y","ang","floorY"]:
		if not SaveSchema.number_in(from.get(key),-1e8,1e8): return "梦境返回位置无效"
	return ""


func restore(data: Dictionary) -> void:
	top=data["top"]
	class_day=data["class_day"].duplicate()
	entered=data["entered"].duplicate()
	dream=data["dream"].duplicate(true)
	settled=data["settled"].duplicate()
	RandomState.restore(_rng,data)
	events=[]


func take_events() -> Array[Dictionary]:
	var out:=events
	events=[]
	return out


func _emit(kind: String, data: Dictionary = {}) -> void:
	data["kind"]=kind
	events.append(data)


func _say(text: String) -> void:
	_emit("notice",{"text":text})


func _random() -> float:
	return float(roll.call()) if roll.is_valid() else _rng.randf()


func near_top(scene: String, room: Dictionary, w: Vector2) -> bool:
	return not top and scene==TOP_ROOM and w.distance_to(CampusGeometry.tile_center(room,TOP_CELL.x,TOP_CELL.y))<1.5*float(room["tw"])


## Called after the facility has checked its closure and cooldown, before ordinary sleep settlement.
func rest(day: int, tsec: float, in_class: bool, has_top: bool, from: Dictionary) -> bool:
	var key:=str(day)
	if in_class:
		if not class_day.has(key): class_day[key]=_random()<.20
		if not class_day[key]:
			_say("我：我躺下了。隔着几栋楼也听得见上课的声音。我睡不着。")
			return true
	if has_top and not entered.get(key,false) and _random()<(.10 if in_class else .05):
		entered[key]=true
		dream={"day":day,"spin":"","id":"d%d:%d" % [day,roundi(tsec)],"from":from.duplicate(true),"falling":0.0}
		_emit("fact",{"fact":{"kind":"inception","what":"enter"}})
		_say("我：我闭上眼睛。床板往下陷，陷得很深，一直往下。")
		_emit("enter")
		return true
	return false


func ensure_dream(day: int) -> void:
	if dream.is_empty():
		dream={"day":day,"spin":"fall","id":"","from":{"room":"dorm1","x":null,"y":null},"falling":0.0}


func spin(here: bool) -> void:
	if not here or dream.is_empty():
		_say("我：我在桌上转了一下陀螺。它转了一会儿，晃了晃，倒了。")
		return
	if dream["spin"]=="":
		dream["spin"]="stand" if _random()<.5 else "fall"
		_emit("fact",{"fact":{"kind":"inception","what":"spin","spin":dream["spin"]}})
		_emit("save")
	_say("我：我蹲下来转陀螺。它转起来了，一直转，一直转，一点要停的意思都没有。" if dream["spin"]=="stand" else "我：我蹲下来转陀螺。它转了几圈，晃了晃，倒了。")


static func pit(cell: Vector2i) -> bool:
	return cell.y>=0 and cell.y<GRID.size() and cell.x>=0 and cell.x<GRID[cell.y].length() and GRID[cell.y][cell.x]=="p"


static func near_exit(cell: Vector2i) -> bool:
	return absi(cell.x-EXIT.x)+absi(cell.y-EXIT.y)<=1


func exit_door(asked: bool) -> void:
	if dream.is_empty() or dream["falling"]>0: return
	if dream["spin"]=="":
		if asked: _say("我：门把手转不动。……我还没确认过，这里是不是梦。")
	elif dream["spin"]=="fall":
		succeed("exit")
	else:
		_say("我：我推开门。门后面，还是这条走廊。")
		_emit("loop")


func eye_drop() -> float:
	return minf(6,float(dream.get("falling",0))*float(dream.get("falling",0))*4)


func tick(dt: float, cell: Vector2i) -> void:
	if dream.is_empty():
		wake(false)
		return
	if dream["falling"]>0:
		dream["falling"]=float(dream["falling"])+maxf(0,dt)
		if dream["falling"]>=FALL_TIME:
			if dream["spin"]=="stand": succeed("fall")
			else: wake(true)
	elif pit(cell):
		dream["falling"]=.001
		_emit("fact",{"fact":{"kind":"inception","what":"fall","spin":null if dream["spin"]=="" else dream["spin"]}})
		_say("我：脚下一空——")
	elif cell==EXIT:
		exit_door(false)


func succeed(how: String) -> void:
	dream={}
	_emit("fact",{"fact":{"kind":"inception","what":"ending","how":how}})
	_emit("ending",{"id":"inception"})


func wake(fell: bool) -> void:
	var from: Dictionary=dream.get("from",{"room":"dorm1","x":null,"y":null})
	var id:=String(dream.get("id",""))
	var pay: bool=id!="" and not settled.get(id,false)
	dream={}
	if pay: settled[id]=true
	_emit("wake",{"from":from.duplicate(true),"settle":pay,"fell":fell})
