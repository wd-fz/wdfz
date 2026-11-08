class_name ArchiveFlow
extends Node
## Menu/profile boundary. Replay is allowed only after the live run has left the tree.
const KNOCK := {"id":"x.rules.knock","fx":"rules_knock","n":"门外有你的名字","d":"熄灯后门外敲了三下，有人问「在吗？查寝。」我应了一声。","stage":"dorm1","no":1}
var app: GameApp
var rules: ArchiveRules
var store: ArchiveStore
var stage: ArchiveStage
var section := "死亡"
var _last_id := ""
var _grade_open := false

func setup(owner_app: GameApp) -> void:
	app = owner_app
	rules = ArchiveRules.new(CampusData.archive())
	store = ArchiveStore.new(app.saves.side_path("archive.json"))
	store.read(rules,app._read_death_log())

func active() -> bool: return _grade_open or (is_instance_valid(stage) and stage.on)

func _ends() -> Dictionary:
	var raw: Variant = app._read_side("ends.json")
	return raw if raw is Dictionary else {}

func _opening() -> bool: return FileAccess.file_exists(app.saves.side_path("opening_seen"))

func _records() -> Dictionary:
	var dlc := RulesDlcModule.new(CampusData.rules_dlc(),CampusData.rooms())
	var raw: Variant = app._read_side("rules_records.json")
	dlc.load_records(raw if raw is Dictionary else {})
	return dlc.records

func record(source: String, fx: String) -> void:
	var debug := is_instance_valid(app.debug_panel) and app.debug_panel.visible
	rules.record(source,fx,debug,active(),"debug" if source == "debug" else null,int(Time.get_unix_time_from_system()*1000))
	store.write(rules)

func mark_seen(id: String) -> void:
	if rules.mark_seen(id,active()): store.write(rules)

func open(tab: String = "") -> void:
	if active(): return
	if tab != "": section = tab
	var rows := []
	var known := 0
	var public := 0
	var hidden := 0
	if section in ["死亡","演出"]:
		var ends := _ends()
		var opening := _opening()
		for entry: Dictionary in rules.visible("deaths" if section == "死亡" else "cuts",ends,opening):
			var real := rules.real(entry,ends,opening)
			var unlocked := rules.is_open(entry,ends,opening)
			if entry.get("secret",false): hidden += 1
			else:
				public += 1
				if unlocked: known += 1
			var meta := "直接解锁 · 没有亲历"
			if real:
				meta = ("已达成" if entry.has("end") else "已看过") if entry.has("cut") else ("旧版本记录" if rules.state["legacy"].has(entry["id"]) else "经历 %d 次" % int(rules.state["count"].get(entry["id"],1)))
			rows.append({"id":entry["id"],"text":"%02d · %s" % [entry["no"],entry["n"] if unlocked else "尚未记录"],"on":unlocked,
				"memo":String(entry["d"])+"\n"+meta,"action":play.bind(String(entry["id"])) if unlocked else Callable(),"label":"重看"})
	elif section == "结算":
		var grades := app.runs().grades()
		public = ScoreRules.GRADES.size()
		for grade: Dictionary in ScoreRules.GRADES:
			var id := "x.grade."+String(grade["g"])
			var earned: Dictionary = grades.get(grade["g"],{})
			var unlocked: bool = not earned.is_empty() or rules.state["granted"].has(id)
			known += 1 if unlocked else 0
			var meta := "直接解锁 · 没有亲历" if earned.is_empty() else "取得 %d 次" % earned["count"]
			rows.append({"id":id,"text":String(grade["g"])+" · "+String(grade["name"]) if unlocked else "尚未取得","on":unlocked,
				"memo":"「"+String(grade["memo"])+"」\n"+meta,"action":play.bind(id) if unlocked else Callable(),"label":"重看"})
	else:
		var records := _records()
		var dlc := RulesDlcModule.new(CampusData.rules_dlc(),CampusData.rooms())
		public = 8
		var unlocked: bool = records.has("rules.h.reply") or rules.state["granted"].has(KNOCK["id"])
		known += 1 if unlocked else 0
		rows.append({"id":KNOCK["id"],"text":KNOCK["n"] if unlocked else "封存的死亡档案","on":unlocked,"memo":KNOCK["d"],"action":play.bind(KNOCK["id"]) if unlocked else Callable(),"label":"重看"})
		for entry: Dictionary in dlc.content["achievements"]:
			var id := "x.rules."+String(entry["id"]).trim_prefix("rules.")
			unlocked = records.has(entry["id"]) or rules.state["granted"].has(id)
			known += 1 if unlocked else 0
			var record: Dictionary = records.get(entry["id"],{})
			var meta := "直接解锁 · 没有亲历" if record.is_empty() else "规则 v%s%s · 只记录，不给加成" % [record.get("ver","1.0.0")," · 规则组 "+String(record["bundle"]) if record.has("bundle") else ""]
			rows.append({"id":id,"text":("？？？" if entry.get("hidden",false) and not unlocked else String(entry["name"]))+" · "+String(entry["tier"]),"on":unlocked,"memo":meta})
	var title := "CG 档案馆 · %s  %d / %d%s" % [section,known,public," · 隐藏 %d" % hidden if hidden else ""]
	if int(rules.state["pending"]) > 0: rows.append({"text":"另有 %d 条旧死亡记录来源不明，未解锁档案。" % rules.state["pending"],"on":true,"memo":""})
	var tabs := []
	for label: String in ["死亡","演出","规则怪谈","结算"]: tabs.append({"text":label,"action":open.bind(label),"on":label == section})
	app.ui.show_list(title,rows)
	app.ui.list_tabs(tabs)
	if DebugPanel.enabled(): app.ui.list_footer("调试：解锁全部 CG",unlock_all)
	app.ui.focus_list_entry(_last_id)

func unlock_all() -> void:
	if not DebugPanel.enabled(): return
	var ids := rules.locked(_ends(),_opening())
	ids.append(KNOCK["id"])
	for entry: Dictionary in CampusData.rules_dlc()["achievements"]: ids.append("x.rules."+String(entry["id"]).trim_prefix("rules."))
	for grade: Dictionary in ScoreRules.GRADES: ids.append("x.grade."+String(grade["g"]))
	rules.grant(ids)
	store.write(rules)
	open()

func play(id: String) -> bool:
	if active() or app.session != null or not app.ui.menu.visible: return false
	if id.begins_with("x.grade."): return _play_grade(id)
	var entry: Dictionary = rules.entries.get(id,{})
	if id == KNOCK["id"]:
		if not _records().has("rules.h.reply") and not rules.state["granted"].has(id): return false
		entry = KNOCK
	elif entry.is_empty() or not rules.is_open(entry,_ends(),_opening()): return false
	_last_id = id
	app.audio.stop_all()
	stage = ArchiveStage.new()
	add_child(stage)
	stage.finished.connect(stop.bind(true))
	var error := stage.begin(entry,app.router.worlds,app.ui,app.settings,app.audio.muted)
	if error != "":
		stop(true)
		app.ui.show_notice("档案读取失败："+error)
		return false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	return true

func stop(reopen: bool = false) -> void:
	if not is_instance_valid(stage) and not _grade_open: return
	if _grade_open:
		_grade_open = false
		app.ui.hide_results()
	if is_instance_valid(stage):
		stage.cancel()
		stage.queue_free()
		stage = null
	app.player.camera.make_current()
	app.ui.set_mode("menu")
	if reopen: open()

func _play_grade(id: String) -> bool:
	var letter := id.trim_prefix("x.grade.")
	if ScoreRules.grade_index(letter) < 0: return false
	var earned: Dictionary = app.runs().grades().get(letter,{})
	if earned.is_empty() and not rules.state["granted"].has(id): return false
	var meta := app.runs().get_record(String(earned["best"])) if earned.get("best") is String else {}
	if meta.is_empty():
		meta = ScoreRules.sample_meta(letter,"car")
		meta["routeName"] = String(RoutesModule.ENDINGS["car"]["t"]).replace(" ","")
		meta["source"] = "archive"
	_last_id = id
	_grade_open = true
	app.ui.ach_panel.hide()
	app.ui.show_results(meta,{"back_label":"返回档案馆","reduce":app.settings.get_int("reduce_flash") != 0})
	app._wire_results(stop.bind(true))
	return true
