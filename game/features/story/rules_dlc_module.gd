class_name RulesDlcModule
extends FeatureModule
## The bundled campus-rules.js 1.1.0, with independent per-run state and local records.
## Timed scene cues and choices are transient, as in the original Lifecycle.scope('scene').
const VERSION := "1.1.0"
const VARIANT := "rules@"+VERSION
const OLD_KEYS := {"knock":"rules.e.knock","reply":"rules.h.reply","sources":"rules.e.sources","ticket":"rules.n.ticket"}
const PAPER_TEXT := "两次拍窗以后，纸从哪里来就回哪里去。返程不能碰墙。\n若字看不清，贴近玻璃再念一次。"
var content: Dictionary
var rooms: Dictionary
var state: Dictionary
var records: Dictionary = {}
var events: Array = []
var _windows: WindowGazeModule
var _spots: Dictionary = {}
var _pending: Dictionary = {}
var _knock_elapsed := -1.0
var _c: Dictionary = {}

func _init(data: Dictionary = {}, room_data: Dictionary = {}) -> void:
	content=data
	rooms=room_data
	_windows=WindowGazeModule.new(rooms)
	reset()

func module_id() -> StringName: return &"dlc.campus_rules"
func reset() -> void:
	state={"on":0,"v":2,"bundle":"A","read":{},"marks":{},"knock":{},"ticket":{},"name":{},"nameAt":null,"tainted":0,"run":{},"knockT":0.0,"nameT":0.0}
	events=[]
	cancel_scene()
func capture() -> Dictionary: return state.duplicate(true)
func active() -> bool: return bool(state.get("on",false))

func validate(data: Dictionary) -> String:
	if not content.get("bundles",{}).has(data.get("bundle","A")): return "规则怪谈的规则组无效"
	for key: String in ["on","tainted"]:
		if data.has(key) and not (data[key] is bool or SaveSchema.number_in(data[key],0,1)): return "规则怪谈标记无效"
	for key: String in ["read","marks","knock","ticket","name","run"]:
		if not (data.get(key,{}) is Dictionary): return "规则怪谈记录无效"
	for key: String in ["read","knock","ticket","name","run"]:
		for value: Variant in data.get(key,{}).values():
			if not (value is bool or SaveSchema.number_in(value,0,1)): return "规则怪谈记录标记无效"
	for key: String in ["knockT","nameT"]:
		if not SaveSchema.number_in(data.get(key,0),0,SaveSchema.MAX_SECONDS): return "规则怪谈计时无效"
	for id: String in data.get("read",{}):
		if item(id).is_empty(): return "规则怪谈载体无效"
	for id: String in data.get("marks",{}):
		if item(id).is_empty() or not data["marks"][id] in ["可信","存疑"]: return "规则怪谈批注无效"
	return ""

func restore(data: Dictionary) -> void:
	reset()
	for key: String in state:
		if data.has(key): state[key]=data[key].duplicate(true) if data[key] is Dictionary else data[key]

func start(enabled: bool, seed_text: String) -> void:
	reset()
	state["on"]=1 if enabled else 0
	if enabled: state["bundle"]=pick_bundle(seed_text)

static func hash_seed(value: String) -> int:
	# JavaScript charCodeAt hashes UTF-16 code units, including surrogate pairs.
	var h:=2166136261
	for i in value.length():
		var code:=value.unicode_at(i)
		var units: Array=[code] if code<0x10000 else [0xd800+((code-0x10000)>>10),0xdc00+((code-0x10000)&1023)]
		for unit: int in units: h=((h^unit)*16777619)&0xffffffff
	return h

func item(id: String) -> Dictionary:
	for entry: Dictionary in content.get("rules",[])+content.get("evidence",[]):
		if entry["id"]==id: return entry
	return {}

func valid_bundle(ids: Array) -> bool:
	var counts:={"true":0,"false":0,"half":0}
	if not ids.has("R03") or not ids.has("R05"): return false
	for id: String in ids:
		var r:=item(id)
		if r.is_empty() or not r.has("t"): return false
		if id!="R01": counts[r["t"]]+=1
		if r["t"]!="true":
			var refuted:=false
			for proof: String in content["refutations"].get(id,[]):
				var e:=item(proof)
				if proof.begins_with("@") or (not e.is_empty() and (ids.has(e.get("rule","")) if proof.begins_with("E") else ids.has(proof) and e.get("t")=="true")): refuted=true
			if not refuted: return false
	return counts["true"]>=3 and counts["false"]>=2 and counts["half"]>=2

func pick_bundle(seed_text: String) -> String:
	var valid: Array=[]
	for key: String in content.get("bundles",{}):
		if valid_bundle(content["bundles"][key]): valid.append(key)
	return "A" if valid.is_empty() else valid[hash_seed(seed_text)%valid.size()]

func includes(id: String) -> bool:
	var r:=item(id)
	return content.get("bundles",{}).get(state["bundle"],[]).has(r.get("rule",id))

func spots() -> Array:
	var bundle:=String(state["bundle"])
	if _spots.has(bundle): return _spots[bundle]
	var out:=[]
	for entry: Dictionary in content.get("rules",[])+content.get("evidence",[]):
		if not includes(entry["id"]) or not entry.has("where"): continue
		var where: Dictionary=entry["where"]
		var room: Dictionary=rooms.get(where["room"],{})
		if room.is_empty(): continue
		var pos: Dictionary={}
		if where.has("win"):
			var windows:=_windows.windows(where["room"])
			if not windows.is_empty():
				var window: Dictionary=windows[mini(int(where["win"]),windows.size()-1)]
				pos={"room":where["room"],"x":window["p"].x,"y":window["p"].y+window["nz"]*room["th"]*.45,"h":1.5}
		else:
			var n:=0
			for row in int(room["rows"]):
				for col in int(room["cols"]):
					if String(room["grid"][row]).substr(col,1)!=where["ch"]: continue
					if n==int(where["k"]): pos={"room":where["room"],"x":room["ox"]+(col+.5)*room["tw"],"y":room["oy"]+(row+.5)*room["th"],"h":.03 if where["ch"]=="." else (.62 if where["ch"]=="b" else .8)}
					n+=1
		if not pos.is_empty(): out.append({"item":entry,"p":pos})
	_spots[bundle]=out
	return out

func near(scene: String, position: Vector2) -> Dictionary:
	if not active() or not rooms.has(scene): return {}
	var best: Dictionary={}
	var distance:=1.35
	for spot: Dictionary in spots():
		if spot["p"]["room"]!=scene: continue
		var d:=position.distance_to(Vector2(spot["p"]["x"],spot["p"]["y"]))/float(rooms[scene]["tw"])
		if d<distance:
			distance=d
			best=spot
	return best

func set_context(ctx: Dictionary) -> void:
	_c=ctx
	if active() and not bool(ctx.get("trusted",true)): state["tainted"]=1

func _emit(kind: String, values: Dictionary = {}) -> void:
	var e:=values.duplicate(true)
	e["kind"]=kind
	events.append(e)
func take_events() -> Array:
	var result:=events
	events=[]
	return result

func load_records(raw: Dictionary) -> void:
	records={}
	for entry: Dictionary in content.get("achievements",[]):
		var id:=String(entry["id"])
		if raw.get(id) is Dictionary: records[id]=raw[id].duplicate(true)
	for old: String in OLD_KEYS:
		if raw.has(old) and not records.has(OLD_KEYS[old]): records[OLD_KEYS[old]]={"at":raw[old],"ver":"1.0.0"}

func _grant(id: String) -> void:
	if not active() or bool(state["tainted"]) or records.has(id): return
	records[id]={"at":_c.get("now_ms",0),"ver":VERSION,"bundle":state["bundle"]}
	_emit("grant",{"id":id})

func read(id: String) -> void:
	if not active() or not includes(id): return
	var x:=item(id)
	if x.is_empty(): return
	state["read"][id]=1
	var evidence:=x.has("rule")
	_emit("record",{"id":"rule_"+id,"text":("" if evidence else String(x["carrier"])+"：")+"「"+String(x["text"]).replace("\n","")+"」","type":"线索" if evidence else "规则"})
	_emit("fact",{"fact":{"kind":"ruleObserved","id":id,"evidence":evidence}})
	var count:=0
	var proof:=false
	for key: String in state["read"]:
		if key.begins_with("R"): count+=1
		if key.begins_with("E"): proof=true
	if count>=5 and proof: _grant("rules.e.sources")
	if evidence: _emit("notice",{"text":"我："+String(x["text"])})
	else:
		_pending={"type":"read","id":id}
		_emit("choice",{"text":String(x["carrier"])+"上写着：\n「"+String(x["text"])+"」"+("\n（我标过：%s）" % state["marks"][id] if state["marks"].has(id) else ""),"labels":["记为可信","记为存疑","先不标"]})

func paper_text(kind: String) -> Variant:
	if not active() or kind!="danger": return null
	state["read"]["R01"]=1
	return PAPER_TEXT

func tick(dt: float) -> void:
	if not active() or dt<=0 or bool(_c.get("dead",false)) or not bool(_c.get("playing",true)) or bool(_c.get("choice",false)): return
	var scene:=String(_c.get("scene","out"))
	var room: Dictionary=rooms.get(scene,{})
	var day:=str(int(_c.get("day",1)))
	if room.get("host") in ["dormN","dormS"] and float(_c.get("time",0))>=1340:
		var night:=str(floori((float(_c.get("clock",0))-1000)/1440))
		state["knockT"]+=dt
		if not state["knock"].has(night) and state["knockT"]>=8 and includes("R05"):
			state["knock"][night]=1
			_knock_elapsed=0
			_emit("notice",{"text":"（门外敲了一下。）"})
	else: state["knockT"]=0
	if scene=="canteen1" and bool(_c.get("meal",false)) and not state["ticket"].has(day) and includes("R06"):
		state["ticket"][day]=1
		_offer("ticket")
	if room.get("host")=="teach" and _c.get("need")=="教室" and not state["name"].has(day) and includes("R10"):
		state["nameT"]+=dt
		if state["nameT"]>=25:
			state["name"][day]=1
			state["nameT"]=0
			_offer("name")

func advance_cues(dt: float) -> void:
	if _knock_elapsed<0: return
	var prev:=_knock_elapsed
	_knock_elapsed+=dt
	if prev<1.8 and _knock_elapsed>=1.8: _emit("notice",{"text":"（又敲了一下。）"})
	if _knock_elapsed>=3.6:
		_knock_elapsed=-1
		_emit("notice",{"text":"（第三下。）"})
		_offer("knock")

func cancel_scene() -> void:
	_knock_elapsed=-1
	_pending={}

func _offer(type: String) -> void:
	_pending={"type":type}
	var prompts:={"knock":["门外有人问：「在吗？查寝。」",["应一声「在」","不出声"]],"ticket":["托盘上多了一张餐券。没人看着这边。",["原样放回托盘","收下"]],"name":["有人在点名。点到的是我的名字——但不是老师的声音。",["答应","不答应"]]}
	_emit("choice",{"text":prompts[type][0],"labels":prompts[type][1]})

func choose(index: int) -> void:
	var pending:=_pending
	_pending={}
	if pending.is_empty() or index<0: return
	var type:=String(pending["type"])
	if type=="read":
		if index<2: state["marks"][pending["id"]]=["可信","存疑"][index]
		return
	if index>1: return
	var ok:=index==0 if type=="ticket" else index==1
	if ok and type in ["knock","ticket"]: _grant("rules.e.knock" if type=="knock" else "rules.n.ticket")
	if not ok and type!="knock": _emit("san",{"amount":-5})
	_emit("fact",{"fact":{"kind":"ruleResolved","id":{"knock":"R05","ticket":"R06","name":"R10"}[type],"ok":ok}})
	if not ok and type=="knock":
		_emit("kill",{"text":"门外的人用我的声音，又说了一遍「在」。","fx":"rules_knock","source":"rules_knock"})
		return
	var lines:={"knock":["","我：我没有出声。敲门声停了。过了很久，走廊里也没有脚步声。"],"ticket":["我：我把餐券放回去。窗口里的人看了一眼，把它收走了。","我：我把餐券塞进口袋。口袋里一下子沉了，像装了一块湿的东西。"],"name":["我：「到。」整间教室的人一起回头看我。","我：我没有出声。那个声音又念了一遍，然后念了下一个名字。"]}
	_emit("notice",{"text":lines[type][index]})

func fact(f: Dictionary) -> void:
	if not active(): return
	var run: Dictionary=state["run"]
	match String(f.get("kind","")):
		"paper":
			if f.get("what")=="returned":
				run["paper"]=1
				_grant("rules.e.paper_return")
		"gaze":
			if f.get("what")=="contact": run["gaze"]=1
			elif f.get("what")=="escape" and ["R03","E03","R02"].all(func(id: String) -> bool: return bool(state["read"].get(id,false))): _grant("rules.e.clauses")
		"death":
			if f.get("source")=="rules_knock": _grant("rules.h.reply")
		"ending":
			if not bool(f.get("legit",false)) or bool(f.get("fake",false)) or not bool(run.get("gaze",false)) or not bool(run.get("paper",false)): return
			var kinds: Dictionary={}
			for id: String in state["read"]:
				var r:=item(id)
				if r.has("t"): kinds[r["t"]]=true
			if kinds.has("true") and kinds.has("false") and kinds.has("half"): _grant("rules.p.survive")
