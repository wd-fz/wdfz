class_name GameSettings
extends RefCounted
## Player settings, ported from the Web version (reference wd-fz.github.io@0bf508a, settings.js and
## quality.js). Presentation and comfort only: no setting changes the rules, the collision or the
## timetable. Saved on its own (user://settings.json), never inside a run's save.
##
## vol 0–100 (default 70) · amb 1/0 ambient layers · captions 0 auto / 1 on / 2 off (default on) ·
## sub 0/1/2 caption size · distortion 0 off / 1 reduced / 2 full · reduce_flash 1/0 · bright 50–150 ·
## grain 1/0 · mouse, touch 25–250 look sensitivity % · text 85–150 % · touch_size 85–125 % ·
## quality 0–4 (流畅、均衡、精细、超精细、真实) · auto_land 1/0 · full_screen 1/0.
## The Web "graphics mode" (WebGL / WebGPU) is replaced by Godot's renderer. Touch layout is
## stored separately from numeric settings and from gameplay saves.

const VERSION := 1
const DEFAULTS := {"vol": 70, "amb": 1, "captions": 1, "sub": 1, "distortion": 2, "reduce_flash": 0, "bright": 100, "grain": 1,
	"mouse": 100, "touch": 100, "text": 100, "touch_size": 100, "quality": 2, "auto_land": 1, "full_screen": 0, "shake": 1}
const LIMITS := {"vol": [0, 100], "bright": [50, 150], "mouse": [25, 250], "touch": [25, 250], "text": [85, 150], "touch_size": [85, 125]}
const CHOICES := {"amb": 2, "captions": 3, "sub": 3, "distortion": 3, "reduce_flash": 2, "grain": 2, "quality": 5, "auto_land": 2, "full_screen": 2, "shake": 2}
const QUALITY_LABELS := ["流畅", "均衡", "精细", "超精细", "真实"]
## Rendering scale, MSAA (Viewport enum: 0 off, 2 = 4x, 3 = 8x) and sun shadows per quality (quality.js: scale, samples,
## shadow). As in the reference, 精细 and above cast sun shadows.
const QUALITY_SCALE := [0.55, 0.7, 1.0, 1.0, 1.0]
const QUALITY_MSAA := [0, 0, 0, 2, 3]
## Default 精细 (2): the imported models are the old tier-2 build, so this keeps the picture as it was.
const QUALITY_SHADOW := [false, false, true, true, true]
const SUB_MULT := [0.6, 1.0, 1.6]

var path: String
var values: Dictionary = DEFAULTS.duplicate()
var touch_layout: Dictionary = {}
var wuda_armed := false  # local menu unlock, not a visible setting or a chosen talent


func _init(file: String = "user://settings.json") -> void:
	path = file


## Clamp or default every entry; unknown keys are dropped.
static func normalize(raw: Dictionary) -> Dictionary:
	var out := DEFAULTS.duplicate()
	for k: String in DEFAULTS:
		if not raw.has(k) or not (raw[k] is int or raw[k] is float):
			continue
		var v := int(round(float(raw[k])))
		if LIMITS.has(k):
			out[k] = clampi(v, int(LIMITS[k][0]), int(LIMITS[k][1]))
		elif CHOICES.has(k):
			out[k] = v if v >= 0 and v < int(CHOICES[k]) else DEFAULTS[k]
	return out


## First run on a touch device: performance first (quality 流畅), as the Web version did.
func load_file(touch_device: bool = false) -> bool:
	touch_layout = {}
	wuda_armed=false
	if not FileAccess.file_exists(path):
		values = DEFAULTS.duplicate()
		if touch_device:
			values["quality"] = 0
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	wuda_armed = parsed is Dictionary and parsed.get("wuda_armed") is bool and parsed["wuda_armed"]
	values = normalize(parsed.get("values", {}) if parsed is Dictionary else {})
	touch_layout = TouchLayout.normalize(parsed.get("touch_layout", {}) if parsed is Dictionary else {})
	return parsed is Dictionary


func save_file() -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": VERSION, "values": values, "touch_layout": touch_layout,"wuda_armed":wuda_armed}))
	file.close()
	return true


func get_int(key: String) -> int:
	return int(values.get(key, DEFAULTS.get(key, 0)))


## Returns the stored (normalized) value.
func set_value(key: String, value: float) -> int:
	if not DEFAULTS.has(key):
		return 0
	var next := normalize({key: value})
	values[key] = next[key]
	return int(values[key])


func reset_comfort() -> void:
	touch_layout = {}
	for k: String in ["mouse", "touch", "text", "touch_size"]:
		values[k] = DEFAULTS[k]
