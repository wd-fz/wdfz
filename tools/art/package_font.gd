extends SceneTree
## Called by subset_campus_font.py with the WOFF2 source and native resource destination.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var font := FontFile.new()
	font.data = FileAccess.get_file_as_bytes(args[0])
	if not font.has_char("巡".unicode_at(0)):
		push_error("The supplied font has no glyph for 巡.")
		quit(1)
		return
	quit(ResourceSaver.save(font, args[1]))
