extends "res://tests/support/test_suite.gd"

func fixture() -> Dictionary:
	var raw:=FileAccess.get_file_as_bytes("res://tests/fixtures/rules_dlc-reference.json.gz")
	return JSON.parse_string(raw.decompress_dynamic(32*1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8())
func fresh() -> RulesDlcModule:
	return RulesDlcModule.new(CampusData.rules_dlc(),CampusData.rooms())
func ctx(scene: String, time: float = 690, more: Dictionary = {}) -> Dictionary:
	var meal:=false
	for w: Array in CampusData.campus()["meals"]:
		if time>=w[0] and time<w[1]: meal=true
	var c:={"scene":scene,"time":time,"clock":time,"day":1,"need":SchoolClock.period_at(time)[3],"meal":meal,"choice":false,"dead":false,"playing":true,"trusted":true,"now_ms":123456}
	c.merge(more,true)
	return c
func original_events(events: Array) -> Array:
	var out:=[]
	for e: Dictionary in events:
		if e["kind"]=="grant": continue
		if e["kind"]=="fact":
			var f: Dictionary=e["fact"].duplicate(true)
			f["fact"]=f["kind"]
			f["kind"]="fact"
			out.append(f)
		elif e["kind"]=="kill": out.append({"kind":"kill","msg":e["text"],"fx":e["fx"],"source":e["source"]})
		else: out.append(e)
	return out

func test_reference() -> void:
	var reference:=fixture()
	var rules:=fresh()
	for sample: Dictionary in reference["bundles"]:
		check(rules.valid_bundle(rules.content["bundles"][sample["id"]])==sample["valid"],"original validated rule bundle "+String(sample["id"]))
	check(not rules.valid_bundle(["R03","R05"]) and not rules.valid_bundle(["unknown"]),"incomplete and unknown bundles cannot be picked")
	for sample: Array in reference["seeds"]: check(rules.pick_bundle(sample[0])==sample[1],"original UTF-16 seed bundle "+String(sample[0]))
	for sample: Dictionary in reference["spots"]:
		rules.state["bundle"]=sample["bundle"]
		check(same_json(rules.spots(),sample["spots"]),"all original carrier locations for bundle "+String(sample["bundle"]))
	for sample: Dictionary in reference["ticks"]:
		rules.start(true,"0")
		rules.state["bundle"]=sample["bundle"]
		rules.set_context(ctx(sample["room"],sample["time"]))
		rules.tick(sample["dt"])
		var state:=rules.capture()
		for timer: String in ["knockT","nameT"]:
			if not sample["state"].has(timer): state.erase(timer)
		check(same_json(state,sample["state"]) and same_json(original_events(rules.take_events()),sample["events"]),"original event eligibility %s/%s/%.2f/%.2f" % [sample["bundle"],sample["room"],sample["time"],sample["dt"]])
	for sample: Dictionary in reference["cases"]:
		rules.start(true,"0")
		rules.state["bundle"]="A"
		rules.load_records({})
		var type:=String(sample["type"])
		rules.set_context(ctx("dorm1",1340) if type=="knock" else (ctx("canteen1",760) if type=="ticket" else ctx("teach1",690)))
		rules.tick(8 if type=="knock" else (25 if type=="borrowed" else .1))
		if type=="knock":
			rules.advance_cues(1.8)
			rules.advance_cues(1.8)
		rules.choose(sample["selection"])
		var got:=original_events(rules.take_events())
		check(same_json(got,sample["events"]) and same_json(rules.records.keys(),sample["granted"]),"original choice outcome %s/%d: %s" % [type,sample["selection"],got])

func test_state_boundaries() -> void:
	var rules:=fresh()
	rules.set_context(ctx("dorm1",1340))
	rules.tick(100)
	check(rules.take_events().is_empty() and rules.paper_text("danger")==null,"disabled DLC has no events or paper replacement")
	rules.start(true,"0")
	rules.state["bundle"]="A"
	rules.set_context(ctx("dorm1",1340,{"choice":true}))
	rules.tick(8)
	check(rules.state["knock"].is_empty(),"modal choices suspend slice accumulation")
	rules.set_context(ctx("dorm1",1340))
	rules.tick(8)
	rules.take_events()
	rules.cancel_scene()
	rules.advance_cues(20)
	rules.tick(100)
	check(rules.take_events().is_empty() and rules.state["knock"].size()==1,"leaving cancels delayed knocks without replaying the same night")
	rules.set_context(ctx("teach1",690))
	rules.tick(14)
	var before:=rules.capture()
	var loaded:=fresh()
	check(loaded.validate(before).is_empty(),"native rules snapshot is valid")
	loaded.restore(before)
	check(same_json(loaded.capture(),before),"native rules snapshot retains counters and processed days")
	loaded.set_context(ctx("admin1",690))
	loaded.tick(100)
	loaded.set_context(ctx("teach1",690))
	loaded.tick(11)
	check(loaded.state["name"].has("1"),"borrowed-name accumulation survives leaving and loading")
	loaded.choose(1)
	loaded.take_events()
	check(loaded.paper_text("danger")==RulesDlcModule.PAPER_TEXT and loaded.state["read"].has("R01"),"dangerous paper carries R01 and marks it observed at generation")
	loaded.set_context(ctx("teach1"))
	for id: String in ["R02","R03","R04","R05","E03"]:
		loaded.read(id)
		loaded.choose(1)
	check(loaded.records.has("rules.e.sources") and loaded.state["marks"]["R03"]=="存疑","five rule carriers and one evidence grant only the DLC record")
	loaded.fact({"kind":"gaze","what":"escape"})
	loaded.fact({"kind":"paper","what":"returned"})
	loaded.fact({"kind":"gaze","what":"contact"})
	loaded.fact({"kind":"ending","id":"face","legit":true,"fake":false})
	check(loaded.records.has("rules.e.clauses") and loaded.records.has("rules.e.paper_return") and loaded.records.has("rules.p.survive"),"DLC records combine original clauses, paper and genuine clear")
	loaded.set_context(ctx("teach1",690,{"trusted":false}))
	loaded.set_context(ctx("teach1"))
	loaded.fact({"kind":"death","source":"rules_knock"})
	check(loaded.state["tainted"]==1 and not loaded.records.has("rules.h.reply"),"taint is sticky even after debug closes")
	loaded.load_records({"reply":123,"ticket":456})
	check(loaded.records.size()==2 and loaded.records["rules.h.reply"]["ver"]=="1.0.0","old DLC record keys migrate without bonuses or base unlocks")
	var bad:=before.duplicate(true)
	bad["bundle"]="Z"
	check(not loaded.validate(bad).is_empty(),"unknown bundle rejected")
	bad=before.duplicate(true)
	bad["nameT"]=-1
	check(not loaded.validate(bad).is_empty(),"negative timer rejected")

func test_app() -> void:
	var app: GameApp=APP.instantiate()
	app.saves=SaveStore.new(_test_path.get_base_dir()+"/rules-dlc/slot.json")
	app.settings=GameSettings.new(_test_path.get_base_dir()+"/rules-settings.json")
	root.add_child(app)
	await _frames(2)
	app.wuda_roll=func() -> float: return 1
	app.settings.rules_armed=true
	app.start_new_game("hard","none")
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app.rules_dlc_flow.set_process(false)
	var flow:=app.rules_dlc_flow
	var rules:=flow.module()
	rules.state["bundle"]="A"
	flow.menu()
	app._choice_made(0)
	check(not app.settings.rules_armed and rules.active(),"DLC menu toggle leaves the running mode unchanged")
	app._choice_made(-1)
	check(rules.active() and app.paper().text_override.call("danger")==RulesDlcModule.PAPER_TEXT,"enabled new run installs rule mode and paper hook")
	app.achievements().load_profile({})
	app.fact({"kind":"wake"})
	check(app.achievements().unlocked.is_empty(),"DLC run does not unlock base achievements")
	app.travel("canteen1",app.campus().default_spawn("canteen1"),false)
	app.school().tsec=760
	flow.step(.1)
	check(app.ui.choice_open() and not app.player.enabled,"meal slice opens real choice panel")
	app._choice_made(0)
	check(app.player.enabled and app._read_side("rules_records.json").has("rules.n.ticket"),"choice returns control and writes independent records")
	var carrier: Dictionary=rules.spots().filter(func(s: Dictionary) -> bool: return s["item"]["id"]=="R04")[0]
	var point:=CampusGeometry.to_scene(CampusData.layout("canteen1"),Vector2(carrier["p"]["x"],carrier["p"]["y"]))
	app.player.position=Vector3(point.x,0,point.y)
	flow.show_props()
	check(flow._props.get_child_count()==2 and flow.hint()==carrier["item"]["carrier"],"rule carriers are present and reachable by the original proximity rule")
	check(flow.interact() and app.ui.choice_open(),"reading uses the real carrier interaction")
	app._choice_made(1)
	check(rules.state["marks"]["R04"]=="存疑" and app.investigation().entries["rule_R04"]["kind"]=="规则","mark and original wording enter the handbook")
	app.travel("dorm1",app.campus().default_spawn("dorm1"),false)
	app.school().tsec=1340
	flow.step(8)
	flow._process(1.8)
	app.travel("lab1",app.campus().default_spawn("lab1"),false)
	flow._process(10)
	check(not app.ui.choice_open(),"scene change cancels pending knock callbacks")
	app.save_game()
	app.settings.rules_armed=false
	app.load_game()
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	check(flow.module().active() and flow.module().state["bundle"]=="A" and flow.module().state["ticket"].has("1"),"loading follows saved DLC mode and event progress despite menu setting")
	var result:=app._score_ending("face","《白名单》")
	check(result["rated"] and result["variant"]==RulesDlcModule.VARIANT and not RunRecords.is_base(result),"trusted rule-mode clears have separate variant, never base rankings")
	app._toggle_debug()
	app.fact({"kind":"death","source":"rules_knock"})
	check(not flow.module().records.has("rules.h.reply") and flow.module().state["tainted"]==1,"debug blocks mode achievements as well as base achievements")
	app.debug_panel.dismiss()
	app.travel("dorm1",app.campus().default_spawn("dorm1"),false)
	flow.module().state["knock"]={}
	app.school().tsec=1340
	flow.step(8)
	app.kill("test","neck","test")
	app.debug_flow.revive()
	flow._process(10)
	check(not app.ui.choice_open() and flow.module()._knock_elapsed<0,"death and developer revival cannot resume a stale scene callback")
	for source: Dictionary in fixture()["saves"]:
		var error:=app.import_legacy_save(JSON.stringify(source["save"]))
		app.set_physics_process(false)
		app.player.set_physics_process(false)
		check(error=="" and flow.module().active() and flow.module().state["bundle"]==source["bundle"] and flow.module().state["nameT"]==14,"original DLC save restores bundle and unfinished name counter: "+error)
	var disabled: Dictionary=fixture()["saves"][0]["save"].duplicate(true)
	disabled["rt"]["rulesMode"]={"v":0,"ver":"unsupported"}
	disabled["mods"]["mod:campus-rules"]["on"]=0
	check(app.import_legacy_save(JSON.stringify(disabled))=="" and not flow.module().active(),"inactive legacy mode metadata never enables or rejects the base game")
	var current:=app.session
	disabled["rt"]["rulesMode"]["v"]=1
	check(app.import_legacy_save(JSON.stringify(disabled))!="" and app.session==current,"unknown active DLC version rejects atomically")
	app._stand_up()
	app.player.set_pitch(0)
	var cg:=DeathCG.new()
	app.add_child(cg)
	cg.begin("rules_knock",app.player,app._campus_world(),app.ui,7,false)
	for frame: Dictionary in fixture()["frames"]:
		cg.update(frame["t"])
		check(absf(app.player.camera.rotation.x-frame["pitch"])<.00001 and absf(cg._lift-frame["lift"])<.00001 and absf(cg.veil_mesh.material_override.albedo_color.a-frame["shade"])<.00001 and cg.d["feet"][0].visible==frame["feet"][0] and absf(cg.d["ink"].position.x-frame["ink"]["x"])<.00001 and absf(cg.d["ink"].scale.x-frame["ink"]["scale"])<.00001,"original rules death frame %.2f" % frame["t"])
	cg.finish()
	cg.queue_free()
	app.return_to_menu()
	app.queue_free()
	await _frames(3)
	CampusData.clear_caches()
