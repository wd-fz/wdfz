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
	if app.speedrun.active(): clear_modifiers()
	if fast or god or instant_search or (is_instance_valid(app.debug_panel) and app.debug_panel.visible): dirty()
	refresh()

func set_frozen(value: bool) -> void:
	frozen=value
	app.player.debug_frozen=value
	app.player.clear_input()
	app.ui.clear_touch()

func cancel() -> void:
	clear_preview()
	set_frozen(false)

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

func preview_death(cause: String) -> String:
	if not alive(): return report("请先开始游戏或复活。")
	if app.anomaly().is_active(): return report("请先结束当前异象，再预览。")
	if not DeathCG.has(cause): return report("没有该死亡演出。")
	clear_preview()
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
	preview.begin(cause,app.player,app._campus_world(),app.ui,maxf(3.5,DeathCG.duration(cause,StoryModule.duration(cause))+.2),app.settings.get_int("reduce_flash")==1,preview_camera)
	return report("预览 %s；结束后自动清理，不触发死亡结算。" % cause)

func _process(dt: float) -> void:
	if is_instance_valid(preview):
		if not alive(): clear_preview()
		else:
			preview._base_pitch=app.player.camera.rotation.x
			preview._base_y=app.player.camera.position.y
			preview.tick(dt)
			if not preview.on: clear_preview()
	_refresh+=dt
	if _refresh>=.2:
		_refresh=0
		refresh()

func snapshot() -> Dictionary:
	var state:={"playing":alive(),"dead":app.session!=null and app.story().dead,"freeze":frozen,"fast":fast,"god":god,"search":instant_search,
		"renderer":RenderingServer.get_current_rendering_method(),"quality":CampusData.tier,"fps":Engine.get_frames_per_second(),"history":history.duplicate()}
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
	if not DebugPanel.enabled(): return "开发工具未启用。"
	if id=="copy":
		DisplayServer.clipboard_set(JSON.stringify(snapshot(),"  "))
		return report("诊断信息已复制。")
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
