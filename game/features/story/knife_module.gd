class_name KnifeModule
extends FeatureModule
## modules/knife/knife.js: one real simulation second, bag equip followed by bag use.
const ROOM := "gear1"
const CELL := Vector2i(6,1)
const WINDOW := 1.0
var took := false
var held := false
var done := false
var cap: Dictionary = {}
var events: Array = []


func module_id() -> StringName:
	return &"story.knife"


func reset() -> void:
	took=false
	held=false
	done=false
	cap={}
	events=[]


func capture() -> Dictionary:
	return {"took":took,"held":held,"done":done,"cap":cap.duplicate(true)}


func validate(data: Dictionary) -> String:
	for key: String in ["took","held","done"]:
		if not data.get(key) is bool: return "小刀状态无效"
	if not data.get("cap") is Dictionary: return "抓捕窗口无效"
	var c: Dictionary=data["cap"]
	if c.is_empty(): return ""
	if not SaveSchema.number_in(c.get("t"),0,WINDOW+1e-9) or not c.get("msg") is String:
		return "抓捕窗口时间无效"
	if c.get("equip")!=null and not SaveSchema.number_in(c["equip"],0,float(c["t"])):
		return "小刀拿出顺序无效"
	return ""


func restore(data: Dictionary) -> void:
	took=data["took"]
	held=data["held"]
	done=data["done"]
	cap=data["cap"].duplicate(true)
	events=[]


func near(scene: String, room: Dictionary, position: Vector2) -> bool:
	return not took and scene==ROOM and position.distance_to(CampusGeometry.tile_center(room,CELL.x,CELL.y))<1.5*float(room["tw"])


func captured() -> bool:
	return not cap.is_empty()


func catch_player(has_knife: bool, message: String) -> bool:
	if captured(): return true
	if done or not has_knife or held: return false
	cap={"t":0.0,"msg":message,"equip":null,"seq":0}
	events.append({"kind":"fact","fact":{"kind":"knife","what":"caught"}})
	return true


func tick(dt: float, dead: bool) -> void:
	if not captured() or dt<=0 or dead: return
	cap["t"]=float(cap["t"])+dt
	if float(cap["t"])>WINDOW+1e-9:
		var message: String=cap["msg"]
		cap={}
		events.append({"kind":"kill","text":message,"fx":"grip","source":"patrol"})


func use(has_knife: bool, source: String = "bag") -> bool:
	if not has_knife: return false
	if captured():
		if not held:
			held=true
			if source!="hot" and cap["equip"]==null: cap["equip"]=cap["t"]
		elif source!="hot" and cap["equip"]!=null and float(cap["t"])<=WINDOW+1e-9:
			cap={}
			done=true
			held=false
			events.append({"kind":"remove","id":"small_knife"})
			events.append({"kind":"fact","fact":{"kind":"knife","what":"used"}})
			events.append({"kind":"ending","id":"knife"})
		return true
	held=not held
	events.append({"kind":"notice","text":"我：我把小刀拿在手上。" if held else "我：我比划了一下，又把它收了回去。"})
	return true


func take_events() -> Array:
	var out:=events
	events=[]
	return out
