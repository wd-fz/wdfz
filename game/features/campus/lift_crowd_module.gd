class_name LiftCrowdModule
extends FeatureModule
## Original lift-crowd/crowd.js. The elevator owns doors and the boarding roll;
## this module owns eligibility, the six-second decision and its saved progress.
const CHANCE := .01
const MIN_RUN := 60.0
const OPEN := 6.0
const GONE := 1.2
const BREATH := .7
var run := 0.0
var state: Dictionary = {}
var events: Array = []

func module_id() -> StringName:
	return &"campus.lift_crowd"

func reset() -> void:
	run=0.0
	state={}
	events=[]

func capture() -> Dictionary:
	return {"run":run,"state":state.duplicate(true)}

func validate(data: Dictionary) -> String:
	if not SaveSchema.number_in(data.get("run"),0,1e12) or not data.get("state") is Dictionary:
		return "满员事件状态无效"
	var s: Dictionary=data["state"]
	if s.is_empty():
		return ""
	if not s.get("host") in ["teach","lab"] or not SaveSchema.is_integer(s.get("floor"),1,5) or not s.get("phase") in ["full","closing","gone"]:
		return "满员事件地点或阶段无效"
	if not SaveSchema.number_in(s.get("age"),0,1e12) or not SaveSchema.number_in(s.get("t"),-10,OPEN) or not s.get("said") is bool:
		return "满员事件计时无效"
	return ""

func restore(data: Dictionary) -> void:
	run=float(data["run"])
	state=data["state"].duplicate(true)
	if not state.is_empty():
		state["floor"]=int(state["floor"])
	events=[]

func active() -> bool:
	return not state.is_empty() and state["phase"]!="gone"

func eligible(ride: Dictionary, unsafe: bool) -> bool:
	return not ride.is_empty() and not ride.get("rare",false) and run>=MIN_RUN and not unsafe

func board(ride: Dictionary, roll: float) -> void:
	ride["crowd"]=1 if roll<CHANCE else 0

func take_events() -> Array:
	var out:=events
	events=[]
	return out

func _notice(text: String) -> void:
	events.append({"kind":"notice","text":text})

func _fact(phase: String, survived: bool = false) -> void:
	events.append({"kind":"fact","fact":{"kind":"anomaly","phase":phase,"id":"crowd","name":"满员","survived":survived,"lethal":false,"public":false}})

## true prevents this departure; keep pending destination until the event ends.
func depart(ride: Dictionary, lift: Dictionary, host: String) -> bool:
	if not state.is_empty() and state["host"]==host:
		if state["phase"]=="closing":
			state={}
			ride["crowd"]=0
			events.append({"kind":"kill","text":"电梯里一直很挤。","source":"crowd","fx":"crowd"})
			return true
		return state["phase"]!="gone"
	if int(ride.get("crowd",0))!=1:
		return false
	ride["crowd"]=2
	state={"phase":"full","host":host,"floor":int(ride["origin"]),"t":OPEN,"age":0.0,"said":false}
	lift["dir"]=1
	lift["hold"]=OPEN+1
	_fact("start")
	_notice("〔超载蜂鸣〕显示屏跳成了「满员」。门又开了。")
	return true

## Called after the elevator's door/boarding step, in the original tick order.
func tick(dt: float, lifts: Dictionary, ride: Dictionary, in_cabin: bool, scene: String) -> void:
	if dt<=0:
		return
	run+=dt
	if state.is_empty():
		return
	state["age"]=float(state["age"])+dt
	var lift: Dictionary=lifts[state["host"]]
	if state["phase"]=="gone":
		state["t"]=float(state["t"])-dt
		if in_cabin:
			state={}
			return
		if float(lift["door"])>0 and int(lift["dir"])==0:
			lift["dir"]=-1
			lift["hold"]=0.0
		if (float(state["t"])<=0 and float(lift["door"])<=.001) or float(state["t"])<=-4:
			lift["phase"]="waiting"
			lift["target"]=5 if int(state["floor"])<5 else 1
			lift["remaining"]=3.0+absi(int(lift["target"])-int(state["floor"]))* .7
			lift["door"]=0.0
			lift["dir"]=0
			lift["hold"]=0.0
			if scene==String(state["host"])+str(int(state["floor"])):
				_notice("〔电梯〕门合上，它自己往上走了。楼层灯一格一格跳，在一个没有的楼层停了一下。")
			state={}
		return
	if not in_cabin and (ride.is_empty() or ride.get("host")!=state["host"] or ride.get("phase")!="cabin"):
		state["phase"]="gone"
		state["t"]=GONE
		if float(lift["door"])>0:
			lift["dir"]=-1
			lift["hold"]=0.0
		_fact("end",true)
		return
	if not bool(state["said"]) and float(state["age"])>=BREATH:
		state["said"]=true
		_notice("〔身后 · 很近〕很多人在呼吸。")
	if state["phase"]=="full":
		state["t"]=float(state["t"])-dt
		if int(lift["dir"])<0:
			lift["dir"]=1
		lift["hold"]=maxf(float(lift["hold"]),.5)
		if float(state["t"])<=0:
			state["phase"]="closing"
			lift["dir"]=-1
			lift["hold"]=0.0
