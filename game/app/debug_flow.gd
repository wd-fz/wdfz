class_name DebugFlow
extends Node
## dev.js boundary: transient tools, never a saved game module. UI only sends commands.
const POI := [["北门",514,115],["西小门",214,624],["南门",386,1276],["大操场",344,350],["花园雕塑",535,1020],["车库入口",485,163],["宿舍区",420,1160],["食堂西门",530,1160],["教学楼前",561,995],["东干道",704,600],["东围墙",800,700],["垃圾房",768,1134]]
var app: GameApp
var fast := false
var god := false
var instant_search := false
var frozen := false
var preview: DeathCG
var preview_camera: Camera3D
var history: Array[String] = []
var _refresh := 0.0
var _death_view: Dictionary = {}
var telemetry:=DebugTelemetry.new()
var trace:=DebugTrace.new()
var probe: DebugWorldProbe
var collision_view := false
var preview_paused := false
var preview_rate := 1.0
var bookmarks: Array[Dictionary] = []
var _bookmark_sequence := 0
var _bookmark_generation := 0
var _inspection: Dictionary = {}
var _stepping := false
var _last_frame_us := 0
var _session_sequence := 0

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	probe=DebugWorldProbe.new()
	add_child(probe)

func blocks_simulation() -> bool:
	return (frozen and not _stepping) or is_instance_valid(preview)

func observe(fact: Dictionary) -> void:
	if DebugPanel.enabled(): trace.add("fact",String(fact.get("kind","事实")),fact,_context())

func _context() -> Dictionary:
	if app.session==null: return {}
	return {"session":_session_sequence,"day":app.school().day,"time":SchoolClock.fmt_clock(app.school().tsec),"room":app.session.world_id,"active":snappedf(app.session.clock.active_seconds,.01)}

func alive() -> bool:
	return app.session!=null and not app.story().over() and not app.opening_busy()

func report(message: String) -> String:
	history.append(message)
	if history.size()>20: history.pop_front()
	if is_instance_valid(app.debug_panel): app.debug_panel.say(message)
	refresh()
	return message

func dirty() -> void:
	if app.runscore()!=null: app.runscore().trusted=false
	app.speedrun.invalidate("debug")

func clear_modifiers() -> void:
	fast=false
	god=false
	instant_search=false
	if app.items()!=null: app.items().cancel_search()

func session_started() -> void:
	_death_view={}
	bookmarks.clear()
	_bookmark_sequence=0
	_bookmark_generation+=1
	telemetry.reset()
	_session_sequence+=1
	trace.add("fact","游戏会话开始／载入",{},_context())
	if app.speedrun.active(): clear_modifiers()
	if fast or god or instant_search or (is_instance_valid(app.debug_panel) and app.debug_panel.visible): dirty()
	refresh()

func set_frozen(value: bool) -> void:
	frozen=value
	app.player.debug_frozen=value or is_instance_valid(preview)
	app.player.clear_input()
	app.ui.clear_touch()

func cancel() -> void:
	clear_preview()
	set_frozen(false)
	collision_view=false
	_inspection={}
	if is_instance_valid(probe): probe.clear()

func before_death() -> void:
	cancel()
	_death_view=app.player.capture_pose().duplicate(true)

func clear_preview() -> void:
	if is_instance_valid(preview): app.audio.stop_preview()
	if is_instance_valid(preview):
		preview.finish()
		preview.queue_free()
	preview=null
	if is_instance_valid(preview_camera):
		preview_camera.current=false
		preview_camera.queue_free()
		app.player.camera.make_current()
		app.ui.cut_flash(0)
	preview_camera=null
	preview_paused=false
	app.player.debug_frozen=frozen

func preview_death(cause: String) -> String:
	if not alive(): return report("请先开始游戏或复活。")
	if app.anomaly().is_active(): return report("请先结束当前异象，再预览。")
	if not DeathCG.has(cause): return report("没有该死亡演出。")
	clear_preview()
	if is_instance_valid(probe): probe.clear()
	_inspection={}
	# CameraMotion and input keep their own camera and pose; the preview is disposable.
	var source:=app.player.camera
	preview_camera=Camera3D.new()
	preview_camera.name="DebugPreviewCamera"
	app.player.add_child(preview_camera)
	preview_camera.transform=source.transform
	preview_camera.fov=source.fov
	preview_camera.near=source.near
	preview_camera.far=source.far
	preview_camera.keep_aspect=source.keep_aspect
	preview_camera.cull_mask=source.cull_mask
	preview_camera.environment=source.environment
	preview_camera.attributes=source.attributes
	preview_camera.make_current()
	preview=DeathCG.new()
	preview.sound_output=app.audio.preview_play
	app.audio.preview_play("death.base")
	app.audio.preview_play("death."+cause if app.audio.has("death."+cause) else "death.generic")
	add_child(preview)
	preview.begin(cause,app.player,app._campus_world(),app.ui,DeathCG.duration(cause,StoryModule.duration(cause)),app.settings.get_int("reduce_flash")==1,preview_camera)
	app.player.debug_frozen=true
	app.player.clear_input()
	app.ui.clear_touch()
	return report("预览 %s；暂停游戏逻辑，可拖动进度检查画面。" % DeathCG.title(cause))

func _process(dt: float) -> void:
	if is_instance_valid(preview):
		if not alive(): clear_preview()
		else:
			preview._base_pitch=app.player.camera.rotation.x
			preview._base_y=app.player.camera.position.y
			if not preview_paused: preview.tick(dt*preview_rate)
			if not preview.on: clear_preview()
	if is_instance_valid(app.debug_panel) and app.debug_panel.visible:
		var now:=Time.get_ticks_usec()
		if _last_frame_us>0: telemetry.sample((now-_last_frame_us)/1000000.0)
		_last_frame_us=now
	else:
		_last_frame_us=0
	_refresh+=dt
	if _refresh>=.2:
		_refresh=0
		_update_probe()
		refresh()

func snapshot() -> Dictionary:
	var state:={"playing":alive(),"dead":app.session!=null and app.story().dead,"freeze":frozen,"fast":fast,"god":god,"search":instant_search,
		"renderer":RenderingServer.get_current_rendering_method(),"rendering_driver":RenderingServer.get_current_rendering_driver_name(),
		"quality":app.settings.get_int("quality"),"quality_label":GameSettings.QUALITY_LABELS[app.settings.get_int("quality")],
		"model_detail":CampusData.tier,"lighting_detail":app.settings.get_int("lighting_detail"),
		"fps_limit":app.settings.get_int("fps_limit"),"vsync":app.settings.get_int("vsync"),
		"fps":Engine.get_frames_per_second(),"history":history.duplicate(),
		"metrics":telemetry.capture(DisplayServer.get_name()!="headless"),"trace":trace.capture(),
		"collision_view":collision_view,"collision_count":probe.shown if is_instance_valid(probe) else 0,
		"collision_nearby":probe.nearby if is_instance_valid(probe) else 0,"inspect":_inspection.duplicate(true),
		"bookmarks":bookmarks.duplicate(true),"preview":preview_state()}
	if app.session!=null:
		var school:=app.school()
		state.merge({"room":app.session.world_id,"day":school.day,"time":SchoolClock.fmt_clock(school.tsec),"minutes":school.tsec,"san":school.san,"stam":school.stam,"cap":school.stamina_max(),"viol":school.viol,"tt":school.tt,
			"pose":app.player.capture_pose(),"bag":app.items().bag.duplicate(),"hot":app.items().hot.duplicate(),"anomaly":app.anomaly().active_id(),"inspection":school.inspection_active(),"queued":school.inspection["queue"].size(),"patrol":app.patrol().pat["behavior"],"trusted":app.runscore().trusted})
	return state

func refresh() -> void:
	if is_instance_valid(app.debug_panel) and app.debug_panel.visible:
		app.debug_panel.set_runtime(snapshot())

func _close_choice() -> void:
	var had_choice:=app.ui.choice_open()
	app._choice_handler=Callable()
	app._choice_count+=1
	app._choice_left=0
	app.ui.hide_choice()
	if had_choice and alive() and not app.get_tree().paused and not app.phone_open() and not app.ui.terminal_open() and not app.driving(): app.player.enabled=true

func end_anomaly() -> void:
	_close_choice()
	var a:=app.anomaly()
	a.set_context(app._anomaly_context(app.campus().room(app.session.world_id),app.player.capture_pose()))
	# Cola can resume an interrupted anomaly; debug cancellation must end both.
	for _i in 3:
		if not a.is_active(): break
		a.end_now()
	app._anomaly_step(0,app.school(),app.campus().room(app.session.world_id),app.player.capture_pose())
	var world:=app._campus_world()
	if world.phantoms!=null: world.phantoms.clear_smile()
	sync_anomaly()

func sync_anomaly() -> void:
	var cam:=app.player.camera
	var forward:=-cam.global_basis.z
	app._campus_world().anomaly_fx.update(0,app.anomaly().an,app.campus().room(app.session.world_id),app.session.world_id,app.player.position,Vector2(forward.x,forward.z),cam.global_position,app.story().diff=="hard")

func prepare_teleport() -> void:
	clear_preview()
	app.school().cancel_inspection()
	app.school().inspection["queue"]=[]
	app.elevator().cancel()
	app.garage().cancel_chase()
	app._leave_drive()
	app._close_phone()
	app._stop_snake(true)
	app.ui.hide_terminal()
	app.ui.hide_bag()
	end_anomaly()
	app.items().cancel_search()
	app.patrol().hide_out()
	app.player.hiding=false
	app.ui.show_hiding(false)
	app.school().seated=false
	app.player.seated=false
	app.player.clear_input()
	app.ui.clear_touch()
	app.ui.show_search(0)
	app.ui.set_lift_close(false)
	app.player.enabled=not app.get_tree().paused
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE

func _prune_inspections() -> void:
	var school:=app.school()
	school.inspection["queue"]=school.inspection["queue"].filter(func(item: Dictionary) -> bool: return not school._stale(item))

func change_time(minutes: float) -> String:
	if not is_finite(minutes) or absf(minutes)>1440*30: return report("时间调整超出范围。")
	_prune_inspections()
	if not app.elevator().ride.is_empty() or app.driving() or app.school().inspection_pending(): return report("请先结束电梯、驾驶或学生会检查。")
	dirty()
	if minutes>=0: app.school().advance_game_time(minutes)
	else: app.school().rewind_game_time(-minutes)
	_prune_inspections()
	return report("时间已调整至第 %d 天 %s" % [app.school().day,SchoolClock.fmt_clock(app.school().tsec)])

func _stage_allowed() -> bool:
	return not app.ui.choice_open() and not app.phone_open() and not app.ui.terminal_open() and app.elevator().ride.is_empty() and not app.driving() and not app.anomaly().is_active() and not app.school().inspection_pending() and not app.patrol().local_chase()

func command(id: String, args: Dictionary = {}) -> String:
	var result:=_command(id,args)
	if DebugPanel.enabled() and id not in ["preview_seek","copy","trace_copy","trace_clear","trace_toggle","copy_position"]:
		trace.add("command",id,{"args":args,"result":result},_context())
	refresh()
	return result

func _command(id: String, args: Dictionary = {}) -> String:
	if not DebugPanel.enabled(): return "开发工具未启用。"
	if id=="copy":
		DisplayServer.clipboard_set(JSON.stringify(snapshot(),"  "))
		return report("诊断信息已复制。")
	if id=="trace_toggle":
		trace.recording=not trace.recording
		return report("事件记录已继续。" if trace.recording else "事件记录已暂停。")
	if id=="trace_clear":
		trace.clear()
		return report("事件列表已清空。")
	if id=="trace_copy":
		DisplayServer.clipboard_set(JSON.stringify(trace.capture(),"  "))
		return report("事件记录已复制。")
	if id=="metrics_reset":
		telemetry.reset()
		return report("性能采样已重置。")
	if id=="export_report": return export_report()
	if id=="copy_position":
		if app.session==null: return report("没有可复制的位置。")
		DisplayServer.clipboard_set(JSON.stringify({"room":app.session.world_id,"pose":app.player.capture_pose()},"  "))
		return report("场景、位置与朝向已复制。")
	if id=="bookmark_clear":
		bookmarks.clear()
		return report("本局临时位置书签已清空。")
	if id.begins_with("preview_"):
		if not is_instance_valid(preview): return report("请先开始死亡演出预览。")
		match id:
			"preview_pause":
				preview_paused=not preview_paused
				if not preview_paused and preview.k>=preview.dur: _seek_preview(0)
				return report("预览已暂停。" if preview_paused else "预览已继续。")
			"preview_seek":
				var value:=float(args.get("fraction",-1))
				if not is_finite(value) or value<0 or value>1: return report("预览进度需要在 0–100% 内。")
				preview_paused=true
				_seek_preview(value)
				return "预览停在 %.2f 秒" % preview.k
			"preview_rate":
				var value:=float(args.get("rate",0))
				if value not in [.25,.5,1.0,2.0]: return report("请选择 0.25、0.5、1 或 2 倍速。")
				preview_rate=value
				return report("预览速度 ×%.2f" % value)
			"preview_restart": return preview_death(preview.fx)
	if id=="clear_preview":
		clear_preview()
		return report("预览已清理。")
	if id in ["fast","god","search"]:
		dirty()
		match id:
			"fast": fast=not fast
			"god": god=not god
			"search":
				instant_search=not instant_search
				if app.items()!=null: app.items().cancel_search()
		return report("调试开关已更新。")
	if id=="revive": return revive()
	if not alive(): return report("请先开始游戏或复活；过场中不能修改。")
	match id:
		"collisions":
			collision_view=not collision_view
			_update_probe()
			return report("碰撞透视线框已开启；最多显示附近 %d 个实际碰撞体。" % DebugWorldProbe.MAX_SHAPES if collision_view else "碰撞线框已关闭。")
		"bookmark_add": return add_bookmark(String(args.get("name","")))
		"bookmark_go": return goto_bookmark(String(args.get("id","")))
		"step": return step_simulation(float(args.get("seconds",0)))
		"preview": return preview_death(String(args.get("id","")))
		"freeze":
			if not _stage_allowed(): return report("请先退出当前互动、异象或检查。")
			dirty()
			set_frozen(not frozen)
			return report("模拟已冻结；可用此按钮继续。" if frozen else "模拟已继续。")
		"stat":
			var key:=String(args.get("key",""))
			var raw:=String(args.get("value","")).strip_edges()
			if key not in ["san","stam","viol","tt"] or not raw.is_valid_float() or not is_finite(raw.to_float()) or raw.to_float()<0 or raw.to_float()>100: return report("请输入 0–100 的有效数值。")
			dirty()
			app.school().set(key,raw.to_float())
			app.school().stam=minf(app.school().stam,app.school().stamina_max())
			return report("%s 已设为 %.1f" % [key,app.school().get(key)])
		"heal":
			dirty()
			app.school().san=100
			app.school().stam=100
			app.school().tired=false
			return report("SAN / 体力已恢复。")
		"time": return change_time(float(args.get("minutes",0)))
		"clock":
			var parts:=String(args.get("value","")).split(":")
			if parts.size()!=2 or not parts[0].is_valid_int() or not parts[1].is_valid_int(): return report("请输入 HH:MM。")
			var h:=int(parts[0]); var m:=int(parts[1])
			if h<0 or h>23 or m<0 or m>59 or (h*60+m>=60 and h*60+m<440): return report("可设 07:20–次日 00:59。")
			return change_time(float(h*60+m+(1440 if h==0 else 0))-app.school().tsec)
		"item_add","item_remove","hot1","hot2":
			var key:=String(args.get("id",""))
			if not app.items()._items().has(key): return report("请选择有效物品。")
			if id=="item_add" and (app.items().has(key) or app.items().bag.size()>=app.items().capacity()): return report("已持有，或背包已满。")
			if id!="item_add" and not app.items().has(key): return report("背包中没有该物品。")
			dirty()
			match id:
				"item_add": app._add_item(key)
				"item_remove": app.items().remove(key)
				_: app.items().set_hot(0 if id=="hot1" else 1,key)
			return report("背包已更新。")
		"teleport":
			var room:=String(args.get("id",""))
			if not app.campus().knows(room) or room=="out": return report("请选择有效室内场景。")
			dirty()
			prepare_teleport()
			var why:=app.travel(room,app.campus().default_spawn(room),false)
			return report("传送至 "+room if why=="" else why)
		"outdoor":
			var i:=int(args.get("id",-1))
			if i<0 or i>=POI.size(): return report("请选择室外地点。")
			dirty()
			prepare_teleport()
			var p:=CampusGeometry.to_scene(null,Vector2(POI[i][1],POI[i][2])*2.0)
			var why:=app.travel("out",{"position":[p.x,0,p.y],"yaw":CampusGeometry.yaw_from_ang(PI/2),"pitch":0},false)
			return report("传送至 "+POI[i][0] if why=="" else why)
		"anomaly":
			var key:=String(args.get("id",""))
			if not AnomalyModule.DEFS.has(key): return report("请选择有效异象。")
			app.anomaly().set_context(app._anomaly_context(app.campus().room(app.session.world_id),app.player.capture_pose()))
			if key=="cup" and (app.session.world_id!="out" or app.anomaly()._cup_wall().is_empty()): return report("水杯需要室外建筑墙边的落点。")
			if key=="twin" and app.campus().room(app.session.world_id)==null: return report("分身需要室内／天台地图。")
			dirty()
			clear_preview()
			end_anomaly()
			var a:=app.anomaly()
			a.an.merge({"id":key,"t":0.0,"acc":0.0,"active":true,"data":{"scene":app.session.world_id},"sub":0,"lastBig":not AnomalyModule.DEFS[key].get("small",false)},true)
			a._on(key)
			app._anomaly_step(0,app.school(),app.campus().room(app.session.world_id),app.player.capture_pose())
			sync_anomaly()
			return report("异象已触发："+key)
		"anomaly_end":
			dirty()
			end_anomaly()
			return report("当前异象已结束。")
		"fake_normal":
			dirty()
			var state: Dictionary=app.fake_normal().fn
			state["on"]=not bool(state["on"])
			state["v"]=0
			if state["on"]: state.merge({"n":0,"next":3.0,"used":{},"shown":false,"left":int(state.get("left",4)) if int(state.get("left",4))>0 else 4},true)
			else: app._fake_people_clear()
			app._fake_people_step(app.fake_normal(),app.campus().room(app.session.world_id))
			return report("假正常："+("开" if state["on"] else "关"))
		"patrol_start":
			if not _stage_allowed(): return report("请先结束当前互动、异象、检查或追逐。")
			dirty()
			app.patrol().reset()
			return report("巡察者已重置到行政楼一楼。")
		"patrol_end":
			dirty()
			app.patrol().clear_chase()
			return report("普通追逐已解除；常驻实体与永久追踪仍保留。")
		"inspection":
			if not _stage_allowed(): return report("请先结束当前互动、异象、检查或追逐。")
			dirty()
			var room: Variant=app.campus().room(app.session.world_id)
			var p:=app.player.position
			var w:=CampusGeometry.to_world(room,p.x,p.z)
			app.school().start_inspection({"day":app.school().day,"slot":0 if app.school().tsec<920 else 1},app.session.world_id,w,app._can_stand.bind(room,p.y))
			app._campus_world().show_silhouettes(app.school().inspection_points(),room,p.y)
			return report("检查已开始，按站位、移动与注视结算。")
		"inspection_end":
			dirty()
			app.school().cancel_inspection()
			app.school().inspection["queue"]=[]
			app._campus_world().show_silhouettes([],app.campus().room(app.session.world_id),app.player.position.y)
			return report("当前及排队检查已取消；已扣数值保留。")
		"death":
			var cause:=String(args.get("id",""))
			if not DeathCG.has(cause): return report("请选择有效死因。")
			dirty()
			clear_preview()
			var old_god:=god
			god=false
			app.kill("【Dev】测试死亡："+cause,cause,"debug")
			god=old_god
			return report("已触发实际死亡结算。")
	return report("未知调试命令："+id)

func revive() -> String:
	if app.session==null or not app.story().dead: return report("角色尚未死亡。")
	dirty()
	cancel()
	app._stop_death_cg()
	app.story().dead=false
	app.story().wake_pending=false
	app.story().death_fx=""
	app.story().death_t=0
	app._death_hold=0
	app._death_wait=0
	app._death_phase=""
	if not _death_view.is_empty(): app.player.restore_pose(_death_view)
	app.player.reset_view(app.body().eye_drop())
	app._reset_sensory()
	app.ui.hide_death()
	app.ui.cut_flash(0)
	if app.school().san<=0: app.school().san=45
	if app.school().tt>=100:
		app.school().tt=86
		app.school().tt_tier=4
	app.school().stam=minf(app.school().stam,app.school().stamina_max())
	app.player.enabled=not app.get_tree().paused
	return report("已复活；本局仍为调试局，不恢复已删除的存档。")

func preview_state() -> Dictionary:
	if not is_instance_valid(preview): return {"active":false,"paused":false,"rate":preview_rate,"time":0.0,"duration":0.0}
	return {"active":true,"id":preview.fx,"title":DeathCG.title(preview.fx),"paused":preview_paused,"rate":preview_rate,"time":preview.k,"duration":preview.dur}

func _seek_preview(fraction: float) -> void:
	app.audio.stop_preview()
	preview.k=preview.dur*fraction
	preview._cued.clear()
	preview._flashed.clear()
	app.ui.cut_flash(0)
	var output:=preview.sound_output
	preview.sound_output=Callable()
	preview.update(preview.k)
	preview.sound_output=output

func _update_probe() -> void:
	if not is_instance_valid(probe): return
	var visible_panel:=is_instance_valid(app.debug_panel) and app.debug_panel.visible
	if not alive() or is_instance_valid(preview) or not visible_panel:
		probe.clear()
		_inspection={}
		return
	if not collision_view and app.debug_panel._active_page!="诊断":
		probe.clear()
		_inspection={}
		return
	probe.bind_world(app._campus_world())
	probe.draw_near(app.player.camera.global_position,collision_view)
	_inspection=probe.inspect(app.player.camera,app.player)
	var room: Variant=app.campus().room(app.session.world_id)
	var w:=CampusGeometry.to_world(room,app.player.position.x,app.player.position.z)
	_inspection["world_units"]=[snappedf(w.x,.01),snappedf(w.y,.01)]
	_inspection["interaction"]=(app.ui.get_node("%Prompt") as Label).text
	_inspection["physical_interaction"]=app.player._prompt
	_inspection["posture"]="坐着" if app.player.seated else ("躲藏" if app.player.hiding else "站立")
	if room is Dictionary and room.has("grid"):
		_inspection["tile"]=[floori((w.x-float(room.ox))/float(room.tw)),floori((w.y-float(room.oy))/float(room.th))]
		_inspection["cell"]=CampusGeometry.tile_at(room,w)

func step_simulation(seconds: float) -> String:
	if not frozen: return report("请先冻结模拟，再进行逻辑步进。")
	if not is_finite(seconds) or seconds<=0 or seconds>1: return report("逻辑步进范围为 0–1 秒。")
	if is_instance_valid(preview) or app.get_tree().paused or app.ui.choice_open() or app.driving() or not app.elevator().ride.is_empty(): return report("请先退出演出、菜单、选择、驾驶或电梯。")
	dirty()
	var session:=app.session
	var remaining:=seconds
	var elapsed:=0.0
	_stepping=true
	while remaining>.000001 and app.session==session and alive() and frozen:
		var delta:=minf(remaining,1.0/60.0)
		app._physics_process(delta)
		elapsed+=delta
		remaining-=delta
		if app.ui.choice_open(): break
	_stepping=false
	return report("逻辑已步进 %.3f 秒；角色物理移动保持冻结。" % elapsed)

func add_bookmark(title: String) -> String:
	if not _stage_allowed() or app.player.seated or app.player.hiding: return report("请先站起并退出当前互动，再记录位置。")
	if bookmarks.size()>=8: return report("本局最多保留 8 个位置书签，请先清空。")
	_bookmark_sequence+=1
	var label:=title.strip_edges().substr(0,32)
	if label=="": label="%s · %s" % [app.session.world_id,SchoolClock.fmt_clock(app.school().tsec)]
	bookmarks.append({"id":str(_bookmark_sequence),"name":label,"room":app.session.world_id,"pose":app.player.capture_pose().duplicate(true)})
	return report("已记录位置："+label)

func goto_bookmark(id: String) -> String:
	var target: Dictionary={}
	for bookmark: Dictionary in bookmarks:
		if bookmark.id==id: target=bookmark.duplicate(true); break
	if target.is_empty(): return report("请选择本局有效的位置书签。")
	if not _stage_allowed(): return report("请先退出当前互动、追逐或检查。")
	dirty()
	prepare_teleport()
	var error:=app.travel(target.room,target.pose,false)
	if error!="": return report(error)
	_bookmark_generation+=1
	get_tree().physics_frame.connect(_check_bookmark_landing.bind(_bookmark_generation,app.session,weakref(app._campus_world()),target),CONNECT_ONE_SHOT)
	return report("已前往书签，正在核对落点："+String(target.name))

func _check_bookmark_landing(generation: int, session: GameSession, world_ref: WeakRef, target: Dictionary) -> void:
	var world:=world_ref.get_ref() as Node3D
	if generation!=_bookmark_generation or app.session!=session or not alive() or not is_instance_valid(world) or app._campus_world()!=world or app.session.world_id!=target.room: return
	var shape:=CapsuleShape3D.new()
	shape.radius=CampusGeometry.PRAD*CampusGeometry.U2M-.02
	shape.height=1.74
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=shape
	query.transform=Transform3D(Basis(),app.player.global_position+Vector3.UP*.9)
	query.collision_mask=3
	query.exclude=[app.player.get_rid()]
	if world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():
		report("已恢复书签位置与朝向："+String(target.name))
	else:
		app.travel(target.room,app.campus().default_spawn(target.room),false)
		report("书签落点已被障碍占用，已回到该场景的默认落点。")

func export_report() -> String:
	var path:=app.saves.side_path("debug-report.json")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var diagnostics:=snapshot()
	diagnostics.erase("trace")
	var report_data:={"version":1,"engine":Engine.get_version_info().string,"captured_at":Time.get_datetime_string_from_system(true),"diagnostics":diagnostics,"events":trace.capture(),"playtest":app.playtest.export()}
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null: return report("报告写入失败："+error_string(FileAccess.get_open_error()))
	file.store_string(JSON.stringify(report_data,"  "))
	file.close()
	return report("诊断报告已保存到："+ProjectSettings.globalize_path(path))

func location_changing() -> void:
	_bookmark_generation+=1
	clear_preview()
	_inspection={}
	if is_instance_valid(probe): probe.clear()
