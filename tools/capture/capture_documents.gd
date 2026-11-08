extends SceneTree
## Actual controls with synthetic long text, for layout evidence rather than a played route.
var ui: GameUI
func _initialize() -> void: call_deferred("_run")
func shot(label: String) -> void:
	for _i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/documents/"+label+".png")
func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://build/previews/documents")
	root.size = Vector2i(420,900)
	ui = preload("res://game/presentation/ui/game_ui.tscn").instantiate()
	root.add_child(ui)
	await process_frame
	ui.set_mode("play")
	ui.apply_text_scale(150)
	var suite := preload("res://tests/suites/documents.gd").new(self)
	ui.show_notes(suite.notes())
	await shot("竖屏大字调查笔记")
	ui.notes_panel.hide()
	ui.show_terminal("$ help\nhelp — 列出可用命令\nls — 查看文件\ncat — 阅读文件\nscan — 扫描当前网络\n校园维护终端：请核对设备编号与访问范围。\n".repeat(4),"连接正常 · 留意脚步和灯光。")
	await shot("竖屏大字终端")
	ui.hide_terminal()
	ui.show_import()
	ui.show_import_result("存档中的扩展版本不兼容，原进度仍然保留。")
	await shot("竖屏大字旧档导入")
	ui._import_panel.hide()
	var mic := MicPanel.new()
	ui.get_node("Root").add_child(mic)
	mic.show()
	mic.paint([["notice1","第一段通知稿 · 第二天，第八节下课以后"]],"notice1",BroadcastModule.PAGES[0],"广播已接通。完成这段后切换下一张通知稿。",4,20,false,true)
	await shot("竖屏大字广播话筒")
	root.size = Vector2i(960,540)
	mic.paint([["notice1","第一段通知稿 · 第二天，第八节下课以后"]],"notice1",BroadcastModule.PAGES[0].repeat(10),"广播已接通。完成这段后切换下一张通知稿。",4,20,false,true)
	await shot("横屏大字长稿与按钮")
	ui.queue_free()
	await process_frame
	quit()
