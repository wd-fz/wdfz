class_name RulesDlcFlow
extends Node
## Built-in DLC boundary: menus, scene-lifetime callbacks, profile I/O and paper props.
var app: GameApp
var _generation:=0
var _choice:=-1
var _props: RulesDlcProps
var _world_id:=0

func _ready() -> void: process_mode=Node.PROCESS_MODE_ALWAYS
func module() -> RulesDlcModule:
	return app.session.modules.get_module(&"dlc.campus_rules") as RulesDlcModule if app.session!=null else null
func context() -> Dictionary:
	var meal:=false
	for window: Array in CampusData.campus().get("meals",[]):
		if app.school().tsec>=window[0] and app.school().tsec<window[1]: meal=true
	return {"scene":app.session.world_id,"day":app.school().day,"time":app.school().tsec,"clock":SchoolClock.continuous(app.school().day,app.school().tsec),
		"meal":meal,"need":SchoolClock.period_at(app.school().tsec)[3],"dead":app._dead(),"playing":app.session.running,
		"choice":app.ui.choice_open(),"trusted":app.runscore().trusted,"now_ms":int(Time.get_unix_time_from_system()*1000)}

func install() -> void:
	var rules:=module()
	var raw: Variant=app._read_side("rules_records.json")
	rules.load_records(raw if raw is Dictionary else {})
	rules.set_context(context())
	app.paper().text_override=rules.paper_text
	show_props()

func cancel() -> void:
	_generation+=1
	if _choice==app._choice_count:
		app._choice_count+=1
		app._choice_handler=Callable()
		app.ui.hide_choice()
		if app.session!=null and not app._dead(): app.player.enabled=not app.get_tree().paused
	_choice=-1
	if module()!=null: module().cancel_scene()
	if is_instance_valid(_props):
		_props.hide()
		_props.queue_free()
	_props=null
	_world_id=0

func _process(dt: float) -> void:
	if module()==null or not module().active() or not app.session.running or app._dead(): return
	module().set_context(context())
	module().advance_cues(dt)
	flush()
	show_props()

func step(dt: float) -> void:
	if module()==null: return
	module().set_context(context())
	module().tick(dt)
	flush()

func fact(f: Dictionary) -> void:
	if module()==null: return
	module().set_context(context())
	module().fact(f)
	flush()

func near() -> Dictionary:
	if module()==null or not module().active(): return {}
	var room: Variant=app.campus().room(app.session.world_id)
	return module().near(app.session.world_id,CampusGeometry.to_world(room,app.player.position.x,app.player.position.z))

func hint() -> String:
	var spot:=near()
	return "" if spot.is_empty() else ("仔细看看" if spot["item"].has("rule") else String(spot["item"]["carrier"]))

func interact() -> bool:
	var spot:=near()
	if spot.is_empty(): return false
	module().set_context(context())
	module().read(spot["item"]["id"])
	flush()
	return true

func flush() -> void:
	var rules:=module()
	if rules==null: return
	for e: Dictionary in rules.take_events():
		match e["kind"]:
			"notice": app.ui.show_notice(e["text"])
			"record": app.investigation().record(e["id"],e["text"],e["type"],app._location_name())
			"fact": app.fact(e["fact"])
			"san": app.school().change_san(float(e["amount"]),0)
			"grant":
				app._write_side("rules_records.json",rules.records)
				for entry: Dictionary in rules.content["achievements"]:
					if entry["id"]==e["id"]: app.ui.show_notice("【规则怪谈】记录："+String(entry["name"]))
			"kill": app.kill(e["text"],e["fx"],e["source"])
			"choice":
				app._choice_count+=1
				_choice=app._choice_count
				var mine:=_choice
				var scene_generation:=_generation
				app._choice_handler=func(index: int) -> void:
					if scene_generation!=_generation or mine!=app._choice_count or rules!=module(): return
					_choice=-1
					rules.set_context(context())
					rules.choose(index)
					flush()
				app.player.enabled=false
				app.player.clear_input()
				app.ui.clear_touch()
				Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
				app.ui.show_choice(e["text"],e["labels"])

func show_props() -> void:
	if module()==null or not module().active(): return
	var world:=app._campus_world()
	if world==null: return
	if _world_id==world.get_instance_id() and is_instance_valid(_props): return
	if is_instance_valid(_props): _props.queue_free()
	_props=RulesDlcProps.new()
	world.add_child(_props)
	_props.build(module().spots(),app.session.world_id,app.campus().room(app.session.world_id))
	_world_id=world.get_instance_id()

func menu() -> void:
	app._choice_count+=1
	var mine:=app._choice_count
	app._choice_handler=func(index: int) -> void:
		if mine!=app._choice_count: return
		match index:
			0:
				app.settings.rules_armed=not app.settings.rules_armed
				app.settings.save_file()
				menu()
			1: show_records()
			2:
				var rows:=[]
				var session:=app._make_session()
				for id: String in session.modules.capture(): rows.append({"text":id,"on":true,"memo":""})
				app.ui.show_list("内置模块",rows)
	var current:="本局跟随存档。" if module()==null or not app.session.running else ("本局：规则怪谈 · 规则组 "+String(module().state["bundle"]) if module().active() else "本局：本体规则。")
	app.ui.show_choice("DLC 与模块\n规则怪谈 v"+RulesDlcModule.VERSION+"：校园里会出现相互矛盾的文字，部分会影响你的行动。\n开关只影响之后的新局。"+current,
		[("关闭" if app.settings.rules_armed else "启用")+"规则怪谈（新局）","规则怪谈记录","查看内置模块"])

func show_records() -> void:
	app.archive_flow.open("规则怪谈")
